// Plink/Features/WatchRoom/WatchLayouts.swift
//
// Layout variants for WatchRoomScreen. Each layout includes PlayerStage
// with a stable .id so SwiftUI's diff preserves it across rotation.
// The underlying AVPlayer/WKWebView is owned by PlaybackCoordinator /
// EmbeddedPlaybackController and is NEVER recreated by orientation.
//
// PlayerStage has the SAME .id("plink.player.stage") across
// all 3 layouts. SwiftUI's diff treats it as the same view, so the
// underlying UIView is preserved during rotation. The surrounding chrome
// (chat, presence, composer) may rebuild, but the player identity is stable.
//
// Layout rules:
//   - Portrait:    safe area, 16:9 full-width player, 56pt presence, chat, composer
//   - Landscape:   player full canvas, optional trailing drawer (320-420pt)
//   - iPad:        player leading 60%+, social rail 340-400pt
//
// Animation: .plinkLayout (0.42s smooth spring, damping 0.92).

import SwiftUI

// MARK: - Portrait

struct PortraitWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        VStack(spacing: 0) {
            // Player must ignore keyboard — otherwise send/chat focus shrinks video
            PlayerStage(model: model, ui: $ui, variant: .portrait)
                .id("plink.player.stage")
                .aspectRatio(16 / 9, contentMode: .fit)
                .layoutPriority(1)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            PresenceBar(model: model)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            RoomControlsRowBridge(model: model)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            WatchChatView(model: model)
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

            WatchChatComposer(model: model)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Строка управления комнатой

/// Связывает `V4RoomControlsRow` с `WatchRoomModel`.
///
/// Вынесено в отдельный тип, потому что строке нужен `@Binding` на уровень
/// приватности, а `@Bindable` требует собственного места хранения — в
/// раскладке модель приходит как `let`.
private struct RoomControlsRowBridge: View {
    @Bindable var model: WatchRoomModel

    @State private var privacySheetPresented = false
    @State private var invitePresented = false
    @State private var queuePresented = false

    init(model: WatchRoomModel) {
        self.model = model
    }

    var body: some View {
        V4RoomControlsRow(
            privacy: $model.privacyLevel,
            queueCount: model.roomQueue.count,
            onTapPrivacy: {
                // Уровень доступа меняет только хост — гостю шторка
                // показала бы контролы, которые ничего не делают.
                guard model.isHost else { return }
                privacySheetPresented = true
            },
            onOpenQueue: { queuePresented = true },
            onInvite: { invitePresented = true },
            accent: V4.accent
        )
        .sheet(isPresented: $privacySheetPresented) {
            V4RoomPrivacySheet(
                privacy: $model.privacyLevel,
                roomCode: model.displayRoomCode,
                accent: V4.accent,
                onCopyLink: {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = model.roomShareText
                    #endif
                    HapticManager.impact(.light)
                },
                onDone: { privacySheetPresented = false }
            )
        }
        .sheet(isPresented: $invitePresented) {
            RoomInviteSheet(model: model)
        }
        .sheet(isPresented: $queuePresented) {
            RoomQueueSheet(model: model)
        }
    }
}

// MARK: - Landscape

struct LandscapeWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        ZStack(alignment: .trailing) {
            // Same .id as Portrait/Tablet → SwiftUI preserves
            // the underlying PlayerSurfaceView across rotation.
            PlayerStage(model: model, ui: $ui, variant: .landscape)
                .id("plink.player.stage")
                .ignoresSafeArea()

            if ui.chatDrawerVisible {
                LandscapeChatDrawer(model: model, isVisible: $ui.chatDrawerVisible)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.plinkDrawer) {
                            ui.chatDrawerVisible = true
                        }
                    } label: {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Cinema2026.text)
                            .frame(width: 44, height: 44)
                            .plinkGlass(.overlay, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .accessibilityLabel("Открыть чат")
                    .padding(.trailing, 12)
                }
            }
        }
    }
}

// MARK: - Tablet

struct TabletWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Same .id as Portrait/Landscape.
                PlayerStage(model: model, ui: $ui, variant: .tablet)
                    .id("plink.player.stage")
                    .aspectRatio(16 / 9, contentMode: .fit)

                RoomIdentityBar(model: model)
                PresenceBar(model: model)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Cinema2026.divider.opacity(0.45))
                .frame(width: 0.5)

            VStack(spacing: 0) {
                WatchChatHeader(model: model)
                WatchChatView(model: model)
                WatchChatComposer(model: model)
            }
            .frame(width: 360)
            .background(Cinema2026.background.opacity(0.95))
        }
    }
}
