// Plink/Features/WatchRoom/WatchRoomUIState.swift — PATCH 02: UI state shell
//
// Commit Group 1: minimum fields required for the new WatchRoomScreen
// scaffolding from PATCH 02, while preserving the existing fields used by
// the current WatchRoomScreen / WatchLayouts / PlayerStage implementation.
//
// Fields that exist on the model (reactions, participants, etc.) are NOT
// duplicated here; they remain on WatchRoomModel.ui-reachable via direct
// model access. The fields here are pure UI ephemerals (control visibility,
// scrubbing state, chat drawer) plus the ambient state shell that PATCH 06
// will populate.

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

    // PATCH 02 scaffolding — ambient + identity + presence shell.
    // Commit 7 (PATCH 06) replaces AmbientState defaults with sampled palette.
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
    let id: String           // user id
    let displayName: String
    let avatarColorHex: UInt32
    let isSpeaking: Bool
    let isHost: Bool

    var avatarColor: Color { Color(hex: avatarColorHex) }
}
