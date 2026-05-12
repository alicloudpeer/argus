
import Foundation
import Combine

/// Sirkiye (BIST/Altın/Fon) Ekranı için Ana ViewModel
/// Global MarketDataProvider'dan BAĞIMSIZ çalışır.
/// 2026-05-11: DovizCom kaldırıldı (yarım ölü modül, `.phoenixDetail` route hiç tetiklenmiyordu).
/// Gram altın/gümüş için Frankfurter (Faz 1) eklendiğinde buraya geri bağlanır.
class SirkiyeViewModel: ObservableObject {
    @Published var bistTickers: [String: BistTicker] = [:]
    @Published var funds: [String: FundDetail] = [:]

    @Published var isLoading = false
    @Published var errorMessage: String?

    // Services
    private let bistService = BistDataService.shared
    private let tefasService = TefasService.shared

    // BIST İzleme Listesi (Örnek)
    private let bistWatchlist = ["THYAO", "ASELS", "GARAN", "EREGL", "SISE"]

    init() {
        // Initial load
    }

    // MARK: - Data Fetching

    func refreshAll() async {
        await MainActor.run { isLoading = true }

        await fetchBistWatchlist()

        await MainActor.run { isLoading = false }
    }

    // MARK: - BIST Operations

    private func fetchBistWatchlist() async {
        await withTaskGroup(of: BistTicker?.self) { group in
            for symbol in bistWatchlist {
                group.addTask {
                    try? await self.bistService.fetchQuote(symbol: symbol)
                }
            }

            for await ticker in group {
                if let t = ticker {
                    await MainActor.run {
                        self.bistTickers[t.shortSymbol] = t
                    }
                }
            }
        }
    }

    // MARK: - TEFAS Operations

    func fetchFundDetail(code: String) async {
        // TEFAS Service henüz tam detail endpointine sahip değil, history üzerinden mockluyoruz.
        // İleride burası güncellenecek.
        // FundDetailView kendi datasını yüklüyor, burası global bir fon listesi için olabilir.
    }
}
