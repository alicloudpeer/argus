import SwiftUI

// MARK: - Stock Detail Module Sheets (V5)
//
// **2026-04-23 Hotfix.** Hisse detayındaki motor chip grid'inde
// Prometheus / Alkindus / Demeter chip'lerinin yanlış sheet açtığı bug'ı
// fix ettik. Bu dosya 3 yeni sheet için ortak chrome + yardımcı view'ları
// barındırır:
//   • `ModuleSheetShell` — ArgusNavHeader + dismiss + scroll sarmal.
//   • `ModulePlaceholderSheet` — fallback (advice yok, veri yok) için
//     bilgilendirici boş hal. Artık bomboş gri sheet yok.
//   • `ModulePlaceholderBody` — shell içinde kullanılan gövde.
//   • `DemeterSectorCard` — Demeter sektör skoru panel kartı; data
//     sözleşmesi HoloPanel'deki `.demeter` case'iyle aynı.

// MARK: - Module Sheet Shell

struct ModuleSheetShell<Content: View>: View {
    let title: String
    let motor: MotorEngine
    let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(title: String,
         motor: MotorEngine,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.motor = motor
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ArgusNavHeader(
                title: title,
                subtitle: "Modül detayı",
                leadingDeco: .bars3([.holo, .text, .text]),
                actions: [
                    .custom(sfSymbol: "xmark", action: { dismiss() })
                ]
            )

            ScrollView {
                VStack(spacing: 14) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Module Placeholder Sheet

struct ModulePlaceholderSheet: View {
    let title: String
    let subtitle: String
    let message: String
    let motor: MotorEngine

    var body: some View {
        ModuleSheetShell(title: title, motor: motor) {
            ModulePlaceholderBody(message: message, motor: motor)
        }
    }
}

struct ModulePlaceholderBody: View {
    let message: String
    let motor: MotorEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MotorLogo(motor, size: 18)
                ArgusSectionCaption("VERİ BEKLENİYOR")
                Spacer()
                ArgusChip("PASİF", tone: .titan)
            }

            HStack(alignment: .top, spacing: 10) {
                ArgusDot(color: InstitutionalTheme.Colors.titan)
                    .padding(.top, 5)
                Text(message)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg,
                             style: .continuous)
                .stroke(InstitutionalTheme.Colors.Motors.color(for: motor).opacity(0.3),
                        lineWidth: 1)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg,
                             style: .continuous)
        )
    }
}
