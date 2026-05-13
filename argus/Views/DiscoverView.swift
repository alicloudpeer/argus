import SwiftUI

/// V5 mockup dil bütünlüğü için in-place refactor.
/// 2026-04-22 Sprint 3 — üst chrome `ArgusNavHeader`'a alındı (bars3 deco +
/// menu/refresh action). Yükselenler/Düşenler/En Hareketliler bölümleri ve
/// card/row bileşenleri zaten V5 tokenize olduğundan korunur.
/// Veri imzası değişmez: `market.topGainers/topLosers/mostActive` +
/// `market.loadDiscoverData()`; drawer + deep link akışı dokunulmadı.
struct DiscoverView: View {
    @ObservedObject private var market = MarketViewModel.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showDrawer = false

    private var isPushed: Bool { !router.navigationStack.isEmpty }

    // Grid adaptation for horizontal scroll if needed, but HStacks work better for single row carousels.

    var body: some View {
        // 2026-05-03 H-59: nested NavigationStack kaldırıldı — ContentView
        // root'taki NavigationStack ile çakışıp back butonunu bozuyordu.
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                    ArgusNavHeader(
                        title: "Keşfet",
                        subtitle: "Momentum, dibe vuranlar ve hacim",
                        leadingDeco: isPushed ? .back(onTap: { dismiss() }) : .none,
                        actions: isPushed
                            ? [.custom(sfSymbol: "arrow.clockwise",
                                       action: { market.loadDiscoverData() })]
                            : [.menu({ withAnimation(ArgusDrawerView.toggleAnimation) { showDrawer = true } }),
                               .custom(sfSymbol: "arrow.clockwise",
                                       action: { market.loadDiscoverData() })]
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {

                        // 2026-04-30 H-50: ScoutStoriesBar Cockpit'ten taşındı.
                        // Argus'un keşfettikleri Discover'ın doğal bağlamı.
                        ScoutStoriesBar()
                            .padding(.bottom, 8)

                        // MARK: - 1. Top Gainers (Momentum)
                        VStack(alignment: .leading, spacing: 16) {
                            DiscoverSectionHeader(title: "Yükselenler", subtitle: "Günün momentum liderleri")
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(market.topGainers, id: \.symbol) { quote in
                                        Button { NavigationRouter.shared.navigate(to: .stockDetail(symbol: quote.symbol ?? "---")) } label: {
                                            DiscoverMarketCard(
                                                quote: quote,
                                                type: .gainer,
                                                onAddToWatchlist: { symbol in
                                                    market.addToWatchlist(symbol: symbol)
                                                }
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // MARK: - 2. Top Losers (Dip Opportunities)
                        VStack(alignment: .leading, spacing: 16) {
                            DiscoverSectionHeader(title: "Düşenler", subtitle: "Olası Phoenix adayları")
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(market.topLosers, id: \.symbol) { quote in
                                        Button { NavigationRouter.shared.navigate(to: .stockDetail(symbol: quote.symbol ?? "---")) } label: {
                                            DiscoverMarketCard(
                                                quote: quote,
                                                type: .loser,
                                                onAddToWatchlist: { symbol in
                                                    market.addToWatchlist(symbol: symbol)
                                                }
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // MARK: - 3. Most Active (Volume Leaders)
                        VStack(alignment: .leading, spacing: 16) {
                            DiscoverSectionHeader(title: "En Hareketliler", subtitle: "Hacim liderleri")
                                .padding(.bottom, 4)
                            
                            LazyVStack(spacing: 0) {
                                ForEach(market.mostActive, id: \.symbol) { quote in
                                    Button { NavigationRouter.shared.navigate(to: .stockDetail(symbol: quote.symbol ?? "---")) } label: {
                                        DiscoverMarketRow(quote: quote)
                                    }
                                    Divider()
                                        .background(DesignTokens.Colors.borderSubtle)
                                        .padding(.leading, 70)
                                }
                            }
                            .background(DesignTokens.Colors.surface)
                            .cornerRadius(InstitutionalTheme.Radius.lg)
                            .overlay(
                                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }
                        
                        // Bottom Padding for TabBar
                        Color.clear.frame(height: 100)
                        }
                    }
                    .padding(.top, 20)
                }
            }
        .navigationBarHidden(true)
        .presentationDragIndicator(.visible)
        .onAppear {
            market.loadDiscoverData()
        }
        .refreshable {
            market.loadDiscoverData()
        }
        .overlay {
            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200)
            }
        }
    }

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        let dismiss = ArgusDrawerView.dismissClosure($showDrawer)

        return [
            ArgusDrawerView.commonScreensSection(dismiss: dismiss),
            ArgusDrawerView.DrawerSection(
                title: "Keşfet",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Yenile", subtitle: "Listeyi güncelle", icon: "arrow.clockwise") {
                        market.loadDiscoverData()
                        dismiss()
                    }
                ]
            ),
            ArgusDrawerView.commonToolsSection(openSheet: openSheet, dismiss: dismiss)
        ]
    }
}

// MARK: - Components

struct DiscoverSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArgusSectionCaption(title)
            Text(subtitle)
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal)
    }
}

enum MarketCardType {
    case gainer
    case loser
}

struct DiscoverMarketCard: View {
    let quote: Quote
    let type: MarketCardType
    let onAddToWatchlist: (String) -> Void

    var tone: ArgusChipTone {
        type == .gainer ? .aurora : .crimson
    }
    var cardColor: Color { tone.foreground }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: type == .gainer ? "arrow.up.right" : "arrow.down.right")
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .bold))
                    .foregroundColor(cardColor)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(cardColor.opacity(0.18)))
                Spacer()
                Text(String(format: "%+.2f%%", quote.percentChange))
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(cardColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(cardColor.opacity(0.18))
                    )
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol ?? "---")
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                let isBist = (quote.symbol ?? "").uppercased().hasSuffix(".IS")
                Text(String(format: isBist ? "₺%.0f" : "$%.2f", quote.currentPrice))
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(12)
        .frame(width: 142, height: 112)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(cardColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
        .contextMenu {
            Button {
                if let symbol = quote.symbol, !symbol.isEmpty {
                    onAddToWatchlist(symbol)
                }
            } label: {
                Label("İzlemeye Ekle", systemImage: "eye.fill")
            }
        }
    }
}

struct DiscoverMarketRow: View {
    let quote: Quote
    
    // Helper for approximate volume string
    // Yahoo Quote struct doesn't strictly have volume in this simplified model usually, 
    // but assuming Quote struct might have it. 
    // If Quote struct in this project doesn't have `volume`, we omit it.
    // Let's check previously viewed code. `Quote` struct in `FundamentalModels.swift`.
    // Wait, `fetchQuote` returns `Quote`.
    // I recall `Quote` having `c`, `d`, `dp`.
    // If it doesn't have volume, we can simply show price.
    // I'll show symbol name/price.
    
    var body: some View {
        let changeColor: Color = quote.change >= 0
            ? InstitutionalTheme.Colors.aurora
            : InstitutionalTheme.Colors.crimson

        return HStack(spacing: 14) {
            // 2026-04-22 logo-fix-4: Dairesel CompanyLogoView kullan —
            // gradient fallback onun içinde; logo gelirse üstüne oturur.
            CompanyLogoView(symbol: quote.symbol ?? "?", size: 36, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol ?? "---")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                if let name = quote.shortName, !name.isEmpty {
                    Text(name)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                let isBist = (quote.symbol ?? "").uppercased().hasSuffix(".IS")
                Text(String(format: isBist ? "₺%.0f" : "$%.2f", quote.currentPrice))
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                Text(String(format: "%+.2f%%", quote.percentChange))
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(changeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(changeColor.opacity(0.18))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(ArgusHair(), alignment: .bottom)
        .contentShape(Rectangle())
    }
}
