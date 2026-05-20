import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    // MARK: - General
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var isDarkMode: Bool {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode") }
    }
    @Published var currency: String {
        didSet { UserDefaults.standard.set(currency, forKey: "currency") }
    }
    
    // MARK: - Trading Preferences
    @Published var defaultTradeAmountPercentage: Double {
        didSet { UserDefaults.standard.set(defaultTradeAmountPercentage, forKey: "defaultTradeAmountPercentage") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // MARK: - Trading Fees (User-Configurable)
    /// BIST komisyon oranı (%). UI 0–1.5 aralığında gösterir, kayıt ondalık
    /// olarak saklanır. Default 0 (Midas/Garanti gibi sıfır komisyon yaygın).
    @Published var bistCommissionPercent: Double {
        didSet { UserDefaults.standard.bistCommissionRate = bistCommissionPercent / 100.0 }
    }
    /// US/Global komisyon oranı (%). Default 0 (Alpaca/IBKR Lite komisyonsuz).
    @Published var globalCommissionPercent: Double {
        didSet { UserDefaults.standard.globalCommissionRate = globalCommissionPercent / 100.0 }
    }
    /// BIST hisse stopajı (%). Default 0 (2026 itibariyle istisna aktif).
    @Published var bistWithholdingPercent: Double {
        didSet { UserDefaults.standard.bistWithholdingRate = bistWithholdingPercent / 100.0 }
    }
    
    // MARK: - Privacy & Security
    @Published var isFaceIDEnabled: Bool {
        didSet { UserDefaults.standard.set(isFaceIDEnabled, forKey: "isFaceIDEnabled") }
    }
    @Published var shareAnalytics: Bool {
        didSet { UserDefaults.standard.set(shareAnalytics, forKey: "shareAnalytics") }
    }
    
    // MARK: - AI Engine Preferences
    @Published var riskTolerance: RiskTolerance {
        didSet { UserDefaults.standard.set(riskTolerance.rawValue, forKey: "riskTolerance") }
    }
    @Published var maxOpenPositions: Int {
        didSet { UserDefaults.standard.set(maxOpenPositions, forKey: "maxOpenPositions") }
    }
    @Published var aiStrategies: [String: Bool] {
        didSet { UserDefaults.standard.set(aiStrategies, forKey: "aiStrategies") }
    }
    
    // Data Collection (User Preference)
    @Published var isDataCollectionEnabled: Bool {
        didSet { UserDefaults.standard.set(isDataCollectionEnabled, forKey: "isDataCollectionEnabled") }
    }
    
    // Phoenix Timeframe Preference
    @Published var phoenixTimeframe: PhoenixTimeframe {
        didSet { UserDefaults.standard.set(phoenixTimeframe.rawValue, forKey: "phoenixTimeframe") }
    }
    
    // MARK: - API
    // MARK: - API (Linked to KeyStore)
    @Published var apiKey: String = ""
    @Published var fredApiKey: String = "" {
        didSet {
            Task { @MainActor in
                APIKeyStore.shared.setKey(provider: .fred, key: fredApiKey)
            }
        }
    }
    @Published var isApiKeyVisible: Bool = false
    
    // MARK: - Diagnostic Snapshot (Faz 2.3: SettingsView'dan taşındı)
    // refreshSnapshots() bu field'ları doldurur, View bunlardan okur. Singleton
    // erişimi View'dan çıkarıldı; testlerde VM mock'lanabilir.

    @Published var chironTradeCount: Int = 0
    @Published var chironWinRate: Int = 0
    @Published var alkindusPendingCount: Int = 0
    @Published var tradeBlockReasons: [String] = []
    @Published var policyMode: String = "NORMAL"
    @Published var marketOpenGlobal: Bool = false
    @Published var marketOpenBist: Bool = false
    @Published var watchlistCount: Int = 0
    @Published var aetherCurrent: Double = 0
    @Published var aetherVelocity: Double = 0
    @Published var aetherSignal: String = "—"
    @Published var aetherCrossingMsg: String? = nil
    @Published var regimeTransitionDirection: String = "STABLE"
    @Published var regimeTransitionSummary: String? = nil
    @Published var regimeEvidence: [String] = []
    @Published var regimeConfidence: Double = 0
    @Published var pulseSummary: String = "Veri yok"
    @Published var pulseIntensity: String = "DORMANT"
    @Published var pulseDirection: String = "MIXED"
    @Published var pulseMoveRate: Double = 0
    @Published var isRunningCalibration: Bool = false
    @Published var calibrationFlash: String? = nil

    // MARK: - Legal Documents (Static Data)
    // LegalDocument struct is defined in Models.swift
    let privacyPolicy = LegalDocument(title: "Gizlilik Politikası", content: "Bu gizlilik politikası, kişisel verilerinizin nasıl toplandığını, kullanıldığını ve korunduğunu açıklar. Uygulamamızı kullanarak, verilerinizin bu politikaya uygun olarak işlenmesini kabul etmiş olursunuz.\n\n1. Veri Toplama: Uygulama, işlem geçmişinizi ve tercihlerinizi yerel cihazınızda saklar.\n2. Üçüncü Taraflar: Piyasa verileri için üçüncü taraf API sağlayıcıları (örn. Finnhub) kullanılmaktadır.\n3. Güvenlik: Verileriniz endüstri standardı şifreleme yöntemleri ile korunmaktadır.")
    
    let termsOfUse = LegalDocument(title: "Kullanım Koşulları", content: "Bu uygulamayı indirerek ve kullanarak aşağıdaki koşulları kabul etmiş sayılırsınız.\n\n1. Amaç: Bu uygulama sadece eğitim ve simülasyon amaçlıdır. Gerçek para ile işlem yapılmaz.\n2. Sorumluluk Reddi: Uygulama tarafından sağlanan sinyaller ve veriler yatırım tavsiyesi değildir. Finansal kayıplardan geliştirici sorumlu tutulamaz.\n3. Değişiklikler: Geliştirici, uygulama özelliklerini önceden haber vermeksizin değiştirme hakkını saklı tutar.")
    
    let riskDisclosure = LegalDocument(title: "Risk Bildirimi", content: "Finansal piyasalarda işlem yapmak yüksek risk içerir ve tüm yatırımcılar için uygun olmayabilir.\n\nKaldıraçlı işlem yapmak, yatırdığınız sermayenin tamamını veya daha fazlasını kaybetmenize neden olabilir. İşlem yapmaya karar vermeden önce yatırım hedeflerinizi, deneyim seviyenizi ve risk iştahınızı dikkatlice değerlendirmelisiniz.\n\nBu uygulama bir 'Demo' ortamıdır ve gerçek piyasa koşullarını birebir yansıtmayabilir.")
    
    init() {
        self.language = UserDefaults.standard.string(forKey: "language") ?? "tr"
        self.isDarkMode = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
        self.currency = UserDefaults.standard.string(forKey: "currency") ?? "USD"
        
        let savedTradeAmount = UserDefaults.standard.double(forKey: "defaultTradeAmountPercentage")
        self.defaultTradeAmountPercentage = savedTradeAmount == 0 ? 10.0 : savedTradeAmount

        // Komisyon oranları UserDefaults'ta ondalık (0.0015), UI'da % (0.15).
        self.bistCommissionPercent = UserDefaults.standard.bistCommissionRate * 100.0
        self.globalCommissionPercent = UserDefaults.standard.globalCommissionRate * 100.0
        self.bistWithholdingPercent = UserDefaults.standard.bistWithholdingRate * 100.0

        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.isFaceIDEnabled = UserDefaults.standard.bool(forKey: "isFaceIDEnabled")
        self.shareAnalytics = UserDefaults.standard.object(forKey: "shareAnalytics") as? Bool ?? true
        
        // AI Init
        let savedRisk = UserDefaults.standard.string(forKey: "riskTolerance") ?? "Orta"
        self.riskTolerance = RiskTolerance(rawValue: savedRisk) ?? .medium
        
        let savedMaxPos = UserDefaults.standard.integer(forKey: "maxOpenPositions")
        self.maxOpenPositions = savedMaxPos == 0 ? 300 : savedMaxPos
        
        self.aiStrategies = UserDefaults.standard.dictionary(forKey: "aiStrategies") as? [String: Bool] ?? [
            "Trend Takipçisi": true,
            "Ortalamaya Dönüş": true,
            "Kırılım Yakalayıcı": false
        ]
        
        self.isDataCollectionEnabled = UserDefaults.standard.object(forKey: "isDataCollectionEnabled") as? Bool ?? true
        
        // Phoenix Init
        let savedPTF = UserDefaults.standard.string(forKey: "phoenixTimeframe") ?? "Otomatik"
        self.phoenixTimeframe = PhoenixTimeframe(rawValue: savedPTF) ?? .auto
        
        // KeyStore Entegrasyonu (Safe Init)
        self.loadKeys()
        
        // Use Closure instead of Selector to avoid @objc issues during init
        NotificationCenter.default.addObserver(forName: .argusKeyStoreDidUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.loadKeys()
        }
        
    }

    func loadKeys() {
        Task { @MainActor in
            if let fred = APIKeyStore.shared.getKey(for: .fred) {
                if self.fredApiKey != fred { self.fredApiKey = fred }
            }
        }
    }

    // MARK: - Diagnostic Refresh (Faz 2.3: SettingsView'dan taşındı)

    /// Chiron & Alkindus özet verilerini tazele. View bu metodu `.task` ile çağırır.
    @MainActor
    func refreshSnapshots() async {
        // Chiron istatistikleri — iki kaynak: ChironDataLake + PortfolioStore.
        // Eski import edilmemiş 92 trade Chiron dosyasında olmadığı için
        // PortfolioStore'dan da okuyup max(chiron, portfolio) alıyoruz.
        let chironTrades = await ChironDataLakeService.shared.loadAllTradeHistory()
        let portfolioClosed = PortfolioStore.shared.trades.filter { !$0.isOpen && $0.exitPrice != nil }
        let pending = await AlkindusMemoryStore.shared.loadPendingObservations().count
        let velocity = await AetherVelocityEngine.shared.analyze()

        let watchlist = WatchlistStore.shared.items
        let quotes = MarketDataStore.shared.quotes.compactMapValues { $0.value }
        let candles = MarketDataStore.shared.candles.compactMapValues { $0.value }
        let globalMomentum = await MarketMomentumGate.shared.assessGlobal(
            quotes: quotes, candles: candles, watchlistSymbols: watchlist
        )
        let bistMomentum = await MarketMomentumGate.shared.assessBist(
            quotes: quotes, candles: candles, watchlistSymbols: watchlist
        )
        let hermesPos = HermesEventStore.shared.countHighImpactEvents(polarity: .positive)
        let hermesNeg = HermesEventStore.shared.countHighImpactEvents(polarity: .negative)
        let pulse = await WatchlistPulseMonitor.shared.assess(candlesBySymbol: candles)

        let transition = await AetherRegimeTransitionDetector.shared.analyze(
            velocity: velocity,
            recentPositiveHermesEvents: hermesPos,
            recentNegativeHermesEvents: hermesNeg,
            globalMomentumLevel: globalMomentum.level,
            bistMomentumLevel: bistMomentum.level,
            watchlistPulse: pulse
        )

        let tradeCount = max(chironTrades.count, portfolioClosed.count)
        let winRate: Int = {
            if !portfolioClosed.isEmpty {
                let wins = portfolioClosed.filter { ($0.exitPrice ?? 0) > $0.entryPrice }.count
                return Int((Double(wins) / Double(portfolioClosed.count)) * 100)
            }
            if !chironTrades.isEmpty {
                let wins = chironTrades.filter { $0.pnlPercent > 0 }.count
                return Int((Double(wins) / Double(chironTrades.count)) * 100)
            }
            return 0
        }()

        let policy = RiskEscapePolicy.from(aetherScore: velocity.currentScore)
        let globalOpen = MarketStatusService.shared.canTrade(for: .global)
        let bistOpen   = MarketStatusService.shared.canTrade(for: .bist)
        let watchCount = WatchlistStore.shared.items.count

        var reasons: [String] = []
        if !AutoPilotStore.shared.isAutoPilotEnabled {
            reasons.append("Otopilot kapalı — yukarıdaki toggle'dan aç")
        }
        if policy.mode != .normal {
            reasons.append("Risk politikası \(policy.mode.rawValue) — Aether \(Int(velocity.currentScore)) (riskli alım bloke)")
        }
        if !globalOpen && !bistOpen {
            reasons.append("Tüm piyasalar kapalı — açılış saatini bekliyor")
        }
        if watchCount == 0 {
            reasons.append("İzleme listesi boş — sembol ekle")
        }

        self.chironTradeCount = tradeCount
        self.chironWinRate = winRate
        self.alkindusPendingCount = pending
        self.aetherCurrent = velocity.currentScore
        self.aetherVelocity = velocity.velocity
        self.aetherSignal = velocity.signal.rawValue
        self.aetherCrossingMsg = velocity.crossingAlert?.description
        self.regimeTransitionDirection = transition.direction.rawValue
        self.regimeTransitionSummary = transition.direction == .stable ? nil : transition.summary
        self.regimeEvidence = transition.evidence
        self.regimeConfidence = transition.confidence
        self.pulseSummary = pulse.summary
        self.pulseIntensity = pulse.intensity.rawValue
        self.pulseDirection = pulse.direction.rawValue
        self.pulseMoveRate = pulse.avgMoveRate
        self.policyMode = policy.mode.rawValue
        self.marketOpenGlobal = globalOpen
        self.marketOpenBist = bistOpen
        self.watchlistCount = watchCount
        self.tradeBlockReasons = reasons
    }

    /// Alkindus kalibrasyonu manuel tetikle.
    @MainActor
    func runCalibrationNow() {
        guard !isRunningCalibration else { return }
        isRunningCalibration = true
        calibrationFlash = nil

        Task { @MainActor in
            await AlkindusCalibrationEngine.shared.periodicMatureCheck()
            await refreshSnapshots()

            withAnimation { self.calibrationFlash = "Güncellendi" }
            self.isRunningCalibration = false

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { self.calibrationFlash = nil }
        }
    }
}

enum RiskTolerance: String, CaseIterable, Identifiable {
    case low = "Düşük"
    case medium = "Orta"
    case high = "Yüksek"
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .low: return "risk_low".localized()
        case .medium: return "risk_medium".localized()
        case .high: return "risk_high".localized()
        }
    }
}
