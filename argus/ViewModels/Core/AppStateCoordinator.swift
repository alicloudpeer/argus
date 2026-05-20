import Foundation
import Combine
import SwiftUI

/// FAZ 2: AppStateCoordinator - Single Source of Truth (SSOT)
/// Tüm alt ViewModel'leri koordine eden merkezi orchestrator.
/// TradingViewModel'den ayrılmış modüler yapı için köprü görevi görür.
///
/// SSOT Pattern: AppStateCoordinator acts as a facade to child stores/ViewModels:
/// - Does NOT duplicate data
/// - Uses computed properties to access child store data
/// - Binds only its own @Published UI state properties
/// - Coordinates between different domains (Watchlist, Market, Portfolio, Signals, Execution, Diagnostics)
///
/// 2026-05-06 — Aşama A refactor: 31 flat @Published → 6 typed domain state
/// (BacktestState, ReportState, ShockState, UniverseState, EnvironmentState, ExecutionMirrorState).
/// Eski caller'lar için backward-compat computed property'ler korundu.
@MainActor
final class AppStateCoordinator: ObservableObject {

    // MARK: - Singleton (Geçiş döneminde backward compatibility için)
    static let shared = AppStateCoordinator()

    // MARK: - Sub ViewModels
    let watchlist: WatchlistViewModel

    // MARK: - Legacy Accessor for Views (Backward Compatibility)
    var portfolio: PortfolioStore {
        PortfolioStore.shared
    }

    // MARK: - Domain State (6 typed groups)

    @Published var backtest = BacktestState()
    @Published var report = ReportState()
    @Published var shock = ShockState()
    @Published var universe = UniverseState()
    @Published var environment = EnvironmentState()
    @Published var executionMirror = ExecutionMirrorState()

    // MARK: - Combine
    var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    private init() {
        self.watchlist = WatchlistViewModel()
        setupDataBindings()
        setupDomainSideEffects()
    }

    /// Domain state struct değişimlerinde tetiklenecek side-effect'ler.
    /// (Eski didSet'ler typed struct'a taşınamadığı için Combine ile çözülüyor.)
    private func setupDomainSideEffects() {
        $environment
            .map(\.isUnlimitedPositions)
            .removeDuplicates()
            .sink { value in
                PortfolioRiskManager.shared.isUnlimitedPositionsEnabled = value
            }
            .store(in: &cancellables)
    }

    // MARK: - Convenience Methods

    /// Sembol detay görünümüne geçiş
    func selectSymbol(_ symbol: String) {
        universe.selectedSymbol = symbol
    }

    // Backward-compat pass-through'lar Faz 2.5'te kaldırıldı.
    // Yeni kod typed domain'lerden okur: backtest, report, shock, universe,
    // environment, executionMirror. View'lar coordinator.<domain>.<prop> formuyla erişir.
}
