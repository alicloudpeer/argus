import SwiftUI

// MARK: - APIKeyEditSheet
//
// APIKeyCenterView listesindeki satıra tıklanınca açılan sade bottom sheet.
// Tek input + Kaydet/Test butonları + sonuç satırı + opsiyonel "Anahtar al" linki.

struct APIKeyEditSheet: View {
    let entry: APIKeyCenterView.KeyEntry
    let initialValue: String
    let onSaved: (String) -> Void
    let onCleared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draft: String = ""
    @State private var revealed: Bool = false
    @State private var testing: Bool = false
    @State private var testResult: TestResult?

    private struct TestResult {
        let success: Bool
        let message: String
    }

    private var isDirty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != initialValue
    }

    private var hasValue: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isStoredConfigured: Bool {
        !initialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            draft = initialValue
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s10) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.title)
                    .font(DesignTokens.Fonts.custom(size: 18, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(entry.subtitle)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.s10)
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {

            // Field label + durum
            HStack {
                Text("API anahtarı")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(isStoredConfigured ? "Tanımlı" : "Eksik")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(isStoredConfigured
                                     ? DesignTokens.Colors.success
                                     : DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            // Input
            inputField
                .padding(.horizontal, DesignTokens.Spacing.lg)

            // Test sonucu (varsa)
            if let result = testResult {
                resultRow(result)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // Aksiyon butonları
            actionButtons
                .padding(.horizontal, DesignTokens.Spacing.lg)

            // Footer link / sil
            footerLinks
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.sm)
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    // MARK: - Input

    private var inputField: some View {
        HStack(spacing: DesignTokens.Spacing.s10) {
            Group {
                if revealed {
                    TextField(entry.placeholder, text: $draft)
                } else {
                    SecureField(entry.placeholder, text: $draft)
                }
            }
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
            .foregroundColor(DesignTokens.Colors.textPrimary)

            if hasValue {
                Button(action: { revealed.toggle() }) {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(DesignTokens.Fonts.custom(size: 14))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Gizle" : "Göster")
            } else {
                Button(action: paste) {
                    Text("Yapıştır")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.s11)
        .background(DesignTokens.Colors.Overlay.l03)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
        )
        .cornerRadius(DesignTokens.Radius.r10)
    }

    // MARK: - Result row

    private func resultRow(_ result: TestResult) -> some View {
        HStack(spacing: DesignTokens.Spacing.s6) {
            Image(systemName: result.success ? "checkmark.circle" : "exclamationmark.circle")
                .font(DesignTokens.Fonts.custom(size: 14))
            Text(result.message)
                .font(DesignTokens.Fonts.custom(size: 13))
                .lineLimit(2)
        }
        .foregroundColor(result.success
                         ? DesignTokens.Colors.success
                         : DesignTokens.Colors.error)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(action: save) {
                Text("Kaydet")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.s11)
                    .background(
                        isDirty && hasValue
                        ? DesignTokens.Colors.primary
                        : DesignTokens.Colors.Overlay.l05
                    )
                    .cornerRadius(DesignTokens.Radius.r10)
            }
            .buttonStyle(.plain)
            .disabled(!isDirty || !hasValue)

            Button(action: runTest) {
                HStack(spacing: DesignTokens.Spacing.s6) {
                    if testing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Test et")
                            .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    }
                }
                .foregroundColor(hasValue
                                 ? DesignTokens.Colors.textPrimary
                                 : DesignTokens.Colors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s11)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.r10)
                        .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasValue || testing)
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if let url = entry.signUpURL, !isStoredConfigured {
                Button(action: { openURL(url) }) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text("Sağlayıcıdan anahtar al")
                            .font(DesignTokens.Fonts.custom(size: 13))
                        Image(systemName: "arrow.up.right")
                            .font(DesignTokens.Fonts.custom(size: 11))
                    }
                    .foregroundColor(DesignTokens.Colors.primary)
                }
                .buttonStyle(.plain)
            }

            if isStoredConfigured {
                Button(action: clear) {
                    Text("Anahtarı sil")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.error)
                }
                .buttonStyle(.plain)
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func paste() {
        #if canImport(UIKit)
        if let s = UIPasteboard.general.string {
            draft = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch entry.source {
        case .provider(let provider):
            APIKeyStore.shared.setKey(provider: provider, key: value)
        case .customKey(let storeID):
            APIKeyStore.shared.setCustomValue(value, for: storeID)
        }
        testResult = nil
        onSaved(value)
        dismiss()
    }

    private func clear() {
        switch entry.source {
        case .provider(let provider):
            APIKeyStore.shared.deleteKey(provider: provider)
        case .customKey(let storeID):
            APIKeyStore.shared.deleteCustomValue(for: storeID)
        }
        draft = ""
        testResult = nil
        onCleared()
        dismiss()
    }

    private func runTest() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        testing = true
        testResult = nil

        Task {
            let result: TestResult
            switch entry.testMode {
            case .provider(let provider):
                let r = await APIKeyVerifier.verify(provider: provider, key: key)
                result = TestResult(success: r.isValid, message: r.message)
            case .tcmb:
                await TCMBDataService.shared.setAPIKey(key)
                let success = await TCMBDataService.shared.testConnection()
                result = TestResult(
                    success: success,
                    message: success ? "TCMB bağlantısı başarılı." : "TCMB bağlantısı başarısız."
                )
            case .unsupported:
                result = TestResult(
                    success: false,
                    message: "Bu sağlayıcı için otomatik test yok."
                )
            }
            await MainActor.run {
                testing = false
                testResult = result
            }
        }
    }
}
