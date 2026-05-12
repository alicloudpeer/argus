import Foundation
import Combine

/// View-driven "şu an görünür sembol" izleyicisi. SwiftUI view'lar
/// `.onAppear` ile `enter(_:)`, `.onDisappear` ile `leave(_:)` çağırır.
///
/// Heimdall chain'leri bu set'e bakarak HOT vs WARM bandını seçer:
///   * **HOT** (sembol görünür): real-time öncelikli kaynaklar
///     (Alpaca IEX RT, Yahoo direct quote).
///   * **WARM** (sembol görünmez): periyodik refresh kaynakları
///     (Stooq batch, Yahoo backstop).
///
/// `MarketDataStore.userFocusedSymbol` zaten tek sembolü işaretliyordu;
/// HotSymbolTracker çoklu görünür sembolü destekler (chart panel +
/// markets sekmesi aynı anda 5+ sembol gösterebilir).
///
/// 2026-05-11 (Faz 1.6): minimal iskelet — `enter/leave` API ve
/// `Published` set. Heimdall chain'lerine `isHotView` parametresi
/// **Faz 2'de** eklenecek; şu an Alpaca varsa zaten her zaman primary
/// çalışıyor (HOT vs WARM ayrımı acil değil).
@MainActor
final class HotSymbolTracker: ObservableObject {
    static let shared = HotSymbolTracker()

    @Published private(set) var hotSymbols: Set<String> = []

    /// Sembol başına kaç view'ın görüntülediğini sayar — aynı sembol
    /// hem watchlist'te hem chart'ta açık olabilir, ikisi de
    /// `.onDisappear` çağırana kadar HOT kalır.
    private var refCount: [String: Int] = [:]

    private init() {}

    func enter(_ symbol: String) {
        let upper = symbol.uppercased()
        refCount[upper, default: 0] += 1
        hotSymbols.insert(upper)
    }

    func leave(_ symbol: String) {
        let upper = symbol.uppercased()
        let next = (refCount[upper] ?? 0) - 1
        if next <= 0 {
            refCount.removeValue(forKey: upper)
            hotSymbols.remove(upper)
        } else {
            refCount[upper] = next
        }
    }

    func isHot(_ symbol: String) -> Bool {
        hotSymbols.contains(symbol.uppercased())
    }

    /// Test / debug için sıfırla.
    func reset() {
        refCount.removeAll()
        hotSymbols.removeAll()
    }
}
