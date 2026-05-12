import SwiftUI

// MARK: - Teknik Analiz Ekranı (eski adıyla Orion Motherboard)
//
// 2026-04-30 H-58 — sade refactor.
// Eski yapı (V5.H-11): MotorLogo + "ORION · TEKNİK ANALİZ" caps mono +
// 20pt heavy mono sembol + caps mono timeframe pills (motor tint bg) +
// 52pt motor-tinted ring + AL/TUT/SAT chip + 4 satırlık component pill
// (kod rozeti + caps mono başlık + motor tint bg) + caps mono "ORION
// TAVSİYESİ" + sol-bar accent. Toplamda promo kampanyası gibi duruyordu.
//
// Yeni dil:
//   • Header: "Teknik analiz" 13pt secondary + sembol 22pt medium
//   • Timeframe: iOS-native segmented (Saatlik / 4 saat / Günlük / Haftalık)
//   • Skor satırı: 32pt medium skor + "/100" + "Al/Tut/Sat" sentence + güven
//   • Bileşen satırları: ad + ArgusBar + skor + tek-kelime durum
//   • Tavsiye: ayrı sade kart, "Yorum" küçük etiket + cümle
//
// Public API korundu — `OrionMotherboardView(analysis:, symbol:, viewModel:)`.
// Mitoloji "Orion" ismi kullanıcı UI'ında görünmez; iç state ve tip adları
// (CircuitNode, OrionModuleDetailView vs) korundu.

struct OrionMotherboardView: View {
    let analysis: MultiTimeframeAnalysis
    let symbol: String

    @ObservedObject var viewModel: SanctumViewModel

    @State private var selectedTimeframe: TimeframeMode = .daily
    @State private var selectedNode: CircuitNode? = nil

    /// Aktif timeframe'in teknik skoru.
    var currentOrion: OrionScoreResult {
        analysis.scoreFor(timeframe: selectedTimeframe)
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    timeframeSegment
                    scoreCard
                    fallbackNoteIfNeeded
                    chartHero
                    componentList
                    adviceCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            if let node = selectedNode {
                OrionModuleDetailView(
                    type: node,
                    symbol: symbol,
                    analysis: currentOrion,
                    candles: viewModel.candles,
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            selectedNode = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            }
        }
        .onAppear {
            selectedTimeframe = viewModel.selectedTimeframe
            viewModel.analysisBridge.orionScore = analysis.scoreFor(timeframe: selectedTimeframe)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Teknik analiz")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text(symbol.uppercased())
                .font(DesignTokens.Fonts.custom(size: 22, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .tracking(-0.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeframe segmented (iOS-native dili)

    private var timeframeSegment: some View {
        HStack(spacing: 2) {
            ForEach(TimeframeMode.allCases, id: \.rawValue) { mode in
                timeframeTab(mode)
            }
        }
        .padding(2)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timeframeTab(_ mode: TimeframeMode) -> some View {
        let isSelected = selectedTimeframe == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTimeframe = mode
            }
            Task { await viewModel.changeTimeframe(to: mode) }
        } label: {
            Text(timeframeLabel(mode))
                .font(DesignTokens.Fonts.custom(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected
                                 ? DesignTokens.Colors.textPrimary
                                 : DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? DesignTokens.Colors.surface
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func timeframeLabel(_ mode: TimeframeMode) -> String {
        // Sentence case karşılıklar (mitoloji uppercased() yerine)
        switch mode.displayLabel.lowercased() {
        case "saatlik", "1s", "1h": return "Saatlik"
        case "4 saatlik", "4s", "4h": return "4 saat"
        case "günlük", "1g", "1d", "d": return "Günlük"
        case "haftalık", "1h", "1w", "w": return "Haftalık"
        default: return mode.displayLabel.capitalized
        }
    }

    // MARK: - Skor kartı

    /// Tap → CPU node detay overlay (eski "scoreBar" davranışı korundu).
    private var scoreCard: some View {
        Button {
            withAnimation { selectedNode = .cpu }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(currentOrion.score))")
                        .font(DesignTokens.Fonts.custom(size: 32, weight: .medium))
                        .foregroundColor(scoreColor(currentOrion.score))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verdictText)
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                        .foregroundColor(scoreColor(currentOrion.score))
                    Text(confidenceText)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .padding(.leading, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var verdictText: String {
        if currentOrion.score >= 55 { return "Al" }
        if currentOrion.score >= 45 { return "Tut" }
        return "Sat"
    }

    private var confidenceText: String {
        let c = max(50, min(95, 50 + Int(currentOrion.score) / 2))
        return "güven %\(c)"
    }

    // MARK: - Fallback uyarı (sadece gerektiğinde)

    @ViewBuilder
    private var fallbackNoteIfNeeded: some View {
        if analysis.isFallback(timeframe: selectedTimeframe) {
            let source = analysis.sourceFor(timeframe: selectedTimeframe)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text("\(timeframeLabel(selectedTimeframe).lowercased()) skoru \(source.displayLabel) verisinden türetildi.")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - HERO Grafik (sade çerçeve)

    private var chartHero: some View {
        ZStack {
            if !viewModel.candles.isEmpty {
                InteractiveCandleChart(
                    candles: viewModel.candles,
                    trades: nil,
                    showSMA: true,
                    showBollinger: false,
                    showIchimoku: false,
                    showMACD: false,
                    showVolume: true,
                    showRSI: false,
                    showStochastic: false,
                    showSAR: false,
                    showTSI: false
                )
                .frame(height: 280)
                .opacity(viewModel.isCandlesLoading ? 0.3 : 1.0)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(DesignTokens.Fonts.custom(size: 22))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Text("Grafik verisi yükleniyor")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .frame(height: 280)
            }

            if viewModel.isCandlesLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("\(timeframeLabel(selectedTimeframe).lowercased()) yükleniyor")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .padding(14)
                .background(DesignTokens.Colors.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(8)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bileşen listesi (sade satırlar, kart içinde)

    private var componentList: some View {
        VStack(spacing: 0) {
            momentumRow
            divider
            trendRow
            divider
            structureRow
            divider
            patternRow
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private var momentumRow: some View {
        let rsi = currentOrion.components.rsi ?? (currentOrion.components.momentum * 4)
        let (status, color): (String, Color) = {
            if rsi > 70 { return ("aşırı alım", InstitutionalTheme.Colors.crimson) }
            if rsi < 30 { return ("aşırı satım", InstitutionalTheme.Colors.crimson) }
            if rsi > 55 { return ("güçlü", InstitutionalTheme.Colors.aurora) }
            if rsi < 45 { return ("zayıf", InstitutionalTheme.Colors.titan) }
            return ("nötr", DesignTokens.Colors.textSecondary)
        }()

        return componentRow(
            node: .momentum,
            label: "Momentum",
            valueText: "\(Int(rsi))",
            statusText: status,
            color: color,
            barRatio: max(0, min(1, rsi / 100))
        )
    }

    private var trendRow: some View {
        let adx = currentOrion.components.trendStrength ?? (currentOrion.components.trend * 2)
        let (status, color): (String, Color) = {
            if adx >= 25 { return ("yerleşik", InstitutionalTheme.Colors.aurora) }
            if adx >= 15 { return ("zayıf trend", InstitutionalTheme.Colors.titan) }
            return ("yatay", DesignTokens.Colors.textSecondary)
        }()

        return componentRow(
            node: .trend,
            label: "Trend",
            valueText: "\(Int(adx))",
            statusText: status,
            color: color,
            barRatio: max(0, min(1, adx / 50))
        )
    }

    private var structureRow: some View {
        let s = max(0, min(currentOrion.components.structure, 35))
        let pos = s / 35.0
        let (status, color): (String, Color) = {
            if pos > 0.8 { return ("dirence yakın", InstitutionalTheme.Colors.crimson) }
            if pos < 0.2 { return ("desteğe yakın", InstitutionalTheme.Colors.aurora) }
            if pos >= 0.55 { return ("sağlam", InstitutionalTheme.Colors.aurora) }
            return ("kanal içi", DesignTokens.Colors.textSecondary)
        }()

        return componentRow(
            node: .structure,
            label: "Yapı",
            valueText: "\(Int(s))",
            statusText: status,
            color: color,
            barRatio: pos
        )
    }

    private var patternRow: some View {
        let desc = currentOrion.components.patternDesc
        let isEmpty = desc.isEmpty || desc == "Yok"
        let status = isEmpty ? "tespit yok" : desc.lowercased()
        let color: Color = isEmpty
            ? DesignTokens.Colors.textSecondary
            : InstitutionalTheme.Colors.aurora

        return componentRow(
            node: .pattern,
            label: "Formasyon",
            valueText: "",
            statusText: status,
            color: color,
            barRatio: isEmpty ? 0 : 1
        )
    }

    private func componentRow(
        node: CircuitNode,
        label: String,
        valueText: String,
        statusText: String,
        color: Color,
        barRatio: Double
    ) -> some View {
        Button {
            withAnimation { selectedNode = node }
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 84, alignment: .leading)

                ArgusBar(value: barRatio, color: color, height: 4)

                if !valueText.isEmpty {
                    Text(valueText)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }

                Text(statusText)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: valueText.isEmpty ? 92 : 70, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tavsiye kartı

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Yorum")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(analysis.strategicAdvice)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Tone

    private func scoreColor(_ score: Double) -> Color {
        if score >= 55 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return DesignTokens.Colors.textPrimary }
        return InstitutionalTheme.Colors.crimson
    }
}
