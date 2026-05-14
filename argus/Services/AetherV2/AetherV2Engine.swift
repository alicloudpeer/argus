import Foundation

// MARK: - AetherV2 Engine
//
// 2026-05-05 (Round 7B): Eski 5 "Master" pattern (MonetaryPolicy/MarketSentiment/
// SectorRotation/EconomicCycle/CrossAsset) yerine section-based makro analiz.
// Türkçe naming: "Para Politikası" / "Piyasa Hissiyatı" / "Sektör Rotasyonu" / vb.
// Round 5/7 patternı (nil-aware, weight normalize, en az 3 bölüm gereği).
//
// 5 bölüm:
// - Likidite (faiz seviyesi, getiri eğrisi)
// - Risk Modu (VIX, F&G index)
// - Sektör Rotasyonu (genişleme/daralma fazı)
// - Cross-Asset (DXY, 10Y yield, gold bilgisi)
// - Sentiment (put/call, A/D ratio, breadth)

actor AetherV2Engine {
    static let shared = AetherV2Engine()

    private var cache: AetherV2Result? = nil
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 300  // 5 dakika

    private var vixHistory: [(date: Date, value: Double)] = []
    private let vixHistoryWindow: TimeInterval = 5 * 24 * 3600  // 5 gün

    private init() {}

    // MARK: - Ana Analiz

    func analyze(macro: MacroSnapshot) async -> AetherV2Result {
        if let cached = cache, Date().timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cached
        }

        let (liqScore, liqDetails) = analyzeLiquidity(macro: macro)
        let (riskScore, riskDetails) = analyzeRiskMode(macro: macro)
        let (sectorScore, sectorDetails) = analyzeSectorRotation(macro: macro)
        let (crossScore, crossDetails) = analyzeCrossAsset(macro: macro)
        let (sentScore, sentDetails) = analyzeSentiment(macro: macro)

        let candidateSections: [(label: String, score: Double?, weight: Double)] = [
            ("Likidite",          liqScore,    0.25),
            ("Risk Modu",         riskScore,   0.25),
            ("Sektör Rotasyonu",  sectorScore, 0.20),
            ("Cross-Asset",       crossScore,  0.20),
            ("Hissiyat",          sentScore,   0.10)
        ]
        let validSections = candidateSections.compactMap { (lbl, s, w) -> (String, Double, Double)? in
            guard let s = s else { return nil }
            return (lbl, s, w)
        }
        let missingLabels = candidateSections.filter { $0.score == nil }.map { $0.label }

        var warnings: [String] = []
        var highlights: [String] = []
        let totalScore: Double
        if validSections.count < 2 {
            totalScore = 50.0
            warnings.append("⚠️ Makro veri yetersiz: 5 bölümden \(validSections.count) mevcut. Skor 50 nötr.")
            if !missingLabels.isEmpty {
                warnings.append("Eksik: \(missingLabels.joined(separator: ", "))")
            }
        } else {
            let totalWeight = validSections.reduce(0.0) { $0 + $1.2 }
            let weightedSum = validSections.reduce(0.0) { $0 + $1.1 * $1.2 }
            totalScore = weightedSum / totalWeight
            if !missingLabels.isEmpty {
                warnings.append("ℹ️ Skor \(validSections.count)/5 bölümle hesaplandı. Eksik: \(missingLabels.joined(separator: ", "))")
            }
        }

        for (lbl, s, _) in validSections where s >= 75 { highlights.append("\(lbl) güçlü olumlu (\(Int(s)))") }
        for (lbl, s, _) in validSections where s <= 25 { warnings.append("\(lbl) güçlü olumsuz (\(Int(s)))") }

        let summary: String
        if totalScore >= 70       { summary = "Makro: Risk-on uygun (\(Int(totalScore))/100)" }
        else if totalScore >= 55  { summary = "Makro: Cautious — orta-üstü uygun (\(Int(totalScore))/100)" }
        else if totalScore >= 45  { summary = "Makro: Nötr (\(Int(totalScore))/100)" }
        else if totalScore >= 30  { summary = "Makro: Defensive — orta-altı (\(Int(totalScore))/100)" }
        else                       { summary = "Makro: Risk-off (\(Int(totalScore))/100)" }

        let trace = validSections.map { "\($0.0)=\(Int($0.1))" }.joined(separator: " ")
        ArgusLogger.info(.aether, "V2 total=\(Int(totalScore)) (\(validSections.count)/5 bölüm) \(trace)")

        let result = AetherV2Result(
            totalScore: min(100, max(0, totalScore)),
            liquidityScore: liqScore,
            riskOffScore: riskScore,
            sectorRotationScore: sectorScore,
            crossAssetScore: crossScore,
            sentimentScore: sentScore,
            liquidityDetails: liqDetails,
            riskOffDetails: riskDetails,
            sectorRotationDetails: sectorDetails,
            crossAssetDetails: crossDetails,
            sentimentDetails: sentDetails,
            summary: summary,
            highlights: highlights,
            warnings: warnings,
            validSectionCount: validSections.count
        )

        cache = result
        cacheTimestamp = Date()
        return result
    }

    // MARK: - Section: Likidite (Fed faizi seviyesi + yield curve)
    //
    // Faz I.3 (2026-05-12) — Ağırlıklı harman:
    //   Eski model: scores.reduce/count eşit ağırlıklı ortalama. Fed seviyesi
    //   ve getiri eğrisi sinyalleri aynı oranda etkili sayılıyordu.
    //   Yeni model: Fed seviyesi 0.65, yield curve 0.35. Fed faizinin hisse
    //   senedi performansına doğrudan etkisi yield curve sinyalinden daha
    //   güçlü (likidite akışı ↔ inversiyon ihbar göstergesi).

    private func analyzeLiquidity(macro: MacroSnapshot) -> (Double?, [String]) {
        var details: [String] = []
        var fedScore: Double? = nil
        var yieldScore: Double? = nil

        if let fedRate = macro.fedFundsRate {
            // Düşük faiz = bol likidite = risk-on uygun
            let s: Double
            if fedRate < 1.0      { s = 90 }
            else if fedRate < 2.5 { s = 75 }
            else if fedRate < 4.0 { s = 55 }
            else if fedRate < 5.5 { s = 35 }
            else                   { s = 25 }   // Sıkı para politikası
            fedScore = s
            details.append("Fed faizi: %\(String(format: "%.2f", fedRate)) (skor \(Int(s)), ağırlık 0.65)")
        }

        // Yield curve inversion = resesyon işareti = likidite zayıflıyor
        if macro.yieldCurveInverted {
            yieldScore = 30
            details.append("Getiri eğrisi ters: -20 (skor 30, ağırlık 0.35)")
        } else if macro.tenYearYield != nil && macro.twoYearYield != nil {
            yieldScore = 65
            details.append("Getiri eğrisi normal: +15 (skor 65, ağırlık 0.35)")
        }

        // Ağırlıklı blend (0.65 fed / 0.35 yield)
        let blended: Double?
        switch (fedScore, yieldScore) {
        case (let f?, let y?): blended = 0.65 * f + 0.35 * y
        case (let f?, nil):    blended = f
        case (nil, let y?):    blended = y
        default:               blended = nil
        }

        guard let s = blended else { return (nil, ["Likidite için Fed/yield verisi yok"]) }
        return (s, details)
    }

    // MARK: - Section: Risk Modu (VIX seviye + VIX değişim + F&G)
    //
    // Contrarian yaklaşım (variance risk premium literatürü):
    //   Yüksek VIX → tarihsel olarak pozitif forward return (korku fırsat yaratır).
    //   Düşük VIX → complacency riski (rehavet tuzağı).
    //   F&G extreme fear → contrarian AL, extreme greed → contrarian dikkat.
    //
    // VIX seviye (contrarian): 0.40
    // VIX 5-günlük değişim (momentum): 0.20
    // F&G (contrarian): 0.25
    // Put/Call sentiment'e taşındı → burada sadece VIX+F&G.
    // Kalan 0.15 → sentiment section'da put/call ile dolu.

    private func analyzeRiskMode(macro: MacroSnapshot) -> (Double?, [String]) {
        var details: [String] = []
        var vixLevelScore: Double? = nil
        var vixDeltaScore: Double? = nil
        var fgScore: Double? = nil

        if let vix = macro.vix {
            // VIX geçmişini güncelle (delta hesabı için)
            let now = Date()
            vixHistory.append((date: now, value: vix))
            vixHistory.removeAll { now.timeIntervalSince($0.date) > vixHistoryWindow }

            // --- VIX SEVİYE (contrarian) ---
            // Yüksek VIX = piyasa panikte → tarihsel forward return pozitif
            // Düşük VIX = rehavet → complacency riski
            let level: Double
            if vix < 13       { level = 35 }   // Aşırı rehavet — complacency riski
            else if vix < 18  { level = 55 }   // Normal sakinlik
            else if vix < 22  { level = 65 }   // Hafif korku — forward return tarihsel olarak pozitif
            else if vix < 30  { level = 75 }   // Ciddi korku — contrarian fırsat
            else              { level = 80 }   // Panik — güçlü rebound beklentisi
            vixLevelScore = level
            details.append("VIX seviye=\(String(format: "%.1f", vix)) → \(Int(level)) (contrarian)")

            // --- VIX DEĞİŞİM (momentum) ---
            // ~5 gün önceki VIX ile karşılaştır (history'den en yakın kayıt)
            let fiveDaysAgo = now.addingTimeInterval(-5 * 24 * 3600)
            let vixPrev = vixHistory
                .filter { $0.date <= fiveDaysAgo }
                .last?.value
            if let vixPrev = vixPrev {
                let delta = vix - vixPrev
                let d: Double
                if delta > 10      { d = 25 }   // Panik hızla tırmanıyor — henüz erken
                else if delta > 5  { d = 40 }   // Belirgin artış — temkinli
                else if delta > -3 { d = 55 }   // Stabil
                else if delta > -8 { d = 70 }   // Düşüş başladı — toparlanma sinyali
                else               { d = 80 }   // Hızlı çözülme — güçlü toparlanma
                vixDeltaScore = d
                details.append("VIX Δ5g=\(String(format: "%+.1f", delta)) → \(Int(d))")
            }
        }

        if let fg = macro.fearGreedIndex {
            // --- F&G (contrarian) ---
            // Extreme fear → tarihsel forward return pozitif (contrarian AL)
            // Extreme greed → düzeltme riski (contrarian dikkat)
            let s: Double
            if fg > 85       { s = 20 }   // Aşırı açgözlülük — düzeltme çok yakın
            else if fg > 75  { s = 35 }   // Açgözlülük — temkinli ol
            else if fg > 55  { s = 50 }   // Hafif olumlu
            else if fg > 40  { s = 60 }   // Nötr
            else if fg > 25  { s = 70 }   // Korku — contrarian fırsat
            else if fg > 10  { s = 80 }   // Aşırı korku — güçlü contrarian AL
            else              { s = 85 }   // Panik — tarihsel olarak dip bölgesi
            fgScore = s
            details.append("F&G=\(Int(fg)) → \(Int(s)) (contrarian)")
        }

        // Ağırlıklı harman: seviye 0.40, delta 0.20, F&G 0.25
        // Delta yoksa seviye+F&G normalize edilir
        let components: [(Double, Double)] = [
            vixLevelScore.map { ($0, 0.40) },
            vixDeltaScore.map { ($0, 0.20) },
            fgScore.map { ($0, 0.25) }
        ].compactMap { $0 }

        guard !components.isEmpty else { return (nil, ["Risk modu için VIX/F&G verisi yok"]) }

        let totalWeight = components.reduce(0.0) { $0 + $1.1 }
        let blended = components.reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight

        // Kalan ağırlık (0.15) sentiment section'da put/call'a ayrılmış
        return (blended, details)
    }

    // MARK: - Section: Sektör Rotasyonu

    private func analyzeSectorRotation(macro: MacroSnapshot) -> (Double?, [String]) {
        guard let phase = macro.sectorRotation else {
            return (nil, ["Sektör rotasyon fazı tespit edilemedi"])
        }
        let s: Double
        let detail: String
        switch phase {
        case .earlyExpansion:
            s = 80; detail = "Erken genişleme — risk-on güçlü"
        case .lateExpansion:
            s = 60; detail = "Geç genişleme — temkinli olumlu"
        case .earlyRecession:
            s = 35; detail = "Erken resesyon — defensive"
        case .lateRecession:
            s = 25; detail = "Geç resesyon — risk-off"
        }
        return (s, ["Faz: \(detail)"])
    }

    // MARK: - Section: Cross-Asset (DXY, 10Y yield)

    private func analyzeCrossAsset(macro: MacroSnapshot) -> (Double?, [String]) {
        var details: [String] = []
        var scores: [Double] = []

        if let dxy = macro.dxy {
            // DXY yüksek = güçlü dolar = riskli varlıklara olumsuz
            let s: Double
            if dxy > 108        { s = 25 }
            else if dxy > 104   { s = 40 }
            else if dxy > 100   { s = 60 }
            else if dxy > 96    { s = 75 }
            else                { s = 60 }   // Çok zayıf dolar = enflasyon riski
            scores.append(s)
            details.append("DXY=\(String(format: "%.2f", dxy)) (skor \(Int(s)))")
        }

        if let ten = macro.tenYearYield {
            // 10Y yield: düşük = bond bid, yüksek = duration risk
            let s: Double
            if ten < 2.5       { s = 75 }
            else if ten < 4.0  { s = 60 }
            else if ten < 5.0  { s = 40 }
            else                { s = 25 }
            scores.append(s)
            details.append("10Y yield: %\(String(format: "%.2f", ten)) (skor \(Int(s)))")
        }

        if let brent = macro.brent {
            // Brent: 80 dolar civarı normal, 100+ enflasyonist baskı
            let s: Double
            if brent > 100      { s = 35 }
            else if brent > 85  { s = 50 }
            else if brent > 70  { s = 65 }
            else                 { s = 60 }
            scores.append(s)
            details.append("Brent: $\(String(format: "%.2f", brent)) (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Cross-asset (DXY/10Y/Brent) verisi yok"]) }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return (avg, details)
    }

    // MARK: - Section: Sentiment (put/call, A/D ratio, breadth)

    private func analyzeSentiment(macro: MacroSnapshot) -> (Double?, [String]) {
        var details: [String] = []
        var scores: [Double] = []

        if let pcr = macro.putCallRatio {
            // Put/call > 1.0 = bearish, < 0.7 = bullish (kontrarian olarak da okunabilir)
            let s: Double
            if pcr > 1.2      { s = 60 }   // Kontrarian: aşırı pessimism = bottom yakın
            else if pcr > 0.9 { s = 45 }   // Düşük güven
            else if pcr > 0.7 { s = 60 }   // Normal
            else               { s = 35 }   // Aşırı iyimserlik = tepe yakın
            scores.append(s)
            details.append("Put/Call: \(String(format: "%.2f", pcr)) (skor \(Int(s)))")
        }

        if let ad = macro.advanceDeclineRatio {
            // A/D > 1.0 = breadth pozitif
            let s: Double
            if ad > 1.5       { s = 80 }
            else if ad > 1.0  { s = 65 }
            else if ad > 0.7  { s = 50 }
            else if ad > 0.5  { s = 35 }
            else               { s = 20 }
            scores.append(s)
            details.append("A/D ratio: \(String(format: "%.2f", ad)) (skor \(Int(s)))")
        }

        if let above = macro.percentAbove200MA {
            let s: Double
            if above > 70      { s = 80 }
            else if above > 50 { s = 65 }
            else if above > 30 { s = 45 }
            else                { s = 25 }
            scores.append(s)
            details.append("%200MA üstü: %\(Int(above)) (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Sentiment göstergesi (P/C, A/D, breadth) yok"]) }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return (avg, details)
    }
}
