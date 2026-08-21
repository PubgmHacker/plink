// Plink/Features/WatchRoom/WatchRoomModel.swift
// Single owner of room session lifecycle
//
// Contracts this type upholds:
//   syncController talks to a stable PlaybackProxy, never to a player instance
//     directly — the proxy survives player swaps, the player does not.
//   sessionDidConnect(role:) is the only writer of isHost; role is server-assigned.
//   connectionState reflects every state published on the stateChanges stream.
//   Host controls apply optimistically to the local player, then send a v2 command.
//   The chat button only flips UI state — WatchRoomScreen presents the sheet.
//   fetchChatCatchup pages history over REST with a cursor.
//   Presence arrives as a snapshot; reactions arrive as a stream.
//   Dependencies are injected: wiring lives in WatchRoomCompositionRoot.
//   Current user identity comes in through init.
//   Host commands carry a typed mediaId.
//   lastError, hardCorrectionCount and driftMs are bound by the UI and must
//     stay observable.

import Foundation
import Observation
#if canImport(UIKit)
import UIKit  // UIApplication + UIWindowScene for Rutube fallback presentation
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

    /// Active room poll (rides on the chat protocol, see RoomPolls.swift).
    public private(set) var activePoll: RoomPollState?

    /// Текущий режим приватности комнаты (бар модерации).
    // RoomPrivacy — internal-тип, поэтому свойство не может быть public.
    private(set) var roomPrivacy: RoomPrivacy = .publicRoom
    /// Видимость бара модерации (управляется экраном и топ-хромом).
    public var moderationBarVisible = false

    /// ИИ-модератор — до какого момента текущий юзер замучен (nil — не замучен).
    public private(set) var mutedUntil: Date? = nil

    /// Остаток мута в секундах (0 — можно писать).
    public var mutedRemainingSec: Int {
        guard let until = mutedUntil else { return 0 }
        let remaining = Int(until.timeIntervalSinceNow.rounded(.up))
        return max(0, remaining)
    }

    /// Очередь видео комнаты (ИИ-ассистент ставит ролики по-настоящему).
    // RoomQueueWire — internal-тип (RoomQueue.swift), public здесь невозможен.
    private(set) var roomQueue: [RoomQueueWire.Item] = []

    // Управление очередью — REST; broadcast обновит roomQueue у всех участников.
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

    /// Хост переставил элементы очереди. Сервер применяет присланный порядок
    /// как перестановку и рассылает канонический результат бродкастом —
    /// локально порядок не трогаем, иначе список дёрнется дважды.
    func reorderQueue(_ ordered: [RoomQueueWire.Item]) {
        guard isHost else { return }
        let rid = _roomId
        let ids = ordered.map(\.id)
        Task {
            struct Body: Encodable { let order: [String] }
            struct Resp: Decodable { let queue: [RoomQueueWire.Item] }
            do {
                let _: Resp = try await APIClient.shared.request(
                    "rooms/\(rid)/queue",
                    method: .patch,
                    body: Body(order: ids)
                )
            } catch {
                // тихо — очередь синхронизируется бродкастом
            }
        }
    }

    // Синхронный отсчёт 3-2-1 перед стартом
    public private(set) var countdownRemaining: Int? = nil
    private var countdownTask: Task<Void, Never>?
    public private(set) var lastError: String?
    /// Отдельный канал ТОЛЬКО для ошибок загрузки медиа.
    /// Раньше в оверлей плеера падал любой lastError (kick, chat catch-up,
    /// «Voice chat requires Plink+») и рисовал чёрный экран поверх идущего видео.
    public private(set) var mediaError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var hardCorrectionCount: Int = 0
    public private(set) var lastDriftMs: Double = 0
    // Reactions — renamed to WatchReactionEvent to avoid @Observable
    // macro type ambiguity with existing ReactionEvent from SyncEvents.swift
    // Reactions auto-expire after 3 seconds
    public private(set) var reactions: [WatchReactionEvent] = []
    private var reactionExpiryTask: Task<Void, Never>?

    // MARK: - Просьба о паузе
    //
    // До этого гость мог только смотреть на подпись «Управляет хост». Отойти
    // на минуту было нельзя: единственный способ — написать в чат и надеяться,
    // что хост его читает, а не смотрит в кадр.
    //
    // Сервер плеер НЕ останавливает — он доставляет просьбу, решение за хостом
    // (backend/src/realtime/messageRouter.ts → case 'pause.request').
    // Иначе любой гость получил бы кнопку «остановить чужой сеанс».

    /// Просьба о паузе, ожидающая решения хоста. Ненулевая только у хоста.
    public private(set) var pendingPauseRequest: PauseRequestPrompt?
    private var pauseRequestExpiryTask: Task<Void, Never>?
    /// Когда текущий пользователь последний раз просил паузу. Локальный
    /// кулдаун держим сами: серверный лимит отвечает ошибкой RATE_LIMITED,
    /// а показывать человеку код ошибки за второй тап — плохой ответ на
    /// нормальное желание.
    private var lastPauseRequestAt: Date?

    /// Серверный лимит — 1 просьба в 10 с; локально просим на секунду реже,
    /// чтобы гонка часов не превращала разрешённый тап в ошибку.
    private static let pauseRequestCooldownSec: TimeInterval = 11

    /// Сколько просьба живёт у хоста. Просроченная просьба вреднее отсутствующей:
    /// нажатая через минуту, она остановит совсем другой момент фильма.
    private static let pauseRequestTTLSec: TimeInterval = 30

    /// Просьба гостя, показываемая хосту.
    public struct PauseRequestPrompt: Identifiable, Equatable, Sendable {
        public let id: String
        public let userId: String
        public let username: String
        /// Короткая пометка гостя («отойду на минуту»), может отсутствовать.
        public let reason: String?
        public let receivedAt: Date
    }

    /// Чем закончилась попытка попросить паузу. Вью решает, что показать —
    /// модель не трогает тосты: они принадлежат вью (WatchRoomUIState).
    public enum PauseRequestOutcome: Equatable, Sendable {
        /// Просьба ушла на сервер.
        case sent
        /// Хост сам ставит паузу — просить некого.
        case redundantForHost
        /// Нет соединения. В офлайн-очередь просьба намеренно не кладётся.
        case offline
        /// Локальный кулдаун ещё не истёк.
        case throttled
    }

    // MARK: - «что я пропустил»
    //
    // Карточка появляется САМА в момент опоздания — поздний вход в идущую
    // сессию или возврат после долгого разрыва. Запрос к ИИ при этом не
    // уходит, пока человек не попросил: авто-LLM за его счёт (дневной лимит
    // бесплатного тарифа) был бы неприятным сюрпризом.

    /// Всплывшая карточка «что я пропустил». nil — нечего догонять.
    public private(set) var catchUpPrompt: CatchUpPrompt?
    /// Идёт запрос рекапа — карточка показывает прогресс и глушит повторный тап.
    public private(set) var catchUpLoading = false
    /// Момент потери соединения — чтобы отличить моргнувший Wi-Fi от
    /// «отходил на десять минут».
    private var lastConnectionLossAt: Date?
    /// Карточка показывается не чаще раза за жизнь модели: перезаход в ту же
    /// комнату — новая модель, а вот каждый реконнект дёргать её не должен.
    private var catchUpShownThisSession = false

    /// Поздний вход: контент идёт уже дольше этого порога.
    private static let catchUpLateJoinThresholdMs: Int64 = 3 * 60_000
    /// Реконнект: разрыв дольше этого — уже «отходил», а не «моргнула сеть».
    private static let catchUpReconnectGapSec: TimeInterval = 90

    public struct CatchUpPrompt: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Вошёл в сессию, которая идёт давно.
            case lateJoin
            /// Вернулся после долгого разрыва.
            case reconnectGap
        }
        public let kind: Kind
        /// Сколько примерно пропущено, в минутах (для копирайта карточки).
        public let missedMinutes: Int
        /// Начало пропущенного окна (мс эпохи) — уходит в /api/ai/room-recap.
        public let sinceMs: Int64
    }

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator
    private let playbackProxy: PlaybackProxy  // Stable proxy for syncController

    // DanmakuEngine + AmbientVideoSampler owned by the model.
    // One per room session — never global singletons.
    // The engine is fed by chat broadcast handler (chat messages become
    // danmaku placements). The sampler is fed by coordinator.nativePlayer
    // (palette drives PurpleAmbientBackdrop).
    private let danmakuEngine: DanmakuEngine
    private let ambientSampler: AmbientVideoSampler
    private var danmakuSnapshot: [DanmakuPlacement] = []
    private var ambientPalette: AmbientPalette = .defaultPalette
    /// Live blurred backdrop frame (Rave-style) — read by WatchRoomSocialRegion.
    var ambientFrame: UIImage?
    private var danmakuPollTask: Task<Void, Never>?
    private var ambientSampleTask: Task<Void, Never>?

    // MARK: - Config
    // roomId stored as _roomId (private) + protocol conformance via
    // computed var roomId: String? { _roomId }. Only ONE declaration.
    private let _roomId: String
    /// May be recovered after connect if create/join stripped mediaItem.
    public private(set) var mediaSource: PlaybackSource?
    public private(set) var mediaId: String?  // Typed media ID for host commands
    public private(set) var roomCode: String?

    /// Хост шарит экран (Netflix/Disney/кино — режим «ваш экран»).
    public private(set) var isScreenSharing = false
    /// Короткая подсказка в UI комнаты про режим экрана / DRM.
    public private(set) var screenShareStatusLine: String?
    private var screenCapture: ScreenCaptureService?
    public let currentUserId: String  // Identity via init, not UserDefaults
    public let currentUsername: String  //
    private var chatCatchupCursor: String?  // Opaque server cursor
    // Persistent messageIds set — initialized from current chatMessages
    private var knownMessageIds = Set<String>()
    private var clientMessageIds = Set<String>()
    private var stateChangesTask: Task<Void, Never>?
    // Serial state pump — coalesce to latest state
    private var statePumpTask: Task<Void, Never>?
    private var pendingStates: [RealtimeRoomState] = []
    // Snapshot revision — buffer participant events during snapshot fetch
    private var snapshotInFlight = false
    private var bufferedParticipantEvents: [(isJoin: Bool, userId: String, username: String)] = []
    // Single authoritative rollback state
    private var lastAuthoritativeState: RealtimeRoomState?

    /// P1 5.11: живая тема комнаты (Plink+). Стор — на комнату; realtime-событие
    /// room.appearance.updated зовёт applyServerUpdate, хост меняет тему через
    /// updateTheme. Тип internal, поэтому свойство не может быть public.
    private(set) var appearanceStore: RoomAppearanceStore

    // REST client for chat catch-up
    private let chatCatchupClient: ChatCatchupClient?
    private let roomRecapClient: RoomRecapClient?
    /// Host user id from Room model (presence highlight).
    private let roomHostId: String?

    // Init — class is @MainActor, init inherits isolation.
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
        roomRecapClient: RoomRecapClient? = nil,
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
        self.roomRecapClient = roomRecapClient
        self.roomHostId = roomHostId
        let resolvedClock = clock ?? ClockSynchronizer()
        self.clock = resolvedClock
        self.coordinator = coordinator ?? PlaybackCoordinator()

        // Create stable proxy — syncController talks to proxy, not dummy
        let proxy = PlaybackProxy()
        self.playbackProxy = proxy
        self.syncController = OrderedSyncController(clock: resolvedClock, player: proxy)

        // Instantiate engine + sampler BEFORE any use of self
        // (delegate = self below requires all stored properties initialized).
        // Capture local let before assigning to self, so the
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

        // DanmakuEngine has no startSampling() — caller polls
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

    // Links carry the room CODE, not the UUID: the server joins by code only
    // (POST /rooms/join { code }), and the AASA-backed landing page lives at
    // /r/<code>.
    //
    // The code comes from the server, so it is percent-encoded before going
    // into a URL — a space or a non-ASCII character otherwise yields nil and
    // crashes the invite sheet on the force unwrap downstream.
    //
    // Encoded rather than stripped: dropping characters would leave the link
    // and the QR pointing somewhere other than the code shown in the sheet and
    // in the share text, and nothing would report the mismatch.
    private var linkRoomCode: String {
        displayRoomCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? displayRoomCode
    }

    public var roomDeepLink: URL {
        URL(string: "plink://r/\(linkRoomCode)") ?? URL(string: "plink://r")!
    }

    public var roomFallbackURL: URL {
        PlinkURLs.roomLink(code: linkRoomCode) ?? PlinkURLs.shareHome
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

        // Subscribe to stateChanges stream
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

                // Netflix/Disney/кино: WebView для входа хоста + ReplayKit.
                // Кадры уходят в onFrame → будущий LiveKit; пока RTC stub —
                // захват всё равно стартует честно (не молчим про «ваш экран»).
                await beginScreenShareIfNeeded(for: source)
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
        // Просьба о паузе живёт ровно столько, сколько длится сеанс.
        // Оставленная задача разбудила бы модель уже вне комнаты.
        clearPauseRequest()
        lastPauseRequestAt = nil
        Task { await stopScreenShare() }
        realtimeClient.disconnect()
        coordinator.teardown()
        syncController.resetCompletely()
        clock.reset()
        participants = []
        chatMessages = []
        reactions = []
        clientMessageIds.removeAll()
        connectionState = .idle

        // Stop engine + sampler
        // DanmakuEngine has no stopSampling() — cancelling the
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

    // MARK: - Danmaku polling

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

    // MARK: - Ambient palette polling

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

    // Subscribe to RealtimeClient.stateChanges
    private func startStateChangesSubscription() {
        stateChangesTask?.cancel()
        stateChangesTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.realtimeClient.stateChanges {
                guard !Task.isCancelled else { return }
                // Фиксируем момент потери связи — при возврате решим,
                // был ли это моргнувший Wi-Fi или настоящий разрыв.
                if case .connected = self.connectionState {
                    switch state {
                    case .reconnecting, .failed, .idle:
                        self.lastConnectionLossAt = Date()
                    default:
                        break
                    }
                }
                self.connectionState = state
            }
        }
    }

    // Pending actions for reconciliation/rollback
    private struct PendingAction {
        let actionId: String
        let preActionPosition: Double
        let preActionPlaying: Bool
        let timestamp: Date
        // epoch/seq на момент отправки — авторитетное
        // состояние с бОльшим (epoch, seq) означает подтверждение команды.
        let epochAtSend: Int64
        let seqAtSend: Int64
    }
    private var pendingActions: [String: PendingAction] = [:]
    private static let actionTimeoutMs: Int64 = 10_000

    // MARK: - Host commands (optimistic local apply + reconciliation)

    public func sendPlayCommand() async {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // Optimistic local apply
        await coordinator.currentController?.play()
        // play() is a suspension point. If the room was left while it ran,
        // disconnect has already cleared pendingActions, and re-adding an entry
        // here means its 10s timeout reports a bogus error from outside a room.
        guard connectionState != .idle else { return }
        let actionId = UUID().uuidString
        // Track pending action for rollback
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, //
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
        // Optimistic local apply
        coordinator.currentController?.pause()
        let actionId = UUID().uuidString
        // Track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, //
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

    // MARK: - Просьба о паузе

    /// Гость просит хоста поставить паузу.
    ///
    /// Возвращает результат, а не молчит: тихий провал здесь — худший из
    /// возможных, человек ушёл бы от экрана, уверенный, что его просьбу видят.
    @discardableResult
    public func requestPause(reason: String? = nil) -> PauseRequestOutcome {
        // Хосту просить некого — у него есть настоящая кнопка паузы.
        if isHost { return .redundantForHost }

        // Просьба НЕ идёт в офлайн-очередь (RealtimeClient.isUserMessage):
        // доставленная через полминуты после переподключения, она попросит
        // остановить уже другой момент. Поэтому здесь честный отказ.
        guard connectionState == .connected else { return .offline }

        if let last = lastPauseRequestAt,
           Date().timeIntervalSince(last) < Self.pauseRequestCooldownSec {
            return .throttled
        }

        lastPauseRequestAt = Date()
        realtimeClient.send(.pauseRequest(.init(roomId: _roomId, reason: reason)))
        AnalyticsService.shared.track("room_pause_requested", parameters: [
            "has_reason": reason?.isEmpty == false ? "true" : "false",
        ])
        return .sent
    }

    /// Хост ответил на просьбу. `pause == true` — ставим паузу по-настоящему,
    /// обычной командой sync.command, чтобы кадр совпал у всей комнаты.
    ///
    /// Вердикт уходит комнате отдельным pause.resolve. Раньше отклонённая
    /// просьба исчезала молча — гость не знал, увидели её или нет, и после
    /// кулдауна просил снова. Принятие тоже объявляется: пауза, наступившая
    /// без объяснения, читается как сбой синхронизации, а не как ответ.
    public func resolvePauseRequest(pause: Bool) {
        guard let prompt = pendingPauseRequest else { return }
        clearPauseRequest()
        guard isHost else { return }

        if connectionState == .connected {
            realtimeClient.send(.pauseResolve(.init(
                roomId: _roomId,
                accepted: pause,
                requestUserId: prompt.userId
            )))
            AnalyticsService.shared.track("room_pause_resolved", parameters: [
                "accepted": pause ? "true" : "false",
            ])
        }

        guard pause else { return }
        if coordinator.isPlaying {
            sendPauseCommand()
        }
    }

    /// Снять просьбу с экрана и погасить таймер её жизни.
    public func clearPauseRequest() {
        pauseRequestExpiryTask?.cancel()
        pauseRequestExpiryTask = nil
        pendingPauseRequest = nil
    }

    private func handlePauseRequested(_ event: RealtimeServerMessage.PauseRequested) {
        let name = event.username.isEmpty ? "Гость" : event.username

        // Системная строка в чате — тем же способом, что муты ИИ-модератора.
        // Она нужна ВСЕМ: гости видят, что просьба уже висит, и не дублируют
        // её; у хоста остаётся след после того, как баннер погас.
        let line = String(
            format: LocalizationManager.shared.string(.pauseAskPrompt),
            name
        )
        let suffix = event.reason.map { " — \($0)" } ?? ""
        let sys = ChatMessageInfo(
            messageId: "pause-\(event.userId)-\(event.serverTimeMs)",
            clientMessageId: nil,
            senderId: "plink-system",
            senderName: "Plink",
            text: "\u{23F8}\u{FE0E} \(line)\(suffix)",
            createdAtMs: event.serverTimeMs,
            isPending: false,
            bubbleStyle: "bubble-quiet",
            mediaType: nil,
            hasMedia: false
        )
        chatMessages.append(sys)
        if chatMessages.count > 200 { chatMessages.removeFirst(chatMessages.count - 200) }

        // Действие предлагаем только хосту: у остальных кнопка «Пауза» ничего
        // бы не сделала, а неработающая кнопка хуже её отсутствия.
        guard isHost, event.userId != currentUserId else { return }

        pendingPauseRequest = PauseRequestPrompt(
            id: "\(event.userId)-\(event.serverTimeMs)",
            userId: event.userId,
            username: name,
            reason: event.reason,
            receivedAt: Date()
        )
        HapticManager.impact(.medium)

        pauseRequestExpiryTask?.cancel()
        let expectedId = pendingPauseRequest?.id
        pauseRequestExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pauseRequestTTLSec))
            guard !Task.isCancelled, let self else { return }
            // Гасим только СВОЮ просьбу: пока таймер спал, могла прийти новая,
            // и её нельзя убирать чужим таймаутом.
            guard self.pendingPauseRequest?.id == expectedId else { return }
            self.pendingPauseRequest = nil
            self.pauseRequestExpiryTask = nil
        }
    }

    /// Комнате объявлен вердикт хоста по просьбе о паузе.
    ///
    /// Системная строка — всем, кроме самого хоста (он сам только что нажал
    /// кнопку и видит результат). Висящая подсказка гасится у ЛЮБОГО клиента:
    /// если хост ответил с другого устройства или роль мигрировала в момент
    /// просьбы, баннер с уже решённым вопросом — ложь на экране.
    private func handlePauseResolved(_ event: RealtimeServerMessage.PauseResolved) {
        clearPauseRequest()
        guard event.hostId != currentUserId else { return }

        let host = event.hostName.isEmpty
            ? LocalizationManager.shared.string(.pauseResolveHostFallback)
            : event.hostName
        let key: L10n.Key = event.accepted ? .pauseResolveAccepted : .pauseResolveDeclined
        let line = String(format: LocalizationManager.shared.string(key), host)
        let sys = ChatMessageInfo(
            messageId: "pause-resolved-\(event.hostId)-\(event.serverTimeMs)",
            clientMessageId: nil,
            senderId: "plink-system",
            senderName: "Plink",
            text: "\u{23F8}\u{FE0E} \(line)",
            createdAtMs: event.serverTimeMs,
            isPending: false,
            bubbleStyle: "bubble-quiet",
            mediaType: nil,
            hasMedia: false
        )
        chatMessages.append(sys)
        if chatMessages.count > 200 { chatMessages.removeFirst(chatMessages.count - 200) }
    }

    public func sendSeekCommand(to seconds: TimeInterval) async {
        guard isHost else { return }
        let positionMs = Int64(seconds * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // Optimistic local seek
        _ = await coordinator.currentController?.seek(to: seconds, precise: true)
        // Same suspension-point hazard as sendPlayCommand.
        guard connectionState != .idle else { return }
        let actionId = UUID().uuidString
        // Track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date(),
            epochAtSend: lastEpoch, //
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

    // Single authoritative rollback — NOT concurrent Tasks per action.
    // Rollback to last authoritative state, request fresh snapshot.
    private func handleActionRejection(_ errorCode: String) {
        pendingActions.removeAll()
        // Restore to last authoritative state in a single operation
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
        // Request fresh snapshot immediately
        realtimeClient.send(.stateRequest(.init(roomId: _roomId, afterSeq: lastSeq)))
        lastError = "Command rejected: \(errorCode) — rolled back to authoritative state"
    }

    // Timeout pending actions
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

    // Clear pending action when authoritative state arrives
    // Раньше параметр state игнорировался — команды никогда
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

    // MARK: - Chat (optimistic send, reconciliation, failure/retry)

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
        // Schedule 5s timeout — mark as failed if no server echo
        scheduleChatSendTimeout(clientMessageId: clientMessageId)
    }

    // MARK: - Room polls + offline queue badge

    /// Number of chat/reaction messages queued while offline (see RealtimeClient).
    public var queuedMessageCount: Int { realtimeClient.queuedUserMessageCount }

    // MARK: - Синхронный отсчёт 3-2-1

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

    // Retry a failed chat message
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

    // Mark message as failed after 5s if no server confirmation
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

    // roomId protocol conformance — protocol requires String?
    // but our roomId is non-optional String. Return wrapped optional.
    public var roomId: String? { _roomId }

    public var lastEpoch: Int64 { syncController.lastEpoch }
    public var lastSeq: Int64 { syncController.lastSeq }

    public func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double) {
        clock.ingest(clientSentMs: clientSentMs, serverMs: serverMs, clientReceivedMs: clientReceivedMs)
        clockSynced = clock.isSynchronized
    }

    // Serial state pump — enqueue state, process in order
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
                // Store last authoritative state for rollback
                self.lastAuthoritativeState = state
                // Update UI metrics AFTER each apply completes
                self.hardCorrectionCount = self.syncController.hardCorrectionCount
                self.lastDriftMs = self.syncController.lastDriftMs
                // Clear pending actions that match this state
                self.clearPendingActionsIfConfirmed(state: state)
                // Первый авторитетный state — момент, когда видно,
                // насколько сессия уже ушла вперёд без нас.
                self.considerCatchUp(after: state)
            }
            self.statePumpTask = nil
        }
    }

    // MARK: - «что я пропустил»

    /// Решает, показывать ли карточку. Один раз за жизнь модели.
    private func considerCatchUp(after state: RealtimeRoomState) {
        guard !catchUpShownThisSession, catchUpPrompt == nil else { return }
        guard roomRecapClient != nil else { return }

        // Долгий реконнект важнее позднего входа: человек уже был в комнате.
        if let lostAt = lastConnectionLossAt {
            let gap = Date().timeIntervalSince(lostAt)
            if gap >= Self.catchUpReconnectGapSec {
                let minutes = max(1, Int((gap / 60).rounded()))
                let sinceMs = Int64(lostAt.timeIntervalSince1970 * 1000)
                presentCatchUp(.init(kind: .reconnectGap, missedMinutes: minutes, sinceMs: sinceMs))
                lastConnectionLossAt = nil
                return
            }
        }

        // Поздний вход: контент уже идёт дольше порога.
        if state.positionMs >= Self.catchUpLateJoinThresholdMs {
            let minutes = max(1, Int(state.positionMs / 60_000))
            // Окно рекапа — последние N минут позиции, но не больше 4 часов
            // (сервер всё равно режет).
            let lookbackMs = min(state.positionMs, 4 * 3600_000)
            let sinceMs = Int64(Date().timeIntervalSince1970 * 1000) - lookbackMs
            presentCatchUp(.init(kind: .lateJoin, missedMinutes: minutes, sinceMs: sinceMs))
        }
    }

    private func presentCatchUp(_ prompt: CatchUpPrompt) {
        catchUpShownThisSession = true
        catchUpPrompt = prompt
        HapticManager.impact(.light)
    }

    /// Человек отказался от рекапа — карточку убираем, запрос не шлём.
    public func dismissCatchUp() {
        catchUpPrompt = nil
        catchUpLoading = false
    }

    /// Запрашивает рекап у /api/ai/room-recap и кладёт ответ системной строкой
    /// в чат. Приватный ответ: в комнату ничего не публикуется.
    public func requestCatchUp() {
        guard let prompt = catchUpPrompt, let client = roomRecapClient else { return }
        guard !catchUpLoading else { return }
        catchUpLoading = true

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.catchUpLoading = false
                self.catchUpPrompt = nil
            }
            do {
                let response = try await client.fetchRecap(roomId: self._roomId, sinceMs: prompt.sinceMs)
                let text: String
                if let recap = response.recap, !recap.isEmpty {
                    text = recap
                } else {
                    text = LocalizationManager.shared.string(.catchUpEmpty)
                }
                let sys = ChatMessageInfo(
                    messageId: "catchup-\(Int64(Date().timeIntervalSince1970 * 1000))",
                    clientMessageId: nil,
                    senderId: "plink-ai",
                    senderName: "Plink AI",
                    text: "\u{1F4AC} \(text)",
                    createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                    isPending: false,
                    bubbleStyle: "bubble-quiet",
                    mediaType: nil,
                    hasMedia: false
                )
                self.chatMessages.append(sys)
                if self.chatMessages.count > 200 {
                    self.chatMessages.removeFirst(self.chatMessages.count - 200)
                }
                AnalyticsService.shared.track("room_catchup_requested", parameters: [
                    "kind": prompt.kind == .lateJoin ? "late_join" : "reconnect",
                    "message_count": "\(response.messageCount)",
                ])
            } catch {
                // Честный отказ, а не молчание: человек нажал кнопку.
                let sys = ChatMessageInfo(
                    messageId: "catchup-fail-\(Int64(Date().timeIntervalSince1970 * 1000))",
                    clientMessageId: nil,
                    senderId: "plink-system",
                    senderName: "Plink",
                    text: LocalizationManager.shared.string(.catchUpFailed),
                    createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                    isPending: false,
                    bubbleStyle: "bubble-quiet",
                    mediaType: nil,
                    hasMedia: false
                )
                self.chatMessages.append(sys)
            }
        }
    }

    /// Социальный статус комнаты для PresenceBar — только то, что реально
    /// известно клиенту. Per-participant дрифт на проводе отсутствует.
    public var presenceStatusLine: String {
        let l = LocalizationManager.shared
        if let ask = pendingPauseRequest {
            return String(format: l.string(.presencePauseAsk), ask.username)
        }
        if isScreenSharing {
            return isHost ? "Ваш экран в эфире" : "Хост шарит экран"
        }
        if screenShareStatusLine != nil, case .embed = mediaSource {
            return isHost ? "Режим «ваш экран»" : "Кино через экран хоста"
        }
        if let state = lastAuthoritativeState, !state.playing {
            return l.string(.presencePaused)
        }
        if lastDriftMs >= 250 {
            return l.string(.presenceResyncing)
        }
        return l.string(.presenceWatchingTogether)
    }

    /// Netflix/Disney/кино → embed: хост включает ReplayKit in-app capture.
    private func beginScreenShareIfNeeded(for source: PlaybackSource) async {
        guard case .embed = source else {
            screenShareStatusLine = nil
            return
        }
        screenShareStatusLine = isHost
            ? "Кинотеатр / OTT: войдите в свой аккаунт. Экран шарится через ReplayKit — Plink не обходит DRM."
            : "Хост смотрит через свой экран. Когда LiveKit включён, вы увидите его картинку здесь."

        guard isHost else { return }

        let capture = screenCapture ?? ScreenCaptureService()
        screenCapture = capture
        capture.onError = { [weak self] message in
            Task { @MainActor in
                self?.screenShareStatusLine = "Шаринг экрана: \(message)"
                self?.isScreenSharing = false
            }
        }
        do {
            try await capture.startCapture()
            isScreenSharing = true
            AnalyticsService.shared.track("screen_share_started", parameters: ["room_id": _roomId])
        } catch {
            isScreenSharing = false
            screenShareStatusLine =
                "Не удалось начать шаринг экрана: \(error.localizedDescription). WebView остаётся для вашего входа."
            Logger.app.warn("[ScreenShare] start failed: \(error.localizedDescription)")
        }
    }

    private func stopScreenShare() async {
        guard let capture = screenCapture else {
            isScreenSharing = false
            screenShareStatusLine = nil
            return
        }
        await capture.stopCapture()
        if isScreenSharing {
            AnalyticsService.shared.track("screen_share_stopped", parameters: ["room_id": _roomId])
        }
        isScreenSharing = false
        screenShareStatusLine = nil
        screenCapture = nil
    }

    /// P0 12.08.2026: передача роли хоста на живой комнате.
    ///
    /// Раньше уход хоста закрывал комнату всем, поэтому клиенту нечего было
    /// обрабатывать. Теперь сервер (gateway.publishHostMigration) присылает
    /// role.changed с новой эпохой, и роль надо применить БЕЗ перезахода.
    ///
    /// Событие одно на всю комнату: хостом стал тот, чей id совпал с newHostId.
    /// Остальным оно тоже полезно — узнать, что комната жива и у неё новый
    /// ведущий, вместо «плеер больше никого не слушает».
    public func applyRoleChange(_ event: RealtimeServerMessage.RoleChanged) {
        let iAmHost = event.newHostId == currentUserId
        role = iAmHost ? .host : .viewer
        isHost = iAmHost
        appearanceStore.setHost(iAmHost)

        // Эпоха сменилась: команды, отправленные до передачи роли, сервер уже
        // не примет. Держать их в pendingActions значит ждать подтверждения,
        // которое не придёт, и потом откатывать плеер на ровном месте.
        pendingActions.removeAll()

        // Просьба о паузе адресована прежнему хосту — она больше не актуальна.
        pendingPauseRequest = nil

        // Забираем авторитетное состояние заново: позиция зафиксирована
        // bumpEpoch() на сервере, и локальная могла разойтись.
        realtimeClient.send(.stateRequest(.init(roomId: _roomId, afterSeq: lastSeq)))
    }

    // sessionDidConnect now carries role
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
        // Request chat catch-up after reconnect
        Task { await fetchChatCatchup() }
        // Request presence snapshot
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
        // scheduleActionTimeout здесь убран — PendingAction
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
        // Гость попросил паузу. Плеер здесь не трогаем — сервер тоже:
        // решение остаётся за хостом (см. handlePauseRequested).
        case .pauseRequested(let request):
            handlePauseRequested(request)
        // Хост ответил на просьбу — закрываем петлю обратной связи.
        case .pauseResolved(let verdict):
            handlePauseResolved(verdict)
        // P0 12.08.2026: хост ушёл, сервер передал роль. До этого уход хоста
        // просто закрывал комнату всем, поэтому обрабатывать было нечего.
        case .roleChanged(let event):
            applyRoleChange(event)
        case .error(let err):
            lastError = "\(err.code): \(err.message)"
            // Rollback on rejection errors.
            // Откатывать есть смысл ТОЛЬКО когда в полёте висит команда
            // плеера. Раньше условие смотрело лишь на код: любой RATE_LIMITED
            // (а его отдают и chat.send, и reaction.send, и pause.request)
            // прогонял handleActionRejection — то есть за третье сообщение в
            // чате хосту дёргало позицию плеера и запрашивало снапшот.
            // Остаточный случай — чат залимитило ровно в окне ожидания
            // sync.command; там лишний откат безвреден, состояние всё равно
            // авторитетное.
            if !pendingActions.isEmpty,
               err.code == "NOT_HOST" || err.code == "STALE_EPOCH" || err.code == "RATE_LIMITED" {
                handleActionRejection(err.code)
            }
            // Сервер отклонил сообщение из-за мута — синхронизируем таймер локально.
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
        // Countdown events ride on chat — intercept before bubbles.
        if let countdown = RoomCountdownWire.decode(chat.text) {
            if chat.senderId != currentUserId {
                let startAt = Date(timeIntervalSince1970: Double(countdown.startAtMs) / 1000)
                runCountdown(until: startAt, thenPlay: false)
            }
            return
        }
        // Смена приватности едет по чату — не рендерим как сообщение.
        if let modEvent = RoomModerationWire.decode(chat.text) {
            if let newPrivacy = RoomPrivacy(rawValue: modEvent.privacy) {
                roomPrivacy = newPrivacy
            }
            return
        }

        // ИИ-модератор — муты едут по чату. Рен��ерим системную строку,
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

        // Очередь видео комнаты едет по чату — обновляем список, не рендерим как сообщение.
        if let queueEvent = RoomQueueWire.decode(chat.text) {
            roomQueue = queueEvent.queue
            return
        }

        // Poll events ride on chat — intercept before rendering bubbles.
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
            // Update cursor for confirmed own messages too
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

        // Enqueue danmaku placement for this chat message.
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

    // Reaction handler with auto-expiry
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
        // auto-expire reactions after 3 seconds
        scheduleReactionExpiry()
    }

    // Remove old reactions after 3s
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
                // Expire individually, against the local arrival time. A sweep
                // counter here cleared every reaction at once — including one
                // that had just arrived — cutting its animation off mid-flight
                // roughly once a minute under a steady stream.
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
        // Buffer if snapshot is in flight
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
        // Buffer if snapshot is in flight
        if snapshotInFlight {
            bufferedParticipantEvents.append((isJoin: false, userId: event.userId, username: event.username))
            return
        }
        participants.removeAll { $0.userId == event.userId }
    }

    // MARK: - Chat catch-up (implemented REST client)

    // fetchChatCatchup with opaque cursor + persistent dedupe
    private func fetchChatCatchup() async {
        guard let client = chatCatchupClient else { return }

        // Initialize knownMessageIds from current chatMessages
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
                    // Dedupe by messageId using persistent set
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

                // Use server-provided opaque nextCursor, not messageId
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
            // Sort chronologically after merge
            chatMessages.sort { $0.createdAtMs < $1.createdAtMs }
        } catch {
            lastError = "Chat catch-up failed: \(error.localizedDescription)"
        }
    }

    // Presence snapshot with event buffering
    private func fetchPresenceSnapshot() async {
        guard let client = chatCatchupClient else { return }
        snapshotInFlight = true  // Buffer events during fetch
        do {
            let snapshot = try await client.fetchParticipants(roomId: _roomId)
            // Apply snapshot, then merge buffered events
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
            // Replay buffered participant events
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

    // Danmaku placements come from DanmakuEngine. The model
    // polls the engine every 250ms (display-linked cadence) and caches
    // the snapshot in danmakuSnapshot. Views read from this cached array
    // — they never await on the actor during render.
    var danmakuPlacements: [DanmakuPlacement] { danmakuSnapshot }
    var danmakuLaneCount: Int { 5 }
    var danmakuOpacity: Double { 0.85 }

    // Ambient palette comes from AmbientVideoSampler. Drives
    // PurpleAmbientBackdrop's primaryColor + secondaryColor so the room
    // haze breathes with the movie.
    var ambientState: AmbientState {
        AmbientState(
            intensity: AmbientCapability.shouldEnableLivingBackground() ? 0.55 : 0.0,
            primaryColor: ambientPalette.primaryColor,
            secondaryColor: ambientPalette.secondaryColor
        )
    }

    // Rutube fallback indicator. True when source is .rutube
    // and the embedded player's JS API is unavailable — UI shows a toast
    // prompting the user to open the video in Rutube's external app.
    var requiresRutubeFallback: Bool {
        guard case .rutube = coordinator.currentSource else { return false }
        guard let rutube = coordinator.currentController as? RutubePlaybackController else {
            return false
        }
        return rutube.requiresExternalFallback
    }

    // Open current Rutube video in SFSafariViewController.
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

    // MARK: - Приватность комнаты (бар модерации)

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
        AnalyticsService.shared.roomFinished(
            driftMs: Int(lastDriftMs.rounded()),
            participantCount: max(1, participants.count)
        )
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
    // Пустые openPlayerSettings()/startPiP() удалены.
    // Настройки плеера живут инлайн в PlinkPlayerControls.bottomBar; системный
    // PiP для WKWebView-эмбеда недоступен, а кнопок на эти методы не было.
    func enterFullscreen() {
        // Forces landscape rotation only — never disconnects or stops playback.
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
        // Кнопка скрыта флагом в PresenceBar и V4RoomControlsRow; guard —
        // второй барьер.
        //
        // Раньше здесь открывался пейволл .voiceChat. Это продажа фичи,
        // которой в сборке нет: LiveKit не подключён (ждём аккаунт Apple
        // Developer), поэтому оплативший Плинк+ получил бы ровно ничего.
        // Пока голос недоступен — молча ничего не делаем и пишем в лог.
        guard FeatureFlags.liveKitVoiceEnabled else {
            Logger.webrtc.warn("toggleMicrophone(): голос недоступен (LiveKit не подключён) — пейволл не показываем")
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
        // Camera in room — Plink+ only (same as voice).
        // Тот же дефект, что в toggleMicrophone — пейволл за фичу,
        // которой нет в сборке. Убран.
        guard FeatureFlags.liveKitVoiceEnabled else {
            Logger.webrtc.warn("toggleCamera(): видео в комнате недоступно (LiveKit не подключён) — пейволл не показываем")
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

    // Send a reaction emoji via RealtimeClient.
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
    public var isFailed: Bool  // Failed messages can be retried
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

    // Convenience init without isFailed
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

// Renamed from ReactionEvent to avoid @Observable macro ambiguity
public struct WatchReactionEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let userId: String
    public let username: String
    public let emoji: String
    public let timestampMs: Int64
    // Local arrival time. Expiry and animation are measured from this; the
    // server's timestampMs is kept only for ordering and dedup. Device and
    // server clocks drift by seconds, and a cutoff against the server stamp
    // therefore either never fires or fires instantly.
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

// MARK: - Chat catch-up REST client protocol

public protocol ChatCatchupClient: Sendable {
    func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse
    func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot]
}

// MARK: - Room recap client protocol

/// REST-клиент «что я пропустил» (POST /api/ai/room-recap). Отдельный от
/// ChatCatchupClient: догон чата — обязательная механика комнаты, рекап —
/// опциональная ИИ-фича, у которой клиента может не быть вовсе (тесты,
/// сборки без ИИ) — модель обязана честно жить с nil.
public protocol RoomRecapClient: Sendable {
    func fetchRecap(roomId: String, sinceMs: Int64) async throws -> RoomRecapResponse
}

public struct RoomRecapResponse: Sendable, Equatable, Decodable {
    /// nil — в пропущенном окне не было человеческой переписки.
    public let recap: String?
    public let messageCount: Int

    public init(recap: String?, messageCount: Int) {
        self.recap = recap
        self.messageCount = messageCount
    }
}

public struct ChatCatchupResponse: Sendable, Equatable {
    public let messages: [ChatCatchupMessage]
    public let hasMore: Bool
    public let nextCursor: String?  // Opaque server cursor
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
