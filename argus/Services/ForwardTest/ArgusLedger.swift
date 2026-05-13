import Foundation
import SQLite3
import CryptoKit

// MARK: - Argus Ledger (The Scientific Truth)
/// The Single Source of Truth for Argus. Records validation events, trades, and learning outcomes.
/// Uses raw SQLite3 for zero-dependency, offline-first storage.
final class ArgusLedger: Sendable {
    static let shared = ArgusLedger()
    
    private let dbPath: String
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.argus.ledger", qos: .utility)
    
    // MARK: - Integration Context (Runtime Only)
    // Acts as a bridge between DataGateway and AGORA without changing method signatures.
    private var latestSnapshots: [String: [String: String]] = [:] // Symbol -> { Type -> Hash }
    private let contextLock = NSLock()

    // MARK: - Faz IV (2026-05-12): Decision Change Tracking
    // Sembol başına son logged DecisionEvent referansı — yeni `logDecision`
    // çağrısında action veya confidence delta'sı eşik üstüyse otomatik
    // `DecisionChangeEvent` yazılır. SQL truth her zaman events table'da;
    // bu sadece in-memory hızlı erişim cache'i. Cold start'ta ilk read
    // SQL'den lazy load eder.
    //
    // Faz V (2026-05-12): Cache entry'sine `weightSnapshotId` eklendi —
    // konseyin hangi öğrenilmiş ağırlıklarla karar verdiğini izlemek için.
    // DecisionChangeEvent payload'unda from/to snapshotId görünür: weight
    // değişimi ile karar değişimi arasındaki ilişkiyi audit edebiliriz.
    private var lastDecisions: [String: (action: String, confidence: Double, decisionId: UUID, weightSnapshotId: String?)] = [:]
    private let lastDecisionsLock = NSLock()
    /// Confidence delta'sı bu eşik (mutlak) üstüyse aksiyon değişmese bile
    /// DecisionChangeEvent yazılır. Confidence tipik 0-1 ölçeğinde — 0.05 = %5.
    private let decisionConfidenceDeltaThreshold: Double = 0.05
    
    // MARK: - Initialization
    private init() {
        // Store in Application Support or Documents
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        // Clean start for Scientific Era
        let dbUrl = docDir.appendingPathComponent("ArgusScience_V1.sqlite")
        self.dbPath = dbUrl.path
        
        // Lazy init: Do strictly nothing here to prevent Main Thread Hangs.
        // DB will be opened on first write/read on the queue.
    }
    
    private var isDbReady = false
    
    private func ensureConnection() {
        guard !isDbReady else { return }
        openDatabase()
        createSchema()
        isDbReady = true
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("🚨 ArgusLedger: Error opening database at \(dbPath)")
        } else {
            print("💾 ArgusLedger: Database opened at \(dbPath)")
        }
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Schema Management
    private func createSchema() {
        let createBlobs = """
        CREATE TABLE IF NOT EXISTS blobs (
            hash_id TEXT PRIMARY KEY,
            blob_type TEXT NOT NULL,
            compression TEXT NOT NULL,
            payload_bytes BLOB NOT NULL,
            created_at_utc TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            source_meta_json TEXT
        );
        """
        
        let createEvents = """
        CREATE TABLE IF NOT EXISTS events (
            event_id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            event_time_utc TEXT NOT NULL,
            run_id TEXT NOT NULL,
            decision_id TEXT,
            symbol TEXT,
            payload_json TEXT NOT NULL,
            schema_version INTEGER NOT NULL DEFAULT 1,
            app_build TEXT NOT NULL,
            engine_version TEXT,
            
            -- Scientific Validation Columns
            processed INTEGER DEFAULT 0,
            outcome_score REAL,
            horizon_pnl_percent REAL,
            validation_date TEXT,

            -- Faz 1.B Task 1: Veri katmanı (sıcak/ılık/soğuk arşiv)
            -- 'hot' (default) — son 90 gün, tam payload
            -- 'warm' — 90g-1y, raw payload silinmiş, daily aggregate'e yuvarlanmış
            -- 'cold' — 1y+, aylık aggregate satırına yuvarlanmış
            tier TEXT NOT NULL DEFAULT 'hot'
        );
        """

        // ARGUS 3.0: Unified Trade Log (Scientific Schema)
        let createTrades = """
        CREATE TABLE IF NOT EXISTS trades (
            trade_id TEXT PRIMARY KEY,
            symbol TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'OPEN', -- OPEN, CLOSED
            
            -- Entry Context (Experiment Conditions)
            entry_date TEXT NOT NULL, -- Execution Time
            as_of_date TEXT,          -- Data Knowledge Time (No Lookahead)
            entry_price REAL NOT NULL,
            entry_action TEXT NOT NULL, -- BUY, SELL
            entry_reason TEXT,         -- Why we entered (Council action, plan trigger, etc.)
            dominant_signal TEXT,      -- Strongest contributing signal at entry (audit)
            decision_id TEXT,

            -- Experiment Meta
            instrument_type TEXT DEFAULT 'STOCK', -- STOCK, ETF, CRYPTO
            market_region TEXT DEFAULT 'US',      -- US, BIST
            data_version_hash TEXT,               -- Snapshot Hash
            engine_config_hash TEXT,              -- Model/Rule Hash

            -- Exit & Outcome
            exit_date TEXT,
            exit_price REAL,
            exit_reason TEXT,

            -- Scientific Metrics
            pnl_percent REAL,
            max_drawdown REAL,
            holding_period_days REAL,

            -- Learning
            learned_weight_adjustment REAL,
            lesson_blob_id TEXT,

            -- Faz 1.B Task 1: Veri katmanı (events ile aynı anlam)
            tier TEXT NOT NULL DEFAULT 'hot'
        );
        """

        let createLessons = """
        CREATE TABLE IF NOT EXISTS lessons (
            lesson_id TEXT PRIMARY KEY,
            trade_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            lesson_text TEXT NOT NULL,
            deviation_percent REAL,
            weight_changes_json TEXT,
            FOREIGN KEY (trade_id) REFERENCES trades(trade_id)
        );
        """
        
        let createWeightHistory = """
        CREATE TABLE IF NOT EXISTS weight_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            module TEXT NOT NULL,
            old_weight REAL NOT NULL,
            new_weight REAL NOT NULL,
            reason TEXT,
            trade_id TEXT,

            -- Observatory: Extended Learning Tracking
            regime TEXT,           -- Trend, Chop, RiskOff
            window_days INTEGER,   -- 30, 60, 90
            sample_size INTEGER,   -- Kaç karar üzerinden hesaplandı
            trigger_metric TEXT,   -- win_rate, sharpe vb.
            trigger_value REAL     -- Tetikleyici metrik değeri
        );
        """

        // Task 12 (2026-05-12): Outcomes — Ledger üçüncü katman.
        // Decision → Trade → **Outcome** zinciri. Her trade kapanışında insert edilir.
        // FK CASCADE: trade silindiğinde outcome'lar da otomatik silinir
        // (test izolasyonu deleteOpenTrades(symbolPrefix:) ile kolaylaşır).
        let createOutcomes = """
        CREATE TABLE IF NOT EXISTS outcomes (
            outcome_id TEXT PRIMARY KEY,
            trade_id TEXT NOT NULL,
            realized_pnl REAL NOT NULL,
            realized_pnl_pct REAL NOT NULL,
            holding_minutes INTEGER NOT NULL,
            r_multiple REAL,
            mae_pct REAL,
            mfe_pct REAL,
            exit_reason TEXT NOT NULL,
            closed_at TEXT NOT NULL,
            -- Faz 1.B Task 1: Veri katmanı (parent trade'in tier'ı ile sync edilir)
            tier TEXT NOT NULL DEFAULT 'hot',
            FOREIGN KEY (trade_id) REFERENCES trades(trade_id) ON DELETE CASCADE
        );
        """

        let indices = [
            "CREATE INDEX IF NOT EXISTS idx_events_time ON events(event_time_utc);",
            "CREATE INDEX IF NOT EXISTS idx_events_symbol_time ON events(symbol, event_time_utc);",
            "CREATE INDEX IF NOT EXISTS idx_events_decision ON events(decision_id);",
            "CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol);",
            "CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);",
            "CREATE INDEX IF NOT EXISTS idx_lessons_trade ON lessons(trade_id);",
            // Task 12: Outcomes indices
            "CREATE INDEX IF NOT EXISTS idx_outcomes_trade_id ON outcomes(trade_id);",
            "CREATE INDEX IF NOT EXISTS idx_outcomes_closed_at ON outcomes(closed_at);",
            // Faz 1.B Task 1: Tier indices — DataTieringEngine WHERE tier='hot'
            // sorguları + Settings → Veri Defteri ekranında tier dağılımı sayımı
            // (GROUP BY tier) hızlı olsun.
            "CREATE INDEX IF NOT EXISTS idx_events_tier ON events(tier);",
            "CREATE INDEX IF NOT EXISTS idx_trades_tier ON trades(tier);",
            "CREATE INDEX IF NOT EXISTS idx_outcomes_tier ON outcomes(tier);"
        ]

        execute(sql: createBlobs)
        execute(sql: createEvents)
        execute(sql: createTrades)
        execute(sql: createLessons)
        execute(sql: createWeightHistory)
        execute(sql: createOutcomes)
        // FK CASCADE etkin olmazsa trades silindiğinde outcomes orphan kalır.
        // SQLite default PRAGMA foreign_keys=OFF; her connection'da açmak zorunlu.
        // Performans etkisi yok (constraint check), tek satırlık idempotent pragma.
        execute(sql: "PRAGMA foreign_keys = ON;")
        for idx in indices { execute(sql: idx) }

        // Idempotent SQLite schema migrations for existing databases.
        // SQLite does not support ADD COLUMN IF NOT EXISTS; the duplicate-column
        // error is expected for already-migrated DBs and is ignored on purpose
        // (same pattern used by markEventProcessed for events.processed).
        // Without this, INSERT/SELECT statements that reference these columns
        // fail silently and openTrade never persists rows.
        runIdempotentTradeMigrations()
    }

    private func runIdempotentTradeMigrations() {
        // Çağıran (createSchema → ensureConnection) zaten `queue.sync` içinde —
        // burada tekrar `queue.sync` sarmalı YAZMA: deadlock olur.
        let migrations = [
            "ALTER TABLE trades ADD COLUMN entry_reason TEXT;",
            "ALTER TABLE trades ADD COLUMN dominant_signal TEXT;",
            // Faz 1.B Task 1: Mevcut DB'lerde tier kolonu (yeni DB'lerde CREATE
            // TABLE ile var). Idempotent: kolon zaten varsa "duplicate column
            // name" yutulur (yukarıdaki pattern).
            "ALTER TABLE events ADD COLUMN tier TEXT NOT NULL DEFAULT 'hot';",
            "ALTER TABLE trades ADD COLUMN tier TEXT NOT NULL DEFAULT 'hot';",
            "ALTER TABLE outcomes ADD COLUMN tier TEXT NOT NULL DEFAULT 'hot';"
        ]
        for sql in migrations {
            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if rc != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? ""
                sqlite3_free(errMsg)
                // SQLite ADD COLUMN IF NOT EXISTS desteklemez; zaten migrate
                // edilmiş DB'de "duplicate column name" beklenir — sadece bunu
                // yut. Disk dolu, lock, no-such-table gibi diğer hataları log'a
                // bas — sessiz silent failure ile aynı sınıfta hata bırakma.
                if msg.lowercased().contains("duplicate column name") {
                    continue
                }
                print("🚨 ArgusLedger: Trade migration failed (sql=\(sql)): \(msg)")
            }
        }
    }

    // MARK: - Storage Inspection (Faz 1.B.4)

    /// SQLite veritabanı dosyasının boyutu (byte). Dosya yoksa veya okunamıyorsa
    /// `nil`. Settings → Veri Defteri ekranı bu değeri kullanıcıya gösterir +
    /// 250 MB tavanını aşıyorsa sarı banner uyarısı tetikler.
    nonisolated func databaseFileSizeBytes() -> Int64? {
        let url = URL(fileURLWithPath: dbPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else {
            return nil
        }
        return size
    }

    // MARK: - Tier Migration (Faz 1.B.2)

    /// Belirli bir tablodaki `tier` kolonu üzerinde toplu güncelleme.
    /// DataTieringEngine bu helper'ı çağırarak 90g→warm, 1y→cold yuvarlamasını
    /// yapar. SQL idempotent: birden fazla çalıştırılırsa state bozulmaz
    /// (`fromTier` filtresi nedeniyle aynı satır iki kez güncellenmez).
    ///
    /// - Parameters:
    ///   - table: "events" | "trades" | "outcomes" — sadece bu üç tablo desteklenir.
    ///   - dateColumn: Kıyaslama yapılacak ISO8601 tarih kolonu (events:
    ///     event_time_utc; trades: entry_date; outcomes: closed_at).
    ///   - fromTier: Kaynak tier ("hot" veya "warm").
    ///   - toTier: Hedef tier ("warm" veya "cold").
    ///   - cutoff: Bu tarihten ESKİ olanlar güncellenir (ISO8601 string < cutoff).
    /// - Returns: Etkilenen satır sayısı.
    @discardableResult
    func migrateTier(
        table: String,
        dateColumn: String,
        fromTier: String,
        toTier: String,
        cutoff: Date
    ) -> Int {
        // Identifier interpolation güvenli — caller her zaman literal string verir
        // (DataTieringEngine içinde hard-coded). SQL injection yüzeyi yok.
        let sql = """
        UPDATE \(table)
           SET tier = ?
         WHERE tier = ?
           AND \(dateColumn) < ?;
        """
        let cutoffString = cutoff.iso8601
        var affected = 0
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (toTier as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (fromTier as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (cutoffString as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                affected = Int(sqlite3_changes(db))
            }
        }
        return affected
    }

    /// Tablo başına tier dağılımı: ["hot": 12000, "warm": 4500, "cold": 200].
    /// Settings → Veri Defteri ekranı bu çıktıyı çizgi grafik veya kart olarak gösterir.
    func countByTier(table: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let sql = "SELECT tier, COUNT(*) FROM \(table) GROUP BY tier;"
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cstr = sqlite3_column_text(stmt, 0) else { continue }
                let tier = String(cString: cstr)
                let count = Int(sqlite3_column_int64(stmt, 1))
                result[tier] = count
            }
        }
        return result
    }

    // MARK: - Schema Inspection (test + UI introspection)

    /// PRAGMA table_info ile belirtilen tablonun kolon adlarını döner.
    /// Faz 1.B test'leri (tier kolonu mevcut mu?) ve gelecek Veri Defteri UI
    /// için kullanılır. Tablo yoksa boş array döner.
    func columnNames(forTable table: String) -> [String] {
        var names: [String] = []
        // PRAGMA table_info(name) kolon listesini SELECT olarak döndürür.
        // Identifier interpolation güvenli: yalnızca dahili çağrılarla kullanılır,
        // SQL injection yüzeyi yok (caller her zaman literal string geçer).
        let sql = "PRAGMA table_info(\(table));"
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            // Kolon indeksleri: 0=cid, 1=name, 2=type, 3=notnull, 4=dflt, 5=pk
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 1) {
                    names.append(String(cString: cstr))
                }
            }
        }
        return names
    }

    // MARK: - Core API
    
    /// Writes a compressed blob to storage. Returns the SHA-256 hash.
    /// If blob exists, strictly ignores (CAS).
    func writeBlob(type: String, data: Data, meta: [String: Any]) -> String? {
        // 1. Skip compression for simplicity (zlib API issue on iOS)
        // Store uncompressed data directly
        let storageData = data
        
        // 2. Hash (We hash the data to ensure strict CAS for what determines storage)
        let hash = sha256(data: storageData)
        let size = storageData.count
        let metaJson = asJsonString(meta) ?? "{}"
        let now = Date().iso8601
        
        let sql = """
        INSERT OR IGNORE INTO blobs (hash_id, blob_type, compression, payload_bytes, created_at_utc, size_bytes, source_meta_json)
        VALUES (?, ?, 'NONE', ?, ?, ?, ?);
        """
        
        return queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (hash as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (type as NSString).utf8String, -1, nil)
                
                // Bind BLOB
                storageData.withUnsafeBytes { ptr in
                     _ = sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(storageData.count), nil) // SQLITE_TRANSIENT
                }
                
                sqlite3_bind_text(stmt, 4, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 5, Int32(size))
                sqlite3_bind_text(stmt, 6, (metaJson as NSString).utf8String, -1, nil)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 FlightRecorder: Blob Write Error")
                }
            } else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                print("🚨 FlightRecorder: Prepare Error: \(errMsg)")
            }
            sqlite3_finalize(stmt)
            return hash
        }
    }
    
    /// Reads a blob from storage by hash.
    func readBlob(hash: String) -> Data? {
        let sql = """
        SELECT payload_bytes FROM blobs WHERE hash_id = ? LIMIT 1;
        """
        
        return queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            var result: Data?
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (hash as NSString).utf8String, -1, nil)
                
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let blobPtr = sqlite3_column_blob(stmt, 0) {
                        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                        result = Data(bytes: blobPtr, count: blobSize)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }
    
    /// Caches a blob reference for the current symbol cycle.
    /// Used to implicitly pass data provenance to AGORA.
    func cacheSnapshotRef(symbol: String, type: String, hash: String) {
        contextLock.lock()
        defer { contextLock.unlock() }
        
        var refs = latestSnapshots[symbol] ?? [:]
        refs[type] = hash
        latestSnapshots[symbol] = refs
    }
    
    /// Retrieves cached snapshot references for linking to a Decision.
    func getSnapshotRefs(symbol: String) -> [String: String] {
        contextLock.lock()
        defer { contextLock.unlock() }
        return latestSnapshots[symbol] ?? [:]
    }
    
    func recordEvent(
        type: String,
        decisionId: String?,
        symbol: String?,
        payload: [String: Any]
    ) {
        let eventId = UUID().uuidString
        let now = Date().iso8601
        let runId = SessionID.shared.id // Assuming we have or will create this
        let payloadJson = asJsonString(payload) ?? "{}"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let engineVer = "AGORA-2.1" // Constant for now
        
        let sql = """
        INSERT INTO events (event_id, event_type, event_time_utc, run_id, decision_id, symbol, payload_json, app_build, engine_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        queue.async {
            self.ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (eventId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (type as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (runId as NSString).utf8String, -1, nil)
                
                if let decId = decisionId {
                    sqlite3_bind_text(stmt, 5, (decId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let sym = symbol {
                    sqlite3_bind_text(stmt, 6, (sym as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                sqlite3_bind_text(stmt, 7, (payloadJson as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (appBuild as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (engineVer as NSString).utf8String, -1, nil)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 FlightRecorder: Event Write Error")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Forecast Logging
    func logForecast(
        symbol: String,
        currentPrice: Double,
        predictedPrice: Double,
        predictions: [Double],
        confidence: Double
    ) {
        let payload: [String: Any] = [
            "current_price": currentPrice,
            "predicted_price": predictedPrice,
            "predictions": predictions,
            "confidence": confidence,
            "model": "Holt-Winters-V1",
            "horizon_days": 5
        ]
        
        recordEvent(
            type: "ForecastEvent",
            decisionId: nil,
            symbol: symbol,
            payload: payload
        )
    }
    
    /// Logs a Grand Council Decision with full scientific context.
    func logDecision(
        decisionId: UUID,
        symbol: String,
        action: String,
        confidence: Double,
        scores: [String: Double],
        vetoes: [String],
        origin: String, // UI_SCAN, AUTOPILOT, BACKTEST
        runId: String? = nil,
        currentPrice: Double? = nil,
        // Faz V (2026-05-12): hangi öğrenilmiş ağırlıkların kullanıldığını
        // tanımlayan deterministik snapshot ID. ChironCouncilLearningService.
        // getWeightsSnapshot çıktısından gelir; nil = legacy çağırı.
        weightSnapshotId: String? = nil,
        // Task 11 (2026-05-13): Council convene anında üretilen modül oy
        // dökümü — `[ModuleVoteRecord]` JSON string olarak gelir. nil ise
        // payload'a yazılmaz (geriye uyumluluk; eski çağırılar etkilenmez).
        // Trade kapanışında `queryModuleVotes(decisionId:)` bu alanı okur.
        moduleVotes: String? = nil
    ) {
        let now = Date().iso8601
        let snapshots = getSnapshotRefs(symbol: symbol)

        // Calculate Data Hash (Composite of all snapshots)
        let dataHash = snapshots.values.sorted().joined(separator: "|")
        let dataVersionHash = sha256(data: dataHash.data(using: .utf8) ?? Data())

        // Task 11: modül oy dökümü JSON string → `[Any]` (gerçek array) olarak
        // payload'a yerleştir. JSONSerialization string'i tekrar parse etmez —
        // string olarak yazılırsa nested JSON-in-JSON olur (çift escape).
        // Decode başarısız olursa (malformed input) payload'tan çıkarılır;
        // sessiz veri kaybı yerine açık log.
        var moduleVotesParsed: Any = NSNull()
        if let raw = moduleVotes,
           let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            moduleVotesParsed = arr
        } else if moduleVotes != nil {
            print("🚨 ArgusLedger: module_votes JSON parse failed for decision \(decisionId.uuidString.prefix(8))")
        }

        let payload: [String: Any] = [
            "action": action,
            "confidence": confidence,
            "scores": scores,
            "vetoes": vetoes,
            "origin": origin,
            "snapshots": snapshots,
            "current_price": currentPrice ?? 0.0,

            // Scientific Meta
            "as_of_utc": now, // For now, decision time is data time (until historical fetch is ready)
            "data_version_hash": dataVersionHash,
            "engine_config_hash": currentConfigHash(),
            "instrument_type": "STOCK",
            "market_region": symbol.contains(".IS") ? "BIST" : "US",

            // Faz V: weight snapshot id (nil → NSNull placeholder JSON-safe).
            "weight_snapshot_id": weightSnapshotId ?? NSNull(),

            // Task 11: modül oy dökümü ([ModuleVoteRecord] JSON dizisi).
            "module_votes": moduleVotesParsed
        ]
        
        let runIdentifier = runId ?? SessionID.shared.id

        // Faz IV (2026-05-12): Önce önceki kararı oku ve delta detect et.
        // BU MUTLAKA yeni DecisionEvent queue.async write'ından ÖNCE olmalı:
        // aksi halde cache miss durumunda `readLastDecision` SQL'i sorguladığında
        // queue serial olduğu için yeni yazılmış event'i "previous" olarak
        // okur (self-reference race). Sıralama:
        //   1. detectAndLogDecisionChange — önceki kararla karşılaştır, gerekirse
        //      DecisionChangeEvent queue'a yaz (async).
        //   2. DecisionEvent queue'a yaz (async).
        //   3. Cache'i yeni kararla güncelle (defer içinde).
        // Queue FIFO olduğu için DB'ye yazım sırası: ChangeEvent → DecisionEvent.
        // Bu, audit trail'i "transition X→Y kaydedildi" → "yeni karar Y kaydedildi"
        // sırasında okumayı sağlar; semantik açıdan tutarlı.
        detectAndLogDecisionChange(
            symbol: symbol,
            newAction: action,
            newConfidence: confidence,
            newDecisionId: decisionId,
            newWeightSnapshotId: weightSnapshotId,
            runId: runIdentifier
        )

        // Record Event
        let eventSql = """
        INSERT INTO events (event_id, event_type, event_time_utc, run_id, decision_id, symbol, payload_json, app_build, engine_version, processed)
        VALUES (?, 'DecisionEvent', ?, ?, ?, ?, ?, ?, 'ARGUS-3.0', 0);
        """

        let payloadJson = asJsonString(payload) ?? "{}"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        queue.async {
            self.ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, eventSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (UUID().uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (runIdentifier as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (decisionId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (symbol as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (payloadJson as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (appBuild as NSString).utf8String, -1, nil)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 ArgusLedger: Decision Log Error")
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Faz IV: Decision Change Detection

    /// Sembolün önceki kararını çağırır, delta varsa DecisionChangeEvent yazar.
    /// Sonra cache'i yeni kararla günceller. Eşik üstü olmayan değişimler
    /// (örn. action aynı + confidence delta < 0.05) yine de cache'i günceller
    /// ama event yazmaz — küçük dalgalanmalar audit trail'i kirletmez.
    private func detectAndLogDecisionChange(
        symbol: String,
        newAction: String,
        newConfidence: Double,
        newDecisionId: UUID,
        newWeightSnapshotId: String?,
        runId: String
    ) {
        let previous = readLastDecision(symbol: symbol)
        defer {
            updateLastDecisionCache(
                symbol: symbol,
                action: newAction,
                confidence: newConfidence,
                decisionId: newDecisionId,
                weightSnapshotId: newWeightSnapshotId
            )
        }

        guard let prev = previous else {
            // İlk karar — change event yok, sadece cache başlat.
            return
        }

        let actionChanged = prev.action != newAction
        let confidenceDelta = newConfidence - prev.confidence
        let significantConfidenceShift = abs(confidenceDelta) >= decisionConfidenceDeltaThreshold

        guard actionChanged || significantConfidenceShift else { return }

        logDecisionChangeEvent(
            symbol: symbol,
            fromAction: prev.action,
            toAction: newAction,
            fromConfidence: prev.confidence,
            toConfidence: newConfidence,
            confidenceDelta: confidenceDelta,
            fromDecisionId: prev.decisionId,
            toDecisionId: newDecisionId,
            fromWeightSnapshotId: prev.weightSnapshotId,
            toWeightSnapshotId: newWeightSnapshotId,
            runId: runId
        )
    }

    /// In-memory cache'ten okur; cache miss'te SQL'den çeker.
    private func readLastDecision(symbol: String) -> (action: String, confidence: Double, decisionId: UUID, weightSnapshotId: String?)? {
        if let cached = lastDecisionsLock.withLock({ lastDecisions[symbol] }) {
            return cached
        }
        // Cache miss — SQL'den lazy load (cold start veya yeni sembol)
        let sql = """
        SELECT decision_id, payload_json FROM events
        WHERE event_type = 'DecisionEvent' AND symbol = ?
        ORDER BY event_time_utc DESC LIMIT 1;
        """
        return queue.sync { () -> (String, Double, UUID, String?)? in
            ensureConnection()
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, (symbol as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let decIdCStr = sqlite3_column_text(stmt, 0),
                  let payloadCStr = sqlite3_column_text(stmt, 1) else { return nil }
            let decIdStr = String(cString: decIdCStr)
            let payloadStr = String(cString: payloadCStr)
            guard let decId = UUID(uuidString: decIdStr) else { return nil }
            guard let data = payloadStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let action = json["action"] as? String ?? "neutral"
            let confidence = (json["confidence"] as? Double) ?? 0.0
            // Faz V: payload'dan weight_snapshot_id'i çek. Eski event'lerde
            // olmayabilir → nil. NSNull JSON serializer'dan geri okurken
            // `NSNull` instance veya yok olarak gelir; ikisini de nil say.
            let snapshotIdRaw = json["weight_snapshot_id"]
            let snapshotId = snapshotIdRaw as? String
            return (action, confidence, decId, snapshotId)
        }
    }

    private func updateLastDecisionCache(
        symbol: String,
        action: String,
        confidence: Double,
        decisionId: UUID,
        weightSnapshotId: String?
    ) {
        lastDecisionsLock.withLock {
            lastDecisions[symbol] = (action, confidence, decisionId, weightSnapshotId)
        }
    }

    /// DecisionChangeEvent — events table'ına yazılan ayrı event tipi.
    /// Schema değişikliği gerektirmez; payload_json delta detaylarını taşır.
    /// `decision_id` field'ı YENİ decision'ı işaret eder (foreign key gibi),
    /// `from_decision_id` payload içinde — eski kararı izlemek için.
    /// Faz V: from/to weight snapshot id'leri de payload'a yazılır — weight
    /// değişimi ile karar değişimi arasındaki nedensellik audit edilebilir.
    private func logDecisionChangeEvent(
        symbol: String,
        fromAction: String,
        toAction: String,
        fromConfidence: Double,
        toConfidence: Double,
        confidenceDelta: Double,
        fromDecisionId: UUID,
        toDecisionId: UUID,
        fromWeightSnapshotId: String?,
        toWeightSnapshotId: String?,
        runId: String
    ) {
        let payload: [String: Any] = [
            "symbol": symbol,
            "from_action": fromAction,
            "to_action": toAction,
            "from_confidence": fromConfidence,
            "to_confidence": toConfidence,
            "confidence_delta": confidenceDelta,
            "action_changed": fromAction != toAction,
            "from_decision_id": fromDecisionId.uuidString,
            "to_decision_id": toDecisionId.uuidString,
            "from_weight_snapshot_id": fromWeightSnapshotId ?? NSNull(),
            "to_weight_snapshot_id": toWeightSnapshotId ?? NSNull(),
            "weights_changed": (fromWeightSnapshotId != nil && toWeightSnapshotId != nil && fromWeightSnapshotId != toWeightSnapshotId)
        ]
        recordEvent(
            type: "DecisionChangeEvent",
            decisionId: toDecisionId.uuidString,
            symbol: symbol,
            payload: payload
        )
    }

    // MARK: - Config Hash

    /// Deterministic hash of key Grand Council decision parameters.
    /// Changes when thresholds or module weights are modified, allowing the
    /// ledger to distinguish decisions made under different configurations.
    private func currentConfigHash() -> String {
        var hasher = Hasher()
        hasher.combine("GC-v4")
        // Grand Council decision thresholds
        hasher.combine(0.45) // aggressiveBuy
        hasher.combine(0.35) // strongBuy
        hasher.combine(0.10) // accumulate
        hasher.combine(0.40) // liquidate
        // Module weight regime tags (bull/neutral/bear affect weights)
        hasher.combine("bull-neutral-bear")
        return "GC4-\(abs(hasher.finalize()) % 100000)"
    }

    // MARK: - Helpers
    private func execute(sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("🚨 FlightRecorder: SQL Error: \(errMsg)")
        }
    }
    
    private func asJsonString(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // Simple SHA256 Helper using CryptoKit
    private func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - ARGUS 3.0: Trade Lifecycle API
    
    /// Opens a new trade and returns its UUID.
    @discardableResult
    func openTrade(
        symbol: String,
        price: Double,
        reason: String,
        dominantSignal: String? = nil,
        decisionId: String? = nil
    ) -> UUID {
        let tradeId = UUID()
        let now = Date().iso8601
        
        // entry_action is NOT NULL in the schema; ExecutionGovernor.didExecute is the only
        // caller (BUY path), so we hardcode it here. SELL legs are written via closeTrade.
        let sql = """
        INSERT INTO trades (trade_id, symbol, status, entry_date, entry_price, entry_action, entry_reason, dominant_signal, decision_id)
        VALUES (?, ?, 'OPEN', ?, ?, 'BUY', ?, ?, ?);
        """
        
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (tradeId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (symbol as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 4, price)
                sqlite3_bind_text(stmt, 5, (reason as NSString).utf8String, -1, nil)
                
                if let signal = dominantSignal {
                    sqlite3_bind_text(stmt, 6, (signal as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                if let decId = decisionId {
                    sqlite3_bind_text(stmt, 7, (decId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 ArgusLedger: Trade Open Error")
                } else {
                    print("📈 ArgusLedger: Trade Opened for \(symbol) @ \(price)")
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return tradeId
    }
    
    /// Closes an open trade and calculates PnL.
    func closeTrade(tradeId: UUID, exitPrice: Double) {
        let now = Date().iso8601
        
        // First, get entry price to calculate PnL
        var entryPrice: Double = 0
        var symbol: String = ""
        
        let selectSql = "SELECT entry_price, symbol FROM trades WHERE trade_id = ?;"
        
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (tradeId.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    entryPrice = sqlite3_column_double(stmt, 0)
                    if let symPtr = sqlite3_column_text(stmt, 1) {
                        symbol = String(cString: symPtr)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        
        guard entryPrice > 0 else {
            print("⚠️ ArgusLedger: Trade not found for closing: \(tradeId)")
            return
        }
        
        let pnlPercent = ((exitPrice - entryPrice) / entryPrice) * 100.0
        
        let updateSql = """
        UPDATE trades SET status = 'CLOSED', exit_date = ?, exit_price = ?, pnl_percent = ? WHERE trade_id = ?;
        """
        
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 2, exitPrice)
                sqlite3_bind_double(stmt, 3, pnlPercent)
                sqlite3_bind_text(stmt, 4, (tradeId.uuidString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 ArgusLedger: Trade Close Error")
                } else {
                    print("💰 ArgusLedger: Trade Closed for \(symbol). PnL: \(String(format: "%.2f", pnlPercent))%")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Task 12 (2026-05-12): Outcomes API
    //
    // Ledger üçüncü katman — decisions → trades → outcomes. Trade kapanış anında
    // recordOutcome çağrılır (PortfolioStore.applySellStateMutation içinden).
    // R-multiple: Van Tharp (1998) — "1 birim risk için kaç birim kâr" ölçüsü.

    /// R-multiple hesabı (sadece long pozisyon, Faz 1).
    /// Short pozisyon Faz 2'ye bırakıldı: risk yön çevirisi (entry - stop yerine stop - entry).
    ///
    /// - Parameters:
    ///   - entryPrice: Trade giriş fiyatı.
    ///   - exitPrice: Trade çıkış fiyatı.
    ///   - initialStop: Trade açılışındaki stop-loss seviyesi (Optional).
    /// - Returns: R-multiple veya `nil`.
    ///   `nil` koşulları: stop yok / stop ≤ 0 / stop = entry / stop > entry (invalid for long).
    static func calculateRMultiple(
        entryPrice: Double,
        exitPrice: Double,
        initialStop: Double?
    ) -> Double? {
        guard let stop = initialStop, stop > 0, stop != entryPrice else { return nil }
        // Long pozisyon: risk = entry - stop (positive olmalı; stop entry'nin altında)
        let risk = entryPrice - stop
        guard risk > 0 else { return nil }  // stop entry'nin üstündeyse invalid (short ise Faz 2)
        let pnl = exitPrice - entryPrice
        return pnl / risk
    }

    /// Trade kapanış anında outcome insert. Hata olursa log basar ve UUID döndürür —
    /// caller bilmiyor zaten (defensive — outcome eksikliği trade lifecycle'ı bozmamalı).
    @discardableResult
    func recordOutcome(
        tradeId: UUID,
        realizedPnL: Double,
        realizedPnLPct: Double,
        holdingMinutes: Int,
        rMultiple: Double?,
        exitReason: String
    ) -> UUID {
        let outcomeId = UUID()
        let now = Date().iso8601

        // MAE/MFE bind null — Faz 2 (QuoteHandler tick-by-tick) populated edecek.
        let sql = """
        INSERT INTO outcomes (
            outcome_id, trade_id, realized_pnl, realized_pnl_pct,
            holding_minutes, r_multiple, mae_pct, mfe_pct,
            exit_reason, closed_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (outcomeId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (tradeId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 3, realizedPnL)
                sqlite3_bind_double(stmt, 4, realizedPnLPct)
                sqlite3_bind_int(stmt, 5, Int32(holdingMinutes))

                if let r = rMultiple {
                    sqlite3_bind_double(stmt, 6, r)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                // MAE/MFE — her zaman null (Faz 1)
                sqlite3_bind_null(stmt, 7)
                sqlite3_bind_null(stmt, 8)

                sqlite3_bind_text(stmt, 9, (exitReason as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (now as NSString).utf8String, -1, nil)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let err = String(cString: sqlite3_errmsg(db))
                    print("🚨 ArgusLedger: Outcome insert error: \(err)")
                } else {
                    let rStr = rMultiple.map { String(format: "%.2fR", $0) } ?? "n/a"
                    print("🎯 ArgusLedger: Outcome recorded trade=\(tradeId.uuidString.prefix(8)) pnl=\(String(format: "%.2f", realizedPnL)) r=\(rStr)")
                }
            } else {
                let err = String(cString: sqlite3_errmsg(db))
                print("🚨 ArgusLedger: Outcome prepare error: \(err)")
            }
            sqlite3_finalize(stmt)
        }

        return outcomeId
    }

    /// Trade'e ait outcome'u getirir (varsa). Lifecycle'da bir trade bir outcome'a sahip
    /// olabilir; PK trade_id değil outcome_id, fakat tekil insert pattern beklenir.
    func queryOutcome(forTradeId tradeId: UUID) -> Outcome? {
        let sql = """
        SELECT outcome_id, trade_id, realized_pnl, realized_pnl_pct,
               holding_minutes, r_multiple, mae_pct, mfe_pct,
               exit_reason, closed_at
        FROM outcomes
        WHERE trade_id = ?
        LIMIT 1;
        """

        return queue.sync { () -> Outcome? in
            ensureConnection()
            var stmt: OpaquePointer?
            var result: Outcome? = nil

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (tradeId.uuidString as NSString).utf8String, -1, nil)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    result = parseOutcomeRow(stmt: stmt)
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    /// Validator için: belirtilen tarih sonrası kapanmış tüm outcome'ları döner.
    /// `since` UTC timestamp olarak yorumlanır; closed_at ISO8601 string karşılaştırması
    /// SQLite'da lexicographic — ISO8601 format zaten kronolojik sıralı.
    func queryAllOutcomes(since: Date) -> [Outcome] {
        let sinceIso = since.iso8601
        let sql = """
        SELECT outcome_id, trade_id, realized_pnl, realized_pnl_pct,
               holding_minutes, r_multiple, mae_pct, mfe_pct,
               exit_reason, closed_at
        FROM outcomes
        WHERE closed_at >= ?
        ORDER BY closed_at ASC;
        """

        return queue.sync { () -> [Outcome] in
            ensureConnection()
            var stmt: OpaquePointer?
            var results: [Outcome] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (sinceIso as NSString).utf8String, -1, nil)

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let outcome = parseOutcomeRow(stmt: stmt) {
                        results.append(outcome)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return results
        }
    }

    /// Outcome row → struct. Nullable kolonlar (r_multiple, mae_pct, mfe_pct) için
    /// `sqlite3_column_type == SQLITE_NULL` kontrolü zorunlu — aksi halde NULL → 0.0
    /// silent corruption olur.
    private func parseOutcomeRow(stmt: OpaquePointer?) -> Outcome? {
        guard let stmt = stmt,
              let outcomeIdPtr = sqlite3_column_text(stmt, 0),
              let tradeIdPtr = sqlite3_column_text(stmt, 1),
              let exitReasonPtr = sqlite3_column_text(stmt, 8),
              let closedAtPtr = sqlite3_column_text(stmt, 9) else { return nil }

        let outcomeId = UUID(uuidString: String(cString: outcomeIdPtr)) ?? UUID()
        let tradeId = UUID(uuidString: String(cString: tradeIdPtr)) ?? UUID()
        let realizedPnL = sqlite3_column_double(stmt, 2)
        let realizedPnLPct = sqlite3_column_double(stmt, 3)
        let holdingMinutes = Int(sqlite3_column_int(stmt, 4))

        let rMultiple: Double? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(stmt, 5)
        let maePct: Double? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(stmt, 6)
        let mfePct: Double? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(stmt, 7)

        let exitReason = String(cString: exitReasonPtr)
        let closedAt = Date.fromISO8601(String(cString: closedAtPtr)) ?? Date()

        return Outcome(
            outcomeId: outcomeId,
            tradeId: tradeId,
            realizedPnL: realizedPnL,
            realizedPnLPct: realizedPnLPct,
            holdingMinutes: holdingMinutes,
            rMultiple: rMultiple,
            maePct: maePct,
            mfePct: mfePct,
            exitReason: exitReason,
            closedAt: closedAt
        )
    }

    // MARK: - Task 11 (2026-05-13): Module Vote Lookup
    //
    // Decision → Trade → Outcome zincirinin "modül performansı" yan kolu için
    // payload'tan module_votes dizisini çeker. Tablo şeması değişmiyor: votes
    // `events.payload_json` içinde, ayrı kolon yok. `DecisionEvent` event_type
    // ile filtreleme; aynı symbol için birden fazla decision olabilir, biz
    // belirli `decision_id`'yi arıyoruz.
    //
    // Geriye uyumluluk:
    // - Task 11 öncesi decisions'larda module_votes alanı yok → boş dizi.
    // - module_votes alanı var ama malformed → boş dizi (sessiz korumacılık;
    //   trade lifecycle bozulmamalı).
    func queryModuleVotes(decisionId: String) -> [ModuleVoteRecord] {
        let sql = """
        SELECT payload_json FROM events
        WHERE event_type = 'DecisionEvent' AND decision_id = ?
        LIMIT 1;
        """

        return queue.sync { () -> [ModuleVoteRecord] in
            ensureConnection()
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return []
            }
            sqlite3_bind_text(stmt, 1, (decisionId as NSString).utf8String, -1, nil)

            guard sqlite3_step(stmt) == SQLITE_ROW,
                  sqlite3_column_type(stmt, 0) != SQLITE_NULL,
                  let payloadCStr = sqlite3_column_text(stmt, 0) else {
                return []
            }

            let payloadStr = String(cString: payloadCStr)
            guard let data = payloadStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let votesArray = json["module_votes"] as? [[String: Any]] else {
                return []
            }

            // Re-encode + decode ile JSONDecoder'ın strict tip kontrolünü
            // kullanırız — manuel dict parsing'i pas geçer (ileride alan eklendiğinde
            // ModuleVoteRecord değişimini tek yere lokalize eder).
            guard let votesData = try? JSONSerialization.data(withJSONObject: votesArray),
                  let votes = try? JSONDecoder().decode([ModuleVoteRecord].self, from: votesData) else {
                return []
            }
            return votes
        }
    }

    /// Records a lesson learned from a trade.
    func recordLesson(tradeId: UUID, lesson: String, deviationPercent: Double? = nil, weightChanges: [String: Double]? = nil) {
        let lessonId = UUID()
        let now = Date().iso8601
        let weightJson = weightChanges != nil ? asJsonString(weightChanges! as [String: Any]) : nil
        
        let sql = """
        INSERT INTO lessons (lesson_id, trade_id, created_at, lesson_text, deviation_percent, weight_changes_json)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        
        queue.async {
            self.ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (lessonId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (tradeId.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (lesson as NSString).utf8String, -1, nil)
                
                if let dev = deviationPercent {
                    sqlite3_bind_double(stmt, 5, dev)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let wJson = weightJson {
                    sqlite3_bind_text(stmt, 6, (wJson as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("🚨 ArgusLedger: Lesson Record Error")
                } else {
                    print("📚 ArgusLedger: Lesson Recorded for Trade \(tradeId.uuidString.prefix(8))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Observatory: Learning Event Logging
    
    /// Logs a learning event (weight update) for Observatory.
    func logLearning(event: LearningEvent) {
        let now = Date().iso8601
        
        // Insert one row per module weight change
        let sql = """
        INSERT INTO weight_history (timestamp, module, old_weight, new_weight, reason, regime, window_days, sample_size, trigger_metric, trigger_value)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        queue.async {
            self.ensureConnection()
            
            for (module, delta) in event.weightDeltas {
                let oldWeight = event.oldWeights[module] ?? 0.0
                let newWeight = event.newWeights[module] ?? 0.0
                
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (now as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 2, (module as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(stmt, 3, oldWeight)
                    sqlite3_bind_double(stmt, 4, newWeight)
                    sqlite3_bind_text(stmt, 5, (event.reason as NSString).utf8String, -1, nil)
                    
                    if let regime = event.regime {
                        sqlite3_bind_text(stmt, 6, (regime as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(stmt, 6)
                    }
                    
                    sqlite3_bind_int(stmt, 7, Int32(event.windowDays))
                    sqlite3_bind_int(stmt, 8, Int32(event.sampleSize))
                    
                    if let metric = event.triggerMetric {
                        sqlite3_bind_text(stmt, 9, (metric as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(stmt, 9)
                    }
                    
                    if let value = event.triggerValue {
                        sqlite3_bind_double(stmt, 10, value)
                    } else {
                        sqlite3_bind_null(stmt, 10)
                    }
                    
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        print("🚨 ArgusLedger: Learning Event Write Error")
                    }
                }
                sqlite3_finalize(stmt)
            }
            
            print("🧠 ArgusLedger: Learning Event Logged (\(event.weightDeltas.count) modules)")
        }
    }
    
    /// Loads recent learning events for Observatory UI.
    func loadLearningEvents(limit: Int = 50) -> [LearningEvent] {
        let sql = """
        SELECT timestamp, module, old_weight, new_weight, reason, regime, window_days, sample_size, trigger_metric, trigger_value
        FROM weight_history
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        
        var results: [(String, String, Double, Double, String?, String?, Int, Int, String?, Double?)] = []
        
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let timestamp = String(cString: sqlite3_column_text(stmt, 0))
                    let module = String(cString: sqlite3_column_text(stmt, 1))
                    let oldWeight = sqlite3_column_double(stmt, 2)
                    let newWeight = sqlite3_column_double(stmt, 3)
                    let reason = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                    let regime = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
                    let windowDays = Int(sqlite3_column_int(stmt, 6))
                    let sampleSize = Int(sqlite3_column_int(stmt, 7))
                    let triggerMetric = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
                    let triggerValue = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9)
                    
                    results.append((timestamp, module, oldWeight, newWeight, reason, regime, windowDays, sampleSize, triggerMetric, triggerValue))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Group by timestamp to form LearningEvents
        var eventsByTimestamp: [String: (reason: String?, regime: String?, windowDays: Int, sampleSize: Int, triggerMetric: String?, triggerValue: Double?, deltas: [String: Double], oldWeights: [String: Double], newWeights: [String: Double])] = [:]
        
        for row in results {
            let (timestamp, module, oldW, newW, reason, regime, windowDays, sampleSize, triggerMetric, triggerValue) = row
            let delta = newW - oldW
            
            if var existing = eventsByTimestamp[timestamp] {
                existing.deltas[module] = delta
                existing.oldWeights[module] = oldW
                existing.newWeights[module] = newW
                eventsByTimestamp[timestamp] = existing
            } else {
                eventsByTimestamp[timestamp] = (
                    reason: reason,
                    regime: regime,
                    windowDays: windowDays,
                    sampleSize: sampleSize,
                    triggerMetric: triggerMetric,
                    triggerValue: triggerValue,
                    deltas: [module: delta],
                    oldWeights: [module: oldW],
                    newWeights: [module: newW]
                )
            }
        }
        
        return eventsByTimestamp.map { (timestamp, data) in
            LearningEvent(
                id: UUID(),
                timestamp: ISO8601DateFormatter().date(from: timestamp) ?? Date(),
                weightDeltas: data.deltas,
                oldWeights: data.oldWeights,
                newWeights: data.newWeights,
                reason: data.reason ?? "Bilinmiyor",
                triggerMetric: data.triggerMetric,
                triggerValue: data.triggerValue,
                regime: data.regime,
                windowDays: data.windowDays,
                sampleSize: data.sampleSize
            )
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Records a weight change in history.
    func recordWeightChange(module: String, oldWeight: Double, newWeight: Double, reason: String?, tradeId: UUID? = nil) {
        let now = Date().iso8601
        
        let sql = """
        INSERT INTO weight_history (timestamp, module, old_weight, new_weight, reason, trade_id)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        
        queue.async {
            self.ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (module as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 3, oldWeight)
                sqlite3_bind_double(stmt, 4, newWeight)
                
                if let r = reason {
                    sqlite3_bind_text(stmt, 5, (r as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let tid = tradeId {
                    sqlite3_bind_text(stmt, 6, (tid.uuidString as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - ARGUS 3.0: Query API for UI
    
    /// Returns all open trades.
    func getOpenTrades() async -> [TradeRecord] {
        let sql = """
        SELECT trade_id, symbol, status, entry_date, entry_price, entry_reason, 
               exit_date, exit_price, pnl_percent, dominant_signal, decision_id
        FROM trades WHERE status = 'OPEN' ORDER BY entry_date DESC;
        """
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.ensureConnection()
                var results: [TradeRecord] = []
                var stmt: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let record = self.parseTradeRow(stmt: stmt) {
                        results.append(record)
                    }
                }
                
                sqlite3_finalize(stmt)
                continuation.resume(returning: results)
            }
        }
    }

    // MARK: - Test Helpers
    /// Sadece test izolasyonu için: verilen prefix ile başlayan tüm trade
    /// satırlarını siler. Production'da çağırılmamalı — UI bu metoda hiç
    /// referans vermiyor. Test sembolleri (`TEST_DIDEXEC_*`) üretim DB'sini
    /// kirletmesin diye tearDown'da kullanılır.
    func deleteOpenTrades(symbolPrefix: String) async {
        let sql = "DELETE FROM trades WHERE symbol LIKE ?;"
        let pattern = symbolPrefix + "%"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.ensureConnection()
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        let err = String(cString: sqlite3_errmsg(self.db))
                        print("🚨 ArgusLedger: deleteOpenTrades step error: \(err)")
                    }
                } else {
                    let err = String(cString: sqlite3_errmsg(self.db))
                    print("🚨 ArgusLedger: deleteOpenTrades prepare error: \(err)")
                }
                sqlite3_finalize(stmt)
                continuation.resume()
            }
        }
    }

    /// Returns closed trades with limit.
    func getClosedTrades(limit: Int = 50) async -> [TradeRecord] {
        let sql = """
        SELECT trade_id, symbol, status, entry_date, entry_price, entry_reason, 
               exit_date, exit_price, pnl_percent, dominant_signal, decision_id
        FROM trades WHERE status = 'CLOSED' ORDER BY exit_date DESC LIMIT ?;
        """
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.ensureConnection()
                var results: [TradeRecord] = []
                var stmt: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                
                sqlite3_bind_int(stmt, 1, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let record = self.parseTradeRow(stmt: stmt) {
                        results.append(record)
                    }
                }
                
                sqlite3_finalize(stmt)
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Returns lessons with limit.
    func getLessons(limit: Int = 50) async -> [LessonRecord] {
        let sql = """
        SELECT lesson_id, trade_id, created_at, lesson_text, deviation_percent, weight_changes_json
        FROM lessons ORDER BY created_at DESC LIMIT ?;
        """
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.ensureConnection()
                var results: [LessonRecord] = []
                var stmt: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                
                sqlite3_bind_int(stmt, 1, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let lessonIdPtr = sqlite3_column_text(stmt, 0),
                          let tradeIdPtr = sqlite3_column_text(stmt, 1),
                          let createdAtPtr = sqlite3_column_text(stmt, 2),
                          let lessonTextPtr = sqlite3_column_text(stmt, 3) else { continue }
                    
                    let lessonId = UUID(uuidString: String(cString: lessonIdPtr)) ?? UUID()
                    let tradeId = UUID(uuidString: String(cString: tradeIdPtr)) ?? UUID()
                    let createdAt = Date.fromISO8601(String(cString: createdAtPtr)) ?? Date()
                    let lessonText = String(cString: lessonTextPtr)
                    
                    var deviation: Double? = nil
                    if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                        deviation = sqlite3_column_double(stmt, 4)
                    }
                    
                    var weightChanges: [String: Double]? = nil
                    if let jsonPtr = sqlite3_column_text(stmt, 5) {
                        let jsonStr = String(cString: jsonPtr)
                        if let data = jsonStr.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
                            weightChanges = dict
                        }
                    }
                    
                    results.append(LessonRecord(
                        id: lessonId,
                        tradeId: tradeId,
                        createdAt: createdAt,
                        lessonText: lessonText,
                        deviationPercent: deviation,
                        weightChanges: weightChanges
                    ))
                }
                
                sqlite3_finalize(stmt)
                continuation.resume(returning: results)
            }
        }
    }
    
    // MARK: - Observatory: Load Recent Decisions for Timeline
    
    /// Loads recent decision events for Observatory Timeline.
    func loadRecentDecisions(limit: Int = 100) -> [DecisionCard] {
        let sql = """
        SELECT event_id, symbol, event_time_utc, payload_json, processed, horizon_pnl_percent
        FROM events
        WHERE event_type = 'DecisionEvent'
        ORDER BY event_time_utc DESC
        LIMIT ?;
        """
        
        var results: [DecisionCard] = []
        
        queue.sync {
            ensureConnection()
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let eventIdPtr = sqlite3_column_text(stmt, 0),
                          let symbolPtr = sqlite3_column_text(stmt, 1),
                          let timestampPtr = sqlite3_column_text(stmt, 2),
                          let payloadPtr = sqlite3_column_text(stmt, 3) else { continue }
                    
                    let eventId = String(cString: eventIdPtr)
                    let symbol = String(cString: symbolPtr)
                    let timestampStr = String(cString: timestampPtr)
                    let payloadJson = String(cString: payloadPtr)
                    let processed = Int(sqlite3_column_int(stmt, 4))
                    let pnl = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 5)
                    
                    // Parse payload
                    guard let data = payloadJson.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    
                    let action = payload["action"] as? String ?? "GÖZLE"
                    let confidence = payload["confidence"] as? Double ?? 0.5
                    let scoresDict = payload["scores"] as? [String: Double] ?? [:]
                    let marketRegion = payload["market_region"] as? String ?? (symbol.contains(".IS") ? "BIST" : "US")
                    
                    // Extract top factors
                    var factors: [DecisionCard.Factor] = []
                    for (name, value) in scoresDict.sorted(by: { $0.value > $1.value }).prefix(3) {
                        let emoji: String
                        switch name.lowercased() {
                        case "orion": emoji = "📊"
                        case "atlas": emoji = "💰"
                        case "aether": emoji = "🌍"
                        case "hermes": emoji = "📰"
                        case "athena": emoji = "🧠"
                        case "demeter": emoji = "🌾"
                        default: emoji = "📈"
                        }
                        factors.append(DecisionCard.Factor(name: name, emoji: emoji, value: value))
                    }
                    
                    let card = DecisionCard(
                        id: UUID(uuidString: eventId) ?? UUID(),
                        symbol: symbol,
                        market: marketRegion,
                        timestamp: ISO8601DateFormatter().date(from: timestampStr) ?? Date(),
                        action: action,
                        confidence: confidence,
                        topFactors: factors,
                        horizon: .t7, // Default, can be enhanced later
                        outcome: processed == 1 ? .matured : .pending,
                        actualPnl: pnl
                    )
                    
                    results.append(card)
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    // MARK: - Trade Row Parser
    
    private func parseTradeRow(stmt: OpaquePointer?) -> TradeRecord? {
        guard let stmt = stmt,
              let tradeIdPtr = sqlite3_column_text(stmt, 0),
              let symbolPtr = sqlite3_column_text(stmt, 1),
              let statusPtr = sqlite3_column_text(stmt, 2),
              let entryDatePtr = sqlite3_column_text(stmt, 3) else { return nil }
        
        let tradeId = UUID(uuidString: String(cString: tradeIdPtr)) ?? UUID()
        let symbol = String(cString: symbolPtr)
        let status = String(cString: statusPtr)
        let entryDate = Date.fromISO8601(String(cString: entryDatePtr)) ?? Date()
        let entryPrice = sqlite3_column_double(stmt, 4)
        
        var entryReason: String? = nil
        if let ptr = sqlite3_column_text(stmt, 5) {
            entryReason = String(cString: ptr)
        }
        
        var exitDate: Date? = nil
        if let ptr = sqlite3_column_text(stmt, 6) {
            exitDate = Date.fromISO8601(String(cString: ptr))
        }
        
        var exitPrice: Double? = nil
        if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
            exitPrice = sqlite3_column_double(stmt, 7)
        }
        
        var pnlPercent: Double? = nil
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
            pnlPercent = sqlite3_column_double(stmt, 8)
        }
        
        var dominantSignal: String? = nil
        if let ptr = sqlite3_column_text(stmt, 9) {
            dominantSignal = String(cString: ptr)
        }
        
        var decisionId: String? = nil
        if let ptr = sqlite3_column_text(stmt, 10) {
            decisionId = String(cString: ptr)
        }
        
        return TradeRecord(
            id: tradeId,
            symbol: symbol,
            status: status,
            entryDate: entryDate,
            entryPrice: entryPrice,
            entryReason: entryReason,
            exitDate: exitDate,
            exitPrice: exitPrice,
            pnlPercent: pnlPercent,
            dominantSignal: dominantSignal,
            decisionId: decisionId
        )
    }
}

// Session Helper
struct SessionID {
    static let shared = SessionID()
    let id = UUID().uuidString
}

// Date Extension for ISO8601
extension Date {
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
    
    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}

// MARK: - Reading API for Forward Test Processing
extension ArgusLedger {
    
    /// ForecastEvent'leri okur (işlenmemiş olanlar)
    func getUnprocessedForecasts() async -> [ForecastEventData] {
        let sql = """
        SELECT event_id, symbol, event_time_utc, payload_json 
        FROM events 
        WHERE event_type = 'ForecastEvent' AND (processed IS NULL OR processed = 0)
        ORDER BY event_time_utc ASC;
        """
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.ensureConnection()
                var results: [ForecastEventData] = []
                var stmt: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let eventIdPtr = sqlite3_column_text(stmt, 0),
                          let symbolPtr = sqlite3_column_text(stmt, 1),
                          let datePtr = sqlite3_column_text(stmt, 2),
                          let payloadPtr = sqlite3_column_text(stmt, 3) else { continue }
                    
                    let eventId = String(cString: eventIdPtr)
                    let symbol = String(cString: symbolPtr)
                    let dateStr = String(cString: datePtr)
                    let payloadStr = String(cString: payloadPtr)
                    
                    guard let eventDate = Date.fromISO8601(dateStr),
                          let payloadData = payloadStr.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { continue }
                    
                    let currentPrice = payload["current_price"] as? Double ?? 0
                    let predictedPrice = payload["predicted_price"] as? Double ?? 0
                    
                    results.append(ForecastEventData(
                        eventId: eventId,
                        symbol: symbol,
                        eventDate: eventDate,
                        currentPrice: currentPrice,
                        predictedPrice: predictedPrice
                    ))
                }
                
                sqlite3_finalize(stmt)
                continuation.resume(returning: results)
            }
        }
    }
    
    /// DecisionEvent'leri okur (işlenmemiş olanlar)
    func getUnprocessedDecisions() async -> [DecisionEventData] {
        let sql = """
        SELECT event_id, symbol, event_time_utc, payload_json 
        FROM events 
        WHERE event_type = 'DecisionEvent' AND (processed IS NULL OR processed = 0)
        ORDER BY event_time_utc ASC;
        """
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.ensureConnection()
                var results: [DecisionEventData] = []
                var stmt: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let eventIdPtr = sqlite3_column_text(stmt, 0),
                          let symbolPtr = sqlite3_column_text(stmt, 1),
                          let datePtr = sqlite3_column_text(stmt, 2),
                          let payloadPtr = sqlite3_column_text(stmt, 3) else { continue }
                    
                    let eventId = String(cString: eventIdPtr)
                    let symbol = String(cString: symbolPtr)
                    let dateStr = String(cString: datePtr)
                    let payloadStr = String(cString: payloadPtr)
                    
                    guard let eventDate = Date.fromISO8601(dateStr),
                          let payloadData = payloadStr.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { continue }
                    
                    let action = payload["action"] as? String ?? "HOLD"
                    
                    // Fiyatı blob'dan almamız gerekiyor ama şimdilik 0 koyalım
                    // TODO: input_blobs'tan fiyat bilgisi çekilecek
                    let currentPrice = payload["current_price"] as? Double ?? 0
                    
                    // Module scores
                    var moduleScores: [String: Double]? = nil
                    if let scores = payload["scores"] as? [String: Double] {
                        moduleScores = scores
                    }
                    
                    results.append(DecisionEventData(
                        eventId: eventId,
                        symbol: symbol,
                        eventDate: eventDate,
                        currentPrice: currentPrice,
                        action: action,
                        moduleScores: moduleScores ?? [:]
                    ))
                }
                
                sqlite3_finalize(stmt)
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Event'i işlenmiş olarak işaretler
    func markEventProcessed(eventId: String) async {
        // Önce processed kolonu var mı kontrol et, yoksa ekle
        let alterSql = "ALTER TABLE events ADD COLUMN processed INTEGER DEFAULT 0;"
        queue.sync {
            ensureConnection()
            // SQLite ADD COLUMN IF NOT EXISTS desteklemez; zaten migrate edilmiş
            // DB'de "duplicate column name" beklenir — sadece bunu yut. Disk dolu,
            // lock, no-such-table gibi diğer hatalar sessiz silent failure olmasın.
            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, alterSql, nil, nil, &errMsg)
            if rc != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? ""
                sqlite3_free(errMsg)
                if !msg.lowercased().contains("duplicate column name") {
                    print("🚨 ArgusLedger: events.processed migration failed: \(msg)")
                }
            }
        }
        
        let sql = "UPDATE events SET processed = 1 WHERE event_id = ?;"
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (eventId as NSString).utf8String, -1, nil)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
                continuation.resume()
            }
        }
    }
    
    /// İşlenmiş event'leri ve ilişkili blob'ları siler
    func cleanupProcessedEvents() async {
        // 1. İşlenmiş event'lerin blob referanslarını bul
        let findBlobsSql = """
        SELECT DISTINCT json_extract(payload_json, '$.input_blobs[0].hash_id') as blob_hash
        FROM events WHERE processed = 1;
        """
        
        // 2. Blob'ları sil
        let deleteBlobsSql = "DELETE FROM blobs WHERE hash_id = ?;"
        
        // 3. Event'leri sil
        let deleteEventsSql = "DELETE FROM events WHERE processed = 1;"
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.ensureConnection()
                
                // Blob hash'leri topla
                var blobHashes: [String] = []
                var stmt: OpaquePointer?
                
                if sqlite3_prepare_v2(self.db, findBlobsSql, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let hashPtr = sqlite3_column_text(stmt, 0) {
                            blobHashes.append(String(cString: hashPtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                
                // Blob'ları sil
                for hash in blobHashes {
                    var deleteStmt: OpaquePointer?
                    if sqlite3_prepare_v2(self.db, deleteBlobsSql, -1, &deleteStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(deleteStmt, 1, (hash as NSString).utf8String, -1, nil)
                        sqlite3_step(deleteStmt)
                    }
                    sqlite3_finalize(deleteStmt)
                }
                
                // Event'leri sil
                sqlite3_exec(self.db, deleteEventsSql, nil, nil, nil)
                
                // Vacuum
                sqlite3_exec(self.db, "VACUUM;", nil, nil, nil)
                
                print("FlightRecorder: \(blobHashes.count) blob ve iliskili eventler temizlendi")
                continuation.resume()
            }
        }
    }
}

// MARK: - Export / Dump Extension
extension ArgusLedger {
    
    /// Dumps all events to a JSONL file at the specified URL.
    func dumpEvents(to fileUrl: URL) throws {
        let sql = "SELECT payload_json FROM events ORDER BY event_time_utc ASC;"
        var stmt: OpaquePointer?
        
        // Ensure blocking on queue
        try queue.sync {
            ensureConnection()
            
            // Create file handle
            FileManager.default.createFile(atPath: fileUrl.path, contents: nil)
            let handle = try FileHandle(forWritingTo: fileUrl)
            defer { try? handle.close() }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "FlightRecorder", code: 500, userInfo: ["msg": "Prep failed"])
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let textPtr = sqlite3_column_text(stmt, 0) {
                    let json = String(cString: textPtr)
                    if let data = (json + "\n").data(using: .utf8) {
                        try? handle.write(data)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Dumps all blobs as individual files in the target directory.
    func dumpBlobs(to dirUrl: URL) throws {
        let sql = "SELECT hash_id, payload_bytes, blob_type FROM blobs;"
        var stmt: OpaquePointer?
        
        try queue.sync {
            ensureConnection()
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let hashPtr = sqlite3_column_text(stmt, 0),
                      let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
                
                let hash = String(cString: hashPtr)
                let bytes = sqlite3_column_bytes(stmt, 1)
                let data = Data(bytes: blobPtr, count: Int(bytes))
                
                // Filename: hash (e.g., a1b2...CANDLES_OHLCV)
                let fileUrl = dirUrl.appendingPathComponent(hash)
                try? data.write(to: fileUrl)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Aggressive Cleanup (Storage Optimization)
    
    /// Agresif temizlik - Eski verileri siler, depolama alanını küçültür
    /// - Parameters:
    ///   - maxBlobAgeDays: Blob'ları bu günden eski ise sil (varsayılan: 3)
    ///   - maxEventAgeDays: Event'leri bu günden eski ise sil (varsayılan: 7)
    ///   - maxTradeAgeDays: Trade'leri bu günden eski ise sil (varsayılan: 30)
    func aggressiveCleanup(maxBlobAgeDays: Int = 3, maxEventAgeDays: Int = 7, maxTradeAgeDays: Int = 30) async -> CleanupResult {
        return await withCheckedContinuation { (continuation: CheckedContinuation<CleanupResult, Never>) in
            queue.async {
                self.ensureConnection()
                
                var deletedBlobs = 0
                var deletedEvents = 0
                var deletedTrades = 0
                var freedBytes: Int64 = 0
                
                // 1. Eski blob'ları sil
                let blobCutoff = Date().addingTimeInterval(-Double(maxBlobAgeDays) * 24 * 60 * 60).iso8601
                let deleteBlobsSql = "DELETE FROM blobs WHERE created_at_utc < '\(blobCutoff)';"
                
                // Önce boyutu hesapla
                let sizeSql = "SELECT SUM(size_bytes) FROM blobs WHERE created_at_utc < '\(blobCutoff)';"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, sizeSql, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        freedBytes += sqlite3_column_int64(stmt, 0)
                    }
                }
                sqlite3_finalize(stmt)
                
                // Blob'ları sil
                if sqlite3_prepare_v2(self.db, deleteBlobsSql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_step(stmt)
                    deletedBlobs = Int(sqlite3_changes(self.db))
                }
                sqlite3_finalize(stmt)
                
                // 2. Eski event'leri sil
                let eventCutoff = Date().addingTimeInterval(-Double(maxEventAgeDays) * 24 * 60 * 60).iso8601
                let deleteEventsSql = "DELETE FROM events WHERE event_time_utc < '\(eventCutoff)';"
                
                if sqlite3_prepare_v2(self.db, deleteEventsSql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_step(stmt)
                    deletedEvents = Int(sqlite3_changes(self.db))
                }
                sqlite3_finalize(stmt)
                
                // 3. VACUUM to reclaim space
                self.execute(sql: "VACUUM;")
                
                print("🧹 ArgusLedger Cleanup: \(deletedBlobs) blobs, \(deletedEvents) events deleted. ~\(freedBytes / 1024 / 1024)MB freed.")
                
                continuation.resume(returning: CleanupResult(
                    deletedBlobs: deletedBlobs,
                    deletedEvents: deletedEvents,
                    deletedTrades: deletedTrades,
                    freedBytes: freedBytes
                ))
            }
        }
    }
    
    struct CleanupResult {
        let deletedBlobs: Int
        let deletedEvents: Int
        let deletedTrades: Int
        let freedBytes: Int64
        
        var summary: String {
            let mb = freedBytes / 1024 / 1024
            return "🧹 \(deletedBlobs) blob, \(deletedEvents) event silindi. ~\(mb)MB kazanıldı."
        }
    }
    
    /// Uygulama başlangıcında otomatik çağrılmalı
    func autoCleanupIfNeeded() async {
        // Son temizlikten 24 saat geçtiyse çalıştır
        let lastCleanupKey = "ArgusLedger_lastCleanup"
        let lastCleanup = UserDefaults.standard.object(forKey: lastCleanupKey) as? Date ?? .distantPast
        
        if Date().timeIntervalSince(lastCleanup) > 24 * 60 * 60 {
            let result = await aggressiveCleanup()
            print(result.summary)
            UserDefaults.standard.set(Date(), forKey: lastCleanupKey)
        }
    }
}
