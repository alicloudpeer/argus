import SwiftUI

/// TAHTA: Birleşik Teknik Analiz Görünümü
/// OrionBist (SAR, TSI) + MoneyFlow (Hacim, A/D) + RelativeStrength (RS, Beta, Momentum)

struct TahtaView: View {
    let symbol: String

    @State private var result: TahtaResult?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEducation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let r = result {
                    // Ana Sinyal Kartı
                    mainSignalCard(r)

                    // Hızlı Göstergeler Grid
                    quickIndicatorsGrid(r)

                    // Endekse Göre Performans
                    if r.rsResult != nil {
                        relativePerformanceCard(r)
                    }

                    // Detaylı Metrikler (Expandable)
                    detailedMetricsSection(r)
                }
            }
            .padding()
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .onAppear { loadData() }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignTokens.Colors.primary)

            Text("Teknik analiz yapılıyor...")
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(InstitutionalTheme.Colors.warning)

            Text(message)
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Tekrar Dene") {
                loadData()
            }
            .foregroundColor(DesignTokens.Colors.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .institutionalCard(scale: .insight, elevated: false)
    }

    // MARK: - Ana Sinyal Kartı

    private func mainSignalCard(_ r: TahtaResult) -> some View {
        VStack(spacing: 16) {
            // 2026-05-04 H-62 sade. MotorLogo + caps "TAHTA"/"TEKNİK ANALİZ"
            // + ArgusPill kalktı; sade başlık + sentence verdict.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teknik analiz")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(symbol.uppercased())
                        .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }
                Spacer()
                Text(r.signal.rawValue)
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(signalColor(r.signal))
            }
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)

            // Orta: Ana Sinyal
            HStack(spacing: 20) {
                // Sinyal Badge (Büyük)
                VStack(spacing: 8) {
                    Image(systemName: r.signal.icon)
                        .font(DesignTokens.Fonts.custom(size: 36))
                        .foregroundColor(signalColor(r.signal))

                    Text(r.signal.rawValue)
                        .font(.title2)
                        .bold()
                        .foregroundColor(signalColor(r.signal))
                }
                .frame(width: 100)

                // Skor ve Destek
                VStack(alignment: .leading, spacing: 12) {
                    // Güven Skoru
                    HStack {
                        Text("Güven:")
                            .font(.caption)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text("%\(Int(r.confidence))")
                            .font(.title3)
                            .bold()
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }

                    // Destek Sayısı
                    HStack {
                        Text("Destek:")
                            .font(.caption)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(r.supportRatio)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(supportCountColor(r.supportCount, total: r.totalIndicators))
                        Text("gösterge")
                            .font(.caption)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }

                    // Skor Gauge
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(signalColor(r.signal))
                                .frame(width: geo.size.width * (r.totalScore / 100), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Alt: Özet
            Text(r.summary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(signalColor(r.signal).opacity(0.1))
                .cornerRadius(8)
        }
        .padding(16)
        .background(Color(hex: "0A0A0F"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(signalColor(r.signal).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Hızlı Göstergeler Grid

    private func quickIndicatorsGrid(_ r: TahtaResult) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            // SAR
            QuickIndicatorCell(
                icon: "arrow.triangle.swap",
                title: "SAR",
                value: r.orionResult.sarStatus.replacingOccurrences(of: "SAR ", with: ""),
                color: r.orionResult.sarStatus.contains("AL") ? .green : .red
            )

            // TSI
            QuickIndicatorCell(
                icon: "gauge.with.dots.needle.50percent",
                title: "TSI",
                value: String(format: "%+.0f", r.orionResult.tsiValue),
                color: r.orionResult.tsiValue > 0 ? .green : .red
            )

            // RSI
            QuickIndicatorCell(
                icon: "speedometer",
                title: "RSI",
                value: String(format: "%.0f", r.rsi),
                color: rsiColor(r.rsi)
            )

            // Para Akışı
            if let mf = r.moneyFlowResult {
                QuickIndicatorCell(
                    icon: mf.flowStatus.icon,
                    title: "AKIM",
                    value: flowStatusShort(mf.flowStatus),
                    color: flowColor(mf.flowStatus)
                )
            } else {
                QuickIndicatorCell(
                    icon: "arrow.left.arrow.right",
                    title: "AKIM",
                    value: "N/A",
                    color: .gray
                )
            }
        }
    }

    // MARK: - Rölatif Performans Kartı

    private func relativePerformanceCard(_ r: TahtaResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 2026-05-04 H-62 sade. MotorLogo + caps + ArgusPill kalktı.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rölatif güç")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text("Endekse göre · XU100")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                if let rs = r.rsResult {
                    Text(rs.statusText)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(rsStatusTone(rs.status).foreground)
                }
            }

            if let rs = r.rsResult {
                HStack(spacing: 16) {
                    // RS
                    VStack(spacing: 4) {
                        Text("RS")
                            .font(.caption2)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(String(format: "%.2f", rs.relativeStrength))
                            .font(.headline)
                            .bold()
                            .foregroundColor(rs.relativeStrength > 1.0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DesignTokens.Colors.Overlay.l05)
                    .cornerRadius(8)

                    // Beta
                    VStack(spacing: 4) {
                        Text("Beta")
                            .font(.caption2)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(String(format: "%.2f", rs.beta))
                            .font(.headline)
                            .bold()
                            .foregroundColor(rs.beta < 1.0 ? .blue : .orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DesignTokens.Colors.Overlay.l05)
                    .cornerRadius(8)

                    // Momentum
                    VStack(spacing: 4) {
                        Text("Mom.")
                            .font(.caption2)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(String(format: "%+.1f%%", rs.momentum))
                            .font(.headline)
                            .bold()
                            .foregroundColor(rs.momentum > 0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DesignTokens.Colors.Overlay.l05)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "0A0A0F"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Detaylı Metrikler

    private func detailedMetricsSection(_ r: TahtaResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation(.spring()) { showEducation.toggle() } }) {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.cyan)
                    Text("Formüller & Eğitim")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(DesignTokens.Colors.textPrimary)

                    Spacer()

                    Image(systemName: showEducation ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if showEducation {
                VStack(spacing: 0) {
                    ForEach(r.metrics) { metric in
                        TahtaMetricRow(metric: metric)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(hex: "0A0A0F"))
        .cornerRadius(16)
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await TahtaEngine.shared.analyze(symbol: symbol)
                await MainActor.run {
                    self.result = data
                    self.isLoading = false
                }
            } catch TahtaEngine.TahtaError.insufficientData {
                await MainActor.run {
                    self.errorMessage = "Yetersiz veri. En az 30 günlük tarihsel veri gerekli."
                    self.isLoading = false
                }
            } catch TahtaEngine.TahtaError.dataUnavailable {
                await MainActor.run {
                    self.errorMessage = "Veri kaynağına ulaşılamıyor."
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Analiz hatası: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func signalColor(_ signal: TahtaSignal) -> Color {
        switch signal {
        case .gucluAl: return DesignTokens.Colors.success
        case .al: return DesignTokens.Colors.success.opacity(0.8)
        case .tut: return InstitutionalTheme.Colors.warning
        case .sat: return InstitutionalTheme.Colors.warning
        case .gucluSat: return DesignTokens.Colors.error
        }
    }

    private func supportCountColor(_ count: Int, total: Int) -> Color {
        let ratio = Double(count) / Double(max(1, total))
        if ratio >= 0.7 { return .green }
        if ratio >= 0.4 { return .yellow }
        return .red
    }

    private func rsiColor(_ rsi: Double) -> Color {
        if rsi > 70 { return .red }
        if rsi < 30 { return .green }
        return .yellow
    }

    private func flowStatusShort(_ status: FlowStatus) -> String {
        switch status {
        case .strongInflow: return "G++"
        case .inflow: return "GİR"
        case .neutral: return "NÖTR"
        case .outflow: return "ÇIK"
        case .strongOutflow: return "Ç--"
        }
    }

    private func flowColor(_ status: FlowStatus) -> Color {
        switch status {
        case .strongInflow: return DesignTokens.Colors.success
        case .inflow: return DesignTokens.Colors.success.opacity(0.8)
        case .neutral: return InstitutionalTheme.Colors.warning
        case .outflow: return InstitutionalTheme.Colors.warning
        case .strongOutflow: return DesignTokens.Colors.error
        }
    }

    private func rsStatusColor(_ status: RSStatus) -> Color {
        switch status {
        case .outperforming: return .green
        case .stable: return .blue
        case .neutral: return .yellow
        case .underperforming: return .red
        }
    }

    // MARK: - V5 Tone Helpers

    private func signalTone(_ signal: TahtaSignal) -> ArgusChipTone {
        switch signal {
        case .gucluAl, .al:    return .aurora
        case .tut:             return .neutral
        case .sat, .gucluSat:  return .crimson
        }
    }

    private func rsStatusTone(_ status: RSStatus) -> ArgusChipTone {
        switch status {
        case .outperforming:   return .aurora
        case .stable:          return .motor(.orion)
        case .neutral:         return .neutral
        case .underperforming: return .crimson
        }
    }
}

// MARK: - Quick Indicator Cell

struct QuickIndicatorCell: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text(title)
                .font(DesignTokens.Fonts.custom(size: 9))
                .foregroundColor(DesignTokens.Colors.textTertiary)

            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Tahta Metric Row

struct TahtaMetricRow: View {
    let metric: TahtaMetric
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.snappy) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: metric.icon)
                        .font(.caption)
                        .foregroundColor(metricColor)
                        .frame(width: 20)

                    Text(metric.name)
                        .font(.subheadline)
                        .foregroundColor(DesignTokens.Colors.textPrimary)

                    Spacer()

                    Text(metric.value)
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(metricColor)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.cyan.opacity(0.8))
                        .offset(y: 2)

                    Text(metric.education)
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(DesignTokens.Colors.Overlay.l10)
        }
    }

    private var metricColor: Color {
        switch metric.color {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        case "orange": return .orange
        case "blue": return .blue
        case "mint": return Color(red: 0.4, green: 0.9, blue: 0.7)
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    TahtaView(symbol: "THYAO")
}
