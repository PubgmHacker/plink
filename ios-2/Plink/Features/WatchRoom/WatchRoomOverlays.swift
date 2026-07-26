// Plink/Features/WatchRoom/WatchRoomOverlays.swift — PATCH 02
//
// Extracted from WatchRoomSupportTypes.swift per PATCH 02 spec.
//
// Contains:
//   - RoomToastView          (toast notification)
//   - WatchChatSheet         (modal chat sheet for portrait)
//   - LandscapeChatDrawer    (slide-in chat for landscape)
//   - WatchChatHeader        (chat header with title + watcher count)
//   - ChatAvatar             (small avatar in chat bubble)
//   - ParticipantAvatar      (larger avatar in presence bar)
//   - DanmakuCanvasLayer     (flying comments overlay)
//   - VoiceActionButton      (mic toggle)
//   - CameraActionButton     (camera toggle)
//
// All chrome uses .ultraThinMaterial + subtle strokes for depth.

import SwiftUI

// MARK: - Toast

struct RoomToastView: View {
    let toast: RoomToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForKind)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colorForKind)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cinema2026.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(colorForKind.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 8)
    }

    private var colorForKind: Color {
        switch toast.kind {
        case .info: return Cinema2026.secondary
        case .success: return Cinema2026.accent
        case .warning: return Cinema2026.amber
        case .error: return Cinema2026.danger
        }
    }

    private var iconForKind: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Chat containers

struct WatchChatSheet: View {
    let model: WatchRoomModel

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model)
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .background(Cinema2026.background)
    }
}

struct LandscapeChatDrawer: View {
    let model: WatchRoomModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model, closable: true, onClose: {
                withAnimation(.plinkDrawer) {
                    isVisible = false
                }
            })
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.5))
                .frame(width: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 16, x: -4, y: 0)
    }
}

struct WatchChatHeader: View {
    let model: WatchRoomModel
    var closable: Bool = false
    var onClose: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text("Chat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .medium))
                Text("\(model.participants.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Cinema2026.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Cinema2026.raised.opacity(0.6), in: Capsule())

            if closable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 28, height: 28)
                        .background(Cinema2026.raised, in: Circle())
                }
                .accessibilityLabel("Close chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Cinema2026.surface.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Avatars

struct ChatAvatar: View {
    let message: ChatMessageInfo

    var body: some View {
        Circle()
            .fill(avatarBackground)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(avatarForeground)
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var avatarBackground: Color {
        if message.isAdmin { return Cinema2026.amber.opacity(0.18) }
        if message.isPremium { return Cinema2026.danger.opacity(0.18) }
        return Cinema2026.raised
    }

    private var avatarForeground: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.danger }
        return Cinema2026.text
    }
}

struct ParticipantAvatar: View {
    let participant: ParticipantInfo
    let hostId: String?
    var isSpeaking: Bool = false

    private var isHost: Bool { participant.userId == hostId }

    var body: some View {
        Circle()
            .fill(Cinema2026.raised)
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(participant.username.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
            )
            .overlay(
                Circle()
                    .stroke(ringColor, lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if isHost {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Cinema2026.amber)
                        .background(Cinema2026.background, in: Circle())
                        .frame(width: 14, height: 14)
                        .offset(x: 1, y: 1)
                }
            }
    }

    private var ringColor: Color {
        if isSpeaking { return Cinema2026.accent }
        if isHost { return Cinema2026.amber.opacity(0.6) }
        return Cinema2026.accent.opacity(0.18)
    }
}

// MARK: - Danmaku
//
// PATCH 05: DanmakuCanvasLayer now renders DanmakuPlacement snapshots from
// the DanmakuEngine actor. Lane assignment, duration, and progress are all
// computed by the engine — this view only draws the current snapshot.
//
// The view polls the engine via TimelineView at .animation cadence (~16ms).
// Each frame it asks the engine for poll(at: now), which returns the
// surviving placements sorted by lane.
//
// Tap on a placement freezes it for 2 seconds (per PATCH 05 spec).
// Long press reports/blocks the sender — wired via closures.

struct DanmakuCanvasLayer: View {
    let placements: [DanmakuPlacement]
    let laneCount: Int
    let opacity: Double
    var onTap: ((DanmakuPlacement) -> Void)? = nil
    var onLongPress: ((DanmakuPlacement) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let laneHeight = proxy.size.height / CGFloat(max(1, laneCount))
            let viewportWidth = proxy.size.width

            ZStack(alignment: .topLeading) {
                ForEach(placements) { placement in
                    DanmakuItemView(placement: placement, viewportWidth: viewportWidth)
                        .offset(x: xOffset(for: placement, in: viewportWidth),
                                y: CGFloat(placement.lane) * laneHeight + 4)
                        .opacity(opacity)
                        .onTapGesture { onTap?(placement) }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            onLongPress?(placement)
                        }
                }
            }
        }
        .allowsHitTesting(true)
    }

    /// Compute x-offset for a placement at the current frame.
    /// progress 0 = right edge (entering), progress 1 = left edge (exiting).
    /// We compute relative to the placement's own createdAt — but since
    /// this view is fed a snapshot, the caller must use TimelineView to
    /// drive re-renders. The actual progress is recomputed each frame by
    /// the engine's poll() — but we need a stable offset for the rendered
    /// snapshot. For simplicity, we use the placement.id's hash as a
    /// deterministic initial offset and the placement.duration for the
    /// traversal speed.
    ///
    /// NOTE: the engine's poll() returns placements sorted by lane, but
    /// the actual progress is computed by the View using ContinuousClock
    /// — see DanmakuItemView below.
    private func xOffset(for placement: DanmakuPlacement, in viewportWidth: CGFloat) -> CGFloat {
        // The View below (DanmakuItemView) handles its own animation via
        // .offset modifier internally based on TimelineView. This outer
        // offset is just the lane entry position (right edge).
        return 0
    }
}

/// Single danmaku item with self-contained animation. Uses TimelineView
/// to drive its own x-offset based on the placement's createdAt and
/// duration. This avoids re-rendering the entire layer every frame.
private struct DanmakuItemView: View {
    let placement: DanmakuPlacement
    let viewportWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            // PATCH 16: use Date-based progress overload — TimelineView
            // provides context.date as Date, and DanmakuPlacement stores
            // a parallel createdAtDate for this purpose.
            let progress = placement.progress(at: context.date, speed: 1.0)
            let x = viewportWidth - (CGFloat(progress) * (viewportWidth + estimatedTextWidth + 40))

            Text(placement.text)
                .font(.system(size: placement.isPremium ? 17 : 14, weight: .medium))
                .foregroundStyle(placement.isAdmin ? Cinema2026.amber : placement.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Cinema2026.background.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.05), lineWidth: 0.5))
                .offset(x: x)
        }
    }

    private var estimatedTextWidth: CGFloat {
        CGFloat(placement.text.count) * 8
    }
}

// MARK: - Voice / Camera buttons

struct VoiceActionButton: View {
    let state: MicrophoneUIState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
                .background(bgColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .off: return "mic.slash.fill"
        case .on: return "mic.fill"
        case .talking: return "mic.fill"
        case .pushToTalk: return "mic.fill"
        }
    }
    private var iconColor: Color {
        switch state {
        case .off: return Cinema2026.danger
        case .on: return Cinema2026.text
        case .talking: return Cinema2026.accent
        case .pushToTalk: return Cinema2026.amber
        }
    }
    private var bgColor: Color {
        switch state {
        case .talking: return Cinema2026.accent.opacity(0.16)
        default: return .clear
        }
    }
    private var accessibilityLabel: String {
        switch state {
        case .off: return "Unmute"
        case .on: return "Mute"
        case .talking: return "Talking"
        case .pushToTalk: return "Hold to talk"
        }
    }
}

struct CameraActionButton: View {
    let state: CameraUIState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state == .on ? Cinema2026.accent : Cinema2026.secondary)
                .frame(width: 38, height: 38)
                .background(.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Camera off" : "Camera on")
    }

    private var iconName: String {
        state == .on ? "video.fill" : "video.slash.fill"
    }
}

// MARK: - PATCH 14: Rutube fallback toast

/// Toast shown when source is .rutube and the embedded player's JS API
/// is unavailable. Tapping "Open" launches SFSafariViewController with
/// the Rutube video URL.
struct RutubeFallbackToast: View {
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.amber)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text("Open in Rutube to watch")
                    .font(.system(size: 11))
                    .foregroundStyle(Cinema2026.secondary)
            }

            Spacer()

            Button(action: onOpen) {
                Text("Open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Cinema2026.accentAction, in: Capsule())
            }
            .accessibilityLabel("Open in Rutube")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Cinema2026.amber.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 90)  // above the composer
    }
}
