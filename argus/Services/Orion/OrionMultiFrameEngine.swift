import Foundation

// MARK: - Orion Multi-Frame Engine
/// Farklı zaman dilimlerinde bağımsız teknik analiz yaparak konsensus oluşturur.

@MainActor
final class OrionMultiFrameEngine {
    static let shared = OrionMultiFrameEngine()
    
    private init() {}
    
    // MARK: - Supported Timeframes
    
    enum Timeframe: String, CaseIterable, Codable {
        case m5 = "5m"
        case m15 = "15m"
        case h1 = "1h"
        case h4 = "4h"
        case d1 = "1d"
        case w1 = "1w"
        
        var displayName: String {
            switch self {
            case .m5: return "5 Dakika"
            case .m15: return "15 Dakika"
            case .h1: return "1 Saat"
            case .h4: return "4 Saat"
            case .d1: return "Günlük"
            case .w1: return "Haftalık"
            }
        }
        
        var shortName: String {
            switch self {
            case .m5: return "5D"
            case .m15: return "15D"
            case .h1: return "1S"
            case .h4: return "4S"
            case .d1: return "1G"
            case .w1: return "1H"
            }
        }
        
        var priority: Int {
            switch self {
            case .w1: return 6
            case .d1: return 5
            case .h4: return 4
            case .h1: return 3
            case .m15: return 2
            case .m5: return 1
            }
        }
        
        var strategyBucket: StrategyBucket {
            switch self {
            case .m5, .m15: return .scalp
            case .h1, .h4: return .swing
            case .d1, .w1: return .position
            }
        }
    }
    
    enum StrategyBucket: String, Codable {
        case scalp = "SCALP"
        case swing = "SWING"
        case position = "POSITION"
        
        var displayName: String {
            switch self {
            case .scalp: return "Scalp (Kısa Vade)"
            case .swing: return "Swing (Orta Vade)"
            case .position: return "Position (Uzun Vade)"
            }
        }
        
        var riskMultiplier: Double {
            switch self {
            case .scalp: return 0.5
            case .swing: return 1.0
            case .position: return 1.5
            }
        }
    }
    
    // MARK: - Analysis Models
    
    struct TimeframeAnalysis: Codable {
        let timeframe: Timeframe
        let trendScore: Double
        let momentumScore: Double
        let volumeScore: Double
        let overallScore: Double
        let signal: Signal
        let confidence: Double
        let keyLevels: KeyLevels
        let indicators: IndicatorSnapshot
        
        enum Signal: String, Codable {
            case strongBuy = "GÜÇLÜ AL"
            case buy = "AL"
            case neutral = "NÖTR"
            case sell = "SAT"
            case strongSell = "GÜÇLÜ SAT"
        }
        
        struct KeyLevels: Codable {
            let support: Double?
            let resistance: Double?
            let pivot: Double?
        }
        
        struct IndicatorSnapshot: Codable {
            let rsi: Double?
            let macdHistogram: Double?
            let stochasticK: Double?
            let adx: Double?
            let atr: Double?
            let sma20: Double?
            let sma50: Double?
            let sma200: Double?
        }
    }
    
    struct MultiFrameReport: Codable {
        let symbol: String
        let timestamp: Date
        let analyses: [TimeframeAnalysis]
        let consensus: ConsensusResult
        let bucketRecommendations: [StrategyBucket: BucketRecommendation]
    }
    
    struct ConsensusResult: Codable {
        let overallSignal: TimeframeAnalysis.Signal
        let confidence: Double
        let alignment: AlignmentStatus
        let dominantTimeframe: Timeframe
        let conflictingTimeframes: [Timeframe]
        let summary: String
        
        enum AlignmentStatus: String, Codable {
            case fullAlignment = "TAM UYUM"
            case partialAlignment = "KISMİ UYUM"
            case conflict = "ÇATIŞMA"
            case noData = "VERİ YOK"
        }
    }
    
    struct BucketRecommendation: Codable {
        let bucket: StrategyBucket
        let signal: TimeframeAnalysis.Signal
        let confidence: Double
        let reasoning: String
        let suggestedAction: String
    }
    
    // MARK: - API
    
    func analyzeTimeframe(symbol: String, candles: [Candle], timeframe: Timeframe) -> TimeframeAnalysis? {
        guard candles.count >= 50 else { return nil }
        
        let closes = candles.map { $0.close }
        let currentPrice = closes.last ?? 0
        
        let rsi = IndicatorService.lastRSI(values: closes)
        let macd = IndicatorService.lastMACD(values: closes)
        let stoch = IndicatorService.lastStochastic(candles: candles)
        let adx = IndicatorService.lastADX(candles: candles)
        let atr = IndicatorService.lastATR(candles: candles)
        let bb = IndicatorService.lastBollingerBands(values: closes)
        
        let sma20 = IndicatorService.lastSMA(values: closes, period: 20)
        let sma50 = IndicatorService.lastSMA(values: closes, period: 50)
        let sma200 = closes.count >= 200 ? IndicatorService.lastSMA(values: closes, period: 200) : nil
        
        var trendScore: Double = 50
        if let s20 = sma20, let s50 = sma50 {
            if currentPrice > s20 && s20 > s50 { trendScore = 80 }
            else if currentPrice < s20 && s20 < s50 { trendScore = 20 }
            else if currentPrice > s20 { trendScore = 65 }
            else { trendScore = 35 }
        }
        if let s200 = sma200 {
            trendScore += currentPrice > s200 ? 10 : -10
        }
        trendScore = max(0, min(100, trendScore))
        
        var momentumScore: Double = 50
        if let r = rsi {
            if r > 70 { momentumScore -= 20 }
            else if r < 30 { momentumScore += 20 }
            else if r > 50 { momentumScore += 10 }
            else { momentumScore -= 10 }
        }
        if let h = macd.histogram {
            momentumScore += h > 0 ? 15 : -15
        }
        if let k = stoch.k {
            if k > 80 { momentumScore -= 10 }
            else if k < 20 { momentumScore += 10 }
        }
        momentumScore = max(0, min(100, momentumScore))
        
        var volumeScore: Double = 50
        if let a = adx {
            volumeScore = a > 25 ? min(100, 50 + a) : max(0, 50 - (25 - a))
        }

        // 2026-05-13 Task 4: Chiron'un öğrendiği master ağırlıkları artık burada
        // kullanılıyor. Önceki sabit 0.4/0.4/0.2 ağırlıkları ChironCouncilLearning-
        // Service'in master rolleri öğrenmesini hiçbir karara yansıtmıyordu — tam
        // ölü öğrenme döngüsü. Mapping:
        //   trendScore    → trendMaster
        //   momentumScore → momentumMaster
        //   volumeScore   → priceMaster (hacim/fiyat ekseni)
        // structureMaster + patternMaster MultiFrameEngine'de üretilmiyor (pattern
        // detection OrionAnalysisService'in alt-bileşeni); şimdilik bu master
        // ağırlıkları MultiFrameEngine kompozisyonunda kullanılmıyor.
        //
        // Timeframe → Engine: scalp + swing → .pulse, position → .corse.
        let engine: AutoPilotEngine = (timeframe.strategyBucket == .position) ? .corse : .pulse
        let chiron = ChironCouncilLearningService.shared.getCouncilWeights(symbol: symbol, engine: engine)
        let normalizer = chiron.trendMaster + chiron.momentumMaster + chiron.priceMaster
        let trendW: Double
        let momentumW: Double
        let volumeW: Double
        if normalizer > 0.001 {
            trendW = chiron.trendMaster / normalizer
            momentumW = chiron.momentumMaster / normalizer
            volumeW = chiron.priceMaster / normalizer
        } else {
            // Defensive fallback — Chiron weights bozulmuşsa eski sabit kompozisyon
            trendW = 0.4
            momentumW = 0.4
            volumeW = 0.2
        }
        let overallScore = (trendScore * trendW) + (momentumScore * momentumW) + (volumeScore * volumeW)
        
        let signal: TimeframeAnalysis.Signal
        if overallScore >= 75 { signal = .strongBuy }
        else if overallScore >= 60 { signal = .buy }
        else if overallScore >= 40 { signal = .neutral }
        else if overallScore >= 25 { signal = .sell }
        else { signal = .strongSell }
        
        let confidence = calculateConfidence(trend: trendScore, momentum: momentumScore, volume: volumeScore)
        
        return TimeframeAnalysis(
            timeframe: timeframe,
            trendScore: trendScore,
            momentumScore: momentumScore,
            volumeScore: volumeScore,
            overallScore: overallScore,
            signal: signal,
            confidence: confidence,
            keyLevels: TimeframeAnalysis.KeyLevels(support: bb.lower, resistance: bb.upper, pivot: bb.middle),
            indicators: TimeframeAnalysis.IndicatorSnapshot(
                rsi: rsi,
                macdHistogram: macd.histogram,
                stochasticK: stoch.k,
                adx: adx,
                atr: atr,
                sma20: sma20,
                sma50: sma50,
                sma200: sma200
            )
        )
    }
    
    func analyzeMultiFrame(
        symbol: String,
        fetchCandles: (String, String) async -> [Candle]?
    ) async -> MultiFrameReport {
        var analyses: [TimeframeAnalysis] = []
        
        for tf in Timeframe.allCases {
            if let candles = await fetchCandles(symbol, tf.shortName) {
                if let analysis = analyzeTimeframe(symbol: symbol, candles: candles, timeframe: tf) {
                    analyses.append(analysis)
                }
            }
        }
        
        let consensus = calculateConsensus(analyses: analyses)
        let bucketRecs = calculateBucketRecommendations(analyses: analyses)
        
        return MultiFrameReport(
            symbol: symbol,
            timestamp: Date(),
            analyses: analyses,
            consensus: consensus,
            bucketRecommendations: bucketRecs
        )
    }
    
    // MARK: - Private Helpers
    
    private func calculateConfidence(trend: Double, momentum: Double, volume: Double) -> Double {
        let trendBias = trend > 50 ? 1 : -1
        let momentumBias = momentum > 50 ? 1 : -1
        let volumeBias = volume > 50 ? 1 : -1
        
        if trendBias == momentumBias && momentumBias == volumeBias {
            return 0.85
        } else if trendBias == momentumBias || trendBias == volumeBias {
            return 0.65
        } else {
            return 0.45
        }
    }
    
    private func calculateConsensus(analyses: [TimeframeAnalysis]) -> ConsensusResult {
        guard !analyses.isEmpty else {
            return ConsensusResult(
                overallSignal: .neutral,
                confidence: 0,
                alignment: .noData,
                dominantTimeframe: .d1,
                conflictingTimeframes: [],
                summary: "Veri yok"
            )
        }
        
        var weightedScore: Double = 0
        var totalWeight: Double = 0
        var bullishCount = 0
        var bearishCount = 0
        var conflicting: [Timeframe] = []

        // Faz I.4 (2026-05-12) — m5 gürültü dampener (1.0 → 0.5).
        // 5 dakikalık TF tek başına sinyal flippinin başlıca kaynağı; konsensus
        // skorunda %5 → %2.5 ağırlığa düştü. Alignment sayımına dahil edilmiyor
        // (tek başına bullish/bearishCount'u zıplatıyordu). Daha üst TF'ler
        // (1h+) sahipliği koruyor.
        for analysis in analyses {
            let noiseDamper: Double = analysis.timeframe == .m5 ? 0.5 : 1.0
            let weight = Double(analysis.timeframe.priority) * noiseDamper
            weightedScore += analysis.overallScore * weight
            totalWeight += weight

            // m5 alignment sayımına dahil değil — gürültülü TF'in tek başına
            // fullAlignment ↔ partialAlignment ↔ conflict zıplatması engelleniyor.
            if analysis.timeframe == .m5 { continue }
            if analysis.overallScore >= 60 { bullishCount += 1 }
            else if analysis.overallScore <= 40 { bearishCount += 1 }
        }
        
        let avgScore = totalWeight > 0 ? weightedScore / totalWeight : 50

        let overallSignal: TimeframeAnalysis.Signal
        if avgScore >= 75 { overallSignal = .strongBuy }
        else if avgScore >= 60 { overallSignal = .buy }
        else if avgScore >= 40 { overallSignal = .neutral }
        else if avgScore >= 25 { overallSignal = .sell }
        else { overallSignal = .strongSell }

        // Faz I.4: bullishCount/bearishCount artık m5'i hariç tutuyor; alignment
        // payda da m5 hariç olmalı. Yoksa fullAlignment hiçbir zaman tetiklenmez
        // (bullishCount=5, analyses.count=6 mantıksızca eşitsiz olur).
        let alignmentDenominator = analyses.filter { $0.timeframe != .m5 }.count
        let alignment: ConsensusResult.AlignmentStatus
        if alignmentDenominator > 0 && (bullishCount == alignmentDenominator || bearishCount == alignmentDenominator) {
            alignment = .fullAlignment
        } else if alignmentDenominator > 0 && (bullishCount >= alignmentDenominator / 2 || bearishCount >= alignmentDenominator / 2) {
            alignment = .partialAlignment
        } else {
            alignment = .conflict
        }
        
        let majorityBullish = bullishCount > bearishCount
        for analysis in analyses {
            let isBullish = analysis.overallScore >= 60
            let isBearish = analysis.overallScore <= 40
            if (majorityBullish && isBearish) || (!majorityBullish && isBullish) {
                conflicting.append(analysis.timeframe)
            }
        }
        
        let dominant = analyses
            .filter { $0.overallScore >= 60 || $0.overallScore <= 40 }
            .max { $0.timeframe.priority < $1.timeframe.priority }?
            .timeframe ?? .d1
        
        let confidence = alignment == .fullAlignment ? 0.9 : (alignment == .partialAlignment ? 0.65 : 0.4)
        
        let summary: String
        switch alignment {
        case .fullAlignment:
            summary = "Tüm zaman dilimleri \(overallSignal.rawValue) yönünde uyumlu"
        case .partialAlignment:
            summary = "Çoğunluk \(overallSignal.rawValue) yönünde, \(conflicting.count) zaman dilimi çatışıyor"
        case .conflict:
            summary = "Zaman dilimleri arasında ciddi çatışma var"
        case .noData:
            summary = "Yeterli veri yok"
        }
        
        return ConsensusResult(
            overallSignal: overallSignal,
            confidence: confidence,
            alignment: alignment,
            dominantTimeframe: dominant,
            conflictingTimeframes: conflicting,
            summary: summary
        )
    }
    
    private func calculateBucketRecommendations(analyses: [TimeframeAnalysis]) -> [StrategyBucket: BucketRecommendation] {
        var recs: [StrategyBucket: BucketRecommendation] = [:]
        
        for bucket in [StrategyBucket.scalp, .swing, .position] {
            let relevantAnalyses = analyses.filter { $0.timeframe.strategyBucket == bucket }
            
            guard !relevantAnalyses.isEmpty else {
                recs[bucket] = BucketRecommendation(
                    bucket: bucket,
                    signal: .neutral,
                    confidence: 0,
                    reasoning: "Bu strateji için yeterli veri yok",
                    suggestedAction: "Bekle"
                )
                continue
            }
            
            let avgScore = relevantAnalyses.map { $0.overallScore }.reduce(0, +) / Double(relevantAnalyses.count)
            let avgConfidence = relevantAnalyses.map { $0.confidence }.reduce(0, +) / Double(relevantAnalyses.count)
            
            let signal: TimeframeAnalysis.Signal
            if avgScore >= 70 { signal = .strongBuy }
            else if avgScore >= 55 { signal = .buy }
            else if avgScore >= 45 { signal = .neutral }
            else if avgScore >= 30 { signal = .sell }
            else { signal = .strongSell }
            
            let reasoning: String
            let action: String
            
            switch signal {
            case .strongBuy:
                reasoning = "\(bucket.displayName) için güçlü alım sinyalleri"
                action = "Pozisyon aç"
            case .buy:
                reasoning = "\(bucket.displayName) pozitif görünüyor"
                action = "Küçük pozisyon dene"
            case .neutral:
                reasoning = "Net sinyal yok"
                action = "Bekle"
            case .sell:
                reasoning = "\(bucket.displayName) için negatif sinyaller"
                action = "Pozisyonu kapat"
            case .strongSell:
                reasoning = "\(bucket.displayName) için güçlü satış sinyalleri"
                action = "Hemen çık"
            }
            
            recs[bucket] = BucketRecommendation(
                bucket: bucket,
                signal: signal,
                confidence: avgConfidence,
                reasoning: reasoning,
                suggestedAction: action
            )
        }
        
        return recs
    }
}
