import SwiftUI

// MARK: - Entry Setup Card
// Orion "ne alınır"a evet dediyse, bu kart "ne zaman / hangi fiyattan" sorusunu yanıtlar.
// Üç görsel hal:
//   READY (A/B/C): grade rozeti + zon + trigger + stop + hedefler + R:R + confluence chip'leri.
//   WAIT   (reject + entryZone + waitMessage): amber rozet, hedef zon ile bekle mesajı.
//   REJECT (reject + waitMessage, zon yok): gri rozet, sadece sebep.
// Price-in-zone durumunda ekstra yeşil "ZONDA" etiketi → şu an girilebilir sinyali.

struct EntrySetupCard: View {
    let setup: EntrySetup
    let currentPrice: Double?

    var body: some View {
        BentoCard(
            title: "Giriş Noktası",
            icon: "target",
            accentColor: accent
        ) {
            content
        }
    }

    // MARK: - Styling

    private var accent: Color {
        switch setup.grade {
        case .a: return Sanctum2Theme.neonGreen
        case .b: return Sanctum2Theme.hologramBlue
        case .c: return Sanctum2Theme.amberWarning
        case .reject:
            return setup.entryZone != nil ? Sanctum2Theme.amberWarning : Sanctum2Theme.midGray
        }
    }

    @ViewBuilder
    private var content: some View {
        switch setup.grade {
        case .a, .b, .c:
            readyContent
        case .reject:
            waitContent
        }
    }

    // MARK: - Ready State

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GradeBadge(grade: setup.grade, color: accent)
                Spacer()
                if let price = currentPrice, setup.isPriceInZone(price) {
                    Label("ZONDA", systemImage: "bolt.fill")
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .heavy))
                        .foregroundColor(Sanctum2Theme.neonGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Sanctum2Theme.neonGreen.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            if let trig = setup.trigger {
                SetupRow(icon: "wand.and.stars", label: "Tetik", value: trig.userDescription)
            }
            if let zone = setup.entryZone {
                SetupRow(
                    icon: "arrow.down.to.line",
                    label: "Giriş Zonu",
                    value: String(format: "%.2f – %.2f", zone.lowerBound, zone.upperBound)
                )
            }
            if let stop = setup.stopPrice {
                SetupRow(
                    icon: "xmark.shield.fill",
                    label: "Stop",
                    value: String(format: "%.2f", stop),
                    valueColor: Sanctum2Theme.crimsonRed
                )
            }
            if !setup.targets.isEmpty {
                let text = setup.targets.enumerated().map { i, v in
                    String(format: "TP%d %.2f", i + 1, v)
                }.joined(separator: "   ")
                SetupRow(
                    icon: "flag.checkered",
                    label: "Hedef",
                    value: text,
                    valueColor: Sanctum2Theme.neonGreen
                )
            }
            if let rr = setup.rrRatio {
                SetupRow(
                    icon: "scalemass",
                    label: "R:R",
                    value: String(format: "%.2fR", rr)
                )
            }

            if !setup.confluence.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(setup.confluence.indices, id: \.self) { idx in
                            confluenceChip(setup.confluence[idx])
                        }
                    }
                }
                .padding(.top, 4)
            }

            expiryNote
        }
    }

    // MARK: - Wait / Reject State

    private var waitContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bekle")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(accent)
                Spacer()
            }

            Text(setup.waitMessage ?? "Setup uygulanabilir değil.")
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let zone = setup.entryZone {
                SetupRow(
                    icon: "arrow.down.to.line",
                    label: "Hedef Zon",
                    value: String(format: "%.2f – %.2f", zone.lowerBound, zone.upperBound)
                )
            }

            expiryNote
        }
    }

    // MARK: - Pieces

    private var expiryNote: some View {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(DesignTokens.Fonts.custom(size: 9))
            Text("Geçerlilik: \(fmt.string(from: setup.validUntil))")
                .font(DesignTokens.Fonts.custom(size: 10))
        }
        .foregroundColor(DesignTokens.Colors.textTertiary)
        .padding(.top, 2)
    }

    private func confluenceChip(_ factor: ConfluenceFactor) -> some View {
        Text(factor.userDescription)
            .font(DesignTokens.Fonts.custom(size: 10, weight: .semibold))
            .foregroundColor(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12))
            .cornerRadius(3)
    }
}

// MARK: - Subviews

private struct GradeBadge: View {
    let grade: EntryGrade
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text("Not")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(grade.label)
                .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}

private struct SetupRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = DesignTokens.Colors.textPrimary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
