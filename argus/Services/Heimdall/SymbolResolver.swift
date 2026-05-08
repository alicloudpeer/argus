import Foundation

/// Errors thrown by `SymbolResolver` when a symbol cannot be sent to a
/// network provider.
enum SymbolResolverError: Error, LocalizedError {
    case emptySymbol
    case invalidCharacters(symbol: String)
    case tooLong(length: Int)

    var errorDescription: String? {
        switch self {
        case .emptySymbol:
            return "Sembol boş veya sadece boşluktan oluşuyor."
        case .invalidCharacters(let s):
            return "Sembol geçersiz karakter içeriyor: '\(s)'"
        case .tooLong(let n):
            return "Sembol çok uzun (\(n) karakter)."
        }
    }
}

/// Where a symbol should be routed in the new market data pipeline. The
/// orchestrator picks the provider chain based on this value rather than
/// hard-coding `.IS` and `=X` aliases throughout the codebase.
enum MarketDestination: String, Sendable {
    case bist
    case usEquity
    case forex
    case commodity
    case crypto
    case index
}

/// Resolves user-facing symbol aliases into the canonical form used by
/// the rest of the data pipeline and tells the orchestrator which
/// market a symbol belongs to.
struct SymbolResolver {
    static let shared = SymbolResolver()

    private let aliases: [String: String] = [
        "SILVER": "SI=F",
        "GOLD": "GC=F",
        "COPPER": "HG=F",
        "CRUDE_OIL": "CL=F",
        "OIL": "CL=F",
        "WTI": "CL=F",
        "CRUDE": "CL=F",
        "BRENT_OIL": "BZ=F",
        "BRENT": "BZ=F",
        "NAT_GAS": "NG=F",
        "VIX": "^VIX",
        "DXY": "DX-Y.NYB",
        "US10Y": "^TNX",
        "SPX": "^GSPC",
        "S&P500": "^GSPC",
        "SP500": "^GSPC",
        "NDX": "^IXIC",
        "DJI": "^DJI",
        "BTC": "BTC-USD",
        "ETH": "ETH-USD",
        "EURUSD": "EURUSD=X",
        "GBPUSD": "GBPUSD=X",
        "USDTRY": "USDTRY=X"
    ]

    func resolve(_ symbol: String) -> String {
        do {
            return try resolveStrict(symbol)
        } catch {
            print("⚠️ SymbolResolver: \(error.localizedDescription) — pass-through kullanılıyor.")
            return symbol.uppercased()
        }
    }

    /// Backwards compatible overload kept so existing call sites that
    /// pass a `ProviderTag` keep compiling. The provider tag is ignored
    /// in the new pipeline; routing happens via `marketDestination`.
    func resolve(_ symbol: String, for provider: ProviderTag) -> String {
        return resolve(symbol)
    }

    private static let allowedSymbolCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_^=&/")

    func resolveStrict(_ symbol: String) throws -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SymbolResolverError.emptySymbol }
        guard trimmed.count <= 20 else { throw SymbolResolverError.tooLong(length: trimmed.count) }

        if trimmed.unicodeScalars.contains(where: { !Self.allowedSymbolCharacters.contains($0) }) {
            throw SymbolResolverError.invalidCharacters(symbol: trimmed)
        }

        let upper = trimmed.uppercased()
        if let alias = aliases[upper] { return alias }
        if upper.hasSuffix(".IS") { return upper }
        if isBistSymbol(upper) { return "\(upper).IS" }
        return upper
    }

    /// Strict overload kept for source compatibility with callers that
    /// still pass a `ProviderTag`. The provider tag has no effect.
    func resolveStrict(_ symbol: String, for provider: ProviderTag) throws -> String {
        return try resolveStrict(symbol)
    }

    /// Determines which market a canonical symbol should be routed to.
    /// Accepts either bare or already-resolved symbols (e.g. `THYAO` and
    /// `THYAO.IS` both return `.bist`).
    func marketDestination(for symbol: String) -> MarketDestination {
        let upper = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasSuffix(".IS") || isBistSymbol(upper) { return .bist }
        if upper.hasSuffix("=X") { return .forex }
        if upper.hasSuffix("=F") { return .commodity }
        if upper.hasPrefix("^") || upper == "DX-Y.NYB" { return .index }
        if upper.contains("-USD") { return .crypto }
        return .usEquity
    }

    // MARK: - BIST detection

    private let bistSymbols: Set<String> = [
        "THYAO", "ASELS", "KCHOL", "AKBNK", "GARAN", "SAHOL", "TUPRS", "EREGL",
        "BIMAS", "SISE", "PETKM", "SASA", "HEKTS", "FROTO", "TOASO", "ENKAI",
        "ISCTR", "YKBNK", "VAKBN", "HALKB", "PGSUS", "TAVHL", "TCELL", "TTKOM",
        "KOZAL", "KOZAA", "TKFEN", "MGROS", "SOKM", "AEFES", "ARCLK", "ALARK",
        "ASTOR", "BBRYO", "BRSAN", "CIMSA", "DOAS", "EGEEN", "EKGYO", "ENJSA",
        "GESAN", "KONTR", "ODAS", "OYAKC", "SMRTG", "ULKER", "VESTL", "YEOTK",
        "GUBRF", "ISMEN", "AKSEN", "BERA", "DOHOL", "EUPWR", "GLYHO", "IPEKE",
        "KORDS", "LOGO", "MAVI", "NETAS", "OTKAR", "PRKME", "QUAGR", "RYGYO",
        "TURSG", "TTRAK", "ZOREN"
    ]

    func isBistSymbol(_ symbol: String) -> Bool {
        let upper = symbol.uppercased()
        if upper.hasSuffix(".IS") { return true }
        return bistSymbols.contains(upper)
    }

    /// Strips `.IS` so the bare ticker can be sent to BorsaPy.
    static func bareBistSymbol(_ symbol: String) -> String {
        symbol.uppercased().replacingOccurrences(of: ".IS", with: "")
    }
}
