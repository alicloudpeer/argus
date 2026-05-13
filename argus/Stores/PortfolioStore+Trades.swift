import Foundation

// MARK: - Trade Execution (buy / sell / trim / updateStops)
/// PortfolioStore'un asıl iş yükü: pozisyon açma, kapatma, kısmi satış, SL/TP düzenleme.
/// FIFO yaklaşımı, balance kontrolü, commission hesabı, ChironLearning + Council
/// + TradeBrain + Alkindus + RAG cascade'i sell()'de tetiklenir.
extension PortfolioStore {

    // MARK: - Buy

    @discardableResult
    func buy(
        symbol: String,
        quantity: Double,
        price: Double,
        source: TradeSource = .user,
        engine: AutoPilotEngine? = nil,
        stopLoss: Double? = nil,
        takeProfit: Double? = nil,
        rationale: String? = nil,
        orionSnapshot: OrionComponentSnapshot? = nil
    ) -> Trade? {
        guard quantity > 0, price > 0 else { return nil }

        let isBist = isBistSymbol(symbol)
        let currency: Currency = isBist ? .TRY : .USD
        let cost = quantity * price
        let commission = FeeModel.forSymbol(symbol).calculate(amount: cost)
        let totalCost = cost + commission

        // Balance Check
        if isBist {
            guard bistBalance >= totalCost else {
                print("❌ PortfolioEngine: Yetersiz BIST bakiyesi (₺\(bistBalance) < ₺\(totalCost))")
                return nil
            }
            bistBalance -= totalCost
        } else {
            guard globalBalance >= totalCost else {
                print("❌ PortfolioEngine: Yetersiz USD bakiyesi ($\(globalBalance) < $\(totalCost))")
                return nil
            }
            globalBalance -= totalCost
        }

        // Create Trade
        var trade = Trade(
            symbol: symbol,
            entryPrice: price,
            quantity: quantity,
            entryDate: Date(),
            isOpen: true,
            source: source,
            engine: engine,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            rationale: rationale,
            currency: currency
        )
        trade.entryOrionSnapshot = orionSnapshot
        // Y4: Giriş komisyonunun adet bazında payı. Kısmi satışta prorate edilir.
        // quantity > 0 `guard` üstte sağlandığı için bölme güvenli.
        trade.entryCommissionPerShare = commission / quantity

        trades.append(trade)

        // Log Transaction
        let transaction = Transaction(
            id: UUID(),
            type: .buy,
            symbol: symbol,
            amount: cost,
            price: price,
            date: Date(),
            fee: commission
        )
        transactions.insert(transaction, at: 0)

        saveToDisk()

        let currencySymbol = isBist ? "₺" : "$"
        print("✅ PortfolioEngine: BUY \(symbol) x\(quantity) @ \(currencySymbol)\(price)")
        return trade
    }

    // MARK: - Ledger Link (Faz 0 Task 2)

    /// ExecutionGovernor.didExecute → ArgusLedger.openTrade zinciri sonrası dönen
    /// ledger UUID'sini ilgili Trade'e yansıtır. Satım anında ArgusLedger.closeTrade
    /// bu UUID üzerinden ledger satırını kapatır — Decision↔Trade↔Outcome UUID
    /// zincirinin kapanış halkası.
    ///
    /// - Returns: Eşleşen trade bulunduysa `true`, bulunmadıysa `false`.
    @discardableResult
    func updateLedgerId(tradeId: UUID, ledgerId: UUID) -> Bool {
        guard let index = trades.firstIndex(where: { $0.id == tradeId }) else {
            ArgusLogger.warning(.portfoy, "updateLedgerId: trade bulunamadı id=\(tradeId)")
            return false
        }
        var trade = trades[index]
        trade.ledgerTradeId = ledgerId
        trades[index] = trade
        saveToDisk()
        return true
    }

    // MARK: - Sell (Full Close)

    @discardableResult
    func sell(tradeId: UUID, currentPrice: Double, reason: String? = nil) -> Double? {
        guard let index = trades.firstIndex(where: { $0.id == tradeId && $0.isOpen }) else {
            print("❌ PortfolioEngine: Trade bulunamadı: \(tradeId)")
            return nil
        }

        var trade = trades[index]
        let isBist = trade.currency == .TRY
        let revenue = trade.quantity * currentPrice
        let commission = FeeModel.forSymbol(trade.symbol).calculate(amount: revenue)
        let netRevenue = revenue - commission
        // Y4: Giriş komisyonunun bu satışa düşen payı PnL'den düşülür.
        let entryCommissionShare = trade.entryCommissionPerShare * trade.quantity
        let pnl = (currentPrice - trade.entryPrice) * trade.quantity - commission - entryCommissionShare

        // Add to balance
        if isBist {
            bistBalance += netRevenue
        } else {
            globalBalance += netRevenue
        }

        // Close trade
        trade.isOpen = false
        trade.exitPrice = currentPrice
        trade.exitDate = Date()
        trades[index] = trade

        // Log for Chiron Learning
        let tradeLog = TradeLog(
            date: Date(),
            symbol: trade.symbol,
            entryPrice: trade.entryPrice,
            exitPrice: currentPrice,
            pnlPercent: trade.profitPercentage,
            pnlAbsolute: pnl,
            entryRegime: ChironRegimeEngine.shared.globalResult.regime,
            entryOrionScore: trade.entryOrionSnapshot?.momentumScore ?? 0,
            entryAtlasScore: 0,
            entryAetherScore: 0,
            engine: trade.engine?.rawValue ?? "MANUAL",
            entryOrionSnapshot: trade.entryOrionSnapshot,
            exitOrionSnapshot: nil
        )
        TradeLogStore.shared.append(tradeLog)

        // Faz 0 Task 2: ArgusLedger trades tablosundaki satırı kapat (sync, Task.detached
        // dışında — deterministik trade lifecycle). closeTrade kendi queue.sync ile thread
        // safety sağlar. ledgerTradeId nil ise Task 1 öncesi açılmış (legacy) trade — log.
        if let ledgerId = trade.ledgerTradeId {
            ArgusLedger.shared.closeTrade(tradeId: ledgerId, exitPrice: currentPrice)
        } else {
            ArgusLogger.warning(.portfoy, "Trade \(trade.symbol) kapatılıyor ama ledgerTradeId yok — Task 1 öncesi açılmış olabilir")
        }

        // Öğrenme sistemlerine geri besleme — trade kapanınca hepsini tetikle
        let _symbol           = trade.symbol
        let _pnlAbsolute      = pnl
        let _pnlPercent       = trade.profitPercentage
        let _entryPrice       = trade.entryPrice
        let _exitPrice        = currentPrice
        let _entryDate        = trade.entryDate
        let _holdingDays      = Calendar.current.dateComponents([.day], from: trade.entryDate, to: Date()).day ?? 0
        let _engine           = trade.engine ?? .manual
        let _entryOrionScore  = trade.entryOrionSnapshot?.momentumScore
        let _exitReason       = reason ?? "MANUAL"

        Task.detached(priority: .background) {
            // 1a. Chiron öğrenmesi — ağırlık optimizasyonu
            let outcome: ChironLearningSystem.TradeExperience.TradeOutcome
            if _pnlAbsolute > 0      { outcome = .winner }
            else if _pnlAbsolute < 0 { outcome = .loser }
            else                     { outcome = .scratch }

            let weights = await ChironLearningSystem.shared.getCurrentState().weights
            await ChironLearningSystem.shared.recordTrade(
                symbol:        _symbol,
                weights:       weights,
                outcome:       outcome,
                duration:      Date().timeIntervalSince(_entryDate),
                profitPercent: _pnlPercent
            )

            // 1c. ChironDataLakeService — TradeOutcomeRecord ile öğrenme havuzu beslemesi.
            // ChironLearningJob.analyzeSymbol() bu havuzdan okuyarak ağırlıkları günceller.
            // Eski sürümde sadece PaperBroker ve backtest DataLake'e yazıyordu; gerçek
            // trade'ler "kayıp veri" idi → 5 trade minimum'a ulaşılmadığı için
            // analyzeSymbol early-return yapıyor, hiç öğrenme tetiklenmiyordu.
            let dataLakeRecord = TradeOutcomeRecord(
                symbol: _symbol,
                engine: _engine,
                entryDate: _entryDate,
                exitDate: Date(),
                entryPrice: _entryPrice,
                exitPrice: _exitPrice,
                pnlPercent: _pnlPercent,
                exitReason: _exitReason,
                orionScoreAtEntry: _entryOrionScore,
                regime: ChironRegimeEngine.shared.globalResult.regime
            )
            await ChironDataLakeService.shared.logTrade(dataLakeRecord)

            // 1b. ChironCouncilLearningService — feedback loop'un KAPANIŞ adımı.
            // Eski sürümde bu çağrı yoktu; pending CouncilVotingRecord'lar sonsuza dek
            // kuyrukta kalıp completedRecords hiç büyümüyordu.
            let councilOutcome: ChironTradeOutcome = _pnlAbsolute >= 0 ? .win : .loss
            await ChironCouncilLearningService.shared.updateOutcome(
                symbol:     _symbol,
                outcome:    councilOutcome,
                pnlPercent: _pnlPercent
            )

            // 2. TradeBrain öğrenmesi
            await AutoPilotStore.shared.triggerLearningForClosedTrade(
                symbol:      _symbol,
                entryPrice:  _entryPrice,
                exitPrice:   _exitPrice,
                holdingDays: _holdingDays
            )

            // 3. Alkindus olgunlaşma — yeni veri geldi, bekleyen kararları değerlendir
            await AlkindusCalibrationEngine.shared.periodicMatureCheck()

            // 4. RAG — tamamlanan trade'i vektör hafızasına kaydet
            await AlkindusRAGEngine.shared.syncChironTrade(
                id: UUID().uuidString,
                symbol: _symbol,
                engine: "PORTFOLIO",
                entryPrice: _entryPrice,
                exitPrice: _exitPrice,
                pnlPercent: _pnlPercent,
                holdingDays: _holdingDays,
                orionScore: nil,
                atlasScore: nil,
                regime: ChironRegimeEngine.shared.globalResult.regime.rawValue
            )
        }

        // Log Transaction
        var transaction = Transaction(
            id: UUID(),
            type: .sell,
            symbol: trade.symbol,
            amount: revenue,
            price: currentPrice,
            date: Date(),
            fee: commission,
            pnl: pnl,
            pnlPercent: trade.profitPercentage
        )
        transaction.reasonCode = reason
        transactions.insert(transaction, at: 0)

        saveToDisk()

        let currencySymbol = isBist ? "₺" : "$"
        print("✅ PortfolioEngine: SELL \(trade.symbol) @ \(currencySymbol)\(currentPrice), PnL: \(currencySymbol)\(String(format: "%.2f", pnl))")
        return pnl
    }

    // MARK: - Update Stops (SL / TP)

    /// Açık bir pozisyonun stop-loss ve/veya take-profit değerlerini SSoT üzerinde günceller.
    /// ViewModel'lerin kendi `portfolio[index].stopLoss = ...` ataması yapması YASAK —
    /// o atama Combine tick'inde bu store'un yayımladığı değerle ezilir ve koruma
    /// eski seviyede kalır. Trailing stop ve plan sıkılaştırma çağrıları buraya gelmeli.
    @discardableResult
    func updateStops(tradeId: UUID, newStop: Double? = nil, newTakeProfit: Double? = nil) -> Bool {
        guard newStop != nil || newTakeProfit != nil else { return false }
        guard let index = trades.firstIndex(where: { $0.id == tradeId && $0.isOpen }) else {
            return false
        }
        var trade = trades[index]
        if let s = newStop { trade.stopLoss = s }
        if let tp = newTakeProfit { trade.takeProfit = tp }
        trades[index] = trade
        scheduleDebouncedSave()
        return true
    }

    /// Trade'e Argus Voice raporunu ekler ve persist eder.
    @discardableResult
    func attachVoiceReport(tradeId: UUID, report: String) -> Bool {
        guard let index = trades.firstIndex(where: { $0.id == tradeId }) else {
            return false
        }
        var trade = trades[index]
        trade.voiceReport = report
        trades[index] = trade
        scheduleDebouncedSave()
        return true
    }

    // MARK: - Partial Sell (Trim)

    @discardableResult
    func trim(tradeId: UUID, percentage: Double, currentPrice: Double, reason: String? = nil) -> Double? {
        guard percentage > 0, percentage < 100 else { return nil }
        guard let index = trades.firstIndex(where: { $0.id == tradeId && $0.isOpen }) else { return nil }

        var trade = trades[index]
        let sellQuantity = trade.quantity * (percentage / 100.0)
        let remainingQuantity = trade.quantity - sellQuantity

        let isBist = trade.currency == .TRY
        let revenue = sellQuantity * currentPrice
        let commission = FeeModel.forSymbol(trade.symbol).calculate(amount: revenue)
        let netRevenue = revenue - commission
        // Y4: Giriş komisyonunu bu parça kadar prorate et.
        let entryCommissionShare = trade.entryCommissionPerShare * sellQuantity
        let pnl = (currentPrice - trade.entryPrice) * sellQuantity - commission - entryCommissionShare

        // Add to balance
        if isBist {
            bistBalance += netRevenue
        } else {
            globalBalance += netRevenue
        }

        // Update trade quantity
        trade.quantity = remainingQuantity
        trades[index] = trade

        // Log Transaction
        var transaction = Transaction(
            id: UUID(),
            type: .sell,
            symbol: trade.symbol,
            amount: revenue,
            price: currentPrice,
            date: Date(),
            fee: commission,
            pnl: pnl,
            pnlPercent: ((currentPrice - trade.entryPrice) / trade.entryPrice) * 100
        )
        transaction.reasonCode = "TRIM_\(Int(percentage))%"
        transactions.insert(transaction, at: 0)

        saveToDisk()

        print("✅ PortfolioEngine: TRIM \(trade.symbol) \(Int(percentage))% @ \(currentPrice)")
        return pnl
    }

    /// Quantity tabanlı kısmi satış. Plan execution'daki `sellPartial` bu rota üzerinden geçer.
    /// - Parameters:
    ///   - tradeId: Kapatılacak trade.
    ///   - quantity: Satılacak adet. Açık quantity'yi geçerse `nil` döner.
    ///   - currentPrice: Mevcut piyasa fiyatı.
    ///   - reason: Log/Transaction reasonCode.
    /// - Returns: Realize PnL (commission sonrası). Trade kapanırsa `isOpen=false` set edilir.
    @discardableResult
    func trimByQuantity(tradeId: UUID, quantity: Double, currentPrice: Double, reason: String? = nil) -> Double? {
        guard quantity > 0 else { return nil }
        guard let index = trades.firstIndex(where: { $0.id == tradeId && $0.isOpen }) else { return nil }

        var trade = trades[index]
        // Floating point toleransı: 0.0001 adet altında "tam kapatma" sayılır.
        guard quantity <= trade.quantity + 0.0001 else { return nil }

        let isBist = trade.currency == .TRY
        let revenue = quantity * currentPrice
        let commission = FeeModel.forSymbol(trade.symbol).calculate(amount: revenue)
        let netRevenue = revenue - commission
        // Y4: Giriş komisyonunun bu adede düşen payı.
        let entryCommissionShare = trade.entryCommissionPerShare * quantity
        let pnl = (currentPrice - trade.entryPrice) * quantity - commission - entryCommissionShare
        let pnlPct = trade.entryPrice > 0
            ? ((currentPrice - trade.entryPrice) / trade.entryPrice) * 100
            : 0.0

        // Bakiye güncelle
        if isBist {
            bistBalance += netRevenue
        } else {
            globalBalance += netRevenue
        }

        // Trade quantity düş; kalan ≤ 0.0001 ise trade'i kapat
        trade.quantity -= quantity
        if trade.quantity <= 0.0001 {
            trade.quantity = 0
            trade.isOpen = false
            trade.exitPrice = currentPrice
            trade.exitDate = Date()
        }
        trades[index] = trade

        // Transaction log
        var transaction = Transaction(
            id: UUID(),
            type: .sell,
            symbol: trade.symbol,
            amount: revenue,
            price: currentPrice,
            date: Date(),
            fee: commission,
            pnl: pnl,
            pnlPercent: pnlPct
        )
        transaction.reasonCode = reason ?? "TRIM_QTY"
        transactions.insert(transaction, at: 0)

        saveToDisk()

        let currencySymbol = isBist ? "₺" : "$"
        print("✅ PortfolioEngine: TRIM-QTY \(trade.symbol) \(String(format: "%.4f", quantity))@ \(currencySymbol)\(currentPrice), PnL: \(currencySymbol)\(String(format: "%.2f", pnl))")
        return pnl
    }
}
