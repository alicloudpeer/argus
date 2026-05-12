import SwiftUI

/// Anasayfada (Tarama / Global tab) görünen makro durum çubuğu.
///
/// 2026-05-05 H-65 — komple yeniden yazıldı.
///
/// Eski yapı (H-58 + H-60.2): "Bugün" başlığı + "İyimser, hareketli" gibi
/// synthetic sıfat phrase + sağda "Makro 30pt skor" inline. Bağımsız
/// surface kartı, ~60pt yükseklik. Sorunlar:
///   • "Makro 72" inline — 11pt etiket + 30pt sayı sıkışık
///   • "İyimser/Sakin/Tedirgin/Riskli" — synthetic AI cümle
///   • Bağımsız kart üst nav'la görsel bağsız
///
/// Yeni yapı: tek satır status, üst nav'ın hemen altına hairline ile
/// bağlı. Solda nokta + plain rejim adı, sağda muted skor + chevron.
/// Sirkiye tarafındaki SirkiyeDashboardView.statusBar ile aynı dilde.
///
/// Public API korundu: `init(rating:onTap:)`.

struct AetherDashboardHUD: View {
    let rating: MacroEnvironmentRating?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)

                Text(regimeLabel)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                if let r = rating {
                    Text("·")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textTertiary)

                    Text("\(Int(r.numericScore))")
                        .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Colors.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(Text("Makro detayını aç"))
    }

    /// Synthetic sıfat phrase yerine plain rejim adı.
    private var regimeLabel: String {
        guard let r = rating else { return "Makro yükleniyor" }
        switch r.regime {
        case .riskOn:  return "Genişleme rejimi"
        case .neutral: return "Karışık rejim"
        case .riskOff: return "Sıkılaşma rejimi"
        }
    }

    private var statusDotColor: Color {
        guard let r = rating else { return DesignTokens.Colors.textTertiary }
        switch r.regime {
        case .riskOn:  return InstitutionalTheme.Colors.aurora
        case .neutral: return InstitutionalTheme.Colors.titan
        case .riskOff: return InstitutionalTheme.Colors.crimson
        }
    }

    private var accessibilityText: Text {
        guard let r = rating else { return Text("Makro yükleniyor") }
        return Text("\(regimeLabel), skor \(Int(r.numericScore))")
    }
}
