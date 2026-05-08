import SwiftUI
import Combine

/// V5 mockup dil bütünlüğü için in-place refactor.
/// 2026-04-22 Sprint 3 — üst chrome `ArgusNavHeader`'a alındı (bars3 holo/text
/// deco + back + refresh action, status satırı scope + yüklenme durumunu
/// gösteriyor). Scope toggle, feed içerikleri ve `HermesFeedState` veri akışı
/// dokunulmadı.
struct HermesFeedView: View {
    @ObservedObject private var market = MarketViewModel.shared
    @StateObject private var feedState = HermesFeedState()
    @State private var selectedScope = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            InstitutionalTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "Haber",
                    subtitle: "Olay, analiz, akış",
                    leadingDeco: .back(onTap: { dismiss() }),
                    titlePill: nil,
                    actions: [
                        .custom(sfSymbol: "arrow.clockwise",
                                action: {
                                    Task { await feedState.loadFeed(scope: selectedScope, watchlist: market.watchlist) }
                                })
                    ],
                    status: headerStatus
                )

                ScopeSelectorBar(selectedScope: $selectedScope)
                    .padding(.vertical, 12)
                    .background(InstitutionalTheme.Colors.background)
                    .onChange(of: selectedScope) { _, newValue in
                        Task { await feedState.loadFeed(scope: newValue, watchlist: market.watchlist) }
                    }

                if feedState.isLoading {
                    LoadingStateView()
                } else if let error = feedState.errorMessage {
                    ErrorStateView(message: error) {
                        Task { await feedState.loadFeed(scope: selectedScope, watchlist: market.watchlist) }
                    }
                } else if feedState.insights.isEmpty && feedState.events.isEmpty && feedState.rawArticles.isEmpty {
                    EmptyFeedView(scope: selectedScope) {
                        Task { await feedState.loadFeed(scope: selectedScope, watchlist: market.watchlist) }
                    }
                } else {
                    feedContent
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await feedState.loadFeed(scope: selectedScope, watchlist: market.watchlist)
        }
    }

    private var headerStatus: ArgusNavHeader.Status {
        if feedState.isLoading {
            return .custom(dotColor: InstitutionalTheme.Colors.textTertiary,
                           label: "Taranıyor",
                           trailing: scopeLabel)
        }
        if feedState.errorMessage != nil {
            return .custom(dotColor: InstitutionalTheme.Colors.crimson,
                           label: "Hata",
                           trailing: scopeLabel)
        }
        let total = feedState.events.count + feedState.insights.count + feedState.rawArticles.count
        if total == 0 {
            return .custom(dotColor: InstitutionalTheme.Colors.textTertiary,
                           label: "Akış boş",
                           trailing: scopeLabel)
        }
        return .custom(dotColor: InstitutionalTheme.Colors.aurora,
                       label: "\(total) kayıt",
                       trailing: scopeLabel)
    }

    private var scopeLabel: String {
        selectedScope == 0 ? "Takip" : "Piyasa"
    }

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !feedState.events.isEmpty {
                    ForEach(feedState.events) { event in
                        HermesEventCompactCard(event: event)
                            .padding(.horizontal)
                    }
                }

                if !feedState.insights.isEmpty && feedState.events.isEmpty {
                    ForEach(feedState.insights) { insight in
                        if insight.symbol != "MARKET" && insight.symbol != "GENERAL" {
                            NavigationLink(destination: ArgusSanctumView(symbol: insight.symbol)) {
                                HermesInsightCard(insight: insight)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            HermesInsightCard(insight: insight)
                        }
                    }
                    .padding(.horizontal)
                }

                if feedState.events.isEmpty && feedState.insights.isEmpty && !feedState.rawArticles.isEmpty {
                    ForEach(feedState.rawArticles.prefix(40)) { article in
                        RawNewsCard(article: article)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await feedState.loadFeed(scope: selectedScope, watchlist: market.watchlist)
        }
    }
}

@MainActor
class HermesFeedState: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var events: [HermesEvent] = []
    @Published var insights: [NewsInsight] = []
    @Published var rawArticles: [NewsArticle] = []

    func loadFeed(scope: Int, watchlist: [String]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if scope == 0 {
                await loadWatchlistFeed(watchlist: watchlist)
            } else {
                await loadGeneralFeed()
            }
        }
    }

    private func loadWatchlistFeed(watchlist: [String]) async {
        guard !watchlist.isEmpty else {
            errorMessage = "Takip listeniz boş. Önce hisse ekleyin."
            return
        }

        var allEvents: [HermesEvent] = []
        var allInsights: [NewsInsight] = []
        var allRawArticles: [NewsArticle] = []

        let hermesVM = HermesStateViewModel.shared

        for symbol in watchlist {
            let isBist = symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
            
            if let cachedRaw = hermesVM.newsBySymbol[symbol], !cachedRaw.isEmpty {
                allRawArticles.append(contentsOf: cachedRaw)
            }

            if isBist {
                if let cached = hermesVM.kulisEventsBySymbol[symbol], !cached.isEmpty {
                    allEvents.append(contentsOf: cached)
                    continue
                }
            } else {
                if let cached = hermesVM.hermesEventsBySymbol[symbol], !cached.isEmpty {
                    allEvents.append(contentsOf: cached)
                    continue
                }
            }

            if let cachedInsights = hermesVM.newsInsightsBySymbol[symbol], !cachedInsights.isEmpty {
                allInsights.append(contentsOf: cachedInsights)
                continue
            }

            do {
                let articles: [NewsArticle]
                if isBist {
                    articles = try await RSSNewsProvider().fetchNews(symbol: symbol, limit: 10)
                } else {
                    articles = try await GoogleNewsRSSProvider.shared.fetchNews(symbol: symbol, limit: 8)
                }

                guard !articles.isEmpty else { continue }
                allRawArticles.append(contentsOf: articles)
                hermesVM.newsBySymbol[symbol] = articles

                let scope: HermesEventScope = isBist ? .bist : .global
                let events = try await HermesLLMService.shared.analyzeEvents(
                    articles: articles,
                    scope: scope,
                    isGeneral: false
                )

                allEvents.append(contentsOf: events)

                if isBist {
                    hermesVM.kulisEventsBySymbol[symbol] = events
                } else {
                    hermesVM.hermesEventsBySymbol[symbol] = events
                }

                print("✅ HermesFeed: \(symbol) için \(events.count) event yüklendi")

            } catch {
                print("⚠️ HermesFeed: \(symbol) hatası: \(error.localizedDescription)")
            }
        }

        self.events = allEvents.sorted { $0.publishedAt > $1.publishedAt }
        self.insights = allInsights.sorted { $0.createdAt > $1.createdAt }
        self.rawArticles = Array(Dictionary(grouping: allRawArticles, by: { $0.id }).values.compactMap { $0.first })
            .sorted { $0.publishedAt > $1.publishedAt }

        if events.isEmpty && insights.isEmpty && rawArticles.isEmpty {
            errorMessage = "Takip listenizdeki hisseler için haber bulunamadı."
        }
    }

    private func loadGeneralFeed() async {
        do {
            let articles = try await RSSNewsProvider().fetchNews(symbol: "GENERAL", limit: 25)
            self.rawArticles = articles.sorted { $0.publishedAt > $1.publishedAt }

            guard !articles.isEmpty else {
                errorMessage = "Genel piyasa haberi bulunamadı."
                return
            }

            do {
                let events = try await HermesLLMService.shared.analyzeEvents(
                    articles: articles,
                    scope: .bist,
                    isGeneral: true
                )

                self.events = events.sorted { $0.publishedAt > $1.publishedAt }
                HermesStateViewModel.shared.hermesEventsBySymbol["GENERAL"] = events

                print("✅ HermesFeed: Genel piyasa için \(events.count) event yüklendi")
            } catch {
                self.events = []
                self.errorMessage = nil
                print("⚠️ HermesFeed: Genel piyasa analiz katmanı hatası, ham haberler listeleniyor: \(error.localizedDescription)")
            }

        } catch {
            errorMessage = "Haber analizi yapılamadı: \(error.localizedDescription)"
            print("❌ HermesFeed: Genel piyasa hatası: \(error)")
        }
    }
}

struct HermesEventCompactCard: View {
    let event: HermesEvent

    private var tone: ArgusChipTone {
        switch event.polarity {
        case .positive: return .aurora
        case .negative: return .crimson
        case .mixed:    return .titan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ArgusChip(event.symbol.uppercased(), tone: tone)
                Spacer()
                Text(timeAgo(event.publishedAt))
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }

            Text(event.headline)
                .font(InstitutionalTheme.Typography.body)
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(event.eventType.displayTitleTR.uppercased())
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    ArgusDot(color: tone.foreground, size: 5)
                    Text(sentimentLabel())
                        .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundColor(tone.foreground)
                }
            }

            Text(event.summaryTRShort ?? event.rationaleShort)
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                tag("SKOR %\(Int(event.finalScore))", tone: tone)
                tag("GÜVEN %\(Int(event.confidence * 100))", tone: .holo)
                tag(event.horizonHint.rawValue.uppercased(), tone: .neutral)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(tone.foreground.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    private func sentimentLabel() -> String {
        if let label = event.sentimentLabel { return label.displayTitle.uppercased() }
        switch event.polarity {
        case .positive: return "OLUMLU"
        case .negative: return "OLUMSUZ"
        case .mixed:    return "KARMA"
        }
    }

    private func tag(_ text: String, tone: ArgusChipTone) -> some View {
        ArgusChip(text, tone: tone)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct HermesInsightCard: View {
    let insight: NewsInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ArgusChip(insight.symbol.uppercased(), tone: .motor(.hermes), icon: .hermes)
                Spacer()
                Text(timeAgo(insight.createdAt))
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }

            Text(insight.headline)
                .font(InstitutionalTheme.Typography.body)
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .lineLimit(2)

            if !insight.impactSentenceTR.isEmpty {
                Text(insight.impactSentenceTR)
                    .font(InstitutionalTheme.Typography.caption)
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ArgusDot(color: sentimentTone(insight.sentiment).foreground, size: 5)
                    Text(insight.sentiment.displayTitle.uppercased())
                        .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundColor(sentimentTone(insight.sentiment).foreground)
                }
                Spacer()
                Text("ETKİ · %\(Int(insight.impactScore))")
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(impactColor(insight.impactScore))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(impactColor(insight.impactScore).opacity(0.18))
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(InstitutionalTheme.Colors.Motors.hermes.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    private func sentimentTone(_ s: NewsSentiment) -> ArgusChipTone {
        switch s {
        case .strongPositive: return .aurora
        case .weakPositive:   return .aurora
        case .neutral:        return .neutral
        case .weakNegative:   return .crimson
        case .strongNegative: return .crimson
        }
    }

    private func impactColor(_ score: Double) -> Color {
        if score > 60 { return InstitutionalTheme.Colors.aurora }
        if score < 40 { return InstitutionalTheme.Colors.crimson }
        return InstitutionalTheme.Colors.textSecondary
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct RawNewsCard: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ArgusChip(article.symbol.uppercased(), tone: .motor(.hermes))
                Spacer()
                Text(timeAgo(article.publishedAt))
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }

            Text(article.headline)
                .font(InstitutionalTheme.Typography.body)
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .lineLimit(3)

            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .semibold))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                Text(article.source.uppercased())
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(InstitutionalTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Haber akışı taranıyor")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
            Spacer()
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(DesignTokens.Fonts.custom(size: 28))
                .foregroundColor(InstitutionalTheme.Colors.crimson)

            Text(message)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            sadeFeedActionButton(icon: "arrow.clockwise",
                                 label: "Tekrar dene",
                                 action: onRetry)

            Spacer()
        }
    }
}

struct EmptyFeedView: View {
    let scope: Int
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "newspaper")
                .font(DesignTokens.Fonts.custom(size: 28))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)

            VStack(spacing: 4) {
                Text(scope == 0 ? "Takip listesi boş" : "Haber bulunamadı")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                Text(scope == 0 ? "Takip listenizdeki hisseler için haber bulunamadı."
                                : "Genel piyasa haberi bulunamadı.")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            sadeFeedActionButton(icon: "magnifyingglass",
                                 label: "Tara",
                                 action: onRetry)

            Spacer()
        }
    }
}

/// Sade aksiyon butonu — sentence label + hairline border.
private struct sadeFeedActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DesignTokens.Fonts.custom(size: 12))
                Text(label)
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
            }
            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(InstitutionalTheme.Colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ScopeSelectorBar: View {
    @Binding var selectedScope: Int

    var body: some View {
        HStack(spacing: 2) {
            ScopeButton(title: "Takip", isSelected: selectedScope == 0) {
                withAnimation(.spring(response: 0.3)) { selectedScope = 0 }
            }
            ScopeButton(title: "Piyasa", isSelected: selectedScope == 1) {
                withAnimation(.spring(response: 0.3)) { selectedScope = 1 }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(InstitutionalTheme.Colors.surface2)
        )
        .padding(.horizontal)
    }
}

struct ScopeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected
                                 ? InstitutionalTheme.Colors.textPrimary
                                 : InstitutionalTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? InstitutionalTheme.Colors.surface1
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
