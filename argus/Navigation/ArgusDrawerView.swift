import SwiftUI

struct ArgusDrawerView: View {
    @Binding var isPresented: Bool
    let buildSections: (_ openSheet: @escaping (DrawerSheet) -> Void) -> [DrawerSection]

    @State private var searchText = ""
    @State private var activeSheet: DrawerSheet?

    struct DrawerSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [DrawerItem]
    }

    struct DrawerItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    enum DrawerSheet: Identifiable {
        case systemGuide
        case engineGuide   // ArgusAcademyHubSheet'te ders sheet'i olarak kullanılıyor
        case regimeGuide   // ArgusAcademyHubSheet'te ders sheet'i olarak kullanılıyor
        case dictionary
        case calendar
        case systemHealth
        case feedback
        case alkindusGuide
        case financeWisdom
        case academyHub

        var id: String {
            switch self {
            case .systemGuide: return "systemGuide"
            case .engineGuide: return "engineGuide"
            case .regimeGuide: return "regimeGuide"
            case .dictionary: return "dictionary"
            case .calendar: return "calendar"
            case .systemHealth: return "systemHealth"
            case .feedback: return "feedback"
            case .alkindusGuide: return "alkindusGuide"
            case .financeWisdom: return "financeWisdom"
            case .academyHub: return "academyHub"
            }
        }
    }

    /// Drawer açıp kapatma için ortak animation tokeni — parent view'lar
    /// `withAnimation(ArgusDrawerView.toggleAnimation) { showDrawer.toggle() }`
    /// ile çağırmalı.
    /// 2026-05-03 H-59: drawer aniden çıkıp kayboluyordu, animasyon eklendi.
    static let toggleAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)

    private var sections: [DrawerSection] {
        let baseSections = buildSections { sheet in
            activeSheet = sheet
        }
        return withAcademyShortcut(baseSections)
    }

    private var allItems: [DrawerItem] {
        sections.flatMap { $0.items }
    }

    private var filteredItems: [DrawerItem] {
        if searchText.isEmpty { return [] }
        return allItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // 2026-05-03 H-59: navigasyon bug fix.
        //   • HStack'in sağ tarafında `Spacer()` yerine `Color.clear` +
        //     contentShape + onTapGesture — Spacer tap event'i tutarsız
        //     yutmuyordu, "drawer dışına bas kapansın" bazen çalışmıyordu.
        //   • Backdrop opacity .ignoresSafeArea + tap birlikte güvenli olsun
        //     diye contentShape eklendi.
        //   • Sheet kapatınca drawer'ı kapatmak yerine açık bırakıyoruz —
        //     kullanıcı sheet'ten çıkınca menüye geri dönmek isteyebilir.
        ZStack {
            DesignTokens.Colors.background.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(ArgusDrawerView.toggleAnimation) {
                        isPresented = false
                    }
                }

            HStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        headerSection
                        searchSection

                        if !searchText.isEmpty {
                            groupedSection(title: "Arama sonuçları", items: filteredItems)
                        } else {
                            ForEach(sections) { section in
                                groupedSection(title: section.title, items: section.items)
                            }
                        }

                        Spacer().frame(height: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .frame(width: 320)
                .background(DesignTokens.Colors.background)

                // Sağ alan — explicit tap area (Spacer tap event'i yutmuyordu)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                    withAnimation(ArgusDrawerView.toggleAnimation) {
                        isPresented = false
                    }
                }
            }
        }
        .transition(.move(edge: .leading))
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    /// Bölüm başlığı + grouped list — iOS Settings list diline yakın.
    /// 2026-04-30 H-43 fix: Array(items.enumerated()) + id:\.element.id
    /// kombinasyonu Button binding'ini bazen koparıyordu (tıklama
    /// işlemiyor). ForEach(items) + son-eleman karşılaştırmasıyla divider
    /// gösterimine geçtim. Identity stabil, tıklamalar dirilir.
    @ViewBuilder
    private func groupedSection(title: String, items: [DrawerItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    navigationItem(icon: item.icon,
                                   title: item.title,
                                   subtitle: item.subtitle,
                                   action: item.action)
                    if item.id != items.last?.id {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 44)
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Header (2026-04-30 H-43 sade)
    //
    // ARGUS heavy mono caps tracking 2.4 + INSTITUTIONAL · V1.0 micro caps + dot
    // + 48pt logo + alt hairline → sade tek satır: küçük dairesel logo +
    // "Argus" 17pt medium + sağda close. Sürüm satırı ayarlar > hakkında
    // sayfasında zaten var, drawer üstünden kalkıyor.
    private var headerSection: some View {
        HStack(spacing: 12) {
            MotorLogo(.argus, size: 28)

            Text("Argus")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Spacer()

            Button {
                withAnimation(ArgusDrawerView.toggleAnimation) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .regular))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .font(DesignTokens.Fonts.custom(size: 14))

            TextField("Ara…", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .font(DesignTokens.Fonts.custom(size: 14))

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .font(DesignTokens.Fonts.custom(size: 14))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Components

    @ViewBuilder
    private func iconView(for icon: String) -> some View {
        if let motor = motorFromIconName(icon) {
            MotorLogo(motor, size: 20)
        } else if isCustomAsset(icon) {
            // Motor olmayan özel asset'ler (örn. TradeBrainIcon).
            // Template rendering — proje tonu uygulanır, transparent
            // PNG ile silüet olarak gösterilir.
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: icon)
                .font(DesignTokens.Fonts.custom(size: 16, weight: .regular))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    /// "Icon" suffix'li ve büyük harfle başlayan string'ler asset varsayılır.
    private func isCustomAsset(_ name: String) -> Bool {
        guard name.hasSuffix("Icon"), let first = name.first else { return false }
        return first.isUppercase
    }

    /// Icon adından MotorEngine türet (varsa).
    private func motorFromIconName(_ icon: String) -> MotorEngine? {
        switch icon {
        case "OrionIcon":      return .orion
        case "AtlasIcon":      return .atlas
        case "AetherIcon":     return .aether
        case "HermesIcon":     return .hermes
        case "AthenaIcon":     return .athena
        case "DemeterIcon":    return .demeter
        case "ChironIcon":     return .chiron
        case "PrometheusIcon": return .prometheus
        case "AlkindusIcon":   return .alkindus
        case "AnalystIcon":    return .council
        default:               return nil
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .padding(.leading, 4)
    }

    private func navigationItem(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView(for: icon)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .regular))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func sheetContent(for sheet: DrawerSheet) -> some View {
        switch sheet {
        case .systemGuide:
            SystemGuideSheet()
        case .engineGuide:
            EngineGuideSheet()
        case .regimeGuide:
            RegimeGuideSheet()
        case .dictionary:
            FinanceDictionarySheet()
        case .calendar:
            EconomicCalendarSheet()
        case .systemHealth:
            SystemHealthSheet()
        case .feedback:
            FeedbackSheet()
        case .alkindusGuide:
            AlkindusEducationSheet()
        case .financeWisdom:
            FinanceWisdomSheet()
        case .academyHub:
            ArgusAcademyHubSheet()
        }
    }

    private func withAcademyShortcut(_ baseSections: [DrawerSection]) -> [DrawerSection] {
        let academyItem = DrawerItem(
            title: "Argus Akademi",
            subtitle: "Sistem ve motor eğitimi",
            icon: "graduationcap"
        ) {
            activeSheet = .academyHub
        }

        var updated: [DrawerSection] = []
        var hadLearningItems = false

        for section in baseSections {
            let filteredItems = section.items.filter { item in
                let isLearning = isLearningItem(item.title)
                if isLearning { hadLearningItems = true }
                return !isLearning
            }
            if !filteredItems.isEmpty {
                updated.append(DrawerSection(title: section.title, items: filteredItems))
            }
        }

        let alreadyHasAcademy = updated
            .flatMap(\.items)
            .contains { normalized($0.title).contains("akademi") }

        guard !alreadyHasAcademy else { return updated }

        if let toolsIndex = updated.firstIndex(where: { normalized($0.title).contains("arac") }) {
            let targetSection = updated[toolsIndex]
            let sectionWithAcademy = DrawerSection(
                title: targetSection.title,
                items: [academyItem] + targetSection.items
            )
            updated[toolsIndex] = sectionWithAcademy
            return updated
        }

        if hadLearningItems {
            updated.insert(DrawerSection(title: "Öğrenme", items: [academyItem]), at: 0)
            return updated
        }

        updated.append(DrawerSection(title: "Öğrenme", items: [academyItem]))
        return updated
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
    }

    private func isLearningItem(_ title: String) -> Bool {
        let normalizedTitle = normalized(title)
        return normalizedTitle.contains("egitim") || normalizedTitle.contains("rehber") || normalizedTitle.contains("akademi")
    }

    /// Drawer'da yer alan ana ekran kısayolları.
    /// 2026-05-04: Önceden 8 view'da aynı 5 item kopyalanıyordu;
    /// item isimleri (Kokpit/Piyasalar/Terminal), büyük-küçük harf
    /// ("Ana Sayfa" / "Ana sayfa") ve dismiss sırası tutarsızdı.
    /// Tek source-of-truth burada — `excluding` ile bulunduğu ekranı
    /// menüden çıkarmak için kullanılır (örn. SettingsView .settings'i çıkarır).
    enum Screen: Hashable, CaseIterable {
        case home
        case kokpit
        case alkindus
        case portfolio
        case settings
    }

    static func commonScreensSection(
        excluding excluded: Set<Screen> = [],
        dismiss: @escaping () -> Void
    ) -> DrawerSection {
        var items: [DrawerItem] = []

        if !excluded.contains(.home) {
            items.append(
                DrawerItem(title: "Ana Sayfa", subtitle: "Sinyal akışı", icon: "waveform.path.ecg") {
                    DeepLinkManager.shared.navigate(to: .home)
                    dismiss()
                }
            )
        }

        if !excluded.contains(.kokpit) {
            items.append(
                DrawerItem(title: "Piyasalar", subtitle: "Market ekranı", icon: "chart.line.uptrend.xyaxis") {
                    DeepLinkManager.shared.navigate(to: .kokpit)
                    dismiss()
                }
            )
        }

        if !excluded.contains(.alkindus) {
            items.append(
                DrawerItem(title: "Alkindus Merkez", subtitle: "Yapay zeka merkezi", icon: "AlkindusIcon") {
                    NavigationRouter.shared.navigate(to: .alkindusDashboard)
                    dismiss()
                }
            )
        }

        if !excluded.contains(.portfolio) {
            items.append(
                DrawerItem(title: "Portföy", subtitle: "Pozisyonlar", icon: "briefcase.fill") {
                    DeepLinkManager.shared.navigate(to: .portfolio)
                    dismiss()
                }
            )
        }

        if !excluded.contains(.settings) {
            items.append(
                DrawerItem(title: "Ayarlar", subtitle: "Tercihler", icon: "gearshape") {
                    DeepLinkManager.shared.navigate(to: .settings)
                    dismiss()
                }
            )
        }

        return DrawerSection(title: "Ekranlar", items: items)
    }

    /// Parent view drawer item'larından drawer'ı kapatmak için helper.
    ///
    /// 2026-05-04 H-61: `withAnimation(toggleAnimation) { binding = false }`
    /// kalıbı navigation eşliğinde donma yaratıyordu (Alkindus push +
    /// drawer transition + parent re-render aynı turn'de SwiftUI'i takıyor).
    /// Animasyonu KASITLI olarak kaldırdım — drawer item'a basıldığında
    /// drawer anlık kapanır, sonrasında push/tab değişimi animasyonu
    /// NavigationStack/ContentView tarafından doğal yapılır.
    ///
    /// Backdrop tap ve close button (ArgusDrawerView'ın içinde) hala
    /// `withAnimation` ile animasyonlu — orada navigation yok, güvenli.
    static func dismissClosure(_ binding: Binding<Bool>) -> () -> Void {
        return {
            binding.wrappedValue = false
        }
    }

    /// Tüm parent view'ların kullandığı ortak "Araçlar" bölümü.
    /// Önceden 5 farklı parent view'da aynı kod kopyalanıyordu —
    /// tek source-of-truth burada.
    static func commonToolsSection(
        openSheet: @escaping (DrawerSheet) -> Void,
        dismiss: @escaping () -> Void = {}
    ) -> DrawerSection {
        DrawerSection(
            title: "Araçlar",
            items: [
                DrawerItem(title: "Ekonomi Takvimi", subtitle: "Gerçek takvim", icon: "calendar") {
                    openSheet(.calendar)
                },
                // 2026-05-06: Tahminler ekosistemi drawer'dan doğrudan ulaşılabilir oldu.
                // Önceden sadece Ana Sayfa → Aether kartı → sheet → liste 3 tıklama gerekiyordu.
                DrawerItem(title: "Yaklaşan veriler", subtitle: "Tahmin gir", icon: "calendar.badge.clock") {
                    NavigationRouter.shared.navigate(to: .expectationsEntry)
                    dismiss()
                },
                DrawerItem(title: "Tahminlerim", subtitle: "Geçmiş isabet", icon: "checkmark.seal") {
                    NavigationRouter.shared.navigate(to: .myPredictions)
                    dismiss()
                },
                DrawerItem(title: "Finans Sözlüğü", subtitle: "Terimler", icon: "character.book.closed") {
                    openSheet(.dictionary)
                },
                DrawerItem(title: "Ünlü Finans Sözleri", subtitle: "Finans alıntıları", icon: "quote.opening") {
                    openSheet(.financeWisdom)
                },
                DrawerItem(title: "Sistem Durumu", subtitle: "Servis sağlığı", icon: "waveform.path.ecg") {
                    openSheet(.systemHealth)
                },
                DrawerItem(title: "Görev Günlüğü", subtitle: "Otopilot kararları", icon: "list.bullet.clipboard") {
                    NavigationRouter.shared.navigate(to: .gorevGunlugu)
                    dismiss()
                },
                DrawerItem(title: "Geri Bildirim", subtitle: "Sorun bildir", icon: "envelope") {
                    openSheet(.feedback)
                }
            ]
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ArgusDrawerView(isPresented: .constant(true)) { _ in
            [
                ArgusDrawerView.DrawerSection(
                    title: "Örnek",
                    items: [
                        ArgusDrawerView.DrawerItem(title: "Demo", subtitle: "Örnek aksiyon", icon: "gearshape", action: {})
                    ]
                )
            ]
        }
    }
}
