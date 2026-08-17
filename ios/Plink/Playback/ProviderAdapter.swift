// Plink/Playback/ProviderAdapter.swift
// Provider abstraction (runbook §6)
//
// A ProviderAdapter knows how to:
//   1. Take a PlaybackSource and turn it into something AVPlayer (or the
//      embedded YouTube player) can render.
//   2. Report capability flags for that source.
//   3. Optionally provide an AVPlayerItem or a UIView for embedded rendering.
//
// Implementations:
//   - NativeHLSProvider:  .hls / .mp4 → AVPlayerItem with custom headers
//   - YouTubeEmbeddedProvider: .youtube → WKWebView with IFrame API
//     (App Store compliant flow ONLY — no extraction, no cookie relay,
//      no raw CDN proxy — runbook §7)
//
// Per §21: 'PlaybackController не отправляет WebSocket сообщения' —
// provider adapters never talk to RealtimeClient.

import Foundation
import AVFoundation
import UIKit

// UIKit needed for UIView (embeddedView in ProviderAdapter protocol)

@MainActor
public protocol ProviderAdapter: AnyObject {
    var capabilities: PlaybackCapabilities { get }
    var playerItem: AVPlayerItem? { get }
    var embeddedView: UIView? { get }

    func prepare(source: PlaybackSource) async throws
    func teardown()
}

/// Empty extension so the protocol can be found via Plink/Playback/Providers/
/// namespace if we add a registry later.
public extension ProviderAdapter {
    var supportsEmbeddedRendering: Bool { embeddedView != nil }
}
