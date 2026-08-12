// Plink/Realtime/RealtimeClient.swift
// Production WebSocket client (runbook §8 + Brain Review 3 P0-19..P0-21 fixes)
//
// Brain Review 3 fixes:
//
// P0-19: receive loop bound to EXACT task, not shared transport.task.
//   Old loop's `try await self.transport.task?.receive()` reads the shared
//   current task — after reconnect, old loop can steal the new task's first
//   message. Fixed: startReceiveLoop takes task parameter; loop awaits
//   task.receive() directly, never reads transport.task.
//
// P0-20: URLSession delegate callbacks check task identity via
//   transport.isCurrent(task). Old socket close no longer triggers
//   scheduleReconnect() over healthy new connection.
//
// P0-21: beginReconnect(cause:) unifies reconnect paths. Cancels old
//   transport IMMEDIATELY before backoff (not after). Single reconnectTask
//   prevents competing reconnect attempts.

import Foundation
import Observation

// MARK: - Sendable transport holder with task identity check (P0-20)
private final class Transport: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionWebSocketTask?
    private var _session: URLSession?

    func set(task: URLSessionWebSocketTask?, session: URLSession?) {
        lock.lock(); defer { lock.unlock() }
        _task?.cancel(with: .goingAway, reason: nil)
        _session?.invalidateAndCancel()
        _task = task
        _session = session
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _task?.cancel(with: .goingAway, reason: nil)
        _session?.invalidateAndCancel()
        _task = nil
        _session = nil
    }

    var task: URLSessionWebSocketTask? {
        lock.lock(); defer { lock.unlock() }
        return _task
    }

    // P0-20: identity check for delegate callbacks
    func isCurrent(_ candidate: URLSessionWebSocketTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _task === candidate
    }

    func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) {
        lock.lock()
        let t = _task
        lock.unlock()
        guard let t else {
            completionHandler(NSError(domain: "Transport", code: -1, userInfo: [NSLocalizedDescriptionKey: "no task"]))
            return
        }
        t.send(.data(data), completionHandler: completionHandler)
    }
}

// MARK: - Subscription tokens
private struct MessageSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeServerMessage>.Continuation
}
private struct StateSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeConnectionState>.Continuation
}

// MARK: - Realtime ticket
public struct RealtimeTicket: Sendable, Equatable {
    public let jwt: String
    public let roomId: String
    public let expiresInSec: Int
    public init(jwt: String, roomId: String, expiresInSec: Int) {
        self.jwt = jwt
        self.roomId = roomId
        self.expiresInSec = expiresInSec
    }
}

// P0-30: typed RoomRole — not raw String
public enum RoomRole: String, Sendable, Equatable, Codable {
    case host
    case viewer
}

// MARK: - Delegate protocol (P0-30: sessionDidConnect now carries role)
@MainActor
public protocol RealtimeClientDelegate: AnyObject {
    var roomId: String? { get }
    var lastEpoch: Int64 { get }
    var lastSeq: Int64 { get }
    func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double)
    func applySnapshot(_ state: RealtimeRoomState?)
    /// P0-30: role from session.ready — host or viewer
    func sessionDidConnect(role: RoomRole)
    func handleOtherMessage(_ message: RealtimeServerMessage)
}

// MARK: - Client
@MainActor
@Observable
public final class RealtimeClient: NSObject {
    public private(set) var state: RealtimeConnectionState = .idle
    public private(set) var lastError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var snapshotReceived: Bool = false
    // P0-30: role from session.ready — exposed to delegate via sessionDidConnect(role:)
    public private(set) var role: RoomRole = .viewer

    private var messageSinks: [MessageSink] = []
    private var stateSinks: [StateSink] = []

    private let transport = Transport()

    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var clockProbeTask: Task<Void, Never>?
    private var clockTimeoutTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?

    // Generation — bumped on each new transport
    private var generation: UUID = UUID()
    private var clockReplyCount = 0

    private let baseEndpoint: URL
    public weak var delegate: RealtimeClientDelegate?
    private let ticketProvider: (String) async throws -> RealtimeTicket
    private var currentTicket: RealtimeTicket?
    private var currentRoomId: String?
    private var reconnectAttempt = 0

    // M12: outbound queue — user messages (chat/reactions) composed while
    // offline or during reconnect are queued and flushed after the session
    // is fully connected, instead of being silently dropped.
    private var pendingOutbound: [RealtimeClientMessage] = []
    private static let maxPendingOutbound = 50

    /// M13: number of user messages queued while offline (surfaced in the room UI).
    public var queuedUserMessageCount: Int { pendingOutbound.count }
    private static let maxReconnectBackoffSec: Double = 30
    private static let clockTimeoutNs: UInt64 = 5_000_000_000
    private static let snapshotTimeoutNs: UInt64 = 8_000_000_000
    private static let minClockRepliesForSync = 3

    public init(baseEndpoint: URL, ticketProvider: @escaping (String) async throws -> RealtimeTicket) {
        self.baseEndpoint = baseEndpoint
        self.ticketProvider = ticketProvider
        super.init()
    }

    // MARK: - Public API

    public var messages: AsyncStream<RealtimeServerMessage> {
        AsyncStream { continuation in
            let sink = MessageSink(id: UUID(), continuation: continuation)
            self.messageSinks.append(sink)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.messageSinks.removeAll { $0.id == sink.id }
                }
            }
        }
    }

    public var stateChanges: AsyncStream<RealtimeConnectionState> {
        AsyncStream { continuation in
            let sink = StateSink(id: UUID(), continuation: continuation)
            self.stateSinks.append(sink)
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stateSinks.removeAll { $0.id == sink.id }
                }
            }
        }
    }

    public func connect(roomId: String) {
        switch state {
        case .idle, .failed:
            break
        case .connecting, .authenticating, .joining, .synchronizing,
             .connected, .reconnecting:
            return
        }
        currentRoomId = roomId
        cancelAllTasks()
        transport.cancel()
        setState(.connecting)
        Task { await openConnection() }
    }

    public func disconnect() {
        cancelAllTasks()
        transport.cancel()
        pendingOutbound.removeAll()
        currentTicket = nil
        clockReplyCount = 0
        clockSynced = false
        snapshotReceived = false
        setState(.idle)
    }

    public func send(_ msg: RealtimeClientMessage) {
        // M12: while offline or reconnecting, queue user-visible messages
        // (chat/reactions) instead of dropping them; flush after connect.
        guard state.isOnline || state.isTransient else {
            enqueueIfUserMessage(msg)
            return
        }
        if !state.isOnline && isUserMessage(msg) {
            // Transient (handshake/reconnect) — transport is not ready for
            // user traffic yet; queue and flush on connected.
            enqueueIfUserMessage(msg)
            return
        }
        do {
            let data = try JSONEncoder().encode(msg)
            transport.send(data) { [weak self] err in
                if let err {
                    Task { @MainActor [weak self] in
                        self?.lastError = "send failed: \(err.localizedDescription)"
                    }
                }
            }
        } catch {
            lastError = "encode failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Connection (P0-21: cancel old transport BEFORE backoff)

    private func openConnection() async {
        guard let roomId = currentRoomId else {
            setState(.failed(reason: "No roomId"))
            return
        }
        generation = UUID()
        let gen = generation
        clockSynced = false
        clockReplyCount = 0
        snapshotReceived = false

        let ticket: RealtimeTicket
        do {
            ticket = try await ticketProvider(roomId)
        } catch {
            if gen == generation { setState(.failed(reason: "Ticket error: \(error.localizedDescription)")) }
            return
        }
        guard gen == generation else { return }
        currentTicket = ticket

        guard ticket.roomId == roomId else {
            setState(.failed(reason: "Ticket roomId mismatch"))
            return
        }

        let url: URL
        do {
            url = try roomEndpoint(roomId: roomId)
        } catch {
            setState(.failed(reason: "Invalid endpoint: \(error.localizedDescription)"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("plink.v2, plink.ticket.\(ticket.jwt)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0

        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        let t = s.webSocketTask(with: request)
        transport.set(task: t, session: s)
        if gen == generation { setState(.authenticating) }
        t.resume()
        // P0-19: pass the EXACT task to the receive loop — do not read
        // transport.task inside the loop.
        if gen == generation { startReceiveLoop(task: t, generation: gen) }
    }

    private func roomEndpoint(roomId: String) throws -> URL {
        var components = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)
        guard let scheme = components?.scheme,
              scheme == "ws" || scheme == "wss",
              components?.host != nil else {
            throw NSError(domain: "RealtimeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "baseEndpoint must be ws:// or wss://"])
        }
        var path = components?.path ?? ""
        if path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/ws" }
        path += "/room/" + roomId
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        guard let url = components?.url else {
            throw NSError(domain: "RealtimeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "failed to build room endpoint"])
        }
        return url
    }

    // P0-19: receive loop bound to EXACT task — never reads transport.task
    private func startReceiveLoop(task: URLSessionWebSocketTask, generation: UUID) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, weak task] in
            guard let self else { return }
            guard let task else { return }
            while !Task.isCancelled {
                do {
                    // P0-19: await on the EXACT task, not transport.task
                    let msg = try await task.receive()
                    // Generation check still needed for handleIncoming, but
                    // the message came from the correct task — no stealing.
                    guard generation == self.generation else { return }
                    self.handleIncoming(msg, generation: generation)
                } catch {
                    if generation != self.generation { return }
                    if !Task.isCancelled {
                        self.handleReceiveError(error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Incoming (single yield per message)

    private func handleIncoming(_ msg: URLSessionWebSocketTask.Message, generation: UUID) {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        let clientReceivedMs = Date().timeIntervalSince1970 * 1000
        do {
            let decoded = try JSONDecoder().decode(RealtimeServerMessage.self, from: data)
            for sink in messageSinks { sink.continuation.yield(decoded) }
            switch decoded {
            case .sessionReady(let ready):
                handleSessionReady(ready, generation: generation)
            case .clockProbeReply(let reply):
                handleClockReply(reply, clientReceivedMs: clientReceivedMs, generation: generation)
            case .syncStateSnapshot(let snapshot):
                handleSnapshot(snapshot, generation: generation)
            case .syncState(let stateMsg):
                delegate?.applySnapshot(stateMsg.state)
            default:
                delegate?.handleOtherMessage(decoded)
            }
        } catch {
            lastError = "decode failed: \(error.localizedDescription)"
        }
    }

    private func handleSessionReady(_ ready: RealtimeServerMessage.SessionReady, generation: UUID) {
        guard generation == self.generation else { return }
        // P0-30: store role from session.ready for sessionDidConnect(role:)
        self.role = RoomRole(rawValue: ready.role) ?? .viewer
        setState(.synchronizing)
        startClockProbes(generation: generation)
        startClockTimeout(generation: generation)
        startSnapshotTimeout(generation: generation)
        if let roomId = currentRoomId {
            let afterSeq = delegate?.lastSeq ?? 0
            send(.stateRequest(.init(roomId: roomId, afterSeq: afterSeq)))
        }
    }

    private func handleClockReply(_ reply: RealtimeServerMessage.ClockProbeReply, clientReceivedMs: Double, generation: UUID) {
        guard generation == self.generation else { return }
        delegate?.ingestClockProbe(
            clientSentMs: reply.clientSentMs,
            serverMs: reply.serverMs,
            clientReceivedMs: clientReceivedMs
        )
        clockReplyCount += 1
        if clockReplyCount >= Self.minClockRepliesForSync && !clockSynced {
            clockSynced = true
            clockTimeoutTask?.cancel()
            clockTimeoutTask = nil
        }
    }

    private func handleSnapshot(_ snapshot: RealtimeServerMessage.SyncStateSnapshotMessage, generation: UUID) {
        guard generation == self.generation else { return }
        delegate?.applySnapshot(snapshot.state)
        snapshotReceived = true
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        if state != .connected {
            setState(.connected)
            // P0-30: pass role to delegate — host or viewer
            delegate?.sessionDidConnect(role: self.role)
            reconnectAttempt = 0
            // M12: flush chat/reactions composed while offline
            flushPendingOutbound()
        }
    }

    private func startClockTimeout(generation: UUID) {
        clockTimeoutTask?.cancel()
        clockTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.clockTimeoutNs)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.generation else { return }
            if !self.clockSynced {
                self.clockSynced = false
                self.lastError = "Clock sync timeout — degraded mode"
            }
        }
    }

    private func startSnapshotTimeout(generation: UUID) {
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.snapshotTimeoutNs)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.generation else { return }
            if !self.snapshotReceived && self.state != .connected {
                self.lastError = "Snapshot timeout — reconnecting"
                self.beginReconnect(cause: "snapshot timeout")
            }
        }
    }

    // P0-31: handshake timeout — was previously in startHandshakeTimeout,
    // now split into clock + snapshot timeouts above.

    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
        let transient = [57, 60, 54, -1005, -1009, -1001].contains(nsError.code)
        if transient {
            beginReconnect(cause: "receive error: \(nsError.localizedDescription)")
        } else {
            setState(.failed(reason: nsError.localizedDescription))
        }
    }

    // MARK: - Reconnect (P0-21: unified beginReconnect, cancel old BEFORE backoff)

    private func beginReconnect(cause: String) {
        // P0-21: prevent competing reconnect tasks
        if reconnectTask != nil { return }
        // P0-21: invalidate generation + cancel old transport IMMEDIATELY
        generation = UUID()  // old callbacks now ignored
        cancelAllTasksExceptReconnect()
        transport.cancel()  // old task cancelled BEFORE backoff
        reconnectAttempt += 1
        setState(.reconnecting(attempt: reconnectAttempt))
        lastError = cause
        let delaySec = min(Self.maxReconnectBackoffSec, pow(2.0, Double(reconnectAttempt))) + Double.random(in: 0...0.5)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            await self.openConnection()
        }
    }

    // Legacy alias — kept for delegate close path
    private func scheduleReconnect() {
        beginReconnect(cause: "socket closed")
    }

    // MARK: - Clock probes

    private func startClockProbes(generation: UUID) {
        clockProbeTask?.cancel()
        clockProbeTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<7 {
                if Task.isCancelled { return }
                if generation != self.generation { return }
                self.sendClockProbe()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                if generation != self.generation { return }
                self.sendClockProbe()
            }
        }
    }

    private func sendClockProbe() {
        // Аудит 26.07.2026 P0: сервер требует целое (zod .int()), Double с дробью
        // отбивался SCHEMA_INVALID — клоксинк в проде не работал вообще.
        send(.clockProbe(.init(clientSentMs: (Date().timeIntervalSince1970 * 1000).rounded())))
    }

    // MARK: - M12 offline outbound queue

    private func isUserMessage(_ msg: RealtimeClientMessage) -> Bool {
        switch msg {
        case .chatSend, .reactionSend: return true
        // M26: просьба о паузе НЕ копится в офлайн-очереди намеренно.
        // «Поставь паузу» имеет смысл ровно сейчас; доставленная через
        // 30 секунд после переподключения, она попросит хоста остановить
        // совсем другой момент фильма. Лучше не отправить и сказать об этом,
        // чем отправить не вовремя (см. WatchRoomModel.requestPause).
        // M27: ответ хоста — по той же причине: вердикт по просьбе, которой
        // к моменту реконнекта уже никто не ждёт, только запутает комнату.
        case .syncCommand, .stateRequest, .clockProbe, .pauseRequest, .pauseResolve: return false
        }
    }

    private func enqueueIfUserMessage(_ msg: RealtimeClientMessage) {
        guard isUserMessage(msg) else { return }
        pendingOutbound.append(msg)
        if pendingOutbound.count > Self.maxPendingOutbound {
            pendingOutbound.removeFirst(pendingOutbound.count - Self.maxPendingOutbound)
        }
    }

    private func flushPendingOutbound() {
        guard state.isOnline, !pendingOutbound.isEmpty else { return }
        let queued = pendingOutbound
        pendingOutbound = []
        for msg in queued { send(msg) }
    }

    private func setState(_ newState: RealtimeConnectionState) {
        state = newState
        for sink in stateSinks { sink.continuation.yield(newState) }
    }

    private func cancelAllTasks() {
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        clockProbeTask?.cancel(); clockProbeTask = nil
        clockTimeoutTask?.cancel(); clockTimeoutTask = nil
        snapshotTimeoutTask?.cancel(); snapshotTimeoutTask = nil
    }

    // P0-21: cancel all except reconnect (called FROM beginReconnect)
    private func cancelAllTasksExceptReconnect() {
        receiveTask?.cancel(); receiveTask = nil
        clockProbeTask?.cancel(); clockProbeTask = nil
        clockTimeoutTask?.cancel(); clockTimeoutTask = nil
        snapshotTimeoutTask?.cancel(); snapshotTimeoutTask = nil
    }

    nonisolated deinit {
        transport.cancel()
    }
}

// MARK: - URLSessionWebSocketDelegate (P0-20: task identity check)

extension RealtimeClient: URLSessionWebSocketDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // P0-20: only handle if this is the current task
            guard self.transport.isCurrent(webSocketTask) else { return }
            self.setState(.joining)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // P0-20: only handle if this is the current task
            guard self.transport.isCurrent(webSocketTask) else { return }
            // P0-5: URLSessionWebSocketTask.CloseCode — use rawValue only,
            // named cases vary across SDK versions (.normal vs .protocolNormal).
            let code = closeCode.rawValue
            if code == 1000 || code == 1001 {
                self.setState(.idle)
            } else if code == 4001 {
                self.setState(.failed(reason: "Auth rejected (4001)"))
            } else if closeCode.rawValue == 4003 {
                self.setState(.failed(reason: "Forbidden (4003) — not member/host"))
            } else {
                self.beginReconnect(cause: "socket closed: \(closeCode.rawValue)")
            }
        }
    }
}
