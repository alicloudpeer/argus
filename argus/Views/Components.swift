import SwiftUI
import Charts

struct SignalDetailView: View {
    let signal: Signal
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(signal.strategyName)
                            .font(InstitutionalTheme.Typography.title)
                            .bold()
                        Spacer()
                        Text(signal.action.rawValue)
                            .font(InstitutionalTheme.Typography.bodyStrong)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colorForAction(signal.action).opacity(0.2))
                            .foregroundColor(colorForAction(signal.action))
                            .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Basitleştirilmiş Anlatım", systemImage: "brain.head.profile")
                            .font(InstitutionalTheme.Typography.bodyStrong)
                            .foregroundColor(DesignTokens.Colors.primary)
                        
                        Text(signal.simplifiedExplanation)
                            .font(InstitutionalTheme.Typography.body)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .institutionalCard(scale: .standard, elevated: false)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Teknik Detaylar", systemImage: "waveform.path.ecg")
                            .font(InstitutionalTheme.Typography.bodyStrong)
                        
                        Text("Mevcut Değerler:")
                            .font(InstitutionalTheme.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                        
                        HStack(spacing: 20) {
                            ForEach(signal.indicatorValues.sorted(by: >), id: \.key) { key, value in
                                VStack {
                                    Text(key).font(InstitutionalTheme.Typography.caption).foregroundColor(DesignTokens.Colors.textSecondary)
                                    Text(value).font(InstitutionalTheme.Typography.bodyStrong).fontDesign(.monospaced)
                                }
                                .padding(10)
                                .institutionalCard(scale: .micro, elevated: false)
                            }
                        }
                        
                        Text("Sinyal Nedeni: \(signal.reason)")
                            .font(InstitutionalTheme.Typography.caption)
                            .italic()
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .padding(.top, 5)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle("İndikatör Rehberi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func colorForAction(_ action: SignalAction) -> Color {
        switch action {
        case .buy: return DesignTokens.Colors.success
        case .sell: return DesignTokens.Colors.error
        case .hold: return DesignTokens.Colors.textSecondary
        case .wait: return DesignTokens.Colors.textSecondary
        case .skip: return DesignTokens.Colors.textSecondary
        }
    }
}

