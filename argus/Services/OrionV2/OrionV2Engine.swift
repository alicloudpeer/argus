import Foundation

// MARK: - OrionV2 Engine
//
// 2026-05-05 (Round 7B): Eski "5 Ustası" pattern (TrendMaster/MomentumMaster/StructureMaster/
// PatternMaster/PriceMaster — bağımsız oy, static threshold, Atlas eskisi gibi heuristic) yerine
// section-based teknik analiz. AtlasV2 (Round 5) patternının teknik karşılığı.
//
// 6 bölüm: Trend / Momentum / Hacim / Formasyon / Destek-Direnç / Volatilite
// Her bölüm 2-3 standart indicator (IndicatorService kullanır), nil-aware.
// Total skor mevcut bölümlerin ağırlıklı ortalaması, ağırlıklar normalize.

actor OrionV2Engine {
    static let shared = OrionV2Engine()

    private var cache: [String: OrionV2Result] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 dakika
    private var cacheTimestamps: [String: Date] = [:]

    private init() {}

    // MARK: - Ana Analiz

    func analyze(symbol: String, candles: [Candle], forceRefresh: Bool = false) async -> OrionV2Result {
        // Cache kontrolü
        // 2026-05-05 (Round 11): `forceRefresh` parametresi backtest için eklendi.
        // Backtest aynı sembolü farklı candle slice'larıyla 200+ kere çağırır;
        // cache symbol-key'li olduğu için ilk slice'ın sonucu kalanlara yapışırdı.
        // Backtest `forceRefresh: true` ile cache bypass eder, runtime kullanım
        // (default false) cache'ten yararlanır.
        if !forceRefresh, let cached = cache[symbol], let ts = cacheTimestamps[symbol],
           Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }

        guard candles.count >= 50 else {
            return emptyResult(symbol: symbol, reason: "Yetersiz veri (min 50 mum, mevcut \(candles.count))")
        }

        // Her bölümü analiz et
        let (trendScore, trendDetails) = analyzeTrend(candles: candles)
        let (momScore, momDetails) = analyzeMomentum(candles: candles)
        let (volScore, volDetails) = analyzeVolume(candles: candles)
        let (patScore, patDetails) = analyzePattern(candles: candles)
        let (srScore, srDetails) = analyzeSupportResistance(candles: candles)
        let (volatScore, volatDetails) = analyzeVolatility(candles: candles)

        // Round 5 nil-aware aggregator
        let candidateSections: [(label: String, score: Double?, weight: Double)] = [
            ("Trend",         trendScore,  0.30),
            ("Momentum",      momScore,    0.25),
            ("Hacim",         volScore,    0.15),
            ("Formasyon",     patScore,    0.05),
            ("Destek/Direnç", srScore,     0.15),
            ("Volatilite",    volatScore,  0.10)
        ]
        let validSections = candidateSections.compactMap { (lbl, s, w) -> (String, Double, Double)? in
            guard let s = s else { return nil }
            return (lbl, s, w)
        }
        let missingLabels = candidateSections.filter { $0.score == nil }.map { $0.label }

        var warnings: [String] = []
        var totalScore: Double
        if validSections.count < 3 {
            totalScore = 50.0
            warnings.append("⚠️ Veri yetersiz: 6 bölümden \(validSections.count) mevcut. Skor 50 nötr atandı.")
            if !missingLabels.isEmpty {
                warnings.append("Eksik: \(missingLabels.joined(separator: ", "))")
            }
        } else {
            let totalWeight = validSections.reduce(0.0) { $0 + $1.2 }
            let weightedSum = validSections.reduce(0.0) { $0 + $1.1 * $1.2 }
            totalScore = weightedSum / totalWeight
            if !missingLabels.isEmpty {
                warnings.append("ℹ️ Skor \(validSections.count)/6 bölümle hesaplandı. Eksik: \(missingLabels.joined(separator: ", "))")
            }
        }

        // Highlights — yüksek skorlu bölümler
        var highlights: [String] = []
        for (lbl, s, _) in validSections where s >= 75 {
            highlights.append("\(lbl) sinyali güçlü (\(Int(s)))")
        }
        for (lbl, s, _) in validSections where s <= 25 {
            warnings.append("\(lbl) sinyali zayıf (\(Int(s)))")
        }

        let summary: String
        if totalScore >= 70 {       summary = "[\(symbol)] Teknik tablo olumlu — \(Int(totalScore))/100" }
        else if totalScore >= 55 {  summary = "[\(symbol)] Teknik tablo orta-üstü — \(Int(totalScore))/100" }
        else if totalScore >= 45 {  summary = "[\(symbol)] Teknik tablo nötr — \(Int(totalScore))/100" }
        else if totalScore >= 30 {  summary = "[\(symbol)] Teknik tablo orta-altı — \(Int(totalScore))/100" }
        else {                       summary = "[\(symbol)] Teknik tablo olumsuz — \(Int(totalScore))/100" }

        let trace = validSections.map { "\($0.0)=\(Int($0.1))" }.joined(separator: " ")
        ArgusLogger.info(.orion, "V2 \(symbol) total=\(Int(totalScore)) (\(validSections.count)/6 bölüm) \(trace)")

        let result = OrionV2Result(
            symbol: symbol,
            totalScore: min(100, max(0, totalScore)),
            trendScore: trendScore,
            momentumScore: momScore,
            volumeScore: volScore,
            patternScore: patScore,
            srScore: srScore,
            volatilityScore: volatScore,
            trendDetails: trendDetails,
            momentumDetails: momDetails,
            volumeDetails: volDetails,
            patternDetails: patDetails,
            srDetails: srDetails,
            volatilityDetails: volatDetails,
            summary: summary,
            highlights: highlights,
            warnings: warnings,
            validSectionCount: validSections.count
        )

        cache[symbol] = result
        cacheTimestamps[symbol] = Date()
        return result
    }

    // MARK: - Section: Trend (EMA20 vs EMA50, EMA50 vs EMA200, ADX)

    private func analyzeTrend(candles: [Candle]) -> (Double?, [String]) {
        let closes = candles.map { $0.close }
        var details: [String] = []
        var scores: [Double] = []

        if closes.count >= 200,
           let ema20 = IndicatorService.calculateEMA(values: closes, period: 20).last as? Double,
           let ema50 = IndicatorService.calculateEMA(values: closes, period: 50).last as? Double,
           let ema200 = IndicatorService.calculateEMA(values: closes, period: 200).last as? Double {
            let alignment = (ema20 > ema50 ? 1 : 0) + (ema50 > ema200 ? 1 : 0)
            let alignScore = Double(alignment) * 50.0  // 0/50/100
            scores.append(alignScore)
            details.append("EMA hizası: \(alignment)/2 yukarı yönlü (skor \(Int(alignScore)))")
        } else if closes.count >= 50,
                  let ema20 = IndicatorService.calculateEMA(values: closes, period: 20).last as? Double,
                  let ema50 = IndicatorService.calculateEMA(values: closes, period: 50).last as? Double {
            let s = ema20 > ema50 ? 70.0 : 30.0
            scores.append(s)
            details.append("EMA20/EMA50: \(ema20 > ema50 ? "yukarı" : "aşağı") (skor \(Int(s)))")
        }

        if let adx = IndicatorService.lastADX(candles: candles, period: 14) {
            let s: Double
            if adx > 40        { s = 90 }       // Çok güçlü trend
            else if adx > 25   { s = 75 }       // Güçlü trend
            else if adx > 20   { s = 55 }       // Zayıf trend
            else                { s = 35 }       // Trend yok / range
            scores.append(s)
            details.append("ADX(14)=\(String(format: "%.1f", adx)) (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Trend için yeterli veri yok"]) }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return (avg, details)
    }

    // MARK: - Section: Momentum (RSI, MACD)

    private func analyzeMomentum(candles: [Candle]) -> (Double?, [String]) {
        var details: [String] = []
        var scores: [Double] = []

        if let rsi = IndicatorService.lastRSI(candles: candles, period: 14) {
            let regime = ChironRegimeEngine.shared.globalResult.regime
            let s: Double
            if rsi > 70 {
                switch regime {
                case .trend:
                    s = rsi > 85 ? 45 : 65
                default:
                    s = 30
                }
            }
            else if rsi > 60 { s = 75 }
            else if rsi > 50 { s = 65 }
            else if rsi > 40 { s = 50 }
            else if rsi > 30 { s = 40 }
            else              { s = 60 }
            scores.append(s)
            details.append("RSI(14)=\(String(format: "%.1f", rsi)) (skor \(Int(s)))")
        }

        let macd = IndicatorService.lastMACD(candles: candles, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        if let hist = macd.histogram, let macdLine = macd.macd, let signal = macd.signal {
            let bullish = macdLine > signal
            let strength = abs(hist) / max(abs(macdLine), 0.001)
            let s: Double = bullish ? min(85, 55 + strength * 30) : max(15, 45 - strength * 30)
            scores.append(s)
            details.append("MACD=\(String(format: "%.3f", macdLine)) sig=\(String(format: "%.3f", signal)) (\(bullish ? "yukarı" : "aşağı"), skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Momentum için yeterli veri yok"]) }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return (avg, details)
    }

    // MARK: - Section: Hacim (volume vs MA20)

    private func analyzeVolume(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 20 else { return (nil, ["Hacim için yeterli veri yok"]) }
        let volumes = candles.map { Double($0.volume) }
        let recentVol = volumes.suffix(5).reduce(0, +) / 5.0
        let avgVol20 = volumes.suffix(20).reduce(0, +) / 20.0
        guard avgVol20 > 0 else { return (nil, ["Hacim verisi sıfır"]) }

        let ratio = recentVol / avgVol20
        let s: Double
        if ratio > 2.0      { s = 85 }     // Çok yüksek hacim — güçlü ilgi
        else if ratio > 1.3 { s = 70 }     // Yüksek hacim
        else if ratio > 0.8 { s = 55 }     // Normal
        else if ratio > 0.5 { s = 40 }     // Düşük ilgi
        else                 { s = 25 }     // Çok düşük — likidite riski

        return (s, [
            "Son 5 ortalaması: \(String(format: "%.0f", recentVol))",
            "20 ortalaması: \(String(format: "%.0f", avgVol20))",
            "Oran: \(String(format: "%.2fx", ratio)) (skor \(Int(s)))"
        ])
    }

    // MARK: - Section: Formasyon (basit higher highs/lows count)

    private func analyzePattern(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 20 else { return (nil, ["Formasyon için yeterli veri yok"]) }
        let recent = Array(candles.suffix(20))

        var higherHighs = 0
        var higherLows = 0
        var lowerHighs = 0
        var lowerLows = 0

        for i in 1..<recent.count {
            if recent[i].high > recent[i-1].high { higherHighs += 1 } else { lowerHighs += 1 }
            if recent[i].low > recent[i-1].low { higherLows += 1 } else { lowerLows += 1 }
        }

        let bullishCount = higherHighs + higherLows
        let bearishCount = lowerHighs + lowerLows
        let total = bullishCount + bearishCount
        guard total > 0 else { return (nil, ["Formasyon hesabı yapılamadı"]) }

        let bullishRatio = Double(bullishCount) / Double(total)
        let s: Double
        if bullishRatio > 0.65      { s = 80 }   // Net yükselen yapı
        else if bullishRatio > 0.55 { s = 65 }
        else if bullishRatio > 0.45 { s = 50 }   // Sıkışma
        else if bullishRatio > 0.35 { s = 35 }
        else                         { s = 20 }   // Net düşen yapı

        return (s, [
            "HH: \(higherHighs), HL: \(higherLows), LH: \(lowerHighs), LL: \(lowerLows)",
            "Yükselen: %\(Int(bullishRatio * 100)) (skor \(Int(s)))"
        ])
    }

    // MARK: - Section: Destek/Direnç (mevcut fiyat son 50 günün H/L'sine ne kadar yakın)

    private func analyzeSupportResistance(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 50, let last = candles.last else { return (nil, ["S/R için yeterli veri yok"]) }
        let recent50 = candles.suffix(50)
        let high50 = recent50.map { $0.high }.max() ?? last.close
        let low50 = recent50.map { $0.low }.min() ?? last.close
        let range = high50 - low50
        guard range > 0 else { return (nil, ["S/R aralığı sıfır"]) }

        let position = (last.close - low50) / range  // 0 = low (destek), 1 = high (direnç)
        // Simetrik: destek yakını AL sinyali (75), direnç yakını SAT sinyali (25), orta nötr (50)
        let s = 75.0 - (position * 50.0)

        return (s, [
            "50-günlük aralık: \(String(format: "%.2f", low50)) — \(String(format: "%.2f", high50))",
            "Konum: %\(Int(position * 100)) (skor \(Int(s)))"
        ])
    }

    // MARK: - Section: Volatilite (ATR / fiyat oranı, BB band genişliği)

    private func analyzeVolatility(candles: [Candle]) -> (Double?, [String]) {
        guard let last = candles.last, last.close > 0 else { return (nil, ["Volatilite için fiyat yok"]) }
        var details: [String] = []
        var scores: [Double] = []

        if let atr = IndicatorService.lastATR(candles: candles, period: 14) {
            let atrPct = atr / last.close * 100  // %
            // ATR %1-3 normal, %3+ yüksek volatilite (riskli ama büyük hareketler)
            let s: Double
            if atrPct > 5.0      { s = 30 }    // Aşırı volatilite — riskli
            else if atrPct > 3.0 { s = 50 }    // Yüksek
            else if atrPct > 1.5 { s = 65 }    // Normal
            else if atrPct > 0.5 { s = 70 }    // Sıkışmış (potential breakout)
            else                  { s = 50 }    // Çok düşük — illikit
            scores.append(s)
            details.append("ATR(14): %\(String(format: "%.2f", atrPct)) (skor \(Int(s)))")
        }

        let closes = candles.map { $0.close }
        let bb = IndicatorService.lastBollingerBands(values: closes, period: 20, stdDevMultiplier: 2.0)
        if let upper = bb.upper, let lower = bb.lower, let middle = bb.middle, middle > 0 {
            let bandWidth = (upper - lower) / middle * 100
            let s: Double
            if bandWidth > 8 { s = 45 }      // Geniş bantlar (yüksek volatilite)
            else if bandWidth > 4 { s = 60 } // Normal
            else { s = 70 }                  // Daralmış (squeeze - breakout yakın)
            scores.append(s)
            details.append("BB band: %\(String(format: "%.2f", bandWidth)) (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Volatilite hesabı yapılamadı"]) }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return (avg, details)
    }

    // MARK: - Helper: Empty result

    private func emptyResult(symbol: String, reason: String) -> OrionV2Result {
        return OrionV2Result(
            symbol: symbol,
            totalScore: 50,
            trendScore: nil, momentumScore: nil, volumeScore: nil,
            patternScore: nil, srScore: nil, volatilityScore: nil,
            trendDetails: [], momentumDetails: [], volumeDetails: [],
            patternDetails: [], srDetails: [], volatilityDetails: [],
            summary: "[\(symbol)] Teknik analiz yapılamadı",
            highlights: [],
            warnings: [reason],
            validSectionCount: 0
        )
    }
}
