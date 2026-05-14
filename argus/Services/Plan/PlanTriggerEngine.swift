import Foundation

/// Plan trigger değerlendirme motoru + teknik gösterge yardımcıları.
/// God Object Aşama B — PositionPlanStore'dan çıkarıldı.
///
/// Sorumluluk:
/// - 30+ trigger tipini değerlendir (price, time, technical, council, regime)
/// - Teknik göstergeleri hesapla (SMA, ATR, S/R, trend)
/// - Rejim değişimi tespit et + plan review bayrakları
///
/// PlanRepository.shared'i hem trigger eval (`plans` okuma) hem
/// regime shift (`plans` yazma) için kullanır.
///
/// NOT: @MainActor değil — orijinal PositionPlanStore non-isolated idi.
final class PlanTriggerEngine {
    static let shared = PlanTriggerEngine()

    /// Quote cache — her tick'te `updatePriceQuotes()` ile güncellenir.
    private var priceQuotes: [String: Quote] = [:]

    /// Candle cache — TVM `updateCandles()` çağrısıyla beslenir.
    private(set) var candleStore: [String: [Candle]] = [:]

    /// Son gözlemlenen rejim etiketi (BULLISH/BEARISH/NEUTRAL).
    /// İlk değişim transition'ında plan review bayrağı yakılır.
    private var lastObservedRegime: String?

    private init() {}

    // MARK: - Data Sync

    func updatePriceQuotes(_ quotes: [String: Quote]) {
        self.priceQuotes = quotes
        updatePlanPrices()
        checkRegimeShift()
    }

    func updateCandles(_ candles: [String: [Candle]]) {
        self.candleStore = candles
    }

    /// Açık planların `highestPrice`'ını güncelle (trailing stop için tepe takibi).
    func updatePlanPrices() {
        guard !priceQuotes.isEmpty else { return }

        var updatedCount = 0
        for (tradeId, var plan) in PlanRepository.shared.plans {
            guard let planSymbol = plan.originalSnapshot.symbol as String? else { continue }

            if let quote = priceQuotes[planSymbol] {
                if quote.currentPrice > plan.highestPrice {
                    plan.highestPrice = quote.currentPrice
                    PlanRepository.shared.plans[tradeId] = plan
                    updatedCount += 1
                }
            }
        }

        if updatedCount > 0 {
            PlanRepository.shared.persist()
            print("💰 \(updatedCount) planın highestPrice güncellendi")
        }
    }

    // MARK: - Regime Shift Detection

    /// Aether score'dan rejim etiketi türet (BULLISH ≥60, BEARISH ≤40, NEUTRAL).
    static func currentRegimeLabel() -> String? {
        guard let score = MacroRegimeService.shared.getCachedRating()?.numericScore else {
            return nil
        }
        if score >= 60 { return "BULLISH" }
        if score <= 40 { return "BEARISH" }
        return "NEUTRAL"
    }

    /// Rejim değişiminde aktif planları `requiresReview = true` ile işaretle.
    /// Rate-limit: aynı rejimde tekrar tetiklenmez.
    private func checkRegimeShift() {
        let current = PlanTriggerEngine.currentRegimeLabel()
        defer { lastObservedRegime = current }
        guard let current, let last = lastObservedRegime, last != current else { return }

        var flaggedCount = 0
        let repo = PlanRepository.shared
        for (id, var plan) in repo.plans where plan.isActive && plan.requiresReview != true {
            plan.requiresReview = true
            plan.lastUpdated = Date()
            repo.plans[id] = plan
            flaggedCount += 1
        }
        if flaggedCount > 0 {
            repo.persist()
            ArgusLogger.info(
                "PositionPlan: rejim \(last) → \(current), \(flaggedCount) aktif plan review bayrağı aldı",
                category: "PLAN"
            )
        }
    }

    // MARK: - Trigger Evaluation

    /// Trade için tetiklenen ilk aksiyonu döndür (varsa).
    func checkTriggers(
        trade: Trade,
        currentPrice: Double,
        grandDecision: ArgusGrandDecision?
    ) -> PlannedAction? {
        guard let plan = PlanRepository.shared.plans[trade.id], plan.isActive else { return nil }

        let entryPrice = plan.originalSnapshot.entryPrice
        let pnlPercent = ((currentPrice - entryPrice) / entryPrice) * 100
        let daysHeld = Calendar.current.dateComponents([.day], from: plan.dateCreated, to: Date()).day ?? 0

        let activeScenarios = [plan.bullishScenario, plan.bearishScenario, plan.neutralScenario]
            .compactMap { $0 }
            .filter { $0.isActive }

        for scenario in activeScenarios {
            for step in scenario.steps {
                if plan.executedSteps.contains(step.id) { continue }

                let triggered = checkTrigger(
                    trigger: step.trigger,
                    currentPrice: currentPrice,
                    entryPrice: entryPrice,
                    highestPrice: max(plan.highestPrice, entryPrice),
                    pnlPercent: pnlPercent,
                    daysHeld: daysHeld,
                    grandDecision: grandDecision
                )

                if triggered {
                    print("🎯 Tetiklendi: \(plan.originalSnapshot.symbol) - \(step.description)")
                    return step
                }
            }
        }

        return nil
    }

    private func checkTrigger(
        trigger: ActionTrigger,
        currentPrice: Double,
        entryPrice: Double,
        highestPrice: Double,
        pnlPercent: Double,
        daysHeld: Int,
        grandDecision: ArgusGrandDecision?
    ) -> Bool {
        let rsi = grandDecision?.orionDetails?.components.rsi

        switch trigger {
        // BASIC
        case .priceAbove(let target):
            return currentPrice > target

        case .priceBelow(let target):
            return currentPrice < target

        case .gainPercent(let target):
            return pnlPercent >= target

        case .lossPercent(let target):
            return pnlPercent <= -target

        case .daysElapsed(let days):
            return daysHeld >= days

        case .councilSignal(let signal):
            guard let gd = grandDecision else { return false }
            switch signal {
            case .trim: return gd.action == .trim
            case .liquidate: return gd.action == .liquidate
            case .accumulate: return gd.action == .accumulate
            case .aggressive: return gd.action == .aggressiveBuy
            }

        case .priceAndTime(let price, let days):
            return currentPrice >= price && daysHeld <= days

        // ADVANCED — Fiyat
        case .priceAboveEntry(let percent):
            return pnlPercent >= percent

        case .priceBelowEntry(let percent):
            return pnlPercent <= -percent

        // ADVANCED — Zaman
        case .maxHoldingDays(let days):
            return daysHeld >= days

        case .daysWithoutProgress(let days, let minGain):
            return daysHeld >= days && pnlPercent < minGain

        // ADVANCED — Stop-loss
        case .trailingStop(let pct):
            // peakPrice tepe değerden trailing stop hesabı.
            let peakPrice = max(highestPrice, entryPrice)
            let stopLevel = peakPrice * (1 - pct)
            return currentPrice < stopLevel

        case .atrMultiple(let multiplier):
            // Note: ATR henüz orionDetails'te yok; entryPrice * 0.03 placeholder
            let atr = entryPrice * 0.03
            let stopLevel = entryPrice - (atr * multiplier)
            return currentPrice < stopLevel

        case .entryAtrStop(let multiplier):
            let atr = entryPrice * 0.03
            let stopLevel = entryPrice - (atr * multiplier)
            return currentPrice < stopLevel

        case .rsiOverbought, .rsiOversold, .crossBelow, .crossAbove:
            switch trigger {
            case .rsiOverbought(let threshold):
                if let rsiValue = rsi { return rsiValue > threshold }
                return false

            case .rsiOversold(let threshold):
                if let rsiValue = rsi { return rsiValue < threshold }
                return false

            case .crossBelow(let indicator):
                return checkCross(trigger: .crossBelow(indicator: indicator), symbol: grandDecision?.symbol ?? "")

            case .crossAbove(let indicator):
                return checkCross(trigger: .crossAbove(indicator: indicator), symbol: grandDecision?.symbol ?? "")

            default: return false
            }

        case .councilActionChanged, .councilConfidenceDropped, .orionScoreDropped, .deltaExceeds:
            guard let gd = grandDecision else { return false }

            switch trigger {
            case .councilActionChanged(let from, let to):
                // Faz III (2026-05-12): Önceki uygulama "to" parametresini görmezden
                // geliyordu (`gd.action != from`). Bu yüzden balancedPlan'daki ardışık
                // iki trigger — trim ve liquidate — Council herhangi bir yöne kaydığında
                // hepsi tetikleniyordu. Sonuç: bir tick'te trim adımı (%30 azalt),
                // sonraki tick'te liquidate adımı (tamamını sat) ardışık fire ediyordu.
                // Doğru semantik: "Council ŞU ANDA spesifik hedef state'te ve giriş
                // state'inden farklı".
                return gd.action != from && gd.action == to

            case .councilConfidenceDropped:
                return false  // ileride implement

            case .orionScoreDropped:
                return false  // ileride implement

            case .deltaExceeds:
                return false  // ileride implement

            default: return false
            }

        case .earningsWithin(let days):
            let check = EventCalendarService.shared.hasEarningsWithin(symbol: grandDecision?.symbol ?? "", days: days)
            return check.hasEarnings

        case .marketModeChanged, .vixAbove, .vixBelow, .spyDropped:
            let currentRegime = ChironRegimeEngine.shared.globalResult.regime

            switch trigger {
            case .marketModeChanged(let mode):
                let modeMatched: Bool
                switch mode {
                case .greed, .extremeGreed:
                    modeMatched = currentRegime == .trend
                case .neutral, .complacency:
                    modeMatched = currentRegime == .neutral
                case .fear, .extremeFear, .panic:
                    modeMatched = currentRegime == .riskOff || currentRegime == .chop
                }
                return modeMatched

            case .vixAbove, .vixBelow, .spyDropped:
                return false  // ileride implement

            default: return false
            }

        default:
            return false
        }
    }

    private func checkCross(trigger: ActionTrigger, symbol: String) -> Bool {
        guard let candles = candleStore[symbol], candles.count >= 20 else { return false }

        let period: Int
        let isCrossAbove: Bool

        switch trigger {
        case .crossAbove(let ind):
            isCrossAbove = true
            if ind.lowercased().contains("sma") {
                let digits = ind.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                period = Int(digits) ?? 20
            } else {
                return false
            }

        case .crossBelow(let ind):
            isCrossAbove = false
            if ind.lowercased().contains("sma") {
                let digits = ind.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                period = Int(digits) ?? 20
            } else {
                return false
            }
        default: return false
        }

        guard candles.count > period + 1 else { return false }

        func getSMA(offset: Int) -> Double? {
            let endIndex = candles.count - 1 - offset
            let startIndex = endIndex - period + 1
            guard startIndex >= 0 else { return nil }

            let slice = candles[startIndex...endIndex]
            let sum = slice.reduce(0.0) { $0 + $1.close }
            return sum / Double(period)
        }

        guard let currentSMA = getSMA(offset: 0),
              let previousSMA = getSMA(offset: 1) else { return false }

        let currentPrice = candles.last!.close
        let previousPrice = candles[candles.count - 2].close

        if isCrossAbove {
            return previousPrice < previousSMA && currentPrice > currentSMA
        } else {
            return previousPrice > previousSMA && currentPrice < currentSMA
        }
    }

    // MARK: - Technical Helpers (createPlan içinde de kullanılır)

    /// Belirli periyot için basit hareketli ortalama. Yeterli candle yoksa nil.
    func movingAverage(from candles: [Candle], period: Int) -> Double? {
        guard candles.count >= period else { return nil }
        let slice = candles.suffix(period)
        let sum = slice.reduce(0.0) { $0 + $1.close }
        return sum / Double(period)
    }

    /// 14-bar ATR (Average True Range). Sadece son `period+1` mum kullanılır.
    func estimateATR(from candles: [Candle], period: Int = 14) -> Double? {
        guard candles.count >= (period + 1) else { return nil }
        let sample = Array(candles.suffix(period + 1))

        var trueRanges: [Double] = []
        for index in 1..<sample.count {
            let current = sample[index]
            let previousClose = sample[index - 1].close
            let trueRange = max(
                current.high - current.low,
                abs(current.high - previousClose),
                abs(current.low - previousClose)
            )
            trueRanges.append(trueRange)
        }

        guard !trueRanges.isEmpty else { return nil }
        return trueRanges.reduce(0, +) / Double(trueRanges.count)
    }

    /// Son `lookback` mumdan kaba destek/direnç (lokal min/max).
    func estimateSupportResistance(from candles: [Candle], lookback: Int = 40) -> (support: Double?, resistance: Double?) {
        guard !candles.isEmpty else { return (nil, nil) }
        let slice = candles.suffix(lookback)
        let support = slice.map(\.low).min()
        let resistance = slice.map(\.high).max()
        return (support, resistance)
    }

    /// SMA20/SMA50 sırasına göre trend yönü.
    func estimateTrend(from candles: [Candle], sma20: Double?, sma50: Double?) -> TrendDirection? {
        guard let lastClose = candles.last?.close else { return nil }
        guard let sma20, let sma50 else { return nil }

        if lastClose > sma20 && sma20 > sma50 { return .strongUp }
        if lastClose > sma20 { return .up }
        if lastClose < sma20 && sma20 < sma50 { return .strongDown }
        if lastClose < sma20 { return .down }
        return .sideways
    }
}
