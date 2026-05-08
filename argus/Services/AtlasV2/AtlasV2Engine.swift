import Foundation

// MARK: - Atlas V2 Eğitim Motoru
// Şirketleri A'dan Z'ye analiz eden ana motor

actor AtlasV2Engine {
    static let shared = AtlasV2Engine()
    
    private let explainer = AtlasExplanationFactory.shared
    
    // Cache
    private var cache: [String: AtlasV2Result] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 saat
    
    private init() {}
    
    // MARK: - Ana Analiz Fonksiyonu
    
    func analyze(symbol: String, forceRefresh: Bool = false) async throws -> AtlasV2Result {
        // Cache kontrolü
        if !forceRefresh, let cached = cache[symbol] {
            if Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                return cached
            }
        }
        
        // FIX: HeimdallOrchestrator @MainActor olduğu için timeout ile korumalı çağrı
        // Actor isolation Swift tarafından otomatik handle edilir, ama timeout ekliyoruz
        
        // 1. Veri çek (timeout ile) - increased to 45s for better reliability
        print("🔍 AtlasV2: Fetching fundamentals for \(symbol)...")
        let financials = try await withTimeout(seconds: 45) {
            try await HeimdallOrchestrator.shared.requestFundamentals(symbol: symbol)
        }
        print("✅ AtlasV2: Fundamentals received for \(symbol)")
        
        // 2. Quote çek — önce MarketDataStore cache'i (ensureQuote/refreshQuotes
        // tarafından dolduruluyor). Cache hit ise network çağrısı atlanıyor;
        // 30+ BUY sinyalinde 30+ duplicate Yahoo isteğini engelliyor.
        // Cache miss ise direkt orchestrator'a düşer.
        let cachedQuote = await MainActor.run {
            MarketDataStore.shared.getQuote(for: symbol)
        }
        let quote: Quote?
        if let cached = cachedQuote, cached.currentPrice > 0 {
            print("⚡ AtlasV2: \(symbol) quote cache hit — \(cached.currentPrice)")
            quote = cached
        } else {
            print("🔍 AtlasV2: Fetching quote for \(symbol)...")
            quote = try? await withTimeout(seconds: 20) {
                try await HeimdallOrchestrator.shared.requestQuote(symbol: symbol)
            }
            print("✅ AtlasV2: Quote received for \(symbol): \(quote?.c ?? 0)")
        }
        
        // 3. Sektör benchmark'ını al (dinamik Yahoo verisi + statik fallback)
        let sector = try? await getSectorFromYahoo(symbol: symbol)
        await AtlasSectorBenchmarks.shared.refreshIfNeeded()
        let sectorBenchmark = await AtlasSectorBenchmarks.shared.getBenchmark(for: sector)
        
        // 4. Her bölümü analiz et ve skorla
        let valuationData = analyzeValuation(financials: financials, quote: quote, benchmark: sectorBenchmark)
        let profitabilityData = analyzeProfitability(financials: financials, benchmark: sectorBenchmark)
        let growthData = analyzeGrowth(financials: financials)
        let healthData = analyzeHealth(financials: financials)
        let cashData = analyzeCash(financials: financials)
        let dividendData = analyzeDividend(financials: financials)
        let riskData = analyzeRisk(financials: financials, quote: quote)
        
        // 5. Bölüm skorlarını hesapla — her biri Optional<Double> (nil = veri yok)
        let valuationScoreOpt = calculateSectionScore(valuationData.allMetrics)
        let profitabilityScoreOpt = calculateSectionScore(profitabilityData.allMetrics)
        let growthScoreOpt = calculateSectionScore(growthData.allMetrics)
        let healthScoreOpt = calculateSectionScore(healthData.allMetrics)
        let cashScoreOpt = calculateSectionScore(cashData.allMetrics)
        let dividendScoreOpt = calculateSectionScore(dividendData.allMetrics)

        // 2026-05-05 (Round 5) FIX: Nil section'ları ağırlık hesabından dışla,
        // ağırlıkları normalize et. Eksik section'lar warnings'e eklenir.
        let candidateSections: [(label: String, score: Double?, weight: Double)] = [
            ("Karlılık", profitabilityScoreOpt, 0.30),
            ("Değerleme", valuationScoreOpt, 0.25),
            ("Mali Sağlık", healthScoreOpt, 0.20),
            ("Büyüme", growthScoreOpt, 0.15),
            ("Nakit", cashScoreOpt, 0.10)
        ]
        let validSections = candidateSections.compactMap { (label, score, weight) -> (String, Double, Double)? in
            guard let score = score else { return nil }
            return (label, score, weight)
        }
        let missingSectionLabels = candidateSections.filter { $0.score == nil }.map { $0.label }

        let totalScore: Double
        var dataAdequacyWarning: String? = nil
        if validSections.count < 3 {
            // Yetersiz veri — sahte skor üretmek yerine 50 (nötr) ver, ama warnings'e açıkça yaz
            totalScore = 50.0
            dataAdequacyWarning = "⚠️ Veri yetersiz: 5 bölümden yalnız \(validSections.count) tanesi mevcut. Eksik: \(missingSectionLabels.joined(separator: ", ")). Skor güvenilir değil — 50 (nötr) atandı."
            ArgusLogger.warning(.atlas, "V2: \(symbol) için yetersiz veri (\(validSections.count)/5 bölüm). Skor 50 atandı.")
        } else {
            // Ağırlıkları normalize et — eksik section'ın ağırlığı kalan section'lara dağılır
            let totalWeight = validSections.reduce(0.0) { $0 + $1.2 }
            let weightedSum = validSections.reduce(0.0) { $0 + $1.1 * $1.2 }
            totalScore = weightedSum / totalWeight
            if !missingSectionLabels.isEmpty {
                dataAdequacyWarning = "ℹ️ Skor \(validSections.count)/5 bölümle hesaplandı. Eksik: \(missingSectionLabels.joined(separator: ", "))"
            }
        }

        // 5b. UI ve downstream API uyumluluğu için section skorlarını UI'a düz Double olarak veriyoruz
        // (nil olanlar 0 olarak görünür ama UI tarafı bunu warnings ile birlikte yorumlamalı)
        let valuationScore = valuationScoreOpt ?? 0
        let profitabilityScore = profitabilityScoreOpt ?? 0
        let growthScore = growthScoreOpt ?? 0
        let healthScore = healthScoreOpt ?? 0
        let cashScore = cashScoreOpt ?? 0
        let dividendScore = dividendScoreOpt ?? 0
        
        // 7. Şirket profili
        let profile = AtlasCompanyProfile(
            symbol: symbol,
            name: quote?.shortName ?? symbol,
            sector: sector, // TODO: Sektör bilgisini ayrıca çek
            industry: nil,
            marketCap: financials.marketCap,
            formattedMarketCap: AtlasMetric.format(financials.marketCap),
            employees: nil,
            description: nil,
            currency: financials.currency
        )
        
        // 8. Öne çıkanlar ve uyarılar
        let (highlights, baseWarnings) = generateHighlightsAndWarnings(
            valuation: valuationData,
            profitability: profitabilityData,
            growth: growthData,
            health: healthData,
            cash: cashData
        )
        // Round 5: Veri yetersizliği uyarısı en üste eklenir (kullanıcı için en kritik bilgi)
        var warnings: [String] = baseWarnings
        if let warn = dataAdequacyWarning {
            warnings.insert(warn, at: 0)
        }

        // Round 5 P3-6: Score trace
        // 2026-05-05 (Round 9) FIX: nil section → "N/A" yaz (eskiden 0 yazıyordu, kullanıcı
        // "veri var ama 0 puan" sanıyordu — gerçekte veri yok).
        func fmt(_ value: Double?) -> String {
            return value.map { "\(Int($0))" } ?? "N/A"
        }
        let sectionTrace = "val=\(fmt(valuationScoreOpt)) prof=\(fmt(profitabilityScoreOpt)) grow=\(fmt(growthScoreOpt)) health=\(fmt(healthScoreOpt)) cash=\(fmt(cashScoreOpt)) div=\(fmt(dividendScoreOpt))"
        ArgusLogger.info(.atlas, "V2 \(symbol) total=\(Int(totalScore)) (\(validSections.count)/5 bölüm) \(sectionTrace)")
        
        // 9. Özet yorum
        // 2026-05-05 (Round 9) FIX: < 3 bölüm varsa "şirket olarak değerlendirildi" demek
        // yanıltıcı (BTC-USD'de "Karlılık zayıf" bile diyordu). Veri yetersiz net mesajı ver.
        let summary: String
        if validSections.count < 3 {
            summary = "[\(symbol)] Veri yetersiz — \(validSections.count)/5 bölüm mevcut, fundamental analiz güvenilir değil. Eksik: \(missingSectionLabels.joined(separator: ", "))"
        } else {
            summary = generateSummary(
                symbol: symbol,
                totalScore: totalScore,
                profitability: profitabilityScore,
                valuation: valuationScore,
                growth: growthScore,
                health: healthScore
            )
        }
        
        // 10. Sonuç oluştur
        let result = AtlasV2Result(
            symbol: symbol,
            profile: profile,
            totalScore: totalScore,
            valuationScore: valuationScore,
            profitabilityScore: profitabilityScore,
            growthScore: growthScore,
            healthScore: healthScore,
            cashScore: cashScore,
            dividendScore: dividendScore,
            valuation: valuationData,
            profitability: profitabilityData,
            growth: growthData,
            health: healthData,
            cash: cashData,
            dividend: dividendData,
            risk: riskData,
            summary: summary,
            highlights: highlights,
            warnings: warnings
        )
        
        // Cache'e kaydet
        cache[symbol] = result
        
        return result
    }
    
    // MARK: - Değerleme Analizi
    
    private func analyzeValuation(financials: FinancialsData, quote: Quote?, benchmark: AtlasSectorBenchmark) -> AtlasValuationData {
        // P/E
        let peResult = explainer.explainPE(value: financials.peRatio, sectorAvg: benchmark.avgPE)
        let peMetric = AtlasMetric(
            id: "pe",
            name: "F/K (P/E)",
            value: financials.peRatio,
            sectorAverage: benchmark.avgPE,
            status: peResult.status,
            score: peResult.score,
            explanation: peResult.explanation,
            educationalNote: peResult.educational,
            formula: "Hisse Fiyatı / Hisse Başına Kar"
        )
        
        // P/B
        let pbResult = explainer.explainPB(value: financials.priceToBook, sectorAvg: benchmark.avgPB)
        let pbMetric = AtlasMetric(
            id: "pb",
            name: "PD/DD (P/B)",
            value: financials.priceToBook,
            sectorAverage: benchmark.avgPB,
            status: pbResult.status,
            score: pbResult.score,
            explanation: pbResult.explanation,
            educationalNote: pbResult.educational,
            formula: "Piyasa Değeri / Defter Değeri"
        )
        
        // EV/EBITDA
        let evEbitdaResult = explainer.explainEVEBITDA(value: financials.evToEbitda)
        let evEbitdaMetric = AtlasMetric(
            id: "evebitda",
            name: "EV/EBITDA",
            value: financials.evToEbitda,
            status: evEbitdaResult.status,
            score: evEbitdaResult.score,
            explanation: evEbitdaResult.explanation,
            educationalNote: evEbitdaResult.educational,
            formula: "Kurumsal Değer / FAVÖK"
        )

        // PEG
        let pegResult = explainer.explainPEG(value: financials.pegRatio)
        let pegMetric = AtlasMetric(
            id: "peg",
            name: "PEG Oranı",
            value: financials.pegRatio,
            status: pegResult.status,
            score: pegResult.score,
            explanation: pegResult.explanation,
            educationalNote: pegResult.educational,
            formula: "F/K / Büyüme Oranı"
        )

        // Forward P/E
        let forwardPEResult = explainer.explainForwardPE(value: financials.forwardPERatio)
        let forwardPEMetric = AtlasMetric(
            id: "forwardpe",
            name: "İleriye Dönük F/K",
            value: financials.forwardPERatio,
            status: forwardPEResult.status,
            score: forwardPEResult.score,
            explanation: forwardPEResult.explanation,
            educationalNote: forwardPEResult.educational,
            formula: "Fiyat / Tahmini Gelecek Yıl Karı"
        )
        
        return AtlasValuationData(
            pe: peMetric,
            pb: pbMetric,
            evEbitda: evEbitdaMetric,
            peg: pegMetric,
            forwardPE: forwardPEMetric,
            priceToSales: nil
        )
    }
    
    // MARK: - Karlılık Analizi
    
    private func analyzeProfitability(financials: FinancialsData, benchmark: AtlasSectorBenchmark) -> AtlasProfitabilityData {
        // ROE
        let roeResult = explainer.explainROE(value: financials.returnOnEquity, sectorAvg: benchmark.avgROE)
        let roeMetric = AtlasMetric(
            id: "roe",
            name: "ROE (Özkaynak Karlılığı)",
            value: financials.returnOnEquity,
            sectorAverage: benchmark.avgROE,
            status: roeResult.status,
            score: roeResult.score,
            explanation: roeResult.explanation,
            educationalNote: roeResult.educational,
            formula: "Net Kar / Özkaynaklar × 100"
        )
        
        // ROA
        let roaResult = explainer.explainROA(value: financials.returnOnAssets)
        let roaMetric = AtlasMetric(
            id: "roa",
            name: "ROA (Aktif Karlılığı)",
            value: financials.returnOnAssets,
            status: roaResult.status,
            score: roaResult.score,
            explanation: roaResult.explanation,
            educationalNote: roaResult.educational,
            formula: "Net Kar / Toplam Aktifler × 100"
        )

        // Net Marj
        let netMarginResult = explainer.explainNetMargin(value: financials.profitMargin)
        let netMarginMetric = AtlasMetric(
            id: "netmargin",
            name: "Net Kar Marjı",
            value: financials.profitMargin,
            status: netMarginResult.status,
            score: netMarginResult.score,
            explanation: netMarginResult.explanation,
            educationalNote: netMarginResult.educational,
            formula: "Net Kar / Gelir × 100"
        )

        // Gross Margin
        let grossMarginResult = explainer.explainGrossMargin(value: financials.grossMargin)
        let grossMarginMetric = AtlasMetric(
            id: "grossmargin",
            name: "Brüt Kar Marjı",
            value: financials.grossMargin,
            status: grossMarginResult.status,
            score: grossMarginResult.score,
            explanation: grossMarginResult.explanation,
            educationalNote: grossMarginResult.educational,
            formula: "Brüt Kar / Gelir × 100"
        )
        
        return AtlasProfitabilityData(
            roe: roeMetric,
            roa: roaMetric,
            netMargin: netMarginMetric,
            grossMargin: grossMarginMetric,
            roic: nil
        )
    }
    
    // MARK: - Büyüme Analizi
    
    private func analyzeGrowth(financials: FinancialsData) -> AtlasGrowthData {
        // Revenue CAGR
        let revCAGR = calculateCAGR(history: financials.revenueHistory)
        let revResult = explainer.explainCAGR(value: revCAGR, type: "Gelir")
        let revCAGRMetric = AtlasMetric(
            id: "revcagr",
            name: "Gelir CAGR (3 Yıl)",
            value: revCAGR,
            status: revResult.status,
            score: revResult.score,
            explanation: revResult.explanation,
            educationalNote: revResult.educational,
            formula: "(Son / İlk)^(1/n) - 1"
        )
        
        // Net Income CAGR
        let niCAGR = calculateCAGR(history: financials.netIncomeHistory)
        let niResult = explainer.explainCAGR(value: niCAGR, type: "Net Kar")
        let niCAGRMetric = AtlasMetric(
            id: "nicagr",
            name: "Net Kar CAGR (3 Yıl)",
            value: niCAGR,
            status: niResult.status,
            score: niResult.score,
            explanation: niResult.explanation,
            educationalNote: niResult.educational,
            formula: "(Son Kar / İlk Kar)^(1/n) - 1"
        )
        
        // Forward Growth
        let forwardGrowthMetric = createPercentMetric(
            id: "forwardgrowth",
            name: "Beklenen Büyüme",
            value: financials.forwardGrowthEstimate,
            formula: "Analist tahminleri ortalaması"
        )
        
        return AtlasGrowthData(
            revenueCAGR: revCAGRMetric,
            netIncomeCAGR: niCAGRMetric,
            forwardGrowth: forwardGrowthMetric,
            revenueGrowthYoY: nil
        )
    }
    
    // MARK: - Finansal Sağlık Analizi
    
    private func analyzeHealth(financials: FinancialsData) -> AtlasHealthData {
        // Debt to Equity
        let deResult = explainer.explainDebtToEquity(value: financials.debtToEquity)
        let deMetric = AtlasMetric(
            id: "de",
            name: "Borç/Özkaynak",
            value: financials.debtToEquity,
            status: deResult.status,
            score: deResult.score,
            explanation: deResult.explanation,
            educationalNote: deResult.educational,
            formula: "Toplam Borç / Özkaynaklar"
        )
        
        // Current Ratio
        let crMetric = createRatioMetric(
            id: "currentratio",
            name: "Cari Oran",
            value: financials.currentRatio,
            formula: "Dönen Varlıklar / Kısa Vadeli Borçlar"
        )
        
        return AtlasHealthData(
            debtToEquity: deMetric,
            currentRatio: crMetric,
            interestCoverage: nil,
            altmanZScore: nil
        )
    }
    
    // MARK: - Nakit Analizi
    
    private func analyzeCash(financials: FinancialsData) -> AtlasCashData {
        // FCF
        let fcfResult = explainer.explainFCF(value: financials.freeCashFlow, marketCap: financials.marketCap)
        let fcfMetric = AtlasMetric(
            id: "fcf",
            name: "Serbest Nakit Akışı",
            value: financials.freeCashFlow,
            status: fcfResult.status,
            score: fcfResult.score,
            explanation: fcfResult.explanation,
            educationalNote: fcfResult.educational,
            formula: "İşletme Nakit Akışı - Yatırımlar"
        )
        
        // OCF/NI
        var ocfNiRatio: Double? = nil
        if let ocf = financials.operatingCashflow, let ni = financials.netIncome, ni > 0 {
            ocfNiRatio = ocf / ni
        }
        let ocfNiMetric = createRatioMetric(
            id: "ocfni",
            name: "Nakit Dönüşüm Oranı",
            value: ocfNiRatio,
            formula: "İşletme Nakit Akışı / Net Kar"
        )
        
        return AtlasCashData(
            freeCashFlow: fcfMetric,
            ocfToNetIncome: ocfNiMetric,
            cashPosition: nil,
            netDebt: nil
        )
    }
    
    // MARK: - Temettü Analizi
    
    private func analyzeDividend(financials: FinancialsData) -> AtlasDividendData {
        let divResult = explainer.explainDividendYield(value: financials.dividendYield)
        let divMetric = AtlasMetric(
            id: "divyield",
            name: "Temettü Verimi",
            value: financials.dividendYield.map { $0 * 100 },
            status: divResult.status,
            score: divResult.score,
            explanation: divResult.explanation,
            educationalNote: divResult.educational,
            formula: "Yıllık Temettü / Hisse Fiyatı × 100"
        )
        
        return AtlasDividendData(
            dividendYield: divMetric,
            payoutRatio: nil,
            dividendGrowth: nil
        )
    }
    
    // MARK: - Risk Analizi
    
    private func analyzeRisk(financials: FinancialsData, quote: Quote?) -> AtlasRiskData {
        let betaMetric = createSimpleMetric(
            id: "beta",
            name: "Beta (Volatilite)",
            value: nil, // Yahoo'dan çekilecek
            formula: "Hisse Volatilitesi / Piyasa Volatilitesi"
        )
        
        return AtlasRiskData(
            beta: betaMetric,
            week52High: nil,
            week52Low: nil,
            volatility: nil
        )
    }
    
    // MARK: - Yardımcı Fonksiyonlar
    
    /// 2026-05-05 (Round 5) FIX: Eski sürüm `validScores.isEmpty` durumunda `return 50`
    /// (default fallback) dönüyordu — Sirkiye L56 anti-pattern. Veri yokken sahte
    /// nötr skor üretiyordu, kullanıcı "veri var sanıp" yanlış kararlar veriyordu.
    /// Şimdi: veri yoksa `nil` dön → analyze() bu section'ı total skor hesabından
    /// dışla + warnings'e ekle. UI ve adapter "veri yetersiz" davranışını görür.
    private func calculateSectionScore(_ metrics: [AtlasMetric]) -> Double? {
        let validScores = metrics.compactMap { $0.value != nil ? $0.score : nil }
        guard !validScores.isEmpty else { return nil }
        return validScores.reduce(0, +) / Double(validScores.count)
    }
    
    private func calculateCAGR(history: [Double]?) -> Double? {
        guard let h = history, h.count >= 2 else { return nil }
        let start = h.last ?? 0
        let end = h.first ?? 0
        guard start > 0, end > 0 else { return nil }
        let years = Double(h.count - 1)
        return (pow(end / start, 1.0 / years) - 1) * 100
    }
    
    private func createSimpleMetric(id: String, name: String, value: Double?, formula: String) -> AtlasMetric {
        let status: AtlasMetricStatus = value == nil ? .noData : .neutral
        return AtlasMetric(
            id: id,
            name: name,
            value: value,
            status: status,
            score: value == nil ? 0 : 50,
            explanation: value == nil ? "Veri mevcut değil." : "Değer: \(AtlasMetric.format(value))",
            educationalNote: "",
            formula: formula
        )
    }
    
    private func createPercentMetric(id: String, name: String, value: Double?, formula: String) -> AtlasMetric {
        let status: AtlasMetricStatus = value == nil ? .noData : .neutral
        return AtlasMetric(
            id: id,
            name: name,
            value: value,
            status: status,
            score: value == nil ? 0 : 50,
            explanation: value == nil ? "Veri mevcut değil." : "%\(AtlasMetric.format(value))",
            educationalNote: "",
            formula: formula
        )
    }
    
    private func createRatioMetric(id: String, name: String, value: Double?, formula: String) -> AtlasMetric {
        let status: AtlasMetricStatus
        let score: Double
        let explanation: String
        
        if let v = value {
            switch v {
            case 2.0...: status = .good; score = 80; explanation = "Güçlü"
            case 1.5..<2.0: status = .good; score = 70; explanation = "İyi"
            case 1.0..<1.5: status = .neutral; score = 55; explanation = "Yeterli"
            case 0.5..<1.0: status = .warning; score = 35; explanation = "Zayıf"
            default: status = .bad; score = 20; explanation = "Kritik"
            }
        } else {
            status = .noData
            score = 0
            explanation = "Veri mevcut değil."
        }
        
        return AtlasMetric(
            id: id,
            name: name,
            value: value,
            status: status,
            score: score,
            explanation: explanation,
            educationalNote: "",
            formula: formula
        )
    }
    
    private func generateHighlightsAndWarnings(
        valuation: AtlasValuationData,
        profitability: AtlasProfitabilityData,
        growth: AtlasGrowthData,
        health: AtlasHealthData,
        cash: AtlasCashData
    ) -> ([String], [String]) {
        var highlights: [String] = []
        var warnings: [String] = []
        
        // Karlılık
        if profitability.roe.score >= 80 {
            highlights.append("🏆 Mükemmel özkaynak karlılığı (ROE: \(profitability.roe.formattedValue)%)")
        }
        
        // Değerleme
        if valuation.pe.score >= 80 {
            highlights.append("💰 Cazip değerleme (F/K: \(valuation.pe.formattedValue))")
        } else if valuation.pe.score <= 30 {
            warnings.append("⚠️ Pahalı değerleme (F/K: \(valuation.pe.formattedValue))")
        }
        
        // Borç
        if health.debtToEquity.status == .critical || health.debtToEquity.status == .bad {
            warnings.append("🚨 Yüksek borç oranı")
        }
        
        // Nakit
        if cash.freeCashFlow.score >= 80 {
            highlights.append("💵 Güçlü nakit üretimi")
        } else if cash.freeCashFlow.status == .bad {
            warnings.append("⚠️ Zayıf nakit akışı")
        }
        
        return (highlights, warnings)
    }
    
    private func generateSummary(
        symbol: String,
        totalScore: Double,
        profitability: Double,
        valuation: Double,
        growth: Double,
        health: Double
    ) -> String {
        let band = AtlasQualityBand.from(score: totalScore)
        
        var summary = "\(symbol) genel olarak \(band.description.lowercased()) bir şirket olarak değerlendiriliyor. "
        
        if profitability >= 70 {
            summary += "Karlılık güçlü. "
        } else if profitability <= 40 {
            summary += "Karlılık zayıf. "
        }
        
        if valuation >= 70 {
            summary += "Değerleme cazip görünüyor. "
        } else if valuation <= 40 {
            summary += "Pahalı fiyatlanmış olabilir. "
        }
        
        if health <= 40 {
            summary += "Finansal sağlık dikkat gerektiriyor."
        }
        
        return summary
    }
    
    // MARK: - Timeout Helper (Deadlock Prevention)
    
    private enum TimeoutError: Error {
        case timeout
    }
    
    /// Timeout ile async işlemleri korur, sonsuz beklemeyi önler
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Ana işlem
            group.addTask {
                try await operation()
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timeout
            }
            
            // İlk tamamlanan task'ı al
            guard let result = try await group.next() else {
                throw TimeoutError.timeout
            }
            
            // Diğer task'ı iptal et
            group.cancelAll()
            
            return result
        }
    }
    
    private func getSectorFromYahoo(symbol: String) async throws -> String? {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v10/finance/quoteSummary/\(symbol)?modules=assetProfile") else {
            print("Invalid URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Invalid response")
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let quoteSummary = json?["quoteSummary"] as? [String: Any],
                  let result = quoteSummary["result"] as? [[String: Any]],
                  let assetProfile = result.first?["assetProfile"] as? [String: Any],
                  let sector = assetProfile["sector"] as? String else {
                print("Failed to parse sector from JSON")
                return nil
            }
            
            return sector
        } catch {
            print("Error fetching sector: \(error)")
            return nil
        }
    }
}
