import SwiftUI

// MARK: - BistDividendCard (BIST temettü)
//
// 2026-05-05 H-67 — sade refactor.
//
// Eski V5: MotorLogo(.atlas) + "TEMETTÜ GEÇMİŞİ" caps section caption,
// "X KAYIT" caps chip, ArgusHair separator'lar, "SON TEMETTÜ" 9pt bold
// mono tracking 0.8 caps + "%X BRÜT" 11pt black mono caps, satır
// içinde tarih.uppercased() + "HİSSE BAŞI" 9pt mono caps tracking 0.4
// + "BRÜT" 8pt mono caps tracking 0.6, atlas motor tinted border 0.3.
// BistCapitalIncreaseCard'da da aynı dil + "SERMAYE ARTIRIMLARI" caps,
// "BEDELLİ / BEDELSİZ" caps mono.
//
// Yeni dil: sentence "Temettü geçmişi" başlık + "N kayıt" muted, satır
// içinde tarih + sentence "Hisse başı ₺X" + sade "Brüt %X" sağ kolon,
// hairline borderSubtle.

struct BistDividendCard: View {
    let symbol: String
    @State private var dividends: [BistDividend] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var isBist: Bool {
        symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
    }

    var body: some View {
        if isBist {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let error = errorMessage {
                    errorBlock(error)
                } else if dividends.isEmpty && !isLoading {
                    emptyBlock
                } else {
                    dividendList

                    if let lastDividend = dividends.first {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                        footerRow(last: lastDividend)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { loadDividends() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Temettü geçmişi")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            if isLoading {
                ProgressView().scaleEffect(0.6)
            } else {
                Text("\(dividends.count) kayıt")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private var dividendList: some View {
        VStack(spacing: 0) {
            ForEach(Array(dividends.prefix(5).enumerated()), id: \.offset) { idx, dividend in
                DividendRow(dividend: dividend)
                    .padding(.vertical, 8)
                if idx < min(dividends.count, 5) - 1 {
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private func footerRow(last: BistDividend) -> some View {
        HStack {
            Text("Son temettü")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Spacer()
            Text(String(format: "Brüt %%%.1f", last.grossRate))
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.aurora)
        }
        .padding(.top, 2)
    }

    private var emptyBlock: some View {
        Text("Bu hisse için temettü kaydı yok.")
            .font(DesignTokens.Fonts.custom(size: 13))
            .foregroundColor(DesignTokens.Colors.textSecondary)
    }

    private func errorBlock(_ error: String) -> some View {
        Text(error)
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(InstitutionalTheme.Colors.crimson)
    }

    private func loadDividends() {
        Task {
            do {
                let result = try await BorsaPyProvider.shared.getDividends(symbol: symbol)
                await MainActor.run {
                    self.dividends = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Veri yüklenemedi"
                    self.isLoading = false
                }
            }
        }
    }
}

struct DividendRow: View {
    let dividend: BistDividend

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(dividend.date))
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(String(format: "Hisse başı ₺%.2f", dividend.perShare))
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Text(String(format: "%%%.1f", dividend.grossRate))
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(InstitutionalTheme.Colors.aurora)
                .monospacedDigit()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: date)
    }
}

// MARK: - BistCapitalIncreaseCard (BIST sermaye artırımları)

struct BistCapitalIncreaseCard: View {
    let symbol: String
    @State private var capitalIncreases: [BistCapitalIncrease] = []
    @State private var isLoading = true

    var isBist: Bool {
        symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
    }

    var body: some View {
        if isBist && !capitalIncreases.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(capitalIncreases.prefix(3).enumerated()), id: \.offset) { idx, increase in
                        CapitalIncreaseRow(increase: increase)
                            .padding(.vertical, 8)
                        if idx < min(capitalIncreases.count, 3) - 1 {
                            Rectangle()
                                .fill(DesignTokens.Colors.borderSubtle)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { loadCapitalIncreases() }
        }
    }

    private var header: some View {
        HStack {
            Text("Sermaye artırımları")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            if isLoading {
                ProgressView().scaleEffect(0.6)
            } else {
                Text("\(capitalIncreases.count) kayıt")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private func loadCapitalIncreases() {
        Task {
            do {
                let result = try await BorsaPyProvider.shared.getCapitalIncreases(symbol: symbol)
                await MainActor.run {
                    self.capitalIncreases = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct CapitalIncreaseRow: View {
    let increase: BistCapitalIncrease

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(increase.date))
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                if increase.rightsIssueRate > 0 {
                    Text(String(format: "Bedelli %%%.0f", increase.rightsIssueRate))
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.holo)
                }
            }

            Spacer()

            if increase.totalBonusRate > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%%%.0f", increase.totalBonusRate))
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(InstitutionalTheme.Colors.aurora)
                        .monospacedDigit()
                    Text("Bedelsiz")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: date)
    }
}
