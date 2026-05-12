import SwiftUI

// MARK: - Kulis KAP Haberleri Kartı
// Hisse bazlı KAP bildirimleri gösterir.
// Veri kaynağı: BorsaPyProvider.getNews()

struct KulisKAPCard: View {
    let symbol: String
    @State private var news: [BorsaPyProvider.BistNewsItem] = []
    @State private var isLoading = true
    @State private var showAll = false
    @State private var showEducation = false
    
    private var displayedNews: [BorsaPyProvider.BistNewsItem] {
        showAll ? news : Array(news.prefix(3))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KULİS")
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Text("KAP Bildirimleri")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Button(action: { withAnimation(.snappy) { showEducation.toggle() } }) {
                    Image(systemName: showEducation ? "info.circle.fill" : "info.circle")
                        .foregroundColor(SanctumTheme.hermesColor)
                }
            }
            .padding(16)
            
            if showEducation {
                kulisEducationNote
            }
            
            Divider().background(DesignTokens.Colors.borderSubtle)
            
            if isLoading {
                ProgressView()
                    .padding(32)
            } else if news.isEmpty {
                emptyState
            } else {
                newsListView
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: DesignTokens.Colors.background.opacity(0.35), radius: 8, x: 0, y: 4)
        .onAppear { loadData() }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.title3)
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text("Kayitli KAP bildirimi bulunamadi")
                .font(.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .padding(24)
    }
    
    // MARK: - News List
    
    private var newsListView: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedNews.enumerated()), id: \.element.id) { index, item in
                newsRow(item)
                
                if index < displayedNews.count - 1 {
                    Divider()
                        .background(DesignTokens.Colors.borderSubtle)
                        .padding(.horizontal, 16)
                }
            }
            
            // Daha fazla göster
            if news.count > 3 {
                Divider().background(DesignTokens.Colors.borderSubtle)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAll.toggle()
                    }
                }) {
                    HStack {
                        Text(showAll ? "Kapat" : "\(news.count - 3) haber daha")
                            .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(DesignTokens.Fonts.custom(size: 9))
                    }
                    .foregroundColor(SanctumTheme.hermesColor)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - News Row
    
    @ViewBuilder
    private func newsRow(_ item: BorsaPyProvider.BistNewsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tarih + Kaynak
            HStack {
                Text(item.date)
                    .font(DesignTokens.Fonts.custom(size: 9, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                
                Spacer()
                
                Text(item.source)
                    .font(DesignTokens.Fonts.custom(size: 8, weight: .bold))
                    .foregroundColor(SanctumTheme.hermesColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SanctumTheme.hermesColor.opacity(0.12))
                    .cornerRadius(4)
            }
            
            // Başlık
            Text(item.title)
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
            
            // Özet (varsa)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
    }
    
    // MARK: - Data
    
    private func loadData() {
        Task {
            await MainActor.run { isLoading = true }
            
            let clean = symbol.replacingOccurrences(of: ".IS", with: "")
            let fetched = (try? await BorsaPyProvider.shared.getNews(symbol: clean)) ?? []
            
            await MainActor.run {
                self.news = fetched
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Öğretici Not
    
    private var kulisEducationNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.caption)
                    .foregroundColor(SanctumTheme.hermesColor)
                Text("KAP Bildirimleri Neden Önemli?")
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
            }
            
            Group {
                kapBullet("KAP, şirketlerin yasal olarak kamuyu aydınlatma yükümlülüğüdür")
                kapBullet("Bilanço, temettü, sermaye artırımı gibi kritik gelişmeler buradan duyurulur")
                kapBullet("Zamanında takip, fiyat hareketlerinden önce bilgi sahibi olmayı sağlar")
            }
            
            Text("⚠️ KAP haberleri bilgilendirme amaçlıdır, yatırım tavsiyesi değildir.")
                .font(DesignTokens.Fonts.custom(size: 9))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(12)
        .background(SanctumTheme.hermesColor.opacity(0.08))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private func kapBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.caption).foregroundColor(SanctumTheme.hermesColor)
            Text(text)
                .font(DesignTokens.Fonts.custom(size: 10))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }
}
