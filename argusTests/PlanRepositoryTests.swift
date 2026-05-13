import XCTest
@testable import argus

@MainActor
final class PlanRepositoryTests: XCTestCase {

    let repo = PlanRepository.shared
    private let persistenceKey = "ArgusPositionPlansVortex"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        repo.plans.removeAll()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        repo.plans.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeTrade(
        id: UUID = UUID(),
        symbol: String = "AAPL",
        entryPrice: Double = 150.0,
        quantity: Double = 10.0,
        isOpen: Bool = true
    ) -> Trade {
        Trade(
            id: id,
            symbol: symbol,
            entryPrice: entryPrice,
            quantity: quantity,
            entryDate: Date(),
            isOpen: isOpen
        )
    }

    private func makeDecision(
        symbol: String = "AAPL",
        action: ArgusAction = .accumulate,
        confidence: Double = 0.75
    ) -> ArgusGrandDecision {
        let orion = CouncilDecision(
            symbol: symbol,
            action: .buy,
            netSupport: 0.5,
            approveWeight: 0.7,
            vetoWeight: 0.2,
            isStrongSignal: true,
            isWeakSignal: false,
            winningProposal: nil,
            allProposals: [],
            votes: [],
            vetoReasons: [],
            timestamp: Date()
        )
        let aether = AetherDecision(
            stance: .riskOn,
            marketMode: .neutral,
            netSupport: 0.6,
            isStrongSignal: false,
            winningProposal: nil,
            votes: [],
            warnings: [],
            timestamp: Date()
        )
        return ArgusGrandDecision(
            id: UUID(),
            symbol: symbol,
            action: action,
            strength: .normal,
            confidence: confidence,
            reasoning: "Test decision",
            contributors: [],
            vetoes: [],
            orionDecision: orion,
            atlasDecision: nil,
            aetherDecision: aether,
            hermesDecision: nil,
            phoenixAdvice: nil,
            orionDetails: nil,
            financialDetails: nil,
            orionV2TotalScore: nil,
            bistDetails: nil,
            patterns: nil,
            kellyMultiplier: 1.0,
            timestamp: Date()
        )
    }

    // MARK: - Create

    func testCreatePlan_ValidDecision_AddsToPlansDictionary() {
        let trade = makeTrade()
        let decision = makeDecision()

        let plan = repo.createPlan(for: trade, decision: decision)

        XCTAssertNotNil(plan)
        XCTAssertTrue(repo.hasPlan(for: trade.id))
        XCTAssertEqual(repo.plans.count, 1)
    }

    func testCreatePlan_NeutralDecision_ReturnsNilAndRejects() {
        let trade = makeTrade()
        let decision = makeDecision(action: .neutral)

        let plan = repo.createPlan(for: trade, decision: decision)

        XCTAssertNil(plan)
        XCTAssertFalse(repo.hasPlan(for: trade.id))
        XCTAssertEqual(repo.plans.count, 0)
    }

    // MARK: - Read

    func testGetPlan_ExistingTrade_ReturnsPlan() {
        let trade = makeTrade()
        let decision = makeDecision()
        _ = repo.createPlan(for: trade, decision: decision)

        let retrieved = repo.getPlan(for: trade.id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.symbol, "AAPL")
    }

    func testGetPlan_UnknownTradeId_ReturnsNil() {
        let result = repo.getPlan(for: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Update

    func testUpdatePlanStatus_ChangesStatus() {
        let trade = makeTrade()
        _ = repo.createPlan(for: trade, decision: makeDecision())

        repo.updatePlanStatus(tradeId: trade.id, status: .paused)

        let plan = repo.getPlan(for: trade.id)
        XCTAssertEqual(plan?.status, .paused)
    }

    func testCompletePlan_SetsCompletedStatus() {
        let trade = makeTrade()
        _ = repo.createPlan(for: trade, decision: makeDecision())

        repo.completePlan(tradeId: trade.id)

        let plan = repo.getPlan(for: trade.id)
        XCTAssertEqual(plan?.status, .completed)
    }

    func testMarkStepCompleted_AddsStepToExecutedList() {
        let trade = makeTrade()
        let created = repo.createPlan(for: trade, decision: makeDecision())
        guard let stepId = created?.bullishScenario.steps.first?.id else {
            return
        }

        repo.markStepCompleted(tradeId: trade.id, stepId: stepId)

        let plan = repo.getPlan(for: trade.id)
        XCTAssertTrue(plan?.executedSteps.contains(stepId) ?? false)
    }

    // MARK: - Persistence

    func testPersistRoundtrip_PlansPreserved() {
        let trade = makeTrade(symbol: "GOOG")
        _ = repo.createPlan(for: trade, decision: makeDecision(symbol: "GOOG"))
        XCTAssertEqual(repo.plans.count, 1)

        repo.plans.removeAll()
        XCTAssertEqual(repo.plans.count, 0)

        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let loaded = try? JSONDecoder().decode([PositionPlan].self, from: data) {
            for plan in loaded {
                repo.plans[plan.tradeId] = plan
            }
        }

        XCTAssertEqual(repo.plans.count, 1)
        XCTAssertEqual(repo.plans.values.first?.symbol, "GOOG")
    }

    // MARK: - Sync With Portfolio

    func testSyncWithPortfolio_CreatesMissingPlans() {
        let trade1 = makeTrade(symbol: "MSFT")
        let trade2 = makeTrade(symbol: "TSLA")

        repo.syncWithPortfolio(
            trades: [trade1, trade2],
            grandDecisions: [:]
        )

        XCTAssertEqual(repo.plans.count, 2)
        XCTAssertTrue(repo.hasPlan(for: trade1.id))
        XCTAssertTrue(repo.hasPlan(for: trade2.id))
    }

    func testSyncWithPortfolio_SkipsExistingPlans() {
        let trade = makeTrade(symbol: "NVDA")
        _ = repo.createPlan(for: trade, decision: makeDecision(symbol: "NVDA"))
        XCTAssertEqual(repo.plans.count, 1)

        repo.syncWithPortfolio(
            trades: [trade],
            grandDecisions: [:]
        )

        XCTAssertEqual(repo.plans.count, 1)
    }

    func testSyncWithPortfolio_IgnoresClosedTrades() {
        let closedTrade = makeTrade(symbol: "META", isOpen: false)

        repo.syncWithPortfolio(
            trades: [closedTrade],
            grandDecisions: [:]
        )

        XCTAssertEqual(repo.plans.count, 0)
    }
}
