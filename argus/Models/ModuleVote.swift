import Foundation

// MARK: - Task 11 (2026-05-13): Module Performance Karnesi
//
// Council convene anında her bir Council üyesinin (Orion, Atlas, Aether,
// Hermes, Phoenix, Athena, Demeter, Prometheus, Poseidon) oyu — module +
// action ("buy"/"sell"/"hold", kanonik İngilizce) + confidence (0..1) —
// `ArgusLedger`'ın `DecisionEvent` payload'ında `module_votes` JSON dizisi
// olarak saklanır. Trade kapanışında `ModulePerformanceTracker` her oyu
// gerçekleşmiş PnL yönü ile karşılaştırır → modül başına `correctVotes /
// totalVotes` istatistiği üretir.
//
// İsim çakışması notu: `argus/Models/SignalModels.swift` içinde aynı isimli
// `ModuleVote` mevcut (alanlar: score/direction/confidence — `DecisionContext`
// içinde kullanılıyor, farklı semantik). Çakışmayı önlemek için Task 11
// kayıt tipi `ModuleVoteRecord` olarak yeniden adlandırıldı; sözlü iletişimde
// "modül oyu" terimini koruyoruz.
//
// `action` alanı canonical İngilizce ("buy"/"sell"/"hold") tutulur — Argus
// içinde `ProposedAction.rawValue` Türkçe ("AL"/"SAT"/"BEKLE"), bu sınır
// noktasında `ProposedAction → canonicalActionString` ile çevrilir. Saklama
// formatı kararlı kalır, UI yine Türkçe gösterir.
struct ModuleVoteRecord: Codable, Equatable, Hashable, Sendable {
    /// Council üyesinin adı — "Orion", "Atlas", "Aether", "Hermes", "Phoenix",
    /// "Athena", "Demeter", "Prometheus", "Poseidon" gibi. Mitolojik isimler
    /// identifier seviyesinde sabit (kullanıcı tercihi — naming hibrit kuralı).
    let module: String

    /// Canonical İngilizce: "buy" / "sell" / "hold". `ProposedAction` enum'undan
    /// `ProposedAction.canonicalActionString` ile üretilir. UI Türkçe değerleri
    /// ayrı düzeyde sağlar; ledger ve performance tracker bu kanonik formu okur.
    let action: String

    /// 0.0 ile 1.0 arasında, modülün karara katkı gücü. `ModuleContribution`'ın
    /// `confidence` alanına 1:1 karşılık gelir (zaten 0..1 normalize edilmiş).
    let confidence: Double
}
