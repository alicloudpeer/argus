import Foundation

/// Faz 1.A Task 1: Statik kural-bazlı 3 risk senaryosu üretici.
///
/// Yol Haritası §3.8 ("Neyi unuttum?" — premortem) uygulaması. Karar kartı V2'nin
/// dördüncü bölümü için 3'e kadar risk senaryosu üretir.
///
/// **LLM çağrısı YOK** — ilk versiyon deterministik kurallar. Council/Aether/Atlas/
/// Demeter snapshot'larından çekilen primitive değerlere bakar; hangi statik kural
/// tetiklenirse o senaryo üretilir. Belirli koşullara bağımlı olduğu için test'lerde
/// her kural ayrı senaryoyla doğrulanabilir.
///
/// Tasarım kararı: Struct snapshot'lar yerine `Double?` ve `Int` parametreler
/// alıyor — test'lerde 11 alanlık AtlasDecision mock'lamaya gerek yok, ViewModel
/// kendi extraction'ını yapıp engine'i çağırır.
struct PremortemEngine {

    /// Tek bir risk senaryosu. UI'da kart olarak gösterilir.
    struct RiskScenario: Identifiable, Equatable {
        let id = UUID()
        /// Kısa kategori — UI rozetinde kullanılır ("Makro", "Sektör", ...)
        let trigger: String
        /// Tam Türkçe cümle — kullanıcının okuyacağı senaryo.
        let scenario: String
        let severity: Severity

        enum Severity: Equatable {
            case low, medium, high
        }

        // Identifiable + Equatable beraber kullanılırken `id` UUID() default
        // her instance için farklı; Equatable manuel — sadece trigger/scenario/severity
        // karşılaştırılır (UI snapshot karşılaştırması için).
        static func == (lhs: RiskScenario, rhs: RiskScenario) -> Bool {
            lhs.trigger == rhs.trigger
                && lhs.scenario == rhs.scenario
                && lhs.severity == rhs.severity
        }
    }

    /// En fazla 3 senaryo döner; hiçbir kural tetiklenmezse 1 fallback ile yine
    /// boş dönmez — kullanıcı her zaman en az bir uyarı görür ("küçük başla").
    ///
    /// - Parameters:
    ///   - action: Council kararı — sadece `.aggressiveBuy`/`.accumulate` için sektör
    ///     momentum tetiklenir (SAT/AZALT eylemlerinde sektör momentum farklı yorumlanır).
    ///   - aetherScore: Makro skor (0-100). < 50 ise makro risk uyarısı.
    ///   - orionScore: Teknik skor (0-100). < 50 + cluster yoğun ise likidite uyarısı.
    ///   - atlasMarginOfSafety: AtlasDecision.marginOfSafety. nil veya < 0 ise bilanço
    ///     destek vermiyor; teknik tek başına kalıyor demek.
    ///   - demeterTotalScore: DemeterScore.totalScore. nil veya < 40 ise sektör
    ///     momentum negatif — BUY kararlarında uyarı.
    ///   - clusterConcentration: Açık trade sayısı, aynı cluster içinde. > 3 ise
    ///     korelasyon kriz riski.
    static func generate(
        action: ArgusAction,
        aetherScore: Double,
        orionScore: Double,
        atlasMarginOfSafety: Double?,
        demeterTotalScore: Double?,
        clusterConcentration: Int
    ) -> [RiskScenario] {
        var scenarios: [RiskScenario] = []

        // Kural 1: Makro risk — Aether < 50
        if aetherScore < 50 {
            let severity: RiskScenario.Severity = aetherScore < 30 ? .high : .medium
            scenarios.append(.init(
                trigger: "Makro",
                scenario: "BIST-100 endeksi günü -%2'den fazla düşerse stop tetiklenir (Aether \(Int(aetherScore))).",
                severity: severity
            ))
        }

        // Kural 2: Atlas zayıf destek — marginOfSafety negatif veya nil
        // Bu, Atlas bilanço motorunun "değer puanı" verisidir. Negatifse hisse
        // intrinsik değerinin üzerinde fiyatlanıyor; teknik sinyal tek başına kalıyor.
        let isBuyAction = action == .aggressiveBuy || action == .accumulate
        if isBuyAction, let mos = atlasMarginOfSafety, mos < 0 {
            scenarios.append(.init(
                trigger: "Bilanço",
                scenario: "Atlas bilanço destek vermiyor (marginOfSafety \(String(format: "%.0f%%", mos * 100))) — teknik tek dayanak.",
                severity: .medium
            ))
        } else if isBuyAction, atlasMarginOfSafety == nil {
            // Atlas hiç koşulmadıysa (kripto/FX) veya veri yoksa — uyarı seviyesi düşük
            scenarios.append(.init(
                trigger: "Bilanço",
                scenario: "Atlas bilanço motoru bu sembol için veri üretmedi; sinyal sadece teknik/makro.",
                severity: .low
            ))
        }

        // Kural 3: Sektör momentum tersi
        if isBuyAction, let demeter = demeterTotalScore, demeter < 40 {
            scenarios.append(.init(
                trigger: "Sektör",
                scenario: "Sektör momentum zayıf (Demeter \(Int(demeter))) — regülasyon veya sektör haberi boşluklu açılışa yol açabilir.",
                severity: demeter < 25 ? .high : .medium
            ))
        }

        // Kural 4: Likidite + cluster konsantrasyon
        if orionScore < 50 && clusterConcentration > 3 {
            scenarios.append(.init(
                trigger: "Likidite",
                scenario: "Cluster'da \(clusterConcentration) açık pozisyon — teknik zayıf, korelasyon krizinde topluca düşüş riski.",
                severity: .medium
            ))
        }

        // En fazla 3 senaryo
        if scenarios.count > 3 {
            scenarios = Array(scenarios.prefix(3))
        }

        // Fallback: hiç tetiklenmediyse, kullanıcıya en az bir uyarı göster.
        if scenarios.isEmpty {
            scenarios.append(.init(
                trigger: "Genel",
                scenario: "Bu sinyal pattern'inin son 60 örneklemdeki başarı oranı henüz ölçülmedi — küçük pozisyonla başla.",
                severity: .low
            ))
        }

        return scenarios
    }
}
