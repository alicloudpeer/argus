import SwiftUI

/// Faz 1.B.4 + 1.B.5: Settings → Veri Defteri ekranı.
///
/// Kullanıcıya ArgusLedger SQLite dosyasının boyutunu, tier dağılımını
/// (events/trades/outcomes × hot/warm/cold) ve manuel yuvarlama tetiğini sunar.
/// 250 MB tavan aşılırsa sarı banner uyarısı görünür.
///
/// Mevcut Settings yapısına dokunulmadan eklendi; SettingsView yeni "Veri Defteri"
/// link satırı bu view'i SubPage olarak açar.
struct VeriDefteriView: View {
    @State private var dbBytes: Int64? = nil
    @State private var snapshot: [String: [String: Int]] = [:]
    @State private var isRunningMigration: Bool = false
    @State private var lastMigrationMessage: String? = nil

    /// 250 MB tavan — bu üzerinde sarı uyarı banner görünür ve manuel temizleme önerilir.
    static let sizeWarningBytes: Int64 = 250 * 1024 * 1024

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sizeCard
                if isAboveWarning {
                    warningBanner
                }
                tierDistributionSection
                migrationButton
                if let message = lastMigrationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .task {
            await loadAll()
        }
    }

    // MARK: - Sections

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VERİ DEFTERİ BOYUTU")
                .font(.caption.smallCaps())
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            Text(formattedSize)
                .font(.title)
                .fontWeight(.bold)
            Text("ArgusLedger SQLite — kararlar, trade'ler, sonuçlar")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Veri defteri 250 MB'ı aştı")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text("Yuvarlama otomatik çalışıyor ama eski kayıtları manuel de tetikleyebilirsiniz.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.18))
        )
    }

    private var tierDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TIER DAĞILIMI")
                .font(.caption.smallCaps())
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            ForEach(["events", "trades", "outcomes"], id: \.self) { table in
                tierRow(table: table, counts: snapshot[table] ?? [:])
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func tierRow(table: String, counts: [String: Int]) -> some View {
        let hot = counts["hot"] ?? 0
        let warm = counts["warm"] ?? 0
        let cold = counts["cold"] ?? 0
        let total = hot + warm + cold
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(table.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(total) satır")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                tierTag(name: "sıcak", count: hot, color: .red)
                tierTag(name: "ılık", count: warm, color: .orange)
                tierTag(name: "soğuk", count: cold, color: .blue)
            }
        }
    }

    private func tierTag(name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(name) \(count)")
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }

    private var migrationButton: some View {
        Button {
            Task { await triggerMigration() }
        } label: {
            HStack {
                if isRunningMigration {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yuvarlama çalışıyor...")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Yuvarlamayı şimdi çalıştır")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
            )
            .foregroundColor(.blue)
        }
        .disabled(isRunningMigration)
    }

    // MARK: - Computed

    private var formattedSize: String {
        guard let bytes = dbBytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var isAboveWarning: Bool {
        guard let bytes = dbBytes else { return false }
        return bytes > Self.sizeWarningBytes
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
