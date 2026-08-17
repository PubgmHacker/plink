// Plink/Playback/PlaybackSource.swift
// Source types (runbook §6)
//
// Distinguishes between:
//   - hls/mp4: native AVPlayer playback (preferred — full sync control)
//   - youtube: official embedded player (App Store compliant; limited
//     sync control via JS bridge)
//   - external: AirPlay/CarPlay/external route
//
// JWT/cookies are NEVER carried in URL query (runbook §2). Headers go
// through AVPlayer's AVURLAssetHTTPHeaderFieldsKey on the resource loader,
// or signed URL TTL (60–300s) for media URLs.

import Foundation

public enum PlaybackSource: Sendable, Equatable {
    /// HLS playlist URL. AVPlayer handles natively.
    case hls(URL, headers: [String: String])

    /// Progressive MP4 URL. AVPlayer handles natively.
    case mp4(URL, headers: [String: String])

    /// YouTube video ID — rendered via official embedded player (WKWebView
    /// with YouTube IFrame API). App Store compliant; NO extraction/relay.
    case youtube(String)

    /// PATCH 10: Rutube video ID — rendered via official Rutube embed
    /// (WKWebView with rutube.ru/play/embed/<id>). App Store compliant;
    /// NO extraction. Synchronized playback is unsupported when Rutube's
    /// JS API does not expose play/pause/seek — controller falls back to
    /// external provider (SFSafariViewController) in that case.
    case rutube(String)

    /// External playback route (AirPlay, CarPlay).
    case external(URL)

    /// P0: VK Video — vk.com/video_ext.php embed (WKWebView).
    case vk(String)

    /// P1: Generic web embed / cinema services.
    case embed(URL)

    /// Stable identifier for logging / metrics — never includes the URL
    /// (runbook §19: 'Не логировать finalURL.absoluteString, cookies, auth
    /// headers or extracted URLs').
    public var logTag: String {
        switch self {
        case .hls: return "hls"
        case .mp4: return "mp4"
        case .youtube: return "youtube"
        case .rutube: return "rutube"
        case .external: return "external"
        case .vk: return "vk"
        case .embed: return "embed"
        }
    }
}
