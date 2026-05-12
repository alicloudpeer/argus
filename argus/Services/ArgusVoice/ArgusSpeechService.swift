import Foundation
import Speech
import AVFoundation
import Combine

/// 🎤 THE EARS OF ARGUS 🎤
/// Handles real-time speech recognition using SFSpeechRecognizer.
/// Designed for low-latency command parsing.
///
/// 2026-05-12 düzeltmesi:
///   * Sınıf @MainActor'a alındı — `@Published recognizedText/isRecording/
///     audioLevel/errorMsg` mutasyonları artık her zaman main thread'de.
///   * SFSpeechRecognizer.recognitionTask callback'i background queue'da
///     çağrılıyordu; içeride `self.recognizedText = ...` ve
///     `self.stopRecording()` doğrudan yazıyordu → SwiftUI sessiz UI
///     freeze. Şimdi callback `Task { @MainActor in ... }` ile main'e
///     marshall ediliyor.
///   * `stopRecording()` sonundaki `AVAudioSession.setActive(false)`
///     blocking call main'i 0.5-2sn dondurabiliyordu — background
///     queue'ya alındı.
@MainActor
final class ArgusSpeechService: ObservableObject {
    static let shared = ArgusSpeechService()

    @Published var recognizedText: String = ""
    @Published var isRecording = false
    @Published var errorMsg: String? = nil
    @Published var audioLevel: Float = 0.0 // For Waveform Visualization

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")) // Türkçe Odağı
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private init() {
        // Authorization will be requested lazily when startRecording is called
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    print("🎤 Argus Speech: Authorized")
                case .denied:
                    self.errorMsg = "Mikrofon izni reddedildi."
                case .restricted:
                    self.errorMsg = "Konuşma tanıma kısıtlı."
                case .notDetermined:
                    self.errorMsg = "İzin bekleniyor."
                @unknown default:
                    self.errorMsg = "Bilinmeyen durum."
                }
            }
        }
    }

    func startRecording() throws {
        // Request authorization first (lazy)
        requestAuthorization()

        // Cancel previous task if any
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        let inputNode = audioEngine.inputNode
        guard let request = recognitionRequest else {
            print("🛑 ArgusSpeech: Unable to create request")
            throw NSError(domain: "ArgusSpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create speech recognition request"])
        }

        request.shouldReportPartialResults = true

        // Tap for Waveform Visualization + audio buffer feed
        inputNode.removeTap(onBus: 0) // Safety
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate Audio Level (RMS) — pahalı değil ama main'e push lazım.
            let channelData = buffer.floatChannelData?[0]
            let channelDataValue = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
            let rms = sqrt(channelDataValue.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
            let avgPower = 20 * log10(rms)
            let normalized = min(max((avgPower + 50) / 50, 0), 1)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        // 2026-05-12: Recognition callback artık main thread'e marshall
        // ediliyor. Aksi halde @Published yazımı background thread'den
        // SwiftUI freeze tetikliyordu.
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var isFinal = false

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                }

                if error != nil || isFinal {
                    self.stopRecording()
                }
            }
        }

        isRecording = true
        recognizedText = ""
        errorMsg = nil
        print("🎤 Argus Speech: Recording Started")
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        isRecording = false
        print("🎤 Argus Speech: Recording Stopped")

        // 2026-05-12: setActive(false) bazen 0.5-2sn block ediyordu —
        // main thread dondurmasın diye utility queue'ya gönder.
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
