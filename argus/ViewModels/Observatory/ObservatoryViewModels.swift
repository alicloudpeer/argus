import Foundation
import Combine

// MARK: - Observatory Tab ViewModels (Faz 3.6)
//
// Önceki yapı: 4 ayrı view kendi @State'inde decisions/events/trades/metrics
// tutuyor, ArgusLedger.loadRecentDecisions iki view'da (Timeline + Health)
// duplicate çağrılıyordu. Her view inline load logic + UI mixed.
//
// Yeni yapı: tab başına bir ViewModel. View sadece observe eder, load tetikler.
// Test edilebilirlik kazanıldı; data layer ile UI ayrıldı.

// MARK: - Timeline

@MainActor
final class ObservatoryTimelineViewModel: ObservableObject {
    @Published var decisions: [DecisionCard] = []
    @Published var isLoading: Bool = true
    @Published var selectedFilter: TimelineFilter = .all

    var filteredDecisions: [DecisionCard] {
        switch selectedFilter {
        case .all:     return decisions
        case .pending: return decisions.filter { $0.outcome == .pending }
        case .matured: return decisions.filter { $0.outcome == .matured }
        case .bist:    return decisions.filter { $0.market == "BIST" }
        case .global:  return decisions.filter { $0.market == "US" }
        }
    }

    func load() async {
        isLoading = true
        let events = ArgusLedger.shared.loadRecentDecisions(limit: 100)
        self.decisions = events
        self.isLoading = false
    }
}

// MARK: - Learning

@MainActor
final class ObservatoryLearningViewModel: ObservableObject {
    @Published var events: [LearningEvent] = []
    @Published var isLoading: Bool = true

    /// Şu an placeholder — Faz 3.6 öncesinde view'da da load logic yoktu.
    /// LearningEvent kaynak servisi netleştiğinde buraya bağlanır.
    func load() async {
        isLoading = false
    }
}

// MARK: - Health

@MainActor
final class ObservatoryHealthViewModel: ObservableObject {
    @Published var metrics: PerformanceMetrics = .empty
    @Published var distribution: PredictionDistribution = .empty
    @Published var alerts: [DataQualityAlert] = []
    @Published var isLoading: Bool = true

    func load() async {
        isLoading = true
        let decisions = ArgusLedger.shared.loadRecentDecisions(limit: 100)

        // Matured hit rate + profit factor
        let matured = decisions.filter { $0.outcome == .matured }
        let wins = matured.filter { ($0.actualPnl ?? 0) > 0 }
        let hitRate = matured.isEmpty ? 0.5 : Double(wins.count) / Double(matured.count)

        let pnls = matured.compactMap { $0.actualPnl }
        let profits = pnls.filter { $0 > 0 }.reduce(0, +)
        let losses = abs(pnls.filter { $0 < 0 }.reduce(0, +))
        let profitFactor = losses > 0 ? profits / losses : 2.0

        // Sharpe approximation
        let avgPnl = pnls.isEmpty ? 0 : pnls.reduce(0, +) / Double(pnls.count)
        let variance = pnls.isEmpty ? 1 : pnls.map { pow($0 - avgPnl, 2) }.reduce(0, +) / Double(pnls.count)
        let stdDev = sqrt(variance)
        let sharpe = stdDev > 0 ? avgPnl / stdDev : 0

        // Max drawdown (cumulative equity simulation)
        var maxDD = 0.0
        var peak = 0.0
        var equity = 0.0
        for pnl in pnls {
            equity += pnl
            if equity > peak { peak = equity }
            let dd = peak > 0 ? (peak - equity) / peak * 100 : 0
            if dd > maxDD { maxDD = dd }
        }

        // Distribution + drift detection
        let buyCount = decisions.filter { $0.action.contains("BİRİKTİR") || $0.action.contains("HÜCUM") }.count
        let sellCount = decisions.filter { $0.action.contains("AZALT") || $0.action.contains("ÇIK") }.count
        let holdCount = decisions.count - buyCount - sellCount
        let total = max(1, Double(decisions.count))
        let buyPct = Double(buyCount) / total * 100
        let sellPct = Double(sellCount) / total * 100
        let holdPct = Double(holdCount) / total * 100
        let isDrifting = buyPct > 70 || sellPct > 70 || holdPct > 80
        let driftReason = buyPct > 70 ? "EXCESS BUY" : (sellPct > 70 ? "EXCESS SELL" : (holdPct > 80 ? "EXCESS HOLD" : ""))

        self.metrics = PerformanceMetrics(
            sharpe: sharpe,
            hitRate: hitRate,
            profitFactor: profitFactor,
            maxDrawdown: maxDD
        )
        self.distribution = PredictionDistribution(
            buyPercent: buyPct,
            holdPercent: holdPct,
            sellPercent: sellPct,
            isDrifting: isDrifting,
            driftReason: driftReason
        )
        self.isLoading = false
    }
}

// MARK: - Trade History

@MainActor
final class TradeHistoryViewModel: ObservableObject {
    enum Filter: String, CaseIterable {
        case all = "Tümü"
        case wins = "Kazançlar"
        case losses = "Kayıplar"
    }

    @Published var trades: [TradeOutcomeRecord] = []
    @Published var isLoading: Bool = true
    @Published var selectedFilter: Filter = .all

    var filteredTrades: [TradeOutcomeRecord] {
        switch selectedFilter {
        case .all:    return trades
        case .wins:   return trades.filter { $0.pnlPercent > 0 }
        case .losses: return trades.filter { $0.pnlPercent <= 0 }
        }
    }

    func load() async {
        isLoading = true
        trades = await ChironDataLakeService.shared.loadAllTradeHistory()
        isLoading = false
    }
}
