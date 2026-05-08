import Foundation
import Combine

/// BIST quote/history facade. Routes to BorsaPyProvider through the
/// Heimdall pipeline. Older call sites depend on `BistTicker` / `BistCandle`
/// shapes so we adapt the shared models here.
class BistDataService: ObservableObject {
    static let shared = BistDataService()

    private let provider = BorsaPyProvider.shared

    func fetchQuote(symbol: String) async throws -> BistTicker {
        let bare = symbol.uppercased().replacingOccurrences(of: ".IS", with: "")
        let formatted = "\(bare).IS"
        let bist = try await provider.getBistQuote(symbol: bare)
        let prevClose = bist.previousClose > 0 ? bist.previousClose : bist.last
        let change = bist.last - prevClose
        let changePct = prevClose > 0 ? (change / prevClose) * 100 : 0
        return BistTicker(
            symbol: formatted,
            shortSymbol: bare,
            companyName: nil,
            price: bist.last,
            change: change,
            changePercent: changePct,
            volume: bist.volume,
            lastUpdated: bist.timestamp
        )
    }

    func fetchHistory(symbol: String, interval: String = "15m", range: String = "5d") async throws -> [BistCandle] {
        let bare = symbol.uppercased().replacingOccurrences(of: ".IS", with: "")
        let history = try await provider.getBistHistory(symbol: bare, days: Self.days(for: range))
        return history.map { BistCandle(date: $0.date, open: $0.open, high: $0.high, low: $0.low, close: $0.close, volume: $0.volume) }
    }

    func testConnection(symbol: String = "THYAO") async {
        do {
            let ticker = try await fetchQuote(symbol: symbol)
            print("BIST connection ok: \(ticker.shortSymbol) \(ticker.price)")
        } catch {
            print("BIST connection failed: \(error.localizedDescription)")
        }
    }

    private static func days(for range: String) -> Int {
        switch range.lowercased() {
        case "1d":  return 1
        case "5d":  return 5
        case "1mo": return 30
        case "3mo": return 90
        case "6mo": return 180
        case "1y":  return 365
        case "5y":  return 1825
        default:    return 30
        }
    }
}

enum BistDataError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case noData
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Geçersiz URL: \(url)"
        case .invalidResponse: return "Sunucu yanıtı geçersiz"
        case .noData: return "Veri bulunamadı"
        case .parseFailed: return "Veri işlenemedi"
        }
    }
}
