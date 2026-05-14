import XCTest
@testable import argus

final class RiskEscapePolicyTests: XCTestCase {

    func testDeepRiskOffPolicy() {
        let policy = RiskEscapePolicy.from(aetherScore: 10)

        XCTAssertEqual(policy.mode, .deepRiskOff)
        XCTAssertTrue(policy.blockRiskyBuys)
        XCTAssertTrue(policy.forceSafeOnlyBuys)
        XCTAssertEqual(policy.minimumTrimPercent, RiskBudgetConfig.deepRiskOffTrimPercent)
    }

    func testRiskOffPolicy() {
        // Faz 0 Task 6 (2026-05-13): paper-tuned eşikler geri alındı.
        // Eski (paper): deepRiskOff ≤ 15, riskOff ≤ 25 — score 20 riskOff'a düşerdi.
        // Yeni (dürüst): deepRiskOff ≤ 25, riskOff ≤ 40 — riskOff aralığı 26..40.
        // Test örneklemi 30'a çekildi (yeni riskOff bandının ortası).
        let policy = RiskEscapePolicy.from(aetherScore: 30)

        XCTAssertEqual(policy.mode, .riskOff)
        XCTAssertTrue(policy.blockRiskyBuys)
        XCTAssertTrue(policy.forceSafeOnlyBuys)
        XCTAssertEqual(policy.minimumTrimPercent, RiskBudgetConfig.riskOffTrimPercent)
    }

    func testNormalPolicy() {
        let policy = RiskEscapePolicy.from(aetherScore: 55)

        XCTAssertEqual(policy.mode, .normal)
        XCTAssertFalse(policy.blockRiskyBuys)
        XCTAssertFalse(policy.forceSafeOnlyBuys)
        XCTAssertEqual(policy.minimumTrimPercent, 0)
    }

    func testDynamicMaxRiskRByAetherScore() {
        // Faz 0 Task 6 (2026-05-13): paper-tuned 2x scale geri alındı.
        // Eski (paper): 1.0 / 3.0 / 20.0 (çöküşte bile 1R girişi).
        // Yeni (dürüst): 0.0 / 1.5 / 10.0 — çöküşte hard-stop, üst seviyeler yarıya.
        XCTAssertEqual(RiskBudgetConfig.dynamicMaxRiskR(aetherScore: 10), 0.0, accuracy: 0.0001)
        XCTAssertEqual(RiskBudgetConfig.dynamicMaxRiskR(aetherScore: 30), 1.5, accuracy: 0.0001)
        XCTAssertEqual(RiskBudgetConfig.dynamicMaxRiskR(aetherScore: 80), 10.0, accuracy: 0.0001)
    }
}
