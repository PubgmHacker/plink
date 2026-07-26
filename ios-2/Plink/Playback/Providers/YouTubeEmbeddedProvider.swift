// Plink/Playback/Providers/YouTubeEmbeddedProvider.swift
// App Store compliant YouTube provider (runbook §7 + Brain Review P0-8)
//
// Brain P0-8 fix: this provider is now ONLY a view container. All playback
// control (play/pause/seek/position/duration/isPlaying/isBuffering) is
// handled by EmbeddedPlaybackController, which implements PlaybackControlling
// directly via the YouTube IFrame JS bridge.
//
// The ProviderAdapter protocol is kept for HLS/MP4 providers
// (NativeHLSProvider) that produce AVPlayerItem. For YouTube, the
// PlaybackCoordinator should instantiate EmbeddedPlaybackController
// instead of going through NativePlayerController + ProviderAdapter.
//
// App Store compliance (runbook §7):
//   - Official YouTube IFrame API inside WKWebView
//   - NO server-side extraction (no Innertube, no yt-dlp, no Piped)
//   - NO cookie relay — cookies never leave the device
//   - NO raw CDN proxy
//   - YouTube controls + branding visible (ToS)

import Foundation
import AVFoundation
import UIKit
import WebKit

@MainActor
public final class YouTubeEmbeddedProvider: ProviderAdapter {
    public var playerItem: AVPlayerItem? { nil }
    public private(set) var embeddedView: UIView?

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    private var webView: WKWebView?

    public init() {}

    /// Prepare is a no-op for YouTube — the WebView is owned and managed by
    /// EmbeddedPlaybackController, not by this provider. This method exists
    /// only for ProviderAdapter protocol conformance and throws
    /// unsupportedSource so callers route to EmbeddedPlaybackController.
    public func prepare(source: PlaybackSource) async throws {
        throw ProviderError.unsupportedSource
    }

    public func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        embeddedView = nil
    }
}
