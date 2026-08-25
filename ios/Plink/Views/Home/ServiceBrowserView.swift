import SwiftUI
import WebKit

// MARK: - ServiceBrowserView
/// REDESIGNED: Full-screen WebView with smart video page detection.
///
/// When the user navigates to a video page in the service's catalog:
///   • For YouTube/VK/Rutube: detects the video page URL pattern automatically
///     and offers to "Создать комнату" with the embeddable URL
///   • For cinema services (Kinopoisk, Ivi, Okko, etc.): the page URL itself
///     becomes the content URL — the WebView acts as the player in the room
///
/// Auth requirements:
///   • YouTube, VK Video, Rutube: NO auth required for public content
///   • Kinopoisk, Ivi, Okko, Wink, Start, Premier, KION: subscription required
///     (user logs in via the WebView; cookies persist between sessions)
///   • Смотрим: free (state TV, no subscription)
///
/// The "Создать комнату" button is always available at the bottom, but when
/// a video page is detected, a prominent banner appears prompting the user
/// to create a room with the detected content.
struct ServiceBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let service: VideoService
    /// Passes content URL + title to parent for RoomSetupView
    var onCreateRoom: (String, String) -> Void

    @State private var currentURL: URL?
    @State private var pageTitle: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showCreateConfirm = false
    @State private var isPageLoading = true
    @State private var loadFailed = false
    /// Меняется, чтобы пересоздать веб-вью при «Повторить».
    @State private var reloadToken = 0
    /// NEW: When a video page is detected, this is set to the detected video info
    @State private var detectedVideo: DetectedVideo?
    /// Smart Wall appears only when the user selects protected content.
    @State private var authWallVideo: DetectedVideo?

    init(service: VideoService, onCreateRoom: @escaping (String, String) -> Void) {
        self.service = service
        self.onCreateRoom = onCreateRoom
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // WebView
                    ServiceWebView(
                        initialURL: URL(string: service.browseURL)!,
                        currentURL: $currentURL,
                        pageTitle: $pageTitle,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        onVideoDetected: { video in
                            detectedVideo = video
                        },
                        onLoadingChange: { loading in
                            withAnimation(.easeOut(duration: 0.2)) { isPageLoading = loading }
                        },
                        onLoadFailed: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPageLoading = false
                                loadFailed = true
                            }
                        },
                        persistCookies: service.requiresAuth
                    )
                    .id(reloadToken)

                    if service.deliveryBucket == .yourScreen || service == .browser {
                        createFromPageBar
                    }
                }

                // Пока грузится страница сервиса, экран был пустым и чёрным:
                // на медленной сети это читалось как зависшее приложение.
                if isPageLoading {
                    loadingOverlay
                        .transition(.opacity)
                        .zIndex(10)
                } else if loadFailed {
                    // Упавшая загрузка тоже оставляла чёрный экран без
                    // единого объяснения и без выхода.
                    failureOverlay
                        .transition(.opacity)
                        .zIndex(10)
                }

                if let video = authWallVideo {
                    ServiceAuthView(
                        service: video.service,
                        onAuthorized: {
                            ServiceAuthStore.markAuthorized(video.service.serviceType)
                            authWallVideo = nil
                            HapticManager.impact(.medium)
                            onCreateRoom(video.embedURL, video.title ?? pageTitle)
                        },
                        onCancel: {
                            authWallVideo = nil
                            detectedVideo = nil
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
                }
            }
            .navigationTitle(service.brandName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            // Pack v3: АВТО-переход — мгновенно для free services.
            // Smart Wall appears only when protected content is selected.
            .onChange(of: detectedVideo) {
                guard let video = detectedVideo else { return }
                if WatchRoomModel.checkServiceAccess(for: video.service.serviceType) {
                    HapticManager.impact(.medium)
                    onCreateRoom(video.embedURL, video.title ?? pageTitle)
                } else {
                    authWallVideo = video
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Кино/браузер: автодетект срабатывает не на каждой странице (Netflix /browse).
    /// Кнопка создаёт комнату с текущим URL — хост шарит экран с этой страницы.
    private var createFromPageBar: some View {
        Button {
            let href = currentURL?.absoluteString ?? service.browseURL
            let heading = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let video = DetectedVideo(
                title: heading.isEmpty ? nil : heading,
                embedURL: href,
                originalURL: href,
                service: service
            )
            if WatchRoomModel.checkServiceAccess(for: service.serviceType) {
                HapticManager.impact(.medium)
                onCreateRoom(href, heading.isEmpty ? service.brandName : heading)
            } else {
                authWallVideo = video
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                Text(service.deliveryBucket == .yourScreen
                     ? "Создать комнату с этой страницы"
                     : "Создать комнату с этой вкладки")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(V4.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Cinema2026.background)
    }

    // MARK: - Загрузка страницы сервиса

    /// Что показываем, пока грузится сайт сервиса. Логотип сервиса вместо
    /// абстрактного спиннера: пользователь видит, КУДА он идёт, а не просто
    /// факт ожидания.
    private var loadingOverlay: some View {
        ZStack {
            V4.canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                ServiceLogoView(service: service, size: 56)
                    .padding(14)
                    .plinkGlass(.control, cornerRadius: 22)

                VStack(spacing: 5) {
                    Text(service.brandName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text("Открываем сервис…")
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                }

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(V4.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Открываем \(service.brandName)")
    }

    /// Загрузка упала. Раньше на этом месте оставался чёрный экран без
    /// объяснения и без выхода — приходилось закрывать экран вслепую.
    private var failureOverlay: some View {
        ZStack {
            V4.canvas.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(V4.amber)
                    .frame(width: 78, height: 78)
                    .plinkGlass(.control, in: Circle())

                VStack(spacing: 6) {
                    Text("\(service.brandName) не открылся")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text("Проверьте соединение и попробуйте снова.")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(V4.muted)
                }

                Button("Повторить") {
                    loadFailed = false
                    isPageLoading = true
                    // Пересоздаём веб-вью: у упавшего WKWebView reload()
                    // часто возвращает ту же ошибку из кэша.
                    reloadToken += 1
                }
                .buttonStyle(
                    PlinkProminentButtonStyle(
                        tint: V4.accent,
                        height: 48,
                        cornerRadius: 16,
                        fillsWidth: false
                    )
                )
            }
            .padding(.horizontal, 34)
        }
    }

    // MARK: - Video Detected Banner

    private func videoDetectedBanner(video: DetectedVideo) -> some View {
        HStack(spacing: 12) {
            // Service logo
            ServiceLogoView(service: service, size: 32)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.string(.sbVideoFound))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Cinema2026.accent)
                Text(video.title ?? pageTitle)
                    .font(.system(size: 12))
                    .foregroundColor(Cinema2026.text)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                HapticManager.impact(.medium)
                showCreateConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text(LocalizationManager.shared.string(.roomLabel))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Cinema2026.accentAction)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(LinearGradient(colors: [Cinema2026.accent.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .offset(y: -22)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pageTitle.isEmpty ? "Выберите контент" : pageTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Cinema2026.text)
                    .lineLimit(1)
                if let url = currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(Cinema2026.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                HapticManager.impact(.medium)
                showCreateConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text(LocalizationManager.shared.string(.rcCreate))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Cinema2026.accentAction)
                .clipShape(Capsule())
                .shadow(color: Cinema2026.accent.opacity(0.4), radius: 8, y: 3)
            }
            .disabled(currentURL == nil)
            .opacity(currentURL == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Detected Video Model

struct DetectedVideo: Equatable {
    let title: String?
    let embedURL: String       // URL that can be used in our player
    let originalURL: String    // original page URL
    let service: VideoService
    /// Постер видео, если сервис его отдал (FIX: "Value of type 'DetectedVideo'
    /// has no member 'thumbnailURL'" в RoomCreationView.setupStep).
    var thumbnailURL: String? = nil
}

// MARK: - Service Auth Wall

struct ServiceAuthView: View {
    let service: VideoService
    let onAuthorized: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 18) {
                ServiceLogoView(service: service, size: 58)
                    .frame(width: 72, height: 72)
                    .background(service.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(service.accentColor.opacity(0.32), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    Text("Войдите в \(service.brandName)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Cinema2026.text)
                        .multilineTextAlignment(.center)

                    Text(LocalizationManager.shared.string(.sbHostAccount))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Cinema2026.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    HapticManager.impact(.medium)
                    onAuthorized()
                } label: {
                    Text(LocalizationManager.shared.string(.sbSignedIn))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(service.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("Отмена") {
                    onCancel()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.secondary)
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - VideoService + Video Detection

extension VideoService {
    /// Detects if a URL is a video page for this service, and returns the
    /// embeddable video URL if so. Returns nil if the URL is not a video page.
    static func detectVideoURL(_ url: URL, for service: VideoService, title: String?) -> DetectedVideo? {
        let urlString = url.absoluteString
        let host = url.host ?? ""

        switch service {
        case .youtube:
            // Только реальный ролик. lastPathComponent на /feed/trending
            // давал фейковый id «trending» и сразу создавал комнату.
            if PlinkHost.matches(host, anyOf: PlinkHost.youtubeDomains),
               let videoId = RoomCreateMedia.extractYouTubeID(from: urlString) {
                return DetectedVideo(
                    title: title,
                    embedURL: "https://www.youtube.com/embed/\(videoId)",
                    originalURL: urlString,
                    service: .youtube
                )
            }

        case .vk:
            if PlinkHost.matches(host, anyOf: PlinkHost.vkDomains) {
                let path = url.path.lowercased()
                if path.contains("/video") || path.contains("/clip") {
                    return DetectedVideo(
                        title: title,
                        embedURL: urlString,
                        originalURL: urlString,
                        service: .vk
                    )
                }
            }

        case .rutube:
            if PlinkHost.matches(host, anyOf: PlinkHost.rutubeDomains),
               let videoId = RoomCreateMedia.extractRutubeVideoId(from: urlString) {
                return DetectedVideo(
                    title: title,
                    embedURL: "https://rutube.ru/play/embed/\(videoId)",
                    originalURL: urlString,
                    service: .rutube
                )
            }

        case .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion, .netflix, .disney:
            // DRM: страница = контент для режима «ваш экран».
            // Netflix — /title/ и /watch/, Кинопоиск — /film/, Disney — /play/.
            let path = url.path.lowercased()
            let videoPatterns = [
                "/film/", "/series/", "/video/", "/watch/", "/play/",
                "/movies/", "/movie/", "/show/", "/title/", "/clip/", "/episode/",
            ]
            if videoPatterns.contains(where: { path.contains($0) }) {
                return DetectedVideo(
                    title: title,
                    embedURL: urlString,
                    originalURL: urlString,
                    service: service
                )
            }

        case .browser, .customURL:
            break
        }

        return nil
    }
}

// MARK: - ServiceWebView (WKWebView wrapper with video detection)

// WKProcessPool is DEPRECATED in iOS 15+. The v26
// attempt to isolate via process pools was based on outdated info —
// removed. Each WKWebView always gets its own WebContent process
// automatically. The .nonPersistent() data store (kept from v25) is
// the real isolation mechanism.

struct ServiceWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    /// NEW: Called when a video page is detected
    var onVideoDetected: ((DetectedVideo) -> Void)?
    /// Идёт ли загрузка страницы. Без этого сигнала экран сервиса оставался
    /// пустым и чёрным всё время загрузки — на медленной сети выглядело как
    /// зависшее приложение.
    var onLoadingChange: ((Bool) -> Void)?
    /// Загрузка упала — сеть недоступна или сервис не ответил.
    var onLoadFailed: (() -> Void)?
    /// Кинотеатры и Яндекс ID: постоянный cookie-jar. YouTube-поиск — нет.
    var persistCookies: Bool = false

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // ISOLATED, NON-PERSISTENT data store for the
        // search browser.
        //
        // The previous call to WKWebsiteDataStore.default() returned the
        // (the room player), which uses a custom plink-media:// scheme handler
        // and a modified User-Agent. Once that store accumulated cookies +
        // cache entries from the room player, YouTube's anti-bot heuristics
        // flagged it (the WebContent process saw inconsistent fingerprints
        // across the two contexts) and started returning the consent /
        // language-selection interstitial on the search screen as well.
        //
        // Switching to .nonPersistent() gives the search browser a FRESH,
        // isolated store on every launch — YouTube sees a clean Safari-like
        // session and skips the interstitial. Cookies set during search do
        // NOT persist across app launches, which is fine for a video search
        // screen (the user is browsing, not logging in here).
        // YouTube-каталог: nonPersistent, иначе антибот путает плеер комнаты.
        // Кинотеатры / Яндекс ID: CinemaSessionStore — логин один раз.
        config.websiteDataStore = CinemaSessionStore.store(persistingCookies: persistCookies)

        // Pack v3: Register message handler for SPA URL changes.
        // NOTE: this is a coordinator-only message handler, NOT a script
        // injection — YouTube's anti-bot JS cannot see it from the page
        // context (it only sees whatever we add via addUserScript). Keeping
        // this handler is safe; it does not change the page's fingerprint.
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "plinkURLChange")

        // NO injected scripts for YouTube.
        //
        // v9.3 injected an `overflow-x:hidden` style. Even though the script
        // itself is benign, the act of running any WKUserScript at
        // .atDocumentEnd over the YouTube page gives YouTube's anti-bot JS
        // a measurable signal (it can detect document_end script injection
        // timing). Removing the script makes our WKWebView look more like
        // stock Safari.
        //
        // The overflow-x:hidden was only a "safety net" for minor horizontal
        // scroll glitches on m.youtube.com — m.youtube.com's own CSS handles
        // this fine in 2026, so the safety net is no longer worth the
        // detection cost.
        if !PlinkHost.isYouTube(initialURL) {
            // For non-YouTube services (Rutube, VK, etc.) we still allow
            // future script injection here — those services don't run the
            // same anti-bot heuristics.
        }

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // REMOVED customUserAgent for YouTube.
        //
        // Previously this set an iPad Safari UA, hoping YouTube would serve
        // the modern mobile m.youtube.com layout. That worked initially, but
        // once the shared websiteDataStore got "marked" by earlier 153
        // failures (sandbox errors, DownloadFailed) YouTube's anti-bot
        // started treating the iPad UA from a WKWebView process as
        // inconsistent — iPad UA but no iPad Safari cookies, no Safari
        // fingerprint, no real iPad device attestation. Result: language
        // selection screen + "Sign in to confirm you're not a bot".
        //
        // Fix: leave customUserAgent UNSET. iOS will send the system's
        // native WKWebView UA, which is itself an iPhone Safari UA variant
        // (e.g. "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)
        // AppleWebKit/605.1.15 (KHTML, like Gecko) ... Version/17.5
        // Mobile/15E148 Safari/604.1"). This is the closest WKWebView can
        // get to real Safari — YouTube accepts it for m.youtube.com without
        // throwing the consent interstitial.

        webView.load(URLRequest(url: initialURL))

        webView.isOpaque = false
        webView.backgroundColor = UIColor(Cinema2026.background)
        webView.scrollView.backgroundColor = UIColor(Cinema2026.background)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "plinkURLChange")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: ServiceWebView
        private var lastDetectedURL: String?

        init(parent: ServiceWebView) {
            self.parent = parent
        }

        // Pack v3: Handle SPA URL changes from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "plinkURLChange",
               let body = message.body as? [String: Any],
               let urlString = body["url"] as? String,
               let url = URL(string: urlString) {

                let title = body["title"] as? String
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: title) {
                    DispatchQueue.main.async {
                        self.parent.currentURL = url
                        self.parent.pageTitle = title ?? ""
                        self.parent.onVideoDetected?(detected)
                    }
                }
            }
        }

        // Pack v3: Перехватываем КАЖДУЮ навигацию (включая SPA YouTube).
        // Раньше: только didFinish → YouTube SPA не триггерит → видео играло без создания комнаты.
        // Теперь: decidePolicyFor ловит URLchange → детектим видео → авто-переход.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Сначала проверяем URL на видео
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                // Избегаем повторного срабатывания на тот же URL
                if urlString != lastDetectedURL {
                    lastDetectedURL = urlString
                    let service = Self.serviceFromURL(url)
                    if let service, let detected = VideoService.detectVideoURL(url, for: service, title: nil) {
                        // CANCEL navigation — don't load the YouTube watch page.
                        // Was: .allow → YouTube watch page loaded → video auto-played for
                        // a second before room creation took over.
                        // Now: .cancel → YouTube watch page never loads, no video playback.
                        // We just extract the video ID from the URL and create the room.
                        DispatchQueue.main.async {
                            self.parent.currentURL = url
                            self.parent.pageTitle = webView.title ?? ""
                            self.parent.onVideoDetected?(detected)
                        }
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.onLoadingChange?(true) }
        }

        /// Сеть отвалилась до первого байта. Без этого индикатор крутился бы
        /// вечно на упавшей загрузке.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onLoadingChange?(false)
                // Отмена — это не сбой: так выглядит переход на новый URL,
                // пока предыдущий ещё грузился.
                if (error as NSError).code != NSURLErrorCancelled {
                    self.parent.onLoadFailed?()
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.onLoadingChange?(false)
                self.parent.currentURL = webView.url
                self.parent.pageTitle = webView.title ?? ""
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }

            // Detect video page on full load too
            if let url = webView.url {
                let title = webView.title
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: title) {
                    DispatchQueue.main.async {
                        self.parent.onVideoDetected?(detected)
                    }
                }
            }

            // SKIP all JS/CSS injection on YouTube.
            //
            // YouTube's anti-bot heuristics detect `evaluateJavaScript` calls
            // by timing and side-effects (window._plinkURLObserver global,
            // injected <style> nodes). On m.youtube.com, the History API
            // URL observer is also unnecessary — `decidePolicyFor` already
            // catches every navigation (including SPA route changes via
            // pushState) BEFORE the page loads. The observer was a legacy
            // fallback from when YouTube used `pushState` without triggering
            // a navigation delegate callback; in 2026 m.youtube.com triggers
            // a navigation delegate on every route change, so the observer
            // is dead weight that just costs us a fingerprint.
            //
            // For non-YouTube services (Rutube, VK, cinema) we still inject
            // the SPA observer + dark CSS — those services don't run anti-bot
            // heuristics, and some of them (Rutube) genuinely need the
            // observer to detect video page transitions.
            let isYouTubePage = PlinkHost.isYouTube(webView.url)
            guard !isYouTubePage else { return }

            // Pack v3: Inject JS to detect SPA URL changes (Rutube React app
            // and other services that use History API without full reload).
            let js = """
            (function() {
                if (window._plinkURLObserver) return;
                window._plinkURLObserver = true;
                let lastURL = window.location.href;
                setInterval(function() {
                    if (window.location.href !== lastURL) {
                        lastURL = window.location.href;
                        try {
                            window.webkit.messageHandlers.plinkURLChange.postMessage({
                                url: lastURL,
                                title: document.title
                            });
                        } catch(e) {}
                    }
                }, 500);
            })();
            """

            // Inject dark CSS
            let darkCSS = """
            :root { color-scheme: dark; }
            body { background-color: #0A0D14 !important; }
            """
            let cssJS = """
            var style = document.createElement('style');
            style.textContent = '\(darkCSS)';
            document.head.appendChild(style);
            """

            webView.evaluateJavaScript(js)
            webView.evaluateJavaScript(cssJS)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                // Индикатор обязан гаснуть и на упавшей загрузке, иначе он
                // крутится вечно.
                self.parent.onLoadingChange?(false)
                self.parent.pageTitle = "Ошибка загрузки"
                if (error as NSError).code != NSURLErrorCancelled {
                    self.parent.onLoadFailed?()
                }
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Rutube opens video in new window. Check for video URL before loading.
            if let url = navigationAction.request.url {
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: nil) {
                    DispatchQueue.main.async {
                        self.parent.currentURL = url
                        self.parent.pageTitle = webView.title ?? ""
                        self.parent.onVideoDetected?(detected)
                    }
                    return nil  // Don't open new window — go straight to room creation
                }
                // Not a video — load in current webView
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // Helper: determine VideoService from URL host
        //
        // Строгий матч домена (PlinkHost). Прошлая версия матчила подстроки и
        // была строже/слабее самой себя в разных местах: `host.contains("rutube")`
        // классифицировал rutube.evil.com как Rutube, а `contains("youtube")`
        // — любой youtube-something.ru. Список доменов теперь один, в PlinkHost.
        private static func serviceFromURL(_ url: URL) -> VideoService? {
            let host = url.host
            if PlinkHost.matches(host, anyOf: PlinkHost.youtubeDomains)   { return .youtube }
            if PlinkHost.matches(host, anyOf: PlinkHost.vkDomains)        { return .vk }
            if PlinkHost.matches(host, anyOf: PlinkHost.rutubeDomains)    { return .rutube }
            if PlinkHost.matches(host, anyOf: PlinkHost.netflixDomains)   { return .netflix }
            if PlinkHost.matches(host, anyOf: PlinkHost.disneyDomains)    { return .disney }
            if PlinkHost.matches(host, anyOf: PlinkHost.kinopoiskDomains) { return .kinopoisk }
            if PlinkHost.matches(host, anyOf: PlinkHost.iviDomains)       { return .ivi }
            if PlinkHost.matches(host, anyOf: PlinkHost.okkoDomains)      { return .okko }
            if PlinkHost.matches(host, anyOf: PlinkHost.winkDomains)      { return .wink }
            if PlinkHost.matches(host, anyOf: PlinkHost.startDomains)     { return .start }
            if PlinkHost.matches(host, anyOf: PlinkHost.premierDomains)   { return .premier }
            if PlinkHost.matches(host, anyOf: PlinkHost.smotrimDomains)   { return .smotrim }
            if PlinkHost.matches(host, anyOf: PlinkHost.kionDomains)      { return .kion }
            return nil
        }
    }
}
