import SwiftUI
import Combine

enum NavigationRoute: Hashable, Identifiable {
    var id: Self { self }
    // MARK: - Main Tabs (TabItem ile aynı isimler — DeepLinkManager üstünden)
    case kokpit
    case portfolio
    case settings

    // MARK: - Alkindus Merkez (yapay zeka dashboard'u)
    // Önceden NavigationRoute.home kullanılıyordu ama TabItem.home (MarketView)
    // ile çakışıyordu. Ayrı isimle geçildi: net olarak Alkindus Merkez.
    case alkindusDashboard

    // MARK: - Market Views
    case stockDetail(symbol: String)
    case etfDetail(symbol: String)
    case bistMarket
    case bistPortfolio
    case tahta(symbol: String)
    case kasa(symbol: String)
    case rejim(symbol: String)

    // MARK: - Market Tools
    case sectorDetail(sector: String)
    case atlasDetail(symbol: String)
    case poseidon
    case phoenix
    case phoenixDetail(id: String)
    case chiron
    case chironDetail(id: String)
    case chironPerformance

    // MARK: - Analysis Views
    case analystReport(symbol: String)

    // MARK: - Discovery & Signals
    case discover
    case notifications
    case tradeBrain
    case signals
    case hermesFeed
    case journalSignals

    // MARK: - Observatory & History
    case observatory
    case observatoryHealth
    case tradeHistory

    // MARK: - Settings Sub-views
    case priceAlerts
    case guide
    case voice

    // MARK: - Watchlist & Aether
    case aetherDetail(id: String)
    case aetherDashboard

    // MARK: - Council & Debate
    case symbolDebate(symbol: String)

    // MARK: - Legacy/Specialty Views
    case splash
    case intro
    case disclaimer
    case expectationsEntry
    case myPredictions  // 2026-05-06: Tahminlerim — drawer'dan doğrudan erişim
    case roadmap
    case immersiveChart(symbol: String)

    // MARK: - Components/Detail Sheets
    case intelligenceCards(symbol: String)
    case fundList

    // MARK: - Heimdall/Admin Views
    case heimdallDashboard
    case heimdallKeys

    // MARK: - Sirkiye Views
    case sirkiyeDashboard
    case sirkiyeAether
}

@MainActor
class NavigationRouter: ObservableObject {
    @Published var navigationStack: [NavigationRoute] = []
    @Published var presentedSheet: NavigationRoute?
    @Published var presentedFullScreen: NavigationRoute?

    static let shared = NavigationRouter()

    private init() {}

    func navigate(to route: NavigationRoute) {
        navigationStack.append(route)
    }

    func pop() {
        if !navigationStack.isEmpty {
            navigationStack.removeLast()
        }
    }

    func popToRoot() {
        navigationStack.removeAll()
    }

    func presentSheet(_ route: NavigationRoute) {
        presentedSheet = route
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func presentFullScreen(_ route: NavigationRoute) {
        presentedFullScreen = route
    }

    func dismissFullScreen() {
        presentedFullScreen = nil
    }

    func replace(with route: NavigationRoute) {
        navigationStack.removeLast()
        navigationStack.append(route)
    }
}
