import SwiftUI

/// Faz 1.B.4 + 1.B.5: Settings → Veri Defteri ekranı (2026-05-14 V5 sade yeniden yazım).
///
/// Eski: heavy CAPS (`VERİ DEFTERİ BOYUTU`, `TIER DAĞILIMI`, `EVENTS`), sarı
/// warning banner (`Color.yellow.opacity(0.18)`), mavi action button
/// (`Color.blue.opacity(0.15)`), tier dot'ları kırmızı/turuncu/mavi pill,
/// `Color(.secondarySystemBackground)` Apple sistem rengi, default font
/// ölçeği — tasarım sistemi sıfır kullanıyordu.
///
/// Yeni: MarketView "yağ gibi" dili — kart yok, ayraçlı sade liste, sentence
/// case başlık, sarı/titan gitti (text tonu hiyerarşisi ile vurgu), tek
/// renkli vurgu noktası: tavan aşıldığında migration button primary holo
/// olur (action önerilen).
///
/// Kullanıcıya ArgusLedger SQLite dosyasının boyutunu, tier dağılımını
/// (events/trades/outcomes × hot/warm/cold) ve manuel yuvarlama tetiğini sunar.
struct VeriDefteriView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var dbBytes: Int64? = nil
    @State private var snapshot: [String: [String: Int]] = [:]
    @State private var isRunningMigration: Bool = false
    @State private var lastMigrationMessage: String? = nil

    /// 250 MB tavan — bu üzerinde tipografik uyarı + button primary holo olur.
    static let sizeWarningBytes: Int64 = 250 * 1024 * 1024

    /// Tablo sırası (events → trades → outcomes) ve Türkçe karşılığı.
    private let tables: [(key: String, label: String)] = [
        ("events", "Kararlar"),
        ("trades", "Trade'ler"),
        ("outcomes", "Sonuçlar")
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topNav

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sizeSection
                        divider
                        tierList
                        actionSection
                        if let message = lastMigrationMessage {
                            migrationMessage(message)
                        }
                        explanation
                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadAll()
        }
    }

    // MARK: - Top nav

    private var topNav: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Fonts.custom(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Geri")

            Text("Veri defteri")
                .font(DesignTokens.Fonts.custom(size: 22, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Spacer()
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

    // MARK: - Size section

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Toplam boyut")
                .font(DesignTokens.Fonts.custom(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                Text(formattedSize)
                    .font(DesignTokens.Fonts.custom(size: 32, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text("/ \(formattedLimit)")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }

            if isAboveWarning {
                Text("Tavan aşıldı. Yuvarlama eski kayıtları toparlar.")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .padding(.top, DesignTokens.Spacing.s6)
            }

            // Progress — nötr çizgi, renk vurgu yok
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.Colors.Overlay.l06)
                        .frame(height: 2)
                    Capsule()
                        .fill(progressFill)
                        .frame(width: geo.size.width * progressRatio, height: 2)
                }
            }
            .frame(height: 2)
            .padding(.top, DesignTokens.Spacing.s14)
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.top, DesignTokens.Spacing.s20)
        .padding(.bottom, DesignTokens.Spacing.s18)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.borderSubtle)
            .frame(height: DesignTokens.BorderWidth.hairline)
            .padding(.horizontal, DesignTokens.Spacing.s18)
    }

    // MARK: - Tier list

    private var tierList: some View {
        VStack(spacing: 0) {
            ForEach(Array(tables.enumerated()), id: \.element.key) { idx, table in
                tierRow(key: table.key, label: table.label,
                        counts: snapshot[table.key] ?? [:])
                if idx < tables.count - 1 {
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: DesignTokens.BorderWidth.hairline)
                        .padding(.horizontal, DesignTokens.Spacing.s18)
                }
            }
        }
    }

    private func tierRow(key: String, label: String, counts: [String: Int]) -> some View {
        let hot = counts["hot"] ?? 0
        let warm = counts["warm"] ?? 0
        let cold = counts["cold"] ?? 0
        let total = hot + warm + cold

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(DesignTokens.Fonts.custom(size: 15))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(total)")
                    .font(DesignTokens.Fonts.custom(size: 13, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            // Tier dağılımı — tek satır, renk yerine text tonu hiyerarşisi
            // (sıcak en parlak, soğuk en soluk). AI-tell renkler (kırmızı/sarı/mavi)
            // tamamen kaldırıldı.
            tierDistributionText(hot: hot, warm: warm, cold: cold)
        }
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.vertical, DesignTokens.Spacing.s14)
    }

    private func tierDistributionText(hot: Int, warm: Int, cold: Int) -> Text {
        let t1 = Text("\(hot)")
            .foregroundColor(DesignTokens.Colors.textPrimary)
            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
        let t2 = Text(" sıcak · ")
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .font(DesignTokens.Fonts.custom(size: 12))
        let t3 = Text("\(warm)")
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
        let t4 = Text(" ılık · ")
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .font(DesignTokens.Fonts.custom(size: 12))
        let t5 = Text("\(cold)")
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium, design: .monospaced))
        let t6 = Text(" soğuk")
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .font(DesignTokens.Fonts.custom(size: 12))
        return t1 + t2 + t3 + t4 + t5 + t6
    }

    // MARK: - Action

    private var actionSection: some View {
        Button(action: { Task { await triggerMigration() } }) {
            HStack(spacing: DesignTokens.Spacing.s6) {
                if isRunningMigration {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yuvarlama çalışıyor...")
                        .font(DesignTokens.Fonts.custom(size: 14))
                } else {
                    Text("Yuvarlamayı çalıştır")
                        .font(DesignTokens.Fonts.custom(size: 14,
                                                       weight: isAboveWarning ? .medium : .regular))
                }
            }
            .foregroundColor(isAboveWarning && !isRunningMigration
                             ? DesignTokens.Colors.background
                             : DesignTokens.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.s13)
            .background(actionBackground)
            .overlay(actionBorder)
            .cornerRadius(DesignTokens.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(isRunningMigration)
        .padding(.horizontal, DesignTokens.Spacing.s18)
        .padding(.top, DesignTokens.Spacing.s18)
    }

    @ViewBuilder
    private var actionBackground: some View {
        if isAboveWarning && !isRunningMigration {
            DesignTokens.Colors.primary
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var actionBorder: some View {
        if !isAboveWarning || isRunningMigration {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(DesignTokens.Colors.border, lineWidth: DesignTokens.BorderWidth.hairline)
        }
    }

    private func migrationMessage(_ message: String) -> some View {
        Text(message)
            .font(DesignTokens.Fonts.custom(size: 12))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.s18)
            .padding(.top, DesignTokens.Spacing.md)
    }

    private var explanation: some View {
        Text("Sıcak veriler son 30 gün, ılık 30–180 gün, soğuk 180 günden eski. Yuvarlama eski kayıtları sıkıştırılmış halde saklar.")
            .font(DesignTokens.Fonts.custom(size: 11))
            .foregroundColor(DesignTokens.Colors.textTertiary)
            .lineSpacing(2)
            .padding(.horizontal, DesignTokens.Spacing.s18)
            .padding(.top, DesignTokens.Spacing.s20)
    }

    // MARK: - Computed

    private var formattedSize: String {
        guard let bytes = dbBytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var formattedLimit: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Self.sizeWarningBytes)
    }

    private var isAboveWarning: Bool {
        guard let bytes = dbBytes else { return false }
        return bytes > Self.sizeWarningBytes
    }

    private var progressRatio: CGFloat {
        guard let bytes = dbBytes, Self.sizeWarningBytes > 0 else { return 0 }
        let ratio = Double(bytes) / Double(Self.sizeWarningBytes)
        return CGFloat(min(1.0, max(0.0, ratio)))
    }

    private var progressFill: Color {
        // Tavan aşıldığında bile renk vurgu yok — sade textTertiary opaklık.
        isAboveWarning
            ? DesignTokens.Colors.textSecondary
            : DesignTokens.Colors.textTertiary
    }

    // MARK: - Actions

    private func loadAll() async {
        dbBytes = ArgusLedger.shared.databaseFileSizeBytes()
        snapshot = DataTieringEngine.shared.tierSnapshot()
    }

    private func triggerMigration() async {
        isRunningMigration = true
        let result = await DataTieringEngine.shared.runMigration()
        lastMigrationMessage = "Yuvarlama tamam: \(result.totalRowsMoved) satır taşındı"
        await loadAll()
        isRunningMigration = false
    }
}

#Preview {
    VeriDefteriView()
}
