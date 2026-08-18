// Plink/Features/WatchRoom/WatchRoomSupportTypes.swift
//
// Slimmed down. UI views have been extracted to:
//   - PlayerControlLayer.swift  (PlayerTopChrome, PlayerCenterControl,
//                                 PlayerChromeButton,
//                                 PlayerLoadingView, BufferingOverlay,
//                                 SyncHealthPill)
//   - RoomIdentityBar.swift     (RoomIdentityBar)
//   - WatchRoomOverlays.swift   (RoomToastView, WatchChatSheet,
//                                 LandscapeChatDrawer, WatchChatHeader,
//                                 ChatAvatar, ParticipantAvatar,
//                                 DanmakuCanvasLayer, VoiceActionButton,
//                                 CameraActionButton)
//
// This file keeps only the data types (no View body) that are shared
// across multiple files.

import SwiftUI

// MARK: - RTC UI States
//
// Note: DanmakuMessage and DanmakuPlacement live in
// Plink/Features/WatchRoom/Danmaku/DanmakuEngine.swift.
// Lane scheduling is the DanmakuEngine actor's job: it assigns lanes
// dynamically based on availability, so a message carries no static
// `track: Int` index.

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
