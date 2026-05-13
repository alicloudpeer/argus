import SwiftUI

struct ArgusVoiceView: View {
    @StateObject private var viewModel = ChatViewModel()
    @ObservedObject private var speech = ArgusSpeechService.shared
    @ObservedObject private var tts = ArgusTTSService.shared
    @Environment(\.dismiss) var dismiss
    @State private var isListening = false
    @State private var showSuggestions = true
    
    // Design 14: Suggestions
    let suggestions = [
        "Portföy durumum ne?",
        "AAPL için analiz yap",
        "Bugün ne almalıyım?",
        "Piyasa neden düşüyor?"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // V5 Header — Argus göz radial gradient + Argus Voice başlık
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: Color(hex: "6AA5FF"), location: 0),
                                            .init(color: InstitutionalTheme.Colors.holo, location: 0.55),
                                            .init(color: Color(hex: "143A7A"), location: 1.0)
                                        ]),
                                        center: UnitPoint(x: 0.3, y: 0.3),
                                        startRadius: 0,
                                        endRadius: 24
                                    )
                                )
                                .frame(width: 40, height: 40)
                            // 2026-05-05 H-67: MotorLogo(.argus) → SF Symbol sade.
                            Image(systemName: "waveform")
                                .font(DesignTokens.Fonts.custom(size: 18, weight: .medium))
                                .foregroundColor(InstitutionalTheme.Colors.holo)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sesli asistan")
                                .font(DesignTokens.Fonts.custom(size: 17, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Text("Çevrimiçi")
                                .font(DesignTokens.Fonts.custom(size: 11))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DesignTokens.Colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        DesignTokens.Colors.background
                            .overlay(ArgusHair().frame(maxHeight: .infinity, alignment: .bottom))
                    )
                    
                    // Chat Area
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // Welcome Message
                                if viewModel.messages.isEmpty {
                                    // V5 welcome: büyük Argus göz + karşılama
                                    VStack(spacing: 16) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    RadialGradient(
                                                        gradient: Gradient(stops: [
                                                            .init(color: Color(hex: "6AA5FF"), location: 0),
                                                            .init(color: InstitutionalTheme.Colors.holo, location: 0.55),
                                                            .init(color: Color(hex: "143A7A"), location: 1.0)
                                                        ]),
                                                        center: UnitPoint(x: 0.3, y: 0.3),
                                                        startRadius: 0,
                                                        endRadius: 48
                                                    )
                                                )
                                                .frame(width: 80, height: 80)
                                                .shadow(color: InstitutionalTheme.Colors.holo.opacity(0.4),
                                                        radius: 20)
                                            Circle()
                                                .stroke(InstitutionalTheme.Colors.holo.opacity(0.25), lineWidth: 1)
                                                .frame(width: 96, height: 96)
                                            // 2026-05-05 H-67: MotorLogo argus → SF Symbol sade.
                                            Image(systemName: "waveform")
                                                .font(DesignTokens.Fonts.custom(size: 38, weight: .medium))
                                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                        }

                                        Text("Merhaba, ben Argus.")
                                            .font(DesignTokens.Fonts.custom(size: 22, weight: .medium))
                                            .foregroundColor(DesignTokens.Colors.textPrimary)

                                        Text("Piyasalar, portföyün veya hisseler hakkında bana soru sorabilirsin.")
                                            .font(InstitutionalTheme.Typography.caption)
                                            .foregroundColor(DesignTokens.Colors.textSecondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 32)
                                    }
                                    .padding(.top, 40)
                                    .transition(.opacity)
                                }
                                
                                ForEach(viewModel.messages) { msg in
                                    ChatMessageBubble(message: msg)
                                        .id(msg.id)
                                }
                                
                                if viewModel.isLoading {
                                    HStack(spacing: 4) {
                                        Circle().fill(InstitutionalTheme.Colors.holo).frame(width: 8, height: 8)
                                        Circle().fill(InstitutionalTheme.Colors.holo).frame(width: 8, height: 8)
                                        Circle().fill(InstitutionalTheme.Colors.holo).frame(width: 8, height: 8)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 56) // Align with bubble
                                    .padding(.vertical, 8)
                                }
                                
                                Spacer().frame(height: 20)
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.messages.count) {
                            if let last = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // 2026-05-05 H-67: ArgusSectionCaption "ÖNERİLER" caps mono
                    // → sentence "Öneriler" sade label.
                    if viewModel.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Öneriler")
                                .font(DesignTokens.Fonts.custom(size: 13))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                                .padding(.horizontal, 16)

                            VStack(spacing: 8) {
                                v5SuggestionCard(motor: .chiron, tone: .motor(.chiron),
                                                 text: "Portföy durumum ne?")
                                v5SuggestionCard(motor: .orion, tone: .holo,
                                                 text: "AAPL için analiz yap")
                                v5SuggestionCard(motor: .prometheus, tone: .aurora,
                                                 text: "Bugün ne almalıyım?")
                                v5SuggestionCard(motor: .aether, tone: .crimson,
                                                 text: "Piyasa neden düşüyor?")
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)
                    }

                    // V5 input bar — pill shape + mic + send
                    HStack(spacing: 8) {
                        // 2026-05-11: Mic button ArgusSpeechService'e bağlandı.
                        // Recording: tap to start, tap again to stop. Tanınan
                        // metin canlı input field'a aktarılır.
                        Button(action: { toggleSpeech() }) {
                            Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                                .font(DesignTokens.Fonts.custom(size: 14))
                                .foregroundColor(speech.isRecording
                                                 ? DesignTokens.Colors.textPrimary
                                                 : DesignTokens.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(speech.isRecording
                                            ? InstitutionalTheme.Colors.crimson
                                            : InstitutionalTheme.Colors.surface3)
                                .clipShape(Circle())
                                .scaleEffect(speech.isRecording ? 1.0 + CGFloat(speech.audioLevel) * 0.15 : 1.0)
                                .animation(.linear(duration: 0.12), value: speech.audioLevel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(speech.isRecording ? "Kaydı durdur" : "Sesle sor")

                        TextField("Argus'a sor...", text: $viewModel.inputMessage, axis: .vertical)
                            .lineLimit(1...4)
                            .font(DesignTokens.Fonts.custom(size: 13))
                            .foregroundColor(DesignTokens.Colors.textPrimary)

                        Button {
                            if !viewModel.inputMessage.isEmpty {
                                viewModel.sendMessage()
                            }
                        } label: {
                            Image(systemName: viewModel.inputMessage.isEmpty ? "waveform" : "arrow.up")
                                .font(DesignTokens.Fonts.custom(size: 14, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(InstitutionalTheme.Colors.holo)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .overlay(
                                Capsule().stroke(DesignTokens.Colors.borderStrong, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .navigationBarHidden(true)
            .presentationDragIndicator(.visible)
            .onAppear {
                let decisions = Array(SignalStateViewModel.shared.argusDecisions.values)
                viewModel.updateContext(decisions: decisions, portfolio: RiskViewModel.shared.portfolio)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SpeechFinished"))) { notification in
                if let text = notification.object as? String {
                    viewModel.inputMessage = text
                    // Optional: Auto-send if silence detection is good
                    // viewModel.sendMessage()
                }
            }
            // Canlı transkripsiyon → input field'a aktar
            .onChange(of: speech.recognizedText) { _, newText in
                if !newText.isEmpty { viewModel.inputMessage = newText }
            }
            // Recording bittiğinde otomatik gönder (kullanıcı durdurursa son metin gönderilir)
            .onChange(of: speech.isRecording) { wasRecording, isNow in
                if wasRecording && !isNow {
                    let text = viewModel.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        viewModel.sendMessage()
                    }
                }
            }
            // Yeni asistan mesajını sesli oku (TTS)
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let last = viewModel.messages.last,
                      last.role == .assistant,
                      !last.content.isEmpty else { return }
                tts.speak(last.content)
            }
            .onDisappear {
                if speech.isRecording { speech.stopRecording() }
                tts.stop()
            }
        }
    }

    // MARK: - Speech toggle

    private func toggleSpeech() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            // Recording başlarken eski text'i temizle, TTS de sussun
            tts.stop()
            viewModel.inputMessage = ""
            do {
                try speech.startRecording()
            } catch {
                print("🛑 ArgusSpeech start failed: \(error)")
            }
        }
    }
}

// MARK: - Subviews

struct SpeechButton: View {
    @ObservedObject private var speechService = ArgusSpeechService.shared
    @Binding var inputMessage: String

    var body: some View {
        Button(action: { toggleRecording() }) {
            ZStack {
                if speechService.isRecording {
                    // Pulsing Waveform (Fake Visualization based on level)
                    Circle()
                        .stroke(InstitutionalTheme.Colors.crimson.opacity(0.5), lineWidth: 4)
                        .frame(width: 54 + CGFloat(speechService.audioLevel * 40), height: 54 + CGFloat(speechService.audioLevel * 40))
                        .animation(.linear(duration: 0.1), value: speechService.audioLevel)

                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                }
            }
            .frame(width: 48, height: 48)
            .background(speechService.isRecording ? InstitutionalTheme.Colors.crimson : InstitutionalTheme.Colors.holo)
            .clipShape(Circle())
        }
        .onChange(of: speechService.recognizedText) { _, newText in
            // Live transcription update
            inputMessage = newText
        }
    }

    func toggleRecording() {
        if speechService.isRecording {
            speechService.stopRecording()
        } else {
            try? speechService.startRecording()
        }
    }
}

// MARK: - V5 Suggestion Card

private extension ArgusVoiceView {
    /// 2026-05-05 H-67: motor ikon + tinted halka → sade SF Symbol.
    /// MotorLogo (Argus motor system'inden) yerine basit semantic ikon.
    func v5SuggestionCard(motor: MotorEngine, tone: ArgusChipTone, text: String) -> some View {
        Button {
            viewModel.inputMessage = text
            viewModel.sendMessage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: motorIconName(motor))
                    .font(DesignTokens.Fonts.custom(size: 14))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                Text(text)
                    .font(DesignTokens.Fonts.custom(size: 13))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func motorIconName(_ motor: MotorEngine) -> String {
        switch motor {
        case .orion:      return "waveform.path.ecg"
        case .atlas:      return "building.columns"
        case .aether:     return "globe"
        case .hermes:     return "newspaper"
        case .athena:     return "scope"
        case .demeter:    return "chart.pie"
        case .chiron:     return "arrow.triangle.2.circlepath"
        case .prometheus: return "chart.line.uptrend.xyaxis"
        case .phoenix:    return "shield"
        case .argus:      return "eye"
        case .alkindus:   return "brain.head.profile"
        case .poseidon:   return "drop"
        case .titan:      return "mountain.2"
        case .chronos:    return "clock"
        case .hephaestus: return "hammer"
        case .council:    return "person.3"
        }
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if !isUser {
                // V5 Bot Avatar — Argus göz mini
                // 2026-05-05 H-67: MotorLogo argus avatar → SF Symbol sade.
                ZStack {
                    Circle()
                        .fill(InstitutionalTheme.Colors.holo.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform")
                        .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.holo)
                }
            } else {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isUser ? .white : DesignTokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(isUser ? .white.opacity(0.8) : DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .padding(.horizontal, 4)
            .background(isUser ? InstitutionalTheme.Colors.holo : DesignTokens.Colors.surface)
            .clipShape(
                // 2026-05-06: özel `.cornerRadius(_:corners:)` extension yoktu, UnevenRoundedRectangle ile asymmetric corner
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: isUser ? 20 : 4,
                    bottomTrailingRadius: isUser ? 4 : 20,
                    topTrailingRadius: 20
                )
            )
            .shadow(color: DesignTokens.Colors.Scrim.s05, radius: 2, x: 0, y: 1)
            .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            
            if isUser {
                // User Avatar
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.surface)
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.fill")
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .font(.body)
                }
            } else {
                Spacer()
            }
        }
    }
}


