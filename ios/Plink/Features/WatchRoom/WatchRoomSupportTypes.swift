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
