// Plink/Playback/PlayerViewControllerRepresentable.swift
// SwiftUI bridge (runbook §6 + Brain Review P0-8)
//
// Brain P0-8 fix: supports BOTH paths:
//   - Native HLS/MP4 → AVPlayerViewController (PiP + AirPlay)
//   - Embedded YouTube → WKWebView from EmbeddedPlaybackController
//
// The underlying AVPlayer instance is owned by PlaybackCoordinator —
// this view does NOT create its own player (§1 DoD: 'Background/foreground,
// rotation и fullscreen не создают второй player').

import SwiftUI
import AVKit

public struct PlayerSurfaceView: View {
    public let coordinator: PlaybackCoordinator
    /// Optional room-level error (e.g. mediaSource missing) — coordinator may still be idle.
    public var roomError: String? = nil
    /// When true, show loading instead of "Нет видео" during connect bootstrap.
    public var expectMedia: Bool = true

    public init(coordinator: PlaybackCoordinator, roomError: String? = nil, expectMedia: Bool = true) {
        self.coordinator = coordinator
        self.roomError = roomError
        self.expectMedia = expectMedia
    }

    public var body: some View {
        // Observe surfaceEpoch so WKWebView appears as soon as prepare attaches it
        let _ = coordinator.surfaceEpoch
        let _ = coordinator.isPreparing
        let _ = coordinator.lastError
        let error = activeError

        ZStack {
            if let vc = coordinator.makePlayerViewController() {
                PlayerViewControllerRepresentable(controller: vc)
            } else if let embedded = coordinator.embeddedView {
                // Stable identity — do NOT use .id(surfaceEpoch) or SwiftUI will
                // tear down / re-create the UIViewRepresentable and kill YT load.
                EmbeddedViewRepresentable(view: embedded)
                    .overlay {
                        if let error {
                            mediaErrorView(error)
                        }
                    }
            } else if let error {
                // Media prepare failed — show error (chat still works).
                mediaErrorView(error)
            } else if coordinator.isPreparing || (expectMedia && coordinator.currentSource == nil && coordinator.currentController == nil) {
                // Avoid flash "Нет видео" while connect() is still resolving YouTube
                Color.black
                    .overlay(
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Загрузка видео…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    )
            } else {
                Color.black
                    .overlay(
                        Text("Нет видео")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
        .background(Color.black)
    }

    private var activeError: String? {
        coordinator.lastError
            ?? (coordinator.currentController as? EmbeddedPlaybackController)?.lastError
            ?? (coordinator.currentController as? RutubePlaybackController)?.lastError
            ?? (coordinator.currentController as? VKPlaybackController)?.lastError
            ?? (coordinator.currentController as? EmbedPlaybackController)?.lastError
            ?? roomError
    }

    private func mediaErrorView(_ error: String) -> some View {
        Color.black
            .overlay(
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                    Text("Не удалось загрузить видео")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Чат и участники работают")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            )
    }
}

public struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    public let controller: AVPlayerViewController

    public init(controller: AVPlayerViewController) {
        self.controller = controller
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        controller
    }

    public func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Keep AVPlayer reference in sync if coordinator rebuilt it
        if vc.player !== coordinator_player(vc) {
            // vc.player is set by the coordinator when it created the VC.
            // Nothing to do here — coordinator owns the AVPlayer.
        }
    }

    private func coordinator_player(_ vc: AVPlayerViewController) -> AVPlayer? {
        vc.player
    }
}

/// Wraps a UIView (WKWebView for embedded YouTube) for SwiftUI.
/// Uses a container so Auto Layout always gives the webview a non-zero frame
/// (zero-size WKWebView often never finishes YouTube IFrame load).
public struct EmbeddedViewRepresentable: UIViewRepresentable {
    public let view: UIView

    public init(view: UIView) {
        self.view = view
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        install(view, in: container)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if view.superview !== uiView {
            // Only re-parent if needed — never strip a live WKWebView mid-load
            // when it's already correctly installed.
            if view.superview != nil {
                view.removeFromSuperview()
            }
            uiView.subviews.forEach { sub in
                if sub !== view { sub.removeFromSuperview() }
            }
            install(view, in: uiView)
        }
        // Keep frame in sync with container (constraints also active)
        if uiView.bounds.width > 0, uiView.bounds.height > 0 {
            view.frame = uiView.bounds
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func install(_ child: UIView, in parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}
