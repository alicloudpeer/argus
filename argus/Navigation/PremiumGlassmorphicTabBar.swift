import SwiftUI

/// Alt tab bar + merkez Argus Voice butonu.
///
/// 2026-04-30 H-55 — çentikli tab bar:
///   • Bar artık ekran altına tam monte (horizontal padding yok, alt
///     safe area dahil), tam genişlikte. Üst köşeler radius 18, alt
///     köşeler 0 — ekrana yapışık dock görünümü.
///   • Üst kenarda ortada yumuşak yarım daire çukur (`NotchedBarShape`).
///     Çukur FAB çapından geniş, FAB ile bar arasında ~8px hava boşluğu
///     her yönde — top hiçbir yere temas etmiyor, çukurun içinde
///     havada duruyor.
///   • FAB (Argus Voice) — 48pt dairesel ArgusAppIcon, çukurun
///     ortasına oturuyor, üst kenarı bar üst yüzeyiyle aynı seviyede
///     (yukarı taşmıyor).
struct PremiumGlassmorphicTabBar: View {
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @EnvironmentObject var router: NavigationRouter

    // 2026-04-30 H-56 — çentik iptal. Düz bar, üst köşeleri yumuşak,
    // alta monte. FAB orijinal pozisyonda (bar üst kenarına ortalı,
    // yarısı yukarıda yarısı bar düzeyinde).
    private let fabSize: CGFloat = 56
    private let barHeight: CGFloat = 64

    private var allTabs: [TabItem] { TabItem.allCases }

    var body: some View {
        ZStack(alignment: .top) {
            // Düz tab bar — alt safe area'ya monte, üst köşeleri yumuşak
            HStack(spacing: 0) {
                ForEach(Array(allTabs.prefix(2)), id: \.self) { tab in
                    PremiumTabBarButton(
                        tab: tab,
                        isSelected: deepLinkManager.selectedTab == tab,
                        action: { selectTab(tab) }
                    )
                }
                Spacer().frame(width: 64)
                ForEach(Array(allTabs.suffix(2)), id: \.self) { tab in
                    PremiumTabBarButton(
                        tab: tab,
                        isSelected: deepLinkManager.selectedTab == tab,
                        action: { selectTab(tab) }
                    )
                }
            }
            .frame(height: barHeight)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 18, bottomLeading: 0,
                                       bottomTrailing: 0, topTrailing: 18),
                    style: .continuous
                )
                .fill(DesignTokens.Colors.surface)
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 18, bottomLeading: 0,
                                           bottomTrailing: 0, topTrailing: 18),
                        style: .continuous
                    )
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                )
                .ignoresSafeArea(edges: .bottom)
            )

            // FAB — bar üzerine ortalı, yarısı yukarıda
            argusVoiceButton
                .offset(y: -16)
        }
    }

    private var argusVoiceButton: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            NotificationCenter.default.post(name: NSNotification.Name("OpenArgusVoice"), object: nil)
        }) {
            Image("ArgusAppIcon")
                .resizable()
                .scaledToFill()
                .frame(width: fabSize, height: fabSize)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(InstitutionalTheme.Colors.holo.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Argus sesli komut")
    }

    private func selectTab(_ tab: TabItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            deepLinkManager.navigate(to: tab)
            router.popToRoot()
        }
    }
}

// MARK: - TabBarButton
//
// 2026-04-25 H-41: Sentence case label, mono caps tracking gitti.
// Seçili: holo (mavi), seçili olmayan: textSecondary.

struct PremiumTabBarButton: View {
    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))

                Text(tab.rawValue)
                    .font(DesignTokens.Fonts.custom(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected
                             ? InstitutionalTheme.Colors.holo
                             : DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        DesignTokens.Colors.backgroundDeep.ignoresSafeArea()
        VStack {
            Spacer()
            PremiumGlassmorphicTabBar()
                .environmentObject(NavigationRouter.shared)
        }
    }
}
