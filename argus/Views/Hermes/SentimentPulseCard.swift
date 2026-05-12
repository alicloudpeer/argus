import SwiftUI

// MARK: - SentimentPulseCard (Haber modülü duygu nabzı)
//
// 2026-05-05 H-67 — sade refactor.
//
// Eski V5: MotorLogo(.hermes) + "SENTIMENT PULSE" caps section caption,
// 80pt circle ring + 22pt black mono score, interpretation.uppercased()
// 8pt bold mono tracking 0.7, "BOĞA / AYI" 9pt bold mono tracking 0.6
// caps satırlar, ArgusDot bullet'lı commentary ve recent list, "SON
// ANALİZLER" caps section caption, "MOMENTUM × 1.15" caps chip, hermes
// motor tinted border opacity 0.3, "LLM · 5 / FINNHUB · 5 / FALLBACK"
// caps source badge.
//
// Yeni dil: sade "Duygu nabzı" başlık + sağda "N haber" muted, 80pt
// halkanın içinde 22pt medium skor + sentence durum, "Boğa / Ayı"
// sentence + sade ArgusBar, plain commentary metni (bullet yok),
// "Son analizler" sentence, sade hairline borderSubtle.

struct SentimentPulseCard: View {
    let symbol: String

    @State private var sentiment: HermesQuickSentiment?
    @State private var isLoading = true
    @State private var cachedNews: [HermesSummary] = []
    @State private var commentary: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                loadingBlock
            } else if let s = sentiment {
                heroRow(s)

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                commentaryLine

                if !cachedNews.isEmpty {
                    recentList
                }

                if s.newsCount == 0 {
                    fallbackNote
                }
            } else {
                emptyBlock
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
        .task { await loadSentiment() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Duygu nabzı")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text(sourceBadgeText())
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
    }

    private func heroRow(_ s: HermesQuickSentiment) -> some View {
        let color = sentimentColor(s.score)
        return HStack(spacing: 16) {
            ringGauge(score: s.score, interpretation: s.interpretation, color: color)

            VStack(alignment: .leading, spacing: 10) {
                if let mom = momentumText(for: s.score) {
                    Text(mom.text)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(mom.color)
                }
                sentimentRow(label: "Boğa",
                             value: s.bullishPercent,
                             color: InstitutionalTheme.Colors.aurora)
                sentimentRow(label: "Ayı",
                             value: s.bearishPercent,
                             color: InstitutionalTheme.Colors.crimson)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ringGauge(score: Double,
                           interpretation: String,
                           color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(InstitutionalTheme.Colors.surface3, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, score)) / 100))
                .stroke(color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)

            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                Text(interpretation.lowercased())
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
        }
        .frame(width: 80, height: 80)
    }

    private func sentimentRow(label: String,
                              value: Double,
                              color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text("%\(Int(value))")
                    .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
            }
            ArgusBar(value: max(0, min(1, value / 100)), color: color, height: 4)
        }
    }

    private var commentaryLine: some View {
        Text(commentary)
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Son analizler")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(cachedNews.prefix(2).enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(impactColor(for: item.impactScore))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(item.summaryTR)
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    if idx < min(cachedNews.count, 2) - 1 {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    private var fallbackNote: some View {
        Text("Varsayılan skor — haber analizi yok.")
            .font(DesignTokens.Fonts.custom(size: 11))
            .foregroundColor(InstitutionalTheme.Colors.titan)
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Haber taranıyor…")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Haber taraması bekleniyor")
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text("Haber modülünden \"Haberleri tara\" deyince burada görünür.")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sourceBadgeText() -> String {
        guard let sentiment else { return "Henüz haber yok" }
        switch sentiment.source {
        case .llm, .finnhub: return "\(sentiment.newsCount) haber"
        case .fallback:      return "Varsayılan"
        }
    }

    /// Yüksek/düşük momentum mesajı, sentence dilinde.
    private func momentumText(for score: Double) -> (text: String, color: Color)? {
        if score >= 70 {
            return ("Pozitif momentum · 1.15×", InstitutionalTheme.Colors.aurora)
        }
        if score <= 30 {
            return ("Negatif baskı · 0.85×", InstitutionalTheme.Colors.crimson)
        }
        return nil
    }

    private func sentimentColor(_ score: Double) -> Color {
        if score >= 65 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return DesignTokens.Colors.textPrimary }
        if score >= 30 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func impactColor(for impact: Int) -> Color {
        let v = Double(impact)
        if v >= 65 { return InstitutionalTheme.Colors.aurora }
        if v >= 45 { return DesignTokens.Colors.textSecondary }
        if v >= 30 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Data loading (korundu)

    private func loadSentiment() async {
        isLoading = true

        // UX: loading mesajının görünür olması için kısa bekleme.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        cachedNews = HermesLLMService.shared.getCachedSummaries(for: symbol, count: 3)
        guard !cachedNews.isEmpty else {
            sentiment = nil
            commentary = ""
            isLoading = false
            return
        }

        let quick = await HermesLLMService.shared.getQuickSentiment(for: symbol)
        if quick.newsCount > 0 {
            sentiment = quick
            commentary = generateCommentary(for: quick.score)
        } else {
            sentiment = nil
            commentary = ""
        }

        isLoading = false
    }

    // MARK: - Commentary Generator (korundu)

    private func generateCommentary(for score: Double) -> String {
        let veryBullish = [
            "Piyasa bu hisseye aşırı olumlu bakıyor. Güçlü alım baskısı mevcut.",
            "Yatırımcı güveni zirvelerde. Momentumun devamı muhtemel.",
            "Haberlerde ciddi olumlu gelişmeler var. Dikkatle takip edilmeli.",
            "Boğalar tam kontrolde. Trend yukarı yönlü seyrediyor.",
            "Piyasa algısı fevkalade pozitif. Ralli potansiyeli yüksek."
        ]

        let bullish = [
            "Genel sentiment olumlu görünüyor. Yukarı momentum var.",
            "Alıcılar satıcılardan üstün. Hafif iyimser bir tablo.",
            "Piyasada temkinli iyimserlik hakim. Trend destekli.",
            "Pozitif haberler ağırlıkta. Kısa vadede olumlu.",
            "Yatırımcılar bu seviyelerden alıma devam ediyor."
        ]

        let neutral = [
            "Piyasa kararsız. Belirgin bir yön henüz oluşmadı.",
            "Alıcılar ve satıcılar dengede. Konsolidasyon süreci.",
            "Bekle-gör modunda bir piyasa. Katalist bekleniyor.",
            "Ne güçlü alış ne de satış sinyali var. Yatay seyir.",
            "Volatilite düşük, hacim zayıf. Hareket bekleyen piyasa."
        ]

        let bearish = [
            "Satış baskısı hissediliyor. Dikkatli olunmalı.",
            "Piyasada temkinli pesimizm hakim. Risk algısı yüksek.",
            "Olumsuz haberler ağırlıkta. Kısa vadede baskı.",
            "Ayılar kontrolü ele geçirmiş görünüyor. Aşağı baskı var.",
            "Yatırımcılar kar realizasyonuna yönelmiş durumda."
        ]

        let veryBearish = [
            "Piyasada panik havası var. Ciddi satış baskısı mevcut.",
            "Güven çökmüş durumda. Düşüş trendi güçlü.",
            "Olumsuz gelişmeler fiyatları aşağı çekiyor. Risk yüksek.",
            "Ayılar tam kontrolde. Dip arayışı devam ediyor.",
            "Piyasa aşırı satım bölgesinde. Dikkatli yaklaşılmalı."
        ]

        switch score {
        case 70...100: return veryBullish.randomElement() ?? veryBullish[0]
        case 55..<70:  return bullish.randomElement()    ?? bullish[0]
        case 45..<55:  return neutral.randomElement()    ?? neutral[0]
        case 30..<45:  return bearish.randomElement()    ?? bearish[0]
        default:       return veryBearish.randomElement() ?? veryBearish[0]
        }
    }
}

#Preview {
    ZStack {
        DesignTokens.Colors.background.ignoresSafeArea()
        SentimentPulseCard(symbol: "AAPL")
            .padding()
    }
}
