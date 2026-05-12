import SwiftUI

struct AetherHUDView: View {
    let rating: MacroEnvironmentRating?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            if let r = rating {
                // Ultra Compact Card
                HStack(spacing: 12) {
                    // Score
                    ZStack {
                        Circle()
                            .stroke(scoreColor(r.numericScore).opacity(0.3), lineWidth: 3)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: r.numericScore / 100)
                            .stroke(scoreColor(r.numericScore), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(r.numericScore))")
                            .font(DesignTokens.Fonts.custom(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(r.numericScore))
                    }
                    
                    // 2026-04-30 H-58 — sade. MotorLogo + caps "AETHER" gitti.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Makro")
                            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Text(r.regime.rawValue)
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Mini Category Pills
                    HStack(spacing: 4) {
                        MiniPill(emoji: "", score: r.leadingScore ?? 50)
                        MiniPill(emoji: "", score: r.coincidentScore ?? 50)
                        MiniPill(emoji: "", score: r.laggingScore ?? 50)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(DesignTokens.Colors.textSecondary.opacity(0.5))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignTokens.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(scoreColor(r.numericScore).opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                // Loading State
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.cyan)
                    Text("Aether Yükleniyor...")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(DesignTokens.Colors.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 50 { return .yellow }
        return .red
    }
}

// Mini Pill for compact view
struct MiniPill: View {
    let emoji: String
    let score: Double
    
    var body: some View {
        HStack(spacing: 2) {
            Text(emoji)
                .font(DesignTokens.Fonts.custom(size: 8))
            Text("\(Int(score))")
                .font(DesignTokens.Fonts.custom(size: 9, weight: .bold))
                .foregroundColor(scoreColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(scoreColor.opacity(DesignTokens.Opacity.glassCard))
        .clipShape(Capsule())
    }
    
    private var scoreColor: Color {
        if score >= 70 { return .green }
        if score >= 50 { return .yellow }
        return .red
    }
}
