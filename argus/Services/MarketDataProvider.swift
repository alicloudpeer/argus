import Foundation
import Combine

// MARK: - Data Health Report (Inline)
enum DataHealthStatus: String {
    case healthy = "Healthy"
    case degraded = "Degraded"
    case unhealthy = "Unhealthy"
}

struct DataHealthReport {
    var timestamp: Date
    var overallStatus: DataHealthStatus
    var apiLatency: Double
    var dataFreshness: Double
    var activeProvider: String
    var errors: [String]
}

/// Streaming engine. Two parallel WebSocket sources push live ticks
/// into `MarketDataStore`: Finnhub for the primary 50-symbol set and
/// TwelveData for an additional 8-symbol redundancy. Last writer wins
/// by timestamp inside `injectLiveQuote`. Symbol search routes through
/// Finnhub.
class MarketDataProvider: ObservableObject {
    static let shared = MarketDataProvider()

    private let finnhub = FinnhubLiveStream.shared
    private let twelveData = TwelveDataService.shared

    let priceUpdate = PassthroughSubject<Quote, Never>()
    private var cancellables = Set<AnyCancellable>()

    @Published var dataHealth = DataHealthReport(
        timestamp: Date(),
        overallStatus: .healthy,
        apiLatency: 0,
        dataFreshness: 0,
        activeProvider: "Finnhub + TwelveData",
        errors: []
    )

    private init() {
        setupStreaming()
    }

    private func setupStreaming() {
        finnhub.priceUpdate
            .sink { [weak self] quote in
                self?.handleIncomingStream(quote, source: "Finnhub")
            }
            .store(in: &cancellables)

        twelveData.priceUpdate
            .sink { [weak self] quote in
                self?.handleIncomingStream(quote, source: "TwelveData")
            }
            .store(in: &cancellables)
    }

    private func handleIncomingStream(_ quote: Quote, source: String) {
        // Discard ticks older than 15s so a brief disconnect cannot
        // replay stale prices into the SSoT.
        guard let ts = quote.timestamp, Date().timeIntervalSince(ts) <= 15 else {
            return
        }
        Task { @MainActor in
            priceUpdate.send(quote)
            dataHealth.activeProvider = source
            dataHealth.dataFreshness = 0
            MarketDataStore.shared.injectLiveQuote(quote, source: "\(source) (Stream)")
        }
    }

    /// Updates both live subscription sets. Should be the union of open
    /// positions and the visible portion of the watchlist.
    func connectStream(symbols: [String]) {
        finnhub.setSubscriptions(symbols)
        twelveData.setSubscriptions(symbols)
    }

    // MARK: - Symbol Search

    func searchSymbols(query: String) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        return try await FinnhubProvider.shared.search(query: query)
    }

    func evaluateDataHealth(symbol: String) async -> DataHealth {
        var h = DataHealth(symbol: symbol)
        h.technical = CoverageComponent.present(quality: 0.5)
        return h
    }
}
