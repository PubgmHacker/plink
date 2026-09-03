// Plink/Playback/RutubePlaybackController.swift
//
// Official RuTube embed adapter. The player stays inside its own WKWebView;
// Plink never extracts a media URL or relays a CDN stream. The current embed
// exposes external events through window.postMessage: player:play,
// player:pause and player:setCurrentTime.

import Foundation
import UIKit
import WebKit
import Observation
import SafariServices

@MainActor
@Observable
public final class RutubePlaybackController: PlaybackControlling {
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    /// The web surface is ready once the official page has loaded. Sync control
    /// becomes available when the player sends a ready/snapshot event.
    public private(set) var isReady = false
    public private(set) var lastError: String?
    public private(set) var embeddedView: UIView?

    /// Called only for user-originated player changes. WatchRoomModel uses it
    /// to publish the host timeline to the other participants.
    public var onUserPlaybackChange: ((Bool, Double) -> Void)?

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: jsApiConfirmed,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    /// True when the provider page is visible but its external control bridge
    /// is not available. The room can still be opened externally instead of
    /// pretending synchronized controls work.
    public var requiresExternalFallback: Bool {
        isReady && !jsApiConfirmed
    }

    private var webView: WKWebView?
    private var videoId: String?
    private var pollTask: Task<Void, Never>?
    private var navigationDelegateBox: NavigationDelegate?
    private let messageHandler = MessageHandler()
    private var pageDidFinishLoad = false
    private var jsApiConfirmed = false
    private var suppressUserBroadcastDepth = 0
    private var lastBroadcastPlaying: Bool?
    private var lastBroadcastPosition: Double = 0

    public init() {}

    // MARK: - Prepare

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .rutube(let id) = source, Self.isValidVideoId(id) else {
            throw ProviderError.loadingFailed("Некорректная ссылка RuTube")
        }

        teardown()
        videoId = id
        pageDidFinishLoad = false
        jsApiConfirmed = false
        isReady = false
        lastError = nil

        let userContentController = WKUserContentController()
        userContentController.add(messageHandler, name: "plinkRutube")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.bridgeScript(videoId: id),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .default()

        let web = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 220),
            configuration: configuration
        )
        web.customUserAgent = Self.mobileSafariUserAgent
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.translatesAutoresizingMaskIntoConstraints = false

        messageHandler.onEvent = { [weak self] type, payload in
            Task { @MainActor in
                self?.handleEvent(type: type, payload: payload)
            }
        }

        let navigation = NavigationDelegate { [weak self] success, message in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.pageDidFinishLoad = true
                } else {
                    self.lastError = message ?? "Не удалось загрузить RuTube"
                }
            }
        }
        navigationDelegateBox = navigation
        web.navigationDelegate = navigation
        webView = web
        embeddedView = web

        guard let embedURL = URL(string: "https://rutube.ru/play/embed/\(id)/") else {
            throw ProviderError.loadingFailed("Некорректная ссылка RuTube")
        }
        web.load(URLRequest(url: embedURL))

        // Do not hold room connection hostage indefinitely. A loaded page is a
        // valid surface even when the provider's optional JS bridge is delayed;
        // polling promotes it to sync-capable when it becomes available.
        let deadline = Date().addingTimeInterval(10)
        while !pageDidFinishLoad, lastError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let lastError, !lastError.isEmpty {
            throw ProviderError.loadingFailed(lastError)
        }

        isReady = true
        startPolling()
    }

    // MARK: - PlaybackControlling

    public func play() async {
        guard isReady else { return }
        beginSuppressUserBroadcast()
        _ = await sendCommand(type: "player:play", data: ["videoId": videoId ?? ""])
        endSuppressUserBroadcast()
    }

    public func pause() {
        guard isReady else { return }
        beginSuppressUserBroadcast()
        Task { [weak self] in
            guard let self else { return }
            _ = await self.sendCommand(type: "player:pause", data: ["videoId": self.videoId ?? ""])
            self.endSuppressUserBroadcast()
        }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard isReady else { return .unavailable }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        beginSuppressUserBroadcast()
        let sent = await sendCommand(
            type: "player:setCurrentTime",
            data: ["videoId": videoId ?? "", "time": target]
        )
        endSuppressUserBroadcast()
        guard sent else { return .unavailable }
        position = target
        return .applied
    }

    public func setRate(_ rate: Float) {
        // RuTube's public external-events contract does not expose a reliable
        // playback-rate command. The sync controller uses seeks instead.
    }

    // MARK: - Teardown / external fallback

    public func teardown() {
        pollTask?.cancel()
        pollTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "plinkRutube")
        webView?.removeFromSuperview()
        webView = nil
        navigationDelegateBox = nil
        embeddedView = nil
        messageHandler.onEvent = nil
        videoId = nil
        pageDidFinishLoad = false
        jsApiConfirmed = false
        isReady = false
        isPlaying = false
        isBuffering = false
        position = 0
        duration = 0
        lastError = nil
        onUserPlaybackChange = nil
        suppressUserBroadcastDepth = 0
        lastBroadcastPlaying = nil
        lastBroadcastPosition = 0
    }

    public func openInExternalPlayer(from presentingVC: UIViewController) {
        guard let videoId, let url = URL(string: "https://rutube.ru/video/\(videoId)/") else { return }
        presentingVC.present(SFSafariViewController(url: url), animated: true)
    }

    // MARK: - Bridge

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.evaluate("window.__plinkRutubeSnapshot && window.__plinkRutubeSnapshot();")
                if let snapshot = snapshot as? [String: Any] {
                    self.applySnapshot(snapshot)
                }
                if !self.jsApiConfirmed {
                    let ready = await self.evaluate("window.__plinkRutubeBridgeReady === true;") as? Bool ?? false
                    if ready { self.jsApiConfirmed = true }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func applySnapshot(_ snapshot: [String: Any]) {
        if let found = snapshot["found"] as? Bool, found { jsApiConfirmed = true }
        if let time = Self.doubleValue(snapshot["time"]), time.isFinite { position = max(0, time) }
        if let length = Self.doubleValue(snapshot["duration"]), length.isFinite, length > 0 {
            duration = length
        }
        if let playing = snapshot["playing"] as? Bool {
            let changed = isPlaying != playing
            isPlaying = playing
            if changed { emitUserPlaybackChangeIfNeeded(playing: playing, position: position) }
        }
    }

    private func handleEvent(type: String, payload: [String: Any]) {
        switch type {
        case "player:ready", "player:canPlay", "frame:loaded":
            jsApiConfirmed = true
            isReady = true
        case "player:playStart", "player:play":
            jsApiConfirmed = true
            isPlaying = true
            emitUserPlaybackChangeIfNeeded(playing: true, position: position)
        case "player:pause", "player:playComplete":
            jsApiConfirmed = true
            isPlaying = false
            emitUserPlaybackChangeIfNeeded(playing: false, position: position)
        case "player:buffering":
            isBuffering = (payload["buffering"] as? Bool) ?? true
        case "player:currentTime":
            if let time = Self.doubleValue(payload["time"] ?? payload["currentTime"]), time.isFinite {
                position = max(0, time)
            }
        case "player:durationChange":
            if let length = Self.doubleValue(payload["duration"]), length > 0 { duration = length }
        case "player:error", "player:errorInfo":
            lastError = "RuTube не смог загрузить это видео"
            isBuffering = false
            isPlaying = false
        case "snapshot":
            applySnapshot(payload)
        default:
            break
        }
    }

    private func sendCommand(type: String, data: [String: Any]) async -> Bool {
        guard let encoded = try? JSONSerialization.data(withJSONObject: ["type": type, "data": data]),
              let message = String(data: encoded, encoding: .utf8) else { return false }
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return await evaluate("window.postMessage('\(escaped)', '*'); true;") != nil
    }

    @discardableResult
    private func evaluate(_ script: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(script)
    }

    private func beginSuppressUserBroadcast() { suppressUserBroadcastDepth += 1 }

    private func endSuppressUserBroadcast() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            self.suppressUserBroadcastDepth = max(0, self.suppressUserBroadcastDepth - 1)
        }
    }

    private func emitUserPlaybackChangeIfNeeded(playing: Bool, position: Double) {
        guard suppressUserBroadcastDepth == 0 else { return }
        let changed = lastBroadcastPlaying.map { $0 != playing } ?? true
        let jumped = abs(position - lastBroadcastPosition) > 1.25
        guard changed || jumped else { return }
        lastBroadcastPlaying = playing
        lastBroadcastPosition = position
        onUserPlaybackChange?(playing, position)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return value as? Double
    }

    private static func isValidVideoId(_ id: String) -> Bool {
        guard id.count >= 8, id.count <= 64 else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static let mobileSafariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 " +
        "Mobile/15E148 Safari/604.1"

    /// The embed's external-events bus serializes messages as
    /// `{ type: "player:…", data: {...} }` and posts them to its parent. The
    /// listener also watches the DOM video as a compatibility fallback for
    /// revisions that delay or omit the external event.
    private static func bridgeScript(videoId: String) -> String {
        """
        (function() {
          if (window.__plinkRutubeBridgeInstalled) return;
          window.__plinkRutubeBridgeInstalled = true;
          window.__plinkRutubeBridgeReady = false;
          var expectedId = '\(videoId)';

          function send(type, data) {
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.plinkRutube) {
                window.webkit.messageHandlers.plinkRutube.postMessage({ type: type, data: data || {} });
              }
            } catch (e) {}
          }

          function parseMessage(value) {
            if (typeof value !== 'string') return null;
            try { return JSON.parse(value); } catch (e) { return null; }
          }

          window.addEventListener('message', function(event) {
            var message = parseMessage(event.data);
            if (!message || typeof message.type !== 'string') return;
            if (message.type.indexOf('player:') === 0 || message.type === 'frame:loaded') {
              window.__plinkRutubeBridgeReady = true;
              send(message.type, message.data || {});
            }
          }, true);

          function video() {
            var candidates = document.querySelectorAll('video');
            if (!candidates.length) return null;
            var best = candidates[0];
            for (var i = 1; i < candidates.length; i++) {
              if ((candidates[i].clientWidth * candidates[i].clientHeight) >
                  (best.clientWidth * best.clientHeight)) best = candidates[i];
            }
            return best;
          }

          window.__plinkRutubeSnapshot = function() {
            var v = video();
            if (!v) return { found: false, time: 0, duration: 0, playing: false };
            window.__plinkRutubeBridgeReady = true;
            return {
              found: true,
              time: isFinite(v.currentTime) ? v.currentTime : 0,
              duration: isFinite(v.duration) ? v.duration : 0,
              playing: !v.paused && !v.ended
            };
          };

          window.__plinkRutubePlay = function() {
            var v = video();
            if (v) { v.play().catch(function(){}); return true; }
            window.postMessage(JSON.stringify({type:'player:play', data:{videoId:expectedId}}), '*');
            return true;
          };
          window.__plinkRutubePause = function() {
            var v = video();
            if (v) { v.pause(); return true; }
            window.postMessage(JSON.stringify({type:'player:pause', data:{videoId:expectedId}}), '*');
            return true;
          };
          window.__plinkRutubeSeek = function(seconds) {
            var v = video();
            if (v) { v.currentTime = Math.max(0, Number(seconds) || 0); return true; }
            window.postMessage(JSON.stringify({type:'player:setCurrentTime', data:{videoId:expectedId,time:Number(seconds)||0}}), '*');
            return true;
          };

          setInterval(function() {
            var snapshot = window.__plinkRutubeSnapshot();
            if (snapshot.found) send('snapshot', snapshot);
          }, 500);
        })();
        """
    }

    // MARK: - WK delegates

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private let onFinish: (Bool, String?) -> Void

        init(onFinish: @escaping (Bool, String?) -> Void) { self.onFinish = onFinish }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish(true, nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFinish(false, error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            if (error as NSError).code != NSURLErrorCancelled {
                onFinish(false, error.localizedDescription)
            }
        }
    }

    private final class MessageHandler: NSObject, WKScriptMessageHandler {
        var onEvent: ((String, [String: Any]) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            onEvent?(type, body["data"] as? [String: Any] ?? [:])
        }
    }
}
