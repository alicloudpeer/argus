import Foundation
import AVFoundation
import Combine

/// 🔊 THE VOICE OF ARGUS 🔊
/// AVSpeechSynthesizer wrapper — Argus'un cevaplarını sesli okur.
///
/// Tasarım kararları:
///   * Türkçe locale (`tr-TR`) varsayılan — neural Türkçe ses iOS 16+'da
///     mevcut (`Yelda` voice).
///   * Markdown/link/sayı temizliği — TTS ham JSON veya `**bold**`
///     okumaz, sadece düz Türkçe gövde.
///   * Tek seferde çalan kuyruk — yeni mesaj geldiğinde önceki kesilir.
///   * Audio session `.playback` (mic kayıt yapıyorsak çakışmaz; speech
///     service kendi `.record` mode'unu kullanır).
@MainActor
final class ArgusTTSService: NSObject, ObservableObject {
    static let shared = ArgusTTSService()

    @Published private(set) var isSpeaking: Bool = false
    @Published var isEnabled: Bool = true   // Settings'te kapatılabilir

    private let synthesizer = AVSpeechSynthesizer()

    /// Tercih edilen ses sırası. Yelda (neural) iOS 16+'da; yoksa default tr-TR.
    private let preferredVoiceIDs: [String] = [
        "com.apple.ttsbundle.Yelda-premium",
        "com.apple.ttsbundle.Yelda-compact",
        "com.apple.voice.compact.tr-TR.Yelda"
    ]

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public

    func speak(_ rawText: String) {
        guard isEnabled else { return }
        let cleaned = Self.clean(text: rawText)
        guard !cleaned.isEmpty else { return }

        // Önceki konuşmayı kes — kullanıcı yeni mesaj okumak istiyor.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = pickVoice()
        utterance.rate = 0.50            // 0.0..1.0 — 0.5 doğal hız
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.10
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSession()
    }

    // MARK: - Helpers

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        for id in preferredVoiceIDs {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }
        return AVSpeechSynthesisVoice(language: "tr-TR")
            ?? AVSpeechSynthesisVoice(language: "tr")
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("⚠️ TTS audio session error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// LLM çıktısını temizle — TTS gerçek metin okur, markdown yapısı
    /// bozar. Sayısal yüzdeleri ve $ işaretini Türkçe okunabilir kıl.
    static func clean(text: String) -> String {
        var s = text

        // 1. Markdown başlıkları, vurgular
        s = s.replacingOccurrences(of: "###", with: "")
        s = s.replacingOccurrences(of: "##", with: "")
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: "`", with: "")

        // 2. Linkleri at — TTS URL okumaz
        if let regex = try? NSRegularExpression(pattern: "https?://\\S+") {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }

        // 3. Emoji + ikon karakterlerini at (TTS bazılarını sözcükleştiriyor)
        if let regex = try? NSRegularExpression(pattern: "[\\u{1F300}-\\u{1F9FF}\\u{2600}-\\u{27BF}]") {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }

        // 4. $ → "dolar"
        s = s.replacingOccurrences(of: "$", with: " dolar ")

        // 5. Fazla boşlukları kırp
        s = s.replacingOccurrences(of: "\n", with: ". ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ArgusTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.deactivateAudioSession()
        }
    }
}
