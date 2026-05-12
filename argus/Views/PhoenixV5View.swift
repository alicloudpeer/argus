import SwiftUI

/// Risk fırsatları ekranı (eski adıyla Phoenix V5).
/// Dip dedektörü — aşırı-satım + destek testi + dönüş mumu onayları.
/// Veri: `PhoenixAdvice` modeli (PhoenixScenarioEngine'den).
///
/// 2026-04-30 H-58 — sade refactor.
/// Eski yapı: MotorLogo(.phoenix) + caps "PHOENIX" + caps "X KÜL" chip +
/// caps "DÖNÜŞ KONTROL LİSTESİ" + caps "DİĞER KÜLDENİRİŞ ADAYLARI" (mitoloji
/// "kül" kelimesi) + statTile caps mono ("DÜŞÜŞ" "DESTEK" "HEDEF") + raw
/// hex gradient daireler. Yeni: "Risk fırsatları" sentence başlık + sade
/// hairline kartlar + sentence başlıklar + sade text counter.
struct PhoenixV5View: View {
    @ObservedObject private var marketVM = MarketViewModel.shared
    @Environment(\.presentationMode) var presentationMode

    /// Ana sembol (mevcut StockDetail'ten gelebilir) veya liste modu (nil).
    let primarySymbol: String?

    init(primarySymbol: String? = nil) {
        self.primarySymbol = primarySymbol
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navbar
                    if let main = mainAdvice {
                        mainCandidateCard(advice: main)
                        checklistCard(advice: main)
                    } else {
                        ArgusEmptyState(
                            icon: "chart.line.downtrend.xyaxis",
                            title: "Aday yok",
                            message: "Bu sembol için dip dedektörü henüz uyanmadı."
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                    }
                    otherCandidates
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Navbar (sade)

    private var navbar: some View {
        HStack(spacing: 12) {
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(DesignTokens.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Risk fırsatları")
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("Dip dedektörü, dönüş onayları")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            Text("\(otherSymbols.count + (mainAdvice != nil ? 1 : 0)) aday")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            DesignTokens.Colors.surface
                .overlay(
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 0.5),
                    alignment: .bottom
                )
        )
    }

    // MARK: - Ana aday kartı (sade)

    private func mainCandidateCard(advice: PhoenixAdvice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(advice.symbol)
                            .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        if let price = currentPrice(for: advice.symbol) {
                            Text(formatPrice(price, symbol: advice.symbol))
                                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .monospacedDigit()
                        }
                    }
                    Text(scenarioSummary(advice))
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Güven")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Text("\(Int(advice.confidence))")
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                        .foregroundColor(confidenceColor(advice.confidence))
                        .monospacedDigit()
                }
            }

            // Mini grafik
            if let candles = marketVM.candles[advice.symbol], candles.count >= 2 {
                SanctumMiniChart(candles: candles.suffix(60).map { $0 },
                               color: advice.status == .active
                                   ? DesignTokens.Colors.success
                                   : DesignTokens.Colors.error)
                    .frame(height: 66)
            }

            HStack(spacing: 6) {
                statTile(title: "Düşüş",
                         value: drawdownText(advice),
                         color: InstitutionalTheme.Colors.crimson)
                statTile(title: "Destek",
                         value: formatPriceOptional(advice.channelLower, advice.symbol),
                         color: DesignTokens.Colors.textPrimary)
                statTile(title: "Hedef",
                         value: formatPriceOptional(advice.targets.first, advice.symbol),
                         color: InstitutionalTheme.Colors.aurora)
            }
        }
        .padding(14)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func statTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Checklist (sade)

    private func checklistCard(advice: PhoenixAdvice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dönüş kontrol listesi")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            VStack(spacing: 8) {
                checklistRow(done: advice.triggers.touchLowerBand,
                             text: "Aşırı-satım (RSI < 25) / kanal dibi")
                checklistRow(done: advice.triggers.trendOk,
                             text: "Temel destek test edildi")
                checklistRow(done: advice.triggers.bullishDivergence,
                             text: "Boğa ayrışması (divergence)")
                checklistRow(done: advice.triggers.rsiReversal,
                             text: "RSI dönüş mumu")
                checklistRow(done: nil,
                             text: "Pozitif katalizör (haber bekleniyor)")
            }
            .padding(12)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func checklistRow(done: Bool?, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: checklistIcon(done))
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(checklistColor(done))
                .frame(width: 18)
            Text(text)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(done == true
                                 ? DesignTokens.Colors.textPrimary
                                 : DesignTokens.Colors.textSecondary)
            Spacer()
        }
    }

    private func checklistIcon(_ done: Bool?) -> String {
        if done == true  { return "checkmark.circle.fill" }
        if done == false { return "minus.circle" }
        return "circle"
    }

    private func checklistColor(_ done: Bool?) -> Color {
        if done == true  { return InstitutionalTheme.Colors.aurora }
        if done == false { return InstitutionalTheme.Colors.titan }
        return DesignTokens.Colors.textTertiary
    }

    // MARK: - Diğer adaylar (sade)

    private var otherCandidates: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !otherSymbols.isEmpty {
                Text("Diğer adaylar")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)

                VStack(spacing: 6) {
                    ForEach(otherSymbols.prefix(6), id: \.self) { sym in
                        if let adv = phoenixAdvice(for: sym) {
                            otherCandidateRow(sym: sym, advice: adv)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 120)
    }

    private func otherCandidateRow(sym: String, advice: PhoenixAdvice) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sym)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(advice.reasonShort.isEmpty ? "İzle" : advice.reasonShort)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(
                        advice.status == .active
                            ? InstitutionalTheme.Colors.aurora
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)
            }

            Spacer()

            Text("\(Int(advice.confidence))")
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(confidenceColor(advice.confidence))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    // MARK: - Veri

    private var allPhoenixResults: [String: PhoenixAdvice] {
        SignalStateViewModel.shared.phoenixResults
    }

    private var mainAdvice: PhoenixAdvice? {
        if let sym = primarySymbol {
            return allPhoenixResults[sym]
        }
        return allPhoenixResults.values
            .filter { $0.status == .active }
            .max(by: { $0.confidence < $1.confidence })
    }

    private var otherSymbols: [String] {
        let mainSym = mainAdvice?.symbol
        return allPhoenixResults
            .filter { $0.value.status != .error && $0.key != mainSym }
            .sorted { $0.value.confidence > $1.value.confidence }
            .map { $0.key }
    }

    private func phoenixAdvice(for symbol: String) -> PhoenixAdvice? {
        allPhoenixResults[symbol]
    }

    private func currentPrice(for symbol: String) -> Double? {
        MarketDataStore.shared.getQuote(for: symbol)?.currentPrice
            ?? marketVM.quotes[symbol]?.currentPrice
    }

    private func formatPrice(_ price: Double, symbol: String) -> String {
        let isBist = symbol.uppercased().hasSuffix(".IS")
        return String(format: isBist ? "₺%.2f" : "$%.2f", price)
    }

    private func formatPriceOptional(_ price: Double?, _ symbol: String) -> String {
        guard let p = price else { return "—" }
        return formatPrice(p, symbol: symbol)
    }

    private func drawdownText(_ advice: PhoenixAdvice) -> String {
        guard let lower = advice.channelLower,
              let price = currentPrice(for: advice.symbol),
              price > 0 else { return "—" }
        let pct = ((lower - price) / price) * 100
        return String(format: "%.0f%%", pct)
    }

    private func scenarioSummary(_ advice: PhoenixAdvice) -> String {
        var parts: [String] = []
        if advice.triggers.touchLowerBand    { parts.append("kanal dibi") }
        if advice.triggers.rsiReversal       { parts.append("RSI dönüş") }
        if advice.triggers.bullishDivergence { parts.append("ayrışma") }
        if parts.isEmpty { return advice.reasonShort }
        return parts.joined(separator: " · ")
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 65 { return InstitutionalTheme.Colors.aurora }
        if confidence >= 40 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}
