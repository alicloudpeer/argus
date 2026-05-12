import Foundation
import Combine

// MARK: - PortfolioStore
/// Tek Gerçek Kaynak (Single Source of Truth) portföy yönetim sistemi.
/// BIST ve Global piyasalar ayrı bakiyeler, tek portföy listesi.
///
/// God Object Aşama B — Adım B.3: 942 LOC tek dosya → ana sınıf + 5 extension.
/// Davranış 1:1 korundu (PortfolioStoreSmokeTests 12/12 PASS).
/// - PortfolioStore.swift              (state + init + position/admin/cache)
/// - PortfolioStore+Trades.swift       (buy + sell + trim + trimByQuantity + updateStops)
/// - PortfolioStore+QuoteHandler.swift (handleQuoteUpdates + checkStopLoss + checkTakeProfit)
/// - PortfolioStore+Persistence.swift  (saveToDisk + loadFromDisk + migrateFromV5 + flushNow)
/// - PortfolioStore+Valuation.swift    (getGlobalEquity + PnL helpers)
@MainActor
final class PortfolioStore: ObservableObject {

    // MARK: - Singleton
    static let shared = PortfolioStore()

    // MARK: - Published State
    /// NOT: `private(set)` yerine `var` — extension'lar (Trades/QuoteHandler/Persistence)
    /// bu değerlere yazıyor. didSet → cache invalidation ana dosyada kalmalı.
    @Published var trades: [Trade] = [] {
        didSet {
            // CACHE PERFORMANCE: trades değiştiğinde filtered alt küme cache'lerini
            // bir kez hesapla. Önceden computed property'di ve PortfolioView,
            // DailyAgendaView, PortfolioPlanBoard, TradeBrainStatusBand gibi 6+
            // yerde body içinde her render'da .filter çalışıyordu. Artık tek
            // mutasyonla 4 cache güncellenir, view body'leri O(1) okuma yapar.
            recomputeFilteredCaches()
        }
    }
    @Published var globalBalance: Double = -1.0 // -1 denotes "Not Loaded"
    @Published var bistBalance: Double = -1.0   // -1 denotes "Not Loaded"
    @Published var transactions: [Transaction] = []

    // MARK: - Peak Equity Tracking (Drawdown Enforcement)
    @Published var peakGlobalEquity: Double = 0 {
        didSet { UserDefaults.standard.set(peakGlobalEquity, forKey: "argus_peak_global_equity") }
    }
    @Published var peakBistEquity: Double = 0 {
        didSet { UserDefaults.standard.set(peakBistEquity, forKey: "argus_peak_bist_equity") }
    }

    // MARK: - Cached Filtered Subsets (Performance)
    @Published private(set) var openTradesCache: [Trade] = []
    @Published private(set) var closedTradesCache: [Trade] = []
    @Published private(set) var globalOpenTradesCache: [Trade] = []
    @Published private(set) var bistOpenTradesCache: [Trade] = []

    private func recomputeFilteredCaches() {
        var open: [Trade] = []
        var closed: [Trade] = []
        var globalOpen: [Trade] = []
        var bistOpen: [Trade] = []
        open.reserveCapacity(trades.count)
        for trade in trades {
            if trade.isOpen {
                open.append(trade)
                if trade.currency == .USD { globalOpen.append(trade) }
                else if trade.currency == .TRY { bistOpen.append(trade) }
            } else {
                closed.append(trade)
            }
        }
        openTradesCache = open
        closedTradesCache = closed
        globalOpenTradesCache = globalOpen
        bistOpenTradesCache = bistOpen
    }

    /// Cache'lenmiş alt kümeler — geriye dönük uyumluluk için aynı isimle korunur.
    /// Doğrudan @Published cache'e forward eder; geri kalan kod değişiklik gerektirmez.
    var openTrades: [Trade] { openTradesCache }
    var closedTrades: [Trade] { closedTradesCache }
    var globalOpenTrades: [Trade] { globalOpenTradesCache }
    var bistOpenTrades: [Trade] { bistOpenTradesCache }

    // MARK: - Persistence Keys (V6 - FileManager)
    let portfolioFileName = "argus_portfolio_v6.json"
    let transactionsFileName = "argus_transactions_v6.json"
    let balanceFileName = "argus_balance_v6.json"

    // Legacy Keys for Migration
    let legacyPortfolioKey = "argus_portfolio_v5"
    let legacyGlobalBalanceKey = "argus_balance_usd_v5"
    let legacyBistBalanceKey = "argus_balance_try_v5"
    let legacyTransactionsKey = "argus_transactions_v5"

    // MARK: - Debounced Save Mechanism
    var saveWorkItem: DispatchWorkItem?
    let saveDebounceInterval: TimeInterval = 1.0

    // MARK: - Reentrancy Guard (QuoteHandler)
    /// O2: Fonksiyon-seviyesi reentrancy guard. Per-trade `isPendingSale` zaten
    /// aynı trade'in iki kez satılmasını önlüyor; bu flag ise iç `sell()` →
    /// @Published mutation → subscriber → yeniden `handleQuoteUpdates` zincirini
    /// kırıyor.
    var isHandlingQuoteUpdate: Bool = false

    // MARK: - Initialization

    private init() {
        print("🚀 PortfolioStore: Initializing (V6 FileManager)...")
        loadFromDisk()

        // Peak equity — UserDefaults'tan geri yükle (drawdown hesabı için)
        peakGlobalEquity = UserDefaults.standard.double(forKey: "argus_peak_global_equity")
        peakBistEquity = UserDefaults.standard.double(forKey: "argus_peak_bist_equity")
    }

    // MARK: - Add (lightweight mutators)

    func addTransaction(_ transaction: Transaction) {
        transactions.insert(transaction, at: 0)
        saveToDisk() // Will verify balance > 0 inside
        print("📝 PortfolioStore: Transaction logged: \(transaction.type.rawValue) \(transaction.symbol)")
    }

    func addTrade(_ trade: Trade) {
        trades.append(trade)
        scheduleDebouncedSave()
    }

    // MARK: - Balance Helpers

    func availableBalance(for symbol: String) -> Double {
        isBistSymbol(symbol) ? bistBalance : globalBalance
    }

    func availableBalance(currency: Currency) -> Double {
        currency == .TRY ? bistBalance : globalBalance
    }

    // MARK: - Position Helpers

    func getPosition(for symbol: String) -> [Trade] {
        openTrades.filter { $0.symbol == symbol }
    }

    func getTotalQuantity(for symbol: String) -> Double {
        getPosition(for: symbol).reduce(0) { $0 + $1.quantity }
    }

    func hasPosition(for symbol: String) -> Bool {
        openTrades.contains { $0.symbol == symbol }
    }

    // MARK: - Internal Helpers

    func isBistSymbol(_ symbol: String) -> Bool {
        SymbolResolver.shared.isBistSymbol(symbol)
    }

    // MARK: - Reset / Import

    func resetPortfolio() {
        trades = []
        transactions = []
        globalBalance = 100_000.0
        bistBalance = 1_000_000.0
        saveToDisk()
        print("🔄 PortfolioEngine: Reset complete (V6 FileManager)")
    }

    /// Sadece GLOBAL (USD) portföyü sıfırla — BIST'e dokunma.
    /// Tüm USD trade'leri ve USD cinsi transaction'ları sil, bakiyeyi $100k yap.
    func resetGlobalPortfolio() {
        print("🚨 PortfolioStore: GLOBAL PORTFÖY SIFIRLANIYOR...")
        let beforeTradeCount = trades.filter { $0.currency == .USD }.count
        let beforeTxCount = transactions.filter { !isBistSymbol($0.symbol) }.count
        trades.removeAll { $0.currency == .USD }
        transactions.removeAll { !isBistSymbol($0.symbol) }
        globalBalance = 100_000.0
        saveToDisk()
        print("🔄 PortfolioStore: Global reset — \(beforeTradeCount) trade + \(beforeTxCount) tx silindi, bakiye $100k")
        ArgusLogger.warn("🔄 Global portföy sıfırlandı — \(beforeTradeCount) pozisyon kapatıldı, bakiye $100k", category: "PORTFOLIO")
    }

    func resetBistPortfolio() {
        print("🚨 PortfolioStore: BIST PORTFÖYÜ SIFIRLANIYOR...")
        trades.removeAll { $0.currency == .TRY }
        transactions.removeAll { isBistSymbol($0.symbol) }
        bistBalance = 1_000_000.0
        saveToDisk()
    }

    /// Y5: VM facade bağımsız mutation yapmasın; snapshot import bu tek kanaldan geçer.
    /// Dışarıdan alınan parçalar nil olabilir (kısmi import); sadece sağlanan alanlar
    /// uygulanır. Side-effect: `@Published` yayınları tetikler ve sink üzerinden VM
    /// otomatik güncellenir. Disk'e yazma garanti.
    func importSnapshot(
        trades: [Trade]?,
        transactions: [Transaction]?,
        globalBalance: Double?,
        bistBalance: Double?
    ) {
        if let trades = trades { self.trades = trades }
        if let transactions = transactions { self.transactions = transactions }
        if let globalBalance = globalBalance { self.globalBalance = globalBalance }
        if let bistBalance = bistBalance { self.bistBalance = bistBalance }
        saveToDisk()
        print("📥 PortfolioStore: Snapshot import tamamlandı — trades:\(self.trades.count) tx:\(self.transactions.count)")
    }
}
