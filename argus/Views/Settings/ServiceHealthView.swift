import SwiftUI

struct ServiceHealthView: View {
    @ObservedObject var monitor = ServiceHealthMonitor.shared

    @State private var quotaSnapshots: [ProviderQuotaSnapshot] = []
    @State private var quotaLastRefresh: Date = .distantPast

    var body: some View {
        List {
            // 2026-05-11 (Faz 5): Heimdall ProviderQuotaRegistry bölümü
            // — per-endpoint dakikalık/günlük kullanım, predictive
            // throttle alarmları. Üstteki klasik APIProvider listesi
            // legacy sliding-window quota (ServiceHealthMonitor).
            Section(header: Text("Heimdall Kotaları (gerçek-zamanlı)")) {
                ForEach(quotaSnapshots, id: \.provider) { snap in
                    quotaRow(snap)
                }
                if quotaSnapshots.isEmpty {
                    Text("Henüz hiç istek atılmadı — kotalar boş.")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
            .task(id: quotaLastRefresh) {
                quotaSnapshots = await ProviderQuotaRegistry.shared.snapshot()
            }
            .refreshable {
                quotaLastRefresh = Date()
                quotaSnapshots = await ProviderQuotaRegistry.shared.snapshot()
            }

            Section(header: Text("API Durumu & Kotolar (legacy)")) {
                ForEach(APIProvider.allCases) { provider in
                    if let status = monitor.providerStatuses[provider] {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(statusColor(status.status))
                                    .frame(width: 10, height: 10)
                                Text(provider.rawValue)
                                    .font(.headline)
                                Spacer()
                                Text(status.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }
                            
                            if let remaining = status.remainingQuota {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Kalan Hak:")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(remaining) / \(status.totalQuota != nil ? "\(status.totalQuota!)" : "?")")
                                            .font(.caption)
                                            .bold()
                                    }
                                    
                                    if let total = status.totalQuota, total > 0 {
                                        ProgressView(value: Double(remaining), total: Double(total))
                                            .progressViewStyle(LinearProgressViewStyle(tint: statusColor(status.status)))
                                    }
                                }
                            } else {
                                Text("Kota bilgisi alınamıyor veya limitsiz.")
                                    .font(.caption2)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }
                            
                            if let error = status.lastError {
                                Text("Son Hata: \(error)")
                                    .font(.caption2)
                                    .foregroundColor(DesignTokens.Colors.error)
                                    .lineLimit(2)
                            } else if let success = status.lastSuccess {
                                Text("Son İşlem: \(timeString(date: success))")
                                    .font(.caption2)
                                    .foregroundColor(DesignTokens.Colors.success)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section(header: Text("İşlem Günlüğü (Son 50)")) {
                ForEach(monitor.requestLog.reversed(), id: \.self) { log in
                    Text(log)
                        .font(DesignTokens.Fonts.custom(size: 10, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .navigationTitle("Sağlık Raporu")
    }
    
    private func statusColor(_ status: ServiceStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .degraded: return .yellow
        case .down: return .red
        case .unknown: return .gray
        }
    }

    private func timeString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Heimdall Quota Row

    @ViewBuilder
    private func quotaRow(_ snap: ProviderQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(quotaColor(snap))
                    .frame(width: 8, height: 8)
                Text("\(snap.provider) · \(snap.endpoint)")
                    .font(.subheadline)
                    .bold()
                Spacer()
                if let limit = snap.minuteLimit {
                    Text("\(snap.minuteHits)/\(limit) /dk")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if let pct = snap.minutePct, let limit = snap.minuteLimit, limit > 0 {
                ProgressView(value: min(pct, 100), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: quotaColor(snap)))
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
            }

            if let dayLimit = snap.dayLimit {
                HStack {
                    Text("Günlük: \(snap.dayHits)/\(dayLimit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    if let dayPct = snap.dayPct {
                        Text(String(format: "%.0f%%", dayPct))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(dayPct > 80 ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func quotaColor(_ snap: ProviderQuotaSnapshot) -> Color {
        let pct = snap.minutePct ?? 0
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        if pct >= 40 { return .yellow }
        return .green
    }
}

struct ServiceHealthView_Previews: PreviewProvider {
    static var previews: some View {
        ServiceHealthView()
    }
}
