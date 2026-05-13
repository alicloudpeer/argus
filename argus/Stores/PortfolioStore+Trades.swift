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

    /// Senkron `sell()` — UI button tap'leri, QuoteHandler subscription tick'leri
    /// gibi sync caller'lar için. State mutation tamamlanmış olarak döner; öğrenme
    /// cascade'i `Task { }` ile fire-and-forget tetiklenir (caller bloklanmaz,
    /// learning chain arka planda devam eder).
    ///
    /// Caller learning chain tamamlanmasını beklemek istiyorsa `sellAsync` kullanmalı.
    @discardableResult
    func sell(tradeId: UUID, currentPrice: Double, reason: String? = nil) -> Double? {
        guard let snapshot = applySellStateMutation(
            tradeId: tradeId,
            currentPrice: currentPrice,
            reason: reason
        ) else { return nil }

        // Fire-and-forget — sync caller bloklanmaz. Task 7: önceki `Task.detached`
        // davranışıyla uyumlu, learning chain arka planda await sırasıyla çalışır.
        Task { [weak self] in
            await self?.feedLearningSystems(snapshot: snapshot)
        }
        return snapshot.pnl
    }

    /// Async `sell()` — deterministik öğrenme zinciri tamamlanmasına ihtiyaç duyan
    /// caller'lar için. Dönüş anında ChironLearning + ChironDataLake + Council
    /// learning + TradeBrain + Alkindus + RAG cascade'i await edilmiş olur.
    ///
    /// Test kullanımı: side-effect (örn. ChironDataLake.loadTradeHistory) `await
    /// sellAsync(...)` sonrası senkron sorgulanabilir, flaky değil.
    @discardableResult
    func sellAsync(tradeId: UUID, currentPrice: Double, reason: String? = nil) async -> Double? {
        guard let snapshot = applySellStateMutation(
            tradeId: tradeId,
            currentPrice: currentPrice,
            reason: reason
        ) else { return nil }

        await feedLearningSystems(snapshot: snapshot)
        return snapshot.pnl
    }

    // MARK: - Sell Internals (Task 7 refactor)

    /// `sell()` ve `sellAsync()` tarafından paylaşılan state mutation payload'ı.
    /// `feedLearningSystems(...)` bu snapshot'tan tüm cascade çağrılarını yapar
    /// — böylece sync ve async sell aynı argüman yüzeyini taşır, divergence riski yok.
    struct SellSnapshot {
        let symbol: String
        let pnl: Double
        let pnlPercent: Double
        let entryPrice: Double
        let exitPrice: Double
        let entryDate: Date
        let holdingDays: Int
        let engine: AutoPilotEngine
        let entryOrionScore: Double?
        let exitReason: String
    }

    /// State mutation + transaction log + ledger close (sync). Cascade tetiklenmez —
    /// onu `feedLearningSystems(snapshot:)` yapar. Trade bulunamazsa `nil`.
    private func applySellStateMutation(
        tradeId: UUID,
        currentPrice: Double,
        reason: String?
    ) -> SellSnapshot? {
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

        return SellSnapshot(
            symbol: trade.symbol,
            pnl: pnl,
            pnlPercent: trade.profitPercentage,
            entryPrice: trade.entryPrice,
            exitPrice: currentPrice,
            entryDate: trade.entryDate,
            holdingDays: Calendar.current.dateComponents([.day], from: trade.entryDate, to: Date()).day ?? 0,
            engine: trade.engine ?? .manual,
            entryOrionScore: trade.entryOrionSnapshot?.momentumScore,
            exitReason: reason ?? "MANUAL"
        )
    }

    /// Tüm öğrenme sistemlerine geri besleme — Chiron weights + DataLake + Council +
    /// TradeBrain + Alkindus calibration + RAG. Sırası önemli: önce kayıt (DataLake),
    /// sonra outcome update'leri, en sonda RAG sync. `sell()` ve `sellAsync()` tarafından
    /// paylaşılır. Sync sell `Task { }` ile fire-and-forget çağırır, async sell `await` eder.
    func feedLearningSystems(snapshot: SellSnapshot) async {
        // 1a. Chiron öğrenmesi — ağırlık optimizasyonu
        let outcome: ChironLearningSystem.TradeExperience.TradeOutcome
        if snapshot.pnl > 0      { outcome = .winner }
        else if snapshot.pnl < 0 { outcome = .loser }
        else                     { outcome = .scratch }

        let weights = await ChironLearningSystem.shared.getCurrentState().weights
        await ChironLearningSystem.shared.recordTrade(
            symbol:        snapshot.symbol,
            weights:       weights,
            outcome:       outcome,
            duration:      Date().timeIntervalSince(snapshot.entryDate),
            profitPercent: snapshot.pnlPercent
        )

        // 1c. ChironDataLakeService — TradeOutcomeRecord ile öğrenme havuzu beslemesi.
        // ChironLearningJob.analyzeSymbol() bu havuzdan okuyarak ağırlıkları günceller.
        // Eski sürümde sadece PaperBroker ve backtest DataLake'e yazıyordu; gerçek
        // trade'ler "kayıp veri" idi → 5 trade minimum'a ulaşılmadığı için
        // analyzeSymbol early-return yapıyor, hiç öğrenme tetiklenmiyordu.
        let dataLakeRecord = TradeOutcomeRecord(
            symbol: snapshot.symbol,
            engine: snapshot.engine,
            entryDate: snapshot.entryDate,
            exitDate: Date(),
            entryPrice: snapshot.entryPrice,
            exitPrice: snapshot.exitPrice,
            pnlPercent: snapshot.pnlPercent,
            exitReason: snapshot.exitReason,
            orionScoreAtEntry: snapshot.entryOrionScore,
            regime: ChironRegimeEngine.shared.globalResult.regime
        )
        await ChironDataLakeService.shared.logTrade(dataLakeRecord)

        // 1b. ChironCouncilLearningService — feedback loop'un KAPANIŞ adımı.
        // Eski sürümde bu çağrı yoktu; pending CouncilVotingRecord'lar sonsuza dek
        // kuyrukta kalıp completedRecords hiç büyümüyordu.
        let councilOutcome: ChironTradeOutcome = snapshot.pnl >= 0 ? .win : .loss
        await ChironCouncilLearningService.shared.updateOutcome(
            symbol:     snapshot.symbol,
            outcome:    councilOutcome,
            pnlPercent: snapshot.pnlPercent
        )

        // 2. TradeBrain öğrenmesi
        await AutoPilotStore.shared.triggerLearningForClosedTrade(
            symbol:      snapshot.symbol,
            entryPrice:  snapshot.entryPrice,
            exitPrice:   snapshot.exitPrice,
            holdingDays: snapshot.holdingDays
        )

        // 3. Alkindus olgunlaşma — yeni veri geldi, bekleyen kararları değerlendir
        await AlkindusCalibrationEngine.shared.periodicMatureCheck()

        // 4. RAG — tamamlanan trade'i vektör hafızasına kaydet
        await AlkindusRAGEngine.shared.syncChironTrade(
            id: UUID().uuidString,
            symbol: snapshot.symbol,
            engine: "PORTFOLIO",
            entryPrice: snapshot.entryPrice,
            exitPrice: snapshot.exitPrice,
            pnlPercent: snapshot.pnlPercent,
            holdingDays: snapshot.holdingDays,
            orionScore: nil,
            atlasScore: nil,
            regime: ChironRegimeEngine.shared.globalResult.regime.rawValue
        )
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
