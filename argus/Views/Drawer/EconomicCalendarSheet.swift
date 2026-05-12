import SwiftUI

struct EconomicCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [EconomicCalendarService.CalendarEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ArgusNavHeader(
                title: "EKONOMİ TAKVİMİ",
                subtitle: "MAKRO OLAY · ETKİ · TAKİP",
                leadingDeco: .bars3([.holo, .text, .text]),
                actions: [.custom(sfSymbol: "xmark", action: { dismiss() })]
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introSection
                    upcomingEvents
                    impactGuide
                    tcmbSection
                    fedSection
                }
                .padding(20)
            }
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .task {
            await loadEvents()
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Makro takvim")
                .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)

            Text("Önemli ekonomik olaylar piyasaları doğrudan etkiler. Bu olayların öncesinde ve sonrasında volatilite artar.")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textPrimary)
                .lineSpacing(2)
        }
    }

    // MARK: - Upcoming Events

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Yaklaşan olaylar")

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Takvim yükleniyor")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.crimson)
            } else if events.isEmpty {
                Text("Seçilen aralıkta kayıtlı olay yok.")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: EconomicCalendarService.CalendarEvent) -> some View {
        HStack(spacing: 12) {
            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                if let country = event.country, !country.isEmpty {
                    Text(country)
                        .font(.caption2)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }

            Spacer()

            impactBadge(impactFromString(event.impact))
        }
        .padding(10)
        .background(DesignTokens.Colors.Overlay.l02)
        .cornerRadius(InstitutionalTheme.Radius.sm)
    }

    private enum EventImpact {
        case high, medium, low

        var color: Color {
            switch self {
            case .high: return InstitutionalTheme.Colors.crimson
            case .medium: return InstitutionalTheme.Colors.titan
            case .low: return DesignTokens.Colors.textSecondary
            }
        }

        var text: String {
            switch self {
            case .high: return "Yuksek"
            case .medium: return "Orta"
            case .low: return "Dusuk"
            }
        }
    }

    private func impactBadge(_ impact: EventImpact) -> some View {
        Text(impact.text)
            .font(.caption2)
            .foregroundColor(impact.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(impact.color.opacity(DesignTokens.Opacity.glassCard))
            .cornerRadius(4)
    }

    private func impactFromString(_ value: String?) -> EventImpact {
        guard let value = value?.lowercased() else { return .low }
        if value.contains("high") || value.contains("yuksek") {
            return .high
        }
        if value.contains("medium") || value.contains("orta") {
            return .medium
        }
        return .low
    }

    // MARK: - Impact Guide

    private var impactGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ETKI REHBERI")

            VStack(alignment: .leading, spacing: 8) {
                Text("Yuksek etkili olaylar oncesinde:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    guideItem("Pozisyon boyutunu kucult")
                    guideItem("Stop-loss seviyelerini gozden gecir")
                    guideItem("Ani volatiliteye hazirlikli ol")
                    guideItem("Veri sonrasi ilk 15 dakika islem yapma")
                }
            }
        }
    }

    private func guideItem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(InstitutionalTheme.Colors.holo)
            Text(text)
                .font(.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - TCMB

    private var tcmbSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TCMB kararları")

            VStack(alignment: .leading, spacing: 8) {
                Text("TCMB Para Politikası Kurulu (PPK) her ay toplanır ve politika faizini belirler.")
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .lineSpacing(2)

                HStack(spacing: 20) {
                    impactScenario("Faiz artışı", "BIST için genellikle negatif", InstitutionalTheme.Colors.crimson)
                    impactScenario("Faiz indirimi", "BIST için genellikle pozitif", InstitutionalTheme.Colors.aurora)
                }

                Text("Ancak beklentiler önemli: beklenen faiz artışı zaten fiyatlanmış olabilir.")
                    .font(DesignTokens.Fonts.custom(size: 11))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - FED

    private var fedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("FED KARARLARI")

            VStack(alignment: .leading, spacing: 8) {
                Text("ABD Merkez Bankasi (FED) kararlari global piyasalari etkiler. FOMC toplantilari yaklasik 6 haftada bir yapilir.")
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                HStack(spacing: 20) {
                    impactScenario("Sikilastirma", "Gelisen piyasalardan cikis", InstitutionalTheme.Colors.crimson)
                    impactScenario("Gevsetme", "Risk istahi artar", InstitutionalTheme.Colors.aurora)
                }

                tipBox("FED karari sonrasi Dolar/TL hareketini izleyin. Guclu dolar genellikle BIST icin negatif.")
            }
        }
    }

    private func impactScenario(_ scenario: String, _ impact: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scenario)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)

            Text(impact)
                .font(.caption2)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tipBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.subheadline)
                .foregroundColor(InstitutionalTheme.Colors.holo)

            Text(text)
                .font(.caption)
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
        .padding(12)
        .background(InstitutionalTheme.Colors.holo.opacity(0.1))
        .cornerRadius(InstitutionalTheme.Radius.sm)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
            .foregroundColor(DesignTokens.Colors.textSecondary)
    }

    // MARK: - Data Load

    @MainActor
    private func loadEvents() async {
        isLoading = true
        errorMessage = nil

        do {
            events = try await EconomicCalendarService.shared.fetchUpcomingCalendarEvents(days: 14)
        } catch EconomicCalendarService.CalendarFetchError.missingApiKey {
            errorMessage = "Ekonomi takvimi icin FMP anahtari bulunamadi."
        } catch {
            errorMessage = "Ekonomi takvimi yuklenemedi: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

#Preview {
    EconomicCalendarSheet()
}
