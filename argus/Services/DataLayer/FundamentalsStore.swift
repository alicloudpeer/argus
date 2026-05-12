import Foundation
import Combine

/// Unified Store for Fundamentals (Atlas Engine).
/// 2026-05-11: Mimir entegrasyon yer tutucuları kaldırıldı (modül silindi).
/// Eksik veri doldurma stratejisi Faz 2'de SEC EDGAR + FMP merge ile yeniden tasarlanacak.
@MainActor
final class FundamentalsStore: ObservableObject {
    static let shared = FundamentalsStore()

    @Published var financials: [String: DataValue<FinancialsData>] = [:]

    private init() {}

    // MARK: - Access
    func getFinancials(for symbol: String) -> FinancialsData? {
        return financials[symbol]?.value
    }

    // MARK: - Actions
    func fetchFinancials(symbol: String) async {
        // Cache Check — 24h for Fundamentals
        if let current = financials[symbol], !current.isStale, -current.provenance.fetchedAt.timeIntervalSinceNow < 86400 {
            return
        }

        do {
            let data = try await HeimdallOrchestrator.shared.requestFundamentals(symbol: symbol)

            let val = DataValue<FinancialsData>(
                value: data,
                provenance: DataProvenance(source: "Heimdall", fetchedAt: Date(), confidence: 1.0),
                status: .fresh
            )
            self.financials[symbol] = val

        } catch {
            print("📉 FundamentalsStore: Failed for \(symbol): \(error)")
            // Mark Stale
            if let current = financials[symbol] {
                financials[symbol] = DataValue(value: current.value, provenance: current.provenance, status: .stale)
            }
        }
    }
}
