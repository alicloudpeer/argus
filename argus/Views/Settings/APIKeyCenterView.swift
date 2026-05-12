import SwiftUI

// MARK: - APIKeyCenterView (2026-05-11 sade yeniden yazım)
//
// Eski: TerminalSection + Card-pattern + monospace heavy + ASCII Türkçe + sistem renkleri.
// Yeni: MarketView dili — sade liste, kart yok, monospace yalnız anahtar string'inde,
// CAPS yok, status sade text. Tap → bottom sheet ile edit.
//
// Davranış aynen korunuyor: APIKeyStore + APIKeyVerifier + TCMBDataService.

struct APIKeyCenterView: View {

    // MARK: Tipler

    enum KeyFilter: String, CaseIterable, Identifiable {
        case all       = "Tümü"
        case configured = "Tanımlı"
        case missing    = "Eksik"
        var id: String { rawValue }
    }

    enum Category: String, CaseIterable, Identifiable {
        case market        = "Piyasa"
        case macro         = "Makro"
        case intelligence  = "Zekâ"
        case infrastructure = "Altyapı"
        var id: String { rawValue }
    }

    enum Source {
        case provider(APIProvider)
        case customKey(String)
    }

    enum TestMode {
        case provider(APIProvider)
        case tcmb
        case unsupported
    }

    struct KeyEntry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let placeholder: String
        let category: Category
        let source: Source
        let testMode: TestMode
        /// Sağlayıcının anahtar/hesap açma sayfası.
        let signUpURL: URL?
    }

    struct TestState {
        let success: Bool
        let message: String
    }

    // MARK: State

    @State private var searchText = ""
    @State private var filter: KeyFilter = .all
    @State private var categoryFilter: Category?
    @State private var persisted: [String: String] = [:]
    @State private var testStates: [String: TestState] = [:]
    @State private var selectedEntry: KeyEntry?

    // MARK: - Sağlayıcı kataloğu

    private var entries: [KeyEntry] {
        [
            // Piyasa
            KeyEntry(
                id: "alpaca_key_id",
                title: "Alpaca · Key ID",
                subtitle: "US hisse anlık fiyat · 200 r/dk · paper",
                placeholder: "PK... (20 karakter)",
                category: .market,
                source: .customKey(AlpacaProvider.keyIDStoreID),
                testMode: .unsupported,
                signUpURL: URL(string: "https://alpaca.markets/")
            ),
            KeyEntry(
                id: "alpaca_secret",
                title: "Alpaca · Secret",
                subtitle: "Paper hesap secret · ~40 karakter",
                placeholder: "Alpaca Secret Key",
                category: .market,
                source: .customKey(AlpacaProvider.secretStoreID),
                testMode: .unsupported,
                signUpURL: URL(string: "https://alpaca.markets/")
            ),
            KeyEntry(
                id: "fmp",
                title: "Financial Modeling Prep",
                subtitle: "Profil, haber ve finansal tablo verileri",
                placeholder: "FMP API Key",
                category: .market,
                source: .provider(.fmp),
                testMode: .provider(.fmp),
                signUpURL: URL(string: "https://site.financialmodelingprep.com/developer/docs/dashboard")
            ),
            KeyEntry(
                id: "twelve_data",
                title: "Twelve Data",
                subtitle: "Anlık fiyat ve zaman serisi",
                placeholder: "Twelve Data API Key",
                category: .market,
                source: .provider(.twelveData),
                testMode: .provider(.twelveData),
                signUpURL: URL(string: "https://twelvedata.com/account/api-keys")
            ),
            KeyEntry(
                id: "tiingo",
                title: "Tiingo",
                subtitle: "Alternatif fiyat ve temel veri",
                placeholder: "Tiingo API Key",
                category: .market,
                source: .provider(.tiingo),
                testMode: .provider(.tiingo),
                signUpURL: URL(string: "https://www.tiingo.com/account/api/token")
            ),
            KeyEntry(
                id: "eodhd",
                title: "EODHD",
                subtitle: "Global hisse · ETF · screener",
                placeholder: "EODHD API Key",
                category: .market,
                source: .provider(.eodhd),
                testMode: .provider(.eodhd),
                signUpURL: URL(string: "https://eodhd.com/cp/settings")
            ),
            KeyEntry(
                id: "alpha_vantage",
                title: "Alpha Vantage",
                subtitle: "Teknik ve temel veri",
                placeholder: "Alpha Vantage API Key",
                category: .market,
                source: .provider(.alphaVantage),
                testMode: .provider(.alphaVantage),
                signUpURL: URL(string: "https://www.alphavantage.co/support/#api-key")
            ),
            KeyEntry(
                id: "marketstack",
                title: "MarketStack",
                subtitle: "Alternatif market feed",
                placeholder: "MarketStack API Key",
                category: .market,
                source: .provider(.marketstack),
                testMode: .provider(.marketstack),
                signUpURL: URL(string: "https://marketstack.com/signup")
            ),
            KeyEntry(
                id: "finnhub",
                title: "Finnhub",
                subtitle: "Yedek piyasa verisi · 60 r/dk",
                placeholder: "Finnhub API Key",
                category: .market,
                source: .provider(.finnhub),
                testMode: .provider(.finnhub),
                signUpURL: URL(string: "https://finnhub.io/register")
            ),
            KeyEntry(
                id: "collectapi",
                title: "CollectAPI",
                subtitle: "BIST yardımcı veri girişi",
                placeholder: "CollectAPI Key",
                category: .market,
                source: .customKey("collectapi_key"),
                testMode: .unsupported,
                signUpURL: URL(string: "https://collectapi.com/")
            ),

            // Makro
            KeyEntry(
                id: "tcmb_evds",
                title: "TCMB EVDS",
                subtitle: "Türkiye makro veri kaynağı",
                placeholder: "TCMB API Key",
                category: .macro,
                source: .customKey("tcmb_evds_api_key"),
                testMode: .tcmb,
                signUpURL: URL(string: "https://evds2.tcmb.gov.tr/index.php?/evds/login")
            ),
            KeyEntry(
                id: "fred",
                title: "FRED",
                subtitle: "Küresel makro indikatörler",
                placeholder: "FRED API Key",
                category: .macro,
                source: .provider(.fred),
                testMode: .provider(.fred),
                signUpURL: URL(string: "https://fred.stlouisfed.org/docs/api/api_key.html")
            ),

            // Zekâ
            KeyEntry(
                id: "groq",
                title: "Groq",
                subtitle: "Llama tabanlı model çağrıları",
                placeholder: "Groq API Key (gsk_...)",
                category: .intelligence,
                source: .provider(.groq),
                testMode: .provider(.groq),
                signUpURL: URL(string: "https://console.groq.com/keys")
            ),
            KeyEntry(
                id: "cerebras",
                title: "Cerebras",
                subtitle: "Qwen 3 · 1M token/gün ücretsiz",
                placeholder: "Cerebras API Key (csk-...)",
                category: .intelligence,
                source: .provider(.cerebras),
                testMode: .provider(.cerebras),
                signUpURL: URL(string: "https://cloud.cerebras.ai/platform")
            ),
            KeyEntry(
                id: "gemini",
                title: "Gemini",
                subtitle: "Google model ailesi",
                placeholder: "Gemini API Key (AIza...)",
                category: .intelligence,
                source: .provider(.gemini),
                testMode: .provider(.gemini),
                signUpURL: URL(string: "https://aistudio.google.com/app/apikey")
            ),
            KeyEntry(
                id: "glm",
                title: "GLM",
                subtitle: "Zhipu GLM erişimi",
                placeholder: "GLM API Key",
                category: .intelligence,
                source: .provider(.glm),
                testMode: .provider(.glm),
                signUpURL: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")
            ),
            KeyEntry(
                id: "deepseek",
                title: "DeepSeek",
                subtitle: "DeepSeek model erişimi",
                placeholder: "DeepSeek API Key (sk-...)",
                category: .intelligence,
                source: .provider(.deepSeek),
                testMode: .provider(.deepSeek),
                signUpURL: URL(string: "https://platform.deepseek.com/api_keys")
            ),

            // Altyapı
            KeyEntry(
                id: "massive",
                title: "Massive",
                subtitle: "Opsiyon ve zincir verisi",
                placeholder: "Massive Token",
                category: .infrastructure,
                source: .provider(.massive),
                testMode: .provider(.massive),
                signUpURL: nil
            ),
            KeyEntry(
                id: "pinecone",
                title: "Pinecone",
                subtitle: "Vektör veritabanı erişimi",
                placeholder: "Pinecone API Key",
                category: .infrastructure,
                source: .provider(.pinecone),
                testMode: .provider(.pinecone),
                signUpURL: URL(string: "https://app.pinecone.io/")
            )
        ]
    }

    // MARK: - Computed

    private var filteredEntries: [KeyEntry] {
        entries.filter { entry in
            if let categoryFilter, entry.category != categoryFilter { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                if !entry.title.lowercased().contains(q),
                   !entry.subtitle.lowercased().contains(q) {
                    return false
                }
            }
            let configured = !(persisted[entry.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
            switch filter {
            case .all:        return true
            case .configured: return configured
            case .missing:    return !configured
            }
        }
    }

    private var grouped: [(Category, [KeyEntry])] {
        Category.allCases.compactMap { cat in
            let items = filteredEntries.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    private var configuredCount: Int {
        entries.reduce(0) {
            $0 + (persisted[$1.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        searchField
                            .padding(.horizontal, DesignTokens.Spacing.s14)
                            .padding(.top, DesignTokens.Spacing.md)
                            .padding(.bottom, DesignTokens.Spacing.sm)

                        categoryRow
                            .padding(.horizontal, DesignTokens.Spacing.s14)
                            .padding(.bottom, DesignTokens.Spacing.sm)

                        ForEach(grouped, id: \.0) { category, items in
                            sectionHeader(category.rawValue, count: items.count)
                            ForEach(items) { entry in
                                row(for: entry)
                            }
                        }

                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear(perform: loadValuesFromStorage)
        .onReceive(NotificationCenter.default.publisher(for: .argusKeyStoreDidUpdate)) { _ in
            loadValuesFromStorage()
        }
        .sheet(item: $selectedEntry) { entry in
            APIKeyEditSheet(
                entry: entry,
                initialValue: persisted[entry.id, default: ""],
                onSaved: { newValue in
                    persisted[entry.id] = newValue
                    testStates[entry.id] = nil
                },
                onCleared: {
                    persisted[entry.id] = ""
                    testStates[entry.id] = nil
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(spacing: DesignTokens.Spacing.s10) {
            HStack(alignment: .center) {
                Text("API anahtarları")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(configuredCount) / \(entries.count)")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            HStack(spacing: 0) {
                tabButton(title: "Tümü",    value: .all)
                tabButton(title: "Tanımlı", value: .configured)
                tabButton(title: "Eksik",   value: .missing)
                Spacer()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s14)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.s10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: DesignTokens.BorderWidth.hairline)
        }
    }

    @ViewBuilder
    private func tabButton(title: String, value: KeyFilter) -> some View {
        let isSelected = filter == value
        Button(action: { withAnimation(.easeInOut(duration: 0.18)) { filter = value } }) {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Fonts.custom(
                        size: 13,
                        weight: isSelected ? .medium : .regular
                    ))
                    .foregroundColor(isSelected
                                     ? DesignTokens.Colors.textPrimary
                                     : DesignTokens.Colors.textSecondary)
                Rectangle()
                    .fill(isSelected ? DesignTokens.Colors.textPrimary : Color.clear)
                    .frame(height: 1.5)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Search & Category

    private var searchField: some View {
        HStack(spacing: DesignTokens.Spacing.s10) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            TextField("Sağlayıcı ara", text: $searchText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.s10)
        .background(DesignTokens.Colors.Overlay.l03)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
        )
        .cornerRadius(DesignTokens.Radius.r10)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                categoryItem(title: "Tümü", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(Category.allCases) { c in
                    categoryItem(title: c.rawValue, isSelected: categoryFilter == c) {
                        categoryFilter = (categoryFilter == c) ? nil : c
                    }
                }
            }
        }
    }

    private func categoryItem(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Fonts.custom(
                    size: 13,
                    weight: isSelected ? .medium : .regular
                ))
                .foregroundColor(isSelected
                                 ? DesignTokens.Colors.textPrimary
                                 : DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section & Row

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Spacer()
            Text("\(count)")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.s14)
        .padding(.top, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.s6)
    }

    private func row(for entry: KeyEntry) -> some View {
        let configured = !(persisted[entry.id, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
        return Button {
            selectedEntry = entry
        } label: {
            HStack(spacing: DesignTokens.Spacing.s10) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(entry.title)
                        .font(DesignTokens.Fonts.custom(size: 15))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(entry.subtitle)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(configured ? "Tanımlı" : "Eksik")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(configured
                                     ? DesignTokens.Colors.success
                                     : DesignTokens.Colors.textTertiary)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.s14)
            .padding(.vertical, DesignTokens.Spacing.s14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: DesignTokens.BorderWidth.hairline)
                .padding(.leading, DesignTokens.Spacing.s14)
        }
    }

    // MARK: - I/O

    private func loadValuesFromStorage() {
        var snapshot: [String: String] = [:]
        for entry in entries {
            snapshot[entry.id] = readValue(for: entry)
        }
        persisted = snapshot
    }

    private func readValue(for entry: KeyEntry) -> String {
        switch entry.source {
        case .provider(let p):
            return APIKeyStore.shared.getKey(for: p) ?? ""
        case .customKey(let key):
            return APIKeyStore.shared.getCustomValue(for: key) ?? ""
        }
    }
}
