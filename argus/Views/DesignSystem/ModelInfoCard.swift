import SwiftUI

struct SystemInfoCard: View {
    let entity: ArgusSystemEntity
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            DesignTokens.Colors.background.opacity(0.72).ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
            
            // Card Container (No GlassCard, use Direct Background)
            VStack(spacing: 20) {
                // Header
                    HStack {
                        Image(systemName: entity.icon)
                            .font(.title)
                            .foregroundColor(color(for: entity))
                        
                        Text(entity.displayName.uppercased())
                            .font(InstitutionalTheme.Typography.headline)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Spacer()
                        
                        Button { withAnimation { isPresented = false } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                        }
                    }
                    
                    Divider().background(DesignTokens.Colors.borderSubtle)
                    
                    // Description
                    Text(entity.description)
                        .font(InstitutionalTheme.Typography.dataSmall)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                    
                    // Stats / Traits handled generically or customized logic below
                    HStack(spacing: 16) {
                        trait(icon: "brain.head.profile", label: "AI Modülü")
                        trait(icon: "lock.shield", label: "Aktif")
                    }
                }
                .padding(24)
            .institutionalCard(scale: .insight, elevated: true)
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(color(for: entity).opacity(0.3), lineWidth: 1)
            )
            .frame(maxWidth: 340)
            .shadow(color: DesignTokens.Colors.background.opacity(0.6), radius: 20, x: 0, y: 10)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func color(for entity: ArgusSystemEntity) -> Color {
        switch entity {
        case .atlas: return SanctumTheme.atlasColor      // Titan Gold
        case .orion: return SanctumTheme.orionColor      // Hologram Blue
        case .aether: return SanctumTheme.aetherColor    // Ghost Grey
        case .hermes: return SanctumTheme.hermesColor    // Orange
        case .demeter: return SanctumTheme.demeterColor  // Aurora Green
        case .argus, .council, .corse, .pulse, .shield, .poseidon: return SanctumTheme.chironColor // White/System
        }
    }
    
    private func trait(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
                .bold()
        }
        .padding(8)
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
        .cornerRadius(8)
        .foregroundColor(DesignTokens.Colors.textPrimary)
    }
}
