import SwiftUI

// MARK: - Argus Durum Panosu (2026-05-14 V5 sade yeniden yazım)
//
// Eski: TerminalSection CAPS başlık ("OTOPİLOT · TİCARET DURUMU", "AETHER ·
// REJİM RADARI"), icon spam (bolt.fill, shield.lefthalf.filled, gauge.medium,
// arrow.up.forward.app.fill, waveform.path.ecg vb.), `.orange` warning her
// yerde, "AKTİF"/"AZALTILMIŞ" CAPS tracking pill, regime banner colored
// background+stroke, InstitutionalTheme.Typography.{body,caption,micro} —
// AI-tell sinyalleri ile dolu.
//
// Yeni: MarketView "yağ gibi" dili — kart yok, ayraçlı 4 bölüm, sentence
// case başlıklar, icon minimal (sadece geri/kapat), status için renk yerine
// sade text + success/error sadece state'lerde. Sarı/turuncu spam'i SIFIR.

struct ArgusStatusConsoleView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var autoPilotStore = AutoPilotStore.shared
    @ObservedObject private var marketContext = MarketContextCoordinator.shared

    // Canlı değerler — parent view'dan push ediliyor
    let aetherCurrent: Double
    let aetherVelocity: Double
    let aetherSignal: String
    let aetherCrossingMsg: String?
    let regimeDirection: String
    let regimeSummary: String?
    let regimeEvidence: [String]
    let regimeConfidence: Double
    let pulseSummary: String
    let pulseIntensity: String
    let pulseDirection: String
    let chironTradeCount: Int
    let chironWinRate: Int
    let alkindusPendingCount: Int
    let policyMode: String
    let marketOpenGlobal: Bool
    let marketOpenBist: Bool
    let watchlistCount: Int
    let tradeBlockReasons: [String]

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        autoPilotSection
                        bandDivider
                        lastScanSection
                        bandDivider
                        aetherRegimeSection
                        bandDivider
                        moduleHealthSection
                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.s10) {
            Text("Sistem durumu")
                .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(DesignTokens.Colors.Overlay.l05)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, DesignTokens.Spacing.s14)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.s10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: DesignTokens.BorderWidth.hairline)
        }
    }

    /// Bölümler arası 8pt gri ayraç band — section ayrımı için
    private var bandDivider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.Overlay.l03)
            .frame(height: DesignTokens.Spacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: DesignTokens.BorderWidth.hairline)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: DesignTokens.BorderWidth.hairline)
            }
    }

    // MARK: - 1. Otopilot

    private var autoPilotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle satır
            HStack(spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Otopilot")
                        .font(DesignTokens.Fonts.custom(size: 16))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(autoPilotStore.isAutoPilotEnabled
                         ? "Aktif · sinyaller takip ediliyor"
                         : "Kapalı · alım/satım yapılmaz")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(autoPilotStore.isAutoPilotEnabled
                                         ? DesignTokens.Colors.success
                                         : DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $autoPilotStore.isAutoPilotEnabled)
                    .labelsHidden()
                    .tint(DesignTokens.Colors.success)
            }
            .padding(.bottom, DesignTokens.Spacing.s14)

            rowDivider

            // Mod satır
            modeRow
                .padding(.vertical, DesignTokens.Spacing.s14)

            rowDivider

            // Mini stat 3-lü (rejim · nabız · haber)
            miniStatsRow
                .padding(.vertical, DesignTokens.Spacing.s14)

            rowDivider

            // Diagnostic
            diagnosticBlock
                .padding(.top, DesignTokens.Spacing.s10)

            // Blocker (varsa)
            if !tradeBlockReasons.isEmpty {
                rowDivider
                    .padding(.top, DesignTokens.Spacing.s10)
                blockerBlock
                    .padding(.top, DesignTokens.Spacing.s10)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: DesignTokens.BorderWidth.hairline)
    }

    private var modeRow: some View {
        let snap = marketContext.snapshot
        let modeLabel: String
        if snap.opportunityMode { modeLabel = "Fırsat modu" }
        else if snap.protectiveMode { modeLabel = "Koruyucu mod" }
        else { modeLabel = "Normal seyir" }

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(modeLabel)
                    .font(DesignTokens.Fonts.custom(size: 15))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(snap.humanSummary)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("×\(String(format: "%.2f", snap.positionMultiplier))")
                .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
    }

    private var miniStatsRow: some View {
        let snap = marketContext.snapshot
        let regimeText: String = {
            switch snap.regimeDirection {
            case "RISING":  return "↑ %\(Int(snap.regimeConfidence * 100))"
            case "FALLING": return "↓ %\(Int(snap.regimeConfidence * 100))"
            default:        return "stabil"
            }
        }()
        let regimeColor: Color = {
            switch snap.regimeDirection {
            case "RISING":  return DesignTokens.Colors.success
            case "FALLING": return DesignTokens.Colors.error
            default:        return DesignTokens.Colors.textPrimary
            }
        }()
        return HStack(spacing: 0) {
            miniStatCol(label: "Rejim", value: regimeText, color: regimeColor)
            miniStatCol(label: "Nabız", value: pulseHumanText(snap.pulseIntensity),
                        color: DesignTokens.Colors.textPrimary)
            miniStatCol(label: "Haber",
                        value: "+\(snap.hermesPositive) / −\(snap.hermesNegative)",
                        color: DesignTokens.Colors.textPrimary)
        }
    }

    private func miniStatCol(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pulseHumanText(_ intensity: String) -> String {
        switch intensity {
        case "EXTREME":  return "fırtına"
        case "SURGING":  return "yüksek"
        case "STIRRING": return "kıpırtı"
        case "NORMAL":   return "normal"
        default:         return "sakin"
        }
    }

    private var diagnosticBlock: some View {
        VStack(spacing: 0) {
            diagnosticRow(label: "Risk politikası",
                          value: policyModeText,
                          ok: policyMode == "NORMAL")
            diagnosticRow(label: "Global piyasa",
                          value: marketOpenGlobal ? "Açık" : "Kapalı",
                          ok: marketOpenGlobal)
            diagnosticRow(label: "BIST",
                          value: marketOpenBist ? "Açık" : "Kapalı",
                          ok: marketOpenBist)
            diagnosticRow(label: "İzleme listesi",
                          value: "\(watchlistCount) sembol",
                          ok: watchlistCount > 0)
        }
    }

    private var policyModeText: String {
        switch policyMode {
        case "NORMAL": return "Normal"
        case "CAUTIOUS": return "Temkinli"
        case "DEFENSIVE": return "Savunma"
        default: return policyMode.lowercased().capitalized
        }
    }

    private func diagnosticRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(ok ? DesignTokens.Colors.textPrimary
                                    : DesignTokens.Colors.textTertiary)
        }
        .padding(.vertical, DesignTokens.Spacing.s6)
    }

    private var blockerBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Neden trade etmiyor")
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.bottom, DesignTokens.Spacing.xxs)
            ForEach(tradeBlockReasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.s6) {
                    Text("·")
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    Text(reason)
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
        }
    }

    // MARK: - 2. Son tarama

    private var lastScanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Son tarama")
                .padding(.bottom, DesignTokens.Spacing.md)

            let summary = autoPilotStore.lastScanSummary

            if !summary.hasRun {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("İlk tarama bekleniyor")
                        .font(DesignTokens.Fonts.custom(size: 16))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text("Otopilot henüz bir tur çalıştırmadı — 60 saniyeye kadar sürebilir.")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Özet satır
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.scannedCount) sembol tarandı")
                        .font(DesignTokens.Fonts.custom(size: 16))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text(ageText(summary.ageSeconds))
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.bottom, DesignTokens.Spacing.xs)

                (
                    Text("\(summary.signalCount)")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(summary.signalCount > 0
                                         ? DesignTokens.Colors.success
                                         : DesignTokens.Colors.textTertiary)
                    + Text(" sinyal · ")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    + Text("\(summary.skippedCount)")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    + Text(" atlandı")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                )
                .padding(.bottom, DesignTokens.Spacing.md)

                rowDivider

                // Bakiye 3-lü
                HStack(spacing: 0) {
                    miniStatCol(label: "Global",
                                value: "$ \(formatBalance(summary.globalBalance))",
                                color: DesignTokens.Colors.textPrimary)
                    miniStatCol(label: "BIST",
                                value: "₺ \(formatBalance(summary.bistBalance))",
                                color: DesignTokens.Colors.textPrimary)
                    miniStatCol(label: "Açık poz.",
                                value: "\(summary.openPositions)",
                                color: DesignTokens.Colors.textPrimary)
                }
                .padding(.vertical, DesignTokens.Spacing.md)

                // Skip sebepleri
                if !summary.topSkipReasons.isEmpty {
                    rowDivider
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("En sık atlama sebepleri")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .padding(.bottom, DesignTokens.Spacing.xxs)
                        ForEach(summary.topSkipReasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.s6) {
                                Text("·")
                                    .foregroundColor(DesignTokens.Colors.textTertiary)
                                Text(reason)
                                    .font(DesignTokens.Fonts.custom(size: 13))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.s10)
                }

                // Sinyal yoksa uyarı
                if summary.signalCount == 0 && summary.skippedCount == 0 {
                    Text("Tarama çalıştı ama ne sinyal üretildi ne atlama kaydedildi. Council eşikleri veya veri akışı kontrol edilmeli.")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DesignTokens.Spacing.md)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private func formatBalance(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            f.groupingSeparator = ","
            return f.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        return String(format: "%.0f", value)
    }

    private func ageText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) sn önce" }
        if s < 3600 { return "\(s / 60) dk önce" }
        return "\(s / 3600) sa önce"
    }

    // MARK: - 3. Aether rejim

    private var aetherRegimeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Aether rejim")
                .padding(.bottom, DesignTokens.Spacing.md)

            // Ana satır
            HStack(alignment: .firstTextBaseline) {
                Text(aetherDirectionText)
                    .font(DesignTokens.Fonts.custom(size: 16))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("%\(Int(regimeConfidence * 100)) güven")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(.bottom, DesignTokens.Spacing.xs)

            if let summary = regimeSummary, !summary.isEmpty {
                Text(summary)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DesignTokens.Spacing.md)
            }

            // Skor + Hız
            HStack {
                Text("Skor \(Int(aetherCurrent))")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("·")
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text("\(String(format: "%+.1f", aetherVelocity))/gün")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding(.bottom, DesignTokens.Spacing.xs)

            if let crossing = aetherCrossingMsg {
                Text(crossing)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .padding(.bottom, DesignTokens.Spacing.md)
            }

            // Nabız
            if !pulseSummary.isEmpty {
                rowDivider
                    .padding(.top, DesignTokens.Spacing.s6)
                HStack(alignment: .firstTextBaseline) {
                    Text("Nabız")
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Spacer()
                    Text(pulseSummary)
                        .font(DesignTokens.Fonts.custom(size: 13))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DesignTokens.Spacing.md)
            }

            // Evidence — bullet liste, renk yok
            if !regimeEvidence.isEmpty {
                rowDivider
                    .padding(.top, DesignTokens.Spacing.md)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    ForEach(regimeEvidence, id: \.self) { e in
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.s6) {
                            Text("·")
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                            Text(e)
                                .font(DesignTokens.Fonts.custom(size: 13))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                    }
                }
                .padding(.top, DesignTokens.Spacing.s10)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private var aetherDirectionText: String {
        switch regimeDirection {
        case "RISING":  return "Rejim toparlanıyor"
        case "FALLING": return "Rejim bozuluyor"
        default:        return "Stabil seyir"
        }
    }

    // MARK: - 4. Modüller

    private var moduleHealthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Modüller")
                .padding(.bottom, DesignTokens.Spacing.md)

            VStack(spacing: 0) {
                moduleRow(role: "Teknik",
                          active: true,
                          detail: "RSI/MACD · rejim duyarlı")
                rowDivider
                moduleRow(role: "Bilanço",
                          active: true,
                          detail: "Finansal oranlar · sektör karşılaştırma")
                rowDivider
                moduleRow(role: "Makro",
                          active: true,
                          detail: aetherModuleDetail)
                rowDivider
                moduleRow(role: "Haber",
                          degraded: true,
                          detail: "Önbellek devrede")
                rowDivider
                moduleRow(role: "Tahmin",
                          active: true,
                          detail: "5 günlük · advisor")
                rowDivider
                moduleRow(role: "Şok/Sektör",
                          active: true,
                          detail: "Advisor katmanı")
                rowDivider
                moduleRow(role: "Faktör",
                          active: true,
                          detail: "Değer · kalite · momentum")
                rowDivider
                moduleRow(role: "Öğrenme",
                          active: chironTradeCount > 0,
                          detail: chironTradeCount > 0
                            ? "Kazanma %\(chironWinRate) · \(chironTradeCount) trade"
                            : "Veri birikiyor")
                rowDivider
                moduleRow(role: "Kalibrasyon",
                          active: alkindusPendingCount > 0,
                          detail: alkindusPendingCount > 0
                            ? "\(alkindusPendingCount) gözlem bekliyor"
                            : "Sıra boş")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.vertical, DesignTokens.Spacing.s18)
    }

    private func moduleRow(role: String, active: Bool = false, degraded: Bool = false, detail: String) -> some View {
        let statusText: String = degraded ? "Azaltılmış" : (active ? "Çalışıyor" : "Beklemede")
        let statusColor: Color = degraded
            ? DesignTokens.Colors.textTertiary
            : (active ? DesignTokens.Colors.success
                      : DesignTokens.Colors.textTertiary)

        return HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(role)
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(statusText)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(statusColor)
        }
        .padding(.vertical, DesignTokens.Spacing.s10)
    }

    private var aetherModuleDetail: String {
        guard aetherCurrent > 0 else { return "Veri bekleniyor" }
        return "Skor \(Int(aetherCurrent)) · \(String(format: "%+.1f", aetherVelocity))/gün"
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
            .foregroundColor(DesignTokens.Colors.textTertiary)
    }
}
