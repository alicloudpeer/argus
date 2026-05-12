import SwiftUI

/// Sirkiye nabız özet kartı (ana sayfa Sirkiye tab).
///
/// 2026-05-05 H-65 — komple yeniden yazıldı.
///
/// Eski yapı (H-60 sonrası): heroCard "Bugün + sıfat + Nabız 30pt skor"
/// kartı + xu100Strip "BIST 100 yükleniyor" statik dikey kart. Sorunlar:
/// hero kart V5 dilinde (synthetic sıfat phrase + büyük inline skor),
/// xu100Strip statik (kullanıcı kayar canlı ticker bekliyordu).
///
/// Yeni yapı:
///   • heroCard kalktı → SirkiyeMakroStatusBar tek satır status (sayfa
///     üst nav'ının hemen altına hairline ile bağlanıyor). Plain rejim
///     adı + skor + chevron, tap ile makro detayını açıyor.
///   • xu100Strip kalktı → MarqueeTicker kayan canlı bant (BIST 100 +
///     USD/TRY + EUR/TRY + BIST sektör değişimleri).
///
/// Public API: `init()`. Singleton AnalysisViewModel.shared üzerinden okur.

struct SirkiyeDashboardView: View {
    @ObservedObject private var analysisVM = AnalysisViewModel.shared

    @State private var showDetails = false
    @State private var xu100Value: Double = 0
    @State private var xu100Change: Double = 0
    @State private var fallbackMacroScore: Double = 50
    @State private var fallbackMacroReady = false
    @State private var tickerItems: [TickerItem] = []

    // MARK: - Derived data

    private var atmosphereScore: Double {
        if let decision = analysisVM.bistAtmosphere {
            return decision.netSupport * 100.0
        }
        return fallbackMacroScore
    }

    private var atmosphereMode: MarketMode {
        analysisVM.bistAtmosphere?.marketMode ?? modeFrom(score: fallbackMacroScore)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            statusBar
            tickerStrip
        }
        .onAppear {
            Task {
                // refreshBistAtmosphere → HermesNewsVM.bistAtmosphere @Published
                // güncellenir, AnalysisVM Combine ile otomatik mirror eder
                // (analysisVM.bistAtmosphere okuyan UI yenilenir).
                await HermesNewsViewModel.shared.refreshBistAtmosphere()
                await loadFallbackMacroScore()
                await loadXU100()
                await loadTickerData()
            }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                SirkiyeAetherView(linkedDecision: analysisVM.bistAtmosphere)
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Status bar (üst nav'a bağlı tek satır)
    //
    // Sayfa üst nav'ının hemen altında hairline ile bağlanan tek satır
    // status. Solda nokta + plain rejim adı, sağda skor + chevron.
    // Tek tap → makro detay sheet.
    private var statusBar: some View {
        Button(action: { showDetails = true }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)

                Text(regimeLabel)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                Text("·")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textTertiary)

                Text("\(Int(atmosphereScore))")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Colors.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(Text("Sirkiye makro detayını aç"))
    }

    /// Synthetic sıfat phrase yerine plain rejim adı.
    private var regimeLabel: String {
        switch atmosphereMode {
        case .panic, .extremeFear: return "Sıkılaşma rejimi"
        case .fear, .neutral:      return "Karışık rejim"
        case .greed, .extremeGreed, .complacency: return "Genişleme rejimi"
        }
    }

    private var statusDotColor: Color {
        switch atmosphereMode {
        case .panic, .extremeFear: return InstitutionalTheme.Colors.crimson
        case .fear, .neutral:      return InstitutionalTheme.Colors.titan
        case .greed, .extremeGreed, .complacency: return InstitutionalTheme.Colors.aurora
        }
    }

    // MARK: - Kayar ticker (XU100 + döviz + sektör)

    private var tickerStrip: some View {
        MarqueeTicker(items: tickerItems)
            .padding(.horizontal, 16)
    }

    // MARK: - Data Loading

    private func loadXU100() async {
        do {
            let quote = try await BorsaPyProvider.shared.getXU100()
            await MainActor.run {
                xu100Value = quote.last
                xu100Change = quote.changePercent
            }
            await loadTickerData()
        } catch {
            print("⚠️ XU100 yüklenemedi: \(error)")
        }
    }

    private func loadFallbackMacroScore() async {
        let macro = await SirkiyeAetherEngine.shared.analyze(forceRefresh: true)
        await MainActor.run {
            fallbackMacroScore = max(0, min(100, macro.overallScore))
            fallbackMacroReady = true
        }
    }

    /// Kayar bant items'ını oluştur. XU100 + USD/TRY + EUR/TRY +
    /// (varsa) ilk 3 BIST sektör değişimi.
    private func loadTickerData() async {
        // TCMB snapshot — döviz kurları için.
        let snapshot = await TCMBDataService.shared.getMacroSnapshot(forceRefresh: false)
        let sectorResult = try? await BistSektorEngine.shared.analyze(forceRefresh: false)

        var items: [TickerItem] = []

        // 1) XU100
        items.append(TickerItem(
            id: "XU100",
            label: "XU100",
            price: xu100Value > 0 ? xu100Value : nil,
            percentChange: xu100Value > 0 ? xu100Change : nil,
            isSafeHavenCandidate: false,
            status: .index
        ))

        // 2) USD/TRY (delta yok, sadece değer)
        if let usdTry = snapshot.usdTry {
            items.append(TickerItem(
                id: "USDTRY",
                label: "USD/TRY",
                price: usdTry,
                percentChange: nil,
                isSafeHavenCandidate: false,
                status: .index
            ))
        }

        // 3) EUR/TRY
        if let eurTry = snapshot.eurTry {
            items.append(TickerItem(
                id: "EURTRY",
                label: "EUR/TRY",
                price: eurTry,
                percentChange: nil,
                isSafeHavenCandidate: false,
                status: .index
            ))
        }

        // 4) BIST sektör değişimleri — en hareketli 3 sektör.
        if let sectors = sectorResult?.sectors {
            let topMovers = sectors
                .sorted { abs($0.dailyChange) > abs($1.dailyChange) }
                .prefix(3)
            for sector in topMovers {
                items.append(TickerItem(
                    id: "SECTOR_\(sector.code)",
                    label: sector.name.uppercased(),
                    price: nil,
                    percentChange: sector.dailyChange,
                    isSafeHavenCandidate: false,
                    status: .normal
                ))
            }
        }

        await MainActor.run {
            tickerItems = items
        }
    }

    // MARK: - Helpers (legacy, hâlâ kullanılan)

    private func modeFrom(score: Double) -> MarketMode {
        switch score {
        case ..<25:  return .panic
        case ..<40:  return .extremeFear
        case ..<50:  return .fear
        case ..<60:  return .neutral
        case ..<75:  return .greed
        case ..<90:  return .extremeGreed
        default:     return .complacency
        }
    }

    // MARK: - Accessibility

    private var accessibilitySummary: Text {
        Text("\(regimeLabel), nabız \(Int(atmosphereScore))")
    }
}

// MARK: - Custom Badge Helper (legacy, korunuyor — diğer ekranlar kullanıyor olabilir)

extension View {
    func paddingbadge(_ color: Color) -> some View {
        self.padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
