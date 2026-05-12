import SwiftUI

// MARK: - PortfolioView (in-place refactor — ArgusDesignKit v1)
//
// Veri: viewModel.globalPortfolio/bistOpenPortfolio/quotes/planAlerts + PositionPlanStore/ExecutionStateViewModel.
// Korunur: LiquidDashboardHeader, TradeBrainStatusBand, DailyAgendaView, PortfolioPlanBoard,
// PortfolioReportsView, UnifiedPositionCard, TradeBrainAlertBanner, SystemInfoCard, HolographicBalanceCard,
// AssetChipView, CompanyLogoView, NewTradeSheet+TradeDetailSheet+TransactionHistorySheet+TradeBrainView
// +PlanEditorSheet sheet'leri, drawer 3 bölümü ve tüm item'ları.
// Demo veri sıfır — boş durumlar ArgusEmptyState ile anlatılır.

struct PortfolioView: View {
    @ObservedObject private var market = MarketViewModel.shared
    @ObservedObject private var execution = ExecutionStateViewModel.shared
    @ObservedObject private var portfolioStore = PortfolioStore.shared
    @ObservedObject private var autoPilotStore = AutoPilotStore.shared
    @State private var selectedEngine: AutoPilotEngineFilter = .all
    @State private var showNewTradeSheet = false
    @State private var showHistory = false
    @State private var selectedTrade: Trade?
    @State private var selectedMarket: TradeMarket = .global

    // Model Info State
    @State private var showModelInfo = false
    @State private var selectedEntityForInfo: ArgusSystemEntity = .corse
    @State private var showTradeBrain = false
    @State private var showDrawer = false
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    // Sell Logic
    @State private var showSellConfirmation = false
    @State private var tradeToSell: Trade?

    // Plan Editor Logic
    @State private var tradeToEdit: Trade?

    enum AutoPilotEngineFilter: String, CaseIterable {
        case all      = "Genel Bakış"
        case corse    = "Corse (Swing)"
        case pulse    = "Pulse (Scalp)"
        case scouting = "Gözcü (Canlı)"
    }

    // MARK: - Body

    var body: some View {
        // 2026-05-03 H-59: nested NavigationStack kaldırıldı.
        ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()

                if showDrawer {
                    ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                        drawerSections(openSheet: openSheet)
                    }
                    .zIndex(100)
                }

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            LiquidDashboardHeader(
                                selectedMarket: $selectedMarket,
                                onBrainTap:   { showTradeBrain = true },
                                onHistoryTap: { showHistory   = true },
                                onDrawerTap:  { withAnimation { showDrawer = true } }
                            )
                            .padding(.horizontal)
                            .padding(.top, 8)

                            // 2026-04-30 H-46 — sade Trade Brain band.
                            // Eski TradeBrainStatusBand + DailyAgendaView +
                            // PortfolioPlanBoard kombinasyonu (devasa) →
                            // tek satır kompakt özet, ayrıntılar Trade Brain
                            // ekranında.
                            tradeBrainBand
                                .padding(.horizontal)

                            PortfolioReportsView(mode: selectedMarket)

                            if selectedMarket == .global {
                                EngineSelector(selected: $selectedEngine)
                            }

                            tradeList
                                .padding(.horizontal)
                                .padding(.bottom, 100)
                        }
                    }
                }

                // FAB: Yeni İşlem
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showNewTradeSheet = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .frame(width: 56, height: 56)
                                .background(DesignTokens.Colors.primary)
                                .clipShape(Circle())
                                .shadow(color: DesignTokens.Colors.primary.opacity(0.35),
                                        radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Yeni işlem aç")
                        .padding()
                    }
                }

                if showModelInfo {
                    SystemInfoCard(entity: selectedEntityForInfo, isPresented: $showModelInfo)
                        .zIndex(100)
                }

                // 2026-04-30 H-46: Üstten düşen TradeBrainAlertBanner overlay
                // kaldırıldı. Aynı bilgiler şimdi iki yere yedirilmiş:
                // (1) ilgili pozisyon kartının altında inline alert satırı
                //     (UnifiedPositionCard'a alerts parametresi geçer)
                // (2) Trade Brain status band'inde toplam sayı + özet
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewTradeSheet) {
                NewTradeSheet()
                    .presentationDetents([.fraction(0.6)])
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $selectedTrade) { trade in
                TradeDetailSheet(trade: trade)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showHistory) {
                TransactionHistorySheet(marketMode: selectedMarket)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showTradeBrain) {
                TradeBrainView()
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $tradeToEdit) { trade in
                if let plan = PositionPlanStore.shared.getPlan(for: trade.id) {
                    PlanEditorSheet(
                        trade: trade,
                        currentPrice: market.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice,
                        plan: plan
                    )
                    .preferredColorScheme(.dark)
                } else {
                    Text("Plan yüklenemedi.")
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .preferredColorScheme(.dark)
                }
            }
            .alert("Satış Emri", isPresented: $showSellConfirmation) {
                Button("Sat", role: .destructive) {
                    if let trade = tradeToSell {
                        PortfolioStore.shared.sell(
                            tradeId: trade.id,
                            currentPrice: market.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice,
                            reason: "Portfolio User manual sell"
                        )
                    }
                }
                Button("İptal", role: .cancel) { }
            } message: {
                if let trade = tradeToSell {
                    Text("\(trade.symbol) pozisyonunu kapatmak istiyor musunuz?")
                } else {
                    Text("Pozisyon satılsın mı?")
                }
            }
    }

    // MARK: - Trade List

    @ViewBuilder
    private var tradeList: some View {
        LazyVStack(spacing: 16) {
            if selectedMarket == .global {
                globalList
            } else {
                bistList
            }
        }
    }

    @ViewBuilder
    private var globalList: some View {
        if selectedEngine == .all {
            let openTrades = portfolioStore.globalOpenTrades
            if !openTrades.isEmpty {
                ForEach(openTrades) { trade in
                    positionCard(for: trade, market: .global)
                }
            } else {
                EmptyPortfolioState()
            }
        } else if selectedEngine == .scouting {
            let scoutLogs = autoPilotStore.scoutLogs.filter { !$0.symbol.contains(".E") }
            if !scoutLogs.isEmpty {
                ForEach(scoutLogs.sorted(by: { $0.timestamp > $1.timestamp }), id: \.id) { log in
                    ScoutHistoryRow(log: log)
                }
            } else {
                ArgusEmptyState(
                    icon: "binoculars.fill",
                    title: "Gözcü Taraması Bekleniyor",
                    message: "Canlı tarama sonuçları burada listelenecek."
                )
                .padding(.top, 24)
            }
        } else {
            let targetEngine: AutoPilotEngine? = (selectedEngine == .corse) ? .corse : .pulse
            let filtered = portfolioStore.globalOpenTrades.filter { $0.engine == targetEngine }
            if !filtered.isEmpty {
                ForEach(filtered) { trade in
                    positionCard(for: trade, market: .global)
                }
            } else {
                ArgusEmptyState(
                    icon: "gauge.medium",
                    title: "\(selectedEngine.rawValue)",
                    message: "Bu motorda şu an açık işlem yok."
                )
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private var bistList: some View {
        if !portfolioStore.bistOpenTrades.isEmpty {
            ForEach(portfolioStore.bistOpenTrades) { trade in
                positionCard(for: trade, market: .bist)
            }
        } else {
            ArgusEmptyState(
                icon: "case.fill",
                title: "BIST portföyün boş",
                message: "Piyasa ekranından BIST hissesi alabilirsin."
            )
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func positionCard(for trade: Trade, market tradeMarket: TradeMarket) -> some View {
        let symbolAlerts = execution.planAlerts.filter { $0.symbol == trade.symbol }
        UnifiedPositionCard(
            trade: trade,
            currentPrice: self.market.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice,
            market: tradeMarket,
            onEdit: { openPlanEditor(for: trade) },
            onSell: {
                tradeToSell = trade
                showSellConfirmation = true
            },
            alerts: symbolAlerts,
            onAlertDismiss: { alert in
                ExecutionStateViewModel.shared.planAlerts.removeAll { $0.id == alert.id }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selectedTrade = trade }
    }

    // MARK: - Trade Brain band (2026-04-30 H-46)
    //
    // Eski TradeBrainStatusBand + DailyAgendaView + PortfolioPlanBoard (3
    // dev component) yerine tek satır kompakt status band. Aktif uyarı
    // sayısı + ilk 2 özet + tıklayınca Trade Brain ekranı.

    @ViewBuilder
    private var tradeBrainBand: some View {
        let alerts = execution.planAlerts
        Button(action: { showTradeBrain = true }) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image("TradeBrainIcon")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .frame(width: 22, height: 22)
                    if hasHighPriorityAlert(alerts) {
                        Circle()
                            .fill(InstitutionalTheme.Colors.crimson)
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle().stroke(DesignTokens.Colors.surface, lineWidth: 1.5)
                            )
                            .offset(x: 1, y: -1)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Trade Brain")
                            .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        if !alerts.isEmpty {
                            Text("\(alerts.count) bildirim")
                                .font(DesignTokens.Fonts.custom(size: 11))
                                .foregroundColor(hasHighPriorityAlert(alerts)
                                                 ? InstitutionalTheme.Colors.crimson
                                                 : DesignTokens.Colors.textSecondary)
                        }
                    }
                    Text(tradeBrainSummary(alerts))
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hasHighPriorityAlert(_ alerts: [TradeBrainAlert]) -> Bool {
        alerts.contains { $0.priority == .high || $0.priority == .critical }
    }

    private func tradeBrainSummary(_ alerts: [TradeBrainAlert]) -> String {
        if alerts.isEmpty {
            return "Aktif uyarı yok · planları gör"
        }
        let symbols = Array(Set(alerts.map { $0.symbol })).prefix(2).joined(separator: " · ")
        let suffix = alerts.count > 2 ? " · …" : ""
        return "\(symbols)\(suffix)"
    }

    // MARK: - Plan Editor

    private func openPlanEditor(for trade: Trade) {
        if PositionPlanStore.shared.getPlan(for: trade.id) == nil {
            PositionPlanStore.shared.syncWithPortfolio(
                trades: [trade],
                grandDecisions: SignalStateViewModel.shared.grandDecisions
            )
        }
        tradeToEdit = trade
    }

    // MARK: - Drawer

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        var sections: [ArgusDrawerView.DrawerSection] = []

        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Ekranlar",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Ana Sayfa", subtitle: "Sinyal akisi", icon: "waveform.path.ecg") {
                        deepLinkManager.navigate(to: .home); showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Piyasalar", subtitle: "Market ekranı", icon: "chart.line.uptrend.xyaxis") {
                        deepLinkManager.navigate(to: .kokpit); showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Alkindus Merkez", subtitle: "Yapay zeka merkezi", icon: "AlkindusIcon") {
                        NavigationRouter.shared.navigate(to: .alkindusDashboard)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Ayarlar", subtitle: "Tercihler", icon: "gearshape") {
                        deepLinkManager.navigate(to: .settings); showDrawer = false
                    }
                ]
            )
        )

        var portfolioItems: [ArgusDrawerView.DrawerItem] = [
            ArgusDrawerView.DrawerItem(title: "Yeni Islem", subtitle: "Pozisyon ac", icon: "plus.circle") {
                showNewTradeSheet = true; showDrawer = false
            },
            ArgusDrawerView.DrawerItem(title: "Islem Gecmisi", subtitle: "Kapanan islemler", icon: "clock.arrow.circlepath") {
                showHistory = true; showDrawer = false
            },
            ArgusDrawerView.DrawerItem(title: "Trade Brain", subtitle: "Yönetim paneli", icon: "TradeBrainIcon") {
                showTradeBrain = true; showDrawer = false
            },
            ArgusDrawerView.DrawerItem(title: "Global Portfoy", subtitle: "Pazar degistir", icon: "globe") {
                selectedMarket = .global; showDrawer = false
            },
            ArgusDrawerView.DrawerItem(title: "BIST Portfoy", subtitle: "Pazar degistir", icon: "chart.bar") {
                selectedMarket = .bist; showDrawer = false
            }
        ]

        if selectedMarket == .global {
            portfolioItems.append(contentsOf: [
                ArgusDrawerView.DrawerItem(title: "Motor: Genel", subtitle: "Tum islemler", icon: "circle.grid.2x2") {
                    selectedEngine = .all; showDrawer = false
                },
                ArgusDrawerView.DrawerItem(title: "Motor: Corse", subtitle: "Swing", icon: "chart.line.uptrend.xyaxis") {
                    selectedEngine = .corse; showDrawer = false
                },
                ArgusDrawerView.DrawerItem(title: "Motor: Pulse", subtitle: "Scalp", icon: "bolt") {
                    selectedEngine = .pulse; showDrawer = false
                },
                ArgusDrawerView.DrawerItem(title: "Motor: Gozcu", subtitle: "Canli tarama", icon: "binoculars") {
                    selectedEngine = .scouting; showDrawer = false
                }
            ])
        }

        sections.append(ArgusDrawerView.DrawerSection(title: "Portföy", items: portfolioItems))
        sections.append(ArgusDrawerView.commonToolsSection(openSheet: openSheet))
        return sections
    }

    private func mapAndShowInfo(_ engine: AutoPilotEngine) {
        switch engine {
        case .corse:  selectedEntityForInfo = .corse
        case .pulse:  selectedEntityForInfo = .pulse
        case .shield: selectedEntityForInfo = .shield
        case .hermes: selectedEntityForInfo = .hermes
        case .manual: selectedEntityForInfo = .corse
        }
        withAnimation { showModelInfo = true }
    }
}

// MARK: - TransactionConsoleCard

struct TransactionConsoleCard: View {
    let txn: Transaction

    var isProfitable: Bool {
        guard let pnl = txn.pnl else { return false }
        return pnl >= 0
    }

    var statusColor: Color {
        if txn.type == .buy { return DesignTokens.Colors.primary }
        return isProfitable ? DesignTokens.Colors.success : DesignTokens.Colors.error
    }

    var body: some View {
        ArgusCard(style: .flat, padding: 12, cornerRadius: InstitutionalTheme.Radius.sm) {
            VStack(spacing: 10) {
                HStack {
                    Text(txn.symbol)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.Colors.textPrimary)

                    Spacer()

                    Text(txn.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(txn.type == .buy ? "[GİRİŞ]" : "[ÇIKIŞ]")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(statusColor)

                            if txn.type == .sell, let pnl = txn.pnl {
                                Text(pnl >= 0 ? "KAR" : "ZARAR")
                                    .font(.system(.caption2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(statusColor.opacity(0.18))
                                    .foregroundColor(statusColor)
                                    .clipShape(Capsule())
                            }
                        }

                        let currencySymbol = txn.symbol.hasSuffix(".IS") ? "₺" : "$"
                        Text("Vol: \(currencySymbol)\(String(format: "%.2f", txn.amount))")
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        let currencySymbol = txn.symbol.hasSuffix(".IS") ? "₺" : "$"
                        Text("@ \(currencySymbol)\(String(format: "%.2f", txn.price))")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(DesignTokens.Colors.textPrimary)

                        if txn.type == .sell {
                            if let pnl = txn.pnl, let pct = txn.pnlPercent {
                                HStack(spacing: 4) {
                                    Text("\(pnl >= 0 ? "+" : "")\(currencySymbol)\(String(format: "%.2f", pnl))")
                                        .monospacedDigit()
                                    Text("(\(String(format: "%.1f", pct))%)")
                                        .opacity(0.85)
                                        .monospacedDigit()
                                }
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(statusColor)
                            } else {
                                Text("—")
                                    .font(.caption)
                                    .foregroundColor(DesignTokens.Colors.textTertiary)
                            }
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .font(.caption)
                                .foregroundColor(DesignTokens.Colors.primary.opacity(0.85))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - EngineSelector

struct EngineSelector: View {
    @Binding var selected: PortfolioView.AutoPilotEngineFilter
    @Namespace private var animationNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PortfolioView.AutoPilotEngineFilter.allCases, id: \.self) { filter in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selected = filter
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: engineIcon(filter))
                            .font(.system(.caption, design: .default))
                            .fontWeight(selected == filter ? .bold : .regular)
                            .foregroundColor(
                                selected == filter
                                    ? engineColor(filter)
                                    : DesignTokens.Colors.textSecondary
                            )
                        Text(engineLabel(filter))
                            .font(DesignTokens.Fonts.custom(size: 13, weight: selected == filter ? .medium : .regular))
                            .foregroundColor(
                                selected == filter
                                    ? DesignTokens.Colors.textPrimary
                                    : DesignTokens.Colors.textSecondary
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(
                        Group {
                            if selected == filter {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(engineColor(filter).opacity(0.18))
                                    .matchedGeometryEffect(id: "selector", in: animationNamespace)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(engineLabel(filter))
                .accessibilityAddTraits(selected == filter ? .isSelected : [])
            }
        }
        .padding(4)
        .background(DesignTokens.Colors.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    func engineIcon(_ filter: PortfolioView.AutoPilotEngineFilter) -> String {
        switch filter {
        case .all:      return "square.grid.2x2.fill"
        case .corse:    return "clock.arrow.2.circlepath"
        case .pulse:    return "waveform.path.ecg"
        case .scouting: return "eye.circle.fill"
        }
    }

    /// 2026-05-05 H-67: caps mono ("GENEL/CORSE/PULSE/GÖZCÜ") → sentence.
    func engineLabel(_ filter: PortfolioView.AutoPilotEngineFilter) -> String {
        switch filter {
        case .all:      return "Tümü"
        case .corse:    return "Korse"
        case .pulse:    return "Pulse"
        case .scouting: return "Gözcü"
        }
    }

    func engineColor(_ filter: PortfolioView.AutoPilotEngineFilter) -> Color {
        switch filter {
        case .all:      return DesignTokens.Colors.primary
        case .corse:    return DesignTokens.Colors.primary
        case .pulse:    return DesignTokens.Colors.success
        case .scouting: return InstitutionalTheme.Colors.neutral
        }
    }
}

// 2026-05-05 H-67: ScoutCandidateCard, BistPortfolioHeader silindi.
// İkisi de hiçbir yerden çağrılmıyordu (ölü kod). V5 izleri taşıyorlardı:
//   • ScoutCandidateCard: "GÖZCÜ ONAYI" caps mono tracking 0.8 capsule
//   • BistPortfolioHeader: kırmızı LinearGradient hero kart + "BIST
//     PORTFÖY DEĞERİ / KAR/ZARAR / KULLANILABİLİR BAKİYE" caps mono
//     tracking 1.2 + "BIST" 9pt black mono capsule
// PortfolioView body'si LiquidDashboardHeader (Tier #33) kullanıyor;
// BIST portföyü için ayrı bir header'a gerek yok, market segmenti
// LiquidDashboardHeader'da binding ile çalışıyor.

// MARK: - PortfolioHeader (legacy — HolographicBalanceCard sarmalayıcısı)

struct PortfolioHeader: View {
    var body: some View {
        HolographicBalanceCard()
            .padding(.horizontal)
            .padding(.top, 10)
    }
}

// MARK: - PortfolioCard (AssetChipView sarmalayıcısı)

struct PortfolioCard: View {
    let trade: Trade
    @Binding var selectedTrade: Trade?
    @ObservedObject private var market = MarketViewModel.shared

    var onInfoTap: ((AutoPilotEngine) -> Void)?

    var body: some View {
        Button(action: { selectedTrade = trade }) {
            ZStack(alignment: .topLeading) {
                AssetChipView(
                    symbol: trade.symbol,
                    quantity: trade.quantity,
                    currentPrice: market.quotes[trade.symbol]?.currentPrice,
                    entryPrice: trade.entryPrice,
                    engine: trade.engine
                )
            }
            .contextMenu {
                Button(role: .destructive) {
                    if let price = market.quotes[trade.symbol]?.currentPrice {
                        PortfolioStore.shared.sell(tradeId: trade.id, currentPrice: price)
                    }
                } label: {
                    Label("Pozisyonu Kapat", systemImage: "xmark.circle")
                }

                Button {
                    if let engine = trade.engine {
                        onInfoTap?(engine)
                    }
                } label: {
                    Label("Model Bilgisi", systemImage: "info.circle")
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - EmptyPortfolioState

struct EmptyPortfolioState: View {
    var body: some View {
        VStack(spacing: 20) {
            ArgusEmptyState(
                icon: "shippingbox",
                title: "Portföyün boş",
                message: "Yeni pozisyon açmak için sağ alttaki + butonuna dokunabilirsin."
            )
            EmptyPortfolioQuote()
                .padding(.top, 4)
                .padding(.horizontal, 16)
        }
    }
}


// MARK: - ScoutHistoryRow

struct ScoutHistoryRow: View {
    let log: ScoutLog

    var statusColor: Color {
        switch log.status {
        case "ONAYLI": return DesignTokens.Colors.success
        case "RED":    return DesignTokens.Colors.error
        case "BEKLE":  return InstitutionalTheme.Colors.neutral
        case "SATIŞ":  return DesignTokens.Colors.primary
        case "TUT":    return DesignTokens.Colors.textSecondary
        default:       return DesignTokens.Colors.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)
                .clipShape(Capsule())

            Text(log.symbol)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.status)
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.14))
                        .clipShape(Capsule())

                    Spacer()

                    Text("Puan: \(Int(log.score))")
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }

                Text(log.reason)
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }
}
