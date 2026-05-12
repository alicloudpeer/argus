import SwiftUI

// MARK: - Aether Dashboard Card (V5)
//
// **2026-04-23 V5.C estetik refactor.**
// Eski kart `.cyan / .blue / .green / .yellow / .orange / .red / .pink / .mint`
// literalleri ve `LinearGradient` yığınıyla doluydu — makro kartı "promo
// kampanyası" gibi duruyordu. Artık institutional: motor(.aether) tint,
// `ArgusSectionCaption`, `ArgusChip`, `ArgusBar`. Ring gauge korundu ama
// tek renk motor tint. Compact ve full mode ikisi de aynı dile oturdu.
//
// Data sözleşmesi dokunulmadı: `MacroEnvironmentRating` aynen geliyor.
// 2026-04-30 H-57 — sade. AETHER MAKRO caps + tinted aether border +
// 92pt ring gauge + 26pt black mono skor + ÖNCÜ/EŞZAMANLI/GECİKMELİ
// caps mono + tinted miniPill kalktı. Yerine: "Makro" sentence başlık,
// sade hairline border, sol-aligned büyük skor + sağda durum, kategori
// satırları sentence case + bar.

struct AetherDashboardCard: View {
    let rating: MacroEnvironmentRating
    var isCompact: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 14) {
            header
            if isCompact {
                compactRow
            } else {
                fullBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 12 : 14)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Makro")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text(regimeLabel)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(regimeColor)
        }
    }

    // MARK: - Full mode

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(rating.numericScore))")
                    .font(DesignTokens.Fonts.custom(size: 32, weight: .medium))
                    .foregroundColor(scoreColor(rating.numericScore))
                    .monospacedDigit()
                Text("/ 100")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(rating.letterGrade.uppercased())
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(scoreColor(rating.numericScore))
            }

            VStack(spacing: 8) {
                categoryRow(label: "Öncü",
                            score: rating.leadingScore ?? 50,
                            weight: "×1.5")
                categoryRow(label: "Eşzamanlı",
                            score: rating.coincidentScore ?? 50,
                            weight: "×1.0")
                categoryRow(label: "Gecikmeli",
                            score: rating.laggingScore ?? 50,
                            weight: "×0.8")
            }
        }
    }

    private func categoryRow(label: String, score: Double, weight: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(width: 76, alignment: .leading)

            ArgusBar(value: max(0, min(1, score / 100)),
                     color: scoreColor(score),
                     height: 4)

            Text("\(Int(score))")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .monospacedDigit()
                .frame(width: 26, alignment: .trailing)

            Text(weight)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Compact mode

    private var compactRow: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(rating.numericScore))")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .medium))
                    .foregroundColor(scoreColor(rating.numericScore))
                    .monospacedDigit()
                Text("/100")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                miniScore(label: "Ö", score: rating.leadingScore ?? 50)
                miniScore(label: "E", score: rating.coincidentScore ?? 50)
                miniScore(label: "G", score: rating.laggingScore ?? 50)
            }
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
    }

    private func miniScore(label: String, score: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text("\(Int(score))")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(scoreColor(score))
                .monospacedDigit()
        }
    }

    // MARK: - Tone mapping (sade — text rengi, capsule yok)

    private var regimeLabel: String {
        switch rating.regime {
        case .riskOn:  return "Risk açık"
        case .neutral: return "Nötr"
        case .riskOff: return "Risk kapalı"
        }
    }

    private var regimeColor: Color {
        switch rating.regime {
        case .riskOn:  return InstitutionalTheme.Colors.aurora
        case .neutral: return DesignTokens.Colors.textSecondary
        case .riskOff: return InstitutionalTheme.Colors.crimson
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return DesignTokens.Colors.textPrimary }
        return InstitutionalTheme.Colors.crimson
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        AetherDashboardCard(
            rating: MacroEnvironmentRating(
                equityRiskScore: 72, volatilityScore: 85, safeHavenScore: 55,
                cryptoRiskScore: 78, interestRateScore: 60, currencyScore: 62,
                inflationScore: 65, laborScore: 76, growthScore: 80,
                creditSpreadScore: 70, claimsScore: 82,
                leadingScore: 74, coincidentScore: 68, laggingScore: 65,
                leadingContribution: 33.6, coincidentContribution: 20.6,
                laggingContribution: 15.8,
                numericScore: 72, letterGrade: "B+", regime: .riskOn,
                summary: "Aether v5", details: ""
            )
        )

        AetherDashboardCard(
            rating: MacroEnvironmentRating(
                equityRiskScore: 72, volatilityScore: 85, safeHavenScore: 55,
                cryptoRiskScore: 78, interestRateScore: 60, currencyScore: 62,
                inflationScore: 65, laborScore: 76, growthScore: 80,
                creditSpreadScore: 70, claimsScore: 82,
                leadingScore: 74, coincidentScore: 68, laggingScore: 65,
                leadingContribution: 33.6, coincidentContribution: 20.6,
                laggingContribution: 15.8,
                numericScore: 72, letterGrade: "B+", regime: .riskOn,
                summary: "Aether v5", details: ""
            ),
            isCompact: true
        )
    }
    .padding()
    .background(DesignTokens.Colors.background)
}
