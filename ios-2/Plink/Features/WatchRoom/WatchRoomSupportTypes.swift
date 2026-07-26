// Plink/Features/WatchRoom/WatchRoomSupportTypes.swift — PATCH 02
//
// Slimmed down per PATCH 02 spec. UI views have been extracted to:
//   - PlayerControlLayer.swift  (PlayerTopChrome, PlayerCenterControl,
//                                 PlayerChromeButton, PlayerSmallButton,
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
// Note: DanmakuMessage and DanmakuPlacement now live in
// Plink/Features/WatchRoom/Danmaku/DanmakuEngine.swift (PATCH 05).
// The old DanmakuMessage struct here had a `track: Int` field that was
// never used for true lane scheduling — PATCH 05 replaces it with the
// DanmakuEngine actor that assigns lanes dynamically based on availability.

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
