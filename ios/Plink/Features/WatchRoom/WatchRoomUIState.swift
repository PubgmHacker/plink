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
    var chatDrawerVisible = true
    var isScrubbing = false
    var previewPosition: Double?
    var unreadCount = 0
    var activeToast: RoomToast?
    /// P1 5.11 (ревью): панель живой темы комнаты. Флаг живёт ЗДЕСЬ, а не в
    /// PlayerTopChrome: хром сидит внутри `if ui.controlsVisible` и через 4 с
    /// автоскрытия удалялся из иерархии вместе с презентованным шитом —
    /// панель схлопывалась прямо под пальцем хоста.
    var appearancePanelPresented = false

    // The ambient palette, room identity and presence list are owned by
    // WatchRoomModel (ambient is fed by AmbientVideoSampler). The values below
    // are inert defaults kept for source compatibility — read the model, never
    // treat these as a second source of truth.
    var ambient: AmbientState = AmbientState()
    var roomTitle: String = ""
    var hostDisplayName: String = ""
}

// MARK: - Toast

struct RoomToast: Identifiable, Equatable {
    enum Kind: Sendable, Equatable { case info, success, warning, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

// MARK: - Presence

