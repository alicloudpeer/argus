import Combine
import Foundation
import SwiftUI

/// Faz 1.A.2: Karar Kartı V2 ViewModel.
///
/// Dört bölümün UI verisini hazırlar:
/// 1. **Aksiyon özeti** — Action başlığı + tahmini pozisyon büyüklüğü
/// 2. **Top modüller** — En yüksek 3 contributor (modül adı, score, weight)
/// 3. **Güven özeti** — Confidence yüzdesi + top modülün `ModulePerformanceTracker`
///    hit rate'i + düşük güven/AISignal rozetleri (Task 8/10 hijyen)
/// 4. **Premortem** — `PremortemEngine` üretiminden 3 risk senaryosu
///
/// Mevcut `ArgusGrandDecision`/`ModulePerformanceTracker`/`PremortemEngine` API'sini
/// okur, yazmaz. Council kararına dokunmaz.
@MainActor
final class KararKartiViewModel: ObservableObject {

    // MARK: - Section 1: Aksiyon

    @Published private(set) var aksiyonBaslik: String = "GÖZLE"
    @Published private(set) var aksiyonRengi: Color = .gray
    @Published private(set) var pozisyonTahmin: String = "—"

    // MARK: - Section 2: Top Modüller

    /// UI'da iter edilebilir modül satırı. UUID 'id' ile ForEach uyumlu.
    struct ModulSatir: Identifiable, Equatable {
        let id = UUID()
        /// Türkçe display name — UI'da bu görünür ("Orion teknik" gibi).
        let displayName: String
        /// Modülün ham confidence skoru (0-100 ölçek).
        let score: Int
        /// Modülün katkı ağırlığı (Council confidence * Council ağırlığı,
        /// görsel olarak ne kadar belirleyici olduğu — 0.0-1.0 arası).
        let weight: Double

        static func == (lhs: ModulSatir, rhs: ModulSatir) -> Bool {
            lhs.displayName == rhs.displayName
                && lhs.score == rhs.score
                && abs(lhs.weight - rhs.weight) < 0.001
        }
    }

    @Published private(set) var topModuller: [ModulSatir] = []

    // MARK: - Section 3: Güven

    @Published private(set) var confidencePercent: Int = 0
    /// "Son N kararda kâra dönen sayı" — top modülün hit rate'ine dayanır.
    @Published private(set) var hitRateText: String = "Henüz veri yok"
    /// Confidence < %30 ise sarı rozet (Task 10 hijyen — düşük güven göstergesi).
    @Published private(set) var dusukGuvenRozeti: Bool = false
    /// AISignal in-sample backtest verisi karar destekliyorsa turuncu rozet (Task 8).
    @Published private(set) var aiSignalRozeti: Bool = false

    // MARK: - Section 4: Premortem

    @Published private(set) var riskler: [PremortemEngine.RiskScenario] = []

    // MARK: - Preparation

    /// Karar kartını verilen `ArgusGrandDecision` ve dış bağlam ile hazırla.
    /// Bu metod 4 bölümü doldurur — sonra View binding ile render eder.
    ///
    /// - Parameters:
    ///   - decision: Council kararı.
    ///   - atlasMargin: Premortem için Atlas marginOfSafety (nil → veri yok).
    ///   - demeterScore: Premortem için Demeter totalScore (nil → veri yok).
    ///   - aetherScore: Premortem makro değerlendirmesi için.
    ///   - clusterCount: Aynı cluster'daki açık trade sayısı.
    ///   - hasAISignalSupport: AISignalService data mining sinyaliyle aynı yöne mi?
    ///   - estimatedPositionTRY: UI tahmini pozisyon büyüklüğü (TRY, 0 ise "—").
    func prepare(
        from decision: ArgusGrandDecision,
        atlasMargin: Double?,
        demeterScore: Double?,
        aetherScore: Double,
        clusterCount: Int,
        hasAISignalSupport: Bool,
        estimatedPositionTRY: Double
    ) async {
        // Bölüm 1: Aksiyon
        aksiyonBaslik = decision.action.rawValue   // HÜCUM/BİRİKTİR/GÖZLE/AZALT/ÇIK
        aksiyonRengi = Self.color(for: decision.action)
        pozisyonTahmin = Self.formatPosition(estimatedPositionTRY)

        // Bölüm 2: Top 3 modül (confidence-sıralı)
        topModuller = Self.buildTopModules(from: decision.contributors)

        // Bölüm 3: Güven + rozetler
        confidencePercent = Int((decision.confidence * 100).rounded())
        dusukGuvenRozeti = decision.confidence < 0.30
        aiSignalRozeti = hasAISignalSupport
        hitRateText = await Self.hitRateText(forTopModule: topModuller.first?.displayName)

        // Bölüm 4: Premortem
        riskler = PremortemEngine.generate(
            action: decision.action,
            aetherScore: aetherScore,
            orionScore: Self.extractOrionScore(from: decision),
            atlasMarginOfSafety: atlasMargin,
            demeterTotalScore: demeterScore,
            clusterConcentration: clusterCount
        )
    }

    // MARK: - Helpers

    /// Action → renk eşlemesi (mevcut ArgusAction.colorName'den).
    static func color(for action: ArgusAction) -> Color {
        switch action {
        case .aggressiveBuy: return .green
        case .accumulate:    return .blue
        case .neutral:       return .gray
        case .trim:          return .orange
        case .liquidate:     return .red
        }
    }

    /// Pozisyon büyüklüğü TRY formatla — "₺3,200" gibi. 0 → "—".
    static func formatPosition(_ amount: Double) -> String {
        guard amount > 0 else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
        return "₺\(formatted)"
    }

    /// Mitolojik modül adı → Türkçe display name. Memory naming kuralı uyumlu
    /// (identifier mitolojik, UI Türkçe).
    static func displayName(forModule module: String) -> String {
        switch module.lowercased() {
        case "orion":           return "Orion teknik"
        case "orion patterns":  return "Formasyon"
        case "atlas":           return "Atlas bilanço"
        case "aether":          return "Aether makro"
        case "hermes":          return "Hermes haber"
        case "phoenix":         return "Phoenix dönüş"
        case "athena":          return "Athena faktör"
        case "demeter":         return "Demeter sektör"
        case "prometheus":      return "Prometheus tahmin"
        case "poseidon":        return "Poseidon akıllı para"
        default:                return module   // Bilinmeyen modül adıyla göster
        }
    }

    /// Contributors içinden top 3 (confidence-sıralı) ModulSatir döndür.
    static func buildTopModules(from contributors: [ModuleContribution]) -> [ModulSatir] {
        contributors
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map { contrib in
                ModulSatir(
                    displayName: Self.displayName(forModule: contrib.module),
                    score: Int((contrib.confidence * 100).rounded()),
                    weight: contrib.confidence  // Ham confidence — UI'da × ile gösterilir
                )
            }
    }

    /// "Henüz veri yok" veya "Son 60 sinyalde %P doğruluk (N=X)" gibi hit rate metni.
    static func hitRateText(forTopModule displayName: String?) async -> String {
        guard let display = displayName else { return "Henüz veri yok" }
        // Display adı geri çevirip identifier'ı bul (Orion teknik → Orion)
        let canonicalModule = Self.canonicalName(for: display)
        let stats = await ModulePerformanceTracker.shared.getStats(module: canonicalModule)
        let decisive = stats.correctVotes + stats.incorrectVotes
        guard decisive > 0 else { return "Henüz veri yok (modül kararsız)" }
        let pct = Int((stats.hitRate * 100).rounded())
        return "Son \(decisive) decisive oyda %\(pct) doğruluk"
    }

    /// Türkçe display name → mitolojik canonical name (ModulePerformanceTracker
    /// stats anahtarı). displayName(forModule:)'ın tersi.
    static func canonicalName(for displayName: String) -> String {
        switch displayName {
        case "Orion teknik":         return "Orion"
        case "Formasyon":            return "Orion Patterns"
        case "Atlas bilanço":        return "Atlas"
        case "Aether makro":         return "Aether"
        case "Hermes haber":         return "Hermes"
        case "Phoenix dönüş":        return "Phoenix"
        case "Athena faktör":        return "Athena"
        case "Demeter sektör":       return "Demeter"
        case "Prometheus tahmin":    return "Prometheus"
        case "Poseidon akıllı para": return "Poseidon"
        default:                     return displayName
        }
    }

    /// Premortem'in `orionScore` parametresi için contributors içinden Orion'u çıkar.
    /// Yoksa default 50 (nötr) döner — Premortem cluster kuralı zaten orion < 50 +
    /// cluster > 3 ikili koşul; 50'lık nötr cluster kuralını tetiklemez (cluster fazla
    /// olsa bile orion zayıf değil sayılır).
    static func extractOrionScore(from decision: ArgusGrandDecision) -> Double {
        if let orion = decision.contributors.first(where: { $0.module.lowercased() == "orion" }) {
            return orion.confidence * 100
        }
        return 50.0
    }
}
