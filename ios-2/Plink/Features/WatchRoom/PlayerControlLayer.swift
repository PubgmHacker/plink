// Plink/Features/WatchRoom/PlayerControlLayer.swift — PATCH 02
//
// Extracted from PlayerStage.swift per PATCH 02 spec.
//
// Contains:
//   - PlayerTopChrome     (close, sync pill, more menu)
//   - PlayerCenterControl (play/pause for host)
//   - PlayerChromeButton  (36pt touch target, .ultraThinMaterial bg)
//   - PlayerSmallButton   (32pt, for PiP / fullscreen)
//   - PlayerLoadingView   (initial buffer spinner)
//   - BufferingOverlay    (mid-playback rebuffer)
//   - SyncHealthPill      (drift indicator)
//
// Professional sizing:
//   - Chrome buttons: 36pt (was 32pt) — meets 36pt min touch target.
//   - Center control: 64pt (was 52pt) — Apple TV app parity.
//   - Sync pill: 12pt font (was 11pt), proper internal padding.
//   - All chrome uses .ultraThinMaterial over void for depth.

import SwiftUI

// MARK: - Top chrome

struct PlayerTopChrome: View {
    let model: WatchRoomModel
    let variant: WatchRoomLayoutState.Variant
    // M14: шит приглашения (QR + шер-линк)
    @State private var showInvite = false

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                PlayerChromeButton(systemName: "xmark") {
                    model.leaveRoom()
                }
                .accessibilityLabel("Leave room")

                Spacer()

                SyncHealthPill(
                    driftMs: model.lastDriftMs,
                    connected: model.connectionState == .connected
                )

                Spacer()

                // M15: бар модерации — повторный вызов (только хост)
                if model.isHost {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            model.moderationBarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(model.moderationBarVisible ? PlinkRoomAccent.current : Color.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Модерация комнаты")
                }

                // M14: полноценное приглашение: QR-код + шер-линк + копирование
                Button {
                    HapticManager.impact(.light)
                    showInvite = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PlinkRoomAccent.current)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Пригласить в комнату")
                .sheet(isPresented: $showInvite) {
                    RoomInviteSheet(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, variant == .landscape ? 12 : 8)
            Spacer()
        }
    }
}

// MARK: - Center control

struct PlayerCenterControl: View {
    let model: WatchRoomModel

    var body: some View {
        Button {
            if model.coordinator.isPlaying {
                model.sendPauseCommand()
            } else {
                // M14: синхронный отсчёт 3-2-1, когда в комнате есть зрители
                model.sendPlayWithCountdown()
            }
        } label: {
            Image(systemName: model.coordinator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: model.coordinator.isPlaying ? 0 : 1.5)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    // M14: акцент выбранной V4-темы продолжается в комнате
                    Circle().stroke(PlinkRoomAccent.current.opacity(0.65), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!model.isHost || model.connectionState != .connected || model.countdownRemaining != nil)
        .opacity(model.isHost ? 1 : 0)
        .accessibilityLabel(model.coordinator.isPlaying ? "Pause" : "Play")
    }
}

// MARK: - Chrome buttons

struct PlayerChromeButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Cinema2026.text)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct PlayerSmallButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cinema2026.text)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading & buffering

struct PlayerLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Cinema2026.accent)
                .scaleEffect(1.15)
            Text("Loading…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BufferingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(0.95)
            .padding(18)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Sync health pill

struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    private var color: Color {
        guard connected else { return Cinema2026.danger }
        if driftMs < 80 { return Cinema2026.accent }
        if driftMs < 250 { return Cinema2026.secondary }
        if driftMs < 750 { return Cinema2026.amber }
        return Cinema2026.danger
    }

    private var label: String {
        guard connected else { return "Offline" }
        if driftMs < 80 { return "In sync" }
        if driftMs < 250 { return "Syncing" }
        if driftMs < 750 { return "Lagging" }
        return "Resync"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }
}
