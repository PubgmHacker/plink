import XCTest
@testable import Plink

/// Создание комнаты через каждый VideoService: детект URL + MediaItem.
final class RoomCreateServiceTests: XCTestCase {

    func testEveryServiceHasBrowseURL() {
        for svc in VideoService.allCases {
            XCTAssertNotNil(URL(string: svc.browseURL), "\(svc.rawValue) browseURL")
            XCTAssertFalse(svc.browseURL.isEmpty, svc.rawValue)
        }
    }

    func testCatalogListsEveryServiceOnce() {
        let carousel: [VideoService] = [
            .youtube, .vk, .rutube, .kinopoisk, .ivi, .okko, .wink,
            .start, .premier, .kion, .smotrim, .netflix, .disney,
        ]
        let other: [VideoService] = [.browser, .customURL]
        let listed = Set(carousel + other)
        XCTAssertEqual(listed, Set(VideoService.allCases), "Пикер должен покрывать все сервисы")
    }

    // MARK: - YouTube

    func testYouTubeWatchAndShortsDetect() {
        let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let d = VideoService.detectVideoURL(watch, for: .youtube, title: "Rick")
        XCTAssertEqual(d?.service, .youtube)
        XCTAssertTrue(d?.embedURL.contains("dQw4w9WgXcQ") == true)

        let shorts = URL(string: "https://www.youtube.com/shorts/dQw4w9WgXcQ")!
        XCTAssertNotNil(VideoService.detectVideoURL(shorts, for: .youtube, title: nil))

        let be = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertNotNil(VideoService.detectVideoURL(be, for: .youtube, title: nil))
    }

    func testYouTubeTrendingIsNotAVideo() {
        let trending = URL(string: "https://www.youtube.com/feed/trending")!
        XCTAssertNil(VideoService.detectVideoURL(trending, for: .youtube, title: "Trending"))
        XCTAssertNil(RoomCreateMedia.extractYouTubeID(from: trending.absoluteString))
    }

    func testYouTubeMediaItemSetsSourceAndId() {
        let video = DetectedVideo(
            title: "Rick",
            embedURL: "https://www.youtube.com/embed/dQw4w9WgXcQ",
            originalURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            service: .youtube
        )
        let item = RoomCreateMedia.mediaItem(service: .youtube, video: video, roomName: "Rick")
        XCTAssertEqual(item.source, .youtube)
        XCTAssertEqual(item.videoId, "dQw4w9WgXcQ")
        XCTAssertTrue(item.streamURL.contains("dQw4w9WgXcQ"))
    }

    // MARK: - VK / Rutube

    func testVKVideoDetectAndMedia() {
        let url = URL(string: "https://vk.com/video-123_456")!
        let d = VideoService.detectVideoURL(url, for: .vk, title: "Clip")
        XCTAssertEqual(d?.service, .vk)
        let item = RoomCreateMedia.mediaItem(service: .vk, video: d!, roomName: "Clip")
        XCTAssertEqual(item.source, .url)
        XCTAssertTrue(item.streamURL.contains("vk.com"))
        XCTAssertEqual(item.videoId, "-123_456")
    }

    func testRutubeDetectAndEmbed() {
        let id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let url = URL(string: "https://rutube.ru/video/\(id)/")!
        let d = VideoService.detectVideoURL(url, for: .rutube, title: "Show")
        XCTAssertEqual(d?.embedURL, "https://rutube.ru/play/embed/\(id)")
        let item = RoomCreateMedia.mediaItem(service: .rutube, video: d!, roomName: "Show")
        XCTAssertEqual(item.videoId, id)
        XCTAssertTrue(item.streamURL.contains("play/embed"))
    }

    func testPhishingHostsNeverDetect() {
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://evil-vk.com.ru/video-1_2")!, for: .vk, title: nil))
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://youtube.com.evil.ru/watch?v=dQw4w9WgXcQ")!, for: .youtube, title: nil))
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://fakerutube.ru/video/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!, for: .rutube, title: nil))
    }

    // MARK: - Cinema / OTT (ваш экран)

    func testCinemaTitlePagesDetect() {
        let cases: [(VideoService, String)] = [
            (.kinopoisk, "https://www.kinopoisk.ru/film/12345/"),
            (.ivi, "https://www.ivi.ru/watch/show"),
            (.okko, "https://okko.tv/movie/foo"),
            (.wink, "https://wink.ru/watch/1"),
            (.start, "https://start.ru/watch/x"),
            (.premier, "https://premier.one/show/x"),
            (.smotrim, "https://smotrim.ru/video/1"),
            (.kion, "https://kion.ru/video/1"),
            (.netflix, "https://www.netflix.com/title/80178687"),
            (.disney, "https://www.disneyplus.com/play/abc"),
        ]
        for (svc, href) in cases {
            let d = VideoService.detectVideoURL(URL(string: href)!, for: svc, title: svc.rawValue)
            XCTAssertNotNil(d, "\(svc.rawValue) should detect \(href)")
            let item = RoomCreateMedia.mediaItem(service: svc, video: d!, roomName: svc.rawValue)
            XCTAssertEqual(item.source, .url)
            XCTAssertEqual(item.streamURL, href)
            let expectedBucket: DeliveryBucket = svc.serviceType.requiresAuth ? .bySubscription : .worksNow
            XCTAssertEqual(svc.deliveryBucket, expectedBucket, svc.rawValue)
            if svc.requiresSubscription || svc == .browser {
                XCTAssertEqual(svc.playbackMode, .webview, svc.rawValue)
            } else {
                XCTAssertEqual(svc.playbackMode, .webview, svc.rawValue)
            }
        }
    }

    func testCinemaHomepagesDoNotAutoDetect() {
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://www.netflix.com/browse")!, for: .netflix, title: nil))
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://kinopoisk.ru/")!, for: .kinopoisk, title: nil))
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://www.disneyplus.com/")!, for: .disney, title: nil))
    }

    // MARK: - Browser / custom

    func testCustomDirectFile() {
        let video = DetectedVideo(
            title: nil,
            embedURL: "https://cdn.example.com/a.m3u8",
            originalURL: "https://cdn.example.com/a.m3u8",
            service: .customURL
        )
        let item = RoomCreateMedia.mediaItem(service: .customURL, video: video, roomName: "")
        XCTAssertEqual(item.source, .url)
        XCTAssertTrue(item.streamURL.hasSuffix(".m3u8"))
        XCTAssertEqual(item.deliveryIsDirectFile, true)
    }

    func testBrowserPageUsesOfficialWebView() {
        XCTAssertEqual(VideoService.browser.deliveryBucket, .worksNow)
        let video = DetectedVideo(
            title: "Site",
            embedURL: "https://example.com/watch",
            originalURL: "https://example.com/watch",
            service: .browser
        )
        let item = RoomCreateMedia.mediaItem(service: .browser, video: video, roomName: "Site")
        XCTAssertEqual(item.streamURL, "https://example.com/watch")
    }

    func testClipboardDetectCoversAllKnownHosts() {
        XCTAssertEqual(VideoService.detect(fromURL: "https://youtu.be/dQw4w9WgXcQ"), .youtube)
        XCTAssertEqual(VideoService.detect(fromURL: "https://vk.com/video-1_2"), .vk)
        XCTAssertEqual(VideoService.detect(fromURL: "https://rutube.ru/video/aa/"), .rutube)
        XCTAssertEqual(VideoService.detect(fromURL: "https://www.netflix.com/title/1"), .netflix)
        XCTAssertEqual(VideoService.detect(fromURL: "https://www.disneyplus.com/play/x"), .disney)
        XCTAssertEqual(VideoService.detect(fromURL: "https://www.kinopoisk.ru/film/1"), .kinopoisk)
        XCTAssertEqual(VideoService.detect(fromURL: "https://www.ivi.ru/watch/x"), .ivi)
        XCTAssertEqual(VideoService.detect(fromURL: "https://okko.tv/x"), .okko)
        XCTAssertEqual(VideoService.detect(fromURL: "https://wink.ru/x"), .wink)
        XCTAssertEqual(VideoService.detect(fromURL: "https://start.ru/x"), .start)
        XCTAssertEqual(VideoService.detect(fromURL: "https://premier.one/x"), .premier)
        XCTAssertEqual(VideoService.detect(fromURL: "https://smotrim.ru/x"), .smotrim)
        XCTAssertEqual(VideoService.detect(fromURL: "https://kion.ru/x"), .kion)
        XCTAssertEqual(VideoService.detect(fromURL: "https://cdn.example.com/a.mp4"), .customURL)
    }

    /// Каждый VideoService даёт непустой MediaItem — путь создания комнаты.
    func testEveryServiceBuildsNonEmptyMediaItem() {
        let samples: [(VideoService, String)] = [
            (.youtube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            (.vk, "https://vk.com/video-123_456"),
            (.rutube, "https://rutube.ru/video/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"),
            (.netflix, "https://www.netflix.com/title/80178687"),
            (.disney, "https://www.disneyplus.com/play/abc"),
            (.browser, "https://example.com/watch"),
            (.customURL, "https://cdn.example.com/a.m3u8"),
            (.kinopoisk, "https://www.kinopoisk.ru/film/12345/"),
            (.ivi, "https://www.ivi.ru/watch/show"),
            (.okko, "https://okko.tv/movie/foo"),
            (.wink, "https://wink.ru/watch/1"),
            (.start, "https://start.ru/watch/x"),
            (.premier, "https://premier.one/show/x"),
            (.smotrim, "https://smotrim.ru/video/1"),
            (.kion, "https://kion.ru/video/1"),
        ]
        XCTAssertEqual(Set(samples.map(\.0)), Set(VideoService.allCases), "Добавь URL для нового сервиса")
        for (svc, href) in samples {
            let video = DetectedVideo(
                title: svc.rawValue,
                embedURL: href,
                originalURL: href,
                service: svc
            )
            let item = RoomCreateMedia.mediaItem(service: svc, video: video, roomName: svc.rawValue)
            XCTAssertFalse(item.streamURL.isEmpty, svc.rawValue)
            XCTAssertEqual(item.title, svc.rawValue, svc.rawValue)
            let expectedSource: MediaItem.MediaSource = svc == .youtube ? .youtube : .url
            XCTAssertEqual(item.source, expectedSource, svc.rawValue)
        }
    }

    func testCinemaManualPageStillCreatesRoomMedia() {
        let href = "https://www.netflix.com/browse"
        let video = DetectedVideo(
            title: "Netflix",
            embedURL: href,
            originalURL: href,
            service: .netflix
        )
        let item = RoomCreateMedia.mediaItem(service: .netflix, video: video, roomName: "Netflix")
        XCTAssertEqual(item.streamURL, href)
        XCTAssertEqual(item.source, .url)
    }

    // MARK: - VK Video (beta service #3)

    /// Links copied from vkvideo.ru / m.vkvideo.ru / vk.com must all resolve
    /// to the same `oid_id` token the embed player understands.
    func testVKVideoIdFromEveryPublicDomain() {
        XCTAssertEqual(RoomCreateMedia.extractVKVideoId(from: "https://vkvideo.ru/video-123456_789"), "-123456_789")
        XCTAssertEqual(RoomCreateMedia.extractVKVideoId(from: "https://m.vkvideo.ru/video-1_2?t=10s"), "-1_2")
        XCTAssertEqual(RoomCreateMedia.extractVKVideoId(from: "https://vkvideo.ru/clip-55_66"), "-55_66")
        XCTAssertEqual(RoomCreateMedia.extractVKVideoId(from: "https://vk.com/video-77_88"), "-77_88")
        XCTAssertEqual(
            RoomCreateMedia.extractVKVideoId(from: "https://vk.com/video_ext.php?oid=-1&id=2&hd=2"),
            "oid=-1&id=2&hd=2"
        )
    }

    /// The catalogue root, channel pages and VK's autologin redirect chain are
    /// not videos — detecting them would create a room with nothing to play.
    func testVKCatalogueAndAutologinAreNotVideos() {
        let notVideos = [
            "https://vkvideo.ru/",
            "https://m.vkvideo.ru/",
            "https://vkvideo.ru/@somechannel",
            "https://login.vk.ru/?act=autologin&redirect_uri=https://vkvideo.ru&state=abc",
            "https://vkvideo.ru/?errorCode=11300&errorText=invalid+user",
        ]
        for raw in notVideos {
            XCTAssertNil(RoomCreateMedia.extractVKVideoId(from: raw), raw)
            let url = URL(string: raw)!
            XCTAssertNil(VideoService.detectVideoURL(url, for: .vk, title: nil), raw)
        }
    }

    /// A detected VK video carries the video_ext embed the room player needs.
    func testVKDetectedVideoBuildsEmbed() throws {
        let url = URL(string: "https://m.vkvideo.ru/video-123_456")!
        let detected = try XCTUnwrap(VideoService.detectVideoURL(url, for: .vk, title: "Клип"))
        XCTAssertEqual(detected.service, .vk)
        XCTAssertEqual(detected.title, "Клип")
        XCTAssertEqual(detected.originalURL, url.absoluteString)
        XCTAssertEqual(detected.embedURL, "https://vk.com/video_ext.php?oid=-123&id=456&hd=2&js_api=1")
    }

    /// RuTube: the watch page becomes the /play/embed URL, the root page is nothing.
    func testRutubeDetectedVideoBuildsEmbed() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let url = URL(string: "https://rutube.ru/video/\(id)/")!
        let detected = try XCTUnwrap(VideoService.detectVideoURL(url, for: .rutube, title: nil))
        XCTAssertEqual(detected.embedURL, "https://rutube.ru/play/embed/\(id)")
        XCTAssertNil(VideoService.detectVideoURL(URL(string: "https://rutube.ru/")!, for: .rutube, title: nil))
    }

    /// First release ships exactly three watchable services; the rest are "soon".
    func testBetaServicesAreYouTubeRutubeAndVK() {
        let beta = Set(VideoService.allCases.filter(\.isAvailableInBeta))
        XCTAssertEqual(beta, [.youtube, .rutube, .vk])
    }
}

private extension MediaItem {
    var deliveryIsDirectFile: Bool {
        let l = streamURL.lowercased()
        return l.contains(".m3u8") || l.contains(".mp4")
    }
}
