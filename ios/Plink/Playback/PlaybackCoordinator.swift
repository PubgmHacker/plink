// Plink/Playback/PlaybackCoordinator.swift
// Single owner of player lifecycle
//
// The coordinator chooses between NativePlayerController
// (for .hls/.mp4/.external) and EmbeddedPlaybackController (for .youtube).
// The two controllers implement the same PlaybackControlling protocol, so
// OrderedSyncController is agnostic to which one is active.
//
// Per: 'PlaybackController не отправляет WebSocket сообщения' —
// the coordinator never talks to RealtimeClient.
//
// Per: 'Не добавлять еще один singleton WebView' — the coordinator is
// owned by WatchRoomModel, never a global. Each room session gets a fresh
// coordinator with a fresh player.

import Foundation
import AVKit
import UIKit
import Observation

@MainActor
@Observable
public final class PlaybackCoordinator: AnyObject {
    /// Current active controller — either NativePlayerController or
    /// EmbeddedPlaybackController depending on source type.
    public private(set) var currentController: PlaybackControlling?

    public var position: TimeInterval { currentController?.position ?? 0 }
    public var duration: TimeInterval { currentController?.duration ?? 0 }
    public var isPlaying: Bool { currentController?.isPlaying ?? false }
    public var isBuffering: Bool { currentController?.isBuffering ?? false }
    public var capabilities: PlaybackCapabilities {
        currentController?.capabilities ?? .unknown
    }

    public private(set) var currentSource: PlaybackSource?
    public private(set) var isPreparing: Bool = false
    public private(set) var lastError: String?
    /// Bumped whenever embedded WKWebView is attached so SwiftUI re-reads `embeddedView`.
    /// Keep bumps minimal — `.id(surfaceEpoch)` style identity changes kill WKWebView loads.
    public private(set) var surfaceEpoch: Int = 0
    private var cachedPlayerViewController: AVPlayerViewController?

    /// Native AVPlayer (nil for embedded YouTube source).
    public var nativePlayer: AVPlayer? {
        (currentController as? NativePlayerController)?.player
    }

    /// Embedded view (nil for native HLS/MP4 source).
    /// Returns the embedded view for YouTube OR Rutube controllers.
    public var embeddedView: UIView? {
        // Touch surfaceEpoch so Observation tracks UI attach of WKWebView
        _ = surfaceEpoch
        if let youtube = currentController as? EmbeddedPlaybackController {
            return youtube.embeddedView
        }
        if let rutube = currentController as? RutubePlaybackController {
            return rutube.embeddedView
        }
        if let vk = currentController as? VKPlaybackController {
            return vk.embeddedView
        }
        if let embed = currentController as? EmbedPlaybackController {
            return embed.embeddedView
        }
        return nil
    }

    public init() {}

    public func noteSurfaceChanged() {
        surfaceEpoch &+= 1
    }

    // Prepare now throws — caller can catch and decide not to connect
    public func prepare(_ source: PlaybackSource) async throws {
        isPreparing = true
        lastError = nil
        // Teardown any previous controller
        if let prev = currentController {
            if let native = prev as? NativePlayerController { native.teardown() }
            if let embedded = prev as? EmbeddedPlaybackController { embedded.teardown() }
            if let rutube = prev as? RutubePlaybackController { rutube.teardown() }
            if let vk = prev as? VKPlaybackController { vk.teardown() }
            if let embed = prev as? EmbedPlaybackController { embed.teardown() }
        }
        cachedPlayerViewController = nil
        currentController = nil
        surfaceEpoch &+= 1

        do {
            let controller: PlaybackControlling
            switch source {
            case .hls, .mp4, .external:
                let native = NativePlayerController()
                try await native.prepare(source)
                controller = native
                currentController = controller
            case .youtube:
                // Attach controller BEFORE prepare so WKWebView is in the view
                // hierarchy while the YouTube page loads (off-screen WKWebView
                // often never fires onReady → eternal spinner).
                let embedded = EmbeddedPlaybackController()
                // Only bump once when the webview actually appears (not on every
                // intermediate callback — recreating UIViewRepresentable kills load).
                let surfaceGate = SurfaceNotifyGate()
                embedded.onSurfaceChanged = { [weak self] in
                    guard let self else { return }
                    let hasView = (self.currentController as? EmbeddedPlaybackController)?.embeddedView != nil
                    if surfaceGate.shouldNotify(hasView: hasView) {
                        self.noteSurfaceChanged()
                    }
                }
                currentController = embedded
                surfaceEpoch &+= 1
                try await embedded.prepare(source)
                controller = embedded
            case .rutube:
                let rutube = RutubePlaybackController()
                currentController = rutube
                surfaceEpoch &+= 1
                try await rutube.prepare(source)
                controller = rutube
            case .vk:
                let vk = VKPlaybackController()
                try await vk.prepare(source)
                controller = vk
                currentController = controller
            case .embed(let url):
                let s = url.absoluteString.lowercased()
                if s.contains(".m3u8") || s.contains(".mp4") || s.hasSuffix(".mov") {
                    let native = NativePlayerController()
                    try await native.prepare(s.contains(".m3u8") ? .hls(url, headers: [:]) : .mp4(url, headers: [:]))
                    controller = native
                    currentController = controller
                } else {
                    let embed = EmbedPlaybackController()
                    currentController = embed
                    surfaceEpoch &+= 1
                    try await embed.prepare(source)
                    controller = embed
                }
            }
            currentController = controller
            currentSource = source
            // Surface already live for embedded controllers; avoid extra epoch
            // bumps that would rebuild EmbeddedViewRepresentable mid-load.
            switch source {
            case .youtube, .rutube, .embed:
                break
            default:
                surfaceEpoch &+= 1
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isPreparing = false
            surfaceEpoch &+= 1
            throw error
        }
        isPreparing = false
    }

    public func teardown() {
        if let native = currentController as? NativePlayerController { native.teardown() }
        if let embedded = currentController as? EmbeddedPlaybackController { embedded.teardown() }
        if let rutube = currentController as? RutubePlaybackController { rutube.teardown() }
        if let vk = currentController as? VKPlaybackController { vk.teardown() }
        if let embed = currentController as? EmbedPlaybackController { embed.teardown() }
        cachedPlayerViewController = nil
        currentController = nil
        currentSource = nil
        lastError = nil
        surfaceEpoch &+= 1
    }

    /// Returns the AVPlayerViewController for PiP / fullscreen presentation.
    /// Returns nil for embedded YouTube source (no AVPlayer).
    public func makePlayerViewController() -> AVPlayerViewController? {
        guard let native = currentController as? NativePlayerController else { return nil }
        let vc = cachedPlayerViewController ?? AVPlayerViewController()
        if vc.player !== native.player {
            vc.player = native.player
        }
        vc.allowsPictureInPicturePlayback = true
        // PiP стартует сам при сворачивании приложения
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.allowsVideoFrameAnalysis = false
        cachedPlayerViewController = vc
        return vc
    }
}

/// Coalesces surfaceEpoch bumps so attach notifies once, teardown once.
@MainActor
private final class SurfaceNotifyGate {
    private var attached = false

    func shouldNotify(hasView: Bool) -> Bool {
        if hasView {
            guard !attached else { return false }
            attached = true
            return true
        } else {
            guard attached else { return false }
            attached = false
            return true
        }
    }
}
