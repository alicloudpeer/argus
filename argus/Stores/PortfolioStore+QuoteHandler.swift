import Foundation

// MARK: - Quote Handler (HOT PATH)
/// PortfolioStore'un piyasa quote tick'lerine reaksiyonu. Her tick'te:
/// - Açık trade'lerin highWaterMark'ı güncellenir (trailing stop için)
/// - Stop-Loss / Take-Profit eşikleri kontrol edilir
/// - Tetiklenirse `sell()` çağrılır (retroaktif gap koruması ile)
///
/// Reentrancy guard (`isHandlingQuoteUpdate`) ana sınıfta tutulur:
/// iç sell() → @Published mutation → subscriber → yeniden handleQuoteUpdates
/// zincirini kırar.
extension PortfolioStore {

    func handleQuoteUpdates(_ quotes: [String: DataValue<Quote>]) {
        // O2: Zaten içerideyiz → dış çağrı iterasyonunu tamamlasın, yeni çağrıyı
        // düşür. Bir sonraki quote tick'i yine bizi çağıracak; bekleyen güncelleme
        // sırasında kaybolmuş fiyat yok (quote'lar stateless tick'ler, gap önemsiz).
        if isHandlingQuoteUpdate {
            return
        }
        isHandlingQuoteUpdate = true
        defer { isHandlingQuoteUpdate = false }

        // Sadece açık pozisyonlar için quote'ları güncelle ve kontrol et
        let openSymbols = Set(trades.filter { $0.isOpen }.map { $0.symbol })

        for symbol in openSymbols {
            if let dataValue = quotes[symbol], let quote = dataValue.value {
                let currentPrice = quote.currentPrice

                // Stop Loss / Take Profit / HWM kontrolü
                for index in trades.indices where trades[index].symbol == symbol && trades[index].isOpen {
                    let trade = trades[index]

                    // High Water Mark Update (Trailing Stop için)
                    if currentPrice > (trade.highWaterMark ?? 0) {
                        var mutableTrade = trades[index]
                        mutableTrade.highWaterMark = currentPrice
                        trades[index] = mutableTrade
                        scheduleDebouncedSave() // Debounced — çok sık yazma önlenir
                    }

                    checkStopLoss(for: trade, at: index, currentPrice: currentPrice)
                    checkTakeProfit(for: trade, at: index, currentPrice: currentPrice)
                }
            }
        }

        // Peak Equity Tracking — drawdown enforcement için zirve takibi
        let simpleQuotes: [String: Quote] = quotes.compactMapValues { $0.value }
        let currentGlobal = getGlobalEquity(quotes: simpleQuotes)
        if currentGlobal > peakGlobalEquity { peakGlobalEquity = currentGlobal }
        let currentBist = getBistEquity(quotes: simpleQuotes)
        if currentBist > peakBistEquity { peakBistEquity = currentBist }
    }

    func checkStopLoss(for trade: Trade, at index: Int, currentPrice: Double) {
        guard let stopLoss = trade.stopLoss,
              currentPrice <= stopLoss,
              !trade.isPendingSale else { return } // Duplicate trigger koruması

        // İşaretle ve sat — race condition önleme
        trades[index].isPendingSale = true
        scheduleDebouncedSave()

        // Retroaktif gap tespiti: Uygulama kapalıyken fiyat stop'u geçtiyse,
        // satış her zaman stop fiyatından yapılır (mevcut gap fiyatından değil).
        let isRetroactiveGap = currentPrice < stopLoss * 0.99 // %1'den fazla gap = retroaktif
        let sellPrice = stopLoss // Her zaman stop fiyatından sat
        let reason = isRetroactiveGap ? "STOP_LOSS_RETROACTIVE" : "STOP_LOSS"

        if isRetroactiveGap {
            print("🛑⏮️ PortfolioStore: STOP LOSS (RETROAKTİF) tetiklendi for \(trade.symbol) — Stop: \(sellPrice), Mevcut: \(currentPrice)")
        } else {
            print("🛑 PortfolioStore: STOP LOSS tetiklendi for \(trade.symbol) @ \(sellPrice) (SL: \(stopLoss))")
        }
        sell(tradeId: trade.id, currentPrice: sellPrice, reason: reason)
    }

    func checkTakeProfit(for trade: Trade, at index: Int, currentPrice: Double) {
        guard let takeProfit = trade.takeProfit,
              currentPrice >= takeProfit,
              !trade.isPendingSale else { return } // Duplicate trigger koruması

        // İşaretle ve sat — race condition önleme
        trades[index].isPendingSale = true
        scheduleDebouncedSave()

        // Retroaktif gap tespiti: Uygulama kapalıyken fiyat take-profit'i geçtiyse,
        // satış her zaman take-profit fiyatından yapılır (mevcut gap fiyatından değil).
        let isRetroactiveGap = currentPrice > takeProfit * 1.01 // %1'den fazla gap = retroaktif
        let sellPrice = takeProfit // Her zaman take-profit fiyatından sat
        let reason = isRetroactiveGap ? "TAKE_PROFIT_RETROACTIVE" : "TAKE_PROFIT"

        if isRetroactiveGap {
            print("💰⏮️ PortfolioStore: TAKE PROFIT (RETROAKTİF) tetiklendi for \(trade.symbol) — TP: \(sellPrice), Mevcut: \(currentPrice)")
        } else {
            print("💰 PortfolioStore: TAKE PROFIT tetiklendi for \(trade.symbol) @ \(sellPrice) (TP: \(takeProfit))")
        }
        sell(tradeId: trade.id, currentPrice: sellPrice, reason: reason)
    }
}
