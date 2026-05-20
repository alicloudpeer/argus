import SwiftUI

extension NavigationRouter {
    @ViewBuilder
    func destinationView(for route: NavigationRoute) -> some View {
        switch route {
        // MARK: - Main Tabs
        case .kokpit:
            ArgusCockpitView()

        case .portfolio:
            PortfolioView()

        case .settings:
            SettingsView(settingsViewModel: SettingsViewModel())

        // MARK: - Alkindus Merkez
        case .alkindusDashboard:
            AlkindusDashboardView()

        // MARK: - Market Views
        case .stockDetail(let symbol):
            ArgusSanctumView(symbol: symbol)

        case .etfDetail(let symbol):
            ArgusEtfDetailView(symbol: symbol)

        case .bistMarket:
            BistMarketView()

        case .bistPortfolio:
            BistPortfolioView()

        case .tahta(let symbol):
            TahtaView(symbol: symbol)

        case .kasa(let symbol):
            BISTBilancoDetailView(sembol: symbol)

        case .rejim(let symbol):
            RejimView(symbol: symbol)

        // MARK: - Market Tools
        case .sectorDetail(let sector):
            SectorDetailRouterView(sectorName: sector)

        case .atlasDetail(let symbol):
            AtlasV2DetailView(symbol: symbol)

        case .poseidon:
            PoseidonRouterView()

        case .phoenix:
            // 2026-04-22: V5 redesign — legacy PhoenixView kaldırıldı,
            // Sanctum/Drawer'dan gelen `.phoenix` V5 görünümüne çıkıyor.
            PhoenixV5View()

        case .phoenixDetail(let id):
            PhoenixDetailRouterView(symbol: id)

        case .chiron:
            // 2026-05-03 H-59: nested NavigationStack kaldırıldı —
            // ContentView'daki dış NavigationStack(path: $router.navigationStack)
            // ile çakışıp geri butonunu bozuyordu. Push doğrudan ChironInsightsView.
            ChironInsightsView()

        case .chironDetail(let id):
            ChironInsightsView(symbol: id)

        case .chironPerformance:
            ChironPerformanceView()

        // MARK: - Analysis Views
        case .analystReport(let symbol):
            ArgusAnalystReportView(symbol: symbol)

        // MARK: - Discovery & Signals
        case .discover:
            DiscoverView()

        case .notifications:
            NotificationsView()

        case .tradeBrain:
            TradeBrainView()

        case .signals:
            SignalsView()

        case .hermesFeed:
            HermesFeedView()

        case .journalSignals:
            SignalJournalView()

        // MARK: - Observatory
        case .observatory:
            ObservatoryContainerView()

        case .observatoryHealth:
            ObservatoryHealthView()

        case .tradeHistory:
            TradeHistoryView()

        // MARK: - Settings Sub-views
        case .priceAlerts:
            PriceAlertSettingsView()

        case .guide:
            ArgusGuideView()

        case .voice:
            ArgusVoiceView()

        // MARK: - Watchlist & Aether
        case .aetherDetail(let id):
            AetherDetailRouterView(id: id)

        case .aetherDashboard:
            AetherDetailRouterView(id: "GLOBAL")

        // MARK: - Council & Debate
        case .symbolDebate(let symbol):
            SymbolDebateRouterView(symbol: symbol)

        // MARK: - Legacy/Specialty Views
        case .splash:
            SplashScreenView(onFinished: {})

        case .intro:
            ArgusIntroView(onFinished: {})

        case .disclaimer:
            DisclaimerView()

        case .expectationsEntry:
            ExpectationsEntryView()

        case .myPredictions:
            MyPredictionsView()

        case .roadmap:
            RoadmapView()

        case .immersiveChart(let symbol):
            ArgusImmersiveChartView(symbol: symbol)

        // MARK: - Components/Detail Sheets
        case .intelligenceCards(let symbol):
            IntelligenceCardsRouterView(symbol: symbol)

        case .fundList:
            FundListView()

        // MARK: - Heimdall/Admin Views
        case .heimdallDashboard:
            HeimdallDashboardView()

        case .heimdallKeys:
            HeimdallKeysView()

        // MARK: - Sirkiye Views
        case .sirkiyeDashboard:
            SirkiyeDashboardView()

        case .sirkiyeAether:
            SirkiyeAetherView()

        // MARK: - Görev Günlüğü
        case .gorevGunlugu:
            GorevGunluguView()

        }
    }
}
