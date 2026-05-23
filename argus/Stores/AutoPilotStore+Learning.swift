import Foundation

// MARK: - Trade Brain 3.0 Learning Loop
/// AutoPilotStore'un öğrenme döngüsü hook'ları. runAutoPilot 24h'lık rate-limit
/// ile runDailyLearningCycle'ı tetikler. Closed trade'ler için de
/// triggerLearningForClosedTrade direct hook noktası var.
extension AutoPilotStore {

    func runDailyLearningCycle() async {
        ArgusLogger.info("Trade Brain 3.0: Gunluk ogrenme dongusu baslatiliyor...", category: "OTOPİLOT")

        let learningService = TradeBrainLearningService.shared
        let confidenceCalibration = ConfidenceCalibrationService.shared

        let currentPrices = await getCurrentPricesForLearning()

        let processed = await learningService.processMaturedObservations(currentPrices: currentPrices)

        let stats = await learningService.getLearningStats()
        let calibrationStats = await confidenceCalibration.getOverallStats()

        ArgusLogger.info("Trade Brain 3.0: \(processed) karar degerlendirildi, \(stats.pendingCount) bekleyen", category: "OTOPİLOT")
        ArgusLogger.info("Trade Brain 3.0: Genel basari: %\(Int(calibrationStats.overallWinRate * 100))", category: "OTOPİLOT")
    }

    func triggerLearningForClosedTrade(
        symbol: String,
        entryPrice: Double,
        exitPrice: Double,
        holdingDays: Int
    ) async {
        let pnlPercent = ((exitPrice - entryPrice) / entryPrice) * 100
        let wasCorrect = pnlPercent > 0

        await TradeBrainExecutor.shared.recordTradeOutcome(
            symbol: symbol,
            wasCorrect: wasCorrect,
            pnlPercent: pnlPercent,
            holdingDays: holdingDays
        )

        ArgusLogger.info("Trade Brain 3.0: Kapali islem ogrenmesi - \(symbol) \(wasCorrect ? "KAR" : "ZARAR")", category: "OTOPİLOT")
    }

    func getCurrentPricesForLearning() async -> [String: Double] {
        let quotes = await MarketDataStore.shared.liveQuotes
        var prices: [String: Double] = [:]

        for (symbol, quote) in quotes {
            prices[symbol] = quote.currentPrice
        }

        return prices
    }

    // MARK: - Enhanced Decision with Trade Brain 3.0

    func makeEnhancedDecision(
        symbol: String,
        candles: [Candle],
        grandDecision: ArgusGrandDecision,
        orionScore: OrionScoreResult?,
        atlasScore: Double?
    ) async -> EnhancedTradeBrainDecision? {
        return await TradeBrainExecutor.shared.makeEnhancedDecision(
            symbol: symbol,
            grandDecision: grandDecision,
            candles: candles,
            orionScore: orionScore,
            atlasScore: atlasScore
        )
    }
}
