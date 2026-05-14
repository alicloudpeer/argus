import SwiftUI

// MARK: - Argus Analysis Sheet (V5.H-34)
//
// Sanctum'da "Argus analizini aç" düğmesi basıldığında açılır.
//
// İlk versiyon: ArgusGrandDecision'da var olan veriler (motor skorları,
// gerekçe template'leri, çelişki haritası) detaylı bir okuma formatında
// sunulur. Hiçbir nil/boş alan yoktur.
//
// İleride: ArgusExplanationService.generateExplanation(for:) çağrılır,
// Groq/Gemini'den gelen `ArgusExplanation` (title + summary + bullets)
// üst kısma eklenir. Şu an o entegrasyon yapılmadan da sheet işe yarar
// halde duruyor — yine kanonik içerik var.

struct ArgusAnalysisSheet: View {
    let symbol: String
    let decision: ArgusGrandDecision?

    @Environment(\.dismiss) private var dismiss

    @State private var narrative: String?
    @State private var narrativeError: String?
    @State private var isLoadingNarrative: Bool = false

    /// 2026-05-14: KararKartiViewModel'in `prepare()` ve PremortemEngine zincirini
    /// üretim akışına bağlar. V2 kart Sanctum'dan kaldırıldı ama Argus Analizi
    /// sheet'inde "Risk senaryoları" bölümü olarak görünür — risk uyarıları
    /// kararın analiziyle birlikte tek ekranda kalmış olur.
    @StateObject private var kararKartiVM = KararKartiViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock
                    finalDecisionBlock
                    narrativeBlock     // 2026-05-11: LLM destekli Türkçe yorum
                    motorReasoningList
                    conflictBlock
                    riskScenariosBlock // 2026-05-14: PremortemEngine senaryoları
                    footerNote
                }
                .padding(16)
            }
            .task(id: symbol) {
                await loadNarrative()
                await loadRiskScenarios()
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Argus analizi")
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundColor(InstitutionalTheme.Colors.holo)
                }
            }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(symbol)
                .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text("Konsey detaylı analizi")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - Konsey kararı

    @ViewBuilder
    private var finalDecisionBlock: some View {
        if let d = decision {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sonuç")
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text(actionText(d.finalActionCore))
                            .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                            .foregroundColor(actionColor(d.finalActionCore))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Güven")
                            .font(DesignTokens.Fonts.custom(size: 11))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        Text("%\(Int(d.finalScoreCore.rounded()))")
                            .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                }
                Divider().background(DesignTokens.Colors.border)
                Text(summarySentence(d))
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(actionColor(d.finalActionCore).opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholderBlock(text: "Konsey kararı henüz hesaplanmadı.")
        }
    }

    private func summarySentence(_ d: ArgusGrandDecision) -> String {
        // Kısa bir tek cümle: en güçlü destekçi + en güçlü itirazcı.
        let r = d.motorReasonings.sorted { $0.score > $1.score }
        guard let top = r.first, let bottom = r.last else {
            return "Veri yetersiz, konsey net bir tavır almadı."
        }
        if top.motor == bottom.motor {
            return "Sadece \(top.motor.displayName) verisi var. Konsey tek motordan beslendiği için kararı temkinli al."
        }
        return "\(top.motor.displayName) (\(Int(top.score))) en güçlü destekçi, \(bottom.motor.displayName) (\(Int(bottom.score))) en zayıf halka. Konsey kararı bu iki uç arasında dengelendi."
    }

    // MARK: - Motor list

    @ViewBuilder
    private var motorReasoningList: some View {
        if let d = decision, !d.motorReasonings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Motor oyları")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                ForEach(d.motorReasonings, id: \.motor) { r in
                    motorRow(r)
                }
            }
        }
    }

    private func motorRow(_ r: MotorReasoning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.motor.displayName)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                // Chiron gibi sayısal olmayan motorlar için valueText doğrudan gösterilir.
                if let value = r.valueText {
                    Text(value)
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(stanceColor(r.stance))
                } else if r.score <= 0 {
                    Text("Bekleniyor")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                } else {
                    Text("\(r.stance.arrowGlyph) \(r.stance.rawValue) · \(Int(r.score))")
                        .font(DesignTokens.Fonts.custom(size: 12, design: .monospaced))
                        .foregroundColor(stanceColor(r.stance))
                }
            }
            if !r.summary.isEmpty {
                Text(r.summary)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let w = r.weight {
                Text("Konsey ağırlığı %\(Int((w * 100).rounded()))")
                    .font(DesignTokens.Fonts.custom(size: 11, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stanceColor(r.stance).opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Çelişki haritası

    @ViewBuilder
    private var conflictBlock: some View {
        if let d = decision, !d.motorReasonings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Çelişki haritası")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Text(d.conflictMapText)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - LLM-driven narrative (Faz 5.B — 2026-05-11)

    @ViewBuilder
    private var narrativeBlock: some View {
        if let text = narrative, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(InstitutionalTheme.Colors.holo)
                    Text("Argus yorumu")
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                }
                Text(text)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(InstitutionalTheme.Colors.holo.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if isLoadingNarrative {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(InstitutionalTheme.Colors.holo)
                Text("Argus yorumu hazırlanıyor…")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let err = narrativeError {
            Text("Yorum üretilemedi: \(err)")
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
        }
    }

    private var footerNote: some View {
        Text("Bu sayfa motor verilerinden üretilen yapısal analizi gösterir. Yatırım tavsiyesi değildir.")
            .font(DesignTokens.Fonts.custom(size: 11))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .padding(.top, 8)
    }

    // MARK: - Risk senaryoları (Faz 1.A.1 PremortemEngine bağlantısı)
    //
    // 2026-05-14: KararKartiViewModel.prepare() bu sheet'ten çağrılır; viewModel'in
    // hazırladığı 4 bölümden sadece `riskler` array'i kullanılır. Diğer bölümler
    // (aksiyon/güven/modüller) Sanctum Council Body'sinde zaten gösteriliyor —
    // tekrar olmasın diye burada sadece risk senaryoları görünür.
    @ViewBuilder
    private var riskScenariosBlock: some View {
        if !kararKartiVM.riskler.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Risk senaryoları")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Text("Bu kararın yanlış olabileceği senaryolar:")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                ForEach(kararKartiVM.riskler) { scenario in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: severityIcon(scenario.severity))
                            .foregroundColor(severityColor(scenario.severity))
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scenario.trigger)
                                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                                .foregroundColor(severityColor(scenario.severity))
                                .textCase(.uppercase)
                            Text(scenario.scenario)
                                .font(DesignTokens.Fonts.custom(size: 13))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func severityIcon(_ severity: PremortemEngine.RiskScenario.Severity) -> String {
        switch severity {
        case .low:    return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high:   return "exclamationmark.octagon.fill"
        }
    }

    private func severityColor(_ severity: PremortemEngine.RiskScenario.Severity) -> Color {
        switch severity {
        case .low:    return DesignTokens.Colors.textTertiary
        case .medium: return InstitutionalTheme.Colors.holo
        case .high:   return DesignTokens.Colors.error
        }
    }

    /// ViewModel.prepare çağrılır → PremortemEngine sonucu `riskler` array'ine yazılır.
    /// Sheet açıldığında ve sembol değiştiğinde otomatik tetiklenir.
    @MainActor
    private func loadRiskScenarios() async {
        guard let d = decision else { return }
        let aetherScore: Double = {
            switch d.aetherDecision.stance {
            case .riskOn:    return 80
            case .cautious:  return 60
            case .defensive: return 35
            case .riskOff:   return 15
            }
        }()
        await kararKartiVM.prepare(
            from: d,
            atlasMargin: d.atlasDecision?.marginOfSafety,
            demeterScore: nil,
            aetherScore: aetherScore,
            clusterCount: 0,
            hasAISignalSupport: false,
            estimatedPositionTRY: 0
        )
    }

    // MARK: - LLM call

    private func loadNarrative() async {
        guard let d = decision else { return }
        isLoadingNarrative = true
        narrativeError = nil
        defer { isLoadingNarrative = false }
        do {
            let text = try await ArgusAnalysisNarrative.generate(symbol: symbol, decision: d)
            narrative = text
        } catch {
            narrativeError = error.localizedDescription
            print("⚠️ Argus narrative failed: \(error)")
        }
    }

    private func placeholderBlock(text: String) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.custom(size: 13))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func actionText(_ a: SignalAction) -> String {
        switch a {
        case .buy:  return "Al"
        case .sell: return "Sat"
        case .hold: return "Bekle"
        case .wait: return "İzle"
        case .skip: return "Pas"
        }
    }

    private func actionColor(_ a: SignalAction) -> Color {
        switch a {
        case .buy:                return InstitutionalTheme.Colors.aurora
        case .hold, .wait, .skip: return InstitutionalTheme.Colors.holo
        case .sell:               return InstitutionalTheme.Colors.crimson
        }
    }

    private func stanceColor(_ s: MotorStance) -> Color {
        switch s {
        case .strongBuy, .buy:   return InstitutionalTheme.Colors.aurora
        case .wait:              return InstitutionalTheme.Colors.holo
        case .neutral:           return DesignTokens.Colors.textSecondary
        case .sell, .strongSell: return InstitutionalTheme.Colors.crimson
        }
    }
}
