// Plink/Playback/VKPlaybackController.swift — P0 VK Video sync
// Similar to RutubePlaybackController but for official VK embed.
// Embed: https://vk.com/video_ext.php?oid=OWNER&id=VIDEO&hash=...
// App Store compliant (no extraction).
// Sync is best-effort via JS bridge on the embed page.

import Foundation
import WebKit
import UIKit

public final class VKPlaybackController: PlaybackControlling {
    public private(set) var isReady = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var lastError: String?

    public var capabilities: PlaybackCapabilities {
        PlaybackCapabilities(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    public private(set) var embeddedView: UIView?
    private var webView: WKWebView?
    private var videoId: String?
    private var jsApiConfirmed = false
    private var pollTask: Task<Void, Never>?

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .vk(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        teardown()
        self.videoId = id
        isReady = true
        lastError = nil

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.audio]

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.translatesAutoresizingMaskIntoConstraints = false
        webView = web
        embeddedView = web

        // VK video_ext embed. id may be full query or "oid_id"
        let embedURL: URL
        if id.contains("http") {
            embedURL = URL(string: id)!
        } else if id.contains("oid=") || id.contains("video_ext") {
            embedURL = URL(string: id.hasPrefix("http") ? id : "https://vk.com/video_ext.php?\(id)")!
        } else {
            // assume oid_id or just use as-is
            embedURL = URL(string: "https://vk.com/video_ext.php?\(id)")!
        }
        web.load(URLRequest(url: embedURL))

        // Give page time to load
        try? await Task.sleep(for: .seconds(2))
        await probeJsApi()
        startPolling()
    }

    public func play() async {
        if isReady {
            await evaluate("window.plinkVKPlay && window.plinkVKPlay();")
        }
    }

    public func pause() {
        if isReady {
            Task { await evaluate("window.plinkVKPause && window.plinkVKPause();") }
        }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        if isReady {
            let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
            _ = await evaluate("window.plinkVKSeek && window.plinkVKSeek(\(target));")
            position = target
            return .applied
        }
        return .unavailable
    }

    public func setRate(_ rate: Float) {}

    public func teardown() {
        pollTask?.cancel()
        webView?.stopLoading()
        webView = nil
        embeddedView = nil
        isReady = false
        jsApiConfirmed = false
        position = 0
        duration = 0
    }

    public var requiresExternalFallback: Bool { false }

    public func openInExternalPlayer(from vc: UIViewController) {
        guard let id = videoId else { return }
        let url = URL(string: "https://vk.com/video\(id)") ?? URL(string: "https://vk.com")!
        UIApplication.shared.open(url)
    }

    // MARK: - Internals

    private func probeJsApi() async {
        let probe = """
        (function() {
            // VK embed often exposes player via postMessage or window globals.
            // Best effort injection.
            const p = window.player || window.VKPlayer || window.__vkPlayer;
            window.plinkVKPlay = function() { if (p && p.play) p.play(); else document.querySelector('video')?.play(); return true; };
            window.plinkVKPause = function() { if (p && p.pause) p.pause(); else document.querySelector('video')?.pause(); return true; };
            window.plinkVKSeek = function(s) {
                const v = document.querySelector('video');
                if (v) v.currentTime = s;
                if (p && p.setCurrentTime) p.setCurrentTime(s);
                return true;
            };
            window.plinkVKSnapshot = function() {
                const v = document.querySelector('video');
                return { time: v ? v.currentTime : 0, duration: v ? v.duration : 0 };
            };
            return true;
        })();
        """
        _ = await evaluate(probe)
        jsApiConfirmed = true
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snap = await self.evaluate("window.plinkVKSnapshot && window.plinkVKSnapshot();")
                if let dict = snap as? [String: Any] {
                    if let t = dict["time"] as? Double { self.position = t }
                    if let d = dict["duration"] as? Double, d > 0 { self.duration = d }
                }
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    @discardableResult
    private func evaluate(_ js: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }
}
