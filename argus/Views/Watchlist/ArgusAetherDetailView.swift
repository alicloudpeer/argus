import SwiftUI

// MARK: - ArgusAetherDetailView (Makro merkezi)
//
// 2026-05-04 H-63 — komple yeniden yazıldı. Önceki yapı tek ekrana hero
// skor + 3 katman expandable + accuracy + formula + decision + tüm
// metric tablolarını yığıyordu (AI dashboard dili). Yeni yapı iOS
// Settings hub'ı: kısa durum cümlesi + "Bugün" 3 satır inline + grouped
// list (Yaklaşan veriler / Tahminlerim / Tüm göstergeler) + footer.
// Detay içerikler ayrı sub-page'lere bölündü, geri butonu sistem
// NavigationStack push'undan geliyor.

struct ArgusAetherDetailView: View {
    let rating: MacroEnvironmentRating

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var expectationsStore = ExpectationsStore.shared

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                inlineTopNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        statusParagraph
                        if !todayMovers.isEmpty {
                            todayList
                        }
                        navigationGroup
                        advancedGroup
                        footerNote
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
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

            Text("Makro")
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

    // MARK: - Durum paragrafı

    /// Hero skor / 100/100 yüzde rozetinin yerini alan tek paragraf.
    /// Rejim + en belirgin katman üzerinden plain Türkçe cümle kuruluyor.
    private var statusParagraph: some View {
        Text(statusSentence)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    private var statusSentence: String {
        let regimeText: String
        switch rating.regime {
        case .riskOn:  regimeText = "Genişleme rejimi"
        case .neutral: regimeText = "Karışık rejim"
        case .riskOff: regimeText = "Sıkılaşma rejimi"
        }

        // En yüksek katmanı bul → hangi katman destek veriyor?
        // 2026-05-05: Rating.{leading,coincident,lagging}Score son refactor'da Double? oldu
        // (OrionModels.swift:112-114). Veri eksikliğinde 0 fallback → hâlâ kıyaslanabilir.
        let scores: [(String, Double)] = [
            ("öncü göstergeler", rating.leadingScore ?? 0),
            ("eşzamanlı göstergeler", rating.coincidentScore ?? 0),
            ("gecikmeli göstergeler", rating.laggingScore ?? 0)
        ]
        let strongest = scores.max(by: { $0.1 < $1.1 })?.0 ?? "göstergeler"

        switch rating.regime {
        case .riskOn:
            return "\(regimeText). \(strongest.capitalized) destekleyici, risk iştahı pozitif."
        case .neutral:
            return "\(regimeText). \(strongest.capitalized) ön planda, yön belirsiz."
        case .riskOff:
            return "\(regimeText). \(strongest.capitalized) baskı yapıyor, koruma önemli."
        }
    }

    // MARK: - Bugün satırları (inline 3 indicator)

    /// rating.componentChanges'tan en belirgin 3 hareketi seçer.
    /// Boşsa kart hiç çizilmez.
    private var todayMovers: [TodayMover] {
        let pairs: [(String, String)] = [
            ("volatility", "Volatilite, VIX"),
            ("crypto", "Bitcoin"),
            ("dollar", "Dolar endeksi, DXY"),
            ("equity", "S&P 500"),
            ("gold", "Altın")
        ]
        let movers: [TodayMover] = pairs.compactMap { key, label in
            guard let change = rating.componentChanges[key] else { return nil }
            return TodayMover(label: label, change: change)
        }
        // Mutlak değere göre sırala, ilk 3'ü al.
        return movers.sorted { abs($0.change) > abs($1.change) }.prefix(3).map { $0 }
    }

    private struct TodayMover {
        let label: String
        let change: Double
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bugün")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(todayMovers.enumerated()), id: \.offset) { idx, mover in
                    HStack(spacing: 0) {
                        Text(mover.label)
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Text(String(format: "%@%.1f%%", mover.change >= 0 ? "+" : "", mover.change))
                            .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                            .foregroundColor(changeColor(mover.change))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if idx < todayMovers.count - 1 {
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

    private func changeColor(_ value: Double) -> Color {
        if abs(value) < 0.1 { return DesignTokens.Colors.textSecondary }
        return value >= 0 ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson
    }

    // MARK: - Ana navigasyon grubu

    private var navigationGroup: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: ExpectationsEntryView()) {
                hubRow(title: "Yaklaşan veriler", trailing: pendingCount > 0 ? "\(pendingCount)" : nil)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, 14)

            NavigationLink(destination: MyPredictionsView()) {
                hubRow(title: "Tahminlerim", trailing: predictionsTrailing)
            }
            .buttonStyle(.plain)
        }
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 18)
    }

    private var advancedGroup: some View {
        NavigationLink(destination: MakroIndicatorsListView(rating: rating)) {
            hubRow(title: "Tüm göstergeler", trailing: nil)
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func hubRow(title: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var pendingCount: Int {
        expectationsStore.getPendingExpectations().count
    }

    private var predictionsTrailing: String? {
        guard let summary = expectationsStore.getOverallAccuracy(lastN: 20) else {
            return nil
        }
        return String(format: "%%%.0f", summary.accuracy)
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Skor 30 günlük öncü, eşzamanlı ve gecikmeli göstergelerin ağırlıklı ortalamasından üretilir.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 14)
    }
}

// MARK: - MakroIndicatorsListView (Tüm göstergeler sub-page)
//
// Eski 3 katman expandable kart + skor formülü kartı buraya taşındı.
// Sade list dili: katman = grouped row, skor sağ tarafta sentence.
// Tıklandığında katmanın metricleri açılıyor (DisclosureGroup yerine
// inline expand state).

struct MakroIndicatorsListView: View {
    let rating: MacroEnvironmentRating

    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<MakroLayer> = []

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        layerGroup
                        formulaGroup
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
            Text("Tüm göstergeler")
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

    private var layerGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Katmanlar")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(MakroLayer.allCases.enumerated()), id: \.offset) { idx, layer in
                    layerRow(layer)
                    if expanded.contains(layer) {
                        layerMetrics(layer)
                    }
                    if idx < MakroLayer.allCases.count - 1 {
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

    private func layerRow(_ layer: MakroLayer) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expanded.contains(layer) {
                    expanded.remove(layer)
                } else {
                    expanded.insert(layer)
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.title)
                        .font(DesignTokens.Fonts.custom(size: 15))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(layer.subtitle)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Text("\(Int(score(for: layer)))")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(scoreColor(score(for: layer)))
                    .monospacedDigit()
                Image(systemName: expanded.contains(layer) ? "chevron.down" : "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func layerMetrics(_ layer: MakroLayer) -> some View {
        VStack(spacing: 0) {
            ForEach(metrics(for: layer), id: \.title) { metric in
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)
                    .padding(.leading, 14)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title)
                            .font(DesignTokens.Fonts.custom(size: 13))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Text(metric.detail)
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    if let change = metric.change {
                        Text(String(format: "%@%.1f%%", change >= 0 ? "+" : "", change))
                            .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                            .foregroundColor(metric.inverse
                                             ? (change <= 0 ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson)
                                             : (change >= 0 ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson))
                            .monospacedDigit()
                    }
                    Text("\(Int(metric.score ?? 50))")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(scoreColor(metric.score ?? 50))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .padding(.leading, 14)
            }
        }
        .background(DesignTokens.Colors.background.opacity(0.5))
    }

    private var formulaGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skor formülü")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("(Öncü × 1.5 + Eşzamanlı × 1.0 + Gecikmeli × 0.8) / 3.3")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("Öncü göstergeler erken sinyal verdiği için en yüksek ağırlığı taşır. Gecikmeli göstergeler onay rolündedir.")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Layer data

    enum MakroLayer: CaseIterable {
        case leading, coincident, lagging

        var title: String {
            switch self {
            case .leading: return "Öncü katman"
            case .coincident: return "Eşzamanlı katman"
            case .lagging: return "Gecikmeli katman"
            }
        }

        var subtitle: String {
            switch self {
            case .leading: return "VIX · faiz · ICSA · BTC"
            case .coincident: return "S&P · istihdam · DXY"
            case .lagging: return "CPI · işsizlik · altın"
            }
        }
    }

    private func score(for layer: MakroLayer) -> Double {
        // Rating.*Score Double? — veri henüz hesaplanmamışsa 0 ile clamp et (max(0, min(100, 0)) = 0).
        let value: Double
        switch layer {
        case .leading: value = rating.leadingScore ?? 0
        case .coincident: value = rating.coincidentScore ?? 0
        case .lagging: value = rating.laggingScore ?? 0
        }
        return max(0, min(100, value))
    }

    private struct LayerMetric {
        let title: String
        let detail: String
        let score: Double?
        let change: Double?
        let inverse: Bool
    }

    private func metrics(for layer: MakroLayer) -> [LayerMetric] {
        switch layer {
        case .leading:
            return [
                LayerMetric(title: "VIX", detail: "Volatilite, korku göstergesi", score: rating.volatilityScore, change: rating.componentChanges["volatility"], inverse: true),
                LayerMetric(title: "Faiz eğrisi", detail: "10Y–2Y yayılımı", score: rating.interestRateScore, change: nil, inverse: false),
                LayerMetric(title: "İşsizlik başvuruları", detail: "Haftalık ICSA eğilimi", score: rating.claimsScore, change: nil, inverse: true),
                LayerMetric(title: "Bitcoin", detail: "Risk iştahı proxy'si", score: rating.cryptoRiskScore, change: rating.componentChanges["crypto"], inverse: false)
            ]
        case .coincident:
            return [
                LayerMetric(title: "S&P 500", detail: "Piyasa yönü", score: rating.equityRiskScore, change: rating.componentChanges["equity"], inverse: false),
                LayerMetric(title: "İstihdam", detail: "Büyüme temposu", score: rating.growthScore, change: nil, inverse: false),
                LayerMetric(title: "DXY", detail: "Dolar baskısı", score: rating.currencyScore, change: rating.componentChanges["dollar"], inverse: true)
            ]
        case .lagging:
            return [
                LayerMetric(title: "CPI", detail: "Enflasyon yönü", score: rating.inflationScore, change: nil, inverse: true),
                LayerMetric(title: "İşsizlik", detail: "Gecikmeli iş gücü etkisi", score: rating.laborScore, change: nil, inverse: true),
                LayerMetric(title: "Altın, GLD", detail: "Güvenli liman eğilimi", score: rating.safeHavenScore, change: rating.componentChanges["gold"], inverse: true)
            ]
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}

// MARK: - MyPredictionsView (Tahminlerim sub-page)
//
// Önceki accuracyCard + indicatorAccuracyRow buraya taşındı, ayrı bir
// sub-page olarak. Hero %X + indicator breakdown + geçmiş tahminler.

struct MyPredictionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ExpectationsStore.shared

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topNav
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        accuracyHero
                        indicatorBreakdown
                        historyList
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
            Text("Tahminlerim")
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

    private var accuracyHero: some View {
        Group {
            if let summary = store.getOverallAccuracy(lastN: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Son \(summary.total) tahminin \(summary.correct) tanesi tutmuş.")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text("Sapma her gösterge için ayrı eşikle değerlendirilir.")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.bottom, 22)
            } else {
                Text("Henüz olgunlaşmış tahmin yok. Veri açıklandıkça burada görünecek.")
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)
            }
        }
    }

    private var indicatorBreakdown: some View {
        let rows = ExpectationsStore.EconomicIndicator.allCases.compactMap { indicator -> (ExpectationsStore.EconomicIndicator, ExpectationsStore.AccuracySummary)? in
            guard let s = store.getAccuracySummary(for: indicator, lastN: 10) else { return nil }
            return (indicator, s)
        }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Göstergeye göre")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .padding(.leading, 2)

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                            HStack {
                                Text(row.0.shortName)
                                    .font(DesignTokens.Fonts.custom(size: 14))
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Spacer()
                                Text("\(row.1.correct) / \(row.1.total)")
                                    .font(DesignTokens.Fonts.custom(size: 12))
                                    .foregroundColor(DesignTokens.Colors.textTertiary)
                                    .monospacedDigit()
                                Text(String(format: "%%%.0f", row.1.accuracy))
                                    .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                                    .foregroundColor(accuracyColor(row.1.accuracy))
                                    .monospacedDigit()
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            if idx < rows.count - 1 {
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
        }
    }

    private var historyList: some View {
        let history = store.getRecentSurprises().prefix(20)
        return Group {
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Geçmiş tahminler")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .padding(.leading, 2)

                    VStack(spacing: 0) {
                        ForEach(Array(history.enumerated()), id: \.offset) { idx, entry in
                            historyRow(entry)
                            if idx < history.count - 1 {
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
        }
    }

    private func historyRow(_ entry: ExpectationsStore.ExpectationEntry) -> some View {
        let surprise = entry.surprise ?? 0
        let isCorrect = entry.isCorrect == true
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.indicator.shortName)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(historySubtitle(entry, isCorrect: isCorrect))
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            if let actual = entry.actualValue {
                Text(String(format: "%.1f / %.1f", actual, entry.expectedValue))
                    .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
            }
            Text(String(format: "%@%.2f%@", surprise >= 0 ? "+" : "", surprise, entry.indicator.unit))
                .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                .foregroundColor(isCorrect ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func historySubtitle(_ entry: ExpectationsStore.ExpectationEntry, isCorrect: Bool) -> String {
        let when: String
        if let date = entry.announcedAt {
            let elapsed = Date().timeIntervalSince(date)
            if elapsed < 86400 { when = "bugün" }
            else if elapsed < 86400 * 2 { when = "dün" }
            else { when = "\(Int(elapsed / 86400)) gün önce" }
        } else {
            when = "—"
        }
        return "\(when) · \(isCorrect ? "isabet" : "sapma")"
    }

    private func accuracyColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}

// MARK: - Indicator helpers

extension ExpectationsStore.EconomicIndicator {
    /// Liste sayfaları için kısa isim — displayName parantez vs içeriyor.
    var shortName: String {
        switch self {
        case .cpi: return "CPI"
        case .unemployment: return "İşsizlik"
        case .payrolls: return "İstihdam"
        case .claims: return "İşsizlik başvurusu"
        case .pce: return "PCE"
        case .gdp: return "GDP"
        }
    }
}
