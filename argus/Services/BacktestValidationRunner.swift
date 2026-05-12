import Foundation
import SwiftUI
import Combine

// MARK: - Per-symbol result

struct ValidationSymbolResult: Identifiable {
    let id = UUID()
    let symbol: String
    let strategy: String

    let totalReturn: Double
    let benchmarkReturn: Double      // Buy & Hold
    let alpha: Double                // totalReturn - benchmarkReturn

    let winRate: Double
    let totalTrades: Int
    let maxDrawdown: Double
    let sharpeRatio: Double
    let profitFactor: Double

    let walkForwardDegradation: Double?  // pozitif = overfitting sinyali

    // Action distribution (0.0–1.0 oranlar)
    let buyRatio: Double
    let sellRatio: Double
    let holdRatio: Double

    let candleCount: Int
    let error: String?

    var isOverfit: Bool { (walkForwardDegradation ?? 0) > 20 }

    var returnColor: Color {
        totalReturn >= 0 ? DesignTokens.Colors.success : DesignTokens.Colors.error
    }

    var alphaColor: Color {
        alpha >= 0 ? DesignTokens.Colors.success : DesignTokens.Colors.error
    }
}

// MARK: - Runner

@MainActor
final class BacktestValidationRunner: ObservableObject {

    static let shared = BacktestValidationRunner()

    @Published var results: [ValidationSymbolResult] = []
    @Published var isRunning = false
    @Published var progress: Double = 0       // 0.0–1.0
    @Published var currentSymbol: String = ""
    @Published var errorMessage: String?

    private let bistSymbols = ["THYAO.IS", "ASELS.IS", "GARAN.IS", "EREGL.IS", "TUPRS.IS"]
    private let usSymbols   = ["AAPL", "MSFT", "NVDA", "GOOGL", "AMZN"]

    private var allSymbols: [String] { bistSymbols + usSymbols }

    private init() {}

    func run() {
        guard !isRunning else { return }
        isRunning = true
        results = []
        progress = 0
        errorMessage = nil

        Task {
            await runValidation()
            isRunning = false
        }
    }

    private func runValidation() async {
        let symbols = allSymbols
        let config = BacktestConfig(
            initialCapital: 10_000,
            strategy: .argusStandard,
            stopLossPct: 0.07,
            executionModel: .realistic
        )
        let benchConfig = BacktestConfig(
            initialCapital: 10_000,
            strategy: .buyAndHold,
            stopLossPct: 0.07,
            executionModel: .realistic
        )

        for (i, symbol) in symbols.enumerated() {
            currentSymbol = symbol
            progress = Double(i) / Double(symbols.count)

            let result = await validateSymbol(symbol: symbol, config: config, benchConfig: benchConfig)
            results.append(result)
        }

        progress = 1.0
        currentSymbol = ""
    }

    private func validateSymbol(
        symbol: String,
        config: BacktestConfig,
        benchConfig: BacktestConfig
    ) async -> ValidationSymbolResult {
        let candleValue = await MarketDataStore.shared.ensureCandles(symbol: symbol, timeframe: "1day")

        guard let candles = candleValue.value, candles.count >= 100 else {
            return ValidationSymbolResult(
                symbol: symbol, strategy: config.strategy.rawValue,
                totalReturn: 0, benchmarkReturn: 0, alpha: 0,
                winRate: 0, totalTrades: 0, maxDrawdown: 0,
                sharpeRatio: 0, profitFactor: 0,
                walkForwardDegradation: nil,
                buyRatio: 0, sellRatio: 0, holdRatio: 1,
                candleCount: candleValue.value?.count ?? 0,
                error: "Yetersiz veri (\(candleValue.value?.count ?? 0) bar, minimum 100)"
            )
        }

        // Son 6 ay (yaklaşık 130 işlem günü)
        let sixMonthBars = min(candles.count, 130)
        let slice = Array(candles.suffix(sixMonthBars))

        async let stratResult = ArgusBacktestEngine.shared.runBacktestWithValidation(
            symbol: symbol,
            config: config,
            candles: slice,
            financials: nil,
            trainRatio: 0.7
        )
        async let benchResult = ArgusBacktestEngine.shared.runBacktest(
            symbol: symbol,
            config: benchConfig,
            candles: slice,
            financials: nil
        )

        let (strat, bench) = await (stratResult, benchResult)

        let (buyR, sellR, holdR) = actionDistribution(logs: strat.logs)

        return ValidationSymbolResult(
            symbol: symbol,
            strategy: config.strategy.rawValue,
            totalReturn: strat.totalReturn,
            benchmarkReturn: bench.totalReturn,
            alpha: strat.totalReturn - bench.totalReturn,
            winRate: strat.winRate,
            totalTrades: strat.totalTrades,
            maxDrawdown: strat.maxDrawdown,
            sharpeRatio: strat.sharpeRatio,
            profitFactor: strat.profitFactor,
            walkForwardDegradation: strat.walkForwardDegradation,
            buyRatio: buyR,
            sellRatio: sellR,
            holdRatio: holdR,
            candleCount: slice.count,
            error: nil
        )
    }

    private func actionDistribution(logs: [BacktestDayLog]) -> (buy: Double, sell: Double, hold: Double) {
        guard !logs.isEmpty else { return (0, 0, 1) }
        let total = Double(logs.count)
        let buys  = Double(logs.filter { $0.action == "BUY" }.count)
        let sells = Double(logs.filter { $0.action == "SELL" }.count)
        let holds = total - buys - sells
        return (buys / total, sells / total, holds / total)
    }

    // MARK: - Markdown Export

    func markdownReport() -> String {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = [
            "# Argus Sprint A — Backtest Validation Report",
            "",
            "> Tarih: \(dateStr)  ",
            "> Strateji: Argus Standard (V2 motorlar) vs Buy & Hold  ",
            "> Dönem: Son ~6 ay (130 işlem günü), walk-forward %70/%30  ",
            "",
            "## Sembol Bazlı Sonuçlar",
            "",
            "| Sembol | Return | B&H | Alpha | Win% | İşlem | Sharpe | Drawdown | WF Deg | Overfitting |",
            "|--------|--------|-----|-------|------|-------|--------|----------|--------|-------------|",
        ]

        for r in results {
            if let err = r.error {
                lines.append("| \(r.symbol) | HATA | — | — | — | — | — | — | — | \(err) |")
                continue
            }
            let wfd = r.walkForwardDegradation.map { String(format: "%.1f", $0) } ?? "—"
            let ovf = r.isOverfit ? "⚠️ Yüksek" : "Normal"
            lines.append(
                "| \(r.symbol) | \(pct(r.totalReturn)) | \(pct(r.benchmarkReturn)) | \(pct(r.alpha)) | \(pct(r.winRate)) | \(r.totalTrades) | \(fmt2(r.sharpeRatio)) | \(pct(r.maxDrawdown)) | \(wfd) | \(ovf) |"
            )
        }

        let valid = results.filter { $0.error == nil }
        if !valid.isEmpty {
            let avgAlpha = valid.map(\.alpha).reduce(0, +) / Double(valid.count)
            let avgSharpe = valid.map(\.sharpeRatio).reduce(0, +) / Double(valid.count)
            let avgWinRate = valid.map(\.winRate).reduce(0, +) / Double(valid.count)
            let overfit = valid.filter(\.isOverfit).count

            lines += [
                "",
                "## Özet",
                "",
                "| Metrik | Değer |",
                "|--------|-------|",
                "| Ortalama Alpha vs B&H | \(pct(avgAlpha)) |",
                "| Ortalama Sharpe | \(fmt2(avgSharpe)) |",
                "| Ortalama Win Rate | \(pct(avgWinRate)) |",
                "| Overfitting Riski (WFD > 20) | \(overfit) / \(valid.count) sembol |",
                "",
                "## Aksiyon Dağılımı",
                "",
                "| Sembol | BUY% | SELL% | HOLD% |",
                "|--------|------|-------|-------|",
            ]
            for r in valid {
                lines.append(
                    "| \(r.symbol) | \(pct(r.buyRatio * 100)) | \(pct(r.sellRatio * 100)) | \(pct(r.holdRatio * 100)) |"
                )
            }

            lines += [
                "",
                "## Değerlendirme",
                "",
                avgAlpha > 0
                ? "✅ V2 motorlar, son 6 ayda Buy&Hold'u ortalama **\(pct(avgAlpha))** geçti."
                : "⚠️ V2 motorlar, son 6 ayda Buy&Hold'un **\(pct(abs(avgAlpha)))** gerisinde kaldı.",
                "",
                "Walk-forward degradation > 20 puan olan semboller: overfitting riski, V2 ağırlıklarının kalibrasyona ihtiyacı olabilir.",
            ]
        }

        return lines.joined(separator: "\n")
    }

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v) }
    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
}
