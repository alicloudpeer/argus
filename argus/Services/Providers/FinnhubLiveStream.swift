import Foundation
import Combine

/// WebSocket adapter for Finnhub trade streaming. Subscribes to a
/// dynamic set of symbols and republishes trades as `Quote` events on
/// `priceUpdate`. The actor maintains one connection regardless of how
/// many subscribers ask for symbols, and it keeps the subscription set
/// reconciled whenever `setSubscriptions` is called.
///
/// Free tier supports 50 symbol subscriptions on a single socket and
/// is sufficient for the visible/focus set (open positions plus the
/// part of the watchlist actually rendered).
final class FinnhubLiveStream: NSObject, @unchecked Sendable {
    static let shared = FinnhubLiveStream()

    let priceUpdate = PassthroughSubject<Quote, Never>()

    private let queue = DispatchQueue(label: "argus.finnhub.live", qos: .userInitiated)
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private let decoder = JSONDecoder()
    private var desired: Set<String> = []
    private var active: Set<String> = []
    private var connected = false
    private var connectInFlight = false
    private var reconnectAttempt = 0

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    func setSubscriptions(_ symbols: [String]) {
        let normalized = Set(symbols.map { FinnhubProvider.toFinnhubSymbol($0) })
        queue.async { [weak self] in
            guard let self = self else { return }
            self.desired = normalized
            if Secrets.shared.finnhub.isEmpty {
                return
            }
            if self.connected {
                self.reconcileSubscriptions()
            } else {
                self.openSocket()
            }
        }
    }

    // MARK: - Connection

    private func openSocket() {
        guard !connectInFlight else { return }
        guard !Secrets.shared.finnhub.isEmpty else { return }
        connectInFlight = true

        let urlString = "wss://ws.finnhub.io?token=\(Secrets.shared.finnhub)"
        guard let url = URL(string: urlString) else {
            connectInFlight = false
            return
        }
        task = session.webSocketTask(with: url)
        task?.resume()
        listen()
    }

    private func reconcileSubscriptions() {
        let toAdd = desired.subtracting(active)
        let toRemove = active.subtracting(desired)
        for symbol in toRemove { send(type: "unsubscribe", symbol: symbol) }
        for symbol in toAdd { send(type: "subscribe", symbol: symbol) }
        active = desired
    }

    private func send(type: String, symbol: String) {
        guard let task = task else { return }
        let payload = ["type": type, "symbol": symbol]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { error in
            if let error = error {
                print("⚠️ Finnhub WS send failed for \(symbol): \(error.localizedDescription)")
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.handle(message: message)
                self.listen()
            case .failure(let error):
                print("⚠️ Finnhub WS receive failed: \(error.localizedDescription)")
                self.queue.async {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let payload: Data
        switch message {
        case .string(let s):
            guard let bytes = s.data(using: .utf8) else { return }
            payload = bytes
        case .data(let d):
            payload = d
        @unknown default:
            return
        }
        guard let envelope = try? decoder.decode(TradeEnvelope.self, from: payload) else { return }
        guard envelope.type == "trade" else { return }
        for trade in envelope.data ?? [] {
            let quote = Quote(
                c: trade.p,
                d: nil,
                dp: nil,
                currency: "USD",
                shortName: nil,
                symbol: Self.toCanonical(trade.s)
            )
            var withTimestamp = quote
            withTimestamp.timestamp = Date(timeIntervalSince1970: TimeInterval(trade.t / 1000))
            withTimestamp.volume = trade.v
            priceUpdate.send(withTimestamp)
        }
    }

    private func scheduleReconnect() {
        connected = false
        connectInFlight = false
        active.removeAll()
        task = nil

        guard !desired.isEmpty else { return }
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        // Backoff with jitter so a fleet of clients reconnecting after a
        // Finnhub outage do not all hit the socket at the same instant.
        let base = pow(2.0, Double(reconnectAttempt))
        let delay = base * Double.random(in: 0.7...1.3)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openSocket()
        }
    }

    // MARK: - Symbol mapping

    private static func toCanonical(_ finnhubSymbol: String) -> String {
        if finnhubSymbol.hasPrefix("BINANCE:") {
            let base = finnhubSymbol.dropFirst("BINANCE:".count)
            if base.hasSuffix("USDT") {
                return "\(base.dropLast(4))-USD"
            }
            return String(base)
        }
        if finnhubSymbol.hasPrefix("OANDA:") {
            return "\(finnhubSymbol.dropFirst("OANDA:".count))=X"
        }
        return finnhubSymbol
    }

    // MARK: - Decode shapes

    private struct TradeEnvelope: Decodable {
        let type: String
        let data: [Trade]?
    }

    private struct Trade: Decodable {
        let s: String      // Symbol
        let p: Double      // Price
        let t: Int64       // Timestamp ms
        let v: Double      // Volume
    }
}

extension FinnhubLiveStream: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connected = true
            self.connectInFlight = false
            self.reconnectAttempt = 0
            self.active.removeAll()
            self.reconcileSubscriptions()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { [weak self] in
            self?.scheduleReconnect()
        }
    }
}
