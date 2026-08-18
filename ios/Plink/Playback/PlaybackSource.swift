// Plink/Playback/PlaybackSource.swift
// Source types
//
// Distinguishes between:
//   - hls/mp4: native AVPlayer playback (preferred — full sync control)
//   - youtube: official embedded player (App Store compliant; limited
//     sync control via JS bridge)
//   - external: AirPlay/CarPlay/external route
//
// JWT/cookies are NEVER carried in URL query. Headers go
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

    /// Rutube video ID — rendered via official Rutube embed
    /// (WKWebView with rutube.ru/play/embed/<id>). App Store compliant;
    /// NO extraction. Synchronized playback is unsupported when Rutube's
    /// JS API does not expose play/pause/seek — controller falls back to
    /// external provider (SFSafariViewController) in that case.
    case rutube(String)

    /// External playback route (AirPlay, CarPlay).
    case external(URL)

    /// VK Video, as a vk.com/video_ext.php embed in a WKWebView.
    case vk(String)

    /// Generic web embed, used for the cinema services.
    case embed(URL)

    /// Stable identifier for logging / metrics — never includes the URL
    /// (: 'Не логировать finalURL.absoluteString, cookies, auth
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
