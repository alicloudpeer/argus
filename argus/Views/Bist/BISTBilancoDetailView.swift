import SwiftUI

// MARK: - BISTBilancoDetailView (BIST Bilanço)
//
// 2026-05-05 H-66 — sıfırdan yeniden yazıldı.
//
// Eski yapı (>980 satır): ArgusNavHeader caps subtitle "KASA · BIST
// TEMEL ANALİZ", titlePill .atlas, 80pt circular ring + qualityBand
// hero, ArgusDot/Chip/SectionCaption "POZİTİF SİNYALLER / KRİTİK
// NOTLAR", expandable bölüm kartları progress bar + chevron, atlas
// motor tinted border'lar, value alert tinted block'lar.
//
// Yeni yapı: AtlasV2DetailView (Global Bilanço) ile aynı iOS Settings
// hub dilinde. Şirket meta + durum cümlesi + Pozitif/Kritik link grup
// + 3 boyut grubu (Temel/Genişleme/Ek) + boyut detay sub-page +
// pozitif/kritik sub-page'i (paylaşılan BilancoSinyalView).
//
// Public API korundu: `init(sembol:)`.

struct BISTBilancoDetailView: View {
    let sembol: String

    @State private var sonuc: BISTBilancoSonuc?
    @State private var yukleniyor = true
    @State private var hata: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                inlineTopNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if yukleniyor {
                            loadingState
                        } else if let h = hata {
                            errorState(h)
                        } else if let s = sonuc {
                            companyMeta(s)
                            statusParagraph(s)
                            signalsGroup(s)
                            boyutlarTemel(s)
                            boyutlarGenisleme(s)
                            boyutlarEk(s)
                            footerNote
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await veriYukle()
        }
    }

    // MARK: - Üst nav

    private var inlineTopNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Geri")

            Text(sembol.replacingOccurrences(of: ".IS", with: ""))
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("Bilanço yükleniyor…")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bilanço alınamadı")
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text(msg)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 22)
    }

    // MARK: - Şirket meta

    private func companyMeta(_ s: BISTBilancoSonuc) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.profil.isim)
                .font(DesignTokens.Fonts.custom(size: 18, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Text(s.sembol.replacingOccurrences(of: ".IS", with: ""))
                    .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                if let sektor = s.profil.sektor, !sektor.isEmpty {
                    Text(" · \(sektor)")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                Text(" · \(s.profil.formatliPiyasaDegeri)")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Durum cümlesi

    private func statusParagraph(_ s: BISTBilancoSonuc) -> some View {
        Text(s.ozet)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    // MARK: - Pozitif / Kritik link grubu

    @ViewBuilder
    private func signalsGroup(_ s: BISTBilancoSonuc) -> some View {
        if !s.oneCikanlar.isEmpty || !s.uyarilar.isEmpty {
            VStack(spacing: 0) {
                if !s.oneCikanlar.isEmpty {
                    NavigationLink(destination: BilancoSinyalView(
                        title: "Pozitif sinyaller",
                        items: s.oneCikanlar,
                        tone: .aurora
                    )) {
                        signalRow(title: "Pozitif sinyaller",
                                  count: s.oneCikanlar.count,
                                  color: InstitutionalTheme.Colors.aurora)
                    }
                    .buttonStyle(.plain)
                    if !s.uyarilar.isEmpty {
                        divider
                    }
                }
                if !s.uyarilar.isEmpty {
                    NavigationLink(destination: BilancoSinyalView(
                        title: "Kritik notlar",
                        items: s.uyarilar,
                        tone: .crimson
                    )) {
                        signalRow(title: "Kritik notlar",
                                  count: s.uyarilar.count,
                                  color: InstitutionalTheme.Colors.crimson)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 18)
        }
    }

    private func signalRow(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 15))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Text("\(count)")
                .font(DesignTokens.Fonts.custom(size: 14))
                .foregroundColor(color)
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    // MARK: - Boyut grupları

    private func boyutlarTemel(_ s: BISTBilancoSonuc) -> some View {
        boyutGroup(
            title: "Temel",
            rows: [
                BoyutRow(title: "Değerleme", sub: "F/K · PD/DD · FD/FAVÖK",
                         score: s.degerleme, metrikler: s.degerlemeVerisi.tumMetrikler),
                BoyutRow(title: "Karlılık", sub: "ROE · ROA · marjlar",
                         score: s.karlilik, metrikler: s.karlilikVerisi.tumMetrikler),
                BoyutRow(title: "Sağlık", sub: "Borç/özkaynak · cari oran",
                         score: s.saglik, metrikler: s.saglikVerisi.tumMetrikler)
            ]
        )
    }

    private func boyutlarGenisleme(_ s: BISTBilancoSonuc) -> some View {
        boyutGroup(
            title: "Genişleme",
            rows: [
                BoyutRow(title: "Büyüme", sub: "Gelir · net kâr · FAVÖK",
                         score: s.buyume, metrikler: s.buyumeVerisi.tumMetrikler),
                BoyutRow(title: "Nakit kalitesi", sub: "Serbest nakit · nakit pozisyonu",
                         score: s.nakit, metrikler: s.nakitVerisi.tumMetrikler)
            ]
        )
    }

    private func boyutlarEk(_ s: BISTBilancoSonuc) -> some View {
        boyutGroup(
            title: "Ek",
            rows: [
                BoyutRow(title: "Temettü", sub: "Verim · dağıtım · büyüme",
                         score: s.temettu, metrikler: s.temettuVerisi.tumMetrikler),
                BoyutRow(title: "Risk", sub: "Beta · korelasyon · volatilite",
                         score: riskScore(s), metrikler: s.riskVerisi.tumMetrikler)
            ]
        )
    }

    /// Risk skoru BISTBilancoSonuc'ta direkt yok; metric'lerin
    /// ortalaması alınır (AtlasV2 ile aynı pattern).
    private func riskScore(_ s: BISTBilancoSonuc) -> Double {
        let metrikler = s.riskVerisi.tumMetrikler
        guard !metrikler.isEmpty else { return 50 }
        let sum = metrikler.reduce(0.0) { $0 + $1.skor }
        return sum / Double(metrikler.count)
    }

    private struct BoyutRow {
        let title: String
        let sub: String
        let score: Double
        let metrikler: [BISTMetrik]
    }

    private func boyutGroup(title: String, rows: [BoyutRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    NavigationLink(destination: BistBilancoBoyutView(
                        title: row.title,
                        score: row.score,
                        metrikler: row.metrikler
                    )) {
                        boyutRowView(row)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        divider
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 18)
    }

    private func boyutRowView(_ row: BoyutRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DesignTokens.Fonts.custom(size: 15))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(row.sub)
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Text("\(Int(row.score))")
                .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                .foregroundColor(scoreColor(row.score))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Skor 7 boyutun ağırlıklı ortalamasıdır. Veriler son finansal raporlardan ve BorsaPy'den çekilir.")
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Data Loading

    private func veriYukle() async {
        do {
            let analiz = try await BISTBilancoEngine.shared.analiz(sembol: sembol)
            await MainActor.run {
                self.sonuc = analiz
                self.yukleniyor = false
            }
        } catch {
            await MainActor.run {
                self.hata = error.localizedDescription
                self.yukleniyor = false
            }
        }
    }
}

// MARK: - BistBilancoBoyutView (BIST Boyut detay sub-page)
//
// AtlasV2 tarafındaki BilancoBoyutView ile aynı dilde, ama BISTMetrik
// tipi kullanır. Üstte bağlam cümlesi (en yüksek skorlu metric'in
// açıklaması), sonra metric listesi, sonra değerlendirme.

struct BistBilancoBoyutView: View {
    let title: String
    let score: Double
    let metrikler: [BISTMetrik]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let lead = leadingMetric {
                            statusParagraph(lead)
                        }
                        metricsGroup
                        evaluationGroup
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var topNav: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(title)
                .font(DesignTokens.Fonts.custom(size: 17, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var leadingMetric: BISTMetrik? {
        metrikler.max(by: { $0.skor < $1.skor })
    }

    private func statusParagraph(_ m: BISTMetrik) -> some View {
        Text(m.aciklama)
            .font(DesignTokens.Fonts.custom(size: 14))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }

    private var metricsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrikler")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(metrikler.enumerated()), id: \.offset) { idx, m in
                    metricRow(m)
                    if idx < metrikler.count - 1 {
                        Rectangle()
                            .fill(DesignTokens.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 18)
    }

    private func metricRow(_ m: BISTMetrik) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.isim)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                if let sektorAvg = m.sektorOrtalamasi {
                    Text("Sektör ortalaması \(BISTMetrik.formatla(sektorAvg))")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                } else if !m.aciklama.isEmpty {
                    Text(m.aciklama)
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(m.formatliDeger)
                .font(DesignTokens.Fonts.custom(size: 14, design: .monospaced))
                .foregroundColor(metricValueColor(m.durum))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func metricValueColor(_ durum: BISTMetrikDurum) -> Color {
        switch durum {
        case .mukemmel, .iyi:    return InstitutionalTheme.Colors.aurora
        case .notr:              return DesignTokens.Colors.textSecondary
        case .dikkat:            return InstitutionalTheme.Colors.titan
        case .kotu, .kritik:     return InstitutionalTheme.Colors.crimson
        case .veriYok:           return DesignTokens.Colors.textTertiary
        }
    }

    private var evaluationGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Değerlendirme")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textTertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                HStack {
                    Text("Özet skor")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text("\(Int(score)) / 100")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(scoreColor(score))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                Text(summarySentence)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var summarySentence: String {
        if score >= 70 { return "Bu boyutta sektör üstü bir performans var." }
        if score >= 50 { return "Bu boyutta orta seviye, sektör ortalamasına yakın." }
        return "Bu boyut zayıf, dikkatle izlenmesi gereken alan."
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 70 { return InstitutionalTheme.Colors.aurora }
        if value >= 50 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }
}
