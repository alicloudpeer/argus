import SwiftUI

// MARK: - REUSABLE HOLO SHEET (The "Jilet Gibi" Animation)
struct ModuleHoloSheet: View {
    let module: ArgusSanctumView.ModuleType
    let symbol: String
    let onClose: () -> Void

    @State private var chironPulseWeights: ChironModuleWeights?
    @State private var chironCorseWeights: ChironModuleWeights?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: module.icon)
                    .foregroundColor(module.color)
                    .font(.title3)
                Text(module.rawValue)
                    .font(.headline)
                    .bold()
                    .tracking(2)
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Circle().fill(DesignTokens.Colors.Overlay.l10))
                }
            }
            .padding()
            .background(
                LinearGradient(colors: [module.color.opacity(0.2), .black], startPoint: .top, endPoint: .bottom)
            )

            Divider().background(module.color)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(module.description)
                        .font(.caption)
                        .italic()
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal)

                    SanctumContentLogic(module: module, symbol: symbol)
                }
                .padding(.vertical)
            }
        }
        .task {
            if module == .atlas {
                if FundamentalScoreStore.shared.getScore(for: symbol) == nil {
                    await SignalViewModel.shared.calculateFundamentalScore(for: symbol, assetType: .stock)
                }
            } else if module == .orion {
                if SignalStateViewModel.shared.orionScores[symbol] == nil {
                    await SignalStateViewModel.shared.ensureOrionAnalysis(for: symbol)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Material.ultraThinMaterial)
        .background(DesignTokens.Colors.Scrim.s80)
        .edgesIgnoringSafeArea(.bottom)
    }
}

// Helper struct to render content, extracted from Sanctum logic
private struct SanctumContentLogic: View {
    let module: ArgusSanctumView.ModuleType
    let symbol: String

    var body: some View {
        Group {
            switch module {
            case .atlas:
                if symbol.uppercased().hasSuffix(".IS") || SymbolResolver.shared.isBistSymbol(symbol) {
                    let bistSymbol = symbol.uppercased().hasSuffix(".IS") ? symbol : "\(symbol.uppercased()).IS"
                    BISTBilancoDetailView(sembol: bistSymbol)
                } else {
                    AtlasV2DetailView(symbol: symbol)
                }
            case .orion:
                OrionContent(symbol: symbol)
            default:
                VStack {
                    Text("Bu modülün detay görünümü hazırlanıyor...")
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding()
            }
        }
    }
}

// Extracted Content Views
private struct AtlasContent: View {
    let symbol: String

    var body: some View {
        if let result = FundamentalScoreStore.shared.getScore(for: symbol) {
            let score = Int(result.totalScore)
            VStack(alignment: .leading, spacing: 12) {
                // Score Header
                HStack {
                    Text("Temel Puan")
                        .font(.headline)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text("\(score)")
                        .font(DesignTokens.Fonts.custom(size: 40, weight: .black))
                        .foregroundColor(score > 60 ? .green : (score > 40 ? .yellow : .red))
                }
                .padding(.horizontal)
                
                Divider().background(DesignTokens.Colors.Overlay.l10)
                
                // Highlights
                if !result.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.highlights.prefix(4), id: \.self) { highlight in
                            HStack(alignment: .top) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(DesignTokens.Colors.success).font(.caption)
                                Text(highlight).font(.caption).foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Breakdown Chart
                VStack(spacing: 8) {
                    breakdownRow("Karlılık", score: result.profitabilityScore ?? 0, max: 25)
                    breakdownRow("Büyüme", score: result.growthScore ?? 0, max: 25)
                    breakdownRow("Kaldıraç", score: result.leverageScore ?? 0, max: 25)
                    breakdownRow("Nakit", score: result.cashQualityScore ?? 0, max: 25)
                }
                .padding()
                .background(DesignTokens.Colors.Overlay.l05)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        } else {
            ProgressView().padding()
        }
    }
    
    func breakdownRow(_ title: String, score: Double, max: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text("\(Int(score))/\(Int(max))").font(.caption).bold().foregroundColor(DesignTokens.Colors.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule().fill(Color.yellow)
                        .frame(width: geo.size.width * (score / max))
                }
            }
            .frame(height: 4)
        }
    }
}

private struct OrionContent: View {
    @ObservedObject private var signalState = SignalStateViewModel.shared
    let symbol: String

    var body: some View {
        if let orion = signalState.orionScores[symbol] {
            VStack(alignment: .leading, spacing: 16) {
                // Score Gauge
                HStack {
                    Text("Teknik Puan")
                        .font(.headline)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        Circle().trim(from: 0, to: orion.score / 100)
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(orion.score))")
                            .font(.title2).bold().foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    .frame(width: 60, height: 60)
                }
                .padding(.horizontal)
                
                // Components
                VStack(spacing: 12) {
                    componentRow("Yapı (Structure)", val: orion.components.structure, max: 35, color: .cyan)
                    componentRow("Trend", val: orion.components.trend, max: 25, color: .green)
                    componentRow("Momentum", val: orion.components.momentum, max: 25, color: .orange)
                    componentRow("Pattern", val: orion.components.pattern, max: 15, color: .purple)
                }
                .padding()
                .background(DesignTokens.Colors.Overlay.l05)
                .cornerRadius(12)
            }
        } else {
            ProgressView().padding()
        }
    }
    
    func componentRow(_ title: String, val: Double, max: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text(String(format: "%.1f", val)).font(.caption).bold().foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * (val / max))
                }
            }
            .frame(height: 4)
        }
    }
}
