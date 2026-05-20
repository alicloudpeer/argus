import SwiftUI

// MARK: - Observatory Container View
/// Main container view for Observatory with tab-based navigation
// MARK: - Observatory Container View
/// Main container view for Observatory with tab-based navigation
struct ObservatoryContainerView: View {
    @State private var selectedTab: ObservatoryTab = .timeline

    // 2026-05-09: Eski sürümde leadingDeco `.bars3` + sağda xmark vardı.
    // Bu view NavigationRouter ile push'lanıyor — push'ta xmark dismiss
    // navigation stack'i pop'lamaz, kullanıcı geri dönemiyordu. Tutarlı
    // back chevron'a alındı.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // V5: Tek katman surface0 background; NeuralNetworkBackground
            // kaldırıldı (mor overdose + performans).
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "GÖZLEMEVİ",
                    subtitle: "ZAMAN · ÖĞRENME · TRADE · SAĞLIK",
                    leadingDeco: .back(onTap: { dismiss() })
                )

                // 3. Custom Tab Bar
                cyberTabBar

                // 4. Content Area
                ZStack {
                    switch selectedTab {
                    case .timeline:
                        ObservatoryTimelineContentView()
                    case .learning:
                        ObservatoryLearningContentView()
                    case .trades:
                        TradeHistoryView()
                    case .health:
                        ObservatoryHealthContentView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
    }

    private var cyberTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ObservatoryTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                            Text(tab.title)
                                .font(DesignTokens.Fonts.custom(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(selectedTab == tab
                                         ? InstitutionalTheme.Colors.holo
                                         : DesignTokens.Colors.textSecondary)
                        .padding(.vertical, 10)

                        // V5 active indicator
                        Rectangle()
                            .fill(selectedTab == tab
                                  ? InstitutionalTheme.Colors.holo
                                  : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .background(DesignTokens.Colors.surface)
        .overlay(ArgusHair(), alignment: .bottom)
    }
}

enum ObservatoryTab: String, CaseIterable {
    case timeline
    case learning
    case trades
    case health
    
    var title: String {
        switch self {
        case .timeline: return "ZAMANÇİZ"
        case .learning: return "ÖĞRENME"
        case .trades: return "TRADE"
        case .health: return "SAĞLIK"
        }
    }
    
    var icon: String {
        switch self {
        case .timeline: return "clock.arrow.circlepath"
        case .learning: return "brain.head.profile"
        case .trades: return "chart.line.uptrend.xyaxis"
        case .health: return "waveform.path.ecg"
        }
    }
}

// MARK: - Timeline Content (Faz 3.6: VM-backed)
struct ObservatoryTimelineContentView: View {
    @StateObject private var viewModel = ObservatoryTimelineViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Filter
            Picker("Filtre", selection: $viewModel.selectedFilter) {
                ForEach(TimelineFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if viewModel.isLoading {
                Spacer()
                ProgressView("Yükleniyor...")
                Spacer()
            } else if viewModel.decisions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(DesignTokens.Fonts.custom(size: 50))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("Henüz karar yok")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredDecisions) { decision in
                            DecisionCardView(decision: decision)
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await viewModel.load() }
    }
}

// MARK: - Learning Content (Faz 3.6: VM-backed)
struct ObservatoryLearningContentView: View {
    @StateObject private var viewModel = ObservatoryLearningViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                Spacer()
                ProgressView("Yükleniyor...")
                Spacer()
            } else if viewModel.events.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(DesignTokens.Fonts.custom(size: 50))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("Henüz öğrenme kaydı yok")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.events) { event in
                            LearningEventCardView(event: event)
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await viewModel.load() }
    }
}

// MARK: - Health Content (Faz 3.6: VM-backed, hesaplama ObservatoryHealthViewModel'de)
struct ObservatoryHealthContentView: View {
    @StateObject private var viewModel = ObservatoryHealthViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCardView(
                        title: "Sharpe",
                        value: String(format: "%.2f", viewModel.metrics.sharpe),
                        icon: "chart.xyaxis.line",
                        color: viewModel.metrics.sharpe > 1 ? .green : (viewModel.metrics.sharpe > 0.5 ? .yellow : .red)
                    )
                    MetricCardView(
                        title: "İsabet",
                        value: String(format: "%.0f%%", viewModel.metrics.hitRate * 100),
                        icon: "target",
                        color: viewModel.metrics.hitRate > 0.55 ? .green : .yellow
                    )
                    MetricCardView(
                        title: "Kâr Faktörü",
                        value: String(format: "%.2f", viewModel.metrics.profitFactor),
                        icon: "dollarsign.circle",
                        color: viewModel.metrics.profitFactor > 1.5 ? .green : .yellow
                    )
                    MetricCardView(
                        title: "Maks DD",
                        value: String(format: "%.1f%%", viewModel.metrics.maxDrawdown),
                        icon: "arrow.down.right",
                        color: viewModel.metrics.maxDrawdown < 10 ? .green : .red
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Çıktı Dağılımı")
                        .font(.headline)

                    HStack(spacing: 2) {
                        Rectangle().fill(Color.green)
                            .frame(width: CGFloat(viewModel.distribution.buyPercent) * 2, height: 20)
                        Rectangle().fill(Color.gray)
                            .frame(width: CGFloat(viewModel.distribution.holdPercent) * 2, height: 20)
                        Rectangle().fill(Color.red)
                            .frame(width: CGFloat(viewModel.distribution.sellPercent) * 2, height: 20)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    if viewModel.distribution.isDrifting {
                        Label("Drift tespit edildi: \(viewModel.distribution.driftReason)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }
            .padding()
        }
        .task { await viewModel.load() }
    }
}

// MARK: - Decision Card View
struct DecisionCardView: View {
    let decision: DecisionCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(decision.symbol)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                
                Spacer()
                
                Text(decision.action)
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(decision.actionColor.opacity(0.2))
                    .foregroundColor(decision.actionColor)
                    .cornerRadius(4)
            }
            
            // Factor bilgilerini göster
            if !decision.topFactors.isEmpty {
                HStack(spacing: 6) {
                    ForEach(decision.topFactors.prefix(3), id: \.name) { factor in
                        Text("\(factor.name): \(Int(factor.value))")
                            .font(DesignTokens.Fonts.custom(size: 10, design: .monospaced))
                            .foregroundColor(factor.value >= 50 ? .green : .red)
                    }
                }
            }
            
            HStack {
                Label(decision.market, systemImage: "globe")
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                
                Spacer()
                
                if let pnl = decision.actualPnl {
                    Text(String(format: "%.2f%%", pnl))
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(pnl >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(InstitutionalTheme.Colors.holo.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Learning Event Card View
struct LearningEventCardView: View {
    let event: LearningEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Öğrenme")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                Spacer()

                Text(event.timestamp, style: .date)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            
            Text(event.reason)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .lineLimit(3)
            
            // Weight değişimlerini göster
            Text(event.summaryText)
                .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                .foregroundColor(InstitutionalTheme.Colors.holo)
        }
        .padding()
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(InstitutionalTheme.Colors.holo.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Metric Card View
struct MetricCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(DesignTokens.Fonts.custom(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ObservatoryContainerView()
}

// MARK: - TimelineFilter (moved here from deleted ObservatoryTimelineView)
enum TimelineFilter: String, CaseIterable {
    case all      = "Tümü"
    case pending  = "Bekleyen"
    case matured  = "Olgunlaşmış"
    case bist     = "BIST"
    case global   = "Global"

    var displayName: String { rawValue }
}

// MARK: - DecisionCard UI Extension (moved here from deleted ObservatoryTimelineView)
extension DecisionCard {
    var actionColor: Color {
        switch action.uppercased() {
        case "BUY", "AL":  return .green
        case "SELL", "SAT": return .red
        default:           return .orange
        }
    }
}
