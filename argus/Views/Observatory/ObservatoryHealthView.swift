import SwiftUI

// MARK: - Observatory Health View
/// Displays system health metrics, drift detection, and data quality alerts
// MARK: - Observatory Health View
/// Displays system health metrics, drift detection, and data quality alerts
struct ObservatoryHealthView: View {
    // Faz 3.6: ObservatoryHealthViewModel'i kullanır; hesaplama VM'de.
    @StateObject private var viewModel = ObservatoryHealthViewModel()

    private var metrics: PerformanceMetrics { viewModel.metrics }
    private var distribution: PredictionDistribution { viewModel.distribution }
    private var alerts: [DataQualityAlert] { viewModel.alerts }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                performanceHUD
                driftEnergyBar
                systemLogConsole
            }
            .padding(.top, 20)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .task { await viewModel.load() }
    }
    
    // MARK: - Performance HUD
    private var performanceHUD: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SYSTEM_PERFORMANCE", systemImage: "chart.line.uptrend.xyaxis")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                HoloMetricCard(
                    title: "SHARPE",
                    value: String(format: "%.2f", metrics.sharpe),
                    icon: "chart.xyaxis.line",
                    color: metrics.sharpe > 1.0 ? InstitutionalTheme.Colors.aurora : (metrics.sharpe > 0.5 ? InstitutionalTheme.Colors.titan : InstitutionalTheme.Colors.crimson)
                )
                
                HoloMetricCard(
                    title: "HIT_RATE",
                    value: String(format: "%.0f%%", metrics.hitRate * 100),
                    icon: "target",
                    color: metrics.hitRate > 0.55 ? InstitutionalTheme.Colors.aurora : (metrics.hitRate > 0.45 ? InstitutionalTheme.Colors.titan : InstitutionalTheme.Colors.crimson)
                )
                
                HoloMetricCard(
                    title: "PROFIT_FACTOR",
                    value: String(format: "%.2f", metrics.profitFactor),
                    icon: "dollarsign.circle",
                    color: metrics.profitFactor > 1.5 ? InstitutionalTheme.Colors.aurora : (metrics.profitFactor > 1.0 ? InstitutionalTheme.Colors.titan : InstitutionalTheme.Colors.crimson)
                )
                
                HoloMetricCard(
                    title: "MAX_DD",
                    value: String(format: "%.1f%%", metrics.maxDrawdown),
                    icon: "arrow.down.right",
                    color: metrics.maxDrawdown < 10 ? InstitutionalTheme.Colors.aurora : (metrics.maxDrawdown < 20 ? InstitutionalTheme.Colors.titan : InstitutionalTheme.Colors.crimson)
                )
            }
        }
    }
    
    // MARK: - Drift Energy Bar
    private var driftEnergyBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PREDICTION_DRIFT", systemImage: "chart.pie")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // BUY
                    Rectangle()
                        .fill(InstitutionalTheme.Colors.aurora)
                        .frame(width: max(0, CGFloat(distribution.buyPercent / 100) * (UIScreen.main.bounds.width - 40)))
                    
                    // HOLD
                    Rectangle()
                        .fill(DesignTokens.Colors.textSecondary.opacity(0.3))
                        .frame(width: max(0, CGFloat(distribution.holdPercent / 100) * (UIScreen.main.bounds.width - 40)))
                    
                    // SELL
                    Rectangle()
                        .fill(InstitutionalTheme.Colors.crimson)
                        .frame(width: max(0, CGFloat(distribution.sellPercent / 100) * (UIScreen.main.bounds.width - 40)))
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                
                // Labels below bar
                HStack {
                    Text("BUY \(Int(distribution.buyPercent))%")
                        .foregroundColor(InstitutionalTheme.Colors.aurora)
                    Spacer()
                    Text("HOLD \(Int(distribution.holdPercent))%")
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Spacer()
                    Text("SELL \(Int(distribution.sellPercent))%")
                        .foregroundColor(InstitutionalTheme.Colors.crimson)
                }
                .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                .padding(.top, 6)
            }
            .padding(12)
            .background(DesignTokens.Colors.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignTokens.Colors.Overlay.l10, lineWidth: 1)
            )
            
            // Drift Warning
            if distribution.isDrifting {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundStyle(InstitutionalTheme.Colors.titan)
                    Text("Sapma algılandı: \(distribution.driftReason)")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundStyle(InstitutionalTheme.Colors.titan)
                }
                .padding(8)
                .background(InstitutionalTheme.Colors.titan.opacity(0.08))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - System Log Console
    private var systemLogConsole: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sistem günlüğü", systemImage: "exclamationmark.shield")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            
            if alerts.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(InstitutionalTheme.Colors.aurora)
                    Text("ALL SYSTEMS NOMINAL")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.Colors.surface)
                .cornerRadius(8)
            } else {
                ForEach(alerts) { alert in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: alert.icon)
                            .font(DesignTokens.Fonts.custom(size: 14))
                            .foregroundStyle(alert.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(DesignTokens.Fonts.custom(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Text(alert.message)
                                .font(DesignTokens.Fonts.custom(size: 10, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Text(alert.formattedTime)
                            .font(DesignTokens.Fonts.custom(size: 9, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary.opacity(0.5))
                    }
                    .padding(12)
                    .background(DesignTokens.Colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(alert.color.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // Faz 3.6: loadData() ObservatoryHealthViewModel.load()'a taşındı.
}

// MARK: - Holo Metric Card
struct HoloMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(DesignTokens.Fonts.custom(size: 14))
                Spacer()
            }
            
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 20, weight: .black, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding()
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.3), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Supporting Models

struct PerformanceMetrics {
    let sharpe: Double
    let hitRate: Double
    let profitFactor: Double
    let maxDrawdown: Double
    
    static var empty: PerformanceMetrics {
        PerformanceMetrics(sharpe: 0, hitRate: 0, profitFactor: 0, maxDrawdown: 0)
    }
}

struct PredictionDistribution {
    let buyPercent: Double
    let holdPercent: Double
    let sellPercent: Double
    let isDrifting: Bool
    let driftReason: String
    
    static var empty: PredictionDistribution {
        PredictionDistribution(buyPercent: 33, holdPercent: 34, sellPercent: 33, isDrifting: false, driftReason: "")
    }
}

struct DataQualityAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    
    enum AlertSeverity {
        case warning, error, info
    }
    
    var icon: String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Preview
#Preview {
    ObservatoryHealthView()
}
