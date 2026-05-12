import SwiftUI

struct DebugTracePanel: View {
    let engine: EngineTag
    @State private var trace: RequestTraceEvent?
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Veri Analizi: \(engine.rawValue)", systemImage: "ladybug")
                .font(.headline)
                .foregroundColor(.orange)
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let trace = trace {
                VStack(alignment: .leading, spacing: 6) {
                    
                    // row 1: Status
                    HStack {
                        Text(trace.isSuccess ? "BAŞARILI" : "BAŞARISIZ")
                            .bold()
                            .foregroundColor(trace.isSuccess ? .green : .red)
                            .padding(4)
                            .background(trace.isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("\(Int(trace.durationMs))ms")
                            .monospacedDigit()
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        
                        Spacer()
                        
                        Text(trace.provider.rawValue)
                            .bold()
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    .font(.caption)
                    
                    Divider().background(DesignTokens.Colors.Overlay.l10)
                    
                    // row 2: Details
                    Group {
                        Text("Kategori: \(trace.failureCategory.rawValue)")
                        Text("Symbol: \(trace.symbol)") // Forensic: Encoded symbol verification
                        // Showing mostly decoded url for readability, or keep raw
                        Text("URL: \(trace.endpoint)")
                            .font(DesignTokens.Fonts.custom(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        // Error & Domain
                        if let err = trace.errorMessage {
                            Text("Hata: \(err)")
                                .foregroundColor(DesignTokens.Colors.error)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if let code = trace.httpStatusCode {
                             Text("HTTP: \(code) | Request Sent: Yes")
                        } else {
                             Text("Request Sent: Failed (Client Side)")
                                .foregroundColor(.orange)
                        }
                        
                        if let path = trace.decisionPath {
                            Text("Karar Yolu: \(path.joined(separator: " -> "))")
                                .italic()
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                    
                    // row 3: Retry/Fallback
                    if trace.retryCount > 0 {
                        Text("Yeniden Deneme: \(trace.retryCount)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Text("Bu motor için kayıt bulunamadı.")
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
        }
        .padding()
        .background(DesignTokens.Colors.Scrim.s40)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .onAppear {
            loadTrace()
        }
    }
    
    private func loadTrace() {
        Task {
            // Find last relevant trace for this engine
            let last = await HeimdallTelepresence.shared.getTraces().last { $0.engine == engine }
            await MainActor.run {
                self.trace = last
                self.isLoading = false
            }
        }
    }
}
