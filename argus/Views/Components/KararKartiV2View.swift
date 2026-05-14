import SwiftUI

/// Faz 1.A.3: Karar Kartı V2 — 4-bölümlü şeffaf karar önizlemesi.
///
/// 2026-05-14: Sade V5 yeniden yazımı.
/// Eski: .smallCaps() heavy CAPS başlıklar, `viewModel.aksiyonRengi.opacity(0.08)`
/// kart background, `Color(.secondarySystemBackground)`, mitolojik isim ve
/// `× weight` çarpan gösterimi, sarı/turuncu icon spam'i (risk severity için
/// .blue/.orange/.red), `.tint(.yellow)` ProgressView — AI-tell sinyalleri ile
/// dolu, tasarım sistemi 0 kullanılıyordu.
/// Yeni: MarketView "yağ gibi" dili — kart yok, ayraçlı 4 bölüm, sentence case,
/// mitolojik isim YOK (sadece Türkçe karşılık), çarpan YOK, risk severity için
/// text tonu hiyerarşisi (renksiz), DesignTokens semantik renkler.
///
/// ArgusSanctumView'daki render kaldırıldı; view artık yalnızca
/// Settings → Deneysel → "Karar Kartı V2 önizleme" üzerinden erişilebilir
/// önizleme olarak çalışır.
struct KararKartiV2View: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AksiyonOzetiSection(viewModel: viewModel)
                ayrac
                NedenSection(modules: viewModel.topModuller)
                ayrac
                GuvenSection(viewModel: viewModel)
                ayrac
                RiskSection(scenarios: viewModel.riskler)
            }
            .padding(.horizontal, DesignTokens.Spacing.s18)
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
    }

    private var ayrac: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: DesignTokens.BorderWidth.hairline)
    }
}

// MARK: - Bölüm 1: Ne öneriyor

struct AksiyonOzetiSection: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(aksiyonText)
                    .font(DesignTokens.Fonts.custom(size: 28, weight: .medium))
                    .foregroundColor(aksiyonRengi)
                Spacer()
                Text(viewModel.pozisyonTahmin)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            Text("Argus'un önerdiği aksiyon ve tahmini pozisyon")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .padding(.vertical, DesignTokens.Spacing.s18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aksiyon: \(aksiyonText), pozisyon \(viewModel.pozisyonTahmin)")
    }

    /// "AL"/"SAT"/"TUT"/"GÖZLE" → sentence case
    private var aksiyonText: String {
        let raw = viewModel.aksiyonBaslik
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst().lowercased()
    }

    /// Renk semantiği View tarafında — ViewModel'in `.green/.gray` gibi sistem
    /// rengine bağımlılığı yerine DesignTokens üzerinden çözülür.
    private var aksiyonRengi: Color {
        switch viewModel.aksiyonBaslik.lowercased() {
        case "al":   return DesignTokens.Colors.success
        case "sat":  return DesignTokens.Colors.error
        default:     return DesignTokens.Colors.textTertiary
        }
    }
}

// MARK: - Bölüm 2: Neden (top modüller — çarpan YOK)

struct NedenSection: View {
    let modules: [KararKartiViewModel.ModulSatir]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SectionTitle(text: "Neden",
                         subtitle: "Karara en çok katkı veren modüller")

            if modules.isEmpty {
                Text("Henüz modül oyu yok")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .padding(.top, DesignTokens.Spacing.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(modules) { modul in
                        ModulSatirRow(modul: modul)
                    }
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }
}

private struct ModulSatirRow: View {
    let modul: KararKartiViewModel.ModulSatir

    var body: some View {
        HStack {
            Text(turkishName)
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text("\(modul.score)")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
        .padding(.vertical, DesignTokens.Spacing.s6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(turkishName), skor \(modul.score)")
    }

    /// UI sözleşmesi: mitolojik isimler (Orion, Atlas, Aether...) gösterilmez —
    /// sadece Türkçe karşılığı (Teknik, Bilanço, Makro...). `displayName`
    /// "Orion teknik" gibi iki kelime döner; ilk kelime mitolojik, kalan kısım
    /// Türkçe — bunu izole edip capitalize ederek gösteririz.
    private var turkishName: String {
        let parts = modul.displayName.split(separator: " ", maxSplits: 1).map(String.init)
        let tr = parts.count == 2 ? parts[1] : parts[0]
        guard let first = tr.first else { return tr }
        return first.uppercased() + tr.dropFirst()
    }
}

// MARK: - Bölüm 3: Ne kadar emin

struct GuvenSection: View {
    @ObservedObject var viewModel: KararKartiViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SectionTitle(text: "Ne kadar emin",
                         subtitle: "Güven yüzdesi ve geçmiş başarı")

            HStack(alignment: .center) {
                Text("%\(viewModel.confidencePercent)")
                    .font(DesignTokens.Fonts.custom(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                rozetler
            }
            .padding(.top, DesignTokens.Spacing.xs)

            // Progress — nötr çizgi, renk vurgu yok
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.Colors.Overlay.l06)
                        .frame(height: 2)
                    Capsule()
                        .fill(DesignTokens.Colors.Overlay.l40)
                        .frame(width: geo.size.width * progressRatio, height: 2)
                }
            }
            .frame(height: 2)
            .padding(.top, DesignTokens.Spacing.s6)

            Text(viewModel.hitRateText)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.top, DesignTokens.Spacing.s6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private var progressRatio: CGFloat {
        CGFloat(max(0, min(100, viewModel.confidencePercent))) / 100.0
    }

    @ViewBuilder
    private var rozetler: some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            if viewModel.dusukGuvenRozeti {
                RozetView(metin: "Düşük güven")
            }
            if viewModel.aiSignalRozeti {
                // Faz 1 Task 8 hijyen: AISignal in-sample backtest etiketi.
                RozetView(metin: "In-sample")
            }
        }
    }
}

/// Sade outline pill — renk vurgu yok, sadece border + textSecondary.
/// (Eski: yellow/orange .opacity(0.18) background ile renk vurgusu vardı.)
private struct RozetView: View {
    let metin: String

    var body: some View {
        Text(metin)
            .font(DesignTokens.Fonts.custom(size: 11))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .overlay(
                Capsule()
                    .stroke(DesignTokens.Colors.border,
                            lineWidth: DesignTokens.BorderWidth.hairline)
            )
            .accessibilityLabel("Rozet: \(metin)")
    }
}

// MARK: - Bölüm 4: Neyi unuttum

struct RiskSection: View {
    let scenarios: [PremortemEngine.RiskScenario]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SectionTitle(text: "Neyi unuttum",
                         subtitle: "Bu kararın yanlış olabileceği senaryolar")

            if scenarios.isEmpty {
                Text("Senaryo üretilmedi")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .padding(.top, DesignTokens.Spacing.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(scenarios) { scenario in
                        RiskSatirRow(scenario: scenario)
                    }
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }
}

private struct RiskSatirRow: View {
    let scenario: PremortemEngine.RiskScenario

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s10) {
            // Severity için 2pt dikey bar — renk değil, text tonu üzerinden
            // hiyerarşi. Yüksek risk parlak, düşük risk soluk.
            Capsule()
                .fill(severityColor)
                .frame(width: 2, height: 18)
                .padding(.top, DesignTokens.Spacing.xs)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(scenario.trigger)
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(severityColor)
                Text(scenario.scenario)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.s10)
        .accessibilityElement(children: .combine)
    }

    /// Severity için text tonu hiyerarşisi — renk yerine parlaklık.
    /// (Eski: .blue/.orange/.red icon + foreground renkleri AI-tell idi.)
    private var severityColor: Color {
        switch scenario.severity {
        case .high:   return DesignTokens.Colors.textPrimary
        case .medium: return DesignTokens.Colors.textSecondary
        case .low:    return DesignTokens.Colors.textTertiary
        }
    }
}

// MARK: - Shared

/// Sade section başlığı — eski `.caption.smallCaps().bold()` heavy CAPS gitti,
/// sentence case + textTertiary.
private struct SectionTitle: View {
    let text: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(text)
                .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(subtitle)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
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
