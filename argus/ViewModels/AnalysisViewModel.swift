import Foundation
import Combine
import SwiftUI

/// Analysis & Signals Manager
/// Extracted from TradingViewModel (Phase 2)
/// Handles: Orion, Council, Chimera, Reports, Demeter
@MainActor
final class AnalysisViewModel: ObservableObject {
    static let shared = AnalysisViewModel()

    // MARK: - Signal Facade (Delegated to SignalStateViewModel)
    
    var orionAnalysis: [String: MultiTimeframeAnalysis] { SignalStateViewModel.shared.orionAnalysis }
    var isOrionLoading: Bool { SignalStateViewModel.shared.isOrionLoading }
    var patterns: [String: [OrionChartPattern]] { SignalStateViewModel.shared.patterns }
    
    var grandDecisions: [String: ArgusGrandDecision] {
        get { SignalStateViewModel.shared.grandDecisions }
        set { SignalStateViewModel.shared.grandDecisions = newValue }
    }
    
    var chimeraSignals: [String: ChimeraSignal] {
        get { SignalStateViewModel.shared.chimeraSignals }
        set { SignalStateViewModel.shared.chimeraSignals = newValue }
    }
    
    /// Cached daily scores - SignalStateViewModel'deki @Published cache'ten okur.
    /// Önceden her erişimde mapValues çalışıyordu; artık tek seviyeli forward.
    var orionScores: [String: OrionScoreResult] {
        return SignalStateViewModel.shared.orionScores
    }
    
    // MARK: - Financial Data
    @Published var snapshots: [String: FinancialSnapshot] = [:]

    // MARK: - Other AI Signals
    @Published var aiSignals: [AISignal] = []
    @Published var macroRating: MacroEnvironmentRating?
    
    // Reported & Content
    @Published var dailyReport: String?
    @Published var weeklyReport: String?
    @Published var bistDailyReport: String?
    @Published var bistWeeklyReport: String?
    
    // KAP
    @Published var kapDisclosures: [String: [KAPDataService.KAPNews]] = [:]
    
    // Sirkiye (BIST Atmosphere)
    @Published var bistAtmosphere: AetherDecision?
    @Published var bistAtmosphereLastUpdated: Date?
    
    // Overreaction Hunter
    @Published var overreactionResult: OverreactionResult?
    
    // DEMETER state: SignalStateViewModel'den okuyun — bu mirror'lar kaldırıldı (Faz 2.4 SSOT)
    
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Faz 3.5: SignalViewModel.analysisViewModel artık lazy var — init zincirinde
        // AnalysisViewModel.shared'a erişim yok. Cyclic crash riski kalktığı için
        // setupSourceMirrors doğrudan çağrılır, defer kaldırıldı.
        setupSourceMirrors()
    }

    /// View-facing AnalysisVM, kanonik kaynaklardan (HermesNewsVM, SignalViewModel)
    /// per-property mirror eder. TVM facade'inin yerini tutar: engine'ler kendi
    /// VM'lerine yazar, view'lar AnalysisVM'i observe eder, bu binding bridge'i
    /// sağlar. Dar binding — tek property güncellemesi tek emit üretir.
    private func setupSourceMirrors() {
        // BIST Atmosphere — HermesNewsVM canonical writer
        HermesNewsViewModel.shared.$bistAtmosphere
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bistAtmosphere = $0 }
            .store(in: &cancellables)

        HermesNewsViewModel.shared.$bistAtmosphereLastUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bistAtmosphereLastUpdated = $0 }
            .store(in: &cancellables)

        // Demeter mirror'ları kaldırıldı (Faz 2.4 SSOT) — view'lar SignalStateViewModel'i observe etsin.
    }

    func generateAISignals() async {
        let market = MarketViewModel.shared
        let signals = await AISignalService.shared.generateSignals(quotes: market.quotes, candles: market.candles)
        await MainActor.run { self.aiSignals = signals }
    }

    func refreshReports() async {
        let trades = PortfolioStore.shared.transactions
        let decisions = Array(ExecutionStateViewModel.shared.agoraTraces.values)
        let atmosphere = (aether: macroRating?.numericScore, demeter: SignalViewModel.shared.demeterMatrix)

        let bistTrades = trades.filter { $0.symbol.uppercased().hasSuffix(".IS") }
        let bistDecisions = decisions.filter { $0.symbol.uppercased().hasSuffix(".IS") }
        let globalTrades = trades.filter { !$0.symbol.uppercased().hasSuffix(".IS") }
        let globalDecisions = decisions.filter { !$0.symbol.uppercased().hasSuffix(".IS") }

        let engine = ReportEngine.shared

        dailyReport = await engine.generateDailyReport(
            date: Date(), trades: globalTrades, decisions: globalDecisions, atmosphere: atmosphere
        )
        weeklyReport = await engine.generateWeeklyReport(
            date: Date(), trades: globalTrades, decisions: globalDecisions
        )
        bistDailyReport = await engine.generateDailyReport(
            date: Date(), trades: bistTrades, decisions: bistDecisions, atmosphere: atmosphere
        )
        bistWeeklyReport = await engine.generateWeeklyReport(
            date: Date(), trades: bistTrades, decisions: bistDecisions
        )
    }
}
