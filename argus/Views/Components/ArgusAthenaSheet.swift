import SwiftUI

// MARK: - Argus Athena Sheet (V5)
//
// **2026-04-23 V5 tam yazım.** Eski `ArgusAthenaSheet` raw `Color.teal` +
// `presentationMode` + `cornerRadius(12)` + Türkçe karakter eksik metinler
// şablonuyla V5 dışındaydı. Yeni sheet:
//
//   • `ModuleSheetShell` → `ArgusNavHeader` + dismiss + scroll sarmal.
//   • Hero kart: circular skor ring + styleLabel + "GÜÇLÜ SINIFLA" pill.
//   • Eğitici intro: Athena'yı 1 cümlede tanıtır.
//   • 4 faktör kartı (Değer / Kalite / Momentum / Risk):
//       - Mikro alt-başlık ("ucuz mu pahalı mı?" gibi).
//       - Skor + `ArgusBar`.
//       - En güçlü faktöre "EN GÜÇLÜ" rozeti + vurgulu arka plan.
//       - Alt-satır gerçek veri cümlesi (F/K, ROE, Beta, trendDesc) —
//         sadece veri kaynağında o alan mevcutsa render edilir.
//         **Veri yoksa satır gizlenir.** Uydurma yok.
//   • Athena yargısı: en güçlü 1-2 faktör + styleLabel birleşimi.
//   • Pedagoji footer: 4 faktörün akademik tanımları (statik öğretici).
//
// Gerçek veri kaynağı:
//   - `viewModel.athenaResults[symbol]` → `AthenaFactorResult` (4 skor)
//   - `viewModel.getFundamentalScore(for:)?.financials` → `FinancialsData`
//     (peRatio, priceToBook, returnOnEquity, profitMargin, debtToEquity)
//   - `viewModel.getFinancialSnapshot(for:)?.beta` → `Double?`
//   - `viewModel.orionScores[symbol]?.components.trendDesc` → String
//
// `AthenaFactorResult` yoksa `ModulePlaceholderSheet` ile bilgilendirici
// boş hal gösterilir.

struct ArgusAthenaSheet: View {
    let symbol: String
    @ObservedObject private var signalState = SignalStateViewModel.shared

    // MARK: - Veri erişim

    private var result: AthenaFactorResult? {
        signalState.athenaResults[symbol]
    }

    private var financials: FinancialsData? {
        FundamentalScoreStore.shared.getScore(for: symbol)?.financials
    }

    private var snapshot: FinancialSnapshot? {
        AnalysisViewModel.shared.snapshots[symbol]
    }

    private var orionTrendDesc: String? {
        let d = signalState.orionScores[symbol]?.components.trendDesc
        return (d?.isEmpty == false) ? d : nil
    }

    /// 4 faktör skorunun en büyüğünü bul — "EN GÜÇLÜ" rozeti ve yargı için.
    private func strongestFactor(_ r: AthenaFactorResult) -> AthenaSheetFactor {
        let pairs: [(AthenaSheetFactor, Double)] = [
            (.value,    r.valueFactorScore),
            (.quality,  r.qualityFactorScore),
            (.momentum, r.momentumFactorScore),
            (.risk,     r.riskFactorScore),
        ]
        return pairs.max(by: { $0.1 < $1.1 })?.0 ?? .quality
    }

    // MARK: - Body

    var body: some View {
        if let r = result {
            ModuleSheetShell(title: "Faktör analizi", motor: .athena) {
                heroCard(r)
                educationalIntroCard
                factorCaption
                factorCard(.value,    score: r.valueFactorScore,    strongest: strongestFactor(r))
                factorCard(.quality,  score: r.qualityFactorScore,  strongest: strongestFactor(r))
                factorCard(.momentum, score: r.momentumFactorScore, strongest: strongestFactor(r))
                factorCard(.risk,     score: r.riskFactorScore,     strongest: strongestFactor(r))
                verdictCard(r)
                pedagogyFooter
            }
        } else {
            ModulePlaceholderSheet(
                title: "Faktör analizi",
                subtitle: "Hazır değil",
                message: "Bu hisse için 4 faktör skoru henüz hesaplanmadı. Daha fazla veri bekleniyor.",
                motor: .athena
            )
        }
    }

    // MARK: - Hero

    private func heroCard(_ r: AthenaFactorResult) -> some View {
        // 2026-04-30 H-58 — sade. 76pt motor ring + caps "STRATEJİ ETİKETİ"
        // + caps "GÜÇLÜ SINIFLA" chip kalktı. Yerine: 32pt skor + sentence
        // "Strateji" + sentence styleLabel.
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Faktör skoru")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(r.factorScore))")
                        .font(DesignTokens.Fonts.custom(size: 32, weight: .medium))
                        .foregroundColor(scoreColor(r.factorScore))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Strateji")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(r.styleLabel)
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.trailing)
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

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return DesignTokens.Colors.textPrimary }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Educational intro

    private var educationalIntroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nasıl okunur")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text("Hisse 4 akademik faktöre göre puanlanır. En yüksek 2 faktör strateji etiketini belirler.")
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

    // MARK: - Factor caption

    private var factorCaption: some View {
        HStack {
            Text("4 faktör kırılımı")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Factor card

    private func factorCard(_ factor: AthenaSheetFactor,
                            score: Double,
                            strongest: AthenaSheetFactor) -> some View {
        let isStrongest = (factor == strongest)
        let clamped = max(0, min(100, score))
        let barColor: Color = scoreColor(clamped)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(factor.title)
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(factor.microCaption)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer(minLength: 0)
                if isStrongest {
                    Text("en güçlü")
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.aurora)
                }
                Text("\(Int(clamped))")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(scoreColor(clamped))
                    .monospacedDigit()
            }

            ArgusBar(value: clamped / 100.0, color: barColor, height: 4)

            if let line = factorDataLine(factor) {
                Text(line)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
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

    // MARK: - Gerçek veri satırları (uydurma yok — yoksa nil döner, satır gizlenir)

    private func factorDataLine(_ factor: AthenaSheetFactor) -> String? {
        switch factor {
        case .value:    return valueLine()
        case .quality:  return qualityLine()
        case .momentum: return momentumLine()
        case .risk:     return riskLine()
        }
    }

    private func valueLine() -> String? {
        var parts: [String] = []
        if let pe = financials?.peRatio {
            parts.append("F/K \(AtlasMetric.format(pe))")
        }
        if let pb = financials?.priceToBook {
            parts.append("PD/DD \(AtlasMetric.format(pb))")
        }
        if let ev = financials?.evToEbitda {
            parts.append("EV/EBITDA \(AtlasMetric.format(ev))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func qualityLine() -> String? {
        var parts: [String] = []
        // ROE önceliği: FinancialsData > FinancialSnapshot
        if let roe = financials?.returnOnEquity ?? snapshot?.roe {
            parts.append("ROE \(AtlasMetric.formatPercent(roe))")
        }
        if let nm = financials?.profitMargin ?? snapshot?.netMargin {
            parts.append("Net marj \(AtlasMetric.formatPercent(nm))")
        }
        if let de = financials?.debtToEquity ?? snapshot?.debtToEquity {
            parts.append("Borç/Özkaynak \(AtlasMetric.format(de))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func momentumLine() -> String? {
        // Orion trendDesc varsa onu kullan; yoksa satır gizle.
        // "Son 3-12 ay getirisi" için kayıtlı field yok — uydurmuyoruz.
        if let desc = orionTrendDesc {
            if let age = signalState.orionScores[symbol]?.components.trendAge {
                return "Trend · \(desc) · \(age) gün önce başladı"
            }
            return "Trend · \(desc)"
        }
        return nil
    }

    private func riskLine() -> String? {
        // Beta: global için FinancialSnapshot.beta; BIST için cache yok —
        // null dönerse satır gizlenir.
        guard let beta = snapshot?.beta else { return nil }
        let tone = beta < 0.9 ? "sakin" : (beta > 1.2 ? "hareketli" : "dengeli")
        return "Beta \(String(format: "%.2f", beta)) · \(tone)"
    }

    // MARK: - Verdict

    private func verdictCard(_ r: AthenaFactorResult) -> some View {
        let (primary, secondary) = topTwoFactors(r)
        let summary = verdictText(primary: primary, secondary: secondary, styleLabel: r.styleLabel)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Yorum")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text(summary)
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

    private func topTwoFactors(_ r: AthenaFactorResult) -> (AthenaSheetFactor, AthenaSheetFactor) {
        let pairs: [(AthenaSheetFactor, Double)] = [
            (.value,    r.valueFactorScore),
            (.quality,  r.qualityFactorScore),
            (.momentum, r.momentumFactorScore),
            (.risk,     r.riskFactorScore),
        ].sorted(by: { $0.1 > $1.1 })
        return (pairs[0].0, pairs[1].0)
    }

    private func verdictText(primary: AthenaSheetFactor,
                             secondary: AthenaSheetFactor,
                             styleLabel: String) -> String {
        // Strateji etiketi zaten Athena servisi tarafından üretiliyor —
        // burada kendi yargımızı eklemiyoruz, sadece en güçlü 2 faktörü
        // okunaklı bir cümleye sarıyoruz.
        return "En güçlü iki faktör: \(primary.title) ve \(secondary.title). Strateji: \(styleLabel)."
    }

    // MARK: - Pedagogy footer

    private var pedagogyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Faktör yatırımı nedir")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                pedagogyRow(.value)
                pedagogyRow(.quality)
                pedagogyRow(.momentum)
                pedagogyRow(.risk)
            }
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

    private func pedagogyRow(_ factor: AthenaSheetFactor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(factor.title)
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .frame(width: 84, alignment: .leading)
            Text(factor.pedagogy)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }
}

// MARK: - Factor Enum

private enum AthenaSheetFactor: Hashable {
    case value, quality, momentum, risk

    var title: String {
        switch self {
        case .value:    return "Değer"
        case .quality:  return "Kalite"
        case .momentum: return "Momentum"
        case .risk:     return "Risk"
        }
    }

    var microCaption: String {
        switch self {
        case .value:    return "ucuz mu pahalı mı?"
        case .quality:  return "sağlıklı mı?"
        case .momentum: return "son dönemde yükseliyor mu?"
        case .risk:     return "ne kadar sakin?"
        }
    }

    var pedagogy: String {
        switch self {
        case .value:
            return "Ucuz fiyatlı hisseler uzun vadede fark yaratır (F/K, PD/DD düşükse değerli)."
        case .quality:
            return "İyi işleyen şirketler krizleri rahat atlatır (yüksek ROE, düşük borç)."
        case .momentum:
            return "Kazananlar bir süre daha kazanır (güçlü trend, yerleşik yükseliş)."
        case .risk:
            return "Sakin hisseler zamanla daha iyi getirir (düşük beta = düşük oynaklık)."
        }
    }
}
