import SwiftUI

// MARK: - BIST modül kartları
// 2026-05-04 H-62 sade refactor:
//   • caps başlıklar ("TEMEL ANALİZ & FAKTÖRLER", "SEKTÖR ROTASYONU",
//     "PARA AKIŞI & HACİM", "NEDEN BU HAREKET VAR?", "DETAYLI ANALİZ
//     RAPORU", "VERİ YOK") → sentence case
//   • factor.name.uppercased() → sentence case
//   • mono .heavy/.black → medium
//   • BistSektorCard'daki raw Color.white/hex → InstitutionalTheme tokenları
//   • shadow kaldırıldı (sade dilde flat surface)

// ═══════════════════════════════════════════════════════════════════
// MARK: - SHARED: INSIGHT ROW
// ═══════════════════════════════════════════════════════════════════

struct MetricInsightRow: View {
    let metric: AnalysisMetric
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.snappy) { isExpanded.toggle() } }) {
                HStack {
                    // Label & Context
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Text(metric.context)
                            .font(.caption2)
                            .foregroundColor(impactColor)
                    }
                    
                    Spacer()
                    
                    // Value
                    Text(metric.value)
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(metric.scoreImpact > 0 ? DesignTokens.Colors.success : (metric.scoreImpact < 0 ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary))
                    
                    // Expand Icon
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle()) // Make full row tappable
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.primary.opacity(0.85))
                        .offset(y: 2)
                    
                    Text(metric.education)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(DesignTokens.Colors.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider().background(DesignTokens.Colors.borderSubtle)
        }
    }

    private var impactColor: Color {
        if metric.scoreImpact > 0 { return DesignTokens.Colors.success }
        if metric.scoreImpact < 0 { return DesignTokens.Colors.error }
        return DesignTokens.Colors.textSecondary
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - 1. BIST FAKTOR CARD (DATA & EDUCATION)
// ═══════════════════════════════════════════════════════════════════

struct BistFaktorCard: View {
    let symbol: String
    @State private var result: BistFaktorResult?
    @State private var isLoading = true
    @State private var showDetails = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Total Score
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temel analiz")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(symbol)
                        .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }

                Spacer()

                if let r = result {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(r.totalScore))")
                            .font(DesignTokens.Fonts.custom(size: 24, weight: .medium))
                            .foregroundColor(scoreColor(r.totalScore))
                            .monospacedDigit()
                        Text("/ 100")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    Text("Veri yok")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.titan)
                }
            }
            .padding(16)
            
            Divider().background(DesignTokens.Colors.borderSubtle)
            
            // Factor Summary Grid (Interactive)
            if let r = result {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(r.factors) { factor in
                        FactorSummaryCell(factor: factor)
                    }
                }
                .padding(16)
                
                // Detailed Metrics List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detaylı analiz")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.top, 8)

                    ForEach(r.factors) { factor in
                        if !factor.metrics.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(factor.name)
                                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                                    .foregroundColor(factorColor(factor.color))
                                    .padding(.bottom, 4)
                                
                                ForEach(factor.metrics) { metric in
                                    MetricInsightRow(metric: metric)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else if !isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Faktör analizi şu an yüklenemedi.")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loadData() }
    }

    private func loadData() {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }

            do {
                // 1. Oracle verilerini cache katmanından al
                let oracleSignals = await OracleEngine.shared.getLatestSignals()

                // 2. Faktör Analizi (Oracle Sinyalleri ile)
                let data = try await BistFaktorEngine.shared.analyze(symbol: symbol, oracleSignals: oracleSignals)
                await MainActor.run {
                    self.result = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.result = nil
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return DesignTokens.Colors.success }
        if score >= 50 { return InstitutionalTheme.Colors.warning }
        return DesignTokens.Colors.error
    }
    
    private func factorColor(_ name: String) -> Color {
        switch name {
        case "blue": return DesignTokens.Colors.primary
        case "green": return DesignTokens.Colors.success
        case "purple": return DesignTokens.Colors.primary
        case "yellow": return InstitutionalTheme.Colors.warning
        case "orange": return InstitutionalTheme.Colors.warning
        case "red": return DesignTokens.Colors.error
        case "mint": return DesignTokens.Colors.success
        default: return DesignTokens.Colors.textSecondary
        }
    }
}

struct FactorSummaryCell: View {
    let factor: BistFaktor
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: factor.icon)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(factorColor(factor.color))

            Text(factor.name.components(separatedBy: " ").first ?? "")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .lineLimit(1)

            Text("\(Int(factor.score))")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    func factorColor(_ name: String) -> Color {
        switch name {
        case "blue": return DesignTokens.Colors.primary
        case "green": return DesignTokens.Colors.success
        case "purple": return DesignTokens.Colors.primary
        case "yellow": return InstitutionalTheme.Colors.warning
        case "orange": return InstitutionalTheme.Colors.warning
        case "red": return DesignTokens.Colors.error
        case "mint": return DesignTokens.Colors.success
        default: return DesignTokens.Colors.textSecondary
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 2. BIST SEKTOR CARD (CONTEXTUAL ROTATION)
// ═══════════════════════════════════════════════════════════════════

struct BistSektorCard: View {
    @State private var result: BistSektorResult?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sektör rotasyonu")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    if let r = result {
                        Text(r.rotation.rawValue)
                            .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                            .foregroundColor(rotationColor(r.rotation))
                    } else {
                        Text("Yükleniyor")
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(16)

            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)

            if let r = result {
                // Top Sectors (Visual)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(r.sectors.prefix(5)) { sector in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Image(systemName: sector.icon)
                                        .font(DesignTokens.Fonts.custom(size: 11))
                                        .foregroundColor(DesignTokens.Colors.textSecondary)
                                    Text(sector.name)
                                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                        .lineLimit(1)
                                }

                                Text("\(sector.dailyChange >= 0 ? "+" : "")\(String(format: "%.1f", sector.dailyChange))%")
                                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                                    .foregroundColor(sector.dailyChange >= 0
                                                     ? InstitutionalTheme.Colors.aurora
                                                     : InstitutionalTheme.Colors.crimson)
                                    .monospacedDigit()
                            }
                            .padding(10)
                            .background(DesignTokens.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                // Educational Insights
                VStack(alignment: .leading, spacing: 0) {
                    Text("Neden bu hareket")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.vertical, 8)

                    ForEach(r.rotationMetrics) { metric in
                        MetricInsightRow(metric: metric)
                    }
                }
                .padding(16)
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loadData() }
    }

    private func loadData() {
        Task {
            if let data = try? await BistSektorEngine.shared.analyze() {
                await MainActor.run { self.result = data }
            }
        }
    }

    private func rotationColor(_ rotation: SektorRotasyon) -> Color {
        switch rotation {
        case .riskOn, .buyume:    return InstitutionalTheme.Colors.aurora
        case .teknoloji:          return InstitutionalTheme.Colors.holo
        case .defansif:           return InstitutionalTheme.Colors.titan
        case .riskOff, .belirsiz: return InstitutionalTheme.Colors.crimson
        case .karisik:            return InstitutionalTheme.Colors.titan
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 3. BIST MONEY FLOW CARD (DEEP DIVE)
// ═══════════════════════════════════════════════════════════════════

struct BistMoneyFlowCard: View {
    let symbol: String
    @State private var result: BistMoneyFlowResult?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Para akışı")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    if let r = result {
                        Text(r.flowStatus.rawValue)
                            .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                            .foregroundColor(flowColor(r.flowStatus))
                    } else {
                        Text("Analiz ediliyor")
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(16)

            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)

            if let r = result {
                // Visual Flow Meter — sade, shadow yok
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(InstitutionalTheme.Colors.crimson.opacity(0.25))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)

                    Circle()
                        .fill(flowColor(r.flowStatus))
                        .frame(width: 10, height: 10)

                    Rectangle()
                        .fill(InstitutionalTheme.Colors.aurora.opacity(0.25))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Deep Dive Metrics
                VStack(alignment: .leading, spacing: 0) {
                    Text("Akıllı para")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.vertical, 8)

                    ForEach(r.metrics) { metric in
                        MetricInsightRow(metric: metric)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loadData() }
    }

    private func loadData() {
        Task {
            if let data = try? await BistMoneyFlowEngine.shared.analyze(symbol: symbol) {
                await MainActor.run { self.result = data }
            }
        }
    }

    private func flowColor(_ status: FlowStatus) -> Color {
        switch status {
        case .strongInflow, .inflow:    return InstitutionalTheme.Colors.aurora
        case .neutral:                  return InstitutionalTheme.Colors.titan
        case .outflow, .strongOutflow:  return InstitutionalTheme.Colors.crimson
        }
    }
}

// BistRejimCard: Kaldırıldı — REJİM modülü artık BistMacroSummaryCard + SirkiyeDashboard + Oracle + Sektör kullanıyor

// Helper
extension Double {
    // Already exists in project likely, can add format helper if needed
}
