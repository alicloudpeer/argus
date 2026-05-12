import SwiftUI

// MARK: - Konsey raporu (eski adıyla Argus Analyst Report)
//
// 2026-04-30 H-58 — sade refactor.
// Eski yapı V5: MotorLogo(.council) + caps "ARGUS ANALİST · SYMBOL" caption
// + caps mono loading "SYMBOL ANALİZ EDİLİYOR…" + monospaced report gövdesi
// + caps mono "POWERED BY ARGUS AI ENGINE" footer (corporate boilerplate)
// + motor tint border.
// Yeni: "Konsey raporu" sentence başlık + sembol + sade text durum + system
// font report gövdesi (typewriter aynen) + footer kaldırıldı + hairline border.

struct ArgusAnalystReportView: View {
    let symbol: String

    @State private var displayedText: String = ""
    @State private var fullReportText: String = ""
    @State private var isLoading: Bool = true
    @State private var typewriterTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                loadingBlock
            } else {
                reportBody
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
        )
        .onAppear { loadAIReport() }
        .onDisappear { typewriterTimer?.invalidate() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Konsey raporu")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(symbol.uppercased())
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            Text(isLoading ? "Hazırlanıyor" : "Hazır")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(isLoading
                                 ? DesignTokens.Colors.textTertiary
                                 : InstitutionalTheme.Colors.aurora)
        }
    }

    // MARK: - States

    private var loadingBlock: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("\(symbol.uppercased()) analiz ediliyor")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var reportBody: some View {
        ScrollView {
            Text(displayedText)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md,
                                     style: .continuous)
                        .fill(DesignTokens.Colors.surfaceElevated)
                )
        }
        .frame(minHeight: 280, maxHeight: 500)
    }

    // MARK: - AI Report Loading

    private func loadAIReport() {
        isLoading = true

        Task {
            let aiReport = await ArgusNarrativeEngine.generateAIReport(
                symbol: symbol,
                type: .comprehensive
            )

            await MainActor.run {
                fullReportText = aiReport
                isLoading = false
                startTypewriterEffect()
            }
        }
    }

    private func startTypewriterEffect() {
        displayedText = ""
        let chars = Array(fullReportText)
        var index = 0

        typewriterTimer = Timer.scheduledTimer(withTimeInterval: 0.003, repeats: true) { timer in
            if index < chars.count {
                displayedText.append(chars[index])
                index += 1
            } else {
                timer.invalidate()
            }
        }
    }
}
