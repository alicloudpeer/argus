import SwiftUI

// MARK: - TechnicalConsensusView (Teknik konsensüs 4 zaman)
//
// 2026-05-05 H-67 — sade refactor.
//
// Eski V5: MotorLogo(.orion) + "TEKNİK KONSENSÜS" caps section caption,
// "X SİNYAL" caps chip, dominant.uppercased() 20pt black mono tracking
// 0.8, "X AL · Y SAT" 9pt bold mono tracking 0.6, sütun başlıkları
// "OSİLATÖRLER / HAREKETLİ ORT." 9pt mono tracking 0.8 caps, signal
// rows isim.uppercased() 10pt mono tracking 0.5, action.uppercased()
// chip, vote chips "A/S/N" 8-10pt mono caps, orion motor border 0.3.
//
// Yeni dil: sade "Teknik konsensüs" + sayım muted, dominant 20pt
// medium sentence ("Al / Sat / Bekle"), sütun başlıkları sentence
// ("Osilatörler / Hareketli ortalamalar"), sinyal isimleri orijinal
// (RSI, MACD, vs zaten kısa), aksiyon chip → sade renkli text, vote
// chips küçültülmüş ve sade.

struct TechnicalConsensusView: View {
    let breakdown: OrionSignalBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gaugeCard
            consensusSplit
        }
        .padding(.horizontal)
    }

    // MARK: - Gauge Card

    private var gaugeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Teknik konsensüs")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(breakdown.summary.total) sinyal")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            ZStack {
                GaugeView(value: consensusValue)
                    .frame(height: 120)

                VStack(spacing: 3) {
                    Spacer()
                    Text(dominantLabel)
                        .font(DesignTokens.Fonts.custom(size: 20, weight: .medium))
                        .foregroundColor(dominantColor)
                    Text("\(breakdown.summary.buy) al · \(breakdown.summary.sell) sat")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .offset(y: 16)
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
    }

    // MARK: - Consensus Split (2 kolon)

    private var consensusSplit: some View {
        HStack(alignment: .top, spacing: 10) {
            SignalColumn(
                title: "Osilatörler",
                vote: breakdown.oscillators,
                signals: breakdown.indicators.filter { isOscillator($0.name) }
            )
            SignalColumn(
                title: "Hareketli ort.",
                vote: breakdown.movingAverages,
                signals: breakdown.indicators.filter { !isOscillator($0.name) }
            )
        }
    }

    // MARK: - Helpers

    /// -1 (Strong Sell) to 1 (Strong Buy)
    var consensusValue: Double {
        let total = Double(breakdown.summary.total)
        if total == 0 { return 0 }
        let net = Double(breakdown.summary.buy - breakdown.summary.sell)
        return net / total
    }

    /// dominant: caps "AL/SAT/NÖTR" → sentence "Al/Sat/Bekle".
    var dominantLabel: String {
        switch breakdown.summary.dominant.uppercased() {
        case "AL":  return "Al"
        case "SAT": return "Sat"
        default:    return "Bekle"
        }
    }

    var dominantColor: Color {
        switch breakdown.summary.dominant.uppercased() {
        case "AL":  return InstitutionalTheme.Colors.aurora
        case "SAT": return InstitutionalTheme.Colors.crimson
        default:    return InstitutionalTheme.Colors.titan
        }
    }

    func isOscillator(_ name: String) -> Bool {
        let oscs = ["RSI", "Stoch", "CCI", "Williams", "Momentum", "MACD Level", "Aroon"]
        return oscs.contains { name.contains($0) }
    }
}

// MARK: - Signal Column

struct SignalColumn: View {
    let title: String
    let vote: VoteCount
    let signals: [OrionSignalBreakdown.SignalItem]

    var body: some View {
        VStack(spacing: 0) {
            columnHeader

            VStack(spacing: 0) {
                ForEach(Array(signals.enumerated()), id: \.element.name) { idx, signal in
                    signalRow(signal)
                    if idx < signals.count - 1 {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 10)
                    }
                }
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var columnHeader: some View {
        HStack {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Spacer()
            HStack(spacing: 6) {
                voteCount(vote.buy, color: InstitutionalTheme.Colors.aurora)
                voteCount(vote.sell, color: InstitutionalTheme.Colors.crimson)
                voteCount(vote.neutral, color: DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    /// Sade vote sayacı: nokta + sayı.
    private func voteCount(_ count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private func signalRow(_ signal: OrionSignalBreakdown.SignalItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.name)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(signal.value)
                    .font(DesignTokens.Fonts.custom(size: 10, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer(minLength: 4)
            Text(actionLabel(signal.action))
                .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                .foregroundColor(actionColor(signal.action))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Sentence dilinde aksiyon etiketi.
    func actionLabel(_ action: String) -> String {
        switch action.uppercased() {
        case "AL":  return "Al"
        case "SAT": return "Sat"
        default:    return "Bekle"
        }
    }

    func actionColor(_ action: String) -> Color {
        switch action.uppercased() {
        case "AL":  return InstitutionalTheme.Colors.aurora
        case "SAT": return InstitutionalTheme.Colors.crimson
        default:    return DesignTokens.Colors.textSecondary
        }
    }
}

// MARK: - Gauge
//
// 3-bucket arc: crimson (180-240°) → titan (240-300°) → aurora (300-360°).
// Needle textPrimary, pivot textSecondary (motor renk yerine sade).

struct GaugeView: View {
    let value: Double // -1.0 to 1.0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height)
            let radius = min(size.width / 2, size.height) - 12
            let lineWidth: CGFloat = 10

            // Track
            let fullTrack = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(180), endAngle: .degrees(360),
                         clockwise: false)
            }
            context.stroke(fullTrack,
                           with: .color(InstitutionalTheme.Colors.surface3),
                           lineWidth: lineWidth + 2)

            // Crimson (sell)
            let crimsonArc = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(180), endAngle: .degrees(240),
                         clockwise: false)
            }
            context.stroke(crimsonArc,
                           with: .color(InstitutionalTheme.Colors.crimson),
                           lineWidth: lineWidth)

            // Titan (neutral)
            let titanArc = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(240), endAngle: .degrees(300),
                         clockwise: false)
            }
            context.stroke(titanArc,
                           with: .color(InstitutionalTheme.Colors.titan),
                           lineWidth: lineWidth)

            // Aurora (buy)
            let auroraArc = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(300), endAngle: .degrees(360),
                         clockwise: false)
            }
            context.stroke(auroraArc,
                           with: .color(InstitutionalTheme.Colors.aurora),
                           lineWidth: lineWidth)

            // Needle
            let angle = 180 + ((value + 1.0) / 2.0) * 180
            let needleEnd = CGPoint(
                x: center.x + Foundation.cos(Angle(degrees: angle).radians) * (radius - 14),
                y: center.y + Foundation.sin(Angle(degrees: angle).radians) * (radius - 14)
            )
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: needleEnd)
            context.stroke(needle,
                           with: .color(DesignTokens.Colors.textPrimary),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Pivot dot — sade textSecondary (motor tinted yerine)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                with: .color(DesignTokens.Colors.textSecondary)
            )
        }
    }
}
