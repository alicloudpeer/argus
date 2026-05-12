import SwiftUI

// MARK: - SanctumHeader
//
// Argus Sanctum ekranının başlık bloğu: sembol + fiyat + yüzdelik değişim.
// Önceden ArgusSanctumView içinde computed property olarak yaşıyordu.
// Split edildi → bağımsız bir bileşen olarak Views/Sanctum/ altına alındı.
//
// Kullanım:
//     SanctumHeader(symbol: symbol, quote: vm.quote)
//
// Veri kaynağı: SanctumViewModel.quote (Quote)
// Demo veri yok — quote nil ise yalnızca sembol gösterilir.

struct SanctumHeader: View {
    let symbol: String
    let quote: Quote?

    // 2026-04-25 H-36: Büyük sembol Sanctum top nav'a taşındı; bu header
    // artık sadece fiyat ve yüzde değişim taşıyor. Sola hizalı, top nav'ın
    // hemen altında yaşar — duplikasyon yok.
    var body: some View {
        if let quote {
            let change = quote.percentChange ?? 0
            let priceColor: Color = change >= 0
                ? SanctumTheme.auroraGreen
                : SanctumTheme.crimsonRed
            let isBist = symbol.uppercased().hasSuffix(".IS")
            let currency = isBist ? "₺" : "$"

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "\(currency)%.2f", quote.currentPrice))
                    .font(DesignTokens.Fonts.custom(size: 32, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text(String(format: "%@%.2f", change >= 0 ? "+" : "", quote.change))
                        .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(priceColor)
                    Text(String(format: "%@%.2f%%", change >= 0 ? "+" : "", change))
                        .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(priceColor)
                    Spacer()
                    Text("Son · \(formattedTime)")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(
                "Fiyat \(String(format: "%.2f", quote.currentPrice)), " +
                "değişim \(String(format: "%+.2f", change)) yüzde"
            ))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("—")
                    .font(DesignTokens.Fonts.custom(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var formattedTime: String {
        Date().formatted(.dateTime.hour().minute())
    }
}
