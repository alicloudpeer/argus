import SwiftUI

struct GorevGunluguView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "Görev Günlüğü",
                    subtitle: "Otopilot karar merkezi",
                    leadingDeco: .back(onTap: { dismiss() }),
                    titlePill: nil,
                    actions: []
                )
                Spacer()
                Text("Yakında burada.")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}
