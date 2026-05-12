import SwiftUI

// MARK: - BacktestValidationView

struct BacktestValidationView: View {
    @StateObject private var runner = BacktestValidationRunner.shared

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    if runner.isRunning {
                        progressSection
                    }
                    if !runner.results.isEmpty {
                        summarySection
                        resultsSection
                        actionDistributionSection
                    }
                    if !runner.isRunning && runner.results.isEmpty {
                        emptyStateSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Backtest Validasyon")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sprint A · V2 Motor Alpha Doğrulama")
                .font(InstitutionalTheme.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)

            Text("10 sembol · Son 6 ay · Walk-forward %70/%30")
                .font(InstitutionalTheme.Typography.dataSmall)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Button(action: { runner.run() }) {
                HStack(spacing: 8) {
                    Image(systemName: runner.isRunning ? "stop.circle" : "play.circle.fill")
                        .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                    Text(runner.isRunning ? "Çalışıyor…" : "Validasyonu Başlat")
                        .font(InstitutionalTheme.Typography.body)
                }
                .foregroundStyle(runner.isRunning ? DesignTokens.Colors.textSecondary : InstitutionalTheme.Colors.aurora)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(DesignTokens.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                        .stroke(runner.isRunning ? DesignTokens.Colors.border : InstitutionalTheme.Colors.aurora.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(runner.isRunning)
        }
        .padding(.top, 8)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(runner.currentSymbol.isEmpty ? "Başlatılıyor…" : runner.currentSymbol)
                    .font(InstitutionalTheme.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(Int(runner.progress * 100))%")
                    .font(InstitutionalTheme.Typography.dataSmall)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            ProgressView(value: runner.progress)
                .tint(InstitutionalTheme.Colors.aurora)
        }
        .padding(16)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Summary

    private var summarySection: some View {
        let valid = runner.results.filter { $0.error == nil }
        guard !valid.isEmpty else { return AnyView(EmptyView()) }
        let avgAlpha = valid.map(\.alpha).reduce(0, +) / Double(valid.count)
        let avgSharpe = valid.map(\.sharpeRatio).reduce(0, +) / Double(valid.count)
        let avgWin = valid.map(\.winRate).reduce(0, +) / Double(valid.count)
        let overfitCount = valid.filter(\.isOverfit).count
        let alphaPositive = avgAlpha >= 0

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                ArgusSectionCaption("ÖZET")
                    .padding(.horizontal, 0)
                HStack(spacing: 8) {
                    summaryChip(
                        label: "Ort. Alpha",
                        value: String(format: "%+.1f%%", avgAlpha),
                        color: alphaPositive ? DesignTokens.Colors.success : DesignTokens.Colors.error
                    )
                    summaryChip(
                        label: "Ort. Sharpe",
                        value: String(format: "%.2f", avgSharpe),
                        color: avgSharpe > 0.5 ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary
                    )
                    summaryChip(
                        label: "Win Rate",
                        value: String(format: "%.0f%%", avgWin),
                        color: avgWin >= 50 ? DesignTokens.Colors.success : DesignTokens.Colors.error
                    )
                    summaryChip(
                        label: "Overfitting",
                        value: "\(overfitCount)/\(valid.count)",
                        color: overfitCount > 0 ? InstitutionalTheme.Colors.warning : DesignTokens.Colors.success
                    )
                }
            }
            .padding(16)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
        )
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(InstitutionalTheme.Typography.body.bold())
                .foregroundStyle(color)
            Text(label)
                .font(InstitutionalTheme.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.sm, style: .continuous))
    }

    // MARK: - Results Table

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArgusSectionCaption("PER-SYMBOL SONUÇLAR")
                .padding(.horizontal, 0)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                resultHeaderRow
                Divider()
                    .background(DesignTokens.Colors.border)
                ForEach(runner.results) { r in
                    resultRow(r)
                    if r.id != runner.results.last?.id {
                        Divider()
                            .background(DesignTokens.Colors.border.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
        }
    }

    private var resultHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Sembol").frame(width: 80, alignment: .leading)
            Text("Return").frame(maxWidth: .infinity, alignment: .trailing)
            Text("B&H").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Alpha").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Win%").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Sharpe").frame(maxWidth: .infinity, alignment: .trailing)
            Text("WFD").frame(width: 52, alignment: .trailing)
        }
        .font(InstitutionalTheme.Typography.micro)
        .foregroundStyle(DesignTokens.Colors.textTertiary)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func resultRow(_ r: ValidationSymbolResult) -> some View {
        if let err = r.error {
            HStack(spacing: 0) {
                Text(r.symbol)
                    .frame(width: 80, alignment: .leading)
                    .font(InstitutionalTheme.Typography.dataSmall.bold())
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(err)
                    .font(InstitutionalTheme.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 0) {
                Text(r.symbol)
                    .frame(width: 80, alignment: .leading)
                    .font(InstitutionalTheme.Typography.dataSmall.bold())
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(format: "%+.1f%%", r.totalReturn))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(r.returnColor)
                Text(String(format: "%+.1f%%", r.benchmarkReturn))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(format: "%+.1f%%", r.alpha))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(r.alphaColor)
                Text(String(format: "%.0f%%", r.winRate))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(r.winRate >= 50 ? DesignTokens.Colors.success : DesignTokens.Colors.error)
                Text(String(format: "%.2f", r.sharpeRatio))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Group {
                    if let wfd = r.walkForwardDegradation {
                        Text(String(format: "%.0f", wfd))
                            .foregroundStyle(r.isOverfit ? InstitutionalTheme.Colors.warning : DesignTokens.Colors.success)
                    } else {
                        Text("—")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: 52, alignment: .trailing)
            }
            .font(InstitutionalTheme.Typography.dataSmall)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Action Distribution

    private var actionDistributionSection: some View {
        let valid = runner.results.filter { $0.error == nil }
        guard !valid.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                ArgusSectionCaption("AKSİYON DAĞILIMI")
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Sembol").frame(width: 80, alignment: .leading)
                        Text("BUY%").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("SELL%").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("HOLD%").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("İşlem").frame(width: 52, alignment: .trailing)
                    }
                    .font(InstitutionalTheme.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.bottom, 8)

                    Divider().background(DesignTokens.Colors.border)

                    ForEach(valid) { r in
                        HStack(spacing: 0) {
                            Text(r.symbol)
                                .frame(width: 80, alignment: .leading)
                                .font(InstitutionalTheme.Typography.dataSmall.bold())
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Text(String(format: "%.0f%%", r.buyRatio * 100))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(DesignTokens.Colors.success)
                            Text(String(format: "%.0f%%", r.sellRatio * 100))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(DesignTokens.Colors.error)
                            Text(String(format: "%.0f%%", r.holdRatio * 100))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            Text("\(r.totalTrades)")
                                .frame(width: 52, alignment: .trailing)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                        }
                        .font(InstitutionalTheme.Typography.dataSmall)
                        .padding(.vertical, 10)

                        if r.id != valid.last?.id {
                            Divider().background(DesignTokens.Colors.border.opacity(0.5))
                        }
                    }
                }
                .padding(16)
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            }
        )
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(DesignTokens.Fonts.custom(size: 32))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("10 sembol, son 6 ay, V2 motorlar")
                .font(InstitutionalTheme.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("BIST: THYAO · ASELS · GARAN · EREGL · TUPRS\nUS: AAPL · MSFT · NVDA · GOOGL · AMZN")
                .font(InstitutionalTheme.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
