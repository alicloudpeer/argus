import SwiftUI

struct GorevGunluguView: View {
    @StateObject private var viewModel = GorevGunluguViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "Görev Günlüğü",
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
                            ForEach(viewModel.anlatılar) { anlatim in
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
                label: "Kayıt yok",
                trailing: ""
            )
        }
        var parcalar: [String] = []
        if o.alimSayisi > 0   { parcalar.append("\(o.alimSayisi) alım") }
        if o.satimSayisi > 0  { parcalar.append("\(o.satimSayisi) satım") }
        if o.pasSayisi > 0    { parcalar.append("\(o.pasSayisi) pas") }
        if o.engelSayisi > 0  { parcalar.append("\(o.engelSayisi) engel") }
        let ozet = parcalar.joined(separator: " · ")
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
            return "Henüz kayıtlı karar yok.\nOtopilot çalıştığında kararlar burada görünecek."
        case .alimlar:
            return "Henüz alım kararı yok."
        case .satimlar:
            return "Henüz satım kararı yok."
        case .pasGecilenler:
            return "Pas geçilen karar yok."
        case .engellenenler:
            return "Engellenen karar yok."
        }
    }
}
