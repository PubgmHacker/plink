// Plink/Features/WatchRoom/WatchRoomUIState.swift
// Ephemeral view state shared by WatchRoomScreen, WatchLayouts and PlayerStage.
//
// Fields that exist on the model (reactions, participants, etc.) are NOT
// duplicated here; they stay on WatchRoomModel and are read through direct
// model access. What belongs here is presentation-only — control visibility,
// scrubbing state, chat drawer — plus the inert ambient / identity / presence
// defaults described below.

import Foundation
import SwiftUI

struct WatchRoomUIState: Equatable {
    // Ephemeral UI state (existing — preserved for back-compat)
    var controlsVisible = true
    var chatPresented = false
    /// Ящик чата в ландшафте. По умолчанию закрыт: ландшафт — это «во весь
    /// экран», и открывать поверх фильма панель на 40 % ширины за человека
    /// неправильно. Чат в одном тапе — переключатель стоит в нижней панели
    /// плеера рядом со звуком.
    var chatDrawerVisible = false
    var isScrubbing = false
    var previewPosition: Double?
    var unreadCount = 0
    var activeToast: RoomToast?
    /// P1 5.11 (ревью): панель живой темы комнаты. Флаг живёт ЗДЕСЬ, а не в
    /// PlayerTopChrome: хром сидит внутри `if ui.controlsVisible` и через 4 с
    /// автоскрытия удалялся из иерархии вместе с презентованным шитом —
    /// панель схлопывалась прямо под пальцем хоста.
    var appearancePanelPresented = false
    /// Stamp of the last chrome toggle. A web player surface reports taps
    /// through a UIKit recognizer while the room root also has a SwiftUI tap;
    /// one finger may reach both, so the toggle is collapsed per touch.
    var controlsToggledAt: Date = .distantPast

    /// Toggles the chrome once per touch; returns false when the tap was a
    /// duplicate of one handled a moment ago.
    @discardableResult
    mutating func toggleControlsDebounced() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(controlsToggledAt) > 0.35 else { return false }
        controlsToggledAt = now
        controlsVisible.toggle()
        return true
    }

    // The ambient palette, room identity and presence list are owned by
    // WatchRoomModel (ambient is fed by AmbientVideoSampler). The values below
    // are inert defaults kept for source compatibility — read the model, never
    // treat these as a second source of truth.
    var ambient: AmbientState = AmbientState()
    var roomTitle: String = ""
    var hostDisplayName: String = ""
    var presence: [PresencePill] = []
}

// MARK: - Toast

struct RoomToast: Identifiable, Equatable {
    enum Kind: Sendable, Equatable { case info, success, warning, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

// MARK: - Presence

struct PresencePill: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let avatarColorHex: UInt32
    let isSpeaking: Bool
    let isHost: Bool

    var avatarColor: Color { Color(hex: avatarColorHex) }
}

// MARK: - Presence

/// Диагностика хрома: кто именно поднял или погасил панель. Пишется только
/// в отладочной сборке и только под `-plink.designplayer`, читается из лога
/// симулятора живым UI-кейсом. В релизе функции нет вовсе.
enum PlinkChromeTrace {
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.arguments.contains("-plink.designplayer")
    static func log(_ what: String) {
        guard enabled else { return }
        NSLog("PLINKCHROME %@", what)
    }
    #else
    static func log(_ what: String) {}
    #endif
}
