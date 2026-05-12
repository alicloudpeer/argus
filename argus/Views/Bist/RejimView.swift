import SwiftUI

/// Rejim merkezi.
/// Piyasa rejimi, makro göstergeler, teknik konsensüs ve sektör analizi.
/// Tüm veriler BorsaPy backend'inden canlı çekilir.
///
/// 2026-04-30 H-58 — sade refactor.
/// Eski yapı: MotorLogo(.aether) + caps "REJİM MERKEZİ" caption + caps mono
/// "PİYASA · MAKRO · SEKTÖR" subtitle + caps "ORACLE LENS" başlık + motor
/// tinted ArgusChip badge.
/// Yeni: "Rejim" sentence başlık + "Piyasa, makro, sektör" sentence subtitle
/// + sade text rozet (skoru ve etiketi tek satır), "Makro mercek" sentence
/// (Oracle Lens mitoloji ismi gizlendi).

struct RejimView: View {
    let symbol: String

    @State private var rejimScore: Double = 50
    @State private var rejimLabel: String = "Nötr"
    @State private var rejimStance: String = "cautious"
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {

            // Header — sade
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rejim")
                        .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text("Piyasa, makro, sektör")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                regimeBadge
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Rejim verileri yükleniyor")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(40)
            } else {
                VStack(spacing: 20) {
                    // 1. Piyasa Rejimi
                    PiyasaRejimiCard(
                        rejimScore: rejimScore,
                        rejimLabel: rejimLabel,
                        stance: rejimStance
                    )

                    // 2. Makro Göstergeler (BorsaPy canlı)
                    MakroGostergelerCard()

                    // 3. Makro mercek (eski adıyla Oracle Lens)
                    macroLensSection

                    // 4. Teknik Konsensüs (28 gösterge)
                    TeknikKonsensusCard(symbol: symbol)

                    // 5. Sektör Analizi
                    BistSektorCard()

                    // Disclaimer
                    disclaimerFooter
                }
            }
        }
        .task { await loadRejimData() }
    }

    // MARK: - Regime rozet (sade — capsule yok, text + renkli skor)

    private var regimeBadge: some View {
        Group {
            if isLoading {
                Text("Yükleniyor")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            } else {
                HStack(spacing: 6) {
                    Text(rejimLabel)
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                        .foregroundColor(stanceColor)
                    Text("\(Int(rejimScore))")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var stanceColor: Color {
        switch rejimStance {
        case "riskOn":    return InstitutionalTheme.Colors.aurora
        case "riskOff":   return InstitutionalTheme.Colors.crimson
        case "defensive": return InstitutionalTheme.Colors.titan
        default:          return DesignTokens.Colors.textSecondary
        }
    }

    // MARK: - Disclaimer

    private var disclaimerFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text("Eğitim amaçlıdır, yatırım tavsiyesi değildir.")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Makro mercek (eski "Oracle Lens" mitoloji ismi)

    private var macroLensSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Makro mercek")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, 16)

            OracleChamberEmbeddedView()
                .frame(height: 320)
        }
    }

    // MARK: - Data Loading
    private func loadRejimData() async {
        // MacroSnapshot'tan rejim skorunu hesapla
        let macro = await MacroSnapshotService.shared.getSnapshot()

        // Rejim skoru: VIX + DXY + yield curve bileşiminden hesapla
        var score: Double = 50
        var label = "Nötr"
        var stance = "cautious"

        // VIX bazlı
        if let vix = macro.vix {
            if vix < 15 {
                score += 20; stance = "riskOn"
            } else if vix < 20 {
                score += 10
            } else if vix > 30 {
                score -= 25; stance = "riskOff"
            } else if vix > 25 {
                score -= 15; stance = "defensive"
            }
        }

        // Fed Funds / Rate bazlı
        if let rate = macro.fedFundsRate {
            if rate < 4.0 { score += 5 }
            else if rate > 5.5 { score -= 10 }
        }

        // Fear & Greed bazlı
        if let fg = macro.fearGreedIndex {
            if fg > 70 { score += 10 }
            else if fg < 30 { score -= 15 }
        }

        score = max(0, min(100, score))

        if score >= 65 { label = "Boğa"; stance = "riskOn" }
        else if score >= 50 { label = "Temkinli boğa" }
        else if score >= 40 { label = "Nötr" }
        else if score >= 25 { label = "Temkinli ayı"; stance = "defensive" }
        else { label = "Ayı"; stance = "riskOff" }

        await MainActor.run {
            self.rejimScore = score
            self.rejimLabel = label
            self.rejimStance = stance
            self.isLoading = false
        }
    }
}
