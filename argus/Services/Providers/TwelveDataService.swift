import Foundation
import Combine

/// TwelveData WebSocket-only client.
/// REST endpoints (quote/candles/fundamentals) were dropped on
/// 2026-05-11 — never called from anywhere in the codebase and
/// the 8 req/min free tier was prohibitive anyway. The WS feed
/// stays because it complements Finnhub's 50-symbol live cap
/// (free tier allows ~8 additional symbols streamed live).
final class TwelveDataService: NSObject, @unchecked Sendable {
    static let shared = TwelveDataService()

    private let socketURL = URL(string: "wss://ws.twelvedata.com/v1/quotes?apikey=\(Secrets.shared.twelveData)")!

    // WebSocket State
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var subscriptions: Set<String> = []
    private var reconnectBlockedUntil: Date?
    private lazy var wsSession: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())

    // Publishers
    let priceUpdate = PassthroughSubject<Quote, Never>()

    private override init() {
        super.init()
    }

    // MARK: - WebSocket (Live Streaming)

    func connect() {
        guard !isConnected else { return }
        if let blockedUntil = reconnectBlockedUntil, Date() < blockedUntil {
            let remaining = max(1, Int(blockedUntil.timeIntervalSinceNow))
            print("⏳ TwelveData: Reconnect blocked (\(remaining)s) due to prior rate limit.")
            return
        }
        print("TwelveData: Connecting...")
        webSocketTask = wsSession.webSocketTask(with: socketURL)
        webSocketTask?.resume()
        listen()
    }

    func subscribe(symbols: [String]) {
        let newSymbols = symbols.filter { !subscriptions.contains($0) }
        guard !newSymbols.isEmpty else { return }

        for s in newSymbols { subscriptions.insert(s) }

        if !isConnected {
            connect()
            return
        }

        sendSubscription(newSymbols)
    }

    /// Diff-based subscription update. Adds new symbols, removes ones
    /// no longer requested. Without this the subscription set grows
    /// monotonically and hits the 8-symbol free-tier cap.
    func setSubscriptions(_ symbols: [String]) {
        let desired = Set(symbols)
        let toAdd = desired.subtracting(subscriptions)
        let toRemove = subscriptions.subtracting(desired)
        subscriptions = desired

        if !isConnected {
            connect()
            return
        }
        if !toRemove.isEmpty { sendUnsubscribe(Array(toRemove)) }
        if !toAdd.isEmpty { sendSubscription(Array(toAdd)) }
    }

    private func sendUnsubscribe(_ symbols: [String]) {
        guard !symbols.isEmpty else { return }
        let joined = symbols.joined(separator: ",")
        let msg = """
        {
            "action": "unsubscribe",
            "params": {
                "symbols": "\(joined)"
            }
        }
        """
        sendMessage(msg)
    }

    private func sendSubscription(_ symbols: [String]) {
        guard !symbols.isEmpty else { return }
        let joined = symbols.joined(separator: ",")
        let msg = """
        {
            "action": "subscribe",
            "params": {
                "symbols": "\(joined)"
            }
        }
        """
        sendMessage(msg)
    }

    private func sendMessage(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("❌ TwelveData Send Error: \(error)")
            }
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("❌ TwelveData: Receive Error \(error)")
                self.isConnected = false
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default: break
                }
                self.listen()
            }
        }
    }

    private func handleMessage(_ text: String) {
        // TD price event: {"event":"price","symbol":"AAPL","currency":"USD","price":150.0,...}
        guard let data = text.data(using: .utf8) else { return }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let event = json["event"] as? String {

                if event == "price" {
                    if let sym = json["symbol"] as? String,
                       let price = json["price"] as? Double {

                        var q = Quote(
                            c: price,
                            d: 0, // Stream doesn't always send change, ViewModel calculates diff
                            dp: 0,
                            currency: json["currency"] as? String,
                            shortName: sym,
                            symbol: sym
                        )
                        q.timestamp = Date()

                        DispatchQueue.main.async {
                            self.priceUpdate.send(q)
                        }
                    }
                }
                // heartbeat events are ignored
            }
        } catch {
            print("Parser error: \(text)")
        }
    }
}

extension TwelveDataService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("🔌 TwelveData: Connected!")
        isConnected = true
        reconnectBlockedUntil = nil

        if !subscriptions.isEmpty {
            sendSubscription(Array(subscriptions))
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if closeCode.rawValue == 1013 {
            reconnectBlockedUntil = Date().addingTimeInterval(90)
            print("⚠️ TwelveData: Closed with 1013 (rate limit). Pausing reconnect for 90s.")
        } else {
            print("🔌 TwelveData: Closed (\(closeCode.rawValue)).")
        }
        isConnected = false
    }
}
