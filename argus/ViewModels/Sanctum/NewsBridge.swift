import Foundation
import Combine
import SwiftUI

/// SanctumViewModel'in haber/sentiment katmanı:
/// - HermesStateViewModel SSoT'tan reactive read
/// - On-demand RSS/Yahoo fetch + Hermes LLM analizi
@MainActor
final class NewsBridge: ObservableObject {
    let symbol: String

    @Published var newsInsights: [NewsInsight] = []
    @Published var hermesEvents: [HermesEvent] = []
    @Published var kulisEvents: [HermesEvent] = []
    @Published var isLoadingNews: Bool = false
    @Published var newsErrorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init(symbol: String) {
        self.symbol = symbol
        setupBindings()
    }

    private func setupBindings() {
        HermesStateViewModel.shared.$newsInsightsBySymbol
            .map { $0[self.symbol] ?? [] }
            .receive(on: RunLoop.main)
            .assign(to: \.newsInsights, on: self)
            .store(in: &cancellables)

        HermesStateViewModel.shared.$hermesEventsBySymbol
            .map { $0[self.symbol] ?? [] }
            .receive(on: RunLoop.main)
            .assign(to: \.hermesEvents, on: self)
            .store(in: &cancellables)

        HermesStateViewModel.shared.$kulisEventsBySymbol
            .map { $0[self.symbol] ?? [] }
            .receive(on: RunLoop.main)
            .assign(to: \.kulisEvents, on: self)
            .store(in: &cancellables)
    }

    /// On-demand: haber çek + LLM analizi yap + HermesStateViewModel'e yaz.
    /// Subscription chain'i sayesinde lokal property'ler otomatik güncellenir.
    func analyzeOnDemand() async {
        isLoadingNews = true
        newsErrorMessage = nil
        defer { isLoadingNews = false }

        let isBist = symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)

        do {
            let articles: [NewsArticle]
            if isBist {
                articles = try await RSSNewsProvider().fetchNews(symbol: symbol, limit: 20)
            } else {
                articles = try await GoogleNewsRSSProvider.shared.fetchNews(symbol: symbol, limit: 15)
            }

            guard !articles.isEmpty else {
                newsErrorMessage = "Bu sembol için haber bulunamadı."
                print("⚠️ NewsBridge: \(symbol) için haber bulunamadı")
                return
            }

            print("✅ NewsBridge: \(symbol) için \(articles.count) haber bulundu")

            let scope: HermesEventScope = isBist ? .bist : .global
            let events = try await HermesLLMService.shared.analyzeEvents(
                articles: articles,
                scope: scope,
                isGeneral: false
            )

            print("✅ NewsBridge: \(symbol) için \(events.count) event analiz edildi")

            let insights = events.map { event -> NewsInsight in
                let sentiment: NewsSentiment = event.sentimentLabel ?? .neutral

                let delayPenalty = HermesEventScoring.delayFactor(
                    ageMinutes: max(0.0, Date().timeIntervalSince(event.publishedAt) / 60.0)
                )

                let detail = """
                Bu haber \(event.polarity == .positive ? "olumlu" : (event.polarity == .negative ? "olumsuz" : "karma")) etki üretiyor.
                Şiddet: \(Int(event.severity))/100, Kaynak güveni: \(Int(event.sourceReliability))/100.
                Gecikme etkisi: %\(Int(delayPenalty * 100)).
                """

                return NewsInsight(
                    id: UUID(),
                    symbol: event.symbol,
                    articleId: event.articleId,
                    headline: event.headline,
                    summaryTRLong: detail,
                    impactSentenceTR: event.rationaleShort,
                    sentiment: sentiment,
                    confidence: event.confidence,
                    impactScore: event.finalScore,
                    relatedTickers: nil,
                    createdAt: event.createdAt
                )
            }

            HermesStateViewModel.shared.newsInsightsBySymbol[symbol] = insights
            if isBist {
                HermesStateViewModel.shared.kulisEventsBySymbol[symbol] = events
            } else {
                HermesStateViewModel.shared.hermesEventsBySymbol[symbol] = events
            }

            print("✅ NewsBridge: \(symbol) analiz tamamlandı - \(insights.count) insight")

        } catch {
            newsErrorMessage = "Haber analizi yapılamadı: \(error.localizedDescription)"
            print("❌ NewsBridge: \(symbol) analiz hatası: \(error)")
        }
    }
}
