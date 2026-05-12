import SwiftUI

// MARK: - SANCTUM 2.0 DESIGN SYSTEM
// "Gotham City Batcomputer" Aesthetic

struct Sanctum2Theme {
    // Colors
    static let voidBlack = DesignTokens.Colors.background
    static let neonGreen = DesignTokens.Colors.success
    static let crimsonRed = DesignTokens.Colors.error
    static let hologramBlue = DesignTokens.Colors.primary
    static let amberWarning = InstitutionalTheme.Colors.warning
    static let midGray = InstitutionalTheme.Colors.surface3

    // Gradients
    static let glassGradient = LinearGradient(
        colors: [InstitutionalTheme.Colors.surface3, DesignTokens.Colors.surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Borders
    static func neonBorder(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [color.opacity(0.35), DesignTokens.Colors.borderSubtle],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

// MARK: - COMPONENTS

// 1. CINEMATIC HEADER (Compact & Stylish)
struct CinematicHeader: View {
    let symbol: String
    let price: Double?
    let change: Double?
    let sector: String
    var onDismiss: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Back Button (Cyber)
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .bold))
                    .foregroundColor(Sanctum2Theme.hologramBlue)
                    .frame(width: 36, height: 36)
                    .background(DesignTokens.Colors.surfaceElevated)
                    .cornerRadius(InstitutionalTheme.Radius.sm)
                    .overlay(Sanctum2Theme.neonBorder(Sanctum2Theme.hologramBlue))
            }
            
            // Symbol & Sector
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(symbol.replacingOccurrences(of: ".IS", with: ""))
                        .font(DesignTokens.Fonts.custom(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .shadow(color: Sanctum2Theme.hologramBlue.opacity(0.5), radius: 8, x: 0, y: 0)
                    
                    Text("•")
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .font(.caption)
                    
                    Text(sector.uppercased())
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
                
                // Live Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMarketOpen ? Sanctum2Theme.neonGreen : Sanctum2Theme.crimsonRed)
                        .frame(width: 6, height: 6)
                        .shadow(color: (isMarketOpen ? Sanctum2Theme.neonGreen : Sanctum2Theme.crimsonRed).opacity(0.8), radius: 4)
                    
                    Text(isMarketOpen ? "PİYASA AÇIK" : "PİYASA KAPALI")
                        .font(DesignTokens.Fonts.custom(size: 9, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Price (Hero but Compact)
            if let p = price, let c = change {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", p))
                        .font(DesignTokens.Fonts.custom(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: c >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%+.2f%%", c))
                    }
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                    .foregroundColor(c >= 0 ? Sanctum2Theme.neonGreen : Sanctum2Theme.crimsonRed)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Sanctum2Theme.voidBlack)
        .overlay(Divider().background(DesignTokens.Colors.borderSubtle), alignment: .bottom)
    }
    
    // Quick Logic for Market Hours (Simplified)
    var isMarketOpen: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        // BIST Logic: 10:00 - 18:00 roughly
        return hour >= 10 && hour < 18
    }
}

// 2. BENTO CARD (The building block)
struct BentoCard<Content: View, HeaderAccessory: View>: View {
    let title: String
    let icon: String // SF Symbol
    let accentColor: Color
    var height: CGFloat? = nil // Optional fixed height
    @ViewBuilder let headerAccessory: () -> HeaderAccessory
    @ViewBuilder let content: () -> Content
    
    // Overload for no accessory
    init(title: String, icon: String, accentColor: Color, height: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) where HeaderAccessory == EmptyView {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.height = height
        self.headerAccessory = { EmptyView() }
        self.content = content
    }

    // Full init
    init(title: String, icon: String, accentColor: Color, height: CGFloat? = nil, @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.height = height
        self.headerAccessory = headerAccessory
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Card Header
            HStack {
                HStack(spacing: 6) {
                    // Custom asset veya SF Symbol
                    if icon.hasSuffix("Icon") {
                        Image(icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: icon)
                            .font(DesignTokens.Fonts.custom(size: 11, weight: .bold))
                            .foregroundColor(accentColor)
                    }

                    Text(title.uppercased())
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .heavy))
                        .foregroundColor(accentColor.opacity(0.8))
                        .tracking(1) // Letter spacing
                }
                
                Spacer()
                
                headerAccessory()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // Content
            content()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: height) // If fixed height provided
        .background(Sanctum2Theme.glassGradient)
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
        .institutionalCard(scale: .insight, elevated: true)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
    }
}

