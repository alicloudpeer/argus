import SwiftUI

// MARK: - PlanEditorSheet (2026-05-11 sade yeniden yazım)
//
// Eski: Form + Section + Slider + presentationMode (deprecated) + İngilizce
// karışık terminoloji ("take profit"/"stop loss").
// Yeni: Sade VStack, visual price track (stop · maliyet · anlık · hedef),
// text input + step button + chip ile düzenleme, validation, keyboard "Bitti".
//
// Davranış aynen korunuyor:
// - VortexEngine.shared.updatePlan(tradeId:newTarget:quantityPercent:reason:)
// - Init plan.bullishScenario.steps.first ve bearishScenario.steps.first'ten
//   targetPrice / stopPrice / sellPercent çıkarır.
// - Stop kaydı VortexEngine'in mevcut imzasında yok; eski davranış gibi
//   stop UI'da düzenlenir ama save'de yalnızca hedef + miktar gider.

struct PlanEditorSheet: View {
    let trade: Trade
    let currentPrice: Double
    let plan: PositionPlan

    @Environment(\.dismiss) private var dismiss

    @State private var targetText: String
    @State private var stopText: String
    @State private var sellPercent: Double

    // Drag override — kullanıcı sürüklerken canlı fiyat
    @State private var draggingStop: Double?
    @State private var draggingTarget: Double?

    init(trade: Trade, currentPrice: Double, plan: PositionPlan) {
        self.trade = trade
        self.currentPrice = currentPrice
        self.plan = plan

        // Hedef ve satış yüzdesi — bullishScenario.steps.first
        var initialTarget = trade.entryPrice * 1.05
        var initialPercent: Double = 100
        if let firstStep = plan.bullishScenario.steps.first {
            if case .priceAbove(let target) = firstStep.trigger {
                initialTarget = target
            }
            switch firstStep.action {
            case .sellPercent(let pct): initialPercent = pct
            case .sellAll: initialPercent = 100
            default: initialPercent = 50
            }
        }

        // Stop — bearishScenario.steps.first
        var initialStop = trade.entryPrice * 0.95
        if let firstStop = plan.bearishScenario.steps.first,
           case .priceBelow(let stop) = firstStop.trigger {
            initialStop = stop
        }

        _targetText = State(initialValue: Self.format(initialTarget))
        _stopText = State(initialValue: Self.format(initialStop))
        _sellPercent = State(initialValue: initialPercent)
    }

    // MARK: - Computed

    private var entryPrice: Double { trade.entryPrice }
    private var quantity: Double { trade.quantity }
    private var symbol: String { trade.symbol }

    private var isBist: Bool {
        symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol)
    }
    private var balanceSymbol: String { isBist ? "₺" : "$" }

    private var targetPrice: Double {
        if let drag = draggingTarget { return drag }
        return Double(targetText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var stopPrice: Double {
        if let drag = draggingStop { return drag }
        return Double(stopText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var targetGainPct: Double {
        guard entryPrice > 0 else { return 0 }
        return (targetPrice - entryPrice) / entryPrice * 100
    }
    private var stopLossPct: Double {
        guard entryPrice > 0 else { return 0 }
        return (stopPrice - entryPrice) / entryPrice * 100
    }
    private var targetGainAmount: Double {
        (targetPrice - entryPrice) * quantity * (sellPercent / 100)
    }
    private var stopLossAmount: Double {
        (entryPrice - stopPrice) * quantity
    }
    private var riskRewardRatio: Double? {
        let r = abs(stopLossPct)
        guard r > 0 else { return nil }
        return abs(targetGainPct) / r
    }

    private var sellQuantity: Double {
        quantity * (sellPercent / 100)
    }

    // Validation
    private var validationError: String? {
        if targetPrice <= entryPrice {
            return "Hedef fiyat maliyetten yüksek olmalı"
        }
        if stopPrice >= entryPrice {
            return "Zarar kes fiyatı maliyetten düşük olmalı"
        }
        if stopPrice <= 0 {
            return "Zarar kes fiyatı pozitif olmalı"
        }
        return nil
    }
    private var canSave: Bool { validationError == nil }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        priceTrackCard
                        targetSection
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: DesignTokens.BorderWidth.hairline)
                        stopSection

                        if let err = validationError {
                            inlineError(err)
                        }

                        submitButton
                            .padding(.top, DesignTokens.Spacing.xs)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.lg)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s10) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Plan düzenle")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                HStack(spacing: DesignTokens.Spacing.s6) {
                    Text(symbol)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text("·")
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Image(systemName: plan.intent.icon)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Text(plan.intent.rawValue)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
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
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    // MARK: - Price Track (visual)

    private var priceTrackCard: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            priceTrack
            trackLegend
            dragHint
            Divider()
                .background(DesignTokens.Colors.borderSubtle)
            riskRewardRow
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.Overlay.l03)
        .cornerRadius(DesignTokens.Radius.r10)
    }

    private var priceTrack: some View {
        GeometryReader { geo in
            let minP = trackMin
            let maxP = trackMax
            let range = max(maxP - minP, 0.0001)
            let w = geo.size.width

            let stopX  = CGFloat((stopPrice  - minP) / range) * w
            let entryX = CGFloat((entryPrice - minP) / range) * w
            let curX   = CGFloat((currentPrice - minP) / range) * w
            let tgtX   = CGFloat((targetPrice - minP) / range) * w

            ZStack(alignment: .leading) {
                // Track zemin
                Capsule()
                    .fill(DesignTokens.Colors.Overlay.l05)
                    .frame(height: 6)

                // Kayıp alanı (stop → entry)
                Capsule()
                    .fill(DesignTokens.Colors.error.opacity(0.30))
                    .frame(width: max(0, entryX - stopX), height: 6)
                    .offset(x: stopX)

                // Kâr alanı (entry → target)
                Capsule()
                    .fill(DesignTokens.Colors.success.opacity(0.30))
                    .frame(width: max(0, tgtX - entryX), height: 6)
                    .offset(x: entryX)

                // Maliyet — pasif küçük
                passiveDot(color: DesignTokens.Colors.textSecondary, size: 8)
                    .position(x: entryX, y: 16)

                // Anlık — pasif orta, vurgu
                currentDot(color: currentPrice >= entryPrice
                           ? DesignTokens.Colors.success
                           : DesignTokens.Colors.error)
                    .position(x: curX, y: 16)

                // Stop — DRAGGABLE büyük + handle
                draggableDot(color: DesignTokens.Colors.error)
                    .position(x: stopX, y: 16)
                    .gesture(stopDragGesture(width: w, minP: minP, range: range, entryX: entryX))

                // Hedef — DRAGGABLE büyük + handle
                draggableDot(color: DesignTokens.Colors.primary)
                    .position(x: tgtX, y: 16)
                    .gesture(targetDragGesture(width: w, minP: minP, range: range, entryX: entryX))
            }
            .frame(height: 32)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 32)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // Pasif dot (Maliyet)
    private func passiveDot(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(DesignTokens.Colors.background, lineWidth: 2)
            )
    }

    // Anlık dot — pasif ama vurgulu (halo)
    private func currentDot(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 22, height: 22)
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(DesignTokens.Colors.background, lineWidth: 2)
                )
        }
    }

    // Drag-edilebilir dot (Stop/Hedef): büyük, handle çizgili
    private func draggableDot(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(DesignTokens.Colors.background, lineWidth: 3)
                )
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: 1)
                        .frame(width: 26, height: 26)
                )
            // Handle çizgileri (sürükle hint'i)
            HStack(spacing: 1.5) {
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5, height: 8)
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5, height: 8)
            }
        }
        .contentShape(Rectangle().inset(by: -8))  // genişletilmiş tap area
    }

    // Drag handlers

    private func stopDragGesture(width w: CGFloat, minP: Double, range: Double, entryX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let x = min(max(0, gesture.location.x), entryX - 16)
                let price = minP + Double(x / w) * range
                draggingStop = price
            }
            .onEnded { _ in
                if let final = draggingStop {
                    stopText = Self.format(final)
                }
                draggingStop = nil
            }
    }

    private func targetDragGesture(width w: CGFloat, minP: Double, range: Double, entryX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let x = max(min(w, gesture.location.x), entryX + 16)
                let price = minP + Double(x / w) * range
                draggingTarget = price
            }
            .onEnded { _ in
                if let final = draggingTarget {
                    targetText = Self.format(final)
                }
                draggingTarget = nil
            }
    }

    // Track range — sıkı padding, dot'lar arası okunabilir mesafe
    private var trackMin: Double {
        let lowest = [stopPrice, currentPrice, entryPrice].filter { $0 > 0 }.min() ?? entryPrice
        return max(0.01, lowest * 0.97)
    }
    private var trackMax: Double {
        let highest = [targetPrice, currentPrice, entryPrice].max() ?? entryPrice
        return highest * 1.03
    }

    // MARK: - Legend (4-li compact row, çakışmasız)

    private var trackLegend: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            legendItem(color: DesignTokens.Colors.error,
                       title: "Stop",
                       value: Self.format(stopPrice))
            legendItem(color: DesignTokens.Colors.textSecondary,
                       title: "Maliyet",
                       value: Self.format(entryPrice))
            legendItem(color: currentPrice >= entryPrice
                       ? DesignTokens.Colors.success
                       : DesignTokens.Colors.error,
                       title: "Anlık",
                       value: Self.format(currentPrice),
                       valueColor: currentPrice >= entryPrice
                            ? DesignTokens.Colors.success
                            : DesignTokens.Colors.error)
            legendItem(color: DesignTokens.Colors.primary,
                       title: "Hedef",
                       value: Self.format(targetPrice))
        }
    }

    private func legendItem(color: Color, title: String, value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                    .foregroundColor(valueColor ?? DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dragHint: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "arrow.left.and.right")
                .font(DesignTokens.Fonts.custom(size: 10))
            Text("Stop ve hedef noktalarını sürükleyebilirsin")
                .font(DesignTokens.Fonts.custom(size: 11))
        }
        .foregroundColor(DesignTokens.Colors.textTertiary)
        .frame(maxWidth: .infinity)
    }

    private var riskRewardRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String(format: "%%%.1f risk", abs(stopLossPct)))
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.error)
                Text("\(balanceSymbol) \(Self.format(stopLossAmount))")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            if let rr = riskRewardRatio {
                Text("R / R · \(String(format: "%.2f", rr))")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xxs) {
                Text(String(format: "+%%%.1f hedef", targetGainPct))
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.success)
                Text("\(balanceSymbol) \(Self.format(targetGainAmount))")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
    }

    // MARK: - Target section

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            Text("Hedef fiyat")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            priceInputRow(text: $targetText,
                          step: { sign in stepPrice(&targetText, by: sign * 0.5) })

            HStack(spacing: DesignTokens.Spacing.s6) {
                gainChip(title: "+%5",  pct: 5)
                gainChip(title: "+%10", pct: 10)
                gainChip(title: "+%20", pct: 20)
                gainChip(title: "+%50", pct: 50)
            }

            HStack {
                Text("Hedefte satılacak")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("\(Int(sellPercent))% · \(Self.formatQty(sellQuantity)) adet")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
            }
            .padding(.top, DesignTokens.Spacing.xs)

            HStack(spacing: DesignTokens.Spacing.s6) {
                sellChip(title: "%25",  pct: 25)
                sellChip(title: "%50",  pct: 50)
                sellChip(title: "%75",  pct: 75)
                sellChip(title: "%100", pct: 100)
            }
        }
    }

    private func gainChip(title: String, pct: Double) -> some View {
        Button(action: { applyTargetGain(pct: pct) }) {
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

    private func sellChip(title: String, pct: Double) -> some View {
        let isSelected = Int(sellPercent) == Int(pct)
        return Button(action: { sellPercent = pct }) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 12,
                                                weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected
                                 ? DesignTokens.Colors.textPrimary
                                 : DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(isSelected ? DesignTokens.Colors.Overlay.l05 : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stop section

    private var stopSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            Text("Zarar kes fiyatı")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            priceInputRow(text: $stopText,
                          step: { sign in stepPrice(&stopText, by: sign * 0.5) })

            HStack(spacing: DesignTokens.Spacing.s6) {
                lossChip(title: "−%3",  pct: 3)
                lossChip(title: "−%5",  pct: 5)
                lossChip(title: "−%10", pct: 10)
                lossChip(title: "−%20", pct: 20)
            }
        }
    }

    private func lossChip(title: String, pct: Double) -> some View {
        Button(action: { applyStopLoss(pct: pct) }) {
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

    // MARK: - Price input row (input + +/- step)

    private func priceInputRow(text: Binding<String>, step: @escaping (Double) -> Void) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            HStack {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(DesignTokens.Fonts.custom(size: 17, weight: .medium, design: .monospaced))
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

            VStack(spacing: DesignTokens.Spacing.xxs) {
                Button(action: { step(1) }) {
                    Image(systemName: "plus")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .frame(width: 36, height: 24)
                        .background(DesignTokens.Colors.Overlay.l05)
                        .cornerRadius(DesignTokens.Radius.r6)
                }
                .buttonStyle(.plain)
                Button(action: { step(-1) }) {
                    Image(systemName: "minus")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .frame(width: 36, height: 24)
                        .background(DesignTokens.Colors.Overlay.l05)
                        .cornerRadius(DesignTokens.Radius.r6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Inline error

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

    // MARK: - Submit

    private var submitButton: some View {
        Button(action: savePlan) {
            Text("Planı kaydet")
                .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                .foregroundColor(DesignTokens.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s13)
                .background(canSave
                            ? DesignTokens.Colors.primary
                            : DesignTokens.Colors.Overlay.l05)
                .cornerRadius(DesignTokens.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: - Actions

    private func applyTargetGain(pct: Double) {
        let newTarget = entryPrice * (1 + pct / 100)
        targetText = Self.format(newTarget)
    }

    private func applyStopLoss(pct: Double) {
        let newStop = entryPrice * (1 - pct / 100)
        stopText = Self.format(newStop)
    }

    private func stepPrice(_ text: inout String, by delta: Double) {
        let current = Double(text.replacingOccurrences(of: ",", with: ".")) ?? entryPrice
        let next = max(0.01, current + delta)
        text = Self.format(next)
    }

    private func savePlan() {
        guard canSave else { return }
        // Mevcut VortexEngine imzası yalnızca target + quantityPercent kabul ediyor.
        // Stop UI'da güncellenmiş olabilir ama save edilemez (eski davranış).
        VortexEngine.shared.updatePlan(
            tradeId: trade.id,
            newTarget: targetPrice,
            quantityPercent: sellPercent,
            reason: "Kullanıcı tarafından manuel güncellendi"
        )
        dismiss()
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }

    // MARK: - Formatting

    private static func format(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private static func formatQty(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }
}
