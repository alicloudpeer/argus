import SwiftUI
import Charts

// 2026-04-30 H-58 — sade refactor.
// Eski yapı V5: ArgusOrb + MotorLogo(.prometheus) + caps "PROMETHEUS · FIYAT
// PROJEKSİYONU" başlık + caps mono "TAHMİN" + 28pt black mono fiyat + ArgusPill
// uppercased + caps mono mini metric titles + motor tint border.
// Yeni: "Tahmin" sentence başlık + sentence "Fiyat projeksiyonu" subtitle +
// 28pt medium fiyat + sade hairline kart + sentence "Al/Tut/Sat" + sentence
// metric başlıkları + sade numaralı liste.

struct PrometheusPanelView: View {
    let symbol: String
    let candles: [Candle]

    @State private var forecast: PrometheusForecast?
    @State private var isLoading = false

    private var historicalTail: [Candle] {
        Array(candles.suffix(80))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryCard
            continuationChartCard
            rationaleCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadForecast()
        }
    }

    // MARK: - Header (sade)

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tahmin")
                .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text("Kısa vadeli fiyat projeksiyonu")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        Group {
            if isLoading {
                loadingBlock
            } else if let f = forecast, f.isValid {
                VStack(alignment: .leading, spacing: 12) {

                    // Üst satır: tavsiye + ufuk
                    HStack(spacing: 10) {
                        Text(recommendationLabel(f.recommendation))
                            .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                            .foregroundColor(recommendationColor(f.recommendation))
                        Spacer()
                        Text("\(f.horizonDays) gün")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }

                    // Tahmin fiyatı
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tahmin")
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(formatPrice(f.predictedPrice))
                                .font(DesignTokens.Fonts.custom(size: 28, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .monospacedDigit()
                            Text(f.formattedChange)
                                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                                .foregroundColor(recommendationColor(f.recommendation))
                                .monospacedDigit()
                        }
                    }

                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 0.5)

                    HStack(spacing: 12) {
                        sadeMetric("Şimdi", value: formatPrice(f.currentPrice))
                        sadeMetric("Güven", value: "%\(Int(f.confidence))",
                                   color: confidenceColor(f.confidence))
                        sadeMetric("MAPE", value: String(format: "%.2f%%", f.validationMAPE))
                    }

                    HStack(spacing: 12) {
                        sadeMetric("Yön isabeti",
                                   value: String(format: "%.1f%%", f.directionalAccuracy * 100),
                                   color: f.directionalAccuracy >= 0.55
                                          ? InstitutionalTheme.Colors.aurora
                                          : InstitutionalTheme.Colors.titan)
                        sadeMetric("Veri", value: "\(f.dataPointsUsed) bar")
                    }
                }
            } else {
                missingDataBlock
            }
        }
        .padding(14)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    /// Sade metrik kutusu — sentence başlık + değer.
    private func sadeMetric(_ title: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(color ?? DesignTokens.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return DesignTokens.Colors.textPrimary }
        if value >= 30 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func recommendationColor(_ rec: PrometheusRecommendation) -> Color {
        switch rec {
        case .buy:  return InstitutionalTheme.Colors.aurora
        case .sell: return InstitutionalTheme.Colors.crimson
        case .hold: return InstitutionalTheme.Colors.titan
        }
    }

    private func recommendationLabel(_ rec: PrometheusRecommendation) -> String {
        switch rec {
        case .buy:  return "Al"
        case .sell: return "Sat"
        case .hold: return "Tut"
        }
    }

    // MARK: - Chart card

    private var continuationChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fiyat devam grafiği")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                if let f = forecast, f.isValid {
                    Text("\(historicalTail.count) + \(f.predictions.count)")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
            }

            if let f = forecast, f.isValid, !historicalTail.isEmpty {
                let chartData = buildChartData(forecast: f, history: historicalTail)
                let lineColor = DesignTokens.Colors.textPrimary

                Chart {
                    ForEach(chartData.history) { p in
                        LineMark(
                            x: .value("Tarih", p.date),
                            y: .value("Fiyat", p.price)
                        )
                        .foregroundStyle(DesignTokens.Colors.textSecondary.opacity(0.85))
                    }

                    ForEach(chartData.future) { p in
                        LineMark(
                            x: .value("Tarih", p.date),
                            y: .value("Tahmin", p.price)
                        )
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }

                    ForEach(chartData.futureBand) { p in
                        AreaMark(
                            x: .value("Tarih", p.date),
                            yStart: .value("Alt", p.lower),
                            yEnd: .value("Üst", p.upper)
                        )
                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.08))
                    }
                }
                .frame(height: 230)

                HStack(spacing: 14) {
                    legendDot(color: DesignTokens.Colors.textSecondary, label: "geçmiş")
                    legendDot(color: DesignTokens.Colors.textPrimary, label: "tahmin")
                    legendDot(color: DesignTokens.Colors.textPrimary.opacity(0.3),
                              label: "güven aralığı")
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DesignTokens.Colors.textTertiary)
                        .frame(width: 4, height: 4)
                    Text("Grafik için tahmin verisi yok.")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - Rationale card

    private var rationaleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Neden bu karar")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            if let f = forecast, !f.rationale.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(f.rationale.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(idx + 1).")
                                .font(DesignTokens.Fonts.custom(size: 12))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                                .monospacedDigit()
                                .frame(width: 18, alignment: .leading)
                            Text(line)
                                .font(DesignTokens.Fonts.custom(size: 13))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DesignTokens.Colors.textTertiary)
                        .frame(width: 4, height: 4)
                    Text("Açıklama verisi hazır değil.")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    // MARK: - States

    private var loadingBlock: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Tahmin hesaplanıyor")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private var missingDataBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(DesignTokens.Fonts.custom(size: 18))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text("Tahmin için yeterli veri yok")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Double) -> String {
        let isBist = symbol.uppercased().hasSuffix(".IS")
        let currency = isBist ? "₺" : "$"
        if price > 1000 { return String(format: "%@%.0f", currency, price) }
        if price > 1 { return String(format: "%@%.2f", currency, price) }
        return String(format: "%@%.4f", currency, price)
    }

    private func loadForecast() async {
        isLoading = true
        defer { isLoading = false }
        forecast = await PrometheusEngine.shared.forecast(
            symbol: symbol,
            historicalPrices: candles.map(\.close)
        )
    }

    private func buildChartData(forecast: PrometheusForecast, history: [Candle]) -> PrometheusChartData {
        let historyPoints = history.map { PricePoint(date: $0.date, price: $0.close) }
        guard let lastDate = history.last?.date else {
            return PrometheusChartData(history: historyPoints, future: [], futureBand: [])
        }

        var future: [PricePoint] = []
        var futureBand: [BandPoint] = []

        for i in 0..<forecast.predictions.count {
            let date = nextTradingDate(from: lastDate, offset: i + 1)
            future.append(PricePoint(date: date, price: forecast.predictions[i]))
            if i < forecast.lowerBand.count && i < forecast.upperBand.count {
                futureBand.append(BandPoint(date: date, lower: forecast.lowerBand[i], upper: forecast.upperBand[i]))
            }
        }

        return PrometheusChartData(history: historyPoints, future: future, futureBand: futureBand)
    }

    private func nextTradingDate(from start: Date, offset: Int) -> Date {
        var date = start
        var advanced = 0
        let calendar = Calendar.current
        while advanced < offset {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            let weekday = calendar.component(.weekday, from: date)
            if weekday != 1 && weekday != 7 {
                advanced += 1
            }
        }
        return date
    }
}

private struct PrometheusChartData {
    let history: [PricePoint]
    let future: [PricePoint]
    let futureBand: [BandPoint]
}

private struct PricePoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
}

private struct BandPoint: Identifiable {
    let id = UUID()
    let date: Date
    let lower: Double
    let upper: Double
}
