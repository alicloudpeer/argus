import XCTest
@testable import argus

/// SettingsViewModel davranış kontratı testleri.
///
/// Kapsam:
/// - UserDefaults-backed preferences round-trip (set → didSet → UserDefaults)
/// - Trading fee transformation (UI yüzde ↔ UserDefaults ondalık)
/// - AI strategies dictionary defaults
/// - Diagnostic field initial state (Faz 2.3'te ViewModel'e taşındı)
///
/// Kapsam dışı:
/// - `refreshSnapshots()` — 13+ singleton'a bağımlı (ChironDataLake, PortfolioStore,
///   AlkindusMemoryStore, AetherVelocityEngine, vb.) — mock altyapısı kurulduğunda eklenir
/// - `runCalibrationNow()` — AlkindusCalibrationEngine singleton
/// - Keychain bağımlı `loadKeys()` / `fredApiKey` setter
@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Setup

    /// Her test sıfır UserDefaults state ile başlasın diye bilinen anahtarları temizle.
    /// Lokal UserDefaults standard suite'i kullanılıyor — TestSuite yarın eklenirse buraya enjekte edilir.
    override func setUp() async throws {
        try await super.setUp()
        let keys = [
            "language", "isDarkMode", "currency",
            "defaultTradeAmountPercentage", "notificationsEnabled",
            "isFaceIDEnabled", "shareAnalytics",
            "riskTolerance", "maxOpenPositions", "aiStrategies",
            "isDataCollectionEnabled", "phoenixTimeframe"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Fee anahtarları ayrı extension üzerinden saklanıyor; default fallback'leri reset et.
        UserDefaults.standard.bistCommissionRate = 0.0
        UserDefaults.standard.globalCommissionRate = 0.0
        UserDefaults.standard.bistWithholdingRate = 0.0
    }

    // MARK: - Initial Defaults

    /// Boş UserDefaults durumunda doğru fallback'ler init edilmeli.
    func test_init_defaultsAreSensibleWhenUserDefaultsEmpty() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.language, "tr")
        XCTAssertTrue(vm.isDarkMode, "Default tema karanlık olmalı")
        XCTAssertEqual(vm.currency, "USD")
        XCTAssertEqual(vm.defaultTradeAmountPercentage, 10.0)
        XCTAssertTrue(vm.notificationsEnabled)
        XCTAssertFalse(vm.isFaceIDEnabled)
        XCTAssertTrue(vm.shareAnalytics)
        XCTAssertEqual(vm.riskTolerance, .medium)
        XCTAssertEqual(vm.maxOpenPositions, 300)
        XCTAssertTrue(vm.isDataCollectionEnabled)
        XCTAssertEqual(vm.phoenixTimeframe, .auto)
        XCTAssertEqual(vm.bistCommissionPercent, 0.0)
        XCTAssertEqual(vm.globalCommissionPercent, 0.0)
        XCTAssertEqual(vm.bistWithholdingPercent, 0.0)
    }

    /// Önceden yazılmış UserDefaults değerleri init'te okunmalı.
    func test_init_readsPersistedValues() {
        UserDefaults.standard.set("en", forKey: "language")
        UserDefaults.standard.set(false, forKey: "isDarkMode")
        UserDefaults.standard.set("EUR", forKey: "currency")
        UserDefaults.standard.set(25.0, forKey: "defaultTradeAmountPercentage")
        UserDefaults.standard.set(50, forKey: "maxOpenPositions")

        let vm = SettingsViewModel()

        XCTAssertEqual(vm.language, "en")
        XCTAssertFalse(vm.isDarkMode)
        XCTAssertEqual(vm.currency, "EUR")
        XCTAssertEqual(vm.defaultTradeAmountPercentage, 25.0)
        XCTAssertEqual(vm.maxOpenPositions, 50)
    }

    // MARK: - Preferences Round-Trip

    /// language değişimi UserDefaults'a yazılmalı (didSet kontratı).
    func test_languageChange_persistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.language = "en"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), "en")
    }

    func test_isDarkModeChange_persistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.isDarkMode = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: "isDarkMode") as? Bool, false)
    }

    func test_currencyChange_persistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.currency = "EUR"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currency"), "EUR")
    }

    func test_maxOpenPositionsChange_persistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.maxOpenPositions = 150
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "maxOpenPositions"), 150)
    }

    // MARK: - Trading Fee Transformations

    /// UI 0.15 (yüzde) → UserDefaults 0.0015 (ondalık) → init'te tekrar 0.15.
    func test_bistCommissionPercent_uiToDecimalRoundTrip() {
        let vm1 = SettingsViewModel()
        vm1.bistCommissionPercent = 0.15

        // UserDefaults ondalık olarak saklamalı
        XCTAssertEqual(UserDefaults.standard.bistCommissionRate, 0.0015, accuracy: 1e-9)

        // Yeni VM aynı değeri yüzde olarak göstermeli
        let vm2 = SettingsViewModel()
        XCTAssertEqual(vm2.bistCommissionPercent, 0.15, accuracy: 1e-9)
    }

    func test_globalCommissionPercent_uiToDecimalRoundTrip() {
        let vm1 = SettingsViewModel()
        vm1.globalCommissionPercent = 0.50

        XCTAssertEqual(UserDefaults.standard.globalCommissionRate, 0.0050, accuracy: 1e-9)

        let vm2 = SettingsViewModel()
        XCTAssertEqual(vm2.globalCommissionPercent, 0.50, accuracy: 1e-9)
    }

    func test_bistWithholdingPercent_uiToDecimalRoundTrip() {
        let vm1 = SettingsViewModel()
        vm1.bistWithholdingPercent = 10.0

        XCTAssertEqual(UserDefaults.standard.bistWithholdingRate, 0.10, accuracy: 1e-9)

        let vm2 = SettingsViewModel()
        XCTAssertEqual(vm2.bistWithholdingPercent, 10.0, accuracy: 1e-9)
    }

    /// Sıfır değer kabul edilebilir olmalı (Midas/Garanti gibi komisyon yok).
    func test_bistCommissionPercent_zeroIsValid() {
        let vm = SettingsViewModel()
        vm.bistCommissionPercent = 0.0
        XCTAssertEqual(UserDefaults.standard.bistCommissionRate, 0.0)
        XCTAssertEqual(vm.bistCommissionPercent, 0.0)
    }

    // MARK: - AI Strategies

    /// Boş UserDefaults durumunda 3 default strateji init edilmeli.
    func test_aiStrategies_defaultsContainExpectedKeys() {
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.aiStrategies["Trend Takipçisi"], true)
        XCTAssertEqual(vm.aiStrategies["Ortalamaya Dönüş"], true)
        XCTAssertEqual(vm.aiStrategies["Kırılım Yakalayıcı"], false)
    }

    /// Strateji değişimi UserDefaults'a yazılmalı.
    func test_aiStrategiesChange_persists() {
        let vm = SettingsViewModel()
        vm.aiStrategies["Trend Takipçisi"] = false
        let saved = UserDefaults.standard.dictionary(forKey: "aiStrategies") as? [String: Bool]
        XCTAssertEqual(saved?["Trend Takipçisi"], false)
    }

    // MARK: - Risk Tolerance

    func test_riskTolerance_persists() {
        let vm = SettingsViewModel()
        vm.riskTolerance = .high
        XCTAssertEqual(UserDefaults.standard.string(forKey: "riskTolerance"), "Yüksek")
    }

    func test_riskTolerance_invalidStringFallsBackToMedium() {
        UserDefaults.standard.set("Garip", forKey: "riskTolerance")
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.riskTolerance, .medium)
    }

    // MARK: - Diagnostic Initial State (Faz 2.3 — taşınan field'lar)

    /// refreshSnapshots() çağrılmadan önce diagnostic field'lar makul default'larda olmalı.
    /// View ilk render'da "Veri yok" benzeri gösterim için bu varsayılanlara güvenir.
    func test_diagnosticFields_haveSensibleInitialState() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.chironTradeCount, 0)
        XCTAssertEqual(vm.chironWinRate, 0)
        XCTAssertEqual(vm.alkindusPendingCount, 0)
        XCTAssertEqual(vm.tradeBlockReasons, [])
        XCTAssertEqual(vm.policyMode, "NORMAL")
        XCTAssertFalse(vm.marketOpenGlobal)
        XCTAssertFalse(vm.marketOpenBist)
        XCTAssertEqual(vm.watchlistCount, 0)
        XCTAssertEqual(vm.aetherCurrent, 0)
        XCTAssertEqual(vm.aetherVelocity, 0)
        XCTAssertEqual(vm.aetherSignal, "—")
        XCTAssertNil(vm.aetherCrossingMsg)
        XCTAssertEqual(vm.regimeTransitionDirection, "STABLE")
        XCTAssertNil(vm.regimeTransitionSummary)
        XCTAssertEqual(vm.regimeEvidence, [])
        XCTAssertEqual(vm.regimeConfidence, 0)
        XCTAssertEqual(vm.pulseSummary, "Veri yok")
        XCTAssertEqual(vm.pulseIntensity, "DORMANT")
        XCTAssertEqual(vm.pulseDirection, "MIXED")
        XCTAssertEqual(vm.pulseMoveRate, 0)
        XCTAssertFalse(vm.isRunningCalibration)
        XCTAssertNil(vm.calibrationFlash)
    }

    // MARK: - Legal Documents

    /// Yasal belgeler statik veri — boş veya nil olmamalı.
    func test_legalDocuments_haveContent() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.privacyPolicy.title.isEmpty)
        XCTAssertFalse(vm.privacyPolicy.content.isEmpty)
        XCTAssertFalse(vm.termsOfUse.content.isEmpty)
        XCTAssertFalse(vm.riskDisclosure.content.isEmpty)
    }
}
