import SwiftUI

// MARK: - ArgusCockpitView (in-place refactor — ArgusDesignKit v1)
//
// Trader Terminal: Global / Sirkiye (BIST) / Fonlar sekmesi + terminal listesi.
// Veri: TerminalViewModel.shared.terminalItems, ChironDataLakeService (loadLearningEvents).
// Korunur:
//   • ScoutStoriesBar, ChironCockpitWidget, ChironTerminalFeed, FundListView, ModuleHoloSheet
//   • TerminalControlBar / TerminalStockRow alt bileşen imzaları
//   • MarketTab enum (dışarıdan referans edilebilir)
//   • Drawer tüm item'ları ile aynı
// 2026-05-04 H-55: TerminalScoreBadge ve education* helper'ları silindi (ölü
// kod, V5 izi taşıyordu — MotorLogo + caps mono).
// Demo veri yok — boş liste ArgusEmptyState ile ifade edilir.

// Global Scope Enum (dışarıdan referans ediliyor)
enum MarketTab: String, CaseIterable {
    case global  = "Global"
    case bist    = "Sirkiye"
    case fonlar  = "Fonlar"
}

struct ArgusCockpitView: View {
    @ObservedObject private var terminal = TerminalViewModel.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    // Terminal State
    @State private var sortOption: TerminalSortOption = .councilScore
    @State private var hideLowQualityData: Bool = true
    @State private var searchText: String = ""
    @State private var selectedMarket: MarketTab = .global
    @State private var showDrawer = false

    // Overlay State
    @State private var selectedSymbolForModule: String? = nil
    @State private var selectedModuleType: ArgusSanctumView.ModuleType? = nil

    // Sort Options
    enum TerminalSortOption: String, CaseIterable, Identifiable {
        case councilScore = "Konsey / Divan"
        case orion        = "Orion / Tahta"
        case atlas        = "Atlas / Kasa"
        case prometheus   = "Prometheus"
        case potential    = "Potansiyel"

        var id: String { rawValue }
    }

    // Terminal liste — ViewModel'den
    var terminalData: [TerminalItem] {
        var items = terminal.terminalItems

        // 1. Market Filter
        switch selectedMarket {
        case .bist:   items = items.filter { $0.market == .bist }
        case .global: items = items.filter { $0.market == .global }
        case .fonlar: return []
        }

        // 2. Search
        if !searchText.isEmpty {
            items = items.filter { $0.symbol.localizedCaseInsensitiveContains(searchText) }
        }

        // 3. Quality Filter
        if hideLowQualityData {
            items = items.filter { $0.dataQuality >= 50 }
        }

        // 4. Sort — 2026-04-30 H-51:
        // Eski: tüm skorlar 0 ise alfabetik kalıyor, sıralama anlamsız
        // görünüyordu. Yeni: skoru olmayan (0/nil) hisseleri liste sonuna
        // at, gerçek sıralama tepede çalışsın.
        items.sort { a, b in
            switch sortOption {
            case .councilScore:
                let av = a.councilScore ?? 0, bv = b.councilScore ?? 0
                if av == 0 && bv != 0 { return false }
                if bv == 0 && av != 0 { return true }
                return av > bv
            case .orion:
                let av = a.orionScore ?? 0, bv = b.orionScore ?? 0
                if av == 0 && bv != 0 { return false }
                if bv == 0 && av != 0 { return true }
                return av > bv
            case .atlas:
                let av = a.atlasScore ?? 0, bv = b.atlasScore ?? 0
                if av == 0 && bv != 0 { return false }
                if bv == 0 && av != 0 { return true }
                return av > bv
            case .prometheus:
                let av = a.forecast?.changePercent ?? -999
                let bv = b.forecast?.changePercent ?? -999
                if av == -999 && bv != -999 { return false }
                if bv == -999 && av != -999 { return true }
                return av > bv
            case .potential:
                return a.symbol < b.symbol
            }
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                customTopBar

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                marketTabBar

                if selectedMarket == .fonlar {
                    FundListView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            TerminalControlBar(
                                sortOption: $sortOption,
                                hideLowQualityData: $hideLowQualityData,
                                count: terminalData.count,
                                selectedMarket: selectedMarket
                            )

                            if terminalData.isEmpty {
                                ArgusEmptyState(
                                    icon: "antenna.radiowaves.left.and.right.slash",
                                    title: "Veri bulunamadı",
                                    message: "Kriterlere uygun hisse bulunamadı. Kalite filtresini veya arama terimini değiştirmeyi dene."
                                )
                                .padding(.top, 16)
                            } else {
                                ForEach(terminalData) { item in
                                    Button {
                                        NavigationRouter.shared.navigate(to: .stockDetail(symbol: item.symbol))
                                    } label: {
                                        TerminalStockRow(
                                            item: item,
                                            onOrionTap: { openModule(.orion, for: item.symbol) },
                                            onAtlasTap: { openModule(.atlas, for: item.symbol) }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    Rectangle()
                                        .fill(DesignTokens.Colors.borderSubtle)
                                        .frame(height: 0.5)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.bottom, 80)
                    }
                }
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)

            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200)
            }

            // Holo Overlay
            if let module = selectedModuleType, let symbol = selectedSymbolForModule {
                ModuleHoloSheet(
                    module: module,
                    symbol: symbol,
                    onClose: {
                        withAnimation {
                            selectedModuleType = nil
                            selectedSymbolForModule = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onAppear {
            terminal.refreshTerminal()
        }
        .task {
            await terminal.bootstrapTerminalData()
        }
        .onChange(of: terminal.watchlist) { _ in
            terminal.refreshTerminal()
        }
    }

    // MARK: - Module Overlay

    private func openModule(_ type: ArgusSanctumView.ModuleType, for symbol: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            selectedSymbolForModule = symbol
            selectedModuleType = type
        }
    }

    // MARK: - Drawer

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        let dismiss = ArgusDrawerView.dismissClosure($showDrawer)

        return [
            ArgusDrawerView.commonScreensSection(dismiss: dismiss),
            ArgusDrawerView.DrawerSection(
                title: "Terminal",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Pazar: Global", subtitle: "Global liste", icon: "globe.asia.australia") {
                        selectedMarket = .global
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Pazar: BIST", subtitle: "Sirkiye liste", icon: "chart.bar") {
                        selectedMarket = .bist
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Pazar: Fonlar", subtitle: "Fon listesi", icon: "rectangle.stack") {
                        selectedMarket = .fonlar
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Sıralama: Konsey", subtitle: "Konsey skoru", icon: "crown") {
                        sortOption = .councilScore
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Sıralama: Orion", subtitle: "Teknik skor", icon: "waveform.path.ecg") {
                        sortOption = .orion
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Sıralama: Atlas", subtitle: "Temel skor", icon: "chart.bar") {
                        sortOption = .atlas
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Sıralama: Potansiyel", subtitle: "Sembol bazlı", icon: "sparkles") {
                        sortOption = .potential
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(
                        title: "Kalite Filtresi",
                        subtitle: hideLowQualityData ? "Açık" : "Kapalı",
                        icon: "line.3.horizontal.decrease.circle"
                    ) {
                        hideLowQualityData.toggle()
                        dismiss()
                    }
                ]
            ),
            ArgusDrawerView.commonToolsSection(openSheet: openSheet, dismiss: dismiss)
        ]
    }

    // MARK: - Market Tab Bar

    // MARK: - Custom top bar (2026-04-30 H-54)
    //
    // SwiftUI toolbar'ın varsayılan davranışı (44×44 frame'siz item, mono
    // caps başlık, tinted ikon) Portfolio / MarketView / Trade Brain ile
    // tutarsızdı. Yerine sade nav: 32×32 sade ikonlar, sentence case 17pt
    // medium başlık, tek satır.
    private var customTopBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(ArgusDrawerView.toggleAnimation) {
                    showDrawer = true
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .regular))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menü")

            Text(toolbarTitle)
                .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: {
                switch selectedMarket {
                case .fonlar:
                    Task { await FundDataManager.shared.refresh() }
                default:
                    terminal.refreshTerminal()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .regular))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yenile")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.background)
    }

    /// 2026-04-30 H-50 — sade. Mono caps tracking 1 + tab başına ayrı renk
    /// (mavi/kırmızı/yeşil) → MarketView ile aynı dil: 13pt sentence
    /// case + nötr beyaz altı çizgisi.
    @ViewBuilder
    private func tabButton(title: String, tab: MarketTab) -> some View {
        let isSelected = selectedMarket == tab
        Button(action: { withAnimation(.easeInOut(duration: 0.18)) { selectedMarket = tab } }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected
                                     ? DesignTokens.Colors.textPrimary
                                     : DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                Rectangle()
                    .fill(isSelected
                          ? DesignTokens.Colors.textPrimary
                          : Color.clear)
                    .frame(height: 1.5)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) sekmesi")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var marketTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Global",  tab: .global)
            tabButton(title: "Sirkiye", tab: .bist)
            tabButton(title: "Fonlar",  tab: .fonlar)
        }
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    /// 2026-04-30 H-50 — caps "GLOBAL TERMINAL / SİRKİYE KOKPİTİ /
    /// TEFAS FONLARI" → sentence case "Tarama / Sirkiye / Fonlar".
    private var toolbarTitle: String {
        switch selectedMarket {
        case .global: return "Tarama"
        case .bist:   return "Sirkiye"
        case .fonlar: return "Fonlar"
        }
    }
}

// MARK: - TerminalControlBar

struct TerminalControlBar: View {
    @Binding var sortOption: ArgusCockpitView.TerminalSortOption
    @Binding var hideLowQualityData: Bool
    let count: Int
    let selectedMarket: MarketTab

    private var accent: Color {
        selectedMarket == .bist
            ? DesignTokens.Colors.error
            : DesignTokens.Colors.primary
    }

    /// 2026-04-30 H-50 — sade. İki ayrı satır (count+tinted sort menü
    /// pill üstte, kalite toggle altta) → tek satır kompakt: sol "X hisse"
    /// muted, orta "Sırala" menü (sade text, capsule yok), sağ kalite
    /// toggle (label tek kelime). Padding küçüldü, hairline alt çizgisi
    /// kaldırıldı (Cockpit'in kendi tab bar'ı zaten ayraç koyuyor).
    var body: some View {
        HStack(spacing: 10) {
            Text("\(count) hisse")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .monospacedDigit()

            Spacer(minLength: 6)

            Menu {
                Picker("Sıralama", selection: $sortOption) {
                    ForEach(ArgusCockpitView.TerminalSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortLabel(for: sortOption))
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(DesignTokens.Fonts.custom(size: 9))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Sıralama menüsü")

            Toggle(isOn: $hideLowQualityData) {
                Text("Kalite")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .toggleStyle(SwitchToggleStyle(tint: InstitutionalTheme.Colors.aurora))
            .labelsHidden()
            .scaleEffect(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.background)
    }

    func sortLabel(for option: ArgusCockpitView.TerminalSortOption) -> String {
        guard selectedMarket == .bist else { return option.rawValue }
        switch option {
        case .councilScore: return "Divan Puani"
        case .orion:        return "Tahta (Teknik)"
        case .atlas:        return "Kasa (Temel)"
        case .prometheus:   return "Prometheus"
        case .potential:    return "Potansiyel"
        }
    }
}

// MARK: - TerminalStockRow (dumb component)

struct TerminalStockRow: View {
    let item: TerminalItem
    var onOrionTap: () -> Void
    var onAtlasTap: () -> Void

    /// 2026-04-30 H-51 — durumlu render. Console skoru 0 ise "Gözle 0%"
    /// gibi anlamsız bilgi yerine "Henüz analiz yok" muted; aksiyon ve
    /// score kolonları gizlenir. Sadece sembol/fiyat + günlük değişim
    /// kalır.
    var body: some View {
        HStack(spacing: 12) {
            symbolBlock
            if hasAnalysis {
                actionBlock
            } else {
                Text("Henüz analiz yok")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 4)
            dailyChangeBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var hasAnalysis: Bool {
        // Council, orion ya da atlas skorundan en az biri varsa analiz
        // var sayılır. Üçü de 0/nil ise hisse henüz işlenmedi.
        let council = item.councilScore ?? 0
        let orion = item.orionScore ?? 0
        let atlas = item.atlasScore ?? 0
        return council > 0 || orion > 0 || atlas > 0
    }

    // MARK: - Symbol + price

    private var symbolBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.symbol.replacingOccurrences(of: ".IS", with: ""))
                .font(DesignTokens.Fonts.custom(size: 15, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            Text(priceText)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(minWidth: 70, alignment: .leading)
    }

    private var priceText: String {
        guard item.price > 0 else { return "—" }
        let currency = item.currency == .TRY ? "₺" : "$"
        return String(format: "\(currency)%.2f", item.price)
    }

    // MARK: - Aksiyon + güven + iki score

    /// 2026-04-30 H-51 — sadece dolu skorları göster. Council 0 ise
    /// aksiyon satırı yerine ne varsa onu (T/B skoru) tek satır göster.
    /// "T —" / "B —" boş slotları gösterilmez.
    private var actionBlock: some View {
        let council = item.councilScore ?? 0
        let orion = item.orionScore ?? 0
        let atlas = item.atlasScore ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            // Üst satır: aksiyon + güven (council varsa)
            if council > 0 {
                HStack(spacing: 6) {
                    Text(councilLabel(item.action))
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                        .foregroundColor(actionColor(item.action))
                    Text("\(Int(council * 100))%")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }
            }

            // Alt satır: sadece dolu skorlar
            HStack(spacing: 10) {
                if orion > 0 {
                    Button(action: onOrionTap) {
                        inlineScore(prefix: "T",
                                    score: orion,
                                    tone: InstitutionalTheme.Colors.Motors.orion)
                    }
                    .buttonStyle(.plain)
                }
                if atlas > 0 {
                    Button(action: onAtlasTap) {
                        inlineScore(prefix: "B",
                                    score: atlas,
                                    tone: InstitutionalTheme.Colors.Motors.atlas)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineScore(prefix: String, score: Double, tone: Color) -> some View {
        HStack(spacing: 3) {
            Text(prefix)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                .foregroundColor(tone)
            Text("\(Int(score))")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - Günlük değişim

    private var dailyChangeBlock: some View {
        let change = item.dayChangePercent
        let color: Color = (change ?? 0) >= 0
            ? DesignTokens.Colors.success
            : DesignTokens.Colors.error
        return Group {
            if let c = change {
                Text(String(format: "%+.1f%%", c))
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
    }

    // MARK: Helpers

    func actionColor(_ action: ArgusAction) -> Color {
        switch action {
        case .aggressiveBuy: return DesignTokens.Colors.success
        case .accumulate:    return DesignTokens.Colors.primary
        case .neutral:       return DesignTokens.Colors.textSecondary
        case .trim:          return InstitutionalTheme.Colors.warning
        case .liquidate:     return DesignTokens.Colors.error
        }
    }

    /// 2026-04-30 H-50 — "KONSEY HÜCUM" caps mono → sentence kısa kelime.
    /// "Konsey" prefix'i her satırda gereksiz tekrar olduğundan kaldırıldı.
    func councilLabel(_ action: ArgusAction) -> String {
        switch action {
        case .aggressiveBuy: return "Hücum"
        case .accumulate:    return "Topla"
        case .neutral:       return "Gözle"
        case .trim:          return "Azalt"
        case .liquidate:     return "Çık"
        }
    }

    // 2026-05-04 H-55 — ölü helper'lar (educationLevel / educationTitle /
    // educationColor) silindi. "VERI ZAYIF / ERKEN SINYAL / KARISIK / GUCLU /
    // TEYITLI" caps mono etiketleri TerminalStockRow'da çağrılmıyordu;
    // aksiyon (Hücum / Topla / Gözle / Azalt / Çık) + güven% sentence case
    // dilinde aynı işi zaten yapıyor.
}

// 2026-05-04 H-55 — TerminalScoreBadge silindi. Hiçbir yerden çağrılmıyordu
// (BistMarketView'daki referans yorum satırıydı, gerçek call yok). MotorLogo
// + caption2 mono + tracking 0.6 ile V5 izi taşıyordu; yerine
// TerminalStockRow.inlineScore (T/B sade prefix + sayı) kullanılıyor.
