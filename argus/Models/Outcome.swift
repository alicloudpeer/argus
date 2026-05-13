import Foundation

// MARK: - Outcome (Ledger Üçüncü Katman)
/// Decision → Trade → **Outcome** zincirinin kapanış halkası.
/// Her trade kapandığında ledger'a outcome insert edilir; realized PnL, holding süresi,
/// R-multiple ve exit reason saklanır. Van Tharp (1998) "1 birim risk için kaç birim kâr"
/// sorusunu cevaplayan bilimsel ölçü R-multiple olmadan Sharpe + Win Rate eksik kalır.
///
/// MAE/MFE alanları ilk versiyonda `nil`. Faz 2'de QuoteHandler tick-by-tick güncelleme
/// ile populated edilecek (Maximum Adverse Excursion / Maximum Favorable Excursion).
struct Outcome: Codable, Equatable {
    let outcomeId: UUID
    let tradeId: UUID
    let realizedPnL: Double
    let realizedPnLPct: Double
    let holdingMinutes: Int
    /// R-multiple = (exitPrice - entryPrice) / (entryPrice - initialStop).
    /// `initialStop` yoksa veya geçersizse (stop ≥ entry, long pozisyon için) `nil`.
    let rMultiple: Double?
    /// Maximum Adverse Excursion (% açılış fiyatına göre en düşük noktaya gidiş).
    /// İlk versiyonda her zaman `nil` — Faz 2 QuoteHandler tick-by-tick.
    let maePct: Double?
    /// Maximum Favorable Excursion (% açılış fiyatına göre en yüksek noktaya gidiş).
    /// İlk versiyonda her zaman `nil` — Faz 2 QuoteHandler tick-by-tick.
    let mfePct: Double?
    let exitReason: String
    let closedAt: Date
}
