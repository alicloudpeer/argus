import Foundation

/// Legacy facade that pre-dates `MarketDataStore`. Kept around because a
/// few view models still import it; routes through `HeimdallOrchestrator`
/// so the new pipeline is the sole source of truth.
@available(*, deprecated, message: "Use MarketDataStore / HeimdallOrchestrator instead")
class APIService {
    static let shared = APIService()

    private init() {}

    func fetchCandles(symbol: String, resolution: String = "D") async -> [Candle] {
        let timeframe = Self.timeframe(for: resolution)
        do {
            return try await HeimdallOrchestrator.shared.requestCandles(symbol: symbol, timeframe: timeframe, limit: 365)
        } catch {
            print("APIService candle fetch failed for \(symbol): \(error.localizedDescription)")
            return []
        }
    }

    func fetchQuote(symbol: String) async -> Quote? {
        do {
            return try await HeimdallOrchestrator.shared.requestQuote(symbol: symbol)
        } catch {
            print("APIService quote fetch failed for \(symbol): \(error.localizedDescription)")
            return nil
        }
    }

    func getDiscoverCategories() -> [MarketCategory] { [] }

    private static func timeframe(for resolution: String) -> String {
        switch resolution {
        case "1":  return "1m"
        case "5":  return "5m"
        case "15": return "15m"
        case "30": return "30m"
        case "60": return "1h"
        case "D":  return "1d"
        case "W":  return "1week"
        case "M":  return "1month"
        default:   return "1d"
        }
    }
}
