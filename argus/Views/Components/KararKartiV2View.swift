import SwiftUI

/// Faz 1.A.3: Karar Kartı V2 — şeffaf 4-bölümlü karar kartı.
///
/// Yol Haritası §3.8 uygulaması. Dört bölüm:
/// 1. **Ne öneriyor** (AksiyonOzetiSection) — Action + renk + pozisyon
/// 2. **Neden** (NedenSection) — Top 3 modül, mitolojik→Türkçe adlarla
/// 3. **Ne kadar emin** (GuvenSection) — Confidence + ModulePerformanceTracker
///    hit rate + düşük güven/AISignal rozetleri
/// 4. **Neyi unuttum** (RiskSection) — PremortemEngine 3 risk senaryosu
///
/// Mevcut `ArgusScientificDashboardCard` ve diğer karar UI'larına dokunmaz —
/// Settings → "Karar Kartı V2 Deneme" toggle'ı ile opt-in olarak görünür.
struct KararKartiV2View: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AksiyonOzetiSection(viewModel: viewModel)
                NedenSection(modules: viewModel.topModuller)
                GuvenSection(viewModel: viewModel)
                RiskSection(scenarios: viewModel.riskler)
            }
            .padding()
        }
    }
}

// MARK: - Bölüm 1: Ne öneriyor

struct AksiyonOzetiSection: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.aksiyonBaslik)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.aksiyonRengi)
                Spacer()
                Text(viewModel.pozisyonTahmin)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text("Argus'un önerdiği aksiyon ve tahmini pozisyon.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.aksiyonRengi.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aksiyon: \(viewModel.aksiyonBaslik), pozisyon \(viewModel.pozisyonTahmin)")
    }
}

// MARK: - Bölüm 2: Neden (top modüller)

struct NedenSection: View {
    let modules: [KararKartiViewModel.ModulSatir]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "NEDEN", subtitle: "Karara en çok katkı veren modüller")

            if modules.isEmpty {
                Text("Henüz modül oyu yok")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(modules) { modul in
                    ModulSatirRow(modul: modul)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct ModulSatirRow: View {
    let modul: KararKartiViewModel.ModulSatir

    var body: some View {
        HStack {
            Text(modul.displayName)
                .font(.body)
            Spacer()
            Text("\(modul.score)")
                .font(.body.monospacedDigit())
                .foregroundColor(.primary)
            Text("× \(String(format: "%.2f", modul.weight))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(modul.displayName), skor \(modul.score), ağırlık \(String(format: "%.2f", modul.weight))")
    }
}

// MARK: - Bölüm 3: Ne kadar emin

struct GuvenSection: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "NE KADAR EMİN", subtitle: "Güven yüzdesi ve geçmiş başarı")

            HStack {
                Text("%\(viewModel.confidencePercent)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                rozetler
            }

            ProgressView(value: Double(viewModel.confidencePercent) / 100.0)
                .progressViewStyle(.linear)
                .tint(viewModel.dusukGuvenRozeti ? .yellow : .blue)

            Text(viewModel.hitRateText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var rozetler: some View {
        HStack(spacing: 6) {
            if viewModel.dusukGuvenRozeti {
                RozetView(metin: "Düşük güven", renk: .yellow)
            }
            if viewModel.aiSignalRozeti {
                // Faz 1 Task 8 hijyen: AISignal in-sample backtest açıkça etiket.
                RozetView(metin: "In-sample", renk: .orange)
            }
        }
    }
}

private struct RozetView: View {
    let metin: String
    let renk: Color

    var body: some View {
        Text(metin)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(renk.opacity(0.18))
            )
            .foregroundColor(renk)
            .accessibilityLabel("Rozet: \(metin)")
    }
}

// MARK: - Bölüm 4: Neyi unuttum

struct RiskSection: View {
    let scenarios: [PremortemEngine.RiskScenario]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "NEYİ UNUTTUM", subtitle: "Bu kararın yanlış olabileceği senaryolar")

            ForEach(scenarios) { scenario in
                RiskSatirRow(scenario: scenario)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct RiskSatirRow: View {
    let scenario: PremortemEngine.RiskScenario

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ikonAdi(for: scenario.severity))
                .foregroundColor(renkSeverity(scenario.severity))
                .imageScale(.medium)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.trigger)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(renkSeverity(scenario.severity))
                Text(scenario.scenario)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func ikonAdi(for severity: PremortemEngine.RiskScenario.Severity) -> String {
        switch severity {
        case .low:    return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high:   return "exclamationmark.octagon.fill"
        }
    }

    private func renkSeverity(_ severity: PremortemEngine.RiskScenario.Severity) -> Color {
        switch severity {
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

// MARK: - Shared

private struct SectionTitle: View {
    let text: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.caption.smallCaps())
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Boş karar — fallback senaryolarla") {
    // Boş ViewModel: aksiyon GÖZLE, modüller boş, hit rate "veri yok".
    // Premortem fallback "Genel" senaryosu yine de görünür çünkü prepare çağrılmamış —
    // RiskSection boş array ile render eder; gerçek kullanımda prepare(...) sonrası
    // riskler array dolar. Preview UI iskeletini doğrular.
    KararKartiV2View(viewModel: KararKartiViewModel())
}
