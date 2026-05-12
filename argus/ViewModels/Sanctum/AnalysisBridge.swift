import Foundation
import Combine
import SwiftUI

/// SanctumViewModel'in analiz katmanı: Orion (multi-timeframe), Atlas snapshot,
/// Macro rating, Entry setup, Grand Council kararı.
/// SignalStateViewModel + OrionStore + EntryStore + ArgusGrandCouncil'a bağlı.
@MainActor
final class AnalysisBridge: ObservableObject {
    let symbol: String

    @Published var orionAnalysis: MultiTimeframeAnalysis?
    @Published var orionFailure: OrionFailureReason?
    @Published var orionScore: OrionScoreResult?
    @Published var entrySetup: EntrySetup?
    @Published var macroRating: MacroEnvironmentRating?
    @Published var grandDecision: ArgusGrandDecision?
    @Published var snapshot: FinancialSnapshot?

    private var cancellables = Set<AnyCancellable>()
    private let analysisService = FinancialSnapshotService.shared

    /// QuoteDataBridge tarafından sağlanan candle erişimi — council'da kullanılır.
    private weak var quoteBridge: QuoteDataBridge?

    init(symbol: String, quoteBridge: QuoteDataBridge) {
        self.symbol = symbol
        self.quoteBridge = quoteBridge
        setupBindings()
        observeTimeframeChanges()
    }

    private func setupBindings() {
        // Orion Analysis
        SignalStateViewModel.shared.$orionAnalysis
            .map { $0[self.symbol] }
            .receive(on: RunLoop.main)
            .assign(to: \.orionAnalysis, on: self)
            .store(in: &cancellables)

        // Orion Score (timeframe-aware, bridge'in selectedTimeframe'ine göre)
        SignalStateViewModel.shared.$orionAnalysis
            .receive(on: RunLoop.main)
            .sink { [weak self] analysisBySymbol in
                guard let self else { return }
                let timeframe = self.quoteBridge?.selectedTimeframe ?? .daily
                if let analysis = analysisBySymbol[self.symbol] {
                    self.orionScore = analysis.scoreFor(timeframe: timeframe)
                } else {
                    self.orionScore = nil
                }
            }
            .store(in: &cancellables)

        // Orion Failure
        OrionStore.shared.$lastFailureReason
            .map { $0[self.symbol] }
            .receive(on: RunLoop.main)
            .assign(to: \.orionFailure, on: self)
            .store(in: &cancellables)

        // Entry Setup
        EntryStore.shared.$setups
            .map { $0[self.symbol] }
            .receive(on: RunLoop.main)
            .assign(to: \.entrySetup, on: self)
            .store(in: &cancellables)

        // Grand Council
        SignalStateViewModel.shared.$grandDecisions
            .map { $0[self.symbol] }
            .receive(on: RunLoop.main)
            .assign(to: \.grandDecision, on: self)
            .store(in: &cancellables)
    }

    /// QuoteDataBridge.selectedTimeframe değiştiğinde orionScore'u recompute et.
    private func observeTimeframeChanges() {
        guard let quoteBridge else { return }
        quoteBridge.$selectedTimeframe
            .receive(on: RunLoop.main)
            .sink { [weak self] newTimeframe in
                guard let self, let analysis = self.orionAnalysis else { return }
                self.orionScore = analysis.scoreFor(timeframe: newTimeframe)
            }
            .store(in: &cancellables)
    }

    /// Snapshot + macro rating fetch — paralel.
    /// Snapshot per-symbol (FinancialSnapshotService), macro global
    /// (MacroRegimeService). Bağımsız network çağrıları, async-let ile paralel.
    func loadAnalysisCore() async {
        async let snapshotResult: FinancialSnapshot? = {
            do {
                return try await analysisService.fetchSnapshot(symbol: symbol)
            } catch {
                print("⚠️ AnalysisBridge: Snapshot hatası: \(error)")
                return nil
            }
        }()
        async let macroResult: MacroEnvironmentRating = MacroRegimeService.shared.computeMacroEnvironment()

        let (snapshot, macro) = await (snapshotResult, macroResult)
        self.snapshot = snapshot
        self.macroRating = macro
    }

    /// Konsey kararı: Tüm modülleri toplayıp nihai karar üretir.
    /// Candles için QuoteDataBridge'in fallback'ini kullanır.
    func conveneCouncil() async {
        guard let quoteBridge else {
            print("⚠️ AnalysisBridge: quoteBridge nil, konsey atlandı")
            return
        }

        let councilCandles = await quoteBridge.ensureCouncilCandles()
        guard councilCandles.count >= 30 else {
            print("⚠️ AnalysisBridge: Konsey toplanamadı - candle verisi yok (\(symbol))")
            return
        }

        let isBist = symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
        let macro = await MacroSnapshotService.shared.getSnapshot()

        var sirkiyeInput: SirkiyeEngine.SirkiyeInput? = nil
        if isBist {
            sirkiyeInput = await buildSirkiyeInput(macro: macro)
        }

        // Hermes news: cache'den al, yoksa nil (graceful degradation)
        let news: HermesNewsSnapshot? = isBist
            ? await HermesNewsSnapshot.fromBistCache(symbol: symbol)
            : HermesNewsSnapshot.fromCache(symbol: symbol)

        let demeterScore = await DemeterEngine.shared.scoreForSymbol(symbol)
        let athenaResult = SignalStateViewModel.shared.athenaResults[symbol]

        let decision = await ArgusGrandCouncil.shared.convene(
            symbol: symbol,
            candles: councilCandles,
            snapshot: snapshot,
            macro: macro,
            news: news,
            engine: .pulse,
            athena: athenaResult,
            demeter: demeterScore,
            sirkiyeInput: sirkiyeInput,
            origin: "SANCTUM_VM"
        )

        SignalStateViewModel.shared.grandDecisions[symbol] = decision
        print("🏛️ AnalysisBridge: \(symbol) Konsey kararı: \(decision.action.rawValue) (Güven: %\(Int(decision.confidence * 100)))")
    }

    /// BIST için SirkiyeInput hazırla — BorsaPy canlı verilerle.
    private func buildSirkiyeInput(macro: MacroSnapshot) async -> SirkiyeEngine.SirkiyeInput? {
        let quotes = MarketDataStore.shared.liveQuotes
        guard let usdQuote = quotes["USD/TRY"] ?? quotes["USDTRY=X"] else { return nil }

        async let brentTask = { try? await BorsaPyProvider.shared.getBrentPrice() }()
        async let inflationTask = { try? await BorsaPyProvider.shared.getInflationData() }()
        async let policyRateTask = { try? await BorsaPyProvider.shared.getPolicyRate() }()
        async let xu100Task = { try? await BorsaPyProvider.shared.getXU100() }()
        async let goldTask = { try? await BorsaPyProvider.shared.getGoldPrice() }()

        async let newsTask = SirkiyeNewsHelper.snapshotForTurkey()
        async let foreignFlowTask = ForeignInvestorFlowService.shared.getMarketForeignSentiment()

        let (brent, inflation, policyRate, xu100, gold) = await (brentTask, inflationTask, policyRateTask, xu100Task, goldTask)
        let news = await newsTask
        let foreignFlow = await foreignFlowTask

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
            dxy: nil,
            brentOil: brent?.last,
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
