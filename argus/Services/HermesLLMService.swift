import Foundation

/// Handles interaction with AI (Groq/LLaMA 3) for Hermes News Analysis
/// Migrated from Gemini to Groq for centralized reliability.
final class HermesLLMService: Sendable {
    static let shared = HermesLLMService()
    
    // Cache: Article ID -> Summary
    private var cache: [String: HermesSummary] = [:]
    private let eventStore = HermesEventStore.shared
    
    private init() {
        // Load cache
        Task {
            if let loaded: [String: HermesSummary] = await ArgusDataStore.shared.load(key: "argus_hermes_cache") {
                self.cache = loaded
                print("🧠 Hermes: Loaded \(loaded.count) items from disk cache.")
            }
        }
    }

    // MARK: - Hermes V3: Event Extraction
    
    private func cleanRationale(_ text: String, polarity: HermesEventPolarity) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let banned = ["hermes", "ai", "model", "llm", "analiz", "prompt", "sistem"]
        if trimmed.isEmpty || banned.contains(where: { lowered.contains($0) }) {
            switch polarity {
            case .positive:
                return "Haber, kisa vadede alici ilgisini ve fiyatlama destegini artirabilir."
            case .negative:
                return "Haber, kisa vadede satis baskisi ve risk algisi olusturabilir."
            case .mixed:
                return "Haberin etkisi karisik; oynaklik artarken yon teyidi icin ek veri gerekir."
            }
        }
        return trimmed
    }

    private func cleanSummaryTRShort(_ text: String, polarity: HermesEventPolarity) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        switch polarity {
        case .positive: return "Haber kisa vadede hisseyi destekleyebilecek olumlu bir gelisme iceriyor."
        case .negative: return "Haber kisa vadede hisse uzerinde baski yaratabilecek olumsuz bir gelisme iceriyor."
        case .mixed: return "Haberin etkisi karisik; net yon icin ek veri ve fiyat teyidi gerekli."
        }
    }

    private func isSentimentConsistent(sentiment: NewsSentiment, impactScore: Double) -> Bool {
        switch sentiment {
        case .strongPositive: return impactScore >= 75
        case .weakPositive: return impactScore >= 60 && impactScore < 75
        case .neutral: return impactScore >= 45 && impactScore < 60
        case .weakNegative: return impactScore >= 30 && impactScore < 45
        case .strongNegative: return impactScore < 30
        }
    }

    func analyzeEvents(articles: [NewsArticle], scope: HermesEventScope, isGeneral: Bool = false) async throws -> [HermesEvent] {
        guard !articles.isEmpty else { return [] }
        
        var results: [HermesEvent] = []
        var articlesToProcess: [NewsArticle] = []
        
        // Cache hit
        for article in articles {
            if let cached = eventStore.getEvent(for: article.id) {
                results.append(cached)
            } else {
                articlesToProcess.append(article)
            }
        }
        
        if articlesToProcess.isEmpty {
            return results
        }
        
        let chunkedArticles = Array(articlesToProcess.prefix(3))
        let promptText = buildEventPrompt(chunkedArticles, scope: scope, isGeneral: isGeneral)
        
        let messages: [GroqClient.ChatMessage] = [
            .init(role: "system", content: "Sen finansal haberleri etiketleyen bir analiz asistanisin. Sadece verilen JSON semasina uygun cikti uret."),
            .init(role: "user", content: promptText)
        ]
        
        let analysisDate = Date()
        let responseDTO: HermesEventExtractionResponse = try await GroqClient.shared.generateJSON(messages: messages, maxTokens: 1400)
        
        var mappedEvents: [HermesEvent] = []
        for item in responseDTO.results {
            guard let article = chunkedArticles.first(where: { $0.id == item.id }) else { continue }
            let targetSymbol = (isGeneral && !(item.detected_symbol ?? "").isEmpty) ? (item.detected_symbol ?? article.symbol) : article.symbol
            
            let eventType = HermesEventType(rawValue: item.event_type ?? "") ?? .macroShock
            let polarity = HermesEventPolarity(rawValue: item.polarity ?? "") ?? .mixed
            let horizon = HermesEventHorizon(rawValue: item.horizon_hint ?? "") ?? .shortTerm
            let flags = (item.risk_flags ?? []).compactMap { HermesRiskFlag(rawValue: $0) }
            guard let llmSentimentRaw = item.sentiment_label,
                  let llmSentiment = NewsSentiment(rawValue: llmSentimentRaw) else {
                continue
            }
            guard let llmImpactScore = item.impact_score else { continue }
            guard isSentimentConsistent(sentiment: llmSentiment, impactScore: llmImpactScore) else { continue }

            let severity = max(0.0, min(item.severity ?? llmImpactScore, 100.0))
            let confidence = max(0.0, min(item.confidence ?? 0.6, 1.0))
            let sourceReliability = article.sourceReliability * 100.0
            let finalScore = max(0.0, min(llmImpactScore, 100.0))
            let ingestDelayMinutes = max(0.0, analysisDate.timeIntervalSince(article.publishedAt) / 60.0)
            
            mappedEvents.append(
                HermesEvent(
                    scope: scope,
                    symbol: targetSymbol,
                    articleId: article.id,
                    headline: article.headline,
                    eventType: eventType,
                    polarity: polarity,
                    severity: severity,
                    confidence: confidence,
                    sentimentLabel: llmSentiment,
                    horizonHint: horizon,
                    rationaleShort: cleanRationale(item.rationale_short ?? "", polarity: polarity),
                    summaryTRShort: cleanSummaryTRShort(item.summary_tr_short ?? "", polarity: polarity),
                    evidenceQuotes: Array((item.evidence_quotes ?? []).prefix(2)),
                    riskFlags: flags,
                    sourceName: article.source,
                    sourceReliability: sourceReliability,
                    publishedAt: article.publishedAt,
                    ingestDelayMinutes: ingestDelayMinutes,
                    finalScore: finalScore,
                    articleUrl: article.url
                )
            )
            
            HermesDelayStatsService.shared.record(
                source: article.source,
                delayMinutes: ingestDelayMinutes,
                scope: scope
            )
        }
        
        eventStore.saveEvents(mappedEvents)
        results.append(contentsOf: mappedEvents)
        return results
    }
    
    /// Batched Analysis using Groq
    /// - Parameter isGeneral: Global feed için true geçin, sembol tespiti yapılır
    func analyzeBatch(_ articles: [NewsArticle], isGeneral: Bool = false) async throws -> [HermesSummary] {
        if articles.isEmpty { return [] }
        
        var results: [HermesSummary] = []
        var articlesToProcess: [NewsArticle] = []
        
        // T3.6: Sentiment alpha yarı-ömrü 1-3 saat — 6 saat → 30 dk
        let cacheTTL: TimeInterval = 30 * 60 // 30 dk
        for article in articles {
            if let cached = cache[article.id],
               Date().timeIntervalSince(cached.createdAt) < cacheTTL {
                results.append(cached)
            } else {
                // Süresi dolmuş entry'yi temizle
                if cache[article.id] != nil {
                    cache.removeValue(forKey: article.id)
                }
                articlesToProcess.append(article)
            }
        }
        
        if articlesToProcess.isEmpty {
            return results
        }
        
        print("🧠 Hermes: Processing \(articlesToProcess.count) new articles (Cached: \(results.count))")
        
        // 2. Prepare Prompt for MISSING articles
        // Limit to 3 articles per batch (pagination logic should handle rest)
        let chunkedArticles = Array(articlesToProcess.prefix(3))
        let promptText = buildBatchPrompt(chunkedArticles, isGeneral: isGeneral)
        
        let messages: [GroqClient.ChatMessage] = [
            .init(role: "system", content: "You are a financial news analyst JSON generator. Always output valid JSON matching the schema."),
            .init(role: "user", content: promptText)
        ]
        
        // 3. Request via GroqClient
        do {
            let responseDTO: HermesBatchResponse = try await GroqClient.shared.generateJSON(
                messages: messages
            )
            
            // 4. Map to Model & Update Cache
            let newSummaries = responseDTO.results.compactMap { (item: HermesBatchItem) -> HermesSummary? in
                let originalArticle = chunkedArticles.first(where: { $0.id == item.id })
                
                let resolvedSymbol: String
                if isGeneral, let detectedSymbol = item.detected_symbol, !detectedSymbol.isEmpty {
                    resolvedSymbol = detectedSymbol
                } else {
                    resolvedSymbol = originalArticle?.symbol ?? "MARKET"
                }
                
                let summary = HermesSummary(
                    id: item.id,
                    symbol: resolvedSymbol,
                    summaryTR: item.summary_tr,
                    impactCommentTR: item.impact_comment_tr,
                    impactScore: Int(max(0.0, min(item.impact_score, 100.0))),
                    relatedSectors: item.related_sectors,
                    rippleEffectScore: Int(item.ripple_effect_score),
                    createdAt: Date(),
                    mode: .full,
                    publishedAt: originalArticle?.publishedAt,
                    sourceReliability: originalArticle?.sourceReliability
                )
                
                // Save to Cache
                self.cache[item.id] = summary
                return summary
            }
            
            self.persistCache()
            
            results.append(contentsOf: newSummaries)
            return results
            
        } catch {
            print("❌ Hermes Analysis Failed: \(error)")
            // Return whatever we have from cache if API fails
            if !results.isEmpty {
                let avgAgeHours = results.compactMap { r in Date().timeIntervalSince(r.createdAt) / 3600 }
                    .reduce(0, +) / max(1, Double(results.count))
                if avgAgeHours > 1 {
                    print("⚠️ Hermes: LLM hatası — \(results.count) stale cache kullanılıyor (ort. yaş: \(String(format: "%.1f", avgAgeHours))h)")
                }
                return results
            }
            
            let nsError = error as NSError
            if nsError.code == 429 {
                throw HermesError.quotaExhausted
            }
            throw error
        }
    }
    
    // MARK: - Hermes V2: Quick Sentiment (Cache-Based)
    
    /// Gets quick sentiment score for a symbol using cached Hermes analysis
    /// Returns a score from 0-100 (50 = neutral)
    /// - Parameter symbol: Stock symbol (e.g. "AAPL", "THYAO.IS")
    /// - Returns: HermesQuickSentiment with score and news count
    func getQuickSentiment(for symbol: String) async -> HermesQuickSentiment {
        // Get all cached summaries for this symbol
        var symbolSummaries = cache.values.filter {
            $0.symbol.uppercased() == symbol.uppercased() ||
            $0.symbol.uppercased() == symbol.replacingOccurrences(of: ".IS", with: "").uppercased()
        }

        // Fallback: derive from HermesEvent cache if summary cache is empty
        if symbolSummaries.isEmpty {
            let eventSummaries = eventStore.getEvents(for: symbol).map { event in
                HermesSummary(
                    id: event.articleId,
                    symbol: event.symbol,
                    summaryTR: event.rationaleShort,
                    impactCommentTR: event.rationaleShort,
                    impactScore: Int(max(0.0, min(event.finalScore, 100.0))),
                    relatedSectors: [],
                    rippleEffectScore: Int(max(0.0, min(event.severity, 100.0))),
                    createdAt: event.createdAt,
                    mode: .full,
                    publishedAt: event.publishedAt,
                    sourceReliability: event.sourceReliability / 100.0
                )
            }
            symbolSummaries = eventSummaries
        }
        
        guard !symbolSummaries.isEmpty else {
            // No cached data - return neutral
            return HermesQuickSentiment(
                symbol: symbol,
                score: 50,
                bullishPercent: 50,
                bearishPercent: 50,
                newsCount: 0,
                source: .fallback,
                lastUpdated: Date()
            )
        }
        
        // Calculate average sentiment from cached summaries
        let totalScore = symbolSummaries.reduce(0.0) { $0 + Double($1.impactScore) }
        let avgScore = totalScore / Double(symbolSummaries.count)
        
        // Calculate bullish/bearish percentages
        let positiveCount = symbolSummaries.filter { $0.impactScore >= 55 }.count
        let negativeCount = symbolSummaries.filter { $0.impactScore <= 45 }.count
        let total = symbolSummaries.count
        
        let bullishPercent = Double(positiveCount) / Double(total) * 100
        let bearishPercent = Double(negativeCount) / Double(total) * 100
        
        return HermesQuickSentiment(
            symbol: symbol,
            score: avgScore,
            bullishPercent: bullishPercent,
            bearishPercent: bearishPercent,
            newsCount: symbolSummaries.count,
            source: .llm,
            lastUpdated: symbolSummaries.first?.createdAt ?? Date()
        )
    }
    
    /// Gets recent news summaries for a symbol from cache
    func getCachedSummaries(for symbol: String, count: Int = 5) -> [HermesSummary] {
        var symbolSummaries = cache.values.filter {
            $0.symbol.uppercased() == symbol.uppercased() ||
            $0.symbol.uppercased() == symbol.replacingOccurrences(of: ".IS", with: "").uppercased()
        }
        .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }

        if symbolSummaries.isEmpty {
            symbolSummaries = eventStore.getEvents(for: symbol).map { event in
                HermesSummary(
                    id: event.articleId,
                    symbol: event.symbol,
                    summaryTR: event.rationaleShort,
                    impactCommentTR: event.rationaleShort,
                    impactScore: Int(max(0.0, min(event.finalScore, 100.0))),
                    relatedSectors: [],
                    rippleEffectScore: Int(max(0.0, min(event.severity, 100.0))),
                    createdAt: event.createdAt,
                    mode: .full,
                    publishedAt: event.publishedAt,
                    sourceReliability: event.sourceReliability / 100.0
                )
            }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
        }
        
        return Array(symbolSummaries.prefix(count))
    }
    
    private func persistCache() {
        let snapshot = self.cache
        Task {
            await ArgusDataStore.shared.save(snapshot, key: "argus_hermes_cache")
        }
    }

    func getCachedEvents(for symbol: String) -> [HermesEvent] {
        return eventStore.getEvents(for: symbol)
    }
    
    private func buildBatchPrompt(_ articles: [NewsArticle], isGeneral: Bool = false) -> String {
        var articlesText = ""
        for (index, article) in articles.enumerated() {
            articlesText += """
            [NEWS \(index + 1)]
            ID: \(article.id)
            Symbol: \(article.symbol)
            Headline: \(article.headline)
            Summary: \(article.summary ?? "")

            """
        }

        // T3.8: Türkçe finansal jargon kalibrasyonu — BIST haberlerinde sık geçen
        // Türkiye'ye özgü terimleri few-shot örneklerle LLM'e tanıt.
        let hasBistArticle = articles.contains { $0.symbol.uppercased().hasSuffix(".IS") }
        let trGlossary = hasBistArticle ? """

        TÜRKÇE FİNANSAL JARGON SÖZLÜĞÜ (BIST hisseleri için):
        - KAP açıklaması: Resmî zorunlu bildirim; içerikten olumlu/olumsuzluk çıkarılır.
        - BES (Bireysel Emeklilik): Uzun vadeli birikim; doğrudan hisse sentiment'ine etki etmez (NEUTRAL).
        - Repo / TLREF: Para piyasası faiz oranı; yükselişi banka marjlarına negatif.
        - Açığa satış izni: Hisse üzerinde short pozisyon serbestliği; çoğunlukla NEGATIVE.
        - Açığa satış yasağı: Short engellendi; kısa vadeli POSITIVE.
        - Bedelli / bedelsiz sermaye artırımı: Bedelli sulandırıcı (NEGATIVE), bedelsiz nötr-olumlu.
        - KKM (Kur Korumalı Mevduat): Bankalar için maliyet kalemi; aşırı artışı banka NPV'sine baskı.
        - VİOP (Vadeli İşlem ve Opsiyon): Türev piyasası; haberi doğrudan hisseyi etkilemeyebilir.
        - Temettü: Nakit kar payı; tarih yaklaşırken pozitif, sonrasında düşüş normal.
        - Genel Kurul: Stratejik karar toplantısı; içerik bağımlı (yönetim değişikliği → impact yüksek).

        ÖRNEK 1 (Türkçe):
          Haber: "GARAN üçüncü çeyrekte 12 milyar TL net kar açıkladı, beklenti 9.5 milyardı."
          → sentiment: POSITIVE, impact_score: 78
          → summary_tr: "Garanti BBVA 3Ç karı 12 milyar TL ile beklentinin %26 üzerinde geldi."

        ÖRNEK 2 (Türkçe):
          Haber: "SISE bedelli sermaye artırımı kararı aldı, hissedarlara %20 oranında."
          → sentiment: NEGATIVE, impact_score: 30
          → summary_tr: "Şişecam %20'lik bedelli sermaye artırımıyla sulandırma riski getiriyor."

        """ : ""

        // Global feed için ek talimat
        let symbolInstruction = isGeneral ? """

        ÖNEMLİ - SEMBOL TESPİTİ:
        Bu haberler genel piyasa haberleri. Her haber için:
        1. Haberde bahsedilen ANA şirketi/ticker'ı tespit et (örn: "Apple" → "AAPL", "Tesla" → "TSLA")
        2. Eğer haber birden fazla şirketi ilgilendiriyorsa, en çok etkilenen şirketi seç
        3. Eğer belirli bir şirket yoksa, sektörü belirle (örn: "Tech", "Energy", "Crypto")
        4. JSON'da "detected_symbol" alanına tespit ettiğin ticker'ı yaz

        """ : ""
        
        return """
        Sen Argus Terminal içindeki Hermes v2.3 modülüsün.
        Görevin aşağıdaki haberleri finansal ve BAĞLAMSAL açıdan analiz etmek.
        \(trGlossary)\(symbolInstruction)
        GİRDİ:
        \(articlesText)
        
        GÖREV:
        Her bir haber için analiz yap ve JSON üret.
        
        PUANLAMA KURALLARI (KESİN UYULMALI):
        - POSITIVE: 65 - 100 arası. (65 = Hafif Olumlu, 100 = Game Changer)
        - NEGATIVE: 0 - 35 arası. (0 = İflas/Kriz, 35 = Hafif Olumsuz)
        - NEUTRAL: 45 - 55 arası. (Piyasayı etkilemez)
        * Asla Sentiment ile Puan çelişmemeli (Örn: Positive deyip 40 verme).
        
        KURALLAR:
        1. summary_tr: Türkçe 1 cümlelik net özet.
        2. impact_comment_tr: "Hisse için [olumlu/olumsuz/nötr] bir gelişme." şeklinde 1 cümlelik yorum.
        3. sentiment: "POSITIVE", "NEGATIVE" veya "NEUTRAL" (BÜYÜK HARF).
        4. impact_score: Yukarıdaki aralıklara göre bir tamsayı.
        5. related_sectors: İngilizce sektör etiketleri (Örn: "Energy", "Tech").
        6. ripple_effect_score: Piyasaya yayılma potansiyeli (0-100).
        7. detected_symbol: Haberin ilgili olduğu ticker (örn: "AAPL", "TSLA"). Belirsizse boş bırak.
        
        ÇIKTI FORMATI (JSON OBJE):
        {
          "results": [
            {
              "id": "Haber ID'si aynen kopyalanmalı",
              "detected_symbol": "AAPL",
              "summary_tr": "...",
              "impact_comment_tr": "...",
              "sentiment": "POSITIVE",
              "impact_score": 75,
              "related_sectors": ["Sector1"],
              "ripple_effect_score": 60
            }
          ]
        }
        """
    }

    private func buildEventPrompt(_ articles: [NewsArticle], scope: HermesEventScope, isGeneral: Bool) -> String {
        var articlesText = ""
        for (index, article) in articles.enumerated() {
            articlesText += """
            [HABER \(index + 1)]
            ID: \(article.id)
            Symbol: \(article.symbol)
            Headline: \(article.headline)
            Summary: \(article.summary ?? "")
            Source: \(article.source)
            PublishedAt: \(article.publishedAt)
            
            """
        }
        
        let eventList = (scope == .bist) ? HermesPromptLexicon.bistEventTypes : HermesPromptLexicon.globalEventTypes
        let eventListText = eventList.joined(separator: ", ")

        // T3.8: BIST event'leri için Türkçe finansal jargon sözlüğü — KAP/BES/KKM/bedelli
        // terimlerini event_type ve sentiment kararına eşitlemek için.
        let hasBistArticle = articles.contains { $0.symbol.uppercased().hasSuffix(".IS") }
        let trGlossary = (hasBistArticle || scope == .bist) ? """

        TÜRKÇE FİNANSAL JARGON SÖZLÜĞÜ (BIST haberlerinde sık geçer):
        - KAP açıklaması: Resmî zorunlu bildirim — içeriği analiz et, başlık tek başına nötr değil.
        - Bedelli sermaye artırımı: Sulandırıcı (NEGATIVE/mixed); rated_capital_raise event_type'ı uygun.
        - Bedelsiz sermaye artırımı: Genelde nötr-pozitif; sembolik etkili.
        - KKM (Kur Korumalı Mevduat): Banka maliyet baskısı; bankalar için NEGATIVE.
        - Açığa satış izni: Hisseye short serbestliği → NEGATIVE; yasak kalkması POSITIVE.
        - Temettü: Nakit kar payı dağıtımı; tarih öncesi POSITIVE, sonrası fiyat düşüşü teknik beklenir.
        - Genel Kurul: Yönetim değişikliği varsa severity yüksek; rutin onaylar nötr.
        - VİOP: Türev piyasa; doğrudan spot fiyatı etkilemez (nötr).
        - Repo / TLREF: Faiz oranı; bankalar için marja baskı.

        """ : ""

        let symbolInstruction = isGeneral ? """

        HABER SEMBOL TESPITI:
        - Haberde en cok etkilenen ana sirketi/ticker'i tespit et.
        - Eger belirgin sirket yoksa "MARKET" yaz.

        """ : ""

        return """
        Hermes V3 icin haber etiketleme gorevi.
        \(trGlossary)\(symbolInstruction)
        Kullanilacak event_type listesi:
        \(eventListText)
        
        Beklenen JSON semasi:
        {
          "results": [
            {
              "id": "ARTICLE_ID",
              "detected_symbol": "AAPL",
              "event_type": "earnings_surprise",
              "polarity": "positive|negative|mixed",
              "sentiment_label": "strong_positive|weak_positive|neutral|weak_negative|strong_negative",
              "severity": 0-100,
              "impact_score": 0-100,
              "confidence": 0.0-1.0,
              "horizon_hint": "intraday|1-3d|multiweek",
              "summary_tr_short": "Turkce, tek cumlelik haber ozeti (max 140 karakter)",
              "rationale_short": "en fazla 200 karakter",
              "evidence_quotes": ["max 160 karakter", "max 160 karakter"],
              "risk_flags": ["rumor","low_reliability","priced_in","regulatory_uncertainty"]
            }
          ]
        }
        
        KURALLAR:
        - sentiment_label, haberi okuyup etkisini yorumlayarak secilmeli.
        - sentiment_label, polarity, severity ve impact_score birbiriyle celismemeli.
        - impact_score LLM tarafindan dogrudan belirlenmeli (otomatik hesap yok).
        - score bantlari:
          strong_positive: 75-100
          weak_positive: 60-74
          neutral: 45-59
          weak_negative: 30-44
          strong_negative: 0-29
        - strong_* sadece gercekten guclu ve beklenmedik etki varsa kullanilmali.
        - weak_positive / weak_negative secimi sadece etki zayifsa yapilmali, varsayilan secim olarak kullanma.
        - summary_tr_short zorunlu; Turkce, tek cumle ve net olmali.
        - rationale_short yalnizca piyasa etkisini anlatmali; "Hermes", "AI", "model", "LLM", "analiz", "prompt", "sistem" gibi ifadeler kullanilmamali.
        
        HABERLER:
        \(articlesText)
        """
    }
}

// MARK: - Hermes Prompt Lexicon

private enum HermesPromptLexicon {
    static let globalEventTypes: [String] = [
        "earnings_surprise", "guidance_raise", "guidance_cut", "revenue_miss", "margin_pressure",
        "buyback_announcement", "dividend_change", "m_and_a", "regulatory_action", "legal_risk",
        "product_launch", "supply_chain_disruption", "macro_shock", "rating_upgrade",
        "rating_downgrade", "insider_activity", "sector_rotation", "geopolitical_risk",
        "fraud_allegation", "leadership_change"
    ]
    
    static let bistEventTypes: [String] = [
        "kap_disclosure", "bedelli_capital_increase", "bedelsiz_bonus_issue", "temettu_announcement",
        "ihale_kazandi", "ihale_iptal", "spk_action", "ortaklik_anlasmasi", "borclanma_ihraci",
        "kar_uyarisi", "kur_riski", "ihracat_siparisi", "yatirim_plani", "tesis_acilisi",
        "sektor_tesvik", "dava_olumsuz", "dava_olumlu", "yonetim_degisim", "operasyonel_ariza"
    ]
}

private struct HermesEventExtractionResponse: Codable {
    let results: [HermesEventExtractionItem]
}

private struct HermesEventExtractionItem: Codable {
    let id: String
    let detected_symbol: String?
    let event_type: String?
    let polarity: String?
    let sentiment_label: String?
    let severity: Double?
    let impact_score: Double?
    let confidence: Double?
    let horizon_hint: String?
    let summary_tr_short: String?
    let rationale_short: String?
    let evidence_quotes: [String]?
    let risk_flags: [String]?
}
