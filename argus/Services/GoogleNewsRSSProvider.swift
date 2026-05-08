import Foundation

/// Fetches news from Google News RSS feeds. Routes to Turkish or
/// English locale based on whether the symbol is a BIST ticker (`.IS`
/// suffix). Replaces the misnamed `YahooFinanceNewsProvider`.
final class GoogleNewsRSSProvider: NewsProvider {
    static let shared = GoogleNewsRSSProvider()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchNews(symbol: String, limit: Int = 12) async throws -> [NewsArticle] {
        let isBist = symbol.uppercased().hasSuffix(".IS")
        let query = symbol.replacingOccurrences(of: ".IS", with: "")

        let baseUrl = "https://news.google.com/rss/search"
        let langParams = isBist ? "hl=tr-TR&gl=TR&ceid=TR:tr" : "hl=en-US&gl=US&ceid=US:en"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        guard let url = URL(string: "\(baseUrl)?q=\(encodedQuery)&count=\(limit)&\(langParams)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; ArgusBot/1.0)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let parser = RSSParser(limit: limit, sourceName: "Google News")
        let articles = parser.parse(data: data)

        return articles.map { article in
            NewsArticle(
                id: article.id,
                symbol: symbol,
                source: article.source.isEmpty ? "Google News" : article.source,
                headline: article.headline,
                summary: article.summary,
                url: article.url,
                publishedAt: article.publishedAt,
                fetchedAt: article.fetchedAt
            )
        }
    }
}
