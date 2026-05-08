import Foundation

/// Thin facade that delegates to `HeimdallOrchestrator`. Older code
/// imports this; the orchestrator is the canonical entry point.
@MainActor
final class ArgusDataService {
    static let shared = ArgusDataService()

    private let orchestrator = HeimdallOrchestrator.shared
    private let fred = FredProvider.shared

    private init() {}

    func fetchQuote(symbol: String) async throws -> Quote {
        return try await orchestrator.requestQuote(symbol: symbol)
    }

    func fetchCandles(symbol: String, timeframe: String = "1D", limit: Int = 200) async throws -> [Candle] {
        return try await orchestrator.requestCandles(symbol: symbol, timeframe: timeframe, limit: limit)
    }

    func fetchFundamentals(symbol: String) async throws -> FinancialsData {
        return try await orchestrator.requestFundamentals(symbol: symbol)
    }

    func fetchNews(symbol: String, limit: Int = 10) async throws -> [NewsArticle] {
        if symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol) {
            let rss = RSSNewsProvider()
            return try await rss.fetchNews(symbol: symbol, limit: limit)
        }
        return try await orchestrator.requestNews(symbol: symbol, limit: limit)
    }

    func fetchScreener(type: ScreenerType, limit: Int = 10) async throws -> [Quote] {
        return try await orchestrator.requestScreener(type: type, limit: limit)
    }

    func fetchFredSeries(seriesId: String, limit: Int = 24) async throws -> [(Date, Double)] {
        return try await fred.fetchSeries(seriesId: seriesId, limit: limit)
    }

    func checkHealth() async -> Bool {
        let status = await orchestrator.checkSystemHealth()
        return status == .operational
    }
}
