//
//  PlinkRoomPresentation.swift
//  Plink
//
//  P0 — WatchRoom full-screen presentation protocol.
//  Implements Section 9 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  Rule: WatchRoom MUST open ONLY from a real joined/created room session.
//  Never from a bare `videoID`. `room == true` is not enough.
//
//  NOTE: This file does NOT redefine `PlaybackSource` — the project already
//  ships one in `Plink/Playback/PlaybackSource.swift` with cases `hls/mp4/
//  youtube/rutube/external`. We reuse that.
//

import SwiftUI

// MARK: - PresentedRoom

/// The only payload that may trigger `WatchRoom`.
/// Produced by RoomService.create / RoomService.join / AI create flow.
struct PresentedRoom: Identifiable, Sendable {
    let id: String                 // roomID — drives .fullScreenCover(item:)
    let room: Room                 // backend-authoritative snapshot (real Plink.Room)
    let source: PlaybackSource     // resolved playable source (real Plink.PlaybackSource)

    init(id: String, room: Room, source: PlaybackSource) {
        self.id = id
        self.room = room
        self.source = source
    }
}

// MARK: - RoomPresentationError

enum RoomPresentationError: LocalizedError, Sendable {
    case noResolvedSession
    case missingPlaybackSource
    case backendReject(reason: String)
    case idempotencyCollision
    case joinFailed(reason: String)
    case createFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .noResolvedSession:        return "Сессия комнаты не готова. Попробуйте ещё раз."
        case .missingPlaybackSource:    return "Источник воспроизведения не определён."
        case .backendReject(let r):     return "Сервер отклонил запрос: \(r)"
        case .idempotencyCollision:      return "Запрос уже отправлен. Подождите."
        case .joinFailed(let r):        return "Не удалось войти в комнату: \(r)"
        case .createFailed(let r):      return "Не удалось создать комнату: \(r)"
        }
    }
}

// MARK: - RoomPresentationCoordinator

/// Single source of truth for opening / closing WatchRoom.
/// All navigation surfaces (Home hero, Rooms list, AI create flow)
/// MUST route through this coordinator — never present WatchRoom directly.
@MainActor
@Observable
final class RoomPresentationCoordinator {
    var presentedRoom: PresentedRoom?
    private(set) var isResolving: Bool = false
    private(set) var lastError: RoomPresentationError?

    /// Tracks in-flight idempotency keys to prevent double-tap double-create.
    private var inFlightKeys: Set<String> = []

    /// Injected RoomService instance. Real app uses `RoomService(api: APIClient.shared)`.
    private let roomService: RoomService?

    init(roomService: RoomService? = nil) {
        self.roomService = roomService
    }

    // MARK: Join

    /// Join an existing room. Used by "Войти" button on room cards and AI-proposed rooms.
    func join(roomCode: String) async {
        guard !isResolving else { return }
        let key = "join-\(roomCode)"
        guard !inFlightKeys.contains(key) else {
            lastError = .idempotencyCollision
            return
        }
        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }

        guard let svc = roomService else {
            lastError = .joinFailed(reason: "RoomService not configured")
            return
        }

        isResolving = true
        lastError = nil
        do {
            let joined = try await svc.joinRoom(code: roomCode)
            let source = try await resolveSource(for: joined)
            presentedRoom = PresentedRoom(id: joined.id, room: joined, source: source)
        } catch let e as RoomPresentationError {
            lastError = e
        } catch {
            lastError = .joinFailed(reason: error.localizedDescription)
        }
        isResolving = false
    }

    // MARK: Create

    /// Create a new room from a draft. Used by AI create flow and manual create.
    /// `idempotencyKey` MUST be supplied by the caller (UUID per user-intent).
    func create(
        request: CreateRoomRequest,
        idempotencyKey: String
    ) async {
        guard !isResolving else { return }
        guard !inFlightKeys.contains(idempotencyKey) else {
            lastError = .idempotencyCollision
            return
        }
        inFlightKeys.insert(idempotencyKey)
        defer { inFlightKeys.remove(idempotencyKey) }

        guard let svc = roomService else {
            lastError = .createFailed(reason: "RoomService not configured")
            return
        }

        isResolving = true
        lastError = nil
        do {
            let created = try await svc.createRoom(request)
            let source = try await resolveSource(for: created)
            presentedRoom = PresentedRoom(id: created.id, room: created, source: source)
        } catch let e as RoomPresentationError {
            lastError = e
        } catch {
            lastError = .createFailed(reason: error.localizedDescription)
        }
        isResolving = false
    }

    // MARK: Dismiss

    func dismiss() {
        presentedRoom = nil
    }

    // MARK: Helpers

    private func resolveSource(for room: Room) async throws -> PlaybackSource {
        // Resolve from real Room.mediaItem into the existing PlaybackSource enum.
        if let item = room.mediaItem {
            if item.source == .youtube, let vid = item.videoId, !vid.isEmpty {
                return .youtube(vid)
            }
            if item.streamURL.hasSuffix(".m3u8") {
                return .hls(URL(string: item.streamURL)!, headers: [:])
            }
            if item.streamURL.hasSuffix(".mp4") {
                return .mp4(URL(string: item.streamURL)!, headers: [:])
            }
            // Default to mp4 for any non-empty URL.
            if !item.streamURL.isEmpty, let url = URL(string: item.streamURL) {
                return .mp4(url, headers: [:])
            }
        }
        throw RoomPresentationError.missingPlaybackSource
    }
}

// MARK: - View modifier

extension View {
    /// Attach WatchRoom presentation to any view that owns a `RoomPresentationCoordinator`.
    /// Renders WatchRoom via `.fullScreenCover(item:)` — never `.sheet`.
    func plinkRoomPresentation(
        _ coordinator: RoomPresentationCoordinator,
        @ViewBuilder screen: @escaping (PresentedRoom) -> some View
    ) -> some View {
        self.fullScreenCover(item: Binding(
            get: { coordinator.presentedRoom },
            set: { coordinator.presentedRoom = $0 }
        )) { session in
            screen(session)
                .transaction { $0.disablesAnimations = false }
        }
    }
}
