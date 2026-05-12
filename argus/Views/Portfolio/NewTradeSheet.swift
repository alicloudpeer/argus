import SwiftUI

// MARK: - NewTradeSheet (2026-05-11 sade yeniden yazım)
//
// Eski: PortfolioView.swift içine gömülü, +/- circle button'lı adet, kart-vari
// 3 panel, monospace heavy, presentationMode deprecated.
// Yeni: Bağımsız dosya, SanctumTradeSheet pattern'iyle uyumlu — sembol search +
// adet input + hızlı miktar chip'leri + özet + submit.
//
// Davranış aynen korunuyor: ExecutionStateViewModel.shared.buy(symbol:quantity:)
// Sadece alış (Portfolio FAB'tan yeni pozisyon başlatma). Satış mevcut pozisyon
// kartından yapılır.

struct NewTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var market = MarketViewModel.shared
    @ObservedObject private var execution = ExecutionStateViewModel.shared
    @ObservedObject private var portfolio = PortfolioStore.shared

    @State private var searchText: String = ""
    @State private var selectedSymbol: String?
    @State private var quantityString = ""
    @State private var tradeSuccess = false
    @State private var showError = false

    // MARK: - Computed

    private var quantity: Double {
        Double(quantityString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var symbol: String {
        selectedSymbol ?? ""
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

    private var estimatedTotal: Double {
        quantity * currentPrice * 1.002
    }

    private var companyName: String? {
        market.quotes[symbol]?.shortName
    }

    private var validationError: String? {
        guard quantity > 0 else { return nil }
        if currentPrice <= 0 { return "Fiyat verisi bekleniyor" }
        if estimatedTotal > availableBalance { return "Yetersiz bakiye" }
        return nil
    }

    private var canSubmit: Bool {
        selectedSymbol != nil && quantity > 0 && validationError == nil && !tradeSuccess
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        symbolSection

                        if selectedSymbol != nil {
                            currentPriceRow
                            quantitySection
                            quickQuantityRow
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
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                }
            }
        }
        .presentationDetents([.large])
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
                Text("Yeni alış")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("Sembol seç ve adet gir")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
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
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    // MARK: - Symbol section (search or selected pill)

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            Text("Sembol")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            if let sym = selectedSymbol {
                selectedSymbolPill(sym)
            } else {
                searchInput
                if !market.searchResults.isEmpty {
                    searchResultsList
                }
            }
        }
    }

    private var searchInput: some View {
        HStack(spacing: DesignTokens.Spacing.s10) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            TextField("Örn: AAPL, THYAO.IS", text: $searchText)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .onChange(of: searchText) { _, newValue in
                    handleSearch(newValue)
                }
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

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(market.searchResults.prefix(6), id: \.symbol) { result in
                Button(action: { selectSymbol(result.symbol) }) {
                    HStack(spacing: DesignTokens.Spacing.s10) {
                        Text(result.symbol)
                            .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .frame(width: 80, alignment: .leading)
                        Text(result.description)
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.s11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if result.symbol != market.searchResults.prefix(6).last?.symbol {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: DesignTokens.BorderWidth.hairline)
                    }
                }
            }
        }
        .background(DesignTokens.Colors.Overlay.l03)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
        )
        .cornerRadius(DesignTokens.Radius.r10)
    }

    private func selectedSymbolPill(_ sym: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.s10) {
            Text(sym)
                .font(DesignTokens.Fonts.custom(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            if let name = companyName {
                Text(name)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: clearSymbol) {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sembol temizle")
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
                Text("Veri bekleniyor")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
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
            quickChip(title: "%25", fraction: 0.25)
            quickChip(title: "%50", fraction: 0.50)
            quickChip(title: "%75", fraction: 0.75)
            quickChip(title: "Maks", fraction: 1.0)
        }
    }

    private func quickChip(title: String, fraction: Double) -> some View {
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
        .disabled(currentPrice <= 0)
    }

    private func applyFraction(_ fraction: Double) {
        guard currentPrice > 0 else { return }
        let budget = availableBalance * fraction
        let q = budget / (currentPrice * 1.002)
        guard q.isFinite, q > 0 else { return }
        let rounded = isBist ? floor(q) : (q * 10000).rounded() / 10000
        quantityString = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : formatDecimal(rounded)
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
                Text("Sonra kalan")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text("\(balanceSymbol) \(formatDecimal(max(0, availableBalance - estimatedTotal)))")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.Overlay.l03)
        .cornerRadius(DesignTokens.Radius.r10)
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
            Text("Alış emri ver")
                .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                .foregroundColor(DesignTokens.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s13)
                .background(canSubmit
                            ? DesignTokens.Colors.success
                            : DesignTokens.Colors.Overlay.l05)
                .cornerRadius(DesignTokens.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel("Alış emri ver")
    }

    // MARK: - Actions

    private func handleSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            market.searchResults = []
            return
        }
        market.search(query: trimmed) { results in
            MarketViewModel.shared.searchResults = results
        }
    }

    private func selectSymbol(_ sym: String) {
        let upper = sym.uppercased()
        selectedSymbol = upper
        searchText = ""
        market.searchResults = []
        // Mevcut fiyat henüz yoksa quote tetikle
        if market.quotes[upper]?.currentPrice ?? 0 <= 0 {
            Task { await market.fetchQuote(for: upper) }
        }
    }

    private func clearSymbol() {
        selectedSymbol = nil
        quantityString = ""
        tradeSuccess = false
        showError = false
        execution.lastTradeError = nil
    }

    private func executeTrade() {
        guard canSubmit, let sym = selectedSymbol else { return }
        showError = false
        tradeSuccess = false
        execution.lastTradeError = nil

        _ = execution.buy(symbol: sym, quantity: quantity)

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
}
