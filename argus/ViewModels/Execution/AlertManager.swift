import Foundation
import Combine

/// Trade Brain alert pipeline + buy/sell core execution + cooldown yönetimi.
/// God Object Aşama A — ExecutionStateViewModel'den çıkarıldı (en büyük parça).
///
/// Cross-coupling:
/// - ExecutionLogger.shared.lastTradeError / lastTradeTimes → buy/sell yazar
/// - ScanOrchestrator.shared.addAgoraSnapshot → AGORA blok'unda çağırır
@MainActor
final class AlertManager: ObservableObject {
    static let shared = AlertManager()

    /// Trade Brain alerts (capped at 50).
    @Published var planAlerts: [TradeBrainAlert] = []

    /// Cooldown tracking — symbol → next allowed trade time.
    @Published var tradeCooldowns: [String: Date] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupTradeBrainObservers()
    }

    // MARK: - Trade Brain Observers

    private func setupTradeBrainObservers() {
        NotificationCenter.default.publisher(for: .tradeBrainAlert)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.userInfo?["alert"] as? TradeBrainAlert }
            .sink { [weak self] alert in
                self?.planAlerts.append(alert)
                if (self?.planAlerts.count ?? 0) > 50 {
                    self?.planAlerts.removeFirst()
                }
            }
            .store(in: &cancellables)

        // tradeBrainBuyOrder / tradeBrainSellOrder observers kaldirildi.
        // Artik TradeBrainExecutor dogrudan executeBuy()/executeSell() cagiriyor.
    }

    // handleTradeBrainBuy / handleTradeBrainSell kaldirildi.
    // Artik executeBuy() / executeSell() public API'si kullaniliyor.

    // MARK: - Direct Execution API (replaces NotificationCenter fire-and-forget)

    /// TradeBrainExecutor'dan dogrudan cagrilir. Alim yapar, plan olusturur, sonucu doner.
    @discardableResult
    func executeBuy(
        symbol: String,
        quantity: Double,
        price: Double,
        rationale: String,
        stopLoss: Double?,
        takeProfit: Double?,
        decision: ArgusGrandDecision?
    ) -> Trade? {
        guard let trade = self.buy(
            symbol: symbol,
            quantity: quantity,
            source: .autoPilot,
            engine: .pulse,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            rationale: rationale,
            referencePrice: price
        ) else {
            let reason = ExecutionLogger.shared.lastTradeError ?? "bilinmeyen sebep"
            ArgusLogger.error("TRADE BRAIN ALIM RED: \(symbol) → \(reason)", category: "EXECUTION")
            return nil
        }

        if let decision = decision ?? SignalStateViewModel.shared.grandDecisions[symbol] {
            _ = PositionPlanStore.shared.createPlan(for: trade, decision: decision)
            ArgusLogger.info("Trade Brain Plan oluşturuldu: \(symbol)", category: "EXECUTION")
        } else {
            ArgusLogger.warn("Trade Brain Plan atlandı (karar yok): \(symbol)", category: "EXECUTION")
        }

        ArgusLogger.info("TRADE BRAIN ALIM: \(symbol) - \(String(format: "%.4f", quantity)) adet @ \(String(format: "%.2f", price))", category: "EXECUTION")
        return trade
    }

    /// TradeBrainExecutor'dan dogrudan cagrilir. Satim/trim yapar.
    func executeSell(
        tradeId: UUID,
        price: Double,
        reason: String,
        trimPercentage: Double? = nil
    ) {
        guard let trade = PortfolioStore.shared.trades.first(where: { $0.id == tradeId }) else {
            ArgusLogger.error("TRADE BRAIN SATIŞ: trade bulunamadı (id=\(tradeId))", category: "EXECUTION")
            return
        }

        if let trim = trimPercentage, trim > 0, trim < 100 {
            let quantity = trade.quantity * (trim / 100.0)
            self.sell(symbol: trade.symbol, quantity: quantity, source: .autoPilot, reason: reason)
            ArgusLogger.info("TRADE BRAIN SATIŞ(TRIM): \(trade.symbol) %\(Int(trim)) - \(reason)", category: "EXECUTION")
        } else {
            self.sell(symbol: trade.symbol, quantity: trade.quantity, source: .autoPilot, reason: reason)
            ArgusLogger.info("TRADE BRAIN SATIŞ: \(trade.symbol) - \(reason)", category: "EXECUTION")
        }
    }

    // MARK: - Cooldown Management

    func isInCooldown(symbol: String) -> Bool {
        guard let cooldownEnd = tradeCooldowns[symbol] else { return false }
        return Date() < cooldownEnd
    }

    func setCooldown(symbol: String, duration: TimeInterval) {
        tradeCooldowns[symbol] = Date().addingTimeInterval(duration)
    }

    func clearCooldown(symbol: String) {
        tradeCooldowns.removeValue(forKey: symbol)
    }

    func remainingCooldown(symbol: String) -> TimeInterval? {
        guard let cooldownEnd = tradeCooldowns[symbol] else { return nil }
        let remaining = cooldownEnd.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Execution Core (buy / sell)

    @discardableResult
    func buy(symbol: String, quantity: Double, source: TradeSource = .user, engine: AutoPilotEngine? = nil, stopLoss: Double? = nil, takeProfit: Double? = nil, rationale: String? = nil, decisionTrace: DecisionTraceSnapshot? = nil, marketSnapshot: MarketSnapshot? = nil, referencePrice: Double? = nil) -> Trade? {

        let isBist = SymbolResolver.shared.isBistSymbol(symbol)

        ExecutionLogger.shared.lastTradeError = nil
        let price: Double
        if let quote = MarketDataStore.shared.getQuote(for: symbol), quote.currentPrice > 0 {
            price = quote.currentPrice
        } else if let ref = referencePrice, ref > 0 {
            price = ref
            ArgusLogger.warning(.portfoy, "Canli quote yok, referencePrice kullanildi: \(symbol)")
        } else {
            let err = "Fiyat verisi bulunamadi: \(symbol)"
            ExecutionLogger.shared.lastTradeError = err
            ArgusLogger.error(.portfoy, err)
            ArgusLogger.error("TRADE BLOCKED: \(err)", category: "EXECUTION")
            return nil
        }

        let availableBalance = (isBist ? PortfolioStore.shared.bistBalance : PortfolioStore.shared.globalBalance)

        let validation = TradeValidator.validateBuy(
            symbol: symbol,
            quantity: quantity,
            price: price,
            availableBalance: availableBalance,
            isBistMarketOpen: MarketStatusService.shared.canTrade(for: .bist),
            isGlobalMarketOpen: MarketStatusService.shared.canTrade(for: .global)
        )

        guard validation.isValid else {
            let error = validation.error?.localizedDescription ?? "Bilinmeyen hata"
            ExecutionLogger.shared.lastTradeError = error
            ArgusLogger.error(.portfoy, "İŞLEM REDDEDİLDİ: \(error)")
            ArgusLogger.error("TRADE BLOCKED (Validation): \(error) | Balance: \(availableBalance) | Price: \(price) | Qty: \(quantity)", category: "EXECUTION")
            return nil
        }

        if let decision = SignalStateViewModel.shared.argusDecisions[symbol] {
            let snapshot = AgoraExecutionGovernor.shared.audit(
                decision: decision,
                currentPrice: price,
                portfolio: PortfolioStore.shared.trades,
                lastTradeTime: ExecutionLogger.shared.lastTradeTimes[symbol],
                lastActionPrice: nil
            )

            if snapshot.locks.isLocked {
                let err = "AGORA engelledi: \(snapshot.reasonOneLiner)"
                ExecutionLogger.shared.lastTradeError = err
                ArgusLogger.warning(.autopilot, "AGORA BLOCKED BUY: \(snapshot.reasonOneLiner)")
                ArgusLogger.error("TRADE BLOCKED (AGORA): \(err)", category: "EXECUTION")
                ScanOrchestrator.shared.addAgoraSnapshot(snapshot)
                return nil
            }
        } else {
            ArgusLogger.warning(.autopilot, "AGORA: \(symbol) için Council kararı bulunamadı — governor atlandı")
        }

        if let trade = PortfolioStore.shared.buy(
            symbol: symbol,
            quantity: quantity,
            price: price,
            source: source,
            engine: engine,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            rationale: rationale
        ) {
            ExecutionLogger.shared.lastTradeTimes[symbol] = Date()

            let snapshots = ScanOrchestrator.shared.agoraSnapshots
            if !snapshots.isEmpty, let snapshot = snapshots.first {
                Task {
                    let _ = await ArgusVoiceService.shared.generateReport(from: snapshot)
                }
            }

            return trade
        }

        return nil
    }

    func sell(symbol: String, quantity: Double, source: TradeSource = .user, engine: AutoPilotEngine? = nil, reason: String? = nil, referencePrice: Double? = nil) {
        ExecutionLogger.shared.lastTradeError = nil

        let price: Double
        if let quote = MarketDataStore.shared.getQuote(for: symbol), quote.currentPrice > 0 {
            price = quote.currentPrice
        } else if let ref = referencePrice, ref > 0 {
            price = ref
        } else {
            let err = "Fiyat verisi bulunamadi: \(symbol)"
            ExecutionLogger.shared.lastTradeError = err
            ArgusLogger.error(.portfoy, err)
            ArgusLogger.error("SELL BLOCKED: \(err)", category: "EXECUTION")
            return
        }

        let openTrades = PortfolioStore.shared.trades.filter { $0.symbol == symbol && $0.isOpen }
        let totalOwned = openTrades.reduce(0.0) { $0 + $1.quantity }

        let validation = TradeValidator.validateSell(
            symbol: symbol,
            quantity: quantity,
            ownedQuantity: totalOwned,
            isBistMarketOpen: MarketStatusService.shared.canTrade(for: .bist),
            isGlobalMarketOpen: MarketStatusService.shared.canTrade(for: .global)
        )

        guard validation.isValid else {
            let error = validation.error?.localizedDescription ?? "Bilinmeyen hata"
            ExecutionLogger.shared.lastTradeError = error
            ArgusLogger.error(.portfoy, "SATIŞ REDDEDİLDİ: \(error)")
            ArgusLogger.error("SELL BLOCKED (Validation): \(error)", category: "EXECUTION")
            return
        }

        if let decision = SignalStateViewModel.shared.argusDecisions[symbol] {
            let snapshot = AgoraExecutionGovernor.shared.audit(
                decision: decision,
                currentPrice: price,
                portfolio: PortfolioStore.shared.trades,
                lastTradeTime: ExecutionLogger.shared.lastTradeTimes[symbol],
                lastActionPrice: nil
            )

            if snapshot.locks.isLocked {
                let err = "AGORA engelledi: \(snapshot.reasonOneLiner)"
                ExecutionLogger.shared.lastTradeError = err
                ArgusLogger.warning(.autopilot, "AGORA BLOCKED SELL: \(snapshot.reasonOneLiner)")
                ArgusLogger.error("SELL BLOCKED (AGORA): \(err)", category: "EXECUTION")
                ScanOrchestrator.shared.addAgoraSnapshot(snapshot)
                return
            }
        } else {
            ArgusLogger.warning(.autopilot, "AGORA: \(symbol) için Council kararı bulunamadı — governor atlandı")
        }

        // FIFO Close Logic
        var remainingToSell = quantity
        var didSellAny = false
        let sortedTrades = openTrades.sorted { $0.entryDate < $1.entryDate }

        for trade in sortedTrades {
            if remainingToSell <= 0.000001 { break }
            let tradeQty = trade.quantity
            let closeQty = min(tradeQty, remainingToSell)

            if closeQty >= tradeQty {
                let pnl = PortfolioStore.shared.sell(tradeId: trade.id, currentPrice: price, reason: reason)
                if pnl != nil {
                    didSellAny = true
                    remainingToSell -= tradeQty
                }
            } else {
                let percentage = (closeQty / tradeQty) * 100.0
                let pnl = PortfolioStore.shared.trim(tradeId: trade.id, percentage: percentage, currentPrice: price, reason: reason)
                if pnl != nil {
                    didSellAny = true
                    remainingToSell -= closeQty
                }
            }
        }

        if didSellAny {
            ExecutionLogger.shared.lastTradeTimes[symbol] = Date()
            ArgusLogger.info(.portfoy, "Satıldı: \(quantity)x \(symbol) @ \(price)")
        }
    }
}
