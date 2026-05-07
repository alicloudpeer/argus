import Foundation

/// App startup orchestration — TradingViewModel.bootstrap()'tan taşındı.
/// Faz 1-4'lük lazy startup: UI'yı bloklamayan hızlı işlemlerden başlayıp
/// ağır Atlas/Demeter analizine kadar background priority sırasıyla ilerler.
extension AppStateCoordinator {

    /// Tek seferlik startup. Idempotent — birden fazla çağrı no-op.
    func bootstrap() {
        guard !Self.bootstrapDone else { return }
        Self.bootstrapDone = true

        let startTime = Date()
        let signpost = SignpostLogger.shared
        let id = signpost.begin(log: signpost.startup, name: "BOOTSTRAP")

        defer {
            signpost.end(log: signpost.startup, name: "BOOTSTRAP", id: id)
            let duration = Date().timeIntervalSince(startTime)
            ArgusLogger.bootstrapComplete(seconds: duration)
            Task { @MainActor in DiagnosticsViewModel.shared.recordBootstrapDuration(duration) }
        }

        // PHASE 1: HIZLI — UI'ı bloklamayan işlemler (~100ms hedef)
        // Stores (WatchlistStore, PortfolioStore) kendi kendilerine init oluyor.

        // Eski TVM.init()'te çağrılan one-shot işler:
        Task { @MainActor in
            EconomicCalendarService.shared.checkAndNotifyMissingExpectations()
        }

        // BorsaPy warm-up'ı erken başlat — Render.com free tier 40-60sn cold-start
        // verebiliyor. Eskiden Faz 3'te (5sn delay sonrası) çağrılıyordu;
        // kullanıcı bu pencerede BIST sembolüne tıklarsa ardı ardına timeout
        // alıp circuit breaker açılıyor → AutoPilot BIST alımı 5dk bloklanıyor.
        // Faz 1'de paralel başlatınca AutoPilot loop'u (Faz 3 + 5sn + 25sn defer)
        // çalışmaya başladığında backend uyanmış oluyor.
        Task.detached(priority: .userInitiated) {
            ArgusLogger.phase(.veri, "BorsaPy: Backend ısındırılıyor (erken)...")
            await BorsaPyProvider.shared.warmUp()
        }

        ArgusLogger.success(.bootstrap, "Faz 1: UI hazır")

        // PHASE 2: GECİKTİRİLMİŞ — Ağır işlemler background'da
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            await MainActor.run {
                let market = MarketViewModel.shared
                let risk = RiskViewModel.shared

                // RL-Lite: Tune System based on history
                ArgusFeedbackLoopService.shared.tuneSystem(history: risk.portfolio)

                // Enable Live Mode
                market.isLiveMode = true

                // Connect Stream for Watchlist
                ArgusLogger.phase(.veri, "Faz 2: Stream bağlanıyor...")
                MarketDataProvider.shared.connectStream(symbols: market.watchlist)

                // Initial data load — TVM.loadData()'dan taşındı.
                // Quotes startWatchlistLoop tarafından zaten immediate çekiliyor;
                // burada candle/macro/discover/losers paralel başlasın.
                ArgusLogger.phase(.veri, "Faz 2: Initial data load başlatılıyor...")
                market.loadMacroEnvironment()
                market.loadDiscoverData()
                Task { await market.fetchCandles() }
                Task { await market.fetchTopLosers() }
            }
        }

        // PHASE 3: LAZY — Scout/AutoPilot loop'ları daha geç
        // (BorsaPy warm-up Faz 1'e taşındı)
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            await MainActor.run {
                ArgusLogger.phase(.autopilot, "Faz 3: Scout döngüsü başlatılıyor...")
                SignalViewModel.shared.startScoutLoop()

                MarketViewModel.shared.startWatchlistLoop()

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    AutoPilotStore.shared.startAutoPilotLoop()
                }
            }
        }

        // PHASE 4: BACKGROUND — Atlas/Demeter (en ağır)
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            ArgusLogger.phase(.atlas, "Faz 4: Atlas/Demeter başlatılıyor...")
            await SignalViewModel.shared.hydrateAtlas()
            await SignalViewModel.shared.runDemeterAnalysis()

            await QuotaLedger.shared.reset(provider: "Finnhub")
            await QuotaLedger.shared.reset(provider: "Yahoo")
            await QuotaLedger.shared.reset(provider: "Yahoo Finance")
        }

        ArgusLogger.info(.bootstrap, "Lazy loading aktif")
    }

    private static var bootstrapDone: Bool = false
}
