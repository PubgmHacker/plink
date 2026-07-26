//
//  PlinkRoomAppearance.swift
//  Plink
//
//  P1 — Host-authoritative room appearance protocol.
//  Implements Section 2.2 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI
import Foundation

// MARK: - RoomAppearance

internal struct RoomAppearance: Codable, Sendable, Equatable {
    let themeId: String
    let themeRevision: Int
    var intensity: Double       // 0.0 ... 0.44 (V4 cap)
    var motionEnabled: Bool

    init(
        themeId: String,
        themeRevision: Int = 1,
        intensity: Double = 0.44,
        motionEnabled: Bool = true
    ) {
        self.themeId = themeId
        self.themeRevision = themeRevision
        self.intensity = min(intensity, 0.44)
        self.motionEnabled = motionEnabled
    }

    static let defaultStatic = RoomAppearance(
        themeId: "room-default-static",
        themeRevision: 1,
        intensity: 0.30,
        motionEnabled: false
    )
}

// MARK: - RoomAppearanceRegistry

internal enum RoomAppearanceRegistry {
    static func resolve(themeId: String) -> AppearanceDescriptor? {
        AppearanceCatalog.roomLive.first { $0.id == themeId }
    }

    /// Returns `defaultStatic` if the themeId is unknown or revoked.
    static func safeResolve(themeId: String) -> RoomAppearance {
        if resolve(themeId: themeId) != nil {
            return RoomAppearance(themeId: themeId, intensity: 0.44, motionEnabled: true)
        }
        return .defaultStatic
    }
}

// MARK: - RoomAppearanceStore (per active room)

@MainActor
@Observable
internal final class RoomAppearanceStore {
    private(set) var appearance: RoomAppearance = .defaultStatic
    private(set) var isHost: Bool = false

    private let roomID: String
    private let entitlement: EntitlementProviding

    init(roomID: String, isHost: Bool, entitlement: EntitlementProviding) {
        self.roomID = roomID
        self.isHost = isHost
        self.entitlement = entitlement
    }

    // MARK: - Receive from server

    func applyServerUpdate(_ new: RoomAppearance) {
        self.appearance = RoomAppearanceRegistry.safeResolve(themeId: new.themeId)
            .mutating(intensity: new.intensity, motionEnabled: new.motionEnabled)
    }

    // MARK: - Host mutations

    func updateTheme(to themeId: String) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        guard let desc = RoomAppearanceRegistry.resolve(themeId: themeId) else {
            throw RoomAppearanceError.unknownTheme
        }
        if desc.premium {
            guard entitlement.isPlinkPlus else { throw RoomAppearanceError.requiresPlinkPlus }
        }
        let payload = RoomAppearance(
            themeId: themeId,
            themeRevision: desc.revision,
            intensity: 0.44,
            motionEnabled: true
        )
        try await persistAppearance(payload)
        self.appearance = payload
    }

    func setIntensity(_ value: Double) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        let capped = min(value, 0.44)
        var updated = appearance
        updated.intensity = capped
        try await persistAppearance(updated)
        self.appearance = updated
    }

    func setMotionEnabled(_ value: Bool) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        var updated = appearance
        updated.motionEnabled = value
        try await persistAppearance(updated)
        self.appearance = updated
    }

    // MARK: - Backend

    private func persistAppearance(_ payload: RoomAppearance) async throws {
        let body = RoomAppearanceUpdate(
            themeId: payload.themeId,
            themeRevision: payload.themeRevision,
            intensity: payload.intensity,
            motionEnabled: payload.motionEnabled
        )
        do {
            try await APIClient.shared.requestNoBody(
                "rooms/\(roomID)/appearance",
                method: .patch,
                body: body
            )
        } catch {
            throw RoomAppearanceError.backendRejected(reason: error.localizedDescription)
        }
    }
}

// MARK: - Errors

internal enum RoomAppearanceError: LocalizedError, Sendable {
    case notHost
    case unknownTheme
    case requiresPlinkPlus
    case backendRejected(reason: String)

    var errorDescription: String? {
        switch self {
        case .notHost:                  return "Только хост может менять оформление комнаты."
        case .unknownTheme:             return "Тема не найдена в реестре."
        case .requiresPlinkPlus:        return "Эта тема требует Plink+ у хоста."
        case .backendRejected(let r):   return "Сервер отклонил: \(r)"
        }
    }
}

// MARK: - Helpers

extension RoomAppearance {
    func mutating(intensity: Double, motionEnabled: Bool) -> RoomAppearance {
        RoomAppearance(
            themeId: themeId,
            themeRevision: themeRevision,
            intensity: min(intensity, 0.44),
            motionEnabled: motionEnabled
        )
    }
}

// MARK: - RoomAppearanceOverlay

/// The animated background for the room chat / video frame.
/// Renders INSIDE the room surface only. Never overlays the player viewport.
struct RoomAppearanceOverlay: View {
    @Bindable var store: RoomAppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(store: RoomAppearanceStore) {
        self.store = store
    }

    var body: some View {
        let motion = store.appearance.motionEnabled && !reduceMotion && !ProcessInfo.isLowPower
        let intensity = reduceTransparency ? min(store.appearance.intensity, 0.20) : store.appearance.intensity

        ZStack {
            if motion {
                RoomThemeAnimation(themeId: store.appearance.themeId, intensity: intensity)
            } else {
                RoomThemePoster(themeId: store.appearance.themeId, intensity: intensity)
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

// MARK: - RoomThemeAnimation (placeholder until assets arrive)

struct RoomThemeAnimation: View {
    let themeId: String
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { g, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let colors = RoomAppearanceRegistry.resolve(themeId: themeId)?.previewColors
                    ?? ["#0A0E1A", "#1A1F3A"]
                let c1 = Color(hex: colors[0])
                let c2 = Color(hex: colors[safe: 1] ?? "#3FE8C8")
                let r = CGRect(origin: .zero, size: size)

                let b1 = CGRect(
                    x: r.width * (0.2 + 0.1 * sin(phase * 0.4)),
                    y: r.height * (0.3 + 0.1 * cos(phase * 0.3)),
                    width: r.width * 0.6,
                    height: r.height * 0.6
                )
                let b2 = CGRect(
                    x: r.width * (0.5 + 0.1 * cos(phase * 0.35)),
                    y: r.height * (0.4 + 0.1 * sin(phase * 0.45)),
                    width: r.width * 0.5,
                    height: r.height * 0.5
                )
                g.fill(Path(ellipseIn: b1), with: .color(c1.opacity(intensity)))
                g.fill(Path(ellipseIn: b2), with: .color(c2.opacity(intensity * 0.7)))
            }
        }
    }
}

// MARK: - RoomThemePoster

struct RoomThemePoster: View {
    let themeId: String
    let intensity: Double

    var body: some View {
        let colors = RoomAppearanceRegistry.resolve(themeId: themeId)?.previewColors
            ?? ["#0A0E1A", "#1A1F3A"]
        LinearGradient(
            colors: colors.map { (Color(hex: $0)).opacity(0.6 + intensity * 0.4) },
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Array safety

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ProcessInfo {
    static var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
