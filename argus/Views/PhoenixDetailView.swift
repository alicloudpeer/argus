import SwiftUI
import Charts

// MARK: - Risk Fırsatı Detay Ekranı (eski adıyla Phoenix Detail)
//
// 2026-04-30 H-58 — sade refactor.
// Eski yapı V5: ModuleSheetShell title "PHOENIX · DÖNÜŞ" + 76pt motor
// ring + caps "GÜVEN SKORU" + caps "FIRSAT (A+)" status + caps mono
// statBox başlıkları + caps "EVET/BEKLİYOR" + holo tint backtest button +
// "PHOENIX NEDİR?" pedagoji + Motor tint chrome her yerde.
// Yeni: "Risk fırsatı" sentence + sade hairline kartlar + sentence
// statBox başlıkları + ✓ icon checkrow + sade pedagoji.
// Public API korundu — `init(symbol:, advice:, candles:, onRunBacktest:)`.

struct PhoenixDetailView: View {
    let symbol: String
    let advice: PhoenixAdvice
    let candles: [Candle]
    var onRunBacktest: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ModuleSheetShell(title: "Risk fırsatı", motor: .phoenix) {
            heroCard
            chartCard
            analysisCard
            statsGridCard
            checklistCard

            if symbol.uppercased().hasSuffix(".IS") {
                bistSessionCard
            }

            if onRunBacktest != nil {
                backtestButton
            }

            pedagogyFooter
        }
    }

    // MARK: - Hero (sade)

    private var heroCard: some View {
        let conf = max(0, min(100, advice.confidence))

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Güven skoru")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(conf))")
                        .font(DesignTokens.Fonts.custom(size: 32, weight: .medium))
                        .foregroundColor(scoreColor(conf))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                Text(symbol.uppercased())
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .padding(.top, 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(scoreColor(conf))
                Text("Ufuk · \(advice.timeframe.localizedName)")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
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

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Regresyon kanalı")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            ZStack {
                if candles.count > 20 {
                    PhoenixChannelChart(candles: candles, advice: advice)
                        .frame(height: 220)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(DesignTokens.Fonts.custom(size: 18))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text("Grafik için yetersiz veri (en az 20 mum gerekli)")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    // MARK: - Analysis (sade — sol-bar accent kalktı)

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analiz")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text(advice.reasonShort)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    // MARK: - Stats grid

    private var statsGridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("İstatistik")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                statBox(label: "Eğim",
                        value: advice.regressionSlope.map { String(format: "%.4f", $0) } ?? "—")
                statBox(label: "Sigma",
                        value: advice.sigma.map { String(format: "%.2f", $0) } ?? "—")
                statBox(label: "Pivot",
                        value: advice.channelMid.map { String(format: "%.2f", $0) } ?? "—")
                statBox(label: "Kanal genişliği",
                        value: channelWidthText)
                statBox(label: "R² güvenilirlik",
                        value: advice.rSquared.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                        color: rSquaredColor)
                statBox(label: "Lookback",
                        value: "\(advice.lookback) gün")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    private func statBox(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(color ?? DesignTokens.Colors.textPrimary)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var channelWidthText: String {
        guard let sigma = advice.sigma, let mid = advice.channelMid, mid != 0 else { return "—" }
        return String(format: "%%%.1f", (sigma / mid) * 400)
    }

    private var rSquaredColor: Color? {
        guard let r = advice.rSquared else { return nil }
        if r > 0.5 { return InstitutionalTheme.Colors.aurora }
        if r > 0.25 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Checklist (sade)

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sinyal kontrol listesi")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                checkRow("Kanal dibi teması", advice.triggers.touchLowerBand)
                checkRow("RSI dönüş sinyali", advice.triggers.rsiReversal)
                checkRow("Pozitif uyumsuzluk", advice.triggers.bullishDivergence)
                checkRow("Trend onayı", advice.triggers.trendOk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    private func checkRow(_ title: String, _ isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(isActive
                                 ? InstitutionalTheme.Colors.aurora
                                 : DesignTokens.Colors.textTertiary)
                .frame(width: 18)
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text(isActive ? "evet" : "bekliyor")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(isActive
                                 ? InstitutionalTheme.Colors.aurora
                                 : DesignTokens.Colors.textTertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - BIST Session Triggers

    private var bistSessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BIST seans tetikleri")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            BistSessionTriggers(advice: advice)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    // MARK: - Backtest button (sade)

    private var backtestButton: some View {
        Button {
            dismiss()
            if let run = onRunBacktest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { run() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignTokens.Fonts.custom(size: 13))
                Text("Geçmiş test")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundColor(DesignTokens.Colors.textPrimary)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pedagoji footer (mitoloji ismi gizli)

    private var pedagogyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bu nedir?")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text("Risk fırsatı bir dip dedektörüdür. Fiyat regresyon kanalının dibine değdiğinde, RSI toparlandığında ve hacim dönüş mumu geldiğinde güven skoru yükselir. Sadece teknik sinyal — temel analiz bilanço motorunun işidir.")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    DesignTokens.Colors.borderSubtle,
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private var statusText: String {
        switch advice.confidence {
        case 80...100: return "Fırsat (A+)"
        case 60..<80:  return "Güçlü"
        case 40..<60:  return "Nötr"
        default:       return "Zayıf"
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return InstitutionalTheme.Colors.aurora }
        if score >= 40 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    // 2026-05-11: DovizCom kaldırıldı (`.phoenixDetail` route hiç tetiklenmiyordu).
    // Gram altın/gümüş/USD için kurum bazlı kur karşılaştırması Faz 1'de
    // FrankfurterProvider (XAU/USD/TRY) üzerinden yeniden inşa edilecek.
}

// MARK: - BIST Session Triggers

struct BistSessionTriggers: View {
    let advice: PhoenixAdvice
    @State private var currentSession: BistSession = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $currentSession) {
                Text("Genel").tag(BistSession.none)
                Text("Rönesan").tag(BistSession.ronesan)
                Text("Kur şoku").tag(BistSession.kurSoku)
                Text("Seans kapanışı").tag(BistSession.seansKapanisi)
            }
            .pickerStyle(.segmented)

            switch currentSession {
            case .ronesan:       sessionList(items: ronesanItems, caption: "Rönesan günü özel:")
            case .kurSoku:       sessionList(items: kurSokuItems, caption: "Kur şoku durumunda:")
            case .seansKapanisi: sessionList(items: seansKapanisiItems, caption: "Seans kapanışında:")
            case .none:          sessionList(items: generalItems, caption: "Genel BIST tetikleri:")
            }
        }
    }

    private struct SessionItem: Identifiable {
        let id = UUID()
        let condition: String
        let action: String
        let isActive: Bool
    }

    private func sessionList(items: [SessionItem], caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(item.isActive
                              ? InstitutionalTheme.Colors.aurora
                              : DesignTokens.Colors.textTertiary)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.condition)
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Text(item.action)
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DesignTokens.Colors.surfaceElevated.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var ronesanItems: [SessionItem] {
        [
            SessionItem(condition: "Gündüz seans 09:30'dan önce", action: "Alış yap", isActive: false),
            SessionItem(condition: "Seyahat hacmi %2'nin altına düşerse", action: "Alış beklenir", isActive: false),
        ]
    }
    private var kurSokuItems: [SessionItem] {
        [
            SessionItem(condition: "USD/TRY %3 yükselirse", action: "XU030 satışı beklenir", isActive: false),
            SessionItem(condition: "XU100 %2 düşerse", action: "BIST genel satışı beklenir", isActive: false),
        ]
    }
    private var seansKapanisiItems: [SessionItem] {
        [
            SessionItem(condition: "Son 30 dakika hacim artışı", action: "Kapanış alımı için uygun", isActive: false),
            SessionItem(condition: "Seans sonuna doğru düşüş", action: "Short pozisyon kapat", isActive: false),
        ]
    }
    private var generalItems: [SessionItem] {
        [
            SessionItem(condition: "Genel tetikler yükleniyor", action: "Motor tamamlanınca doldurulacak", isActive: false),
        ]
    }
}

enum BistSession: String, CaseIterable {
    case none = "Genel"
    case ronesan = "Rönesan"
    case kurSoku = "Kur şoku"
    case seansKapanisi = "Seans kapanışı"
}

// MARK: - Chart Component (sade — motor tint kalktı)

struct PhoenixChannelChart: View {
    let candles: [Candle]
    let advice: PhoenixAdvice

    var body: some View {
        let displayCandles = candles.suffix(advice.lookback + 20)
        let sorted = Array(displayCandles).sorted { $0.date < $1.date }

        return Chart {
            // 1. Candles
            ForEach(sorted) { candle in
                RectangleMark(
                    x: .value("Tarih", candle.date),
                    yStart: .value("Open", candle.open),
                    yEnd: .value("Close", candle.close),
                    width: .fixed(4)
                )
                .foregroundStyle(
                    candle.close >= candle.open
                        ? InstitutionalTheme.Colors.aurora
                        : InstitutionalTheme.Colors.crimson
                )

                RuleMark(
                    x: .value("Tarih", candle.date),
                    yStart: .value("Low", candle.low),
                    yEnd: .value("High", candle.high)
                )
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            // 2. Channel Lines (sade — orta çizgi nötr, kanal hatları nötr)
            if !sorted.isEmpty {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, candle in
                    if index >= (sorted.count - advice.lookback) {
                        let relativeX = Double(index - (sorted.count - advice.lookback))
                        let distFromEnd = Double(advice.lookback - 1) - relativeX
                        let midY = (advice.channelMid ?? 0.0) - ((advice.regressionSlope ?? 0.0) * distFromEnd)
                        let upperY = midY + (2.0 * (advice.sigma ?? 0.0))
                        let lowerY = midY - (2.0 * (advice.sigma ?? 0.0))

                        LineMark(x: .value("Tarih", candle.date), y: .value("Mid", midY))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                        LineMark(x: .value("Tarih", candle.date), y: .value("Upper", upperY))
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))

                        LineMark(x: .value("Tarih", candle.date), y: .value("Lower", lowerY))
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
