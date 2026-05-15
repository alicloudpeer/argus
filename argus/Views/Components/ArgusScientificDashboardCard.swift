import SwiftUI

// MARK: - Argus Scientific Dashboard Card (2026-05-15 V5 sade yeniden yazım)
//
// Eski: flask icon, "BİLİMSEL DOĞRULAMA" CAPS, 6 metric 2x3 grid box
// (`Color(hex: "1A1A1A")` inline dark + cyan stroke), `.cyan/.green/.red/
// .orange/.gray` 6 farklı sistem rengi, `checkmark.seal.fill / xmark.seal.fill`
// log icon spam'i, "X Adet İncelenebilir" turuncu text — AI-tell dolu.
//
// Yeni: MarketView "yağ gibi" dili — kart yok, ayraçlı 4 bölüm (hero özet +
// performans + son doğrulamalar + bekleyen), success/error sadece anlamlı
// yerlerde, severity için sol 2pt bar (renksiz icon yok), primary holo button
// vade dolan varsa.
struct ArgusScientificDashboardCard: View {
    @State private var stats: ScientificStats = .empty
    @State private var pendingHypotheses: [PendingForwardTest] = []
    @State private var recentResults: [ForwardTestResult] = []
    @State private var isProcessing = false
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                heroSection
                divider
                performansSection
                if !recentResults.isEmpty {
                    divider
                    sonDogrulamalarSection
                }
                divider
                bekleyenSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadData() }
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: DesignTokens.BorderWidth.hairline)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Doğrulanan hipotezler")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                Text("\(stats.validatedHypotheses)")
                    .font(DesignTokens.Fonts.custom(size: 32, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                if totalHypotheses > 0 {
                    Text("/ \(totalHypotheses) toplam")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
            }

            Text("Forward test günlüğü. Bekleyen hipotezler vade dolduğunda otomatik analiz edilir.")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DesignTokens.Spacing.sm)
        }
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private var totalHypotheses: Int {
        stats.validatedHypotheses + pendingHypotheses.count
    }

    // MARK: - Performans

    private var performansSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Performans")
                .padding(.bottom, DesignTokens.Spacing.s6)

            metricRow(label: "Kazanma oranı",
                      value: String(format: "%%%.1f", stats.winRate * 100),
                      color: stats.winRate >= 0.5
                        ? DesignTokens.Colors.success
                        : DesignTokens.Colors.textPrimary)
            rowDivider
            metricRow(label: "Kâr çarpanı",
                      value: String(format: "%.2f", stats.profitFactor),
                      color: DesignTokens.Colors.textPrimary)
            rowDivider
            metricRow(label: "Sharpe oranı",
                      value: String(format: "%.2f", stats.sharpeRatio),
                      color: DesignTokens.Colors.textPrimary)
            rowDivider
            metricRow(label: "Ortalama getiri",
                      value: String(format: "%+.2f%%", stats.averageReturn),
                      color: stats.averageReturn >= 0
                        ? DesignTokens.Colors.success
                        : DesignTokens.Colors.error)
            rowDivider
            metricRow(label: "En kötü düşüş",
                      value: String(format: "−%.1f%%", abs(stats.maxDrawdown)),
                      color: DesignTokens.Colors.error)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.vertical, DesignTokens.Spacing.s10)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: DesignTokens.BorderWidth.hairline)
    }

    // MARK: - Son doğrulamalar

    private var sonDogrulamalarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Son doğrulamalar")
                .padding(.bottom, DesignTokens.Spacing.s6)

            ForEach(Array(recentResults.prefix(3).enumerated()), id: \.element.id) { idx, result in
                validationRow(result)
                if idx < min(2, recentResults.count - 1) {
                    rowDivider
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func validationRow(_ result: ForwardTestResult) -> some View {
        let success = result.wasCorrect
        let actualText = String(format: "%+.2f%%", result.actualChange)
        let resultColor: Color = success
            ? DesignTokens.Colors.success
            : DesignTokens.Colors.error
        let detailText: String = {
            if let notes = result.notes, !notes.isEmpty { return notes }
            return success ? "Tez doğrulandı" : "Beklenti gerçekleşmedi"
        }()

        return HStack(alignment: .center, spacing: DesignTokens.Spacing.s10) {
            Capsule()
                .fill(resultColor)
                .frame(width: 2, height: 32)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(result.symbol)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(detailText)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(actualText)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(resultColor)
        }
        .padding(.vertical, DesignTokens.Spacing.s10)
    }

    // MARK: - Bekleyen

    private var bekleyenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Bekleyen hipotezler")
                .padding(.bottom, DesignTokens.Spacing.s6)

            HStack {
                Text("Vade dolan")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("\(matureCount)")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(matureCount > 0
                                     ? DesignTokens.Colors.textPrimary
                                     : DesignTokens.Colors.textTertiary)
            }
            .padding(.vertical, DesignTokens.Spacing.s10)

            rowDivider

            HStack {
                Text("Vade bekliyor")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("\(pendingHypotheses.count - matureCount)")
                    .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(.vertical, DesignTokens.Spacing.s10)

            // Analiz button — vade dolan varsa primary holo, yoksa outline disabled
            Button(action: runValidation) {
                Text(buttonLabel)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.s13)
                    .background(buttonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(matureCount > 0 || isProcessing
                                    ? Color.clear
                                    : DesignTokens.Colors.border,
                                    lineWidth: DesignTokens.BorderWidth.hairline)
                    )
                    .cornerRadius(DesignTokens.Radius.md)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing || matureCount == 0)
            .padding(.top, DesignTokens.Spacing.md)

            Text("Argus her karar için gizli hipotez kaydeder. Vade dolduğunda gerçekleşen sonuçla karşılaştırır — sistem kendi başarısını gözlemler.")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DesignTokens.Spacing.md)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var matureCount: Int {
        pendingHypotheses.filter { $0.isMature }.count
    }

    private var buttonLabel: String {
        if isProcessing { return "Analiz çalışıyor…" }
        if matureCount == 0 { return "Analiz edilecek hipotez yok" }
        return "Vade dolanları şimdi analiz et"
    }

    private var buttonForeground: Color {
        if isProcessing || matureCount == 0 {
            return DesignTokens.Colors.textTertiary
        }
        return DesignTokens.Colors.background
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if matureCount > 0 && !isProcessing {
            DesignTokens.Colors.primary
        } else {
            Color.clear
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
            .foregroundColor(DesignTokens.Colors.textTertiary)
    }

    // MARK: - Logic

    private func loadData() async {
        isLoading = true
        stats = await ArgusValidator.shared.calculateScientificMetrics()
        pendingHypotheses = await ArgusValidator.shared.getPendingHypotheses()

        let resultsPath = FileManager.default.documentsURL
            .appendingPathComponent("ArgusScientificResults.json")
        if let data = try? Data(contentsOf: resultsPath),
           let results = try? JSONDecoder().decode([ForwardTestResult].self, from: data) {
            recentResults = Array(results.suffix(5).reversed())
        }

        isLoading = false
    }

    private func runValidation() {
        isProcessing = true
        Task {
            _ = await ArgusValidator.shared.validateMaturedHypotheses()
            await loadData()
            isProcessing = false
        }
    }
}
