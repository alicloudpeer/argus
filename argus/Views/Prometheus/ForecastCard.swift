import SwiftUI

// MARK: - ForecastCard (Tahmin modülü 5-gün)
//
// 2026-05-05 H-67 — sıfırdan sade refactor.
//
// Eski V5: MotorLogo(.prometheus) + "PROMETHEUS · PROJEKSİYON" caps
// section caption + "UFUK · 5G" chip, "ŞİMDİ / 5 GÜN SONRA" 9pt bold
// mono tracking 0.8 caps, 18pt black mono fiyat, "GÜVEN" caps + bar +
// confidenceLevel.uppercased(), ArgusDot bullet + insight, prometheus
// motor tinted border (opacity 0.3), insufficient caps mono tracking
// 0.5.
//
// Yeni dil: sade başlık (Tahmin · 5 günlük), sentence case price label
// (Şimdi / +5 gün), 17pt medium fiyat, "Güven %60 · yüksek" tek satır,
// plain insight metni, hairline borderSubtle.

struct ForecastCard: View {
    let symbol: String
    let historicalPrices: [Double]

    @State private var forecast: PrometheusForecast?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                loadingBlock
            } else if let f = forecast, f.isValid {
                priceRow(f)
                trendLine(f)

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                ForecastMiniChart(
                    currentPrice: f.currentPrice,
                    predictions: f.predictions,
                    trend: f.trend
                )
                .frame(height: 60)

                confidenceRow(f)
                insightLine(f)
                footerLine
            } else {
                insufficientBlock
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { await loadForecast() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Tahmin")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text("\(forecast?.horizonDays ?? 5) günlük")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
    }

    private func priceRow(_ f: PrometheusForecast) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Şimdi")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(formatPrice(f.currentPrice))
                    .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
            }

            Spacer()

            Image(systemName: f.trend.icon)
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(trendColor(f.trend))

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("+\(f.horizonDays) gün")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(formatPrice(f.predictedPrice))
                    .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                    .foregroundColor(trendColor(f.trend))
                    .monospacedDigit()
            }
        }
    }

    private func trendLine(_ f: PrometheusForecast) -> some View {
        HStack(spacing: 6) {
            Text(f.formattedChange)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(trendColor(f.trend))
                .monospacedDigit()
            Text("·")
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(trendLabel(f.trend))
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    private func confidenceRow(_ f: PrometheusForecast) -> some View {
        HStack(spacing: 10) {
            Text("Güven")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .frame(width: 50, alignment: .leading)

            ArgusBar(value: max(0, min(1, f.confidence / 100)),
                     color: confidenceColor(f.confidence),
                     height: 4)

            Text("%\(Int(f.confidence))")
                .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)

            Text(confidenceLabel(f.confidence))
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(confidenceColor(f.confidence))
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func insightLine(_ f: PrometheusForecast) -> some View {
        Text(generateInsight(trend: f.trend, confidence: f.confidence))
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerLine: some View {
        Text("Holt-Winters üstel düzleştirme")
            .font(DesignTokens.Fonts.custom(size: 11))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Tahmin hesaplanıyor…")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var insufficientBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Yeterli veri yok")
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text("En az 30 günlük fiyat geçmişi gerekiyor.")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers (sade dilde)

    private func trendColor(_ t: PrometheusTrend) -> Color {
        switch t {
        case .strongBullish, .bullish: return InstitutionalTheme.Colors.aurora
        case .neutral:                 return DesignTokens.Colors.textSecondary
        case .bearish, .strongBearish: return InstitutionalTheme.Colors.crimson
        }
    }

    private func trendLabel(_ t: PrometheusTrend) -> String {
        switch t {
        case .strongBullish: return "Güçlü yukarı"
        case .bullish:       return "Yukarı yönlü"
        case .neutral:       return "Yatay"
        case .bearish:       return "Aşağı yönlü"
        case .strongBearish: return "Güçlü aşağı"
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        if c >= 70 { return InstitutionalTheme.Colors.aurora }
        if c >= 50 { return DesignTokens.Colors.textPrimary }
        if c >= 30 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func confidenceLabel(_ c: Double) -> String {
        if c >= 70 { return "yüksek" }
        if c >= 50 { return "orta" }
        if c >= 30 { return "düşük" }
        return "zayıf"
    }

    private func loadForecast() async {
        isLoading = true
        forecast = await PrometheusEngine.shared.forecast(
            symbol: symbol,
            historicalPrices: historicalPrices
        )
        isLoading = false
    }

    private func formatPrice(_ price: Double) -> String {
        let isBist = symbol.uppercased().hasSuffix(".IS")
        let currency = isBist ? "₺" : "$"
        if price > 1000 {
            return String(format: "%@%.0f", currency, price)
        } else if price > 1 {
            return String(format: "%@%.2f", currency, price)
        } else {
            return String(format: "%@%.4f", currency, price)
        }
    }

    private func generateInsight(trend: PrometheusTrend, confidence: Double) -> String {
        let qualifier = confidence < 50 ? " Güven düşük; tek başına işlem sinyali olarak kullanılmamalı." : ""
        switch trend {
        case .strongBullish:
            return "Mevcut trend devam ederse ufuk sonunda yukarı yönlü projeksiyon güçlü." + qualifier
        case .bullish:
            return "Son trendin sönümlü uzantısı yukarı yönlü; kısa vadeli geri çekilmeler bu projeksiyonu doğrudan değiştirmez." + qualifier
        case .neutral:
            return "Belirgin bir yön yok. Projeksiyon mevcut seviyenin etrafında kalıyor." + qualifier
        case .bearish:
            return "Son trendin sönümlü uzantısı aşağı yönlü." + qualifier
        case .strongBearish:
            return "Mevcut serinin lineer projeksiyonu belirgin aşağı yönlü; bant genişliği riski büyütüyor." + qualifier
        }
    }
}

// MARK: - ForecastMiniChart
//
// Tek renk çizgi + nokta. Trend rengi: aurora/crimson/textSecondary.
// Mevcut nokta textPrimary, gelecek noktalar trend renginde.

struct ForecastMiniChart: View {
    let currentPrice: Double
    let predictions: [Double]
    let trend: PrometheusTrend

    var body: some View {
        GeometryReader { geo in
            let allPrices = [currentPrice] + predictions
            let minPrice = allPrices.min() ?? 0
            let maxPrice = allPrices.max() ?? 1
            let range = max(maxPrice - minPrice, 0.01)

            Path { path in
                for (index, price) in allPrices.enumerated() {
                    let x = (geo.size.width / CGFloat(allPrices.count - 1)) * CGFloat(index)
                    let y = geo.size.height - ((price - minPrice) / range * geo.size.height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(trendColor,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            ForEach(0..<allPrices.count, id: \.self) { index in
                let x = (geo.size.width / CGFloat(allPrices.count - 1)) * CGFloat(index)
                let price = allPrices[index]
                let y = geo.size.height - ((price - minPrice) / range * geo.size.height)

                Circle()
                    .fill(index == 0
                          ? DesignTokens.Colors.textPrimary
                          : trendColor)
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
            }
        }
    }

    private var trendColor: Color {
        switch trend {
        case .strongBullish, .bullish: return InstitutionalTheme.Colors.aurora
        case .neutral:                 return DesignTokens.Colors.textSecondary
        case .bearish, .strongBearish: return InstitutionalTheme.Colors.crimson
        }
    }
}

#Preview {
    ZStack {
        DesignTokens.Colors.background.ignoresSafeArea()
        ForecastCard(
            symbol: "AAPL",
            historicalPrices: Array(stride(from: 180.0, through: 195.0, by: 0.5))
        )
        .padding()
    }
}
