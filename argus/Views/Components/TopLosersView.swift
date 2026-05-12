import SwiftUI

struct TopLosersView: View {
    @ObservedObject private var market = MarketViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("En Çok Düşenler (Günün Kaybedenleri)")
                .font(.headline)
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .padding(.horizontal)

            if !market.topLosers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(market.topLosers, id: \.symbol) { quote in
                            LoserCard(symbol: quote.symbol ?? "N/A", quote: quote)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                HStack {
                    Text("Veri yok veya yüklenemedi.")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Button(action: {
                        Task { await market.fetchTopLosers() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(InstitutionalTheme.Colors.holo)
                    }
                }
                .padding(.horizontal)
                .frame(height: 50)
            }
        }
        .padding(.vertical, 8)
    }
}

struct LoserCard: View {
    let symbol: String
    let quote: Quote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(symbol)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                
                Spacer()
                
                Text(String(format: "%.2f", quote.currentPrice))
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            
            HStack {
                Image(systemName: "arrow.down.right.circle.fill")
                    .foregroundColor(DesignTokens.Colors.error)
                    .font(.caption)
                
                Text(String(format: "%.2f%%", quote.percentChange))
                    .font(.caption)
                    .bold()
                    .foregroundColor(DesignTokens.Colors.error)
            }
        }
        .padding(12)
        .frame(width: 140, height: 70)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
