import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppStateCoordinator
    @ObservedObject private var planStore = PositionPlanStore.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @StateObject private var router = NavigationRouter.shared
    @StateObject private var settingsViewModel = SettingsViewModel()

    // Voice Sheet State
    @State private var showVoiceSheet = false

    var body: some View {
        ZStack {
            // Global Living Background (Design System Base)
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // Background Animation Layer
            ArgusGlobalBackground()
                .opacity(0.16)
                .zIndex(0)


            // 2026-04-22 Sprint 2: V5 layout — NavigationStack tam ekran,
            // AppTabBar alt overlay (safe area inset). Eski VStack + Divider
            // yapısı artık pill-shaped V5 tab bar'ını kesiyordu.
            NavigationStack(path: $router.navigationStack) {
                Group {
                    switch deepLinkManager.selectedTab {
                    case .home:
                        MarketView()
                    case .kokpit:
                        ArgusCockpitView()
                    case .portfolio:
                        PortfolioView()
                    case .settings:
                        SettingsView(settingsViewModel: settingsViewModel)
                    }
                }
                .navigationDestination(for: NavigationRoute.self) { route in
                    router.destinationView(for: route)
                }
                // İçerik alt tab bar + FAB yüksekliği kadar padding
                .safeAreaInset(edge: .bottom) {
                    AppTabBar()
                        .environmentObject(router)
                }
            }
            // Tab değişiminde NavigationStack'i sıfırla (back stack temizle)
            // Önceden .id(selectedTab) ile tüm NavigationStack yok edilip yeniden oluşturuluyordu;
            // bu her tab geçişinde view'ların tamamen rebuild olmasına ve .onAppear/.task'ların
            // tekrar çalışmasına neden oluyordu. popToRoot ile aynı "fresh tab" davranışı,
            // view yıkımı olmadan sağlanır.
            .onChange(of: deepLinkManager.selectedTab) { _, _ in
                router.popToRoot()
            }

        }
        .sheet(item: $planStore.generatedSmartPlan) { plan in
            if let trade = PortfolioStore.shared.trades.first(where: { $0.id == plan.tradeId }) {
                PlanEditorSheet(
                    trade: trade,
                    currentPrice: MarketViewModel.shared.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice,
                    plan: plan
                )
                .preferredColorScheme(.dark)
            } else {
                ArgusEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Pozisyon bulunamadı",
                    message: "Smart Plan oluşturulmak istenen pozisyon artık portföyünüzde değil."
                )
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showVoiceSheet) {
            ArgusVoiceView()
                .preferredColorScheme(.dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenArgusVoice"))) { _ in
            showVoiceSheet = true
        }
        .sheet(item: $router.presentedSheet) { route in
            router.destinationView(for: route)
        }
        .fullScreenCover(item: $router.presentedFullScreen) { route in
            router.destinationView(for: route)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ArgusNotificationTapped"))) { notification in
            // Handle Deep Links
            if let id = notification.userInfo?["notificationId"] as? String {
                print("🔔 Argus Deep Link: ID found \(id)")
            }
            deepLinkManager.navigate(to: .home)
        }
        .onAppear {
            applyLaunchTabOverrideIfNeeded()
        }
        .environmentObject(router)
        .preferredColorScheme(.dark)
    }

    private func applyLaunchTabOverrideIfNeeded() {
        guard
            let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--argus-tab=") })
        else {
            return
        }

        let tabValue = argument.replacingOccurrences(of: "--argus-tab=", with: "")
        switch tabValue {
        case "home":
            deepLinkManager.navigate(to: .home)
        case "kokpit":
            deepLinkManager.navigate(to: .kokpit)
        case "portfolio":
            deepLinkManager.navigate(to: .portfolio)
        case "settings":
            deepLinkManager.navigate(to: .settings)
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
