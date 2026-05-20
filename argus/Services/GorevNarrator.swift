import Foundation

// MARK: - Output Model

struct GorevAnlatisi: Identifiable, Sendable {
    let id: UUID
    let kararTipi: GorevNarrator.KararTipi
    let dominantFaktor: GorevNarrator.DominantFaktor
    let aciklama: String
    let miktarAciklamasi: String?
    let symbol: String
    let quantity: Double
    let price: Double?
    let stopLoss: Double?
    let takeProfit: Double?
    let timestamp: Date
}

// MARK: - GorevNarrator

/// Deterministic narrative engine that converts an `AutoPilotDecision` into
/// a human-readable Turkish explanation. No LLM, purely rule-based.
enum GorevNarrator {

    // MARK: - KararTipi

    enum KararTipi: String, Sendable {
        case alim
        case satim
        case pasGecildi
        case engellendi

        var baslik: String {
            switch self {
            case .alim:        return "Alım"
            case .satim:       return "Satış"
            case .pasGecildi:  return "Pas Geçildi"
            case .engellendi:  return "Engellendi"
            }
        }

    }

    // MARK: - DominantFaktor

    enum DominantFaktor: Sendable {
        case veriKalitesi(skor: Double)
        case zamanlama(sebep: String)
        case veto(sebep: String)
        case riskLimiti(carpan: Double)
        case haber(baslik: String)
        case teknikGuc(skor: Double)
        case temelGuc(skor: Double)
        case makroOrtam(skor: Double)
        case tahmin(yuzde: Double)
        case genelUzlasi(puan: Double)

        var etiket: String {
            switch self {
            case .veriKalitesi:  return "Veri Kalitesi"
            case .zamanlama:     return "Zamanlama"
            case .veto:          return "Veto"
            case .riskLimiti:    return "Risk Limiti"
            case .haber:         return "Haber"
            case .teknikGuc:     return "Teknik"
            case .temelGuc:      return "Temel"
            case .makroOrtam:    return "Makro"
            case .tahmin:        return "Tahmin"
            case .genelUzlasi:   return "Konsensus"
            }
        }
    }

    // MARK: - Public API

    static func anlat(_ decision: AutoPilotDecision) -> GorevAnlatisi {
        let tip = kararTipiBelirle(decision)
        let faktor = dominantFaktorBelirle(decision)
        let aciklama = anlatimUret(tip: tip, faktor: faktor, decision: decision)
        let miktar = miktarAciklamasiUret(decision)

        return GorevAnlatisi(
            id: decision.id,
            kararTipi: tip,
            dominantFaktor: faktor,
            aciklama: aciklama,
            miktarAciklamasi: miktar,
            symbol: decision.symbol,
            quantity: decision.quantity,
            price: decision.price,
            stopLoss: decision.stopLoss,
            takeProfit: decision.takeProfit,
            timestamp: decision.timestamp
        )
    }

    // MARK: - KararTipi Classification

    private static func kararTipiBelirle(_ d: AutoPilotDecision) -> KararTipi {
        let action = d.action.lowercased()
        switch action {
        case "buy":
            return .alim
        case "sell":
            return .satim
        case "skip", "hold":
            return rationaleEngelMi(d.rationale) ? .engellendi : .pasGecildi
        default:
            return .pasGecildi
        }
    }

    /// `true` if the rationale contains cooldown / guard / block / veto hints.
    private static func rationaleEngelMi(_ rationale: String?) -> Bool {
        guard let r = rationale?.lowercased() else { return false }
        let engelIpuclari = [
            "cooldown", "bekleme", "dk kaldı", "veto", "engel",
            "block", "guard", "red", "reddedildi", "risk vetosu",
            "tekrar giriş", "tutma süresi"
        ]
        return engelIpuclari.contains { r.contains($0) }
    }

    // MARK: - DominantFaktor Resolution (priority cascade)

    private static func dominantFaktorBelirle(_ d: AutoPilotDecision) -> DominantFaktor {
        // Priority 1: Data quality issue
        if let dq = d.dataQualityScore, dq < 70 {
            return .veriKalitesi(skor: dq)
        }

        let rationale = d.rationale ?? ""
        let rLow = rationale.lowercased()

        // Priority 2: Timing / cooldown
        if rLow.contains("cooldown") || rLow.contains("dk kaldı")
            || rLow.contains("bekleme") || rLow.contains("tutma süresi") {
            let sebep = zamanlamaSebebiParsla(rationale)
            return .zamanlama(sebep: sebep)
        }

        // Priority 3: Veto
        if rLow.contains("veto") || rLow.contains("engel")
            || rLow.contains("reddedildi") || rLow.contains("block") {
            let sebep = vetoSebebiParsla(rationale)
            return .veto(sebep: sebep)
        }

        // Priority 4: Risk limit
        if let rm = d.riskMultiple, rm < 0.4 {
            return .riskLimiti(carpan: rm)
        }

        // Priority 5: News impact (hermesScore > 70)
        if let hs = d.hermesScore, hs > 70 {
            let baslik = haberBasligiParsla(rationale)
            return .haber(baslik: baslik)
        }

        // Priority 6-8: Highest module score > 60
        let scores: [(Double?, (Double) -> DominantFaktor)] = [
            (d.orionScore,  { .teknikGuc(skor: $0) }),
            (d.atlasScore,  { .temelGuc(skor: $0) }),
            (d.aetherScore, { .makroOrtam(skor: $0) })
        ]

        if let winner = scores
            .compactMap({ (score, factory) -> (Double, DominantFaktor)? in
                guard let s = score, s > 60 else { return nil }
                return (s, factory(s))
            })
            .max(by: { $0.0 < $1.0 }) {
            return winner.1
        }

        // Priority 9: Forecast fallback
        if let final = d.argusFinalScore {
            return .tahmin(yuzde: final)
        }

        // Priority 10: General consensus fallback
        let ortPuan = ortalamaModulPuani(d)
        return .genelUzlasi(puan: ortPuan)
    }

    // MARK: - Narrative Generation (tip x faktor matrix)

    private static func anlatimUret(
        tip: KararTipi,
        faktor: DominantFaktor,
        decision: AutoPilotDecision
    ) -> String {
        let riskTon = riskTonlamasi(decision.riskMultiple)

        switch (tip, faktor) {

        // ── Alım ────────────────────────────────────────
        case (.alim, .haber(let baslik)):
            return "\"\(baslik)\" haberi sonrası analizler belirgin şekilde olumluya döndü. Güven yüksek, \(riskTon)."

        case (.alim, .teknikGuc(let skor)):
            return "Teknik göstergeler güçlü bir alım fırsatına işaret ediyor (skor: \(Int(skor))). Diğer analizler de destekliyor."

        case (.alim, .temelGuc(let skor)):
            return "Temel veriler olumlu bir tablo çiziyor (skor: \(Int(skor))). Bilanço ve değerleme metrikleri alım yönünde."

        case (.alim, .makroOrtam(let skor)):
            return "Makro ortam alım için uygun (skor: \(Int(skor))). Piyasa koşulları destekleyici."

        case (.alim, .genelUzlasi(let puan)):
            return "Modüller genel bir alım konsensusuna ulaştı (ortalama: \(Int(puan))). \(riskTon.capitalized) pozisyon açıldı."

        case (.alim, .tahmin(let yuzde)):
            return "Analiz skoru \(Int(yuzde)) ile alım sinyali verdi. \(riskTon.capitalized) pozisyon."

        case (.alim, .veriKalitesi(let skor)):
            return "Veri kalitesi düşük olmasına rağmen (%\(Int(skor))) diğer sinyaller yeterince güçlü bulundu. Temkinli alım."

        case (.alim, .riskLimiti), (.alim, .veto), (.alim, .zamanlama):
            // Bu kombinasyonlar pratikte nadir; defansif fallback
            return "Sinyaller karışık olsa da alım kararı verildi. \(riskTon.capitalized) yaklaşım."

        // ── Satım ───────────────────────────────────────
        case (.satim, .teknikGuc(let skor)):
            return "Teknik göstergeler satış sinyali veriyor (skor: \(Int(skor))). Pozisyon kapatıldı."

        case (.satim, .haber(let baslik)):
            return "\"\(baslik)\" haberi ardından risk profili olumsuzlaştı. Pozisyon kapatıldı."

        case (.satim, .riskLimiti(let carpan)):
            return "Risk çarpanı düşük seviyede (\(String(format: "%.2f", carpan))). Pozisyon risk yönetimi gereği kapatıldı."

        case (.satim, .temelGuc(let skor)):
            return "Temel veriler bozulmaya işaret ediyor (skor: \(Int(skor))). Pozisyon kapatıldı."

        case (.satim, .makroOrtam(let skor)):
            return "Makro ortam olumsuzlaştı (skor: \(Int(skor))). Pozisyon savunma amaçlı kapatıldı."

        case (.satim, .genelUzlasi(let puan)):
            return "Modüller satış yönünde uzlaştı (ortalama: \(Int(puan))). Pozisyon kapatıldı."

        case (.satim, .tahmin(let yuzde)):
            return "Analiz skoru \(Int(yuzde)) ile satış sinyali üretti. Pozisyon tasfiye edildi."

        case (.satim, .veriKalitesi), (.satim, .veto), (.satim, .zamanlama):
            return "Mevcut koşullar pozisyonun kapatılmasını gerektirdi."

        // ── Pas Geçildi ─────────────────────────────────
        case (.pasGecildi, .veriKalitesi(let skor)):
            return "Veri kalitesi yetersiz (%\(Int(skor))). Güvenilir analiz yapılamadığı için işlem yapılmadı."

        case (.pasGecildi, .genelUzlasi(let puan)):
            return "Modüller arasında yeterli uzlaşı sağlanamadı (ortalama: \(Int(puan))). Beklemeye alındı."

        case (.pasGecildi, .riskLimiti(let carpan)):
            return "Risk çarpanı çok düşük (\(String(format: "%.2f", carpan))). Koşullar uygun değil, işlem yapılmadı."

        case (.pasGecildi, .teknikGuc(let skor)):
            return "Teknik sinyaller belirsiz (skor: \(Int(skor))). Net bir yön oluşana kadar bekleniyor."

        case (.pasGecildi, .temelGuc(let skor)):
            return "Temel veriler kararsız (skor: \(Int(skor))). Daha fazla veri bekleniyor."

        case (.pasGecildi, .makroOrtam(let skor)):
            return "Makro ortam belirsiz (skor: \(Int(skor))). Piyasa yönü netleşene kadar bekleniyor."

        case (.pasGecildi, .haber(let baslik)):
            return "\"\(baslik)\" haberi etkisi henüz netleşmedi. Yön oluşana kadar bekleniyor."

        case (.pasGecildi, .tahmin(let yuzde)):
            return "Analiz skoru (\(Int(yuzde))) işlem eşiğinin altında. Sinyal güçlenene kadar bekleniyor."

        case (.pasGecildi, .veto), (.pasGecildi, .zamanlama):
            return "Mevcut koşullar işlem için uygun değil. Beklemeye alındı."

        // ── Engellendi ──────────────────────────────────
        case (.engellendi, .zamanlama(let sebep)):
            return "Analizler olumlu ancak \(sebep). Koşullar uygun olduğunda yeniden değerlendirilecek."

        case (.engellendi, .veto(let sebep)):
            return "\(sebep) nedeniyle işlem engellendi. Engel kalkana kadar bekleniyor."

        case (.engellendi, .riskLimiti(let carpan)):
            return "Risk çarpanı (\(String(format: "%.2f", carpan))) güvenli eşiğin altında. İşlem engellendi."

        case (.engellendi, .veriKalitesi(let skor)):
            return "Veri kalitesi kritik seviyede düşük (%\(Int(skor))). Güvenilir veri gelene kadar engellendi."

        case (.engellendi, .haber(let baslik)):
            return "\"\(baslik)\" haberi nedeniyle volatilite yüksek. Sakinleşene kadar engellendi."

        case (.engellendi, .teknikGuc(let skor)):
            return "Teknik göstergeler uyarı veriyor (skor: \(Int(skor))). İşlem güvenlik gereği engellendi."

        case (.engellendi, .temelGuc(let skor)):
            return "Temel veriler risk sinyali taşıyor (skor: \(Int(skor))). İşlem engellendi."

        case (.engellendi, .makroOrtam(let skor)):
            return "Makro ortam risk taşıyor (skor: \(Int(skor))). İşlem engellendi."

        case (.engellendi, .genelUzlasi(let puan)):
            return "Konsensus skoru (\(Int(puan))) engel eşiğinde. İşlem yapılmadı."

        case (.engellendi, .tahmin(let yuzde)):
            return "Tahmin skoru (\(Int(yuzde))) engel koşulunu tetikledi. İşlem bloke edildi."
        }
    }

    // MARK: - Amount Explanation

    private static func miktarAciklamasiUret(_ d: AutoPilotDecision) -> String? {
        guard d.quantity > 0,
              let price = d.price, price > 0,
              let portfolyoDeger = d.portfolioValueBefore, portfolyoDeger > 0
        else { return nil }

        let islemTutari = d.quantity * price
        let yuzde = (islemTutari / portfolyoDeger) * 100
        let ton = riskMiktarTonu(d.riskMultiple)

        let formattedTutar = formatCurrency(islemTutari)
        let formattedYuzde = String(format: "%.1f", yuzde)

        return "\(formattedTutar) tutarında (\(ton) — portföyün %\(formattedYuzde)'i)."
    }

    // MARK: - Rationale Parsing Helpers

    /// Extracts timing/cooldown reason from rationale.
    /// Looks for patterns like "X dk kaldı", "cooldown", "Bekleme".
    static func zamanlamaSebebiParsla(_ rationale: String) -> String {
        // Pattern: "N dk kaldı"
        if let range = rationale.range(of: #"\d+ dk kaldı"#, options: .regularExpression) {
            let snippet = String(rationale[range])
            return "\(snippet)"
        }

        // Pattern: "Minimum Tutma Süresi: X dk"
        if let range = rationale.range(of: #"Tutma Süresi[^)]*"#, options: .regularExpression) {
            return String(rationale[range])
        }

        // Pattern: "Tekrar Giriş Beklemesi: X dk"
        if let range = rationale.range(of: #"Tekrar Giriş Beklemesi[^)]*"#, options: .regularExpression) {
            return String(rationale[range])
        }

        if rationale.lowercased().contains("cooldown") {
            return "cooldown süresi devam ediyor"
        }

        return "zamanlama kısıtlaması aktif"
    }

    /// Extracts veto source from rationale.
    static func vetoSebebiParsla(_ rationale: String) -> String {
        let rLow = rationale.lowercased()

        // "Teknik Veto: Orion (75) & ..."
        if let range = rationale.range(of: #"Teknik Veto:[^)]*\)"#, options: .regularExpression) {
            return String(rationale[range])
        }

        // "RİSK VETOSU: reason"
        if let range = rationale.range(of: #"RİSK VETOSU: [^\n]+"#, options: .regularExpression) {
            return String(rationale[range])
        }

        // "Konsey Veto"
        if rLow.contains("konsey veto") {
            return "Konsey vetosu"
        }

        // Generic veto source detection
        if rLow.contains("aether") || rLow.contains("makro") {
            return "Makro analiz vetosu"
        }
        if rLow.contains("orion") || rLow.contains("teknik") {
            return "Teknik analiz vetosu"
        }
        if rLow.contains("atlas") || rLow.contains("temel") {
            return "Temel analiz vetosu"
        }

        return "Sistem vetosu"
    }

    /// Extracts headline from rationale. Looks for quoted text or falls back.
    static func haberBasligiParsla(_ rationale: String) -> String {
        // Quoted headline: "Some headline here"
        if let range = rationale.range(of: #""([^"]+)""#, options: .regularExpression) {
            var match = String(rationale[range])
            match = match.replacingOccurrences(of: "\"", with: "")
            if !match.isEmpty { return match }
        }

        // «guillemet style»
        if let range = rationale.range(of: #"«([^»]+)»"#, options: .regularExpression) {
            var match = String(rationale[range])
            match = match.replacingOccurrences(of: "«", with: "")
                         .replacingOccurrences(of: "»", with: "")
            if !match.isEmpty { return match }
        }

        return "güncel haber akışı"
    }

    // MARK: - Private Helpers

    private static func riskTonlamasi(_ riskMultiple: Double?) -> String {
        guard let rm = riskMultiple else { return "standart pozisyon" }
        if rm < 0.5 { return "temkinli pozisyon" }
        if rm <= 0.8 { return "dengeli pozisyon" }
        return "geniş pozisyon"
    }

    private static func riskMiktarTonu(_ riskMultiple: Double?) -> String {
        guard let rm = riskMultiple else { return "standart" }
        if rm < 0.5 { return "temkinli" }
        if rm <= 0.8 { return "dengeli" }
        return "geniş"
    }

    private static func ortalamaModulPuani(_ d: AutoPilotDecision) -> Double {
        let scores = [d.orionScore, d.atlasScore, d.aetherScore, d.hermesScore, d.demeterScore]
        let valid = scores.compactMap { $0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private static func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM $", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0f $", value)
        } else {
            return String(format: "%.2f $", value)
        }
    }
}
