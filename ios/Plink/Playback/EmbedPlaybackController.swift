// Plink/Playback/EmbedPlaybackController.swift — P1 Cinema / Generic Web Embed
//
// Generic WKWebView-based controller for cinema services (Kinopoisk, Ivi, Okko, etc.)
// and other web pages that don't have a dedicated controller.
//
// Loads the watch page URL directly (user must be logged in on the service in Safari/WebView
// or the embed will prompt for subscription — App Store compliant).
//
// M13 upgrade — real sync for cinema services:
//   - Smart <video> discovery: shadow DOM + same-origin iframes + "main video"
//     ranking (longest duration, then largest on screen), cached per element.
//   - Snapshot now reports `found` + `rate`, so the app knows whether sync is
//     exact (hasBridgedVideo) or best-effort.
//   - Bridge auto-reinstalls after SPA route changes (page navigations reset
//     the injected globals — the poll loop detects this and re-injects).
//   - supportsRateCorrection = true: OrderedSyncController can now use the
//     M12 P-controller for smooth drift correction instead of hard seeks.
//   - fastSeek() used for imprecise seeks when the player supports it.

import Foundation
import WebKit
import UIKit
import Observation

@MainActor
@Observable
public final class EmbedPlaybackController: PlaybackControlling {
    public private(set) var isReady = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var lastError: String?

    /// True when the injected JS bridge found a real <video> element —
    /// i.e. cinema-service sync is exact, not best-effort.
    public private(set) var hasBridgedVideo = false

    public var capabilities: PlaybackCapabilities {
        PlaybackCapabilities(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: true,  // JS bridge drives video.playbackRate
            supportsDRM: false
        )
    }

    public private(set) var embeddedView: UIView?
    private var webView: WKWebView?
    private var sourceURL: URL?
    private var pollTask: Task<Void, Never>?
    /// Whether this session uses the generic <video> bridge (vs YouTube postMessage).
    private var usesEmbedBridge = false

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        let playerURL: URL

        switch source {
        case .embed(let url):
            // Cinema service URL — load directly
            playerURL = url

        case .youtube(let videoId):
            // YouTube — load backend-hosted player page (avoids error 153)
            let baseURL = PlinkConfig.baseURLString
            guard let url = URL(string: "\(baseURL)/api/media/youtube-player?id=\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        case .rutube(let videoId):
            // Rutube — load embed page
            guard let url = URL(string: "https://rutube.ru/play/embed/\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        case .vk(let videoId):
            // VK Video — load embed page
            guard let url = URL(string: "https://vk.com/video_ext.php?\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        default:
            throw ProviderError.unsupportedSource
        }

        teardown()
        self.sourceURL = playerURL
        isReady = false
        lastError = nil

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if let svc = VideoService.detect(fromURL: playerURL.absoluteString), svc.requiresAuth {
            config.websiteDataStore = CinemaSessionStore.persistent
        }

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false  // YouTube player doesn't need scroll
        web.translatesAutoresizingMaskIntoConstraints = false

        // Desktop UA for YouTube IFrame API compatibility
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        webView = web
        embeddedView = web

        web.load(URLRequest(url: playerURL))

        // Give the page a chance to render the player
        try? await Task.sleep(for: .seconds(2))

        // For YouTube: inject postMessage bridge for play/pause/seek
        if case .youtube = source {
            usesEmbedBridge = false
            await injectYouTubeBridge()
        } else {
            usesEmbedBridge = true
            await injectControlBridge()
        }
        isReady = true
        startPolling()
    }

    /// YouTube-specific control bridge via postMessage
    private func injectYouTubeBridge() async {
        guard let web = webView else { return }
        let bridge = """
        window.addEventListener('message', function(e) {
            try {
                var cmd = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                if (cmd.event === 'plink-yt') {
                    window.webkit.messageHandlers.plinkYT && window.webkit.messageHandlers.plinkYT.postMessage(cmd);
                }
            } catch(err) {}
        });
        // Also poll player state
        setInterval(function() {
            try {
                var iframe = document.querySelector('iframe');
                if (iframe && iframe.contentWindow) {
                    iframe.contentWindow.postMessage(JSON.stringify({event: 'listening', id: 'plink'}), '*');
                }
            } catch(err) {}
        }, 1000);
        """
        _ = try? await web.evaluateJavaScript(bridge)
    }

    public func play() async {
        guard isReady else { return }
        await evaluate(controlScript("play"))
    }

    public func pause() {
        guard isReady else { return }
        Task { await evaluate(controlScript("pause")) }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard isReady else { return .unavailable }
        let target = max(0, seconds)
        _ = await evaluate(controlScript("seek", arg: "\(target), \(precise)"))
        position = target
        return .applied
    }

    public func setRate(_ rate: Float) {
        guard isReady else { return }
        Task { await evaluate(controlScript("rate", arg: "\(rate)")) }
    }

    public func teardown() {
        pollTask?.cancel()
        webView?.stopLoading()
        webView = nil
        embeddedView = nil
        isReady = false
        hasBridgedVideo = false
        usesEmbedBridge = false
        position = 0
        duration = 0
    }

    // MARK: - Internals

    private func injectControlBridge() async {
        let bridge = """
        (function() {
            if (window.__plinkEmbedBridgeInstalled) return true;
            window.__plinkEmbedBridgeInstalled = true;

            // Find every candidate <video> — top document, open shadow
            // roots (custom players love hiding <video> there) and
            // same-origin iframes.
            function findAllVideos() {
                var vids = Array.prototype.slice.call(document.querySelectorAll('video'));
                try {
                    var all = document.querySelectorAll('*');
                    for (var i = 0; i < all.length; i++) {
                        if (all[i].shadowRoot) {
                            var inner = all[i].shadowRoot.querySelectorAll('video');
                            for (var j = 0; j < inner.length; j++) vids.push(inner[j]);
                        }
                    }
                } catch (e) {}
                try {
                    var frames = document.querySelectorAll('iframe');
                    for (var k = 0; k < frames.length; k++) {
                        try {
                            var doc = frames[k].contentDocument;
                            if (doc) {
                                var fv = doc.querySelectorAll('video');
                                for (var m = 0; m < fv.length; m++) vids.push(fv[m]);
                            }
                        } catch (e) {}
                    }
                } catch (e) {}
                return vids;
            }

            // Pick the MAIN video (longest duration, then largest box),
            // cache it until it leaves the DOM.
            function getVideo() {
                var cached = window.__plinkVideo;
                if (cached && cached.isConnected) return cached;
                var vids = findAllVideos();
                if (!vids.length) { window.__plinkVideo = null; return null; }
                vids.sort(function(a, b) {
                    var da = isFinite(a.duration) ? a.duration : 0;
                    var db = isFinite(b.duration) ? b.duration : 0;
                    if (db !== da) return db - da;
                    var ra = a.getBoundingClientRect();
                    var rb = b.getBoundingClientRect();
                    return (rb.width * rb.height) - (ra.width * ra.height);
                });
                window.__plinkVideo = vids[0];
                return window.__plinkVideo;
            }

            window.plinkEmbedPlay = function() {
                var v = getVideo();
                if (v) { v.play().catch(function(){}); return true; }
                return false;
            };

            window.plinkEmbedPause = function() {
                var v = getVideo();
                if (v) { v.pause(); return true; }
                return false;
            };

            window.plinkEmbedSeek = function(s, precise) {
                var v = getVideo();
                if (!v) return false;
                try {
                    if (!precise && typeof v.fastSeek === 'function') { v.fastSeek(s); return true; }
                } catch (e) {}
                v.currentTime = s;
                return true;
            };

            window.plinkEmbedRate = function(r) {
                var v = getVideo();
                if (v) { v.playbackRate = r; return true; }
                return false;
            };

            window.plinkEmbedSnapshot = function() {
                var v = getVideo();
                if (!v) return { found: false, time: 0, duration: 0, playing: false, rate: 1 };
                return {
                    found: true,
                    time: v.currentTime || 0,
                    duration: (isFinite(v.duration) && v.duration) || 0,
                    playing: !v.paused && !v.ended,
                    rate: v.playbackRate || 1
                };
            };

            // Try to auto-start muted if autoplay blocked (cinema sites often do this)
            setTimeout(function() {
                var v = getVideo();
                if (v && v.paused) {
                    v.muted = true;
                    v.play().catch(function(){});
                }
            }, 800);

            return true;
        })();
        """
        _ = await evaluate(bridge)
    }

    private func controlScript(_ action: String, arg: String = "") -> String {
        switch action {
        case "play":  return "window.plinkEmbedPlay && window.plinkEmbedPlay();"
        case "pause": return "window.plinkEmbedPause && window.plinkEmbedPause();"
        case "seek":  return "window.plinkEmbedSeek && window.plinkEmbedSeek(\(arg));"
        case "rate":  return "window.plinkEmbedRate && window.plinkEmbedRate(\(arg));"
        default:      return ""
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snap = await self.evaluate("window.plinkEmbedSnapshot && window.plinkEmbedSnapshot();") as? [String: Any] {
                    if let t = snap["time"] as? Double, t.isFinite { self.position = t }
                    if let d = snap["duration"] as? Double, d > 0 { self.duration = d }
                    if let p = snap["playing"] as? Bool { self.isPlaying = p }
                    if let f = snap["found"] as? Bool { self.hasBridgedVideo = f }
                } else if self.usesEmbedBridge {
                    // Page navigated (SPA route change) — injected globals
                    // are gone. Reinstall the bridge and keep polling.
                    self.hasBridgedVideo = false
                    await self.injectControlBridge()
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    @discardableResult
    private func evaluate(_ js: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }
}
