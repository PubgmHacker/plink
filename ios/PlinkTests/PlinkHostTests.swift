import XCTest
@testable import Plink

/// Регрессия на дыру, которая пережила два аудита и один переезд файла.
///
/// Июль 2026: аудит нашёл `host.contains("vk.com")` в `MediaSourceResolver.swift`.
/// Мёртвый CI (`ios-2/.github/workflows/ci.yml`) стерёг именно тот путь.
/// К августу файл удалили, а приём разошёлся по четырём местам:
/// `ServiceBrowserView.detectVideoURL`, `ServiceBrowserView.serviceFromURL`,
/// `ServicePickerCarousel.detect`, `WatchRoomCompositionRoot.extractVKVideoId`
/// (последний матчил подстроку по ВСЕЙ строке URL, включая query).
///
/// Почему это не косметика: результат матча решает, чей URL попадёт в плеер
/// комнаты у ВСЕХ участников. Ложное «это ВКонтакте» = фишинг логина VK
/// внутри нашего приложения, с нашей шапкой и нашим доверием.
final class PlinkHostTests: XCTestCase {

    // MARK: - Ровный домен и поддомены проходят

    func testExactDomainMatches() {
        XCTAssertTrue(PlinkHost.matches("vk.com", domain: "vk.com"))
        XCTAssertTrue(PlinkHost.matches("youtube.com", domain: "youtube.com"))
    }

    func testSubdomainMatches() {
        XCTAssertTrue(PlinkHost.matches("m.vk.com", domain: "vk.com"))
        XCTAssertTrue(PlinkHost.matches("www.youtube.com", domain: "youtube.com"))
        XCTAssertTrue(PlinkHost.matches("a.b.c.rutube.ru", domain: "rutube.ru"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(PlinkHost.matches("VK.COM", domain: "vk.com"))
        XCTAssertTrue(PlinkHost.matches("M.Vk.Com", domain: "VK.com"))
    }

    /// «vk.com.» — валидный абсолютный FQDN, тот же хост.
    func testTrailingDotIsStripped() {
        XCTAssertTrue(PlinkHost.matches("vk.com.", domain: "vk.com"))
        XCTAssertTrue(PlinkHost.matches("m.vk.com.", domain: "vk.com"))
    }

    // MARK: - Фишинг не проходит

    /// Ровно тот хост из отчёта аудита.
    func testAuditPhishingHostRejected() {
        XCTAssertFalse(PlinkHost.matches("evil-vk.com.ru", domain: "vk.com"))
    }

    func testSuffixPhishingRejected() {
        // Домен атакующего, у которого наш домен — префикс родительского.
        XCTAssertFalse(PlinkHost.matches("vk.com.evil.ru", domain: "vk.com"))
        XCTAssertFalse(PlinkHost.matches("youtube.com.attacker.io", domain: "youtube.com"))
    }

    func testPrefixPhishingRejected() {
        // Нет точки перед нашим доменом — значит это другой домен.
        XCTAssertFalse(PlinkHost.matches("notvk.com", domain: "vk.com"))
        XCTAssertFalse(PlinkHost.matches("myyoutube.com", domain: "youtube.com"))
        XCTAssertFalse(PlinkHost.matches("fakerutube.ru", domain: "rutube.ru"))
    }

    /// Старый `contains("youtu")` принимал это. Новый — нет.
    func testLooseTokenPhishingRejected() {
        XCTAssertFalse(PlinkHost.matches("youtube-clone.ru", anyOf: PlinkHost.youtubeDomains))
        XCTAssertFalse(PlinkHost.matches("winkle.io", anyOf: PlinkHost.winkDomains))
        XCTAssertFalse(PlinkHost.matches("rutube.evil.com", anyOf: PlinkHost.rutubeDomains))
    }

    func testEmptyAndNilRejected() {
        XCTAssertFalse(PlinkHost.matches(nil, domain: "vk.com"))
        XCTAssertFalse(PlinkHost.matches("", domain: "vk.com"))
        XCTAssertFalse(PlinkHost.matches(".", domain: "vk.com"))
        XCTAssertFalse(PlinkHost.matches("vk.com", domain: ""))
    }

    // MARK: - Списки доменов

    func testDomainListsMatchRealHosts() {
        XCTAssertTrue(PlinkHost.matches("m.youtube.com", anyOf: PlinkHost.youtubeDomains))
        XCTAssertTrue(PlinkHost.matches("youtu.be", anyOf: PlinkHost.youtubeDomains))
        XCTAssertTrue(PlinkHost.matches("vkvideo.ru", anyOf: PlinkHost.vkDomains))
        XCTAssertTrue(PlinkHost.matches("rutube.video", anyOf: PlinkHost.rutubeDomains))
    }

    func testConvenienceHelpers() {
        XCTAssertTrue(PlinkHost.isYouTube(URL(string: "https://www.youtube.com/watch?v=abc")))
        XCTAssertTrue(PlinkHost.isVK(URL(string: "https://m.vk.com/video-1_2")))
        XCTAssertTrue(PlinkHost.isRutube(URL(string: "https://rutube.ru/video/deadbeef/")))

        XCTAssertFalse(PlinkHost.isYouTube(URL(string: "https://youtube.com.evil.ru/watch?v=abc")))
        XCTAssertFalse(PlinkHost.isVK(URL(string: "https://evil-vk.com.ru/video-1_2")))
        XCTAssertFalse(PlinkHost.isRutube(URL(string: "https://rutube.attacker.io/video/x/")))
    }

    // MARK: - Подстрока в query больше не считается признаком сервиса

    /// `WatchRoomCompositionRoot.extractVKVideoId` матчил `lower.contains("vk.com")`
    /// по всей строке URL. Такой URL проходил и возвращался как embed-источник.
    func testDomainInQueryDoesNotMatch() {
        let url = URL(string: "https://evil.ru/watch?ref=vk.com&next=rutube.ru")
        XCTAssertFalse(PlinkHost.isVK(url))
        XCTAssertFalse(PlinkHost.isRutube(url))
    }

    func testDomainInPathDoesNotMatch() {
        let url = URL(string: "https://evil.ru/vk.com/video-1_2")
        XCTAssertFalse(PlinkHost.isVK(url))
    }

    // MARK: - Реальные вызывающие места

    /// Классификатор из карусели: раньше `contains("youtu")`.
    func testServiceDetectionRejectsPhishing() {
        XCTAssertEqual(VideoService.detect(fromURL: "https://m.vk.com/video-1_2"), .vk)
        XCTAssertEqual(VideoService.detect(fromURL: "https://youtu.be/abc123"), .youtube)

        XCTAssertNil(VideoService.detect(fromURL: "https://evil-vk.com.ru/video-1_2"))
        XCTAssertNil(VideoService.detect(fromURL: "https://youtube-clone.ru/watch?v=x"))
        XCTAssertNil(VideoService.detect(fromURL: "https://rutube.evil.com/video/x/"))
    }

    /// Резолвер embed-URL: сюда попадает то, что грузится в WebView комнаты.
    func testDetectVideoURLRejectsPhishingHost() {
        let phishing = URL(string: "https://evil-vk.com.ru/video-1_2")!
        XCTAssertNil(
            VideoService.detectVideoURL(phishing, for: .vk, title: "Видео"),
            "Фишинговый хост не должен становиться источником для комнаты"
        )

        let legit = URL(string: "https://vk.com/video-1_2")!
        XCTAssertNotNil(VideoService.detectVideoURL(legit, for: .vk, title: "Видео"))
    }
}
