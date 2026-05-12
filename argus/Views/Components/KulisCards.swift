import SwiftUI

// MARK: - Piyasa Duygu Barometresi Kartı
//
// 2026-05-04 H-62 sade refactor:
//   • MotorLogo(.hermes) + caps "PİYASA DUYGU BAROMETRESİ" caption + mono
//     "Haber · Algı Analizi" subtitle gitti
//   • Sentiment hero kartında "DUYGU"/"SKOR" caps mono + 24pt black mono
//     skor + tone background dolgusu temizlendi (sade flat)
//   • "KORKU/NÖTR/AÇGÖZLÜLÜK" caps mono → sentence
//   • Hermes motor tint border + pointer fill → hairline + sade dot
//   • "BAROMETRE OKUNUYOR…" caps mono → "Yükleniyor"

struct DuyguBarometresiCard: View {
    let symbol: String

    @State private var sentimentScore: Double = 0 // -100..+100
    @State private var sentimentLabel: String = "Nötr"
    @State private var isLoading = true
    @State private var showEducation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                loadingBlock
            } else {
                sentimentHero
                spectrumBar
            }

            if showEducation {
                EducationRow(
                    text: "Duygu barometresi haber tonunu ve piyasa algısını ölçer. Aşırı açgözlülük genelde tepe sinyalidir (herkes iyimser olunca dikkatli olunmalı), aşırı korku ise fırsat olabilir (piyasa aşırı satılmış olabilir)."
                )
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
        .task { await loadSentiment() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duygu barometresi")
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Text("Haber, algı analizi")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            EducationToggle(isOn: $showEducation)
        }
    }

    private var sentimentHero: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Duygu")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(sentimentLabel)
                    .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                    .foregroundColor(tone.foreground)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Skor")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text(sentimentScore >= 0
                     ? "+\(Int(sentimentScore))"
                     : "\(Int(sentimentScore))")
                    .font(DesignTokens.Fonts.custom(size: 24, weight: .medium))
                    .foregroundColor(tone.foreground)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    private var spectrumBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Korku")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.crimson)
                Spacer()
                Text("Nötr")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Spacer()
                Text("Açgözlülük")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.aurora)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    InstitutionalTheme.Colors.crimson,
                                    InstitutionalTheme.Colors.titan,
                                    InstitutionalTheme.Colors.aurora
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)

                    // Sade pointer — surface halka, textPrimary dolgu
                    let clampedPos = max(0, min(1, (sentimentScore + 100) / 200))
                    Circle()
                        .strokeBorder(DesignTokens.Colors.surface, lineWidth: 2)
                        .background(
                            Circle().fill(DesignTokens.Colors.textPrimary)
                        )
                        .frame(width: 12, height: 12)
                        .offset(x: geo.size.width * clampedPos - 6)
                        .animation(.easeOut(duration: 0.4), value: sentimentScore)
                }
            }
            .frame(height: 12)
        }
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Yükleniyor")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Helpers

    private var tone: ArgusChipTone {
        if sentimentScore >= 30 { return .aurora }
        if sentimentScore <= -30 { return .crimson }
        return .titan
    }

    private func loadSentiment() async {
        if let payload = try? await BISTSentimentEngine.shared.analyzeSentimentPayload(for: symbol) {
            let score = payload.result.overallScore
            let normalized = (score - 50) * 2

            let label: String
            if normalized >= 50 { label = "Çok Olumlu" }
            else if normalized >= 15 { label = "Olumlu" }
            else if normalized >= -15 { label = "Nötr" }
            else if normalized >= -50 { label = "Olumsuz" }
            else { label = "Çok Olumsuz" }

            await MainActor.run {
                self.sentimentScore = normalized
                self.sentimentLabel = label
                self.isLoading = false
            }
        } else {
            await MainActor.run {
                self.sentimentScore = 0
                self.sentimentLabel = "Veri Yok"
                self.isLoading = false
            }
        }
    }
}

// MARK: - Analist Eğitim Wrapper (V5)

struct AnalistEgitimWrapper: View {
    let symbol: String
    @State private var showEducation = false

    var body: some View {
        EducationShell(
            showEducation: $showEducation,
            content: { BistAnalystCard(symbol: symbol) },
            note: "Analist konsensüsü, profesyonel yatırımcıların ortalama beklentisini gösterir. Hedef fiyat, analistlerin 12 aylık tahminidir. Tek başına yeterli olmaz, diğer modüllerle birlikte değerlendirilmelidir."
        )
    }
}

// MARK: - KAP Eğitim Wrapper (V5)

struct KAPEgitimWrapper: View {
    let symbol: String
    @State private var showEducation = false

    var body: some View {
        EducationShell(
            showEducation: $showEducation,
            content: { KulisKAPCard(symbol: symbol) },
            note: "KAP bildirimleri şirketlerin yasal olarak açıklaması gereken önemli gelişmelerdir. Finansal tablolar, yönetim kurulu kararları, ortaklık yapısı değişiklikleri gibi bilgiler burada yayınlanır. Hızlı hareket eden bilgidir."
        )
    }
}

// MARK: - Temettü Eğitim Wrapper (V5)

struct TemettuEgitimWrapper: View {
    let symbol: String
    @State private var showEducation = false

    var body: some View {
        EducationShell(
            showEducation: $showEducation,
            content: { BistDividendCard(symbol: symbol) },
            note: "Temettü, şirketin kârından ortaklara dağıttığı paydır. Düzenli temettü ödeyen şirketler genelde daha güvenilir kabul edilir. Bedelsiz sermaye artırımı ise hisse adedini artırır ancak toplam değeri değiştirmez."
        )
    }
}

// MARK: - V5 Eğitim Shell
//
// "Ne Demek?" butonu + açılır titan tonlu eğitim notu. Artık orange
// lightbulb yerine ArgusChip, `💡` emoji yerine ArgusDot.

private struct EducationShell<Content: View>: View {
    @Binding var showEducation: Bool
    let content: () -> Content
    let note: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            content()

            EducationToggle(isOn: $showEducation)
                .padding(.top, 2)

            if showEducation {
                EducationRow(text: note)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct EducationToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "info.circle.fill" : "info.circle")
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .semibold))
                    .foregroundColor(InstitutionalTheme.Colors.titan)
                Text("NE DEMEK?")
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundColor(InstitutionalTheme.Colors.titan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(InstitutionalTheme.Colors.titan.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(InstitutionalTheme.Colors.titan.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EducationRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ArgusDot(color: InstitutionalTheme.Colors.titan)
                .padding(.top, 5)
            Text(text)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(InstitutionalTheme.Colors.titan.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
        )
    }
}
