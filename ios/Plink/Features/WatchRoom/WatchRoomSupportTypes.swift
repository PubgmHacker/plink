// Plink/Features/WatchRoom/WatchRoomSupportTypes.swift
//
// Общие для нескольких файлов типы комнаты — без единого View.
// Экранные части живут рядом: PlayerControlLayer.swift (хром плеера),
// RoomIdentityBar.swift (шапка), WatchRoomOverlays.swift (шторки, тосты,
// аватары, даммаку).
//
// DanmakuMessage и DanmakuPlacement лежат в Danmaku/DanmakuEngine.swift:
// дорожки раздаёт актор движка, поэтому у сообщения нет статичного
// поля `track`.

import SwiftUI

// MARK: - Room input states

/// Presentation state for the optional room microphone control.
///
/// Audio/video transport is not a room source of truth; these values are kept
/// in the UI layer so the room model remains about playback and realtime state.
enum MicrophoneUIState: Equatable {
    case off
    case on
    case talking
    case pushToTalk
}

enum CameraUIState: Equatable {
    case off
    case on
    case loading
}
