// Plink/Realtime/DMRealtimeClient.swift — user-level DM WebSocket ('@me' channel)
//
// Lightweight companion to RealtimeClient: connects to the backend user
// channel and delivers dm.event envelopes (message / typing / edited /
// deleted) to DMChatService. Polling remains as a fallback transport, so
// this client is deliberately best-effort: on any failure it backs off
// exponentially and reconnects while start() is active.

import Foundation

@MainActor
final class DMRealtimeClient {

    static let shared = DMRealtimeClient()

    struct Event: Decodable {
        let type: String
        let event: String
        let fromUserId: String?
        let messageId: String?
    }

    var onEvent: ((Event) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var running = false
    private var reconnectAttempt = 0
    private var connectTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        reconnectAttempt = 0
        connectTask = Task { [weak self] in await self?.connect() }
    }

    func stop() {
        running = false
        connectTask?.cancel()
        connectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() async {
        guard running else { return }
        guard let ticket = await fetchTicket() else {
            scheduleReconnect()
            return
        }
        guard let url = URL(string: PlinkConfig.wsURLString + "/user") else { return }
        var request = URLRequest(url: url)
        request.setValue("plink.v2, plink.ticket.\(ticket)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let socket = URLSession.shared.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveLoop(socket)
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                switch result {
                case .success(let message):
                    self.reconnectAttempt = 0
                    var data: Data?
                    switch message {
                    case .string(let text): data = text.data(using: .utf8)
                    case .data(let d): data = d
                    @unknown default: break
                    }
                    if let data,
                       let event = try? JSONDecoder().decode(Event.self, from: data),
                       event.type == "dm.event" {
                        self.onEvent?(event)
                    }
                    guard self.task === socket else { return }
                    self.receiveLoop(socket)
                case .failure:
                    guard self.task === socket else { return }
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard running else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        reconnectAttempt += 1
        let delaySec = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        connectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard let self, self.running else { return }
            await self.connect()
        }
    }

    private struct TicketResponse: Decodable {
        let ticket: String
        let expiresInSec: Int?
    }

    private func fetchTicket() async -> String? {
        guard let auth = KeychainHelper.read(for: "rave_auth_token"),
              let url = URL(string: PlinkConfig.apiURLString + "/realtime/ticket") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["roomId": "@me"])
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TicketResponse.self, from: data) else { return nil }
        return decoded.ticket
    }
}
