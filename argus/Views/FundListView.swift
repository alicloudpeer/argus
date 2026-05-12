import SwiftUI

// MARK: - Fund List View
// Main view for displaying the TEFAS fund watchlist

struct FundListView: View {
    @StateObject private var dataManager = FundDataManager.shared
    
    @State private var selectedCategory: FundCategory? = nil
    @State private var sortOption: FundDataManager.SortOption = .return1Week
    @State private var searchText = ""
    @State private var selectedFund: FundListItem? = nil
    
    // 2026-04-30 H-52 — sade. Cockpit/Sirkiye TerminalStockRow ile aynı
    // dil: kompakt control satırı + sade kategori scroll + grouped row
    // listesi (per-row hairline). Tinted holo pill ve daire ikon kalktı.
    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                controlSection
                categoryFilterSection

                if dataManager.isLoading && dataManager.fundPrices.isEmpty {
                    loadingView
                } else {
                    fundListSection
                }
            }
        }
        // 2026-04-30 H-53 — kendi toolbar refresh'i kaldırıldı. ArgusCockpitView'in
        // toolbar'ında zaten refresh button var, duplicate görünüyordu.
        // Search bar da kaldırıldı — Cockpit'te diğer tab'lerde de yok.
        // Aşağıdaki controlSection için filtreleme şimdilik kategori chip'i
        // ile yeterli; arama ihtiyacı belirirse Cockpit ortak top bar'ına
        // eklenecek.
        .task {
            if dataManager.fundPrices.isEmpty {
                await dataManager.loadAllFunds()
            }
        }
        .sheet(item: $selectedFund) { fund in
            // FundDetailView kaldırıldı (Lab'ların bir parçasıydı).
            // Yerine minimal bir detay sheet'i — kod + ad gösterir.
            VStack(alignment: .leading, spacing: 12) {
                Text(fund.name).font(.title3).bold()
                Text(fund.code).font(.caption).foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Control section (2026-04-30 H-52)
    //
    // Eski: yatay scroll'da 5+ tinted holo pill (selected) — Cockpit'le
    // tutarsız. Yeni: TerminalControlBar dili — sol "X fon" muted +
    // sağda "Sırala · 1 hafta ▾" sade Menu.
    private var controlSection: some View {
        HStack(spacing: 10) {
            Text("\(filteredFunds.count) fon")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .monospacedDigit()

            Spacer(minLength: 6)

            Menu {
                Picker("Sıralama", selection: $sortOption) {
                    ForEach(FundDataManager.SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortOption.rawValue)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(DesignTokens.Fonts.custom(size: 9))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Sıralama menüsü")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.background)
    }
    
    // MARK: - Category Filter Section (2026-04-30 H-52)
    //
    // Tinted holo pill (opacity 0.2 selected) → sade chip; selected =
    // textPrimary text + 1px borderSubtle stroke; passive = textSecondary
    // + transparent. İkonlar duruyor — küçük şekilde tanımayı kolaylaştırır.
    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: "Tümü",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(FundCategory.allCases) { category in
                    CategoryChip(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Fund List Section (2026-04-30 H-52)
    //
    // SwiftUI List + listRowBackground + listRowSeparator → ScrollView +
    // LazyVStack + manuel hairline. Cockpit/Sirkiye TerminalStockRow ile
    // aynı dil — grouped tek surface, alt 0.5px hairline.
    private var fundListSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredFunds) { fund in
                    Button(action: { selectedFund = fund }) {
                        FundRowView(
                            fund: fund,
                            priceData: dataManager.fundPrices[fund.code]
                        )
                    }
                    .buttonStyle(.plain)
                }
                if filteredFunds.isEmpty {
                    Text("Kriterlere uygun fon bulunamadı")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.top, 32)
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await dataManager.refresh()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: InstitutionalTheme.Colors.holo))
                .scaleEffect(1.5)
            
            Text("Fonlar yükleniyor...")
                .font(.subheadline)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Filtered Funds
    private var filteredFunds: [FundListItem] {
        var funds = dataManager.sortedFunds(by: sortOption, category: selectedCategory)
        
        if !searchText.isEmpty {
            funds = funds.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.code.localizedCaseInsensitiveContains(searchText) ||
                $0.shortName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return funds
    }
}

// MARK: - Category Chip Component

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    // 2026-04-30 H-52 — sade. Tinted holo background + holo border
    // (selected) → outline border tek dilde: textPrimary + borderSubtle
    // stroke. Passive: textSecondary + transparent.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Fonts.custom(size: 11))
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 12, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundColor(isSelected
                             ? DesignTokens.Colors.textPrimary
                             : DesignTokens.Colors.textSecondary)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected
                        ? DesignTokens.Colors.borderSubtle
                        : Color.clear,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fund Row View

struct FundRowView: View {
    let fund: FundListItem
    let priceData: FundPriceData?

    // 2026-04-30 H-53 — A versiyonu (iki satır kart):
    // Üst satır: kod + kategori muted + getiri renkli (sağ)
    // Alt satır: tam ad + kuruluş muted + NAV ₺X.XX (sağ)
    // Bilgi yoğun, hızlı tarama mantığı; per-row grouped + alt hairline.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Üst satır
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fund.code)
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(fund.category.rawValue)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer(minLength: 6)
                if let priceData, let return1W = priceData.return1Week {
                    Text(String(format: "%+.1f%%", return1W))
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(return1W >= 0
                                         ? InstitutionalTheme.Colors.aurora
                                         : InstitutionalTheme.Colors.crimson)
                        .monospacedDigit()
                } else {
                    ProgressView().scaleEffect(0.55)
                }
            }

            // Alt satır
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fund.shortName)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                Text("·")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(fund.founder.rawValue)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let priceData {
                    Text(String(format: "₺%.2f", priceData.currentPrice))
                        .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5),
            alignment: .bottom
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    FundListView()
}
