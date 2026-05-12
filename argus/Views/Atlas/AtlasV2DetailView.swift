import SwiftUI

// MARK: - AtlasV2DetailView (Global Bilanço)
//
// 2026-05-05 H-66 — sıfırdan yeniden yazıldı.
//
// Eski yapı (>900 satır): ArgusNavHeader caps subtitle, 80pt circle ring
// + qualityBand hero, ArgusOrb, ArgusDot/Chip/SectionCaption, atlas
// motor tinted border'lar, expandable bölüm kartları progress bar
// chevron ile, "POZİTİF SİNYALLER / KRİTİK NOTLAR" caps captions, value
// alert tinted block'lar. AI dashboard dili.
//
// Yeni yapı: iOS Settings hub (Makro / Türkiye makrosu / Bilanço-BIST
// ile aynı dil).
//   • Üst nav: chevron + sembol
//   • Şirket meta tek satır (isim · sektör · marketCap)
//   • Durum cümlesi (result.summary)
//   • Pozitif sinyaller / Kritik notlar — link satırları → sub-page
//   • Boyutlar 3 grupta: Temel (Değerleme/Karlılık/Sağlık),
//     Genişleme (Büyüme/Nakit), Ek (Temettü/Risk)
//   • Her boyut tıklayınca metric listesi sub-page'i
//   • Footer
//
// Public API korundu: `init(symbol:)`.

struct AtlasV2DetailView: View {
    let symbol: String

    @State private var result: AtlasV2Result?
    @State private var isLoading = true
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                inlineTopNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if isLoading {
                            loadingState
                        } else if let err = error {
                            errorState(err)
                        } else if let r = result {
                            companyMeta(r)
                            statusParagraph(r)
                            signalsGroup(r)
                            boyutlarTemel(r)
                            boyutlarGenisleme(r)
                            boyutlarEk(r)
                            footerNote
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadData()
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

            Text(symbol.replacingOccurrences(of: ".IS", with: ""))
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

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("Bilanço analizi yükleniyor…")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analiz tamamlanamadı")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text(err)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 22)
    }

    // MARK: - Şirket meta

    private func companyMeta(_ r: AtlasV2Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.profile.name)
                .font(DesignTokens.Fonts.custom(size: 18, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Text(symbol.replacingOccurrences(of: ".IS", with: ""))
                    .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                if let sector = r.profile.sector, !sector.isEmpty {
                    Text(" · \(sector)")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                Text(" · \(r.profile.formattedMarketCap)")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Durum cümlesi

    private func statusParagraph(_ r: AtlasV2Result) -> some View {
        Text(r.summary)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    // MARK: - Pozitif / Kritik link grubu

    @ViewBuilder
    private func signalsGroup(_ r: AtlasV2Result) -> some View {
        if !r.highlights.isEmpty || !r.warnings.isEmpty {
            VStack(spacing: 0) {
                if !r.highlights.isEmpty {
                    NavigationLink(destination: BilancoSinyalView(
                        title: "Pozitif sinyaller",
                        items: r.highlights,
                        tone: .aurora
                    )) {
                        signalRow(title: "Pozitif sinyaller", count: r.highlights.count, color: InstitutionalTheme.Colors.aurora)
                    }
                    .buttonStyle(.plain)
                    if !r.warnings.isEmpty {
                        divider
                    }
                }
                if !r.warnings.isEmpty {
                    NavigationLink(destination: BilancoSinyalView(
                        title: "Kritik notlar",
                        items: r.warnings,
                        tone: .crimson
                    )) {
                        signalRow(title: "Kritik notlar", count: r.warnings.count, color: InstitutionalTheme.Colors.crimson)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 18)
        }
    }

    private func signalRow(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text("\(count)")
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(color)
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    // MARK: - Boyut grupları

    private func boyutlarTemel(_ r: AtlasV2Result) -> some View {
        boyutGroup(
            title: "Temel",
            rows: [
                BoyutRow(title: "Değerleme", sub: "F/K · PD/DD · EV/EBITDA",
                         score: r.valuationScore, metrics: r.valuation.allMetrics),
                BoyutRow(title: "Karlılık", sub: "ROE · ROA · marjlar",
                         score: r.profitabilityScore, metrics: r.profitability.allMetrics),
                BoyutRow(title: "Sağlık", sub: "Borç/özkaynak · cari oran",
                         score: r.healthScore, metrics: r.health.allMetrics)
            ]
        )
    }

    private func boyutlarGenisleme(_ r: AtlasV2Result) -> some View {
        boyutGroup(
            title: "Genişleme",
            rows: [
                BoyutRow(title: "Büyüme", sub: "Satış · net kâr · CAGR",
                         score: r.growthScore, metrics: r.growth.allMetrics),
                BoyutRow(title: "Nakit kalitesi", sub: "Serbest nakit · OCF/net kâr",
                         score: r.cashScore, metrics: r.cash.allMetrics)
            ]
        )
    }

    private func boyutlarEk(_ r: AtlasV2Result) -> some View {
        boyutGroup(
            title: "Ek",
            rows: [
                BoyutRow(title: "Temettü", sub: "Verim · ödeme oranı · süreklilik",
                         score: r.dividendScore, metrics: r.dividend.allMetrics),
                BoyutRow(title: "Risk", sub: "Beta · volatilite",
                         score: riskScore(r), metrics: r.risk.allMetrics)
            ]
        )
    }

    /// risk skoru AtlasV2Result'ta direct field değil; allMetrics'in
    /// ortalaması alınır.
    private func riskScore(_ r: AtlasV2Result) -> Double {
        let metrics = r.risk.allMetrics
        guard !metrics.isEmpty else { return 50 }
        let sum = metrics.reduce(0.0) { $0 + $1.score }
        return sum / Double(metrics.count)
    }

    private struct BoyutRow {
        let title: String
        let sub: String
        let score: Double
        let metrics: [AtlasMetric]
    }

    private func boyutGroup(title: String, rows: [BoyutRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    NavigationLink(destination: BilancoBoyutView(
                        title: row.title,
                        score: row.score,
                        metrics: row.metrics
                    )) {
                        boyutRowView(row)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        divider
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 18)
    }

    private func boyutRowView(_ row: BoyutRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DesignTokens.Fonts.custom(size: 15))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(row.sub)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Text("\(Int(row.score))")
                .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                .foregroundColor(scoreColor(row.score))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Skor 7 boyutun ağırlıklı ortalamasıdır. Veriler son finansal raporlardan çekilir.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Data loading

    private func loadData() async {
        let symbolToAnalyze = symbol
        do {
            let r = try await withTimeout(seconds: 60) {
                try await AtlasV2Engine.shared.analyze(symbol: symbolToAnalyze)
            }
            await MainActor.run {
                self.result = r
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private enum TimeoutError: Error { case timeout }

    private func withTimeout<T>(seconds: TimeInterval,
                                operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timeout
            }
            guard let value = try await group.next() else {
                throw TimeoutError.timeout
            }
            group.cancelAll()
            return value
        }
    }
}

// MARK: - BilancoBoyutView (Boyut detay sub-page)
//
// Hem AtlasV2 hem BIST tarafından kullanılır. AtlasMetric tipinde
// metric listesini gösterir, üstte ortalama skor.

struct BilancoBoyutView: View {
    let title: String
    let score: Double
    let metrics: [AtlasMetric]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let lead = leadingMetric {
                            statusParagraph(lead)
                        }
                        metricsGroup
                        evaluationGroup
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
            Text(title)
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

    /// En yüksek skorlu metrik üzerinden bir bağlam cümlesi.
    private var leadingMetric: AtlasMetric? {
        metrics.max(by: { $0.score < $1.score })
    }

    private func statusParagraph(_ m: AtlasMetric) -> some View {
        Text(m.explanation)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    private var metricsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrikler")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { idx, m in
                    metricRow(m)
                    if idx < metrics.count - 1 {
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
    }

    private func metricRow(_ m: AtlasMetric) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                if let sectorAvg = m.sectorAverage {
                    Text("Sektör ortalaması \(AtlasMetric.format(sectorAvg))")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                } else if !m.explanation.isEmpty {
                    Text(m.explanation)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(m.formattedValue)
                .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                .foregroundColor(metricValueColor(m.status))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func metricValueColor(_ status: AtlasMetricStatus) -> Color {
        switch status {
        case .excellent, .good: return InstitutionalTheme.Colors.aurora
        case .neutral: return DesignTokens.Colors.textSecondary
        case .warning: return InstitutionalTheme.Colors.titan
        case .bad, .critical: return InstitutionalTheme.Colors.crimson
        case .noData: return DesignTokens.Colors.textTertiary
        }
    }

    private var evaluationGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Değerlendirme")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                HStack {
                    Text("Özet skor")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text("\(Int(score)) / 100")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(scoreColor(score))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                Text(summarySentence)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var summarySentence: String {
        if score >= 70 { return "Bu boyutta sektör üstü bir performans var." }
        if score >= 50 { return "Bu boyutta orta seviye, sektör ortalamasına yakın." }
        return "Bu boyut zayıf, dikkatle izlenmesi gereken alan."
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}

// MARK: - BilancoSinyalView (Pozitif / Kritik notlar sub-page)

struct BilancoSinyalView: View {
    let title: String
    let items: [String]
    let tone: ArgusChipTone

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        listGroup
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
            Text(title)
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

    private var listGroup: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tone.foreground)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(item)
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                if idx < items.count - 1 {
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
