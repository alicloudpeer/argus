import SwiftUI

// MARK: - Sinyal Analizi Kartı (eski adıyla Athena Card)
//
// 2026-04-30 H-58 — sade refactor.
// Eski yapı: caps "ATHENA" başlık + owl ikon + caps mono "Sinyal Analizi"
// subtitle + caps mono "ACIKLAMA" / "ONERI" captions + raw .secondary/.primary
// + Color(.systemGray6).opacity(0.5) legacy. Yeni: "Sinyal analizi"
// sentence başlık (Athena mitoloji ismi gizli) + InstitutionalTheme tokenları
// + sentence captions + sade hairline kart.

struct AthenaCard: View {
    let signals: [ChimeraSignal]

    var body: some View {
        if signals.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text("Sinyal analizi")
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text("\(signals.count) sinyal")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                // Signal List
                VStack(spacing: 0) {
                    ForEach(Array(signals.enumerated()), id: \.element.id) { idx, signal in
                        if idx > 0 {
                            Rectangle()
                                .fill(DesignTokens.Colors.borderSubtle)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                        AthenaSignalRow(signal: signal)
                    }
                }
            }
            .padding(14)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Signal Row

struct AthenaSignalRow: View {
    let signal: ChimeraSignal
    @State private var isExpanded = false

    private var signalColor: Color {
        Color(hex: signal.type.severityColor) ?? DesignTokens.Colors.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Row (Tappable)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Color Indicator (sade — ince çubuk)
                    Rectangle()
                        .fill(signalColor)
                        .frame(width: 3, height: 28)
                        .cornerRadius(1.5)

                    // Signal Info — sentence
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.type.turkishName)
                            .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)

                        Text(signal.title)
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Açıklama")
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(signal.type.turkishDescription)
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Öneri")
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(signal.type.turkishAdvice)
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
                .padding(.leading, 15)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AthenaCard(signals: [
        ChimeraSignal(
            type: .deepValueBuy,
            title: "AAPL - Temel Guclu",
            description: "Demo",
            severity: 0.8
        ),
        ChimeraSignal(
            type: .bullTrap,
            title: "Dikkat - Hacim Zayif",
            description: "Demo",
            severity: 0.6
        )
    ])
    .padding()
}
