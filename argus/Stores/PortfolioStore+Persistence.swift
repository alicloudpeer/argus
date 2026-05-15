import Foundation

// MARK: - Persistence (FileManager + Debounce + V5→V6 Migration)
/// PortfolioStore'un disk I/O ve migration logic'i.
/// JSON format, 3 dosya (portfolio, transactions, balance), debounced save.
extension PortfolioStore {

    // MARK: - Documents Directory

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Save

    func saveToDisk() {
        // SAFETY CHECK: Never overwrite disk with uninitialized (-1) state
        if globalBalance < 0 || bistBalance < 0 {
            print("⚠️ PortfolioStore: Skipping Save (Balances not loaded yet)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let docs = getDocumentsDirectory()

        // 1. Save Trades
        do {
            let data = try encoder.encode(trades)
            try data.write(to: docs.appendingPathComponent(portfolioFileName), options: [.atomic])
        } catch {
            print("❌ PortfolioStore: Portfolio save failed: \(error)")
        }

        // 2. Save Transactions
        do {
            let data = try encoder.encode(transactions)
            try data.write(to: docs.appendingPathComponent(transactionsFileName), options: [.atomic])
        } catch {
            print("❌ PortfolioStore: Transactions save failed: \(error)")
        }

        // 3. Save Balances
        let balances = ["usd": globalBalance, "try": bistBalance]
        do {
            let data = try encoder.encode(balances)
            try data.write(to: docs.appendingPathComponent(balanceFileName), options: [.atomic])
        } catch {
            print("❌ PortfolioStore: Balance save failed: \(error)")
        }

        print("💾 PortfolioStore: Saved to Disk (V6) - USD: \(globalBalance)")

        // Sync with ArgusStorage (for Widget/AppGroup)
        ArgusStorage.shared.savePortfolio(trades)
    }

    /// Debounced disk yazma — çok sık yazma işlemlerini birleştirir.
    func scheduleDebouncedSave() {
        // Prevent saving if not loaded yet
        if globalBalance < 0 || bistBalance < 0 {
            return
        }

        saveWorkItem?.cancel()
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveToDisk()
        }
        if let workItem = saveWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
        }
    }

    /// O1: Uygulama background'a geçerken veya sonlanırken çağrılır.
    /// Bekleyen 1 sn'lik debounced save'i iptal eder ve diski anında yazar.
    ///
    /// **Neden:** `updateStops()` gibi mutasyonlar debounce kullanıyor; kullanıcı
    /// işlem yapar yapmaz uygulamayı background'a atarsa 1 sn'lik pencere içinde
    /// DispatchWorkItem henüz fire etmeden app suspend olabilir — sessiz veri kaybı.
    /// `flushNow()` bu pencereyi sıfıra indirir.
    func flushNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveToDisk()
    }

    // MARK: - Load + Migration

    func loadFromDisk() {
        let decoder = JSONDecoder()
        let docs = getDocumentsDirectory()

        let balanceFile = docs.appendingPathComponent(balanceFileName)
        let portfolioFile = docs.appendingPathComponent(portfolioFileName)
        let txFile = docs.appendingPathComponent(transactionsFileName)

        let balanceExists = FileManager.default.fileExists(atPath: balanceFile.path)
        let portfolioExists = FileManager.default.fileExists(atPath: portfolioFile.path)
        let txExists = FileManager.default.fileExists(atPath: txFile.path)

        // 1. Check for legacy migration ONLY if no V6 files exist at all
        if !balanceExists && !portfolioExists && !txExists {
            print("📂 PortfolioStore: No V6 files found. Attempting migration from V5...")
            migrateFromV5()
            return
        }

        print("🚀 PortfolioStore: Loading V6 Data (Granular Load)...")

        // 2. Load Balances
        if balanceExists {
            do {
                let data = try Data(contentsOf: balanceFile)
                let balances = try decoder.decode([String: Double].self, from: data)
                if let usd = balances["usd"], let tl = balances["try"] {
                    globalBalance = usd
                    bistBalance = tl
                    print("✅ PortfolioStore: Balances loaded: $\(usd) / ₺\(tl)")
                }
            } catch {
                print("❌ PortfolioStore: Balance Load FAILED: \(error)")
                // Do NOT reset to default. Keep -1 to prevent overwrite.
            }
        } else {
            print("⚠️ PortfolioStore: Balance file missing, but other V6 files exist.")
            globalBalance = 100_000.0
            bistBalance = 1_000_000.0
        }

        // 3. Load Trades
        if portfolioExists {
            do {
                let data = try Data(contentsOf: portfolioFile)
                trades = try decoder.decode([Trade].self, from: data)
                print("✅ PortfolioStore: \(trades.count) trades loaded")
            } catch {
                print("❌ PortfolioStore: Trades Load FAILED: \(error)")
            }
        }

        // 4. Load Transactions
        if txExists {
            do {
                let data = try Data(contentsOf: txFile)
                transactions = try decoder.decode([Transaction].self, from: data)
                print("✅ PortfolioStore: \(transactions.count) transactions loaded")
            } catch {
                print("❌ PortfolioStore: Transactions Load FAILED: \(error)")
            }
        }

        print("🏁 PortfolioStore: Load Complete - Trades: \(trades.count), USD: $\(globalBalance), TRY: ₺\(bistBalance)")

        runOneTimeGlobalReset()
        runOneTimeBistCurrencyFix()
    }

    /// Tek seferlik GLOBAL RESET (2026-04-21).
    /// Kullanıcı isteği: "Global portföyü sıfırla, $100k yatır, baştan başla."
    /// Flag UserDefaults'ta sadece bu build'de tetiklenir, çalıştıktan sonra
    /// kendini devre dışı bırakır. BIST'e dokunmaz.
    private func runOneTimeGlobalReset() {
        let resetFlagKey = "Argus_PendingGlobalReset_2026_04_21"
        let alreadyDone = UserDefaults.standard.bool(forKey: resetFlagKey)
        guard !alreadyDone else { return }
        print("🚨 PortfolioStore: Pending Global Reset algılandı — yürütülüyor...")
        resetGlobalPortfolio()
        UserDefaults.standard.set(true, forKey: resetFlagKey)
        print("✅ PortfolioStore: Global reset tamamlandı, flag kapatıldı.")
    }

    /// Tek seferlik migration: `.IS` suffix'li ama USD etiketli eski trade'leri TRY'ye çek.
    /// BUG: SymbolResolver.isBistSymbol eskiden sadece whitelist'e bakıyordu; AYGAZ.IS,
    /// AGHOL.IS gibi liste dışı BIST sembolleri USD kaydediliyordu.
    private func runOneTimeBistCurrencyFix() {
        let bistCurrencyFixKey = "Argus_BistCurrencyFix_2026_04_23"
        let bistFixDone = UserDefaults.standard.bool(forKey: bistCurrencyFixKey)
        guard !bistFixDone else { return }

        var relabeled = 0
        for idx in trades.indices where trades[idx].symbol.uppercased().hasSuffix(".IS") && trades[idx].currency != .TRY {
            trades[idx].currency = .TRY
            relabeled += 1
        }
        if relabeled > 0 {
            print("🔧 PortfolioStore: \(relabeled) BIST trade USD→TRY'ye taşındı.")
            saveToDisk()
        }
        UserDefaults.standard.set(true, forKey: bistCurrencyFixKey)
    }

    private func migrateFromV5() {
        let decoder = JSONDecoder()
        var migrationSuccess = false

        // Migrate Balances
        if let usd = UserDefaults.standard.object(forKey: legacyGlobalBalanceKey) as? Double {
            globalBalance = usd
            migrationSuccess = true
        }
        if let tl = UserDefaults.standard.object(forKey: legacyBistBalanceKey) as? Double {
            bistBalance = tl
            migrationSuccess = true
        }

        // Migrate Trades
        if let data = UserDefaults.standard.data(forKey: legacyPortfolioKey),
           let v5Trades = try? decoder.decode([Trade].self, from: data) {
            trades = v5Trades
            print("📦 PortfolioStore: Migrated \(trades.count) trades from V5")
            migrationSuccess = true
        }

        // Migrate Transactions
        if let data = UserDefaults.standard.data(forKey: legacyTransactionsKey),
           let v5Tx = try? decoder.decode([Transaction].self, from: data) {
            transactions = v5Tx
        }

        if migrationSuccess {
            // Validate Logic: Defaults if still negative
            if globalBalance < 0 { globalBalance = 100_000.0 }
            if bistBalance < 0 { bistBalance = 1_000_000.0 }
            saveToDisk() // Create V6 files
            print("✅ PortfolioStore: V5 -> V6 Migration Successful")
        } else {
            // FRESH INSTALL
            print("🆕 PortfolioStore: No V5 data found. Fresh Install Defaults.")
            globalBalance = 100_000.0
            bistBalance = 1_000_000.0
            saveToDisk()
        }
    }
}
