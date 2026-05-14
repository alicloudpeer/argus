import Foundation

/// Serves Financial Snaphots for Atlas Council and UI.
/// Bridges the gap between Raw Provider Data (FinancialsData) and Domain Model (FinancialSnapshot).
actor FinancialSnapshotService {
    static let shared = FinancialSnapshotService()

    // 2026-05-04: HeimdallOrchestrator üzerinden çağrı yapıyoruz.
    // Eski hâl: `YahooFinanceProvider.shared` direkt — RequestCoalescer, CircuitBreaker,
    // SymbolBlocklist, DataCacheService fallback'lerini tamamen by-pass ediyordu.
    // Sonuç: AutoPilot 304 sembol × 2 Yahoo isteği × her tarama → çoğu timeout →
    // try? ile sessizce nil → Council snapshot:nil ile konvene → üyeler "Veri yok"
    // der → confidence ~0/1 → AutoPilotEngine veto eder veya TradeBrain reddeder.
    // Yeni: orchestrator'dan geçtiğimiz için coalesce + 24h fundamentals cache +
    // stale fallback aktif. Aynı sembol 24h içinde 1 kere Yahoo'ya gider, sonrası cache.

    /// Snapshot-level cache: mapToSnapshot iş gücünü ve aynı pencerede tekrar
    /// fetch'i önler. Fundamentals saatlik değişir, snapshot daha sık invalidate olabilir.
    private var snapshotCache: [String: (snapshot: FinancialSnapshot, fetchedAt: Date)] = [:]
    private let snapshotTTL: TimeInterval = 1800 // 30 dakika

    private init() {}

    /// Fetches a complete financial snapshot for a symbol
    func fetchSnapshot(symbol: String) async throws -> FinancialSnapshot {
        // 1. Snapshot-level cache hit?
        if let cached = snapshotCache[symbol],
           Date().timeIntervalSince(cached.fetchedAt) < snapshotTTL {
            return cached.snapshot
        }

        // 2. HeimdallOrchestrator üzerinden — coalesced + cache fallback aktif
        let financials = try await HeimdallOrchestrator.shared.requestFundamentals(symbol: symbol)
        let quote = try await HeimdallOrchestrator.shared.requestQuote(symbol: symbol)

        let snapshot = mapToSnapshot(data: financials, quote: quote)
        snapshotCache[symbol] = (snapshot: snapshot, fetchedAt: Date())
        return snapshot
    }

    /// Fetches raw data AND snapshot in one go (for efficient reuse)
    func fetchComprehensiveData(symbol: String) async throws -> (financials: FinancialsData, quote: Quote, snapshot: FinancialSnapshot) {
        let financials = try await HeimdallOrchestrator.shared.requestFundamentals(symbol: symbol)
        let quote = try await HeimdallOrchestrator.shared.requestQuote(symbol: symbol)
        let snapshot = mapToSnapshot(data: financials, quote: quote)
        snapshotCache[symbol] = (snapshot: snapshot, fetchedAt: Date())
        return (financials, quote, snapshot)
    }
    
    private func mapToSnapshot(data: FinancialsData, quote: Quote) -> FinancialSnapshot {
        return FinancialSnapshot(
            symbol: data.symbol,
            marketCap: data.marketCap ?? data.enterpriseValue, // Fallback to EV if Cap missing
            price: quote.c,
            
            // Valuation
            peRatio: data.peRatio,
            forwardPE: data.forwardPERatio,
            pbRatio: data.priceToBook,
            psRatio: data.priceToSales,
            evToEbitda: data.evToEbitda,
            
            // Growth
            revenueGrowth: data.revenueGrowth,
            earningsGrowth: data.earningsGrowth,
            epsGrowth: nil, // Not directly in FinancialsData yet
            
            // Quality
            roe: data.returnOnEquity,
            roa: data.returnOnAssets,
            debtToEquity: data.debtToEquity,
            currentRatio: data.currentRatio,
            grossMargin: data.grossMargin,
            operatingMargin: data.operatingMargin,
            netMargin: data.profitMargin,
            
            // Dividend
            dividendYield: data.dividendYield,
            payoutRatio: nil, // Not mapped yet
            dividendGrowth: nil,
            
            // Other
            beta: nil, // Could be in stats but not in FinancialsData struct explicitly named beta? Check struct.
            sharesOutstanding: nil,
            floatShares: nil,
            insiderOwnership: nil,
            institutionalOwnership: nil,
            
            // Sector (Not available in pure FinancialsData, needs Profile)
            sectorPE: nil,
            sectorPB: nil,
            
            // Analyst Expectations
            targetMeanPrice: data.targetMeanPrice,
            targetHighPrice: data.targetHighPrice,
            targetLowPrice: data.targetLowPrice,
            recommendationMean: data.recommendationMean,
            analystCount: data.numberOfAnalystOpinions,
            lastUpdated: nil
        )
    }
}
