import SwiftUI

// MARK: - SirkiyeAetherView (Türkiye makrosu)
//
// 2026-05-05 H-64 — komple yeniden yazıldı. Eski yapı: 180pt circle gauge
// + 48pt rounded skor + glass + linear gradient mavi-mor + 4 mini card
// grid + 3 sparkline kart + sektör rotasyonu kartı + bileşenler tablosu
// + 80+ satır data grid + insights banner + rationale section. AI
// dashboard dili, Theme.* legacy tokenları, 867 satır.
//
// Yeni yapı: iOS Settings hub'ı (Global Aether ile aynı dil).
// Root: durum cümlesi + "Bugün" 3 satır (USD/TRY, BIST 100, Politika
// faizi) + 3 link satırı (Bileşenler / Sektör rotasyonu / TCMB verileri)
// + footer. Detaylar sub-page'lere bölündü, geri butonu sistem
// NavigationStack push'undan geliyor.
//
// Public API korundu: `init(linkedDecision: AetherDecision? = nil)`.

struct SirkiyeAetherView: View {
    let linkedDecision: AetherDecision?

    @State private var macroScore: SirkiyeAetherEngine.TurkeyMacroScore = .empty
    @State private var snapshot: TCMBDataService.TCMBMacroSnapshot = .empty
    @State private var sectorRotation: BistSektorResult?
    @State private var isLoading = true

    @Environment(\.dismiss) private var dismiss

    init(linkedDecision: AetherDecision? = nil) {
        self.linkedDecision = linkedDecision
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                inlineTopNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if isLoading {
                            loadingState
                        } else {
                            statusParagraph
                            if !todayRows.isEmpty {
                                todayList
                            }
                            navigationGroup
                            footerNote
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .refreshable {
                    await loadData(forceRefresh: true)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadData(forceRefresh: false)
        }
    }

    // MARK: - Üst nav

    private var inlineTopNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Geri")

            Text("Türkiye makrosu")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("TCMB verileri yükleniyor…")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
    }

    // MARK: - Durum cümlesi

    /// Hero gauge yerine geçen tek paragraf. Para politikası + enflasyon
    /// baskısı + dış kırılganlık üzerinden plain Türkçe cümle.
    private var statusParagraph: some View {
        Text(statusSentence)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    private var statusSentence: String {
        let stanceText: String
        switch macroScore.monetaryStance {
        case .tight:   stanceText = "Sıkı para politikası sürüyor"
        case .neutral: stanceText = "Para politikası nötr"
        case .loose:   stanceText = "Para politikası gevşek"
        }

        let infText: String
        switch macroScore.inflationPressure {
        case .severe: infText = "enflasyon baskısı şiddetli"
        case .high:   infText = "enflasyon baskısı yüksek"
        case .medium: infText = "enflasyon baskısı dengelenmiş"
        case .low:    infText = "enflasyon baskısı düşük"
        }

        let extText: String
        switch macroScore.externalRisk {
        case .critical: extText = "dış kırılganlık kritik"
        case .high:     extText = "dış kırılganlık yüksek"
        case .medium:   extText = "dış denge orta"
        case .low:      extText = "dış denge desteklenmiş"
        }

        return "\(stanceText). \(infText.capitalized), \(extText)."
    }

    // MARK: - Bugün satırları

    private struct TodayRow {
        let label: String
        let sub: String
        let value: String
        let valueColor: Color
    }

    private var todayRows: [TodayRow] {
        var rows: [TodayRow] = []

        if let usdTry = snapshot.usdTry {
            rows.append(TodayRow(
                label: "USD/TRY",
                sub: String(format: "%.2f", usdTry),
                value: "—",
                valueColor: DesignTokens.Colors.textSecondary
            ))
        }

        if let bist = snapshot.bist100 {
            rows.append(TodayRow(
                label: "BIST 100",
                sub: bistFormatted(bist),
                value: "—",
                valueColor: DesignTokens.Colors.textSecondary
            ))
        }

        if let policy = snapshot.policyRate {
            rows.append(TodayRow(
                label: "Politika faizi",
                sub: "TCMB",
                value: String(format: "%.2f%%", policy),
                valueColor: DesignTokens.Colors.textSecondary
            ))
        }

        return rows
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bugün")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(todayRows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(DesignTokens.Fonts.custom(size: 14))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Text(row.sub)
                                .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        if row.value != "—" {
                            Text(row.value)
                                .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                                .foregroundColor(row.valueColor)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if idx < todayRows.count - 1 {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 22)
    }

    private func bistFormatted(_ value: Double) -> String {
        // 10842.5 → "10.842"
        let int = Int(value)
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = "."
        return nf.string(from: NSNumber(value: int)) ?? String(int)
    }

    // MARK: - Navigasyon grupları

    private var navigationGroup: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: SirkiyeBilesenlerView(macroScore: macroScore)) {
                hubRow(title: "Bileşenler", trailing: "4 boyut")
            }
            .buttonStyle(.plain)

            divider

            NavigationLink(destination: SirkiyeSektorView(result: sectorRotation)) {
                hubRow(title: "Sektör rotasyonu", trailing: sectorTrailing)
            }
            .buttonStyle(.plain)

            divider

            NavigationLink(destination: SirkiyeTCMBView(snapshot: snapshot)) {
                hubRow(title: "TCMB verileri", trailing: nil)
            }
            .buttonStyle(.plain)
        }
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func hubRow(title: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var sectorTrailing: String? {
        guard let sectorRotation, let strongest = sectorRotation.strongestSector else {
            return nil
        }
        return "\(strongest.name) ön planda"
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Skor TCMB politika faizi, USD/TRY, enflasyon ve dış denge göstergelerinin ağırlıklı ortalamasıdır.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Data loading

    private func loadData(forceRefresh: Bool) async {
        isLoading = true
        async let scoreTask = SirkiyeAetherEngine.shared.analyze(forceRefresh: forceRefresh)
        async let snapshotTask = TCMBDataService.shared.getMacroSnapshot(forceRefresh: forceRefresh)
        async let sectorTask = try? BistSektorEngine.shared.analyze(forceRefresh: forceRefresh)

        let score = await scoreTask
        let snap = await snapshotTask
        let sect = await sectorTask

        await MainActor.run {
            macroScore = score
            snapshot = snap
            sectorRotation = sect
            isLoading = false
        }
    }
}

// MARK: - SirkiyeBilesenlerView (Bileşenler sub-page)
//
// 4 boyut grouped list: Para politikası, Büyüme, Dış kırılganlık,
// Enflasyon. Her satır plain durum etiketi (Sıkı / Yavaşlama / Düşük /
// Yüksek). Tıklamayla detail çıkmıyor — durum etiketi zaten anlamlı,
// daha derin metin gerekirse footer'da kullanıcıya yön verilir.

struct SirkiyeBilesenlerView: View {
    let macroScore: SirkiyeAetherEngine.TurkeyMacroScore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        boyutlarGroup
                        if !macroScore.components.isEmpty {
                            componentsGroup
                        }
                        footer
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var topNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Bileşenler")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var boyutlarGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boyutlar")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                boyutRow(
                    title: "Para politikası",
                    sub: "TCMB faizi, M2 büyümesi",
                    status: macroScore.monetaryStance.rawValue,
                    color: stanceColor(macroScore.monetaryStance)
                )
                divider
                boyutRow(
                    title: "Büyüme",
                    sub: "GSYİH, sanayi üretimi",
                    status: macroScore.growthMomentum.rawValue,
                    color: momentumColor(macroScore.growthMomentum)
                )
                divider
                boyutRow(
                    title: "Dış kırılganlık",
                    sub: "Cari denge, rezerv, CDS",
                    status: macroScore.externalRisk.rawValue,
                    color: riskColor(macroScore.externalRisk)
                )
                divider
                boyutRow(
                    title: "Enflasyon",
                    sub: "TÜFE, ÜFE, beklenti",
                    status: macroScore.inflationPressure.rawValue,
                    color: pressureColor(macroScore.inflationPressure)
                )
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 18)
    }

    private func boyutRow(title: String, sub: String, status: String, color: Color) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 15))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(sub)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Text(status)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    /// Engine'in döndürdüğü ağırlıklı bileşen listesi (analyzeInflation,
    /// analyzeFXStability vs.).
    private var componentsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detay bileşenler")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(macroScore.components.enumerated()), id: \.offset) { idx, component in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.name)
                                .font(DesignTokens.Fonts.custom(size: 14))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Text(formatComponentValue(component))
                                .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Text("\(Int(component.score))")
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundColor(scoreColor(component.score))
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    if idx < macroScore.components.count - 1 {
                        divider
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 14)
    }

    private func formatComponentValue(_ component: SirkiyeAetherEngine.ScoreComponent) -> String {
        let weightPct = Int(component.weight * 100)
        return "Ağırlık %\(weightPct)"
    }

    private var footer: some View {
        Text("Boyutlar TCMB ve makro veri akışından her 5 dakikada güncellenir.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Color helpers

    private func stanceColor(_ stance: SirkiyeAetherEngine.PolicyStance) -> Color {
        switch stance {
        case .tight: return InstitutionalTheme.Colors.aurora
        case .neutral: return InstitutionalTheme.Colors.titan
        case .loose: return InstitutionalTheme.Colors.crimson
        }
    }

    private func momentumColor(_ m: SirkiyeAetherEngine.Momentum) -> Color {
        switch m {
        case .accelerating: return InstitutionalTheme.Colors.aurora
        case .stable: return DesignTokens.Colors.textSecondary
        case .decelerating: return InstitutionalTheme.Colors.titan
        }
    }

    private func riskColor(_ r: SirkiyeAetherEngine.RiskLevel) -> Color {
        switch r {
        case .low: return InstitutionalTheme.Colors.aurora
        case .medium: return DesignTokens.Colors.textSecondary
        case .high: return InstitutionalTheme.Colors.titan
        case .critical: return InstitutionalTheme.Colors.crimson
        }
    }

    private func pressureColor(_ p: SirkiyeAetherEngine.Pressure) -> Color {
        switch p {
        case .low: return InstitutionalTheme.Colors.aurora
        case .medium: return DesignTokens.Colors.textSecondary
        case .high: return InstitutionalTheme.Colors.titan
        case .severe: return InstitutionalTheme.Colors.crimson
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}

// MARK: - SirkiyeSektorView (Sektör rotasyonu sub-page)
//
// Rotation kısa cümle özeti + sektör listesi (dailyChange'e göre sıralı).

struct SirkiyeSektorView: View {
    let result: BistSektorResult?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let result {
                            summaryParagraph(result)
                            sectorList(result)
                        } else {
                            emptyState
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var topNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Sektör rotasyonu")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private func summaryParagraph(_ result: BistSektorResult) -> some View {
        let strongest = result.strongestSector?.name ?? "—"
        let weakest = result.weakestSector?.name ?? "—"
        let rotation = result.rotation.rawValue.lowercased()
        return Text("\(rotation.capitalized) eğilimi öne çıkıyor. \(strongest) güçleniyor, \(weakest) zayıf seyrediyor.")
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    private func sectorList(_ result: BistSektorResult) -> some View {
        let sorted = result.sectors.sorted(by: { $0.dailyChange > $1.dailyChange })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Bugün")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { idx, sector in
                    HStack(spacing: 0) {
                        Text(sector.name)
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Text(formattedChange(sector.dailyChange))
                            .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                            .foregroundColor(changeColor(sector.dailyChange))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if idx < sorted.count - 1 {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formattedChange(_ value: Double) -> String {
        if abs(value) < 0.05 { return "±0.0%" }
        return String(format: "%@%.1f%%", value >= 0 ? "+" : "", value)
    }

    private func changeColor(_ value: Double) -> Color {
        if abs(value) < 0.05 { return DesignTokens.Colors.textSecondary }
        return value >= 0 ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson
    }

    private var emptyState: some View {
        Text("Sektör rotasyonu verisi bekleniyor.")
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .padding(.vertical, 22)
    }
}

// MARK: - SirkiyeTCMBView (TCMB verileri sub-page)
//
// Raw TCMB snapshot'ı 3 grup altında plain key-value listesi olarak
// gösterir: Faiz/kur, Enflasyon, Dış denge.

struct SirkiyeTCMBView: View {
    let snapshot: TCMBDataService.TCMBMacroSnapshot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        faizKurGroup
                        enflasyonGroup
                        disDengeGroup
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var topNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("TCMB verileri")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private struct DataRow {
        let label: String
        let value: String
    }

    private func dataGroup(title: String, rows: [DataRow]) -> some View {
        let valid = rows.filter { $0.value != "—" }
        guard !valid.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .padding(.leading, 2)

                VStack(spacing: 0) {
                    ForEach(Array(valid.enumerated()), id: \.offset) { idx, row in
                        HStack {
                            Text(row.label)
                                .font(DesignTokens.Fonts.custom(size: 14))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Spacer()
                            Text(row.value)
                                .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        if idx < valid.count - 1 {
                            Rectangle()
                                .fill(DesignTokens.Colors.borderSubtle)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.bottom, 18)
        )
    }

    private var faizKurGroup: some View {
        dataGroup(title: "Faiz ve kur", rows: [
            DataRow(label: "Politika faizi", value: format(snapshot.policyRate, suffix: "%")),
            DataRow(label: "Mevduat faizi", value: format(snapshot.depositRate, suffix: "%")),
            DataRow(label: "Kredi faizi", value: format(snapshot.loanRate, suffix: "%")),
            DataRow(label: "USD/TRY", value: format(snapshot.usdTry, decimals: 2)),
            DataRow(label: "EUR/TRY", value: format(snapshot.eurTry, decimals: 2))
        ])
    }

    private var enflasyonGroup: some View {
        dataGroup(title: "Enflasyon", rows: [
            DataRow(label: "TÜFE, yıllık", value: format(snapshot.inflation, suffix: "%")),
            DataRow(label: "Çekirdek TÜFE", value: format(snapshot.coreInflation, suffix: "%"))
        ])
    }

    private var disDengeGroup: some View {
        dataGroup(title: "Dış denge ve rezerv", rows: [
            DataRow(label: "Cari denge", value: formatBillions(snapshot.currentAccount)),
            DataRow(label: "İhracat", value: formatBillions(snapshot.exports)),
            DataRow(label: "İthalat", value: formatBillions(snapshot.imports)),
            DataRow(label: "Brüt rezerv", value: formatBillions(snapshot.reserves)),
            DataRow(label: "Net rezerv", value: formatBillions(snapshot.netReserves))
        ])
    }

    // MARK: - Format helpers

    private func format(_ value: Double?, suffix: String = "", decimals: Int = 2) -> String {
        guard let value else { return "—" }
        let f = "%.\(decimals)f\(suffix)"
        return String(format: f, value)
    }

    private func formatBillions(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f mlr $", value)
    }
}
