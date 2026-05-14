import SwiftUI

// MARK: - ARGUS SANCTUM VIEW
/// Ana hisse detay ekrani - Argus Konseyi gorunum.
/// Theme ve modul tipleri SanctumTypes.swift'te tanimli.
struct ArgusSanctumView: View {
    let symbol: String
    @StateObject private var vm: SanctumViewModel
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @EnvironmentObject var router: NavigationRouter

    init(symbol: String) {
        self.symbol = symbol
        self._vm = StateObject(wrappedValue: SanctumViewModel(symbol: symbol))
    }

    @Environment(\.dismiss) private var dismiss

    // State
    @State private var selectedModule: SanctumModuleType? = nil
    @State private var selectedBistModule: SanctumBistModuleType? = nil
    @State private var showDecision = false
    @State private var showDrawer = false // Contextual Drawer State

    // Legacy type alias for internal references
    typealias ModuleType = SanctumModuleType
    typealias BistModuleType = SanctumBistModuleType

    // BIST Modülleri - Konsolidasyon sonrası
    // TAHTA = Grafik + MoneyFlow + RS (Teknik)
    // KASA = Bilanço + Faktör (Temel)
    // Diğer modüller aşamalı olarak REJİM'e taşınacak
    var bistModules: [BistModuleType] = [
        .tahta, // Teknik + Hacim + Takas -> Orion (Cyan)
        .kasa,  // Temel + Bilanço -> Atlas (Gold)
        .kulis, // Haber + Sentiment -> Hermes (Orange)
        .rejim  // Makro + Oracle + Sektör -> Aether (Purple)
    ]
    
    private var isBistSymbol: Bool {
        symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
    }
    
    private var activeDecision: ArgusGrandDecision? {
        vm.grandDecision ?? SignalStateViewModel.shared.grandDecisions[symbol]
    }

    @State private var showTradeSheet = false
    @State private var tradeAction: TradeAction = .buy
    @State private var hasAppliedLaunchOverride = false
    @State private var showArgusAnalysis = false

    // Faz 1.A.4 entegrasyon: toggle açıksa SanctumCouncilBody'nin altına Karar
    // Kartı V2 eklenir. Settings → Deneysel → "Karar Kartı V2" kontrol eder.
    // Default OFF → mevcut UI'a sıfır etki; opt-in kullanıcı görür.
    @AppStorage("karar_karti_v2_enabled") private var kararKartiV2Enabled = false
    @StateObject private var kararKartiVM = KararKartiViewModel()

    enum TradeAction { case buy, sell }

    /// MotorEngine → SanctumModuleType ters eşleşme (HoloPanel için).
    /// SanctumModuleType.motor zaten ileri yönde mevcut; biz tersini üretiyoruz.
    private func sanctumModule(from motor: MotorEngine) -> SanctumModuleType? {
        switch motor {
        case .atlas:      return .atlas
        case .orion:      return .orion
        case .aether:     return .aether
        case .hermes:     return .hermes
        case .athena:     return .athena
        case .demeter:    return .demeter
        case .chiron:     return .chiron
        case .prometheus: return .prometheus
        case .council:    return .council
        case .phoenix:    return .prometheus  // Phoenix = Tahmin altında Prometheus ile birleşik
        default:          return nil
        }
    }

    /// Faz 1.A entegrasyon: Aktif decision'ı KararKartiViewModel'e hazırlatır.
    /// `.task(id: decision.id)` sembol veya karar değiştiğinde tekrar tetikler.
    /// Eksik veriler (Demeter score, cluster count, AISignal) sonraki turn'de
    /// bağlanır; şimdilik primitive defaults — PremortemEngine nil-safe.
    private func prepareKararKartiV2(for decision: ArgusGrandDecision) async {
        let atlasMargin = decision.atlasDecision?.marginOfSafety
        // Aether stance → 0-100 makro skor eşlemesi (PremortemEngine kural 1).
        let aetherScore: Double = {
            switch decision.aetherDecision.stance {
            case .riskOn:    return 80
            case .cautious:  return 60
            case .defensive: return 35
            case .riskOff:   return 15
            }
        }()
        await kararKartiVM.prepare(
            from: decision,
            atlasMargin: atlasMargin,
            demeterScore: nil,           // Demeter wiring sonraki turn
            aetherScore: aetherScore,
            clusterCount: 0,              // PortfolioStore cluster lookup sonraki turn
            hasAISignalSupport: false,   // AISignal entegrasyon sonraki turn
            estimatedPositionTRY: 0      // TradeBrain tahmini sonraki turn
        )
    }

    var body: some View {
        ZStack {
            // 1. Background
            DesignTokens.Colors.background.ignoresSafeArea()
            SanctumTheme.bg.ignoresSafeArea()
            
            // 2. Main Content
            // 2. Main Content
            Group {
                if vm.isLoading && vm.quote == nil {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: DesignTokens.Colors.textPrimary))
                        
                        LoadingQuoteView()
                    }
                } else {
                    // 2026-04-25 H-36 — Sticky top nav + content scrollview.
                    // Top nav: back chevron + sembol/meta + Argus app-icon
                    // butonu (analiz aç) + drawer (line.3.horizontal). Eski
                    // floating backButtonOverlay kaldırıldı.
                    VStack(spacing: 0) {
                        sanctumTopNav
                        ScrollView {
                            VStack(spacing: 16) {
                                SanctumHeader(symbol: symbol, quote: vm.quote)
                                SanctumCouncilBody(
                                    symbol: symbol,
                                    decision: activeDecision,
                                    prometheusForecast: SignalViewModel.shared.prometheusForecastBySymbol[symbol],
                                    onOpenArgusAnalysis: {
                                        showArgusAnalysis = true
                                    },
                                    onSelectMotor: { motor in
                                        if let mod = sanctumModule(from: motor) {
                                            withAnimation(.spring()) {
                                                self.selectedModule = mod
                                            }
                                        }
                                    }
                                )

                                // Faz 1.A: Karar Kartı V2 (deneysel, default OFF).
                                // Settings'teki toggle açıksa ve aktif decision varsa,
                                // V2 görünür. ViewModel `.task(id:)` ile decision UUID
                                // değiştikçe (sembol/karar değişimi) yeniden hazırlanır.
                                if kararKartiV2Enabled, let decision = activeDecision {
                                    KararKartiV2View(viewModel: kararKartiVM)
                                        .task(id: decision.id) {
                                            await prepareKararKartiV2(for: decision)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .blur(radius: (selectedModule != nil || selectedBistModule != nil) ? 10 : 0)
            .scaleEffect((selectedModule != nil || selectedBistModule != nil) ? 0.95 : 1.0)
            .animation(.spring(), value: selectedModule)
            .animation(.spring(), value: selectedBistModule)
            
            // 4. HoloPanel (Module Details)
            if let module = selectedModule {
                HoloPanelView(
                    module: module,
                    vm: vm,
                    symbol: symbol,
                    router: router,
                    onClose: { withAnimation { selectedModule = nil } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }

            // 5. BIST HoloPanel
            if let bistMod = selectedBistModule {
                let normalizedBistMod: BistModuleType = (bistMod == .oracle) ? .rejim : bistMod

                let mappedModule: ModuleType = {
                    switch normalizedBistMod {
                    case .tahta: return .orion
                    case .kasa: return .atlas
                    case .kulis: return .hermes
                    case .rejim: return .aether
                    default: return .orion
                    }
                }()

                HoloPanelView(
                    module: mappedModule,
                    vm: vm,
                    symbol: symbol,
                    router: router,
                    onClose: { withAnimation { selectedBistModule = nil } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
            
            // 6. Sheets & Modals
            // Trade Action Panel (Flanking FAB - near tab bar)
            VStack {
                Spacer()
                if let quote = vm.quote, selectedModule == nil && selectedBistModule == nil {
                    SanctumTradePanel(
                        symbol: symbol,
                        currentPrice: quote.currentPrice,
                        onBuy: {
                            self.tradeAction = .buy
                            self.showTradeSheet = true
                        },
                        onSell: {
                            self.tradeAction = .sell
                            self.showTradeSheet = true
                        }
                    )
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom))
                }
            }
            .zIndex(90)

            // FAB REMOVED

            
            // LOCAL CONTEXTUAL DRAWER
            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200) // Highest Z-Index
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTradeSheet) {
            SanctumTradeSheet(
                symbol: symbol,
                action: tradeAction
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showArgusAnalysis) {
            ArgusAnalysisSheet(
                symbol: symbol,
                decision: activeDecision
            )
            .preferredColorScheme(.dark)
        }
        // Navigation via Router - Orphaned sheets removed, use router.navigate() instead
        .task {
            // Ensure data is loaded when view appears
            if vm.quote == nil || vm.grandDecision == nil {
                await vm.loadData()
            }
            if vm.grandDecision == nil {
                await vm.refresh()
            }
            await applyLaunchModuleOverrideIfNeeded()
        }
        .onAppear {
            // Re-apply after appearance in case parent navigation rebuilds the view.
            Task {
                await applyLaunchModuleOverrideIfNeeded()
            }
        }
    }
    
    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        let dismiss = ArgusDrawerView.dismissClosure($showDrawer)
        var sections: [ArgusDrawerView.DrawerSection] = []

        // 1) EKRANLAR — merkezi tanım
        sections.append(ArgusDrawerView.commonScreensSection(dismiss: dismiss))

        // 2) MERKEZLER — global motor dashboard'ları (V5 views).
        // Buradaki linkler symbol-context değil; Chiron/Aether/Phoenix'in
        // ağırlıklı genel görünümlerine yönlendirir.
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Merkezler",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Chiron Öğrenme",
                                               subtitle: "Ağırlıklar ve performans",
                                               icon: "ChironIcon") {
                        router.navigate(to: .chiron)
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Aether Makro",
                                               subtitle: "3 katman rejim analizi",
                                               icon: "AetherIcon") {
                        router.navigate(to: .aetherDashboard)
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Phoenix Anka",
                                               subtitle: "Geri dönüş adayları",
                                               icon: "flame.fill") {
                        router.navigate(to: .phoenix)
                        dismiss()
                    }
                ]
            )
        )

        // 3) HISSE İŞLEMLERI — mevcut sembole özgü aksiyonlar
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Hisse işlemleri",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Alım İşlemi",
                                               subtitle: "Pozisyon aç",
                                               icon: "arrow.up.circle.fill") {
                        tradeAction = .buy
                        showTradeSheet = true
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Satış İşlemi",
                                               subtitle: "Pozisyon kapat",
                                               icon: "arrow.down.circle.fill") {
                        tradeAction = .sell
                        showTradeSheet = true
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Analist Raporu",
                                               subtitle: "\(symbol) detaylı rapor",
                                               icon: "AnalystIcon") {
                        router.navigate(to: .analystReport(symbol: symbol))
                        dismiss()
                    },
                    ArgusDrawerView.DrawerItem(title: "Konsey Tartışması",
                                               subtitle: "Motor görüşleri",
                                               icon: "bubble.left.and.bubble.right.fill") {
                        router.navigate(to: .symbolDebate(symbol: symbol))
                        dismiss()
                    }
                ]
            )
        )

        // 4) MODÜLLER — symbol-context HoloPanel açılır.
        // Global (non-BIST) ek olarak Athena (Smart Beta) ve Demeter (Sektör).
        var moduleItems: [ArgusDrawerView.DrawerItem] = [
            ArgusDrawerView.DrawerItem(title: "Orion",
                                       subtitle: "Teknik momentum",
                                       icon: "OrionIcon") {
                selectedModule = .orion
                dismiss()
            },
            ArgusDrawerView.DrawerItem(title: "Atlas",
                                       subtitle: "Temel analiz",
                                       icon: "AtlasIcon") {
                selectedModule = .atlas
                dismiss()
            },
            ArgusDrawerView.DrawerItem(title: "Hermes",
                                       subtitle: "Haber etkisi",
                                       icon: "HermesIcon") {
                selectedModule = .hermes
                dismiss()
            },
            ArgusDrawerView.DrawerItem(title: "Chiron",
                                       subtitle: "Öğrenme · bu sembol",
                                       icon: "ChironIcon") {
                selectedModule = .chiron
                dismiss()
            },
            ArgusDrawerView.DrawerItem(title: "Aether",
                                       subtitle: "Makro rejim",
                                       icon: "AetherIcon") {
                selectedModule = .aether
                dismiss()
            },
            ArgusDrawerView.DrawerItem(title: "Prometheus",
                                       subtitle: "Fiyat projeksiyonu",
                                       icon: "PrometheusIcon") {
                selectedModule = .prometheus
                dismiss()
            }
        ]

        if !isBistSymbol {
            moduleItems.append(contentsOf: [
                ArgusDrawerView.DrawerItem(title: "Athena",
                                           subtitle: "Smart Beta faktörleri",
                                           icon: "AthenaIcon") {
                    selectedModule = .athena
                    dismiss()
                },
                ArgusDrawerView.DrawerItem(title: "Demeter",
                                           subtitle: "Sektör momentum",
                                           icon: "DemeterIcon") {
                    selectedModule = .demeter
                    dismiss()
                }
            ])
        }

        sections.append(
            ArgusDrawerView.DrawerSection(title: "Modüller", items: moduleItems)
        )

        sections.append(ArgusDrawerView.commonToolsSection(openSheet: openSheet, dismiss: dismiss))

        return sections
    }

    // MARK: - Subviews (Computed Properties)

    // 2026-04-25 H-36 · Sticky top nav (P1 layout, kullanıcı onayı):
    //   sol: chevron.left + sembol + borsa altyazısı
    //   sağ: Argus app-icon (analiz aç) + line.3.horizontal (drawer)
    // Eski floating backButtonOverlay (chevron + AnalystIcon + ellipsis)
    // kaldırıldı; bunun yerine sticky bar nav-bar standardını izliyor.
    private var sanctumTopNav: some View {
        HStack(spacing: 8) {
            Button(action: handleBackAction) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Geri")

            VStack(alignment: .leading, spacing: 0) {
                Text(symbol)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(exchangeMeta)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.leading, 2)

            Spacer()

            Button(action: { showArgusAnalysis = true }) {
                Image("ArgusAppIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(InstitutionalTheme.Colors.holo.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Argus analizi")

            Button(action: {
                withAnimation(ArgusDrawerView.toggleAnimation) {
                    showDrawer = true
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menüyü aç")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 0.5)
        }
    }

    /// "NASDAQ · Global" gibi alt başlık. BIST sembolleri için "BIST · Sirkiye".
    private var exchangeMeta: String {
        if symbol.uppercased().hasSuffix(".IS") {
            return "BIST · Sirkiye"
        }
        return "NASDAQ · Global"
    }
    
    // 2. HEADER → Views/Sanctum/SanctumHeader.swift
    // 3. CENTER CORE → Views/Sanctum/SanctumModuleGrid.swift
    //    (decision panel → Views/Sanctum/SanctumDecisionPanel.swift)

    // 4. FOOTER (Pantheon)
    private var footerHelper: some View {
         PantheonDeckView(
            symbol: symbol,
            isBist: symbol.uppercased().hasSuffix(".IS"),
            selectedModule: $selectedModule,
            selectedBistModule: $selectedBistModule
        )
    }

    private func handleBackAction() {
        if selectedModule != nil || selectedBistModule != nil || showDecision {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                selectedModule = nil
                selectedBistModule = nil
                showDecision = false
            }
            return
        }

        dismiss()
    }

    @MainActor
    private func applyLaunchModuleOverrideIfNeeded() async {
        guard !hasAppliedLaunchOverride else { return }

        // Small delay avoids race with initial deep-link navigation state propagation.
        try? await Task.sleep(nanoseconds: 350_000_000)

        let arguments = ProcessInfo.processInfo.arguments
        let isBistSymbol = symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)

        let bistRaw: String? = {
            if let inline = arguments.first(where: { $0.hasPrefix("--argus-bist-module=") }) {
                return inline.replacingOccurrences(of: "--argus-bist-module=", with: "")
            }
            if let index = arguments.firstIndex(of: "--argus-bist-module"), arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            return nil
        }()

        if isBistSymbol, let bistRaw {
            let rawBist = bistRaw.uppercased()
            if let bistModule = SanctumBistModuleType(rawValue: rawBist) {
                let normalizedBistModule: BistModuleType = (bistModule == .oracle) ? .rejim : bistModule
                withAnimation(.spring()) {
                    selectedBistModule = normalizedBistModule
                }
                hasAppliedLaunchOverride = true
                return
            }
        }

        let globalRaw: String? = {
            if let inline = arguments.first(where: { $0.hasPrefix("--argus-module=") }) {
                return inline.replacingOccurrences(of: "--argus-module=", with: "")
            }
            if let index = arguments.firstIndex(of: "--argus-module"), arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            return nil
        }()

        guard let globalRaw else {
            return
        }

        let rawModule = globalRaw.uppercased()

        if isBistSymbol, let bistModule = SanctumBistModuleType(rawValue: rawModule) {
            let normalizedBistModule: BistModuleType = (bistModule == .oracle) ? .rejim : bistModule
            withAnimation(.spring()) {
                selectedBistModule = normalizedBistModule
            }
            hasAppliedLaunchOverride = true
            return
        }

        if let globalModule = SanctumModuleType(rawValue: rawModule) {
            withAnimation(.spring()) {
                selectedModule = globalModule
            }
            hasAppliedLaunchOverride = true
        }
    }
}

private struct SanctumCommandButton: View {
    let title: String
    let icon: String
    let tint: Color
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(.caption2).weight(.semibold))

                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
                    .tracking(0.5)
            }
            .foregroundColor(tint)
            .padding(.horizontal, isPrimary ? 12 : 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.sm, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(isPrimary ? 0.95 : 0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.sm, style: .continuous)
                    .stroke(isPrimary ? tint.opacity(0.30) : DesignTokens.Colors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - COMPONENTS

// OrbView ve BistOrbView -> Views/Sanctum/SanctumOrbViews.swift

// CenterCoreView -> Views/Sanctum/SanctumCenterCore.swift

// MARK: - PANTHEON (THE OVERWATCH DECK)
// PantheonDeckView ve PantheonFlankView -> Views/Sanctum/SanctumPantheon.swift


// MARK: - BIST HOLO PANEL (ESKİ BORSACI VERSİYONU)

// MARK: - Hermes Helper View

