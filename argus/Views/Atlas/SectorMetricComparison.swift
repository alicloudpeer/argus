import SwiftUI

struct SectorMetricComparison: View {
    let label: String
    let current: Double
    let average: Double
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2).foregroundColor(DesignTokens.Colors.textSecondary)
            
            HStack(spacing: 4) {
                Text(String(format: "%.0f", current))
                    .font(.caption).bold().foregroundColor(DesignTokens.Colors.textPrimary)
                
                if current > average {
                    Image(systemName: "arrow.up.right.fill")
                        .font(.caption2).foregroundColor(DesignTokens.Colors.success)
                } else if current < average {
                    Image(systemName: "arrow.down.right.fill")
                        .font(.caption2).foregroundColor(DesignTokens.Colors.error)
                } else {
                    Image(systemName: "equal")
                        .font(.caption2).foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
            
            // Comparison bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 4)
                
                HStack(spacing: 0) {
                    Capsule()
                        .fill(DesignTokens.Colors.primary.opacity(0.7))
                        .frame(width: CGFloat(current / 100) * 40, height: 4)
                    
                    Capsule()
                        .fill(InstitutionalTheme.Colors.warning.opacity(0.6))
                        .frame(width: CGFloat(average / 100) * 40, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

