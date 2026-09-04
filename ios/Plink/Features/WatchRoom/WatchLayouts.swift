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
    /// Голосование запускает экран (у него живёт шит композера). В портрете
    /// кнопка стоит в строке комнаты, а не оверлеем поверх кадра: там она
    /// садилась ровно на ряд перемотки.
    var onPoll: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Player must ignore keyboard — otherwise send/chat focus shrinks video
            PlayerStage(model: model, ui: $ui, variant: .portrait)
                .id("plink.player.stage")
                .aspectRatio(16 / 9, contentMode: .fit)
                .layoutPriority(1)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            RoomHeaderBar(model: model, onPoll: onPoll)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            WatchChatView(model: model)
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

            WatchChatComposer(model: model)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Room header bar

/// One compact strip under the player: who is here, the privacy level and the
/// two room actions (queue, invite). It replaces the former presence bar plus
/// controls row, which stacked two dark bands under the video and carried a
/// second, differently tinted "+" next to the one in the player chrome.
private struct RoomHeaderBar: View {
    @Bindable var model: WatchRoomModel
    var onPoll: (() -> Void)?

    @State private var privacySheetPresented = false
    @State private var invitePresented = false
    @State private var queuePresented = false

    init(model: WatchRoomModel, onPoll: (() -> Void)? = nil) {
        self.model = model
        self.onPoll = onPoll
    }

    private var accent: Color { PlinkRoomAccent.current }
    private var shownParticipants: [ParticipantInfo] {
        Array(model.participants.prefix(model.participants.count > 3 ? 3 : model.participants.count))
    }
    private var overflow: Int { max(0, model.participants.count - shownParticipants.count) }

    var body: some View {
        HStack(spacing: 10) {
            avatarStack

            VStack(alignment: .leading, spacing: 1) {
                Text(model.presenceCountLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(model.presenceStatusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            privacyChip

            if let onPoll, model.activePoll == nil {
                glassButton(glyph: .poll, label: "Создать голосование", action: onPoll)
            }

            glassButton(glyph: .queue, badge: model.roomQueue.count, label: "Очередь") {
                queuePresented = true
            }
            glassButton(glyph: .plus, label: "Пригласить в комнату") {
                invitePresented = true
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .sheet(isPresented: $privacySheetPresented) {
            V4RoomPrivacySheet(
                privacy: $model.privacyLevel,
                roomCode: model.displayRoomCode,
                accent: accent,
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

    private var avatarStack: some View {
        HStack(spacing: -8) {
            ForEach(shownParticipants) { participant in
                Circle()
                    .fill(Cinema2026.raised)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(participant.username.prefix(1)).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                    )
                    .overlay(
                        Circle().stroke(
                            participant.userId == model.hostId ? accent : Cinema2026.background,
                            lineWidth: 1.5
                        )
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .frame(width: 28, height: 28)
                    .background(Cinema2026.raised, in: Circle())
                    .overlay(Circle().stroke(Cinema2026.background, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }

    private var privacyChip: some View {
        Button {
            // Only the host can change the level; a guest would get a sheet
            // full of controls that do nothing.
            guard model.isHost else { return }
            HapticManager.impact(.light)
            privacySheetPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.privacyLevel.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(model.privacyLevel.chipTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if model.isHost {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.65)
                }
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .plinkGlass(.control, in: Capsule(style: .continuous), interactive: model.isHost)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Приватность комнаты: \(model.privacyLevel.title)")
    }

    private func glassButton(
        glyph: V4Glyph, badge: Int = 0, label: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            V4GlyphIcon(glyph: glyph, size: 14, weight: .regular)
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 34, height: 34)
                .plinkGlass(.control, in: Circle(), interactive: true)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(accent, in: Capsule())
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(label), \(badge)" : label)
    }
}

// MARK: - Landscape

struct LandscapeWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        // Геометрию читаем ДО .ignoresSafeArea() на кадре: сам кадр идёт от
        // края до края, а хром обязан знать и вырез, и ширину ящика чата.
        GeometryReader { proxy in
            landscapeBody(size: proxy.size, safeArea: proxy.safeAreaInsets)
        }
    }

    private func landscapeBody(size: CGSize, safeArea: EdgeInsets) -> some View {
        let insets = WatchLandscapeMetrics.chromeInsets(
            canvasWidth: size.width,
            safeArea: safeArea,
            drawerVisible: ui.chatDrawerVisible
        )
        PlinkChromeTrace.log(
            "landscape size=\(size.width)x\(size.height)"
            + " safe=l\(safeArea.leading)/t\(safeArea.trailing)"
            + " drawer=\(ui.chatDrawerVisible ? 1 : 0)"
            + " drawerW=\(WatchLandscapeMetrics.drawerWidth(for: size.width))"
            + " insetTrailing=\(insets.trailing)"
        )
        return ZStack(alignment: .trailing) {
            // Same .id as Portrait/Tablet → SwiftUI preserves
            // the underlying PlayerSurfaceView across rotation.
            PlayerStage(
                model: model,
                ui: $ui,
                variant: .landscape,
                chromeInsets: insets
            )
                .id("plink.player.stage")
                .ignoresSafeArea()

            // Кнопки «открыть чат» поверх кадра больше нет: она висела у
            // правого края над полосой перемотки и перекрывала её конец
            // вместе со звуком и полным экраном. Переключатель чата теперь
            // стоит в нижней панели плеера (PlinkPlayerControls).
            if ui.chatDrawerVisible {
                LandscapeChatDrawer(model: model, isVisible: $ui.chatDrawerVisible,
                                    containerWidth: size.width, safeArea: safeArea)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
