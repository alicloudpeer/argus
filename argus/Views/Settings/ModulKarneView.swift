import SwiftUI

/// Faz 1.C: Settings → Modül Karnesi ekranı.
///
/// `ModulePerformanceTracker.getAllStats()` verisini görselleştirir — her
/// modülün (Orion, Atlas, Aether, ...) decisive oy sayısı, hit rate'i ve
/// PnL katkısı tek bakışta görünür. Hit rate renk-kodlu:
/// - ≥ %55 yeşil (kazanan modül)
/// - %45 – %55 sarı (kararsız)
/// - < %45 kırmızı (kaybeden modül — gelecekte auto-disable adayı)
///
/// Mevcut Settings akışına dokunulmadan eklendi. ModulePerformanceTracker
/// state'ini okur, yazmaz.
struct ModulKarneView: View {
    @State private var stats: [ModulePerformanceTracker.ModuleStats] = []
    @State private var isLoading: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanation
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if stats.isEmpty {
                    emptyState
                } else {
                    moduleList
                }
            }
            .padding()
        }
        .task {
            await load()
        }
    }

    // MARK: - Sections

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODÜL KARNESİ")
                .font(.caption.smallCaps())
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            Text("Her modülün decisive (al/sat) oyları arasında ne kadarı doğru çıktı.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .imageScale(.large)
                .foregroundColor(.secondary)
            Text("Henüz veri yok")
                .font(.callout)
            Text("Trade'ler kapandıkça modül başına karne dolacak.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var moduleList: some View {
        VStack(spacing: 12) {
            ForEach(stats, id: \.module) { stat in
                ModulKarneRow(stat: stat)
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
        VStack(alignment: .leading, spacing: 10) {
            // Üst: modül adı + hit rate yüzde
            HStack {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text(hitRatePercentText)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(hitRateColor)
            }

            // Orta: progress bar (hit rate görsel)
            ProgressView(value: stat.hitRate)
                .tint(hitRateColor)

            // Alt: detay sayılar
            HStack(spacing: 12) {
                statTag(label: "doğru", value: "\(stat.correctVotes)", color: .green)
                statTag(label: "yanlış", value: "\(stat.incorrectVotes)", color: .red)
                statTag(label: "tut", value: "\(stat.holdVotes)", color: .gray)
                Spacer()
                Text(pnlContributionText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(stat.totalPnLContribution >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statTag(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Computed

    private var displayName: String {
        KararKartiViewModel.displayName(forModule: stat.module)
    }

    private var decisive: Int {
        stat.correctVotes + stat.incorrectVotes
    }

    private var hitRatePercentText: String {
        guard decisive > 0 else { return "—" }
        return "%\(Int((stat.hitRate * 100).rounded()))"
    }

    private var hitRateColor: Color {
        guard decisive > 0 else { return .secondary }
        if stat.hitRate >= 0.55 { return .green }
        if stat.hitRate >= 0.45 { return .orange }
        return .red
    }

    private var pnlContributionText: String {
        let sign = stat.totalPnLContribution >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", stat.totalPnLContribution))"
    }
}

#Preview {
    ModulKarneView()
}
