import SwiftUI

/// Faz 1.C: Settings → Modül Karnesi ekranı (2026-05-14 V5 sade yeniden yazım).
///
/// Eski: `.smallCaps()` heavy caps, `.foregroundColor(.green/.red/.orange)`,
/// `Color(.secondarySystemBackground)`, default font ölçeği — tasarım sistemi
/// sıfır kullanıyordu.
///
/// Yeni: MarketView/Portfolio "yağ gibi" dili — sade row liste, sentence case,
/// DesignTokens.Colors.success/warning/error (V5 aurora/titan/crimson),
/// monospace yalnız sayılarda, üst nav'da geri butonu.
///
/// `ModulePerformanceTracker.getAllStats()` verisini görselleştirir — her
/// modülün decisive oy sayısı, hit rate'i ve PnL katkısı tek bakışta görünür.
/// Hit rate renk-kodlu:
/// - ≥ %55 success (kazanan modül)
/// - %45 – %55 warning (kararsız)
/// - < %45 error (kaybeden modül — gelecekte auto-disable adayı)
struct ModulKarneView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var stats: [ModulePerformanceTracker.ModuleStats] = []
    @State private var isLoading: Bool = true

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        explanation
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignTokens.Spacing.xl)
                        } else if stats.isEmpty {
                            emptyState
                        } else {
                            moduleList
                        }

                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.s14)
                    .padding(.top, DesignTokens.Spacing.md)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await load()
        }
    }

    // MARK: - Top nav

    private var topNav: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Geri")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Modül karnesi")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("Her modülün isabet oranı ve katkısı")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.s14)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.s10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: DesignTokens.BorderWidth.hairline)
        }
    }

    // MARK: - Explanation

    private var explanation: some View {
        Text("Decisive (al/sat) oyları arasında ne kadarı doğru çıktı. Hit rate yüksek modüller pratikte sinyal yaratıyor.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(2)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.sm)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(DesignTokens.Fonts.custom(size: 32))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text("Henüz veri yok")
                .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text("Trade'ler kapandıkça modül başına karne dolacak.")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxl)
    }

    // MARK: - Module list

    private var moduleList: some View {
        VStack(spacing: 0) {
            ForEach(stats, id: \.module) { stat in
                ModulKarneRow(stat: stat)
                if stat.module != stats.last?.module {
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: DesignTokens.BorderWidth.hairline)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        stats = await ModulePerformanceTracker.shared.getAllStats()
        isLoading = false
    }
}

// MARK: - Row

private struct ModulKarneRow: View {
    let stat: ModulePerformanceTracker.ModuleStats

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Üst: modül adı + hit rate yüzde (sağda büyük)
            HStack(alignment: .firstTextBaseline) {
                Text(formattedName)
                    .font(DesignTokens.Fonts.custom(size: 15, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                if decisive > 0 {
                    Text(hitRatePercentText)
                        .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundColor(hitRateColor)
                } else {
                    Text("—")
                        .font(DesignTokens.Fonts.custom(size: 15))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
            }

            if decisive > 0 {
                // Progress bar
                ProgressView(value: stat.hitRate)
                    .tint(hitRateColor)
                    .scaleEffect(x: 1, y: 0.8, anchor: .center)

                // Alt: detay sayılar + PnL katkısı
                HStack(alignment: .center) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        countTag(value: stat.correctVotes,
                                 label: "doğru",
                                 color: DesignTokens.Colors.success)
                        countTag(value: stat.incorrectVotes,
                                 label: "yanlış",
                                 color: DesignTokens.Colors.error)
                        countTag(value: stat.holdVotes,
                                 label: "tut",
                                 color: DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    Text(pnlContributionText)
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(stat.totalPnLContribution >= 0
                                         ? DesignTokens.Colors.success
                                         : DesignTokens.Colors.error)
                }
            } else {
                // Veri yok — sade hint
                HStack(spacing: DesignTokens.Spacing.s6) {
                    Image(systemName: "clock")
                        .font(DesignTokens.Fonts.custom(size: 11))
                    Text("Henüz decisive oy yok")
                        .font(DesignTokens.Fonts.custom(size: 12))
                }
                .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.s14)
    }

    // MARK: - Helpers

    private func countTag(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text("\(value)")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - Computed

    private var rawName: String {
        KararKartiViewModel.displayName(forModule: stat.module)
    }

    /// UI sözleşmesi: mitolojik isimler (Orion, Atlas, Aether...) UI'da
    /// gösterilmez — sadece Türkçe karşılığı (Teknik, Bilanço, Makro...).
    /// `displayName(forModule:)` "Orion teknik" gibi iki-kelime döner;
    /// ilk kelime mitolojik, kalan kısım Türkçe — bunu izole edip
    /// capitalize ederek gösteririz.
    private var formattedName: String {
        let parts = rawName.split(separator: " ", maxSplits: 1).map(String.init)
        let turkish = parts.count == 2 ? parts[1] : parts[0]
        guard let first = turkish.first else { return turkish }
        return first.uppercased() + turkish.dropFirst()
    }

    private var decisive: Int {
        stat.correctVotes + stat.incorrectVotes
    }

    private var hitRatePercentText: String {
        "%\(Int((stat.hitRate * 100).rounded()))"
    }

    private var hitRateColor: Color {
        if stat.hitRate >= 0.55 { return DesignTokens.Colors.success }
        if stat.hitRate >= 0.45 { return DesignTokens.Colors.warning }
        return DesignTokens.Colors.error
    }

    private var pnlContributionText: String {
        let sign = stat.totalPnLContribution >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", stat.totalPnLContribution))"
    }
}

#Preview {
    ModulKarneView()
}
