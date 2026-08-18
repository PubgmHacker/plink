//
// The single official YouTube embedded controller for the room session.
// Owns one WKWebView per room (: 'Не добавлять еще один
// singleton WebView' — coordinator is per-room, never global).
//
// Ownership split and hard constraints:
//   - YouTube owns play/pause/timeline/captions/quality (official controls visible).
//   - Plink owns room close/sync/participants/chat/reactions/replace-video only.
//   - NO loadHTMLString — navigate WKWebView to backend /api/media/youtube-player
//     so the page has a real HTTPS origin (fixes error 153).
//   - NO duplicate Plink transport UI on YouTube content (PlayerControlLayer
//     only renders for .plink chrome ownership).
//   - NO invented error 152 — official mapping only: 2/5/100/101/150/153.
//
// JS bridge contract (YouTube IFrame API):
//   - 'ready' → isReady = true, drain pending commands.
//   - 'state' (1/2/3/0) → isPlaying, isBuffering.
//   - 'error' (2/5/100/101/150/153) → lastError set, isBuffering cleared.
//   - poll task: plinkSnapshot() every 250ms (visible) / 1s (background).
//
// App Store compliance:
//   - Official YouTube IFrame API served from Plink backend (real HTTPS origin).
//   - NO server-side extraction (no Innertube, no yt-dlp, no Piped).
//   - NO cookie relay — cookies never leave the device.
//   - NO raw CDN proxy.
//   - YouTube controls VISIBLE (controls=1) — Plink does NOT duplicate them.

import Foundation
import UIKit
import WebKit
import Observation

/// Determines who owns transport UI.
/// `.provider` (YouTube) → hide Plink's PlayerControlLayer.
/// `.plink` (native HLS/MP4) → render PlayerControlLayer.
public enum PlayerChromeOwnership: Sendable {
    case provider
    case plink
}

@MainActor
@Observable
public final class EmbeddedPlaybackController: PlaybackControlling {
    // MARK: - Public state (UI binds to these)

    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false

    /// ready state — UI uses this to show "Loading…" vs "Buffering…".
    public private(set) var isReady: Bool = false

    /// surface YouTube error callback for UI binding.
    public private(set) var lastError: String?

    /// Контролы рисует Plink (`controls=0` в обёртке плеера).
    /// Раньше здесь было `.provider` — панель YouTube поверх видео.
    /// Переключается вместе с параметром `chrome` в URL обёртки: если
    /// вернуть `.provider`, надо вернуть и `chrome=youtube`, иначе видео
    /// останется вообще без органов управления.
    public var chromeOwnership: PlayerChromeOwnership { .plink }

    // MARK: - Состояние для своей панели управления

    /// Доля загруженного (0…1) — рисуется вторым слоем на полосе перемотки.
    public private(set) var buffered: Double = 0
    /// Текущая скорость воспроизведения.
    public private(set) var playbackRate: Float = 1
    public private(set) var isMuted: Bool = false
    /// Доступные уровни качества от YouTube (hd1080, hd720, large…).
    public private(set) var availableQualities: [String] = []
    public private(set) var currentQuality: String = ""

    /// Fired when the *user* (or YouTube chrome) changes play/pause/seek —
    /// not when Plink programmatically applies remote sync commands.
    /// Host WatchRoomModel uses this to emit `sync.command`.
    public var onUserPlaybackChange: ((Bool, Double) -> Void)?

    /// Called when WKWebView is created so coordinator can bump surfaceEpoch
    /// and SwiftUI attaches the view *before* YouTube finishes loading.
    public var onSurfaceChanged: (() -> Void)?

    /// Suppress host broadcast while applying remote sync or host Plink commands.
    private var suppressUserBroadcastDepth: Int = 0
    private var lastBroadcastPlaying: Bool?
    private var lastBroadcastPosition: Double = 0
    private var navigationDelegateBox: YTWebNavigationDelegate?
    private var pageDidFinishLoad: Bool = false

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    // MARK: - Embedded view

    public private(set) var embeddedView: UIView?

    // MARK: - Private state

    /// M29-YT: buffering watchdog — counts consecutive 250ms poll ticks
    /// spent in state 3 (buffering). After 32 ticks (8 s) we do a recovery
    /// seek to current position, which almost always unsticks YouTube.
    private var bufferingTicks: Int = 0
    private static let bufferingRecoveryTicks = 32   // 8 s at 250 ms poll

    private var webView: WKWebView?
    private var videoId: String?

    /// Pending enum consolidates pending seek + play state.
    /// Drained atomically when isReady becomes true.
    private var pending: Pending = .none
    private enum Pending {
        case none
        case state(position: Double?, playing: Bool?)

        func merging(position: Double?, playing: Bool?) -> Pending {
            switch self {
            case .none:
                if position == nil && playing == nil {
                    return .none
                }
                return .state(position: position, playing: playing)
            case .state(let existingPos, let existingPlaying):
                let mergedPos = position ?? existingPos
                let mergedPlaying = playing ?? existingPlaying
                return .state(position: mergedPos, playing: mergedPlaying)
            }
        }
    }

    private var pollTask: Task<Void, Never>?
    private let bridge = EmbeddedMessageHandler()

    /// Backend HTTPS wrapper URL.
    /// Set via prepare(_:) — the wrapper page lives at /api/media/youtube-player.
    private static let backendBaseURL = URL(string: PlinkConfig.baseURLString)!

    public init() {}

    // MARK: - Prepare

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        guard Self.isValidVideoId(id) else {
            throw ProviderError.loadingFailed("Invalid YouTube video ID")
        }

        teardown()
        self.videoId = id
        isReady = false
        lastError = nil
        isBuffering = true
        pageDidFinishLoad = false

        // WKWebView configuration
        let content = WKUserContentController()
        // Avoid duplicate handler crash if reused
        content.removeScriptMessageHandler(forName: "plinkPlayer")
        content.add(bridge, name: "plinkPlayer")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // картинка-в-картинке для встроенного плеера
        config.allowsPictureInPictureMediaPlayback = true
        // Allow autoplay without user gesture (wrapper mutes then unmutes)
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = content
        config.websiteDataStore = .default()
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        // Non-zero frame helps first layout pass before Auto Layout
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 220), configuration: config)
        web.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x0E/255, green: 0x10/255, blue: 0x16/255, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.translatesAutoresizingMaskIntoConstraints = true
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let nav = YTWebNavigationDelegate { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.pageDidFinishLoad = true
                } else {
                    self.lastError = err ?? "Не удалось загрузить страницу плеера"
                    self.isBuffering = false
                }
            }
        }
        navigationDelegateBox = nav
        web.navigationDelegate = nav

        webView = web
        embeddedView = web
        // One surface notify — enough for SwiftUI to attach. Do NOT spam
        // surfaceEpoch (recreates UIViewRepresentable and kills the load).
        onSurfaceChanged?()

        // Wire bridge callbacks
        bridge.onReady = { [weak self] in
            Task { @MainActor in self?.handleReady() }
        }
        bridge.onStateChange = { [weak self] state in
            Task { @MainActor in self?.handleStateChange(state) }
        }
        bridge.onError = { [weak self] code in
            Task { @MainActor in self?.handleError(code: code) }
        }

        // Backend HTTPS wrapper (real origin for YouTube IFrame API)
        var components = URLComponents(url: Self.backendBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/media/youtube-player"
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            // Обёртка отдаёт плеер без родных контролов — панель рисует Plink.
            // Значение должно соответствовать `chromeOwnership` выше.
            URLQueryItem(name: "chrome", value: "plink"),
            // Cache-bust so wrapper HTML updates (bridge fixes) land immediately
            URLQueryItem(name: "v", value: "40")
        ]
        guard let wrapperURL = components.url else {
            throw ProviderError.loadingFailed("Invalid wrapper URL")
        }

        // Wait until SwiftUI pins WKWebView into the hierarchy.
        // Off-screen / zero-size WKWebView often never fires YT onReady.
        for _ in 0..<40 {
            if web.superview != nil || web.window != nil { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(40))
        }
        // One extra layout pass after attach
        web.setNeedsLayout()
        web.layoutIfNeeded()
        await Task.yield()

        var req = URLRequest(url: wrapperURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        web.load(req)

        // Soft-wait for ready so callers are not blocked forever.
        // IMPORTANT: do NOT throw on timeout — keep WKWebView visible so YouTube
        // can finish loading / show its own UI. Throwing discarded the webview
        // and left a permanent spinner.
        let started = Date()
        let deadline = started.addingTimeInterval(10)
        while !isReady && Date() < deadline {
            if lastError != nil { break }

            let jsReady = await evaluate(
                "(function(){try{return !!(window.__plinkIsReady&&window.__plinkIsReady());}catch(e){return false;}})()"
            )
            if let flag = jsReady as? Bool, flag {
                handleReady()
                break
            }

            // Soft-ready: page finished + YT API present after a few seconds
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 3.5 {
                let ytExists = await evaluate(
                    "(function(){try{return !!(window.YT&&window.YT.Player);}catch(e){return false;}})()"
                )
                if let yt = ytExists as? Bool, yt {
                    // Player API present — surface is playable even if bridge lagged
                    handleReady()
                    break
                }
            }
            // Soft-ready: page loaded and iframe exists (YT controls visible)
            if pageDidFinishLoad, elapsed > 5 {
                let hasIframe = await evaluate(
                    "(function(){try{return !!document.querySelector('iframe');}catch(e){return false;}})()"
                )
                if let has = hasIframe as? Bool, has {
                    handleReady()
                    break
                }
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        if !isReady {
            // Keep webview visible; stop covering it with a full-screen spinner.
            // YouTube chrome may still become interactive.
            isBuffering = false
            lastError = nil
        }

        startPolling()
    }

    // MARK: - PlaybackControlling

    public func play() async {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
        guard isReady else {
            pending = pending.merging(position: nil, playing: true)
            return
        }
        await evaluate("window.plinkPlay && window.plinkPlay();")
    }

    public func pause() {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
        guard isReady else {
            pending = pending.merging(position: nil, playing: false)
            return
        }
        Task { await evaluate("window.plinkPause && window.plinkPause();") }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        guard isReady else {
            pending = pending.merging(position: target, playing: nil)
            return .unavailable
        }
        // plinkSeek returns true on success, undefined if not loaded.
        let result = await evaluate("window.plinkSeek && window.plinkSeek(\(target));")
        guard result != nil else { return .unavailable }
        position = target
        return .applied
    }

    private func beginSuppressUserBroadcast() {
        suppressUserBroadcastDepth += 1
    }

    private func endSuppressUserBroadcast() {
        // Keep suppress briefly so IFrame state callbacks from our own JS don't re-broadcast.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            suppressUserBroadcastDepth = max(0, suppressUserBroadcastDepth - 1)
        }
    }

    private func emitUserPlaybackChangeIfNeeded(playing: Bool, position pos: Double, force: Bool = false) {
        guard suppressUserBroadcastDepth == 0 else { return }
        let playingChanged = lastBroadcastPlaying.map { $0 != playing } ?? true
        let seekJump = abs(pos - lastBroadcastPosition) > 1.25
        guard force || playingChanged || seekJump else { return }
        lastBroadcastPlaying = playing
        lastBroadcastPosition = pos
        onUserPlaybackChange?(playing, pos)
    }

    public func setRate(_ rate: Float) {
        // Скорость нужна своей панели управления. Для синхронизации она
        // по-прежнему не используется — `capabilities.supportsRateCorrection`
        // остаётся false, и OrderedSyncController правит рассинхрон точным seek.
        let clamped = max(0.25, min(2.0, rate))
        playbackRate = clamped
        Task { await evaluate("window.plinkSetRate && window.plinkSetRate(\(clamped));") }
    }

    /// Запрос качества. YouTube трактует его как пожелание, поэтому
    /// фактическое значение всегда перечитывается из snapshot().
    public func setQuality(_ quality: String) {
        let safe = quality.filter { $0.isLetter || $0.isNumber }
        guard !safe.isEmpty else { return }
        Task { await evaluate("window.plinkSetQuality && window.plinkSetQuality('\(safe)');") }
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        Task { await evaluate("window.plinkSetMuted && window.plinkSetMuted(\(muted));") }
    }

    public func setVolume(_ volume: Double) {
        let clamped = max(0, min(100, volume))
        Task { await evaluate("window.plinkSetVolume && window.plinkSetVolume(\(clamped));") }
    }

    // MARK: - Teardown

    public func teardown() {
        pollTask?.cancel()
        pollTask = nil

        webView?.navigationDelegate = nil
        navigationDelegateBox = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "plinkPlayer")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        embeddedView = nil
        onSurfaceChanged?()

        bridge.onReady = nil
        bridge.onStateChange = nil
        bridge.onError = nil

        videoId = nil
        isReady = false
        isPlaying = false
        isBuffering = false
        position = 0
        duration = 0
        pending = .none
        lastError = nil
        pageDidFinishLoad = false
        bufferingTicks = 0
    }

    // MARK: - Bridge handlers

    private func handleReady() {
        guard !isReady else { return }
        isReady = true
        isBuffering = false

        // Drain pending commands atomically.
        let command = pending
        pending = .none

        Task {
            if case .state(let p, let playing) = command {
                if let p { _ = await seek(to: p, precise: true) }
                if playing == true { await play() }
                if playing == false { pause() }
            }
        }

        // Fetch duration (fire-and-forget — position poll will keep it fresh).
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.evaluate("window.plinkSnapshot && window.plinkSnapshot();")
            if let dict = snapshot as? [String: Any] {
                if let d = dict["duration"] as? Double, d > 0 {
                    self.duration = d
                }
            }
        }
    }

    private func handleStateChange(_ state: Int) {
        // YouTube IFrame API states:
        //   -1 = unstarted
        //    0 = ended
        //    1 = playing
        //    2 = paused
        //    3 = buffering
        //    5 = cued
        let previousPlaying = isPlaying
        switch state {
        case 1:
            isPlaying = true
            isBuffering = false
            if !isReady { handleReady() }
        case 2:
            isPlaying = false
            isBuffering = false
            if !isReady { handleReady() }
        case 3:
            isBuffering = true
            if !isReady { handleReady() }  // M29-YT: player alive if it sends state events
        case 0:
            isPlaying = false
            isBuffering = false
        case 5:
            // cued — player has video, treat as ready surface
            isBuffering = false
            if !isReady { handleReady() }
        default:
            break
        }
        // Host multi-device: YouTube chrome play/pause → sync.command
        if previousPlaying != isPlaying, state == 1 || state == 2 || state == 0 {
            emitUserPlaybackChangeIfNeeded(playing: isPlaying, position: position, force: true)
        }
    }

    private func handleError(code: Int) {
        // Brain: map official YouTube IFrame API error codes.
        // https://developers.google.com/youtube/iframe_api_reference#onError
        let message: String
        switch code {
        case 2:             message = "Invalid video parameter"
        case 5:             message = "HTML5 player error"
        case 100:           message = "Video not found or private"
        case 101, 150:      message = "This video cannot be embedded in Plink"
        case 153:           message = "Missing client identity — try another video"
        default:            message = "YouTube error \(code) — try another video"
        }
        lastError = message
        isBuffering = false
        isPlaying = false
    }

    // MARK: - Polling

    /// Poll at 250ms while visible, 1s while backgrounded, stop
    /// after teardown. Position + duration in one JS round-trip via
    /// plinkSnapshot() to halve the IPC overhead.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isBackgrounded = await MainActor.run {
                    UIApplication.shared.applicationState == .background
                }
                let snapshot = await self.evaluate("window.plinkSnapshot && window.plinkSnapshot();")
                if let dict = snapshot as? [String: Any] {
                    let time = dict["time"] as? Double
                    let dur = dict["duration"] as? Double
                    let playing = dict["playing"] as? Bool
                    let state = dict["state"] as? Int
                    await MainActor.run {
                        // Late ready detection via snapshot
                        if !self.isReady {
                            if playing == true || state == 1 || state == 2 || state == 5 {
                                self.handleReady()
                            }
                        }
                        let prev = self.position
                        if let t = time, t.isFinite {
                            self.position = t
                            // Large jump while not suppressed → user seek on YouTube chrome
                            if abs(t - prev) > 1.5 {
                                self.emitUserPlaybackChangeIfNeeded(
                                    playing: self.isPlaying,
                                    position: t,
                                    force: true
                                )
                            }
                        }
                        if let d = dur, d > 0 { self.duration = d }
                        if let p = playing {
                            if p {
                                self.isPlaying = true
                                self.isBuffering = false
                            }
                        }
                        // Расширенный снимок для своей панели управления.
                        if let b = dict["buffered"] as? Double, b.isFinite {
                            self.buffered = max(0, min(1, b))
                        }
                        if let r = dict["rate"] as? Double, r > 0 {
                            self.playbackRate = Float(r)
                        }
                        if let m = dict["muted"] as? Bool { self.isMuted = m }
                        if let q = dict["quality"] as? String { self.currentQuality = q }
                        if let list = dict["qualities"] as? [String] {
                            // «auto» YouTube отдаёт отдельно; порядок сохраняем как есть.
                            if list != self.availableQualities { self.availableQualities = list }
                        }
                        // M29-YT: buffering watchdog
                        if state == 3 {
                            self.bufferingTicks += 1
                            if self.bufferingTicks >= Self.bufferingRecoveryTicks {
                                self.bufferingTicks = 0
                                let recoverPos = self.position
                                Task { await self.evaluate("window.plinkSeek && window.plinkSeek(\(recoverPos));") }
                            }
                        } else {
                            self.bufferingTicks = 0
                        }
                    }
                }
                let interval: UInt64 = isBackgrounded ? 1_000_000_000 : 250_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    // MARK: - JS evaluation

    @discardableResult
    private func evaluate(_ js: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }

    // MARK: - Validation

    /// Validate YouTube video ID — only [A-Za-z0-9_-]{11}.
    /// Prevents XSS / injection via URL parameter.
    private static func isValidVideoId(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.allSatisfy { c in
            c.isLetter || c.isNumber || c == "_" || c == "-"
        }
    }
}

// MARK: - Navigation (surface load failures)

private final class YTWebNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: (Bool, String?) -> Void

    init(onFinish: @escaping (Bool, String?) -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish(true, nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish(false, error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinish(false, error.localizedDescription)
    }
}

// MARK: - Bridge message handler

private final class EmbeddedMessageHandler: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onStateChange: ((Int) -> Void)?
    var onError: ((Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let event = body["event"] as? String
        switch event {
        case "ready":
            onReady?()
        case "state":
            if let state = body["state"] as? Int {
                onStateChange?(state)
            } else if let state = body["state"] as? Double {
                onStateChange?(Int(state))
            } else if let state = body["state"] as? NSNumber {
                onStateChange?(state.intValue)
            }
        case "error":
            if let code = body["code"] as? Int {
                onError?(code)
            } else if let code = body["code"] as? Double {
                onError?(Int(code))
            } else if let code = body["code"] as? NSNumber {
                onError?(code.intValue)
            }
        default:
            break
        }
    }
}
