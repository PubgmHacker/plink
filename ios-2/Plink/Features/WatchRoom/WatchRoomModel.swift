// Plink/Features/WatchRoom/WatchRoomModel.swift
// Single owner of room session lifecycle (runbook §21, Brain Review 5 P0-29..P0-37)
//
// Brain Review 5 fixes:
//   P0-29: PlaybackProxy — syncController talks to stable proxy, not dummy player
//   P0-30: RoomRole — sessionDidConnect(role:) sets isHost
//   P0-31: stateChanges stream — connectionState reflects all states
//   P0-33: functional host controls (optimistic local apply + v2 command)
//   P0-34: chat button opens sheet (handled in WatchRoomScreen)
//   P0-35: fetchChatCatchup REST client with cursor paging
//   P0-36: presence snapshot + reaction stream
//   P0-37: composition root (wiring in MainTabView handled separately)
//   P1-32: current user identity via init
//   P1-33: typed mediaId in host commands
//   P1-34: lastError + hardCorrectionCount + driftMs wired to UI

import Foundation
import Observation
#if canImport(UIKit)
import UIKit  // PATCH 16: UIApplication + UIWindowScene for Rutube fallback presentation
#endif

@MainActor
@Observable
public final class WatchRoomModel: RealtimeClientDelegate {
    // MARK: - Public state (UI binds to these)
    // Default to .connecting (not .idle) so the SyncHealthPill shows
    // "Connecting..." instead of "Offline" during the brief moment between
    // view appear and model.connect() running. disconnect() still sets .idle
    // so the pill correctly shows "Offline" after the user leaves the room.
    public private(set) var connectionState: RealtimeConnectionState = .connecting
    public private(set) var isHost: Bool = false
    public private(set) var role: RoomRole = .viewer
    public private(set) var participants: [ParticipantInfo] = []
    public private(set) var chatMessages: [ChatMessageInfo] = []

    /// M13: active room poll (rides on the chat protocol, see RoomPolls.swift).
    public private(set) var activePoll: RoomPollState?

    /// M15: текущий режим приватности комнаты (бар модерации).
    // Аудит 26.07.2026: RoomPrivacy — internal-тип, поэтому свойство не может быть public.
    private(set) var roomPrivacy: RoomPrivacy = .publicRoom
    /// M15: видимость бара модерации (управляется экраном и топ-хромом).
    public var moderationBarVisible = false

    /// M16: ИИ-модератор — до какого момента текущий юзер замучен (nil — не замучен).
    public private(set) var mutedUntil: Date? = nil

    /// M16: остаток мута в секундах (0 — можно писать).
    public var mutedRemainingSec: Int {
        guard let until = mutedUntil else { return 0 }
        let remaining = Int(until.timeIntervalSinceNow.rounded(.up))
        return max(0, remaining)
    }

    /// M16: очередь видео комнаты (ИИ-ассистент ставит ролики по-настоящему).
    // Аудит 26.07.2026: RoomQueueWire — internal-тип (RoomQueue.swift), public здесь невозможен.
    private(set) var roomQueue: [RoomQueueWire.Item] = []

    // M17: управление очередью — REST; broadcast обновит roomQueue у всех участников.
    func removeFromQueue(_ item: RoomQueueWire.Item) {
        let rid = _roomId
        Task {
            struct Resp: Decodable { let queue: [RoomQueueWire.Item] }
            do {
                let _: Resp = try await APIClient.shared.request("rooms/\(rid)/queue/\(item.id)", method: .delete)
            } catch {
                // тихо — очередь синхронизируется бродкастом
            }
        }
    }

    func playFromQueue(_ item: RoomQueueWire.Item) {
        guard isHost else { return }
        let rid = _roomId
        Task {
            struct Resp: Decodable { let queue: [RoomQueueWire.Item] }
            struct Empty: Encodable {}
            do {
                let _: Resp = try await APIClient.shared.request("rooms/\(rid)/queue/\(item.id)/play", method: .post, body: Empty())
            } catch {
                // тихо
            }
        }
    }

    // M14: синхронный отсчёт 3-2-1 перед стартом
    public private(set) var countdownRemaining: Int? = nil
    private var countdownTask: Task<Void, Never>?
    public private(set) var lastError: String?
    /// Аудит 26.07.2026 (P0): отдельный канал ТОЛЬКО для ошибок загрузки медиа.
    /// Раньше в оверлей плеера падал любой lastError (kick, chat catch-up,
    /// «Voice chat requires Plink+») и рисовал чёрный экран поверх идущего видео.
    public private(set) var mediaError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var hardCorrectionCount: Int = 0
    public private(set) var lastDriftMs: Double = 0
    // P1-51: reactions — renamed to WatchReactionEvent to avoid @Observable
    // macro type ambiguity with existing ReactionEvent from SyncEvents.swift
    // P1-61: reactions auto-expire after 3 seconds
    public private(set) var reactions: [WatchReactionEvent] = []
    private var reactionExpiryTask: Task<Void, Never>?

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator
    private let playbackProxy: PlaybackProxy  // P0-29: stable proxy for syncController

    // PATCH 14: DanmakuEngine + AmbientVideoSampler owned by the model.
    // One per room session — never global singletons (runbook §16).
    // The engine is fed by chat broadcast handler (chat messages become
    // danmaku placements). The sampler is fed by coordinator.nativePlayer
    // (palette drives PurpleAmbientBackdrop).
    private let danmakuEngine: DanmakuEngine
    private let ambientSampler: AmbientVideoSampler
    private var danmakuSnapshot: [DanmakuPlacement] = []
    private var ambientPalette: AmbientPalette = .defaultPalette
    /// M27: live blurred backdrop frame (Rave-style) — read by WatchRoomSocialRegion.
    var ambientFrame: UIImage?
    private var danmakuPollTask: Task<Void, Never>?
    private var ambientSampleTask: Task<Void, Never>?

    // MARK: - Config
    // P0-30: roomId stored as _roomId (private) + protocol conformance via
    // computed var roomId: String? { _roomId }. Only ONE declaration.
    private let _roomId: String
    /// May be recovered after connect if create/join stripped mediaItem.
    public private(set) var mediaSource: PlaybackSource?
    public private(set) var mediaId: String?  // P1-33: typed media ID for host commands
    public private(set) var roomCode: String?
    public let currentUserId: String  // P1-32: identity via init, not UserDefaults
    public let currentUsername: String  // P1-32
    private var chatCatchupCursor: String?  // P0-59: opaque server cursor
    // P0-60: persistent messageIds set — initialized from current chatMessages
    private var knownMessageIds = Set<String>()
    private var clientMessageIds = Set<String>()
    private var stateChangesTask: Task<Void, Never>?
    // P0-52/P1-63: serial state pump — coalesce to latest state
    private var statePumpTask: Task<Void, Never>?
    private var pendingStates: [RealtimeRoomState] = []
    // P0-58: snapshot revision — buffer participant events during snapshot fetch
    private var snapshotInFlight = false
    private var bufferedParticipantEvents: [(isJoin: Bool, userId: String, username: String)] = []
    // P0-61: single authoritative rollback state
    private var lastAuthoritativeState: RealtimeRoomState?

    /// P1 5.11: живая тема комнаты (Plink+). Стор — на комнату; realtime-событие
    /// room.appearance.updated зовёт applyServerUpdate, хост меняет тему через
    /// updateTheme. Тип internal, поэтому свойство не может быть public.
    private(set) var appearanceStore: RoomAppearanceStore

    // P0-35: REST client for chat catch-up
    private let chatCatchupClient: ChatCatchupClient?
    /// Host user id from Room model (presence highlight).
    private let roomHostId: String?

    // P0-5: init — class is @MainActor, init inherits isolation.
    // Default params use nil-coalescing inside body to avoid @MainActor
    // default expression evaluation in nonisolated context.
    public init(
        roomId: String,
        currentUserId: String,
        currentUsername: String,
        baseEndpoint: URL,
        ticketProvider: @escaping (String) async throws -> RealtimeTicket,
        mediaSource: PlaybackSource? = nil,
        mediaId: String? = nil,
        roomCode: String? = nil,
        chatCatchupClient: ChatCatchupClient? = nil,
        clock: ClockSynchronizer? = nil,
        coordinator: PlaybackCoordinator? = nil,
        roomHostId: String? = nil
    ) {
        self._roomId = roomId
        self.currentUserId = currentUserId
        self.currentUsername = currentUsername
        self.mediaSource = mediaSource
        self.mediaId = mediaId
        self.roomCode = roomCode
        self.chatCatchupClient = chatCatchupClient
        self.roomHostId = roomHostId
        let resolvedClock = clock ?? ClockSynchronizer()
        self.clock = resolvedClock
        self.coordinator = coordinator ?? PlaybackCoordinator()

        // P0-29: create stable proxy — syncController talks to proxy, not dummy
        let proxy = PlaybackProxy()
        self.playbackProxy = proxy
        self.syncController = OrderedSyncController(clock: resolvedClock, player: proxy)

        // PATCH 14: instantiate engine + sampler BEFORE any use of self
        // (delegate = self below requires all stored properties initialized).
        // PATCH 16g: capture local let before assigning to self, so the
        // Task can configure it without requiring self to be fully
        // initialized.
        let danmakuEngine = DanmakuEngine()
        let ambientSampler = AmbientVideoSampler()
        self.danmakuEngine = danmakuEngine
        self.ambientSampler = ambientSampler

        // P1 5.11: живая тема комнаты. Стор создаётся здесь и живёт ровно
        // столько же, сколько модель (модель — в @State у WatchRoomContainer),
        // поэтому смена темы переживает пересборку вью и поворот экрана.
        // Роль ещё не известна (она придёт в session.ready) — стартуем с
        // предположения по hostID комнаты и уточняем в sessionDidConnect.
        self.appearanceStore = RoomAppearanceStore(
            roomID: roomId,
            isHost: roomHostId != nil && roomHostId == currentUserId,
            entitlement: DefaultEntitlementProvider()
        )

        // Now all stored properties are initialized — safe to use self.
        self.realtimeClient = RealtimeClient(baseEndpoint: baseEndpoint, ticketProvider: ticketProvider)
        self.realtimeClient.delegate = self

        // PATCH 16: DanmakuEngine has no startSampling() — caller polls
        // via poll(at:) which is started in connect().
        Task { @MainActor [danmakuEngine] in
            await danmakuEngine.configure(laneCount: 5)
        }
    }

    // MARK: - Invite / Share

    public var shareRoomId: String { _roomId }

    public var displayRoomCode: String {
        if let roomCode, !roomCode.isEmpty { return roomCode.uppercased() }
        return String(_roomId.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
    }

    // Ссылки несут КОД комнаты, а не UUID: сервер джойнит только по коду
    // (POST /rooms/join { code }), и лендинг с AASA живёт на /r/<code>.
    //
    // P2-фикс аудита: код приходит с сервера, поэтому перед подстановкой в URL
    // его надо экранировать — пробел или не-ASCII символ раньше давал nil и
    // краш на force-unwrap при открытии шита приглашения.
    //
    // Ревью P2: именно экранирование, а не выкидывание символов — иначе ссылка
    // и QR молча расходились бы с кодом, который показан в шите и в шер-тексте.
    private var linkRoomCode: String {
        displayRoomCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? displayRoomCode
    }

    public var roomDeepLink: URL {
        URL(string: "plink://r/\(linkRoomCode)") ?? URL(string: "plink://r")!
    }

    public var roomFallbackURL: URL {
        URL(string: "https://plink.app/r/\(linkRoomCode)") ?? URL(string: "https://plink.app")!
    }

    public var roomShareText: String {
        "Смотри со мной в Plink 🎬\nКод комнаты: \(displayRoomCode)\n\(roomDeepLink.absoluteString)\nЕсли ссылка не открылась: \(roomFallbackURL.absoluteString)"
    }

    // MARK: - Lazy Auth / Smart Wall

    func checkServiceAccess(for service: ServiceType) -> Bool {
        Self.checkServiceAccess(for: service)
    }

    static func checkServiceAccess(for service: ServiceType) -> Bool {
        ServiceAuthStore.hasAccess(to: service)
    }

    // MARK: - Lifecycle

    /// Set true by leaveRoom so the view can dismiss even if connection never reached .connected.
    public private(set) var wantsDismiss: Bool = false

    public func connect() async {
        wantsDismiss = false
        connectionState = .connecting
        // Новая попытка — прошлая медиа-ошибка не должна закрывать плеер.
        mediaError = nil

        // Show local user immediately (never "0 in room" while WS is negotiating)
        if !participants.contains(where: { $0.userId == currentUserId }) {
            participants.insert(
                ParticipantInfo(userId: currentUserId, username: currentUsername, isLocal: true),
                at: 0
            )
        }

        // P0-31: subscribe to stateChanges stream
        startStateChangesSubscription()

        // Realtime first — chat/presence must work even while YouTube is loading.
        realtimeClient.connect(roomId: _roomId)
        startDanmakuPolling()
        // P1 5.11: тема, выбранная хостом ДО нашего входа, живёт в БД —
        // событие room.appearance.updated её не переиграет, пока хост не
        // тронет панель. Поэтому гидрируем из GET /rooms/:id.
        Task { await loadAppearance() }

        // Media prepare: resolve YouTube/native handoff off the main actor while
        // realtime chat/presence are already connecting. This keeps the room UI
        // responsive during backend extraction and falls back to the official
        // embedded player if no native MP4/HLS stream is available quickly.
        let sourceToPrepare = await resolveMediaSourceForPlayback()

        if let source = sourceToPrepare {
            do {
                try await coordinator.prepare(source)
                playbackProxy.attachTarget(coordinator.currentController)

                if let embedded = coordinator.currentController as? EmbeddedPlaybackController {
                    embedded.onUserPlaybackChange = { [weak self] playing, position in
                        self?.publishHostPlaybackState(playing: playing, positionSeconds: position)
                    }
                }

                if let player = coordinator.nativePlayer {
                    await ambientSampler.attach(player: player)
                    await ambientSampler.startSampling()
                    startAmbientPalettePolling()
                }
            } catch {
                // P0 FIX: the native AVPlayer path can still fail (expired
                // stream, poisoned cache, 403). Recover with the official
                // embedded player instead of dead-ending with an error.
                var recovered = false
                if case .youtube = source {
                    // embedded path itself failed — nothing to fall back to
                } else if let ytId = mediaId {
                    await YouTubeNativeStreamCache.shared.invalidate(videoId: ytId)
                    if (try? await coordinator.prepare(.youtube(ytId))) != nil {
                        playbackProxy.attachTarget(coordinator.currentController)
                        if let embedded = coordinator.currentController as? EmbeddedPlaybackController {
                            embedded.onUserPlaybackChange = { [weak self] playing, position in
                                self?.publishHostPlaybackState(playing: playing, positionSeconds: position)
                            }
                        }
                        mediaSource = .youtube(ytId)
                        recovered = true
                    }
                }
                if !recovered {
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    lastError = "Не удалось загрузить видео: \(detail)"
                    mediaError = lastError
                }
            }
        } else {
            lastError = "Нет медиа в комнате — выберите YouTube-видео при создании"
            mediaError = lastError
        }
    }

    /// Resolve the media source used for this session without blocking room
    /// realtime startup on slow backend extraction. YouTube native extraction
    /// races a short grace window; if it does not win, the official embedded
    /// player is prepared and the extraction task continues only to warm cache.
    private func resolveMediaSourceForPlayback() async -> PlaybackSource? {
        if mediaSource == nil {
            if let recovered = await Self.refetchMediaSource(roomId: _roomId) {
                mediaSource = recovered.source
                if mediaId == nil { mediaId = recovered.mediaId }
            }
        }

        guard let source = mediaSource else { return nil }
        guard case .youtube(let ytId) = source else { return source }

        // YouTube native extraction (AVPlayer path) — enabled in ALL builds
        // (Debug + Release). Was #if DEBUG which broke Release/App Store builds.
        let nativeTask = Task.detached(priority: .userInitiated) {
            await Self.extractYouTubeNativePlaybackSource(videoId: ytId)
        }

        let nativeWithinGrace = await withTaskGroup(of: PlaybackSource?.self) { group in
            group.addTask { await nativeTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 450_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        if let nativeWithinGrace {
            mediaSource = nativeWithinGrace
            return nativeWithinGrace
        }

        Task.detached(priority: .utility) {
            _ = await nativeTask.value
        }
        return source
    }

    /// Recover YouTube/media when create/join returned room without mediaItem.
    private static func refetchMediaSource(roomId: String) async -> (source: PlaybackSource, mediaId: String?)? {
        do {
            let room = try await RoomService(api: APIClient.shared).fetchRoom(id: roomId)
            guard let source = WatchRoomCompositionRoot.mediaSource(from: room) else { return nil }
            let mid = room.mediaItem?.videoId ?? room.mediaItem?.id
            return (source, mid)
        } catch {
            Logger.api.error("[WatchRoom] refetch media failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract and cache a native YouTube stream source off the main actor.
    /// Returns nil if extraction fails; callers fall back to .youtube WKWebView.
    /// Enabled in ALL builds (Debug + Release) — was #if DEBUG which broke
    /// Release/App Store builds (player fell back to WKWebView in production).
    private nonisolated static func extractYouTubeNativePlaybackSource(videoId: String) async -> PlaybackSource? {
        // P1 audit: remote kill-switch — when disabled, return nil so the
        // caller falls back to the embedded YouTube player (App Store-safe).
        guard FeatureFlags.youtubeNativeExtraction else { return nil }

        if let cached = await YouTubeNativeStreamCache.shared.source(for: videoId) {
            return cached
        }
        // ── P0 FIX (YouTube infinite loading) ──────────────────────────
        // Never hand AVPlayer the raw googlevideo URL from /media/extract:
        // those URLs are IP-bound to the backend server IP, so on-device
        // requests get HTTP 403 → AVPlayer fails with -11828 and the player
        // spun forever. Stream through the backend reverse proxy instead
        // (/api/media/youtube-stream), which fetches upstream from the same
        // IP that extracted the URL and supports Range requests.
        let api = APIClient.shared
        if api.authToken == nil {
            api.authToken = AuthTokenStore.shared.token
        }
        guard api.authToken != nil else { return nil }

        // P1 audit: never put the long-lived session JWT into a query string
        // (URLs leak into logs/proxies). Ask for a 45-min media-scoped token.
        struct StreamTokenResp: Decodable { let token: String }
        let token: String
        do {
            let resp: StreamTokenResp = try await api.request("media/stream-token", method: .post)
            token = resp.token
        } catch {
            // P2-фикс аудита: legacy-ветка клала сам session JWT в query —
            // ровно то, что запрещает комментарий выше. Бэкенд уже отдаёт
            // stream-token, поэтому при ошибке просто падаем на встроенный
            // YouTube-плеер.
            Logger.api.error("[WatchRoom] stream-token failed: \(error.localizedDescription)")
            return nil
        }

        var components = URLComponents(
            url: api.baseURL.appendingPathComponent("media/youtube-stream"),
            resolvingAgainstBaseURL: false
        )
        // AVPlayer drops custom headers on Range requests → token as query param.
        components?.queryItems = [
            URLQueryItem(name: "id", value: videoId),
            URLQueryItem(name: "token", value: token),
        ]
        guard let proxyURL = components?.url else { return nil }

        // Preflight (bytes 0-1): commit to the native path only if the proxy
        // actually serves media. On any failure return nil → caller falls
        // back to the official embedded YouTube player.
        var probe = URLRequest(url: proxyURL)
        probe.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        probe.timeoutInterval = 6
        guard
            let (_, response) = try? await URLSession.shared.data(for: probe),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200 || http.statusCode == 206
        else { return nil }

        let source = PlaybackSource.mp4(proxyURL, headers: [:])
        await YouTubeNativeStreamCache.shared.store(source, for: videoId)
        return source
    }

    /// Extract direct stream URL from backend /api/media/extract for AVPlayer.
    /// Network work is nonisolated so WatchRoomModel's main actor is not held
    /// while the backend races yt-dlp/Piped/Innertube.
    private nonisolated static func extractYouTubeStreamURL(videoId: String) async -> URL? {
        let api = APIClient.shared
        if api.authToken == nil {
            api.authToken = AuthTokenStore.shared.token
        }
        guard let token = api.authToken else {
            return nil
        }

        var components = URLComponents(url: api.baseURL.appendingPathComponent("media/extract"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: videoId)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            struct StreamInfo: Decodable {
                let streamURL: String?
                let hlsURL: String?
            }
            let info = try JSONDecoder().decode(StreamInfo.self, from: data)
            let urlString = info.hlsURL ?? info.streamURL
            guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    public func disconnect() {
        stateChangesTask?.cancel()
        stateChangesTask = nil
        statePumpTask?.cancel()
        statePumpTask = nil
        pendingStates.removeAll()
        pendingActions.removeAll()
        reactionExpiryTask?.cancel()
        reactionExpiryTask = nil
        // P2-фикс аудита: отсчёт 3-2-1 тоже надо гасить — иначе выход из
        // комнаты во время отсчёта оставляет задачу жить и она дёргает
        // sendPlayCommand по уже разобранному координатору.
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
        realtimeClient.disconnect()
        coordinator.teardown()
        syncController.resetCompletely()
        clock.reset()
        participants = []
        chatMessages = []
        reactions = []
        clientMessageIds.removeAll()
        connectionState = .idle

        // PATCH 14: stop engine + sampler
        // PATCH 16: DanmakuEngine has no stopSampling() — cancelling the
        // poll task is sufficient (engine itself is passive).
        danmakuPollTask?.cancel()
        danmakuPollTask = nil
        ambientSampleTask?.cancel()
        ambientSampleTask = nil
        Task { [danmakuEngine, ambientSampler] in
            await danmakuEngine.clear()
            await ambientSampler.stopSampling()
            await ambientSampler.detach()
        }
        danmakuSnapshot = []
        ambientPalette = .defaultPalette
    }

    // MARK: - PATCH 14: Danmaku polling

    /// Polls the DanmakuEngine every 250ms for the current placement
    /// snapshot. Caches in danmakuSnapshot so views can read without
    /// awaiting on the actor during render.
    private func startDanmakuPolling() {
        danmakuPollTask?.cancel()
        danmakuPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = ContinuousClock.now
                let snapshot = await self.danmakuEngine.poll(at: now)
                self.danmakuSnapshot = snapshot
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Updates the danmaku lane count based on orientation. Called by
    /// WatchRoomScreen on rotation.
    public func updateDanmakuLaneCount(_ count: Int) {
        Task { [danmakuEngine] in
            await danmakuEngine.configure(laneCount: count)
        }
    }

    // MARK: - PATCH 14: Ambient palette polling

    /// Polls the AmbientVideoSampler every 500ms for the current palette.
    /// Caches in ambientPalette so views can read without awaiting.
    private func startAmbientPalettePolling() {
        ambientSampleTask?.cancel()
        ambientSampleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let palette = await self.ambientSampler.currentPalette()
                let frame = await self.ambientSampler.currentFrame()
                let enabled = AmbientCapability.shouldEnableLivingBackground()
                self.ambientPalette = enabled ? palette : .defaultPalette
                self.ambientFrame = enabled ? frame : nil
                await self.ambientSampler.setEnabled(enabled)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // P0-31: subscribe to RealtimeClient.stateChanges
    private func startStateChangesSubscription() {
        stateChangesTask?.cancel()
        stateChangesTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.realtimeClient.stateChanges {
                guard !Task.isCancelled else { return }
                self.connectionState = state
            }
        }
    }

    // P0-54: pending actions for reconciliation/rollback
    private struct PendingAction {
        let actionId: String
        let preActionPosition: Double
        let preActionPlaying: Bool
        let timestamp: Date
        // Аудит 26.07.2026 P1: epoch/seq на момент отправки — авторитетное
        // состояние с бОльшим (epoch, seq) означает подтверждение команды.
        let epochAtSend: Int64
        let seqAtSend: Int64
    }
    private var pendingActions: [String: PendingAction] = [:]
    private static let actionTimeoutMs: Int64 = 10_000

    // MARK: - Host commands (P0-33: functional with optimistic local apply + P0-54: reconciliation)

    public func sendPlayCommand() async {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local apply
        await coordinator.currentController?.play()
        // Ревью P2: play() — точка подвеса. Если за это время комнату покинули
        // (disconnect уже почистил pendingActions), запись нельзя заводить
        // заново: её таймаут через 10 с напишет ложную ошибку вне комнаты.
        guard connectionState != .idle else { return }
        let actionId = UUID().uuidString
        // P0-54: track pending action for rollback
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, // Аудит 26.07.2026 P1
            seqAtSend: lastSeq
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: true
        )))
        scheduleActionTimeout(actionId)
    }

    public func sendPauseCommand() {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local apply
        coordinator.currentController?.pause()
        let actionId = UUID().uuidString
        // P0-54: track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, // Аудит 26.07.2026 P1
            seqAtSend: lastSeq
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: false
        )))
        scheduleActionTimeout(actionId)
    }

    public func sendSeekCommand(to seconds: TimeInterval) async {
        guard isHost else { return }
        let positionMs = Int64(seconds * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local seek
        _ = await coordinator.currentController?.seek(to: seconds, precise: true)
        // Ревью P2: та же точка подвеса, что и в sendPlayCommand.
        guard connectionState != .idle else { return }
        let actionId = UUID().uuidString
        // P0-54: track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, // Аудит 26.07.2026 P1
            seqAtSend: lastSeq
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: coordinator.isPlaying
        )))
        scheduleActionTimeout(actionId)
    }

    // P0-62: single authoritative rollback — NOT concurrent Tasks per action.
    // Rollback to last authoritative state, request fresh snapshot.
    private func handleActionRejection(_ errorCode: String) {
        pendingActions.removeAll()
        // P0-61/P0-62: restore to last authoritative state in a single operation
        if let state = lastAuthoritativeState {
            Task { [weak self] in
                guard let self else { return }
                let target = Double(state.positionMs) / 1000.0
                _ = await self.coordinator.currentController?.seek(to: target, precise: true)
                if state.playing {
                    await self.coordinator.currentController?.play()
                } else {
                    self.coordinator.currentController?.pause()
                }
                self.coordinator.currentController?.setRate(Float(state.rate))
            }
        }
        // P0-62: request fresh snapshot immediately
        realtimeClient.send(.stateRequest(.init(roomId: _roomId, afterSeq: lastSeq)))
        lastError = "Command rejected: \(errorCode) — rolled back to authoritative state"
    }

    // P0-54: timeout pending actions
    private func scheduleActionTimeout(_ actionId: String) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.actionTimeoutMs) * 1_000_000)
            guard let self else { return }
            if self.pendingActions[actionId] != nil {
                self.pendingActions.removeValue(forKey: actionId)
                self.lastError = "Command timeout — no server confirmation"
            }
        }
    }

    // P0-54: clear pending action when authoritative state arrives
    // Аудит 26.07.2026 P1: раньше параметр state игнорировался — команды никогда
    // не «подтверждались», и scheduleActionTimeout через 10 с писал ложный
    // "Command timeout" на каждую команду хоста. Теперь команда считается
    // подтверждённой, когда пришло авторитетное состояние, выпущенное ПОСЛЕ
    // её отправки: state.(epoch, seq) > (epochAtSend, seqAtSend).
    private func clearPendingActionsIfConfirmed(state: RealtimeRoomState) {
        pendingActions = pendingActions.filter { (_, action) in
            let confirmed = state.epoch > action.epochAtSend
                || (state.epoch == action.epochAtSend && state.seq > action.seqAtSend)
            if confirmed { return false }
            // Страховка от вечно висящих записей (таймаут-задача уже покажет ошибку)
            return Date().timeIntervalSince(action.timestamp) < Double(Self.actionTimeoutMs / 1000)
        }
    }

    // MARK: - Chat (optimistic + reconciliation + P1-54 failure/retry)

    public func sendChat(text: String) {
        let clientMessageId = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        let displayText = PlinkBubbleWire.decode(text).text
        let wireText = PlinkBubbleWire.encode(text: displayText, styleID: styleID)
        let optimistic = ChatMessageInfo(
            messageId: nil,
            clientMessageId: clientMessageId,
            senderId: currentUserId,
            senderName: currentUsername,
            text: displayText,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            isPending: true,
            isFailed: false,
            bubbleStyle: styleID
        )
        chatMessages.append(optimistic)
        clientMessageIds.insert(clientMessageId)
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId,
            clientMessageId: clientMessageId,
            text: wireText
        )))
        AnalyticsService.shared.messageSent()
        // P1-54: schedule 5s timeout — mark as failed if no server echo
        scheduleChatSendTimeout(clientMessageId: clientMessageId)
    }

    // MARK: - M13: Room polls + offline queue badge

    /// Number of chat/reaction messages queued while offline (see RealtimeClient).
    public var queuedMessageCount: Int { realtimeClient.queuedUserMessageCount }

    // MARK: - M14: Синхронный отсчёт 3-2-1

    /// Хост: если в комнате есть зрители — общий отсчёт для всех, потом play.
    /// Один в комнате — обычный мгновенный старт без церемоний.
    public func sendPlayWithCountdown() {
        guard isHost else { return }
        // P2-фикс аудита: повторный тап во время отсчёта не должен обходить
        // отсчёт мгновенным play — просто игнорируем.
        if countdownRemaining != nil { return }
        guard !coordinator.isPlaying, participants.count >= 2 else {
            Task { await sendPlayCommand() }
            return
        }
        let startAt = Date().addingTimeInterval(3.2)
        let event = RoomCountdownWire.Event(startAtMs: Int64(startAt.timeIntervalSince1970 * 1000))
        if let wire = RoomCountdownWire.encode(event) {
            realtimeClient.send(.chatSend(.init(
                roomId: _roomId, clientMessageId: UUID().uuidString, text: wire
            )))
        }
        runCountdown(until: startAt, thenPlay: true)
    }

    private func runCountdown(until startAt: Date, thenPlay: Bool) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = startAt.timeIntervalSinceNow
                if remaining <= 0 { break }
                self.countdownRemaining = max(1, Int(remaining.rounded(.up)))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.countdownRemaining = nil
            if thenPlay { await self.sendPlayCommand() }
        }
    }

    /// Creates a poll and broadcasts it over the chat protocol.
    public func sendPoll(question: String, options: [String]) {
        let cleanQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanQuestion.isEmpty, cleanOptions.count >= 2 else { return }
        let finalOptions = Array(cleanOptions.prefix(4))
        let pollId = UUID().uuidString
        let event = RoomPollWire.Event(
            kind: .create, pollId: pollId,
            question: cleanQuestion, options: finalOptions, optionIndex: nil
        )
        guard let wire = RoomPollWire.encode(event) else { return }
        activePoll = RoomPollState(
            id: pollId, question: cleanQuestion, options: finalOptions,
            votes: [:], createdBy: currentUserId, createdByName: currentUsername
        )
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId, clientMessageId: UUID().uuidString, text: wire
        )))
    }

    public func votePoll(optionIndex: Int) {
        guard var poll = activePoll, !poll.isClosed,
              poll.options.indices.contains(optionIndex),
              poll.votes[currentUserId] == nil else { return }
        poll.votes[currentUserId] = optionIndex
        activePoll = poll
        let event = RoomPollWire.Event(
            kind: .vote, pollId: poll.id,
            question: nil, options: nil, optionIndex: optionIndex
        )
        guard let wire = RoomPollWire.encode(event) else { return }
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId, clientMessageId: UUID().uuidString, text: wire
        )))
    }

    public func closePoll() {
        guard var poll = activePoll, poll.createdBy == currentUserId else { return }
        poll.isClosed = true
        activePoll = poll
        let event = RoomPollWire.Event(
            kind: .close, pollId: poll.id,
            question: nil, options: nil, optionIndex: nil
        )
        if let wire = RoomPollWire.encode(event) {
            realtimeClient.send(.chatSend(.init(
                roomId: _roomId, clientMessageId: UUID().uuidString, text: wire
            )))
        }
        hidePollLater(poll.id)
    }

    /// Local-only dismissal of the poll card.
    public func dismissPoll() { activePoll = nil }

    private func hidePollLater(_ pollId: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.activePoll?.id == pollId { self?.activePoll = nil }
        }
    }

    private func applyPollEvent(_ event: RoomPollWire.Event, senderId: String, senderName: String) {
        switch event.kind {
        case .create:
            guard let question = event.question,
                  let options = event.options, options.count >= 2 else { return }
            if activePoll?.id == event.pollId { return }
            activePoll = RoomPollState(
                id: event.pollId, question: question, options: Array(options.prefix(4)),
                votes: [:], createdBy: senderId, createdByName: senderName
            )
        case .vote:
            guard var poll = activePoll, poll.id == event.pollId, !poll.isClosed,
                  let idx = event.optionIndex, poll.options.indices.contains(idx) else { return }
            poll.votes[senderId] = idx
            activePoll = poll
        case .close:
            guard var poll = activePoll, poll.id == event.pollId else { return }
            poll.isClosed = true
            activePoll = poll
            hidePollLater(poll.id)
        }
    }

    public func sendPhoto(dataURL: String, previewImage: UIImage?, caption: String) {
        let clientMessageId = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        let displayText = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1800))
        let wireText = PlinkBubbleWire.encode(text: displayText, styleID: styleID)
        let local = ChatMessageInfo(
            messageId: nil,
            clientMessageId: clientMessageId,
            senderId: currentUserId,
            senderName: currentUsername,
            text: displayText,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            isPending: true,
            isFailed: false,
            bubbleStyle: styleID,
            mediaType: "photo",
            hasMedia: true
        )
        chatMessages.append(local)
        clientMessageIds.insert(clientMessageId)
        if let previewImage { ChatPhotoCache.shared.register(previewImage, for: clientMessageId) }
        if chatMessages.count > 200 { chatMessages.removeFirst(chatMessages.count - 200) }

        struct Body: Encodable {
            let imageData: String
            let content: String
            let clientMessageId: String
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let saved: ChatPhotoSendResponse = try await APIClient.shared.request(
                    "rooms/\(_roomId)/messages/photo",
                    method: .post,
                    body: Body(imageData: dataURL, content: wireText, clientMessageId: clientMessageId)
                )
                if let previewImage {
                    ChatPhotoCache.shared.promote(from: clientMessageId, to: saved.messageId)
                    ChatPhotoCache.shared.register(previewImage, for: saved.messageId)
                }
                if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                    let decoded = PlinkBubbleWire.decode(saved.text.isEmpty ? wireText : saved.text)
                    chatMessages[idx] = ChatMessageInfo(
                        messageId: saved.messageId,
                        clientMessageId: saved.clientMessageId ?? clientMessageId,
                        senderId: saved.senderId,
                        senderName: saved.senderName,
                        text: decoded.text,
                        createdAtMs: saved.createdAtMs,
                        isPending: false,
                        isFailed: false,
                        bubbleStyle: decoded.styleID ?? styleID,
                        mediaType: saved.mediaType ?? "photo",
                        hasMedia: saved.hasMedia ?? true
                    )
                }
            } catch {
                if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                    let msg = chatMessages[idx]
                    chatMessages[idx] = ChatMessageInfo(
                        messageId: msg.messageId,
                        clientMessageId: msg.clientMessageId,
                        senderId: msg.senderId,
                        senderName: msg.senderName,
                        text: msg.text,
                        createdAtMs: msg.createdAtMs,
                        isPending: false,
                        isFailed: true,
                        bubbleStyle: msg.bubbleStyle,
                        mediaType: msg.mediaType,
                        hasMedia: msg.hasMedia
                    )
                }
                lastError = "Photo send failed: \(error.localizedDescription)"
            }
        }
    }

    // P1-54: retry a failed chat message
    /// Host kicks a participant via REST (POST /api/rooms/:id/kick).
    @discardableResult
    public func kickParticipant(userId: String) async -> Bool {
        guard isHost, userId != currentUserId else { return false }
        struct Body: Encodable { let userId: String }
        struct Resp: Decodable { let success: Bool? }
        do {
            let _: Resp = try await APIClient.shared.request(
                "rooms/\(_roomId)/kick",
                method: .post,
                body: Body(userId: userId)
            )
            participants.removeAll { $0.userId == userId }
            return true
        } catch {
            lastError = "Kick failed: \(error.localizedDescription)"
            return false
        }
    }

    public func retryChatMessage(_ message: ChatMessageInfo) {
        guard message.isFailed, let cmid = message.clientMessageId else { return }
        let style = message.bubbleStyle ?? PlinkBubbleStylePrefs.currentID
        let wire = PlinkBubbleWire.encode(text: message.text, styleID: style)
        // Find and update the message back to pending
        if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
            chatMessages[idx] = ChatMessageInfo(
                messageId: nil,
                clientMessageId: cmid,
                senderId: message.senderId,
                senderName: message.senderName,
                text: message.text,
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                isPending: true,
                isFailed: false,
                bubbleStyle: style
            )
        }
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId,
            clientMessageId: cmid,
            text: wire
        )))
        scheduleChatSendTimeout(clientMessageId: cmid)
    }

    // P1-54: mark message as failed after 5s if no server confirmation
    private func scheduleChatSendTimeout(clientMessageId: String) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            // If still pending (no server echo), mark as failed
            if let idx = self.chatMessages.firstIndex(where: {
                $0.clientMessageId == clientMessageId && $0.isPending
            }) {
                let msg = self.chatMessages[idx]
                self.chatMessages[idx] = ChatMessageInfo(
                    messageId: msg.messageId,
                    clientMessageId: msg.clientMessageId,
                    senderId: msg.senderId,
                    senderName: msg.senderName,
                    text: msg.text,
                    createdAtMs: msg.createdAtMs,
                    isPending: false,
                    isFailed: true,
                    bubbleStyle: msg.bubbleStyle
                )
            }
        }
    }

    // MARK: - RealtimeClientDelegate

    // P0-30: roomId protocol conformance — protocol requires String?
    // but our roomId is non-optional String. Return wrapped optional.
    public var roomId: String? { _roomId }

    public var lastEpoch: Int64 { syncController.lastEpoch }
    public var lastSeq: Int64 { syncController.lastSeq }

    public func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double) {
        clock.ingest(clientSentMs: clientSentMs, serverMs: serverMs, clientReceivedMs: clientReceivedMs)
        clockSynced = clock.isSynchronized
    }

    // P0-52: serial state pump — enqueue state, process in order
    public func applySnapshot(_ state: RealtimeRoomState?) {
        guard let state = state else { return }
        pendingStates.append(state)
        startStatePumpIfNeeded()
    }

    private func startStatePumpIfNeeded() {
        guard statePumpTask == nil, !pendingStates.isEmpty else { return }
        statePumpTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingStates.isEmpty && !Task.isCancelled {
                let state = self.pendingStates.removeFirst()
                await self.syncController.apply(state)
                // P0-61: store last authoritative state for rollback
                self.lastAuthoritativeState = state
                // P1-34: update UI metrics AFTER each apply completes
                self.hardCorrectionCount = self.syncController.hardCorrectionCount
                self.lastDriftMs = self.syncController.lastDriftMs
                // P0-61: clear pending actions that match this state
                self.clearPendingActionsIfConfirmed(state: state)
            }
            self.statePumpTask = nil
        }
    }

    // P0-30: sessionDidConnect now carries role
    public func sessionDidConnect(role: RoomRole) {
        self.role = role
        self.isHost = (role == .host)
        // P1 5.11: панель темы комнаты — только у хоста; роль авторитетна здесь.
        appearanceStore.setHost(role == .host)
        connectionState = .connected
        // Avoid "0 in room" flash — ensure local user is listed immediately
        if !participants.contains(where: { $0.userId == currentUserId }) {
            participants.insert(
                ParticipantInfo(userId: currentUserId, username: currentUsername, isLocal: true),
                at: 0
            )
        }
        // P0-35: request chat catch-up after reconnect
        Task { await fetchChatCatchup() }
        // P0-36: request presence snapshot
        Task { await fetchPresenceSnapshot() }
    }

    /// Broadcast host playback state without re-applying local player (avoids feedback loops).
    public func publishHostPlaybackState(playing: Bool, positionSeconds: Double) {
        guard isHost else { return }
        let positionMs = Int64(max(0, positionSeconds) * 1000)
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: playing
        )))
        // Аудит 26.07.2026 P1: scheduleActionTimeout здесь убран — PendingAction
        // для периодического публиша не регистрируется, таймер был пустым no-op.
    }

    /// Показать пользователю НЕ медийную ошибку (модерация, отказ действия).
    /// Пишем в lastError — экран комнаты рисует его тостом. В mediaError не
    /// пишем никогда: тот канал рисует полноэкранную ошибку поверх видео.
    func reportRoomError(_ message: String) {
        lastError = message
    }

    /// Ревью 26.07.2026: экран гасит lastError сразу после показа тоста.
    /// Иначе повтор той же ошибки (тот же текст) не проходил Equatable-проверку
    /// `.onChange(of: model.lastError)` и второй раз не показывался вообще.
    func clearLastError() {
        lastError = nil
    }

    public func handleOtherMessage(_ message: RealtimeServerMessage) {
        switch message {
        case .chatBroadcast(let chat):
            handleChatBroadcast(chat)
        case .reactionBroadcast(let reaction):
            handleReaction(reaction)
        case .participantJoined(let event):
            handleParticipantJoined(event)
        case .participantLeft(let event):
            handleParticipantLeft(event)
        case .serverDraining(let drain):
            lastError = drain.message
        // P1 5.11: живая тема комнаты — авторитетное состояние приходит только
        // отсюда, у хоста и у зрителей одинаково.
        case .roomAppearanceUpdated(let event):
            appearanceStore.applyServerUpdate(RoomAppearance(wire: event.appearance))
        case .error(let err):
            lastError = "\(err.code): \(err.message)"
            // P0-54: rollback on rejection errors
            if err.code == "NOT_HOST" || err.code == "STALE_EPOCH" || err.code == "RATE_LIMITED" {
                handleActionRejection(err.code)
            }
            // M16: сервер отклонил сообщение из-за мута — синхронизируем таймер локально.
            if err.code == "MUTED" {
                let digits = err.message.filter { $0.isNumber }
                if let secs = Int(digits), secs > 0 {
                    mutedUntil = Date().addingTimeInterval(TimeInterval(min(secs, 600)))
                }
            }
        case .syncState, .syncStateSnapshot, .clockProbeReply, .sessionReady:
            break
        }
    }

    // MARK: - Private handlers

    private func handleChatBroadcast(_ chat: RealtimeServerMessage.ChatBroadcast) {
        // M14: countdown events ride on chat — intercept before bubbles.
        if let countdown = RoomCountdownWire.decode(chat.text) {
            if chat.senderId != currentUserId {
                let startAt = Date(timeIntervalSince1970: Double(countdown.startAtMs) / 1000)
                runCountdown(until: startAt, thenPlay: false)
            }
            return
        }
        // M15: смена приватности едет по чату — не рендерим как сообщение.
        if let modEvent = RoomModerationWire.decode(chat.text) {
            if let newPrivacy = RoomPrivacy(rawValue: modEvent.privacy) {
                roomPrivacy = newPrivacy
            }
            return
        }

        // M16: ИИ-модератор — муты едут по чату. Рен��ерим системную строку,
        // а если замучен текущий юзер — блокируем ввод на seconds.
        if let aiMod = RoomAIModWire.decode(chat.text) {
            if aiMod.userId == currentUserId {
                mutedUntil = Date().addingTimeInterval(TimeInterval(aiMod.seconds))
            }
            let sys = ChatMessageInfo(
                messageId: chat.messageId,
                clientMessageId: chat.clientMessageId,
                senderId: "plink-ai-moderator",
                senderName: "ИИ-модератор",
                text: "\u{1F6E1} \(aiMod.username): мут на \(aiMod.seconds) сек — \(RoomAIModWire.reasonText(aiMod.reason))",
                createdAtMs: chat.createdAtMs,
                isPending: false,
                bubbleStyle: "bubble-quiet",
                mediaType: nil,
                hasMedia: false
            )
            chatMessages.append(sys)
            if chatMessages.count > 200 { chatMessages.removeFirst(chatMessages.count - 200) }
            return
        }

        // M16: очередь видео комнаты едет по чату — обновляем список, не рендерим как сообщение.
        if let queueEvent = RoomQueueWire.decode(chat.text) {
            roomQueue = queueEvent.queue
            return
        }

        // M13: poll events ride on chat — intercept before rendering bubbles.
        if let pollEvent = RoomPollWire.decode(chat.text) {
            if chat.senderId != currentUserId {
                applyPollEvent(pollEvent, senderId: chat.senderId, senderName: chat.senderName)
            }
            return
        }
        let decoded = PlinkBubbleWire.decode(chat.text)
        if let cmid = chat.clientMessageId, clientMessageIds.contains(cmid) {
            if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
                chatMessages[idx] = ChatMessageInfo(
                    messageId: chat.messageId,
                    clientMessageId: cmid,
                    senderId: chat.senderId,
                    senderName: chat.senderName,
                    text: decoded.text,
                    createdAtMs: chat.createdAtMs,
                    isPending: false,
                    bubbleStyle: decoded.styleID ?? chatMessages[idx].bubbleStyle,
                    mediaType: chat.mediaType,
                    hasMedia: chat.hasMedia ?? false
                )
            }
            // P0-35: update cursor for confirmed own messages too
            chatCatchupCursor = chat.messageId
            return
        }
        let msg = ChatMessageInfo(
            messageId: chat.messageId,
            clientMessageId: chat.clientMessageId,
            senderId: chat.senderId,
            senderName: chat.senderName,
            text: decoded.text,
            createdAtMs: chat.createdAtMs,
            isPending: false,
            bubbleStyle: decoded.styleID,
            mediaType: chat.mediaType,
            hasMedia: chat.hasMedia ?? false
        )
        chatMessages.append(msg)
        if let cmid = chat.clientMessageId { clientMessageIds.insert(cmid) }
        chatCatchupCursor = chat.messageId
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }

        // PATCH 14: enqueue danmaku placement for this chat message.
        // Photo messages stay in the feed and do not fly over the video.
        guard !msg.isPhotoMessage, !msg.text.isEmpty else { return }
        // Skip system/admin messages (they don't fly as danmaku).
        // Text width is estimated at 8pt per character — close enough
        // for lane scheduling; the actual rendered width is irrelevant
        // to lane availability.
        let danmakuMsg = DanmakuMessage(
            text: msg.text,
            color: .white,
            senderName: msg.senderName,
            createdAt: Date(),
            isPremium: msg.isPremium,
            isAdmin: msg.isAdmin
        )
        let estimatedWidth = CGFloat(msg.text.count * 8)
        Task { [danmakuEngine] in
            await danmakuEngine.enqueue(
                danmakuMsg,
                textWidth: estimatedWidth,
                viewportWidth: 400  // conservative default; engine clamps duration anyway
            )
        }
    }

    // P1-51/P1-61: reaction handler with auto-expiry
    private func handleReaction(_ reaction: RealtimeServerMessage.ReactionBroadcast) {
        let event = WatchReactionEvent(
            id: UUID(),
            userId: reaction.userId,
            username: reaction.username,
            emoji: reaction.emoji,
            timestampMs: reaction.serverTimeMs
        )
        reactions.append(event)
        if reactions.count > 50 {
            reactions.removeFirst(reactions.count - 50)
        }
        // P1-61: auto-expire reactions after 3 seconds
        scheduleReactionExpiry()
    }

    // P1-61: remove old reactions after 3s
    // P2-фикс аудита: раньше каждая новая реакция отменяла предыдущий таймер,
    // и при потоке реакций чаще раза в 3 с очистка не выполнялась никогда —
    // реакции накапливались. Теперь таймер один: он подметает срез каждые
    // 500 мс, пока реакции есть, и сам завершается, когда список пуст.
    private func scheduleReactionExpiry() {
        guard reactionExpiryTask == nil else { return }
        reactionExpiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                // Ревью P2: срез по локальной метке получения, поштучно.
                // Раньше здесь был счётчик подметаний, который раз в минуту
                // непрерывного потока стирал ВСЕ реакции разом (включая
                // пришедшую только что), обрывая анимацию на полуслове.
                let cutoff = Date().addingTimeInterval(-3)
                self.reactions.removeAll { $0.receivedAt < cutoff }
                if self.reactions.isEmpty {
                    self.reactionExpiryTask = nil
                    return
                }
            }
        }
    }

    private func handleParticipantJoined(_ event: RealtimeServerMessage.ParticipantEvent) {
        // P0-58: buffer if snapshot is in flight
        if snapshotInFlight {
            bufferedParticipantEvents.append((isJoin: true, userId: event.userId, username: event.username))
            return
        }
        let info = ParticipantInfo(userId: event.userId, username: event.username, isLocal: event.userId == currentUserId)
        if !participants.contains(where: { $0.userId == info.userId }) {
            participants.append(info)
        }
    }

    private func handleParticipantLeft(_ event: RealtimeServerMessage.ParticipantEvent) {
        // P0-58: buffer if snapshot is in flight
        if snapshotInFlight {
            bufferedParticipantEvents.append((isJoin: false, userId: event.userId, username: event.username))
            return
        }
        participants.removeAll { $0.userId == event.userId }
    }

    // MARK: - Chat catch-up (P0-35: implemented REST client)

    // P0-59/P0-60: fetchChatCatchup with opaque cursor + persistent dedupe
    private func fetchChatCatchup() async {
        guard let client = chatCatchupClient else { return }

        // P0-60: initialize knownMessageIds from current chatMessages
        for msg in chatMessages {
            if let mid = msg.messageId { knownMessageIds.insert(mid) }
        }

        do {
            var cursor = chatCatchupCursor
            var hasMore = true
            var pageCount = 0
            let maxPages = 20

            while hasMore && pageCount < maxPages {
                let response = try await client.fetchMessages(roomId: _roomId, after: cursor)
                pageCount += 1

                for msg in response.messages {
                    // P0-60: dedupe by messageId using persistent set
                    if knownMessageIds.contains(msg.messageId) { continue }
                    knownMessageIds.insert(msg.messageId)

                    let decoded = PlinkBubbleWire.decode(msg.text)

                    // Reconcile optimistic local send — keep same SwiftUI id (clientMessageId)
                    if let cmid = msg.clientMessageId,
                       let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
                        chatMessages[idx] = ChatMessageInfo(
                            messageId: msg.messageId,
                            clientMessageId: cmid,
                            senderId: msg.senderId.isEmpty ? chatMessages[idx].senderId : msg.senderId,
                            senderName: msg.senderName.isEmpty ? chatMessages[idx].senderName : msg.senderName,
                            text: decoded.text.isEmpty ? chatMessages[idx].text : decoded.text,
                            createdAtMs: msg.createdAtMs,
                            isPending: false,
                            isFailed: false,
                            bubbleStyle: decoded.styleID ?? chatMessages[idx].bubbleStyle,
                            mediaType: msg.mediaType,
                            hasMedia: msg.hasMedia
                        )
                        clientMessageIds.insert(cmid)
                        continue
                    }
                    if let cmid = msg.clientMessageId, clientMessageIds.contains(cmid) {
                        // Already reconciled via broadcast
                        continue
                    }

                    let info = ChatMessageInfo(
                        messageId: msg.messageId,
                        clientMessageId: msg.clientMessageId,
                        senderId: msg.senderId,
                        senderName: msg.senderName,
                        text: decoded.text,
                        createdAtMs: msg.createdAtMs,
                        isPending: false,
                        bubbleStyle: decoded.styleID,
                        mediaType: msg.mediaType,
                        hasMedia: msg.hasMedia
                    )
                    chatMessages.append(info)
                    if let cmid = msg.clientMessageId { clientMessageIds.insert(cmid) }
                }

                // P0-59: use server-provided opaque nextCursor, not messageId
                if let next = response.nextCursor {
                    cursor = next
                    chatCatchupCursor = next
                } else {
                    hasMore = false
                }
                hasMore = response.hasMore && cursor != nil

                if chatMessages.count > 200 {
                    chatMessages.removeFirst(chatMessages.count - 200)
                }
            }
            // P0-60: sort chronologically after merge
            chatMessages.sort { $0.createdAtMs < $1.createdAtMs }
        } catch {
            lastError = "Chat catch-up failed: \(error.localizedDescription)"
        }
    }

    // P0-58/P0-36: presence snapshot with event buffering
    private func fetchPresenceSnapshot() async {
        guard let client = chatCatchupClient else { return }
        snapshotInFlight = true  // P0-58: buffer events during fetch
        do {
            let snapshot = try await client.fetchParticipants(roomId: _roomId)
            // P0-58: apply snapshot, then merge buffered events
            var next = snapshot.map { p in
                ParticipantInfo(userId: p.userId, username: p.username, isLocal: p.userId == currentUserId)
            }
            // Never show "0 in room" — always keep local user + host if known
            if !next.contains(where: { $0.userId == currentUserId }) {
                next.insert(
                    ParticipantInfo(userId: currentUserId, username: currentUsername, isLocal: true),
                    at: 0
                )
            }
            if let host = roomHostId, !host.isEmpty,
               !next.contains(where: { $0.userId == host }) {
                next.append(
                    ParticipantInfo(userId: host, username: "Host", isLocal: host == currentUserId)
                )
            }
            participants = next
            // P0-58: replay buffered participant events
            for event in bufferedParticipantEvents {
                if event.isJoin {
                    let info = ParticipantInfo(userId: event.userId, username: event.username, isLocal: event.userId == currentUserId)
                    if !participants.contains(where: { $0.userId == info.userId }) {
                        participants.append(info)
                    }
                } else if event.userId != currentUserId {
                    // Never remove self from presence bar mid-session
                    participants.removeAll { $0.userId == event.userId }
                }
            }
            bufferedParticipantEvents.removeAll()
        } catch {
            // Non-fatal — ensure at least local user is visible
            if !participants.contains(where: { $0.userId == currentUserId }) {
                participants.insert(
                    ParticipantInfo(userId: currentUserId, username: currentUsername, isLocal: true),
                    at: 0
                )
            }
        }
        snapshotInFlight = false
    }

    // MARK: - UI properties (some stubs, some wired)

    var bufferedFraction: Double { 0 }
    var qualityLabel: String { coordinator.capabilities.supportsPiP ? "HD" : "SD" }
    var hostId: String? { roomHostId }
    var activeSpeakerName: String? { nil }
    var microphoneState: MicrophoneUIState { .off }
    var cameraState: CameraUIState { .off }
    var unreadCount: Int { 0 }

    // PATCH 14: danmaku placements come from DanmakuEngine. The model
    // polls the engine every 250ms (display-linked cadence) and caches
    // the snapshot in danmakuSnapshot. Views read from this cached array
    // — they never await on the actor during render.
    var danmakuPlacements: [DanmakuPlacement] { danmakuSnapshot }
    var danmakuLaneCount: Int { 5 }
    var danmakuOpacity: Double { 0.85 }

    // PATCH 14: ambient palette comes from AmbientVideoSampler. Drives
    // PurpleAmbientBackdrop's primaryColor + secondaryColor so the room
    // haze breathes with the movie.
    var ambientState: AmbientState {
        AmbientState(
            intensity: AmbientCapability.shouldEnableLivingBackground() ? 0.55 : 0.0,
            primaryColor: ambientPalette.primaryColor,
            secondaryColor: ambientPalette.secondaryColor
        )
    }

    // PATCH 14: Rutube fallback indicator. True when source is .rutube
    // and the embedded player's JS API is unavailable — UI shows a toast
    // prompting the user to open the video in Rutube's external app.
    var requiresRutubeFallback: Bool {
        guard case .rutube = coordinator.currentSource else { return false }
        guard let rutube = coordinator.currentController as? RutubePlaybackController else {
            return false
        }
        return rutube.requiresExternalFallback
    }

    // PATCH 14: open current Rutube video in SFSafariViewController.
    // Called by WatchRoomScreen when user taps "Open in Rutube" toast.
    #if canImport(UIKit)
    func openInRutubeExternal() {
        guard let rutube = coordinator.currentController as? RutubePlaybackController else {
            return
        }
        // Find the top-most view controller to present from.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else {
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        rutube.openInExternalPlayer(from: topVC)
    }
    #else
    func openInRutubeExternal() {}
    #endif

    private var didLeaveRoom = false

    // MARK: - M15: Приватность комнаты (бар модерации)

    /// Подтягивает актуальный режим приватности с бэкенда.
    /// P1 5.11: начальная тема комнаты при входе.
    ///
    /// GET /api/rooms/:id отдаёт колонку `appearance` КАК СТРОКУ (serializeRoom
    /// разбирает только mediaItem), и внутри неё, помимо провода, лежат
    /// аудит-поля updatedAt/updatedBy — поэтому разбор идёт тем же типом
    /// RoomAppearanceUpdated.Payload, где они опциональны.
    /// Тихо: нет темы / битая строка / нет сети → остаётся defaultStatic.
    func loadAppearance() async {
        struct RoomAppearanceEnvelope: Decodable { let appearance: String? }
        guard let envelope: RoomAppearanceEnvelope = try? await APIClient.shared.request(
            "rooms/\(_roomId)"
        ) else { return }
        guard let raw = envelope.appearance, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(
                  RealtimeServerMessage.RoomAppearanceUpdated.Payload.self,
                  from: data
              )
        else { return }
        // Ревью 26.07.2026: именно applyHydration, а не applyServerUpdate —
        // запрос стартует параллельно сокету, и ответ БД не должен перезаписать
        // уже применённое событие room.appearance.updated (или собственную
        // успешную запись хоста).
        appearanceStore.applyHydration(RoomAppearance(wire: payload))
    }

    func loadPrivacy() async {
        guard let room = try? await RoomService(api: APIClient.shared).fetchRoom(id: _roomId) else { return }
        roomPrivacy = room.privacy
    }

    /// Хост меняет режим приватности: PATCH на бэкенд + мгновенный
    /// broadcast всем участникам по чат-протоколу (как опросы M13).
    func setPrivacy(_ privacy: RoomPrivacy, password: String? = nil) {
        guard isHost else { return }
        roomPrivacy = privacy
        HapticManager.impact(.light)
        Task {
            try? await RoomService(api: APIClient.shared).updatePrivacy(
                roomID: _roomId,
                privacy: privacy,
                password: password
            )
        }
        let wire = RoomModerationWire.encode(.init(privacy: privacy.rawValue))
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId,
            clientMessageId: UUID().uuidString,
            text: wire
        )))
    }

    /// Мост между строкой управления (`V4RoomControlsRow`) и серверным
    /// `RoomPrivacy`. Уровней в UI три, на сервере четыре: `byLink` и
    /// `privateRoom` схлопываются в «Никто» — код и ссылка работают на любом
    /// уровне, поэтому отдельный «по приглашению» был бы дублем ссылки.
    /// Источник истины остаётся один — `roomPrivacy`.
    var privacyLevel: V4RoomPrivacyLevel {
        get {
            switch roomPrivacy {
            case .publicRoom:  return .everyone
            case .friendsRoom: return .friends
            case .byLink, .privateRoom: return .nobody
            }
        }
        set {
            // Приватность меняет только хост; setPrivacy сам это проверяет.
            switch newValue {
            case .everyone: setPrivacy(.publicRoom)
            case .friends:  setPrivacy(.friendsRoom)
            // .byLink, а не .privateRoom: пароля в этом UI нет, а
            // privateRoom без пароля закрыл бы вход даже по коду.
            case .nobody:   setPrivacy(.byLink)
            }
        }
    }

    func leaveRoom() {
        guard !didLeaveRoom else {
            wantsDismiss = true
            return
        }
        didLeaveRoom = true
        wantsDismiss = true
        disconnect()
        // REST leave — host leave or last person soft-ends room → history only
        if let roomId = roomId {
            Task {
                try? await RoomService(api: APIClient.shared).leaveRoom(roomID: roomId)
                // Local history mirror (server also writes WatchHistory)
                if let mediaId = mediaId {
                    let media = MediaItem(
                        id: mediaId,
                        title: "Комната",
                        artist: nil,
                        thumbnailURL: nil,
                        streamURL: mediaId,
                        duration: nil,
                        mediaType: .video,
                        source: .youtube,
                        videoId: mediaId.count == 11 ? mediaId : nil
                    )
                    await MainActor.run {
                        WatchHistoryManager.shared.recordWatch(mediaItem: media)
                    }
                }
            }
        }
    }
    // Аудит 26.07.2026 (P1 5.5): пустые openPlayerSettings()/startPiP() удалены.
    // Настройки плеера живут инлайн в PlinkPlayerControls.bottomBar; системный
    // PiP для WKWebView-эмбеда недоступен, а кнопок на эти методы не было.
    func enterFullscreen() {
        // PATCH: force landscape rotation — do NOT disconnect or stop playback
        #if canImport(UIKit)
        OrientationManager.shared.lockOrientation(.landscape)
        OrientationManager.shared.forceLandscape()
        #endif
    }

    func exitFullscreen() {
        // Return to portrait — do NOT disconnect
        #if canImport(UIKit)
        OrientationManager.shared.lockOrientation(.portrait)
        OrientationManager.shared.forcePortrait()
        #endif
    }
    func toggleMicrophone() async {
        // P0 5.1: голос выключен целиком (LiveKit не сконфигурирован).
        // Кнопка скрыта флагом в PresenceBar; guard — второй барьер.
        guard FeatureFlags.liveKitVoiceEnabled else {
            // LiveKit disabled — trigger paywall so user knows it's a Plink+ feature
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .showPlinkPlusPaywall,
                    object: nil,
                    userInfo: ["trigger": PlinkPlusPaywall.Trigger.voiceChat]
                )
            }
            return
        }
        // P0.2: Premium gate for speaking
        guard PremiumStatusManager.shared.isPremium else {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .showPlinkPlusPaywall,
                    object: nil,
                    userInfo: ["trigger": PlinkPlusPaywall.Trigger.voiceChat]
                )
            }
            return
        }
        // Delegate to RTC controller if available
        // (rtcController is internal; in full impl would call it)
        // For now, toggle state for UI
        // In real: await rtcController?.toggleMic()
    }

    func toggleCamera() async {
        // Camera in room — Plink+ only (same as voice)
        guard FeatureFlags.liveKitVoiceEnabled else {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .showPlinkPlusPaywall,
                    object: nil,
                    userInfo: ["trigger": PlinkPlusPaywall.Trigger.cameraFilter]
                )
            }
            return
        }
        guard PremiumStatusManager.shared.isPremium else {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .showPlinkPlusPaywall,
                    object: nil,
                    userInfo: ["trigger": PlinkPlusPaywall.Trigger.cameraFilter]
                )
            }
            return
        }
        // In real: await rtcController?.toggleCamera()
    }

    // PATCH 14: send a reaction emoji via RealtimeClient.
    // Validates against ReactionPalette — free emojis always sendable,
    // premium requires Plink+ entitlement.
    func sendReaction(emoji: String, hasPremium: Bool) {
        guard ReactionPalette.canSend(emoji, hasPremium: hasPremium) else {
            lastError = "Cannot send emoji: \(emoji) requires Plink+"
            return
        }
        let msg = RealtimeClientMessage.reactionSend(
            .init(roomId: _roomId, emoji: emoji)
        )
        realtimeClient.send(msg)
    }
}

// MARK: - UI models

public struct ParticipantInfo: Identifiable, Sendable, Equatable {
    public let userId: String
    public let username: String
    public let isLocal: Bool
    public var id: String { userId }
}

public struct ChatMessageInfo: Identifiable, Sendable, Equatable {
    public let messageId: String?
    public let clientMessageId: String?
    public let senderId: String
    public let senderName: String
    public let text: String
    public let createdAtMs: Int64
    public let isPending: Bool
    public var isFailed: Bool  // P1-54: failed messages can be retried
    public var isAdmin: Bool = false
    public var isPremium: Bool = false
    /// Sender bubble style (synced via wire format in text).
    public var bubbleStyle: String? = nil
    /// Optional media metadata. Photo bytes are fetched via authenticated REST, never through realtime.
    public var mediaType: String? = nil
    public var hasMedia: Bool = false
    public var isPhotoMessage: Bool { mediaType == "photo" && hasMedia }
    /// Stable SwiftUI identity — MUST NOT flip from clientMessageId → server messageId
    /// or ForEach deletes the bubble (looks like "message vanished").
    public var id: String {
        if let cmid = clientMessageId, !cmid.isEmpty { return cmid }
        if let mid = messageId, !mid.isEmpty { return mid }
        return "\(senderId)-\(createdAtMs)-\(text.hashValue)"
    }

    // P1-54: convenience init without isFailed
    public init(messageId: String?, clientMessageId: String?, senderId: String,
                senderName: String, text: String, createdAtMs: Int64,
                isPending: Bool, isFailed: Bool = false, bubbleStyle: String? = nil,
                mediaType: String? = nil, hasMedia: Bool = false) {
        self.messageId = messageId
        self.clientMessageId = clientMessageId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.createdAtMs = createdAtMs
        self.isPending = isPending
        self.isFailed = isFailed
        self.bubbleStyle = bubbleStyle
        self.mediaType = mediaType
        self.hasMedia = hasMedia
    }
}

// P1-51: renamed from ReactionEvent to avoid @Observable macro ambiguity
public struct WatchReactionEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let userId: String
    public let username: String
    public let emoji: String
    public let timestampMs: Int64
    // Ревью P2: локальная метка получения. Экспирация и анимация считаются по
    // ней, а серверная timestampMs остаётся только для сортировки/дедупа —
    // часы устройства могут расходиться с серверными на секунды, и срез по
    // серверной метке тогда либо не наступал никогда, либо срабатывал сразу.
    public let receivedAt: Date
    // Blueprint: reaction animation properties
    public let startX: CGFloat
    public let rotation: Double
    public let scale: CGFloat
    public let opacity: Double

    public init(id: UUID = UUID(), userId: String, username: String, emoji: String, timestampMs: Int64) {
        self.id = id
        self.userId = userId
        self.username = username
        self.emoji = emoji
        self.timestampMs = timestampMs
        self.receivedAt = Date()
        self.startX = CGFloat.random(in: 0.1...0.9)
        self.rotation = Double.random(in: -30...30)
        self.scale = 1.5
        self.opacity = 1.0
    }

    public func currentY(in height: CGFloat) -> CGFloat {
        let elapsed = max(0, Date().timeIntervalSince(receivedAt) * 1000)
        let progress = min(1, elapsed / 2500)
        return height * (1 - CGFloat(progress) * 0.8)
    }
}

// MARK: - P0-35: Chat catch-up REST client protocol

public protocol ChatCatchupClient: Sendable {
    func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse
    func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot]
}

public struct ChatCatchupResponse: Sendable, Equatable {
    public let messages: [ChatCatchupMessage]
    public let hasMore: Bool
    public let nextCursor: String?  // P0-59: opaque server cursor
}

private struct ChatPhotoSendResponse: Decodable, Sendable {
    let messageId: String
    let clientMessageId: String?
    let senderId: String
    let senderName: String
    let text: String
    let createdAtMs: Int64
    let mediaType: String?
    let hasMedia: Bool?
}

public struct ChatCatchupMessage: Sendable, Equatable {
    public let messageId: String
    public let clientMessageId: String?
    public let senderId: String
    public let senderName: String
    public let text: String
    public let createdAtMs: Int64
    public let mediaType: String?
    public let hasMedia: Bool

    public init(messageId: String, clientMessageId: String?, senderId: String, senderName: String, text: String, createdAtMs: Int64, mediaType: String? = nil, hasMedia: Bool = false) {
        self.messageId = messageId
        self.clientMessageId = clientMessageId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.createdAtMs = createdAtMs
        self.mediaType = mediaType
        self.hasMedia = hasMedia
    }
}

public struct ParticipantSnapshot: Sendable, Equatable {
    public let userId: String
    public let username: String
}


private actor YouTubeNativeStreamCache {
    static let shared = YouTubeNativeStreamCache()

    private struct Entry {
        let source: PlaybackSource
        let createdAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 20 * 60

    func source(for videoId: String) -> PlaybackSource? {
        guard let entry = entries[videoId] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > ttl {
            entries.removeValue(forKey: videoId)
            return nil
        }
        return entry.source
    }

    func store(_ source: PlaybackSource, for videoId: String) {
        entries[videoId] = Entry(source: source, createdAt: Date())
    }

    /// P0 FIX: drop a poisoned entry (e.g. a stream URL that started 403-ing).
    func invalidate(videoId: String) {
        entries.removeValue(forKey: videoId)
    }
}
