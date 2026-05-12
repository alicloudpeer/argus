import SwiftUI

struct BistSectorAverage {
    let profitabilityAvg: Double
    let valuationAvg: Double
    let growthAvg: Double
    let healthAvg: Double
    let cashAvg: Double
    let dividendAvg: Double
}

struct BistSectorComparisonCard: View {
    let symbol: String
    let result: AtlasV2Result
    @State private var sectorAverage: BistSectorAverage?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(DesignTokens.Colors.primary)
                Text("SEKTÖR KIYASLAMASI")
                    .font(.caption).bold().foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
            
            if let sectorAvg = sectorAverage {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    SectorMetricComparison(
                        label: "Karlılık",
                        current: result.profitabilityScore,
                        average: sectorAvg.profitabilityAvg
                    )
                    
                    SectorMetricComparison(
                        label: "Değerleme",
                        current: result.valuationScore,
                        average: sectorAvg.valuationAvg
                    )
                    
                    SectorMetricComparison(
                        label: "Büyüme",
                        current: result.growthScore,
                        average: sectorAvg.growthAvg
                    )
                    
                    SectorMetricComparison(
                        label: "Sağlık",
                        current: result.healthScore,
                        average: sectorAvg.healthAvg
                    )
                    
                    SectorMetricComparison(
                        label: "Nakit",
                        current: result.cashScore,
                        average: sectorAvg.cashAvg
                    )
                    
                    SectorMetricComparison(
                        label: "Temettü",
                        current: result.dividendScore,
                        average: sectorAvg.dividendAvg
                    )
                }
            } else {
                Text("Sektör kıyas verisi şu an mevcut değil.")
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(DesignTokens.Colors.surfaceElevated)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.primary.opacity(0.25), lineWidth: 1)
        )
        .onAppear { loadSectorData() }
    }
    
    private func loadSectorData() {
        // Mock veri yerine boş geçilir; gerçek veri kaynağı bağlandığında burada yüklenecek.
        isLoading = false
        sectorAverage = nil
    }
}

