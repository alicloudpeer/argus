import SwiftUI

// MARK: - SanctumTradeSheet (2026-05-11 sade yeniden yazım)
//
// Eski: Form + Section + ASCII Türkçe + deprecated navigationBarItems +
// CAPS button. iOS 13 Settings dili.
// Yeni: Markets/Portfolio "yağ gibi" dili — VStack, sentence case, modern API,
// hızlı miktar chip'leri (%25/50/75/Maks), inline hata, action rengi submit.
//
// Davranış aynen korunuyor:
// - ExecutionStateViewModel.shared.buy(symbol:quantity:) / .sell(symbol:quantity:)
// - 0.3s sonra lastTradeError check → success/error dismiss
// - bistBalance / globalBalance ayrımı

struct SanctumTradeSheet: View {
    let symbol: String
    let action: ArgusSanctumView.TradeAction

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var execution = ExecutionStateViewModel.shared
    @ObservedObject private var market = MarketViewModel.shared
    @ObservedObject private var portfolio = PortfolioStore.shared

    @State private var quantityString = ""
    @State private var priceString = ""
    @State private var tradeSuccess = false
    @State private var showError = false

    // MARK: - Computed

    private var quantity: Double {
        Double(quantityString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var price: Double {
        let parsed = Double(priceString.replacingOccurrences(of: ",", with: "."))
        if let parsed, parsed > 0 { return parsed }
        return currentPrice
    }

    private var isBist: Bool {
        symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
    }

    private var balanceSymbol: String { isBist ? "₺" : "$" }

    private var currentPrice: Double {
        market.quotes[symbol]?.currentPrice ?? 0
    }

    private var availableBalance: Double {
        isBist ? portfolio.bistBalance : portfolio.globalBalance
    }

    private var openPositionQuantity: Double {
        portfolio.openTrades
            .filter { $0.symbol == symbol }
            .reduce(0.0) { $0 + $1.quantity }
    }

    /// Tahmini maliyet (alış için işlem ücreti dahil, satış için brüt).
    private var estimatedTotal: Double {
        switch action {
        case .buy:  return quantity * price * 1.002
        case .sell: return quantity * price
        }
    }

    private var actionColor: Color {
        switch action {
        case .buy:  return DesignTokens.Colors.success
        case .sell: return DesignTokens.Colors.error
        }
    }

    private var actionLabel: String {
        action == .buy ? "Alış" : "Satış"
    }

    private var submitLabel: String {
        action == .buy ? "Alış emri ver" : "Satış emri ver"
    }

    private var companySubtitle: String? {
        guard let name = market.quotes[symbol]?.shortName, !name.isEmpty else { return nil }
        let venue = isBist ? "BIST" : "NASDAQ"
        return "\(name) · \(venue)"
    }

    // Validation
    private var validationError: String? {
        guard quantity > 0 else { return nil } // Henüz yazılmamış, hata gösterme
        if action == .buy {
            if estimatedTotal > availableBalance {
                return "Yetersiz bakiye"
            }
        } else {
            if quantity > openPositionQuantity {
                let display = String(format: openPositionQuantity.truncatingRemainder(dividingBy: 1) == 0
                                     ? "%.0f" : "%.2f", openPositionQuantity)
                return openPositionQuantity == 0
                    ? "Bu sembolde açık pozisyon yok"
                    : "Pozisyondan fazla satılamaz · en fazla \(display) adet"
            }
        }
        return nil
    }

    private var canSubmit: Bool {
        quantity > 0 && validationError == nil && !tradeSuccess
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { hideKeyboard() }
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.primary)
            }
        }
        .onAppear {
            if currentPrice > 0 {
                priceString = formatDecimal(currentPrice)
            }
            execution.lastTradeError = nil
        }
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s10) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                    Text(symbol)
                        .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(actionLabel)
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(actionColor)
                }
                if let subtitle = companySubtitle {
                    Text(subtitle)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(DesignTokens.Colors.Overlay.l05)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.s10)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: DesignTokens.Spacing.md) {

            currentPriceRow
            quantitySection
            quickQuantityRow
            priceSection
            summaryCard

            if let err = validationError {
                inlineError(err)
            } else if let lastError = execution.lastTradeError, showError {
                inlineError(lastError)
            } else if tradeSuccess {
                inlineSuccess("İşlem başarılı")
            }

            submitButton
                .padding(.top, DesignTokens.Spacing.xs)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    // MARK: - Current price row

    private var currentPriceRow: some View {
        HStack {
            Text("Mevcut fiyat")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
            if currentPrice > 0 {
                Text("\(balanceSymbol) \(formatDecimal(currentPrice))")
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
            } else {
                Text("Veri yok")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.error)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: DesignTokens.BorderWidth.hairline)
        }
    }

    // MARK: - Quantity

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            Text("Adet")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            HStack {
                TextField("0", text: $quantityString)
                    .keyboardType(.decimalPad)
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(DesignTokens.Colors.Overlay.l03)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                    .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
            )
            .cornerRadius(DesignTokens.Radius.r10)
        }
    }

    // MARK: - Quick quantity (%25/50/75/Maks)

    private var quickQuantityRow: some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            quickQuantityChip(title: "%25", fraction: 0.25)
            quickQuantityChip(title: "%50", fraction: 0.50)
            quickQuantityChip(title: "%75", fraction: 0.75)
            quickQuantityChip(title: "Maks", fraction: 1.0)
        }
    }

    private func quickQuantityChip(title: String, fraction: Double) -> some View {
        Button(action: { applyFraction(fraction) }) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyFraction(_ fraction: Double) {
        guard price > 0 else { return }
        let q: Double
        switch action {
        case .buy:
            // Komisyon dahil maliyet ≈ qty * price * 1.002 → qty = budget / (price*1.002)
            let budget = availableBalance * fraction
            q = budget / (price * 1.002)
        case .sell:
            q = openPositionQuantity * fraction
        }
        guard q.isFinite, q > 0 else { return }
        // BIST tam adet, global 4 ondalık (kesir hisse desteği)
        let rounded = isBist ? floor(q) : (q * 10000).rounded() / 10000
        quantityString = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : formatDecimal(rounded)
    }

    // MARK: - Price (optional)

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            HStack {
                Text("Fiyat")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("opsiyonel · boşsa piyasa")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            HStack {
                TextField(formatDecimal(currentPrice), text: $priceString)
                    .keyboardType(.decimalPad)
                    .font(DesignTokens.Fonts.custom(size: 15, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.s11)
            .background(DesignTokens.Colors.Overlay.l03)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                    .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
            )
            .cornerRadius(DesignTokens.Radius.r10)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: DesignTokens.Spacing.s6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Toplam tahmin")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("\(balanceSymbol) \(formatDecimal(estimatedTotal))")
                    .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(secondaryLabel)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text(secondaryValue)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.Overlay.l03)
        .cornerRadius(DesignTokens.Radius.r10)
    }

    private var secondaryLabel: String {
        action == .buy ? "Sonra kalan" : "Pozisyondan satılacak"
    }

    private var secondaryValue: String {
        switch action {
        case .buy:
            let remaining = max(0, availableBalance - estimatedTotal)
            return "\(balanceSymbol) \(formatDecimal(remaining))"
        case .sell:
            let qty = quantity
            let total = openPositionQuantity
            return "\(formatQty(qty)) / \(formatQty(total)) adet"
        }
    }

    // MARK: - Inline error/success

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            Image(systemName: "exclamationmark.circle")
                .font(DesignTokens.Fonts.custom(size: 14))
            Text(message)
                .font(DesignTokens.Fonts.custom(size: 13))
                .lineLimit(2)
        }
        .foregroundColor(DesignTokens.Colors.error)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineSuccess(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            Image(systemName: "checkmark.circle")
                .font(DesignTokens.Fonts.custom(size: 14))
            Text(message)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
        }
        .foregroundColor(DesignTokens.Colors.success)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button(action: executeTrade) {
            Text(submitLabel)
                .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                .foregroundColor(DesignTokens.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s13)
                .background(canSubmit ? actionColor : DesignTokens.Colors.Overlay.l05)
                .cornerRadius(DesignTokens.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel("\(actionLabel) emri ver")
    }

    // MARK: - Actions

    private func executeTrade() {
        guard quantity > 0 else { return }
        showError = false
        tradeSuccess = false
        execution.lastTradeError = nil

        switch action {
        case .buy:
            _ = execution.buy(symbol: symbol, quantity: quantity)
        case .sell:
            execution.sell(symbol: symbol, quantity: quantity)
        }

        // Async result kontrolü — eski davranışı koruyoruz
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if execution.lastTradeError != nil {
                showError = true
            } else {
                tradeSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Formatting

    private func formatDecimal(_ v: Double) -> String {
        let abs = Swift.abs(v)
        if abs >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 2
            f.groupingSeparator = ","
            return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        }
        return String(format: "%.2f", v)
    }

    private func formatQty(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }
}
