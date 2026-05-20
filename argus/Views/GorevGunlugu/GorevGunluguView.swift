import SwiftUI

struct GorevGunluguView: View {
    @StateObject private var viewModel = GorevGunluguViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "G\u{00F6}rev G\u{00FC}nl\u{00FC}\u{011F}\u{00FC}",
                    subtitle: "Otopilot karar merkezi",
                    leadingDeco: .back(onTap: { dismiss() }),
                    titlePill: nil,
                    actions: [],
                    status: headerStatus
                )

                filtreBar
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(DesignTokens.Colors.textTertiary)
                    Spacer()
                } else if viewModel.anlatılar.isEmpty {
                    Spacer()
                    bosEkran
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(viewModel.anlatılar.enumerated()), id: \.offset) { _, anlatim in
                                GorevKartiView(anlatim: anlatim)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header Status

    private var headerStatus: ArgusNavHeader.Status {
        let o = viewModel.ozet
        if o.toplamKarar == 0 {
            return .custom(
                dotColor: DesignTokens.Colors.textTertiary,
                label: "Kay\u{0131}t yok",
                trailing: ""
            )
        }
        var parcalar: [String] = []
        if o.alimSayisi > 0   { parcalar.append("\(o.alimSayisi) al\u{0131}m") }
        if o.satimSayisi > 0  { parcalar.append("\(o.satimSayisi) sat\u{0131}m") }
        if o.pasSayisi > 0    { parcalar.append("\(o.pasSayisi) pas") }
        if o.engelSayisi > 0  { parcalar.append("\(o.engelSayisi) engel") }
        let ozet = parcalar.joined(separator: " \u{00B7} ")
        return .custom(
            dotColor: InstitutionalTheme.Colors.aurora,
            label: ozet,
            trailing: "\(o.toplamKarar) karar"
        )
    }

    // MARK: - Filtre Bar

    private var filtreBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GorevGunluguViewModel.Filtre.allCases) { filtre in
                    filtrePill(filtre)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filtrePill(_ filtre: GorevGunluguViewModel.Filtre) -> some View {
        let secili = viewModel.seciliFiltre == filtre
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.seciliFiltre = filtre
            }
        } label: {
            Text(filtre.rawValue)
                .font(DesignTokens.Fonts.custom(size: 13, weight: secili ? .semibold : .medium))
                .foregroundColor(
                    secili
                        ? DesignTokens.Colors.primary
                        : DesignTokens.Colors.textSecondary
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(secili ? DesignTokens.Colors.primary.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            secili
                                ? DesignTokens.Colors.primary.opacity(0.4)
                                : DesignTokens.Colors.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bos Ekran

    private var bosEkran: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DesignTokens.Colors.textTertiary)

            Text(bosEkranMesaji)
                .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)
        }
    }

    private var bosEkranMesaji: String {
        switch viewModel.seciliFiltre {
        case .tumKararlar:
            return "Hen\u{00FC}z kay\u{0131}tl\u{0131} karar yok.\nOtopilot \u{00E7}al\u{0131}\u{015F}t\u{0131}\u{011F}\u{0131}nda kararlar burada g\u{00F6}r\u{00FC}necek."
        case .alimlar:
            return "Hen\u{00FC}z al\u{0131}m karar\u{0131} yok."
        case .satimlar:
            return "Hen\u{00FC}z sat\u{0131}m karar\u{0131} yok."
        case .pasGecilenler:
            return "Pas ge\u{00E7}ilen karar yok."
        case .engellenenler:
            return "Engellenen karar yok."
        }
    }
}
