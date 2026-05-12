import SwiftUI

// MARK: - Modül detay overlay (eski adıyla Orion Module Detail)
//
// 2026-05-04 H-63 — sade refactor.
// Eski yapı: motor(.orion) tint sarmalı + ArgusSectionCaption "CANLI ANALİZ"
// caps + 13.5pt monospaced colored segment text + technicalCard caps mono
// başlık + ArgusChip delta rozeti + 9pt black mono caption + 16pt black
// mono değer + DisclosureGroup "ÖĞREN · X NEDİR?" caps + bottom action bar
// solid motor button + emptyChartLabel uppercased.
//
// Yeni dil:
//   • Üst nav: chevron + ortalı node başlığı + alt "Teknik · SYMBOL" + xmark
//   • Canlı analiz: sentence dynamic text (system font), inline renk vurgusu
//   • Göstergeler: sade kart başlığı + büyük renkli skor + sade chart
//   • "Bu nedir?" mini açıklama (DisclosureGroup yerine inline)
//   • Bottom outline butonlar (Alarm + Paylaş)
//
// Public API korundu: `init(type:, symbol:, analysis:, candles:, onClose:)`.

struct OrionModuleDetailView: View {
    let type: CircuitNode
    let symbol: String
    let analysis: OrionScoreResult
    let candles: [Candle]
    let onClose: () -> Void

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(spacing: 12) {
                        liveAnalysisCard
                        indicatorsSection
                        learningCard

                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }

            VStack {
                Spacer()
                bottomActionBar
            }
        }
    }

    // MARK: - Üst nav

    private var topNav: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(nodeTitle)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("Teknik · \(symbol.uppercased())")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var nodeTitle: String {
        switch type {
        case .trend:     return "Trend"
        case .momentum:  return "Momentum"
        case .structure: return "Yapı"
        case .pattern:   return "Formasyon"
        default:         return "Detay"
        }
    }

    // MARK: - Canlı analiz kartı (sentence + inline renk vurgusu)

    private var liveAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Canlı analiz")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("son \(min(50, candles.count)) mum")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            // OrionTextGenerator zaten colored segments üretiyor — bunu sade
            // dile uyarlamak için system font + 13pt + lineSpacing 4. Renk
            // vurguları korunuyor (skoru sözle açıklayan yapı için kritik).
            let dynamicText = getDynamicText()
            dynamicText.segments
                .reduce(Text("")) { result, segment in
                    result + Text(segment.text)
                        .foregroundColor(segment.color)
                        .fontWeight(segment.isBold ? .medium : .regular)
                }
                .font(DesignTokens.Fonts.custom(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Göstergeler (4 node case)

    @ViewBuilder
    private var indicatorsSection: some View {
        switch type {
        case .trend:
            indicatorCard(
                title: "Hareketli ortalamalar",
                subtitle: "Fiyat / SMA(10)",
                value: String(format: "%.2f", candles.last?.close ?? 0),
                valueColor: priceDeltaColor,
                meta: getPriceChangeText()
            ) {
                maChart
            }

            indicatorCard(
                title: "RSI (14)",
                subtitle: "Göreceli güç endeksi",
                value: String(format: "%.0f", analysis.components.rsi ?? 50),
                valueColor: rsiColor(analysis.components.rsi ?? 50),
                meta: rsiZoneLabel(analysis.components.rsi ?? 50)
            ) {
                rsiChart
            }

        case .momentum:
            indicatorCard(
                title: "RSI (14)",
                subtitle: "Göreceli güç endeksi",
                value: String(format: "%.0f", analysis.components.rsi ?? 50),
                valueColor: rsiColor(analysis.components.rsi ?? 50),
                meta: rsiZoneLabel(analysis.components.rsi ?? 50)
            ) {
                rsiChart
            }

            indicatorCard(
                title: "Hız",
                subtitle: "Velocity (5 mum)",
                value: getPriceChangeText(),
                valueColor: priceDeltaColor,
                meta: nil
            ) {
                EmptyView()
            }

        case .structure:
            indicatorCard(
                title: "Hacim",
                subtitle: "Son 50 mum",
                value: "\(Int(analysis.components.structure))",
                valueColor: scoreColor(analysis.components.structure / 35.0),
                meta: "/ 35"
            ) {
                volumeChart
            }

        case .pattern:
            patternCard

        default:
            EmptyView()
        }
    }

    private func indicatorCard<Content: View>(
        title: String,
        subtitle: String,
        value: String,
        valueColor: Color,
        meta: String?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(subtitle)
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(DesignTokens.Fonts.custom(size: 22, weight: .medium))
                        .foregroundColor(valueColor)
                        .monospacedDigit()
                    if let meta = meta {
                        Text(meta)
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                }
            }

            // Sade hairline ayraç
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)

            content()
                .frame(height: 90)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    /// Pattern özel kartı — sketch + opsiyonel açıklama
    private var patternCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Formasyon")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(analysis.components.patternDesc.isEmpty || analysis.components.patternDesc == "Yok"
                         ? "Tespit yok"
                         : analysis.components.patternDesc)
                        .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }
                Spacer()
            }

            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)

            patternSketch
                .frame(height: 90)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Charts (sade)

    private var rsiChart: some View {
        GeometryReader { geo in
            let prices = candles.suffix(50).map { $0.close }
            if prices.isEmpty {
                emptyChartLabel("Veri yok")
            } else {
                let rsiData = OrionChartHelpers.calculateRSI(period: 14, prices: prices)
                let normalized = OrionChartHelpers.normalize(rsiData)

                ZStack {
                    // Aşırı alım/satım bölgeleri çok soluk
                    VStack(spacing: 0) {
                        InstitutionalTheme.Colors.crimson.opacity(0.06)
                            .frame(height: geo.size.height * 0.3)
                        Color.clear.frame(height: geo.size.height * 0.4)
                        InstitutionalTheme.Colors.aurora.opacity(0.06)
                            .frame(height: geo.size.height * 0.3)
                    }

                    Path { path in
                        let width = geo.size.width
                        let height = geo.size.height
                        guard normalized.count > 1 else { return }
                        let step = width / CGFloat(normalized.count - 1)
                        for (index, value) in normalized.enumerated() {
                            if value.isNaN || value.isInfinite { continue }
                            let x = CGFloat(index) * step
                            let y = height - (CGFloat(value) * height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(InstitutionalTheme.Colors.holo,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private var maChart: some View {
        GeometryReader { geo in
            let prices = candles.suffix(50).map { $0.close }
            if prices.isEmpty {
                emptyChartLabel("Veri yok")
            } else {
                let normPrices = OrionChartHelpers.normalize(prices)
                let sma = OrionChartHelpers.calculateSMA(period: 10, prices: prices)
                let normSMA = OrionChartHelpers.normalize(sma)

                ZStack {
                    pathShape(values: normPrices, in: geo.size)
                        .stroke(DesignTokens.Colors.textPrimary,
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    pathShape(values: normSMA, in: geo.size)
                        .stroke(InstitutionalTheme.Colors.titan,
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
    }

    private func pathShape(values: [Double], in size: CGSize) -> Path {
        Path { path in
            let step = size.width / CGFloat(max(values.count - 1, 1))
            for (index, value) in values.enumerated() {
                if value.isNaN || value.isInfinite { continue }
                let x = CGFloat(index) * step
                let y = size.height - (CGFloat(value) * size.height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private var volumeChart: some View {
        GeometryReader { geo in
            let lastCandles = Array(candles.suffix(50))
            let volumes = lastCandles.map { Double($0.volume) }

            if volumes.isEmpty {
                emptyChartLabel("Hacim verisi yok")
            } else {
                let maxVol = max(volumes.max() ?? 1.0, 1.0)
                let count = CGFloat(volumes.count)
                let step = geo.size.width / count
                let height = geo.size.height

                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(0..<lastCandles.count, id: \.self) { i in
                        let vol = volumes[i]
                        let barH = (vol / maxVol) * Double(height)
                        let safeBarH = barH.isNaN ? 0 : CGFloat(max(barH, 1.0))
                        Rectangle()
                            .fill(lastCandles[i].close >= lastCandles[i].open
                                  ? InstitutionalTheme.Colors.aurora.opacity(0.6)
                                  : InstitutionalTheme.Colors.crimson.opacity(0.6))
                            .frame(width: max(step - 1, 1), height: safeBarH)
                    }
                }
            }
        }
    }

    private var patternSketch: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.8))
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.2),
                    control1: CGPoint(x: w * 0.4, y: h * 0.1),
                    control2: CGPoint(x: w * 0.6, y: h * 0.9)
                )
            }
            .stroke(DesignTokens.Colors.textSecondary,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
        }
    }

    private func emptyChartLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - "Bu nedir?" mini açıklama

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bu nedir?")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text(type.educationalContent(for: analysis))
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    DesignTokens.Colors.borderSubtle,
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bottom action bar (sade outline)

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "bell")
                        .font(DesignTokens.Fonts.custom(size: 12))
                    Text("Alarm")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                }
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DesignTokens.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(DesignTokens.Fonts.custom(size: 12))
                    Text("Paylaş")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                }
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DesignTokens.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.Colors.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
    }

    private func getDynamicText() -> DynamicAnalysisText {
        switch type {
        case .trend:     return OrionTextGenerator.generateTrendText(for: analysis)
        case .momentum:  return OrionTextGenerator.generateMomentumText(for: analysis)
        case .structure: return OrionTextGenerator.generateStructureText(for: analysis)
        case .pattern:   return OrionTextGenerator.generatePatternText(for: analysis)
        default:         return DynamicAnalysisText(segments: [])
        }
    }

    private func getPriceChangeText() -> String {
        guard let last = candles.last,
              let prev = candles.dropLast().last else { return "0%" }
        let diff = (last.close - prev.close) / prev.close * 100
        return String(format: "%+.2f%%", diff)
    }

    private var priceDeltaColor: Color {
        guard let last = candles.last,
              let prev = candles.dropLast().last else { return DesignTokens.Colors.textPrimary }
        if last.close > prev.close { return InstitutionalTheme.Colors.aurora }
        if last.close < prev.close { return InstitutionalTheme.Colors.crimson }
        return DesignTokens.Colors.textPrimary
    }

    private func rsiColor(_ rsi: Double) -> Color {
        if rsi >= 70 { return InstitutionalTheme.Colors.crimson }
        if rsi <= 30 { return InstitutionalTheme.Colors.crimson }
        if rsi >= 55 { return InstitutionalTheme.Colors.aurora }
        if rsi <= 45 { return InstitutionalTheme.Colors.titan }
        return DesignTokens.Colors.textPrimary
    }

    private func rsiZoneLabel(_ rsi: Double) -> String {
        if rsi >= 70 { return "aşırı alım" }
        if rsi <= 30 { return "aşırı satım" }
        if rsi >= 55 { return "güçlü" }
        if rsi <= 45 { return "zayıf" }
        return "nötr"
    }

    private func scoreColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return InstitutionalTheme.Colors.aurora }
        if rate >= 0.45 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}
