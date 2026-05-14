import Foundation

// MARK: - Scan + Signal Processing + Plan Triggers
/// AutoPilotStore'un asıl iş yükü: market tarama, sinyal işleme, karar alma,
/// trade execution, plan trigger değerlendirme.
extension AutoPilotStore {

    // MARK: - Core Execution Loop

    func runAutoPilot() async {
        print("🚨🚨🚨 runAutoPilot ENTERED — enabled=\(isAutoPilotEnabled)")
        guard isAutoPilotEnabled else {
            print("🚨 runAutoPilot ATLANDI — Otopilot kapalı")
            return
        }

        ArgusLogger.info("AutoPilotStore: runAutoPilot başlatılıyor...", category: "OTOPİLOT")
        ArgusLogger.warn("🚨 runAutoPilot TRIGGERED @ \(Date())", category: "OTOPİLOT")

        // Günlük öğrenme döngüsü — market kapalıyken de çalışır (geçmiş veri işleme).
        let needsLearning: Bool = {
            guard let last = lastDailyLearningRunAt else { return true }
            return Date().timeIntervalSince(last) >= (24 * 3600)
        }()
        if needsLearning {
            Task.detached(priority: .background) { [weak self] in
                await self?.runDailyLearningCycle()
                await MainActor.run { self?.lastDailyLearningRunAt = Date() }
            }
        }

        // T3.3: Market kapalıysa tarama yapma — API çağrıları ve pil tasarrufu.
        if !MarketSessionManager.shared.isMarketOpen() {
            ArgusLogger.info("AutoPilotStore: Market kapalı — scan atlanıyor", category: "OTOPİLOT")
            return
        }

        // 2026-05-05 FIX A: Yeni scan turunda eski execution RED'lerini temizle.
        await TradeBrainExecutionTracker.shared.clearForNewScan()

        // T3.5: Sektör batch optimizasyonu — scan başında Demeter (sektör bazlı)
        // ve makro snapshot'ı bir kez ısıt. Sembol döngüsündeki her Council
        // çağrısı internal cache'lere düşer; redundant API yükü azaltılır.
        //
        // 2026-05-14: Hermes pre-warm eklendi. Eski davranışta Council.convene
        // global semboller için HermesNewsSnapshot cache'ten okuyordu; cache
        // sadece UI manuel tetikten doluyordu → kullanıcı detaya girene kadar
        // boş → "Hermessiz alım" (9 modülün 1'i sessiz). Şimdi scouting
        // başında watchlist global sembolleri paralel pre-fetch ediliyor.
        // BIST sembolleri Council.convene içinde BISTSentimentEngine kendi
        // yolundan ısıtır — bu helper sadece global'i kapsar.
        let watchlistForHermes = WatchlistStore.shared.items
        async let demeterWarm: Void = DemeterEngine.shared.analyze()
        async let macroWarm: MacroEnvironmentRating = MacroRegimeService.shared.computeMacroEnvironment()
        async let hermesWarm: Void = HermesCoordinator.shared.warmupForScouting(symbols: watchlistForHermes)
        _ = await (demeterWarm, macroWarm, hermesWarm)
        ArgusLogger.info("🔥 Pre-warm: Demeter + Makro + Hermes hazır", category: "OTOPİLOT")

        // FİX G (observability): Piyasa durumu her turda loglansın.
        // Önceki davranışta BIST/Global piyasa kapalı olunca sessizce atlanıyordu.
        // Kullanıcı "neden BIST alımı yok?" sorusuna yanıt bulamıyordu.
        let globalOpen = MarketStatusService.shared.canTrade(for: .global)
        let bistOpen = MarketStatusService.shared.canTrade(for: .bist)
        ArgusLogger.info(
            "📍 Piyasa durumu: Global=\(globalOpen ? "AÇIK" : "KAPALI") | BIST=\(bistOpen ? "AÇIK" : "KAPALI")",
            category: "OTOPİLOT"
        )
        if !bistOpen {
            let bistCount = WatchlistStore.shared.items.filter { $0.hasSuffix(".IS") }.count
            ArgusLogger.info("  ⏱️ BIST kapalı — \(bistCount) BIST sembolü bu turda atlanacak", category: "OTOPİLOT")
        }

        let symbols = WatchlistStore.shared.items
        let simpleQuotes = MarketDataStore.shared.liveQuotes

        let portfolio = portfolioStore.trades
        let balance = portfolioStore.globalBalance
        let bistBalance = portfolioStore.bistBalance
        let equity = portfolioStore.getGlobalEquity(quotes: simpleQuotes)
        let bistEquity = portfolioStore.getBistEquity(quotes: simpleQuotes)

        ArgusLogger.info("AutoPilotStore: Bakiye - Global: $\(balance), BIST: ₺\(bistBalance)", category: "OTOPİLOT")
        ArgusLogger.info("AutoPilotStore: Equity - Global: $\(equity), BIST: ₺\(bistEquity)", category: "OTOPİLOT")
        ArgusLogger.info("AutoPilotStore: \(symbols.count) sembol taranacak...", category: "OTOPİLOT")

        var portfolioMap: [String: Trade] = [:]
        for trade in portfolio where trade.isOpen {
            if portfolioMap[trade.symbol] == nil {
                portfolioMap[trade.symbol] = trade
            }
        }
        if portfolioMap.isEmpty {
            ArgusLogger.warning(.autopilot, "Hiç açık pozisyon yok, portföy boş.")
        } else {
            ArgusLogger.info(.autopilot, "Açık pozisyon sayısı: \(portfolioMap.count)")
        }

        // 0.5. BorsaPy backend'ini ısındır — BIST sembolleri varsa ve circuit
        // açıksa veya backend soğuksa scan başlamadan önce /health pingi gönder.
        // warmUp() kendi 90s timeout'unu kullanır, scan'i en fazla o kadar bekletir.
        let hasBistSymbols = symbols.contains { $0.hasSuffix(".IS") }
        if hasBistSymbols && bistOpen {
            let circuitOpen = await BorsaPyProvider.shared.isCircuitOpen()
            let backendWarm = await BorsaPyProvider.shared.isBackendWarm()
            let needsWarmup = circuitOpen || !backendWarm
            if needsWarmup {
                ArgusLogger.info("🔥 BorsaPy backend ısındırılıyor (pre-scan)...", category: "OTOPİLOT")
                await BorsaPyProvider.shared.warmUp()
            }
        }

        // 1. Get Signals (Argus Engine) — background offload
        let results = await Task.detached(priority: .userInitiated) {
            return await AutoPilotService.shared.scanMarket(
                symbols: symbols,
                equity: equity,
                bistEquity: bistEquity,
                buyingPower: balance,
                bistBuyingPower: bistBalance,
                portfolio: portfolioMap
            )
        }.value

        let signals = results.signals
        let logs = results.logs

        if !signals.isEmpty {
            ArgusLogger.success(.autopilot, "Tespit edilen sinyal sayısı: \(signals.count)")
            let buyList = signals.filter { $0.action == .buy }.map { $0.symbol }
            let sellList = signals.filter { $0.action == .sell }.map { $0.symbol }
            ArgusLogger.info(.autopilot, "📌 BUY sinyalleri (\(buyList.count)): \(buyList.prefix(10).joined(separator: ", "))")
            if !sellList.isEmpty {
                ArgusLogger.info(.autopilot, "📌 SELL sinyalleri (\(sellList.count)): \(sellList.prefix(10).joined(separator: ", "))")
            }
        } else {
            ArgusLogger.info(.autopilot, "Yeni sinyal bulunamadı.")
        }

        // Skip özet — UI'da göstermek için
        let skipLogs = logs.filter { $0.status == "ATLA" || $0.status == "RED" || $0.status == "COOLDOWN" }
        let topReasonsArray: [String] = {
            guard !skipLogs.isEmpty else { return [] }
            let grouped = Dictionary(grouping: skipLogs, by: { $0.reason })
            return grouped
                .map { "\($0.value.count)x \($0.key)" }
                .sorted()
                .prefix(5)
                .map { $0 }
        }()

        // 2026-05-05 FIX A: TradeBrainExecutor.executeBuy guard return'lerinden toplanan
        // execution-level RED'leri summary'ye merge et. Scan'de geçip execution'da düşen
        // semboller artık UI'dan görünür.
        let executionReasons = await TradeBrainExecutionTracker.shared.topReasons(limit: 5)

        let summary = ScanSummary(
            timestamp: Date(),
            scannedCount: symbols.count,
            signalCount: signals.count,
            skippedCount: skipLogs.count,
            topSkipReasons: topReasonsArray,
            executionBlockedReasons: executionReasons,
            globalBalance: balance,
            bistBalance: bistBalance,
            openPositions: portfolioMap.count
        )
        await MainActor.run {
            self.lastScanSummary = summary
        }
        if !executionReasons.isEmpty {
            ArgusLogger.warn(
                "AUTOPILOT-EXEC-SKIP-SUMMARY: \(executionReasons.joined(separator: " | "))",
                category: "OTOPİLOT"
            )
        }

        // T3.9: Operasyonel sağlık raporu — scan başına özet metrikler.
        // signals.action SignalAction enum'u (BUY/SELL/HOLD/SKIP/WAIT). Council kararındaki
        // .aggressiveBuy/.accumulate buraya .buy, .trim/.liquidate .sell olarak map'lenir.
        let buySignals = signals.filter { $0.action == .buy }.count
        let sellSignals = signals.filter { $0.action == .sell }.count
        let neutralCount = max(0, symbols.count - buySignals - sellSignals - skipLogs.count)
        let scanRatio: (_ count: Int, _ pct: Double) -> String = { c, total in
            let pct = total > 0 ? Double(c) / total * 100 : 0
            return "\(c) (%\(String(format: "%.1f", pct)))"
        }
        let total = Double(symbols.count)
        ArgusLogger.info(
            "📊 SCAN-METRIC | \(symbols.count) sembol | " +
            "AL \(scanRatio(buySignals, total)) · " +
            "SAT \(scanRatio(sellSignals, total)) · " +
            "TUT \(scanRatio(neutralCount, total)) · " +
            "ATLA \(scanRatio(skipLogs.count, total)) · " +
            "Açık pozisyon: \(portfolioMap.count)",
            category: "OTOPİLOT"
        )

        print("🚨🚨🚨 SCAN RETURNED — signals=\(signals.count), logs=\(logs.count)")
        ArgusLogger.warn("🚨 SCAN RETURNED — signals=\(signals.count), logs=\(logs.count)", category: "OTOPİLOT")
        // 🔬 FORENSIC: İlk 20 log'u tek tek dök — stuck/skip tespiti için
        for (idx, l) in logs.prefix(20).enumerated() {
            print("🔬 LOG[\(idx)]: \(l.symbol) [\(l.status)] \(l.reason)")
            ArgusLogger.warn("🔬 LOG[\(idx)]: \(l.symbol) [\(l.status)] \(l.reason)", category: "OTOPİLOT")
        }

        if !signals.isEmpty || !logs.isEmpty {
            await MainActor.run {
                self.scoutingCandidates = signals
                let combinedLogs = logs + self.scoutLogs
                self.scoutLogs = Array(combinedLogs.prefix(100))
                ArgusLogger.info("AutoPilotStore: Updated with \(logs.count) new logs.", category: "OTOPİLOT")
                print("🚨🚨🚨 CALLING processSignals with \(signals.count) signals")
                ArgusLogger.warn("🚨 CALLING processSignals (\(signals.count) sinyal)", category: "OTOPİLOT")
                self.processSignals(signals)
            }
            if !skipLogs.isEmpty {
                ArgusLogger.warn("AUTOPILOT-SKIP-SUMMARY: \(topReasonsArray.joined(separator: " | "))", category: "OTOPİLOT")
                for item in skipLogs.prefix(12) {
                    ArgusLogger.warn("AUTOPILOT-SKIP-DETAIL: \(item.symbol) -> [\(item.status)] \(item.reason)", category: "OTOPİLOT")
                }
            }
        } else {
            ArgusLogger.warn("AutoPilotStore: Hiç sinyal veya log yok!", category: "OTOPİLOT")
        }
    }

    // MARK: - Discovery / Intent

    func analyzeDiscoveryCandidates(_ tickers: [String], source: NewsInsight) async {
        ArgusLogger.info("AutoPilotStore: Discovery Analysis for \(tickers.count) candidates from \(source.headline)", category: "OTOPİLOT")
        // Implementation Todo: Move full logic from TVM if complex, or keep shim.
    }

    func handleAutoPilotIntent(_ notification: Notification) {
        ArgusLogger.info("AutoPilotStore: Intent Received", category: "OTOPİLOT")
    }

    // MARK: - Signal Processing

    @MainActor
    func processSignals(_ signals: [TradeSignal]) {
        print("🚨🚨🚨 processSignals ENTERED with \(signals.count) signals")
        ArgusLogger.warn("🚨 processSignals ENTERED (\(signals.count))", category: "OTOPİLOT")
        ArgusLogger.info("AutoPilotStore: Toplam \(signals.count) sinyal işleniyor...", category: "OTOPİLOT")
        ArgusLogger.info("Sinyal detayları: \(signals.map { "\($0.symbol): \($0.action)" })", category: "OTOPİLOT")

        Task {
            print("🚨🚨🚨 processSignals Task STARTED")
            var decisionsForExecution: [String: ArgusGrandDecision] = [:]
            var buyCount = 0
            for signal in signals {
                if signal.action == .sell {
                    if let openTrade = self.portfolioStore.trades.first(where: { $0.isOpen && $0.symbol == signal.symbol }),
                       let currentPrice = MarketDataStore.shared.liveQuotes[signal.symbol]?.currentPrice {
                        if let trim = signal.trimPercentage, trim > 0, trim < 1 {
                            let trimPercent = max(1, min(trim * 100, 99))
                            _ = self.portfolioStore.trim(
                                tradeId: openTrade.id,
                                percentage: trimPercent,
                                currentPrice: currentPrice,
                                reason: "AUTOPILOT_SIGNAL_TRIM_\(Int(trimPercent))"
                            )
                            ArgusLogger.warn(
                                "AutoPilotStore: SELL sinyali trim uyguladı -> \(signal.symbol) %\(Int(trimPercent))",
                                category: "OTOPİLOT"
                            )
                        } else {
                            // 2026-05-13 Task 7.1: processSignals LIQUIDATE yolu da
                            // sellAsync'e taşındı (checkPlanTriggers ile symmetrik).
                            // Learning chain deterministik tamamlanır.
                            _ = await self.portfolioStore.sellAsync(
                                tradeId: openTrade.id,
                                currentPrice: currentPrice,
                                reason: "AUTOPILOT_SIGNAL_LIQUIDATE"
                            )
                            ArgusLogger.warn("AutoPilotStore: SELL sinyali tam çıkış uyguladı -> \(signal.symbol)", category: "OTOPİLOT")
                        }
                    } else {
                        ArgusLogger.info("AutoPilotStore: SELL sinyali açık pozisyon bulamadı -> \(signal.symbol)", category: "OTOPİLOT")
                    }
                    continue
                }

                guard signal.action == .buy else { continue }
                buyCount += 1
                ArgusLogger.info(.autopilot, "💡 BUY sinyali bulundu: \(signal.symbol) - \(signal.reason)")

                if SymbolResolver.shared.isBistSymbol(signal.symbol) {
                    if !isBistMarketOpen() {
                        ArgusLogger.warn("AutoPilotStore: BIST kapalı, \(signal.symbol) atlandı", category: "OTOPİLOT")
                        continue
                    }
                }

                // Council kararı evaluate()'den taşınıyor — double convene yok.
                guard let decision = signal.grandDecision else {
                    ArgusLogger.warn("AutoPilotStore: BUY sinyali Council kararı taşımıyor: \(signal.symbol)", category: "OTOPİLOT")
                    continue
                }

                SignalStateViewModel.shared.grandDecisions[signal.symbol] = decision
                decisionsForExecution[signal.symbol] = decision
                ArgusLogger.info("AutoPilotStore: Grand Council Decision for \(signal.symbol): \(decision.action.rawValue) · conf=\(String(format: "%.2f", decision.confidence))", category: "OTOPİLOT")
            }

            if buyCount == 0 {
                ArgusLogger.warn("AutoPilotStore: Bu turda BUY sinyali çıkmadı.", category: "OTOPİLOT")
            }

            // Açık pozisyonlardaki acil likidasyon kararlarını da yürütücüye taşı
            let openSymbols = Set(self.portfolioStore.trades.filter { $0.isOpen }.map { $0.symbol })
            for symbol in openSymbols {
                if let cachedDecision = SignalStateViewModel.shared.grandDecisions[symbol] {
                    decisionsForExecution[symbol] = cachedDecision
                }
            }

            if decisionsForExecution.isEmpty {
                ArgusLogger.warn("AutoPilotStore: Yürütülecek güncel karar yok (signals/open positions).", category: "OTOPİLOT")
            }

            // Execute Decisions (Trade Brain)
            let simpleQuotes = MarketDataStore.shared.liveQuotes

            // Prepare Orion Scores & Candles for Governance
            var orionScoresMap: [String: OrionScoreResult] = [:]
            var candlesMap: [String: [Candle]] = [:]

            for (symbol, _) in decisionsForExecution {
                if let score = SignalStateViewModel.shared.orionScores[symbol] {
                    orionScoresMap[symbol] = score
                }

                if let cVal = MarketDataStore.shared.candles[symbol], let candles = cVal.value {
                    candlesMap[symbol] = candles
                }
            }

            print("🚨🚨🚨 CALLING TradeBrainExecutor.evaluateDecisions with \(decisionsForExecution.count) kararlar")
            ArgusLogger.warn("🚨 evaluateDecisions ÇAĞRILIYOR (\(decisionsForExecution.count) karar)", category: "OTOPİLOT")
            await TradeBrainExecutor.shared.evaluateDecisions(
                decisions: decisionsForExecution,
                portfolio: self.portfolioStore.trades,
                quotes: simpleQuotes,
                balance: self.portfolioStore.globalBalance,
                bistBalance: self.portfolioStore.bistBalance,
                macroScore: MacroRegimeService.shared.getCachedRating()?.numericScore,
                orionScores: orionScoresMap,
                candles: candlesMap
            )
            print("🚨🚨🚨 evaluateDecisions RETURNED")
            ArgusLogger.warn("🚨 evaluateDecisions RETURNED", category: "OTOPİLOT")

            // Check Plan Triggers
            await self.checkPlanTriggers()
        }
    }

    // MARK: - Sirkiye Input (BIST)

    func prepareSirkiyeInput(macro: MacroSnapshot) async -> SirkiyeEngine.SirkiyeInput? {
        // 2026-05-05 (Round 4) FIX: Eski sürüm 3 yolda da `newsSnapshot: nil` ve
        // hardcoded `45.0` enflasyon, `50.0` faiz, `35.0` USD/TRY fallback kullanıyordu.
        // Sonuç: Türkiye'de TL %5 düşse, faiz şoku gelse bile sistem 35.0 referansıyla
        // 45/50 default'larıyla hesap yapıyor → skor sahte stabil ~58 dönüyor.
        // Şimdi: gerçek veri yoksa nil dön (Sirkiye analizini atla), false-positive
        // skor üretmek yerine "veri yetersiz" tutumunu üst katmana bildir.

        let quotes = MarketDataStore.shared.liveQuotes
        var usdQuoteResolved = quotes["USD/TRY"] ?? quotes["USDTRY=X"] ?? quotes["USDTRY"]

        async let newsTask = SirkiyeNewsHelper.snapshotForTurkey()
        async let foreignFlowTask = ForeignInvestorFlowService.shared.getMarketForeignSentiment()

        async let brentTask = { try? await BorsaPyProvider.shared.getBrentPrice() }()
        async let inflationTask = { try? await BorsaPyProvider.shared.getInflationData() }()
        async let policyRateTask = { try? await BorsaPyProvider.shared.getPolicyRate() }()
        async let xu100Task = { try? await BorsaPyProvider.shared.getXU100() }()
        async let goldTask = { try? await BorsaPyProvider.shared.getGoldPrice() }()

        // MarketDataStore'da USD/TRY yoksa BorsaPy'den dene
        if usdQuoteResolved == nil {
            if let fx = try? await BorsaPyProvider.shared.getFXRate(asset: "USDTRY") {
                ArgusLogger.info("💱 USD/TRY BorsaPy'den alındı: ₺\(String(format: "%.2f", fx.last))", category: "OTOPİLOT")
                let news = await newsTask
                let foreignFlow = await foreignFlowTask
                let (brent, inflation, policyRate, xu100, gold) = await (brentTask, inflationTask, policyRateTask, xu100Task, goldTask)
                var xu100Change: Double? = nil
                var xu100Value: Double? = nil
                if let xu = xu100 {
                    xu100Value = xu.last
                    if xu.open > 0 {
                        xu100Change = ((xu.last - xu.open) / xu.open) * 100
                    }
                }
                return SirkiyeEngine.SirkiyeInput(
                    usdTry: fx.last,
                    usdTryPrevious: fx.open > 0 ? fx.open : fx.last,
                    dxy: macro.dxy,
                    brentOil: brent?.last ?? macro.brent,
                    globalVix: macro.vix,
                    newsSnapshot: news,
                    currentInflation: inflation?.yearlyInflation,
                    policyRate: policyRate,
                    xu100Change: xu100Change,
                    xu100Value: xu100Value,
                    goldPrice: gold?.last,
                    foreignFlowScore: foreignFlow
                )
            }
        }

        guard let usdQuote = usdQuoteResolved else {
            // 2026-05-05 FIX: USD/TRY yok ise nil dön, Sirkiye analizi atlansın.
            print("⚠️ AutoPilotStore: USD/TRY kuru bulunamadı, Sirkiye analizi atlanıyor")
            return nil
        }

        let news = await newsTask
        let foreignFlow = await foreignFlowTask
        let (brent, inflation, policyRate, xu100, gold) = await (brentTask, inflationTask, policyRateTask, xu100Task, goldTask)

        var xu100Change: Double? = nil
        var xu100Value: Double? = nil
        if let xu = xu100 {
            xu100Value = xu.last
            if xu.open > 0 {
                xu100Change = ((xu.last - xu.open) / xu.open) * 100
            }
        }

        return SirkiyeEngine.SirkiyeInput(
            usdTry: usdQuote.currentPrice,
            usdTryPrevious: usdQuote.previousClose ?? usdQuote.currentPrice,
            dxy: macro.dxy,
            brentOil: brent?.last ?? macro.brent,
            globalVix: macro.vix,
            newsSnapshot: news,
            currentInflation: inflation?.yearlyInflation,
            policyRate: policyRate,
            xu100Change: xu100Change,
            xu100Value: xu100Value,
            goldPrice: gold?.last,
            foreignFlowScore: foreignFlow
        )
    }

    func isBistMarketOpen() -> Bool {
        MarketStatusService.shared.isBistOpen()
    }

    // MARK: - Plan Triggers

    func checkPlanTriggers() async {
        let openTrades = portfolioStore.trades.filter { $0.isOpen }
        guard !openTrades.isEmpty else { return }

        let quotes = MarketDataStore.shared.liveQuotes
        var triggeredCount = 0

        // FIX #3: Makro rejim transition tepkisi.
        // Aether skoru aniden riskOff eşiğine düşerse (< 40) açık pozisyonlara
        // %30 koruyucu trim uygula. Trim bir kez tetiklensin diye son trim
        // zamanı tutulur (1 saat cooldown).
        let aether = MacroRegimeService.shared.getCachedRating()?.numericScore ?? 50
        let velocitySignal = await AetherVelocityEngine.shared.analyze()
        let isCrashMode = aether < 40 && (velocitySignal.signal == .deterioratingFast || velocitySignal.signal == .deteriorating)
        if isCrashMode {
            let lastProtectiveTrim = UserDefaults.standard.object(forKey: "Argus_LastProtectiveTrim") as? Date
            let cooledDown = lastProtectiveTrim == nil || Date().timeIntervalSince(lastProtectiveTrim!) > 3600
            if cooledDown {
                ArgusLogger.warn("🛡️ Makro rejim transition — Aether:\(Int(aether)) velocity:\(velocitySignal.signal.rawValue). Koruyucu trim %30 uygulanıyor.", category: "OTOPİLOT")
                print("🛡️🛡️🛡️ CRASH MODE — %30 trim tüm açık pozisyonlara")
                for trade in openTrades {
                    guard let currentPrice = quotes[trade.symbol]?.currentPrice, currentPrice > 0 else { continue }
                    _ = portfolioStore.trim(
                        tradeId: trade.id,
                        percentage: 30,
                        currentPrice: currentPrice,
                        reason: "MACRO_CRASH_TRIM_30: Aether<\(Int(aether)) + velocity=\(velocitySignal.signal.rawValue)"
                    )
                    triggeredCount += 1
                }
                UserDefaults.standard.set(Date(), forKey: "Argus_LastProtectiveTrim")
            }
        }

        for trade in openTrades {
            guard let currentPrice = quotes[trade.symbol]?.currentPrice, currentPrice > 0 else {
                continue
            }

            let grandDecision = SignalStateViewModel.shared.grandDecisions[trade.symbol]
            guard let action = PositionPlanStore.shared.checkTriggers(
                trade: trade,
                currentPrice: currentPrice,
                grandDecision: grandDecision
            ) else {
                continue
            }

            triggeredCount += 1
            PositionPlanStore.shared.markStepCompleted(tradeId: trade.id, stepId: action.id)

            switch action.action {
            case .sellAll:
                // Task 7: checkPlanTriggers() async — sellAsync ile learning chain'in
                // tamamlanmasını bekle. Sıralı plan adımlarında "trade kapalı ama Chiron
                // henüz öğrenmedi" race riski yok.
                _ = await portfolioStore.sellAsync(
                    tradeId: trade.id,
                    currentPrice: currentPrice,
                    reason: "PLAN_SELL_ALL: \(action.description)"
                )
                PositionPlanStore.shared.completePlan(tradeId: trade.id)

            case .sellPercent(let percent):
                let clampedPercent = max(1, min(percent, 100))
                if clampedPercent >= 100 {
                    _ = await portfolioStore.sellAsync(
                        tradeId: trade.id,
                        currentPrice: currentPrice,
                        reason: "PLAN_SELL_100: \(action.description)"
                    )
                    PositionPlanStore.shared.completePlan(tradeId: trade.id)
                } else {
                    _ = portfolioStore.trim(
                        tradeId: trade.id,
                        percentage: clampedPercent,
                        currentPrice: currentPrice,
                        reason: "PLAN_TRIM_\(Int(clampedPercent)): \(action.description)"
                    )
                }

            case .reduceAndHold(let percent):
                let clampedPercent = max(1, min(percent, 100))
                if clampedPercent >= 100 {
                    _ = await portfolioStore.sellAsync(
                        tradeId: trade.id,
                        currentPrice: currentPrice,
                        reason: "PLAN_REDUCE_100: \(action.description)"
                    )
                    PositionPlanStore.shared.completePlan(tradeId: trade.id)
                } else {
                    _ = portfolioStore.trim(
                        tradeId: trade.id,
                        percentage: clampedPercent,
                        currentPrice: currentPrice,
                        reason: "PLAN_REDUCE_\(Int(clampedPercent)): \(action.description)"
                    )
                }

            case .alert(let message):
                // Faz III (2026-05-12): Plan alert'i artık plana review bayrağı da
                // basıyor. Eski model: Konsey ÇIK → auto sellAll. Yeni model:
                // alert + requiresReview → kullanıcı tezi gözden geçirir, kendi
                // karar verir. journeyLog'da iz kalır.
                PositionPlanStore.shared.markPlanForReview(
                    tradeId: trade.id,
                    reason: message,
                    triggeredBy: "Plan Trigger"
                )
                let alert = TradeBrainAlert(
                    type: .planTriggered,
                    symbol: trade.symbol,
                    message: message,
                    actionDescription: action.description,
                    priority: .medium
                )
                NotificationCenter.default.post(
                    name: .tradeBrainAlert,
                    object: nil,
                    userInfo: ["alert": alert]
                )

            case .moveStopTo(_), .moveStopByPercent(_), .activateTrailingStop(_), .setBreakeven, .addPercent(_), .addFixed(_), .reevaluate, .doNothing:
                // Bu aksiyonlar için Store tarafında güvenli mutasyon API'si eksik.
                // Şimdilik adım işaretlenir, yalnızca bilgilendirme logu bırakılır.
                ArgusLogger.info("AutoPilotStore: Plan aksiyonu loglandı, icra edilmedi -> \(trade.symbol): \(action.description)", category: "OTOPİLOT")
            }
        }

        if triggeredCount > 0 {
            ArgusLogger.info("AutoPilotStore: \(triggeredCount) plan tetikleyicisi işlendi.", category: "OTOPİLOT")
        }
    }

    // MARK: - Passive Scanner

    func processHighConvictionCandidate(symbol: String, score: Double) async {
        guard isAutoPilotEnabled else { return }
        // ... (Logic to be migrated)
    }
}
