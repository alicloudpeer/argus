import Foundation
import Combine

// MARK: - GorevOzeti

struct GorevOzeti {
    let toplamKarar: Int
    let alimSayisi: Int
    let satimSayisi: Int
    let pasSayisi: Int
    let engelSayisi: Int
}

// MARK: - GorevGunluguViewModel

@MainActor
final class GorevGunluguViewModel: ObservableObject {

    // MARK: - Filtre

    enum Filtre: String, CaseIterable, Identifiable {
        case tumKararlar   = "Tüm Kararlar"
        case alimlar       = "Alımlar"
        case satimlar      = "Satışlar"
        case pasGecilenler = "Pas Geçilenler"
        case engellenenler = "Engellenenler"

        var id: String { rawValue }
    }

    // MARK: - Published Properties

    @Published var seciliFiltre: Filtre = .tumKararlar
    @Published private(set) var anlatılar: [GorevAnlatisi] = []
    @Published private(set) var isLoading: Bool = false

    // MARK: - Summary

    var ozet: GorevOzeti {
        let tum = tumAnlatılar
        return GorevOzeti(
            toplamKarar: tum.count,
            alimSayisi:  tum.filter { $0.kararTipi == .alim }.count,
            satimSayisi: tum.filter { $0.kararTipi == .satim }.count,
            pasSayisi:   tum.filter { $0.kararTipi == .pasGecildi }.count,
            engelSayisi: tum.filter { $0.kararTipi == .engellendi }.count
        )
    }

    // MARK: - Private

    private var tumAnlatılar: [GorevAnlatisi] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        bind()
    }

    // MARK: - Combine Binding

    private func bind() {
        let decisionsPublisher = AutoPilotLogger.shared.$decisions
        let filterPublisher = $seciliFiltre

        // Decisions change -> rebuild all narratives, then apply filter
        decisionsPublisher
            .combineLatest(filterPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] decisions, filtre in
                guard let self else { return }
                self.rebuild(decisions: decisions, filtre: filtre)
            }
            .store(in: &cancellables)
    }

    private func rebuild(decisions: [AutoPilotDecision], filtre: Filtre) {
        isLoading = true

        // Map decisions to narratives, sorted newest-first
        let mapped = decisions
            .map { GorevNarrator.anlat($0) }
            .sorted { $0.timestamp > $1.timestamp }

        tumAnlatılar = mapped
        anlatılar = filtrele(mapped, filtre: filtre)
        isLoading = false
    }

    // MARK: - Filtering

    private func filtrele(_ items: [GorevAnlatisi], filtre: Filtre) -> [GorevAnlatisi] {
        switch filtre {
        case .tumKararlar:
            return items
        case .alimlar:
            return items.filter { $0.kararTipi == .alim }
        case .satimlar:
            return items.filter { $0.kararTipi == .satim }
        case .pasGecilenler:
            return items.filter { $0.kararTipi == .pasGecildi }
        case .engellenenler:
            return items.filter { $0.kararTipi == .engellendi }
        }
    }
}
