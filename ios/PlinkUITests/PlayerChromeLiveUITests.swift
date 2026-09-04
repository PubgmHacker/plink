//
// PlinkUITests/PlayerChromeLiveUITests.swift
//
// Живая проверка хрома плеера в комнате — то, чего не видит офскрин-рендер
// DesignAuditShots: настоящие отступы устройства, настоящий ящик чата и,
// главное, настоящий hit-testing. Дефект, ради которого написан кейс:
// полоса перемотки уходила под вырез, а звук с полным экраном лежали под
// ящиком чата — сквозь `.ultraThinMaterial` их было видно, но нажать нельзя.
//
// Кейс идёт против ПРОДА (PlinkConfig по умолчанию) и требует живого
// бэкенда — ради автологина. Нет сети — skip, а не красный прогон.
//
// ИСТОЧНИК ВИДЕО ЛОКАЛЬНЫЙ, и это не упрощение, а единственный рабочий
// путь на этой машине. VPN публикует пустой DNS-резолвер, и он же
// primary: CFNetwork симулятора слеп ко всему, чего нет в /etc/hosts —
// встроенный плеер RuTube/YouTube вечно висит на «Загрузка видео…».
// Пока поверхности плеера нет, `PlayerLoadingView` накрывает кадр и
// глотает тап, поэтому хром не появляется вовсе и проверять нечего.
// Прямая mp4-ссылка на loopback уходит в NativePlayerController — то есть
// в НАСТОЯЩИЙ AVPlayer с настоящей длительностью, а хром там ровно тот же
// PlayerControlLayer, что и у встроенных провайдеров. Раздатчик:
//   python3 /tmp/plink-media/serve.py 8799
// (отдаёт Range/206 — без этого AVPlayer не стартует и не перематывает).
//
// Запуск:
//   xcodebuild test -project Plink.xcodeproj -scheme Plink-UITests \
//     -destination 'platform=iOS Simulator,id=<UDID>' \
//     -only-testing:PlinkUITests/PlayerChromeLiveUITests \
//     -resultBundlePath /tmp/plink_player.xcresult
//   xcrun xcresulttool export attachments --path /tmp/plink_player.xcresult \
//     --output-path /tmp/plink-player-shots
//

import XCTest

final class PlayerChromeLiveUITests: XCTestCase {

    /// Тестовый аккаунт: вход без единого тапа (AuthLaunchGate.swift).
    private static let login = "testdev@gmail.com:admin12345:testdev"

    /// Прямая ссылка на локальный mp4 — см. шапку файла. Хост именно
    /// `localhost`, а не публичный: DNS в симуляторе сломан VPN, loopback
    /// его не спрашивает. ATS не мешает — приложение уже ходит на
    /// `http://localhost:8080` в UI-тестовом режиме (PlinkConfig).
    private static let videoLink = "http://localhost:8799/test.mp4"

    /// Раздатчик живой? Проверка идёт из процесса раннера, а он крутится на
    /// том же симуляторе, что и приложение, — значит меряет ровно тот путь,
    /// которым пойдёт AVPlayer. Нет раздатчика — skip, а не красный прогон.
    private func mediaServerIsUp() -> Bool {
        guard let url = URL(string: Self.videoLink) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        var ok = false
        let done = DispatchSemaphore(value: 0)
        URLSession(configuration: .ephemeral).dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 8)
        return ok
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        let att = XCTAttachment(screenshot: app.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Хром гаснет сам через несколько секунд. Тап по кадру (не по центру —
    /// там транспорт, и не по низу — там панель) возвращает его.
    @discardableResult
    private func revealChrome(_ app: XCUIApplication) -> Bool {
        let seek = app.descendants(matching: .any)["player.seek"]
        for _ in 0..<6 {
            if seek.exists && seek.isHittable { return true }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
            usleep(700_000)
        }
        return seek.exists
    }

    /// Комната открывается одним флагом, а не прогулкой по мастеру:
    /// `-plink.designplayer <url>` собирает синтетическую комнату на этой
    /// ссылке и показывает её сразу после автологина (AuthLaunchGate).
    /// Мастер тут не годится принципиально — шаг «прямая ссылка» отдаёт
    /// сервис `.customURL`, а он не `isAvailableInBeta`, и создание честно
    /// упирается в «Выберите видео из доступного сервиса».
    private func launchInRoom() throws -> XCUIApplication {
        guard mediaServerIsUp() else {
            throw XCTSkip("Локальный раздатчик не отвечает: python3 /tmp/plink-media/serve.py 8799")
        }
        let app = XCUIApplication()
        // Без `-plink.uitest`: этот флаг уводит PlinkConfig на localhost:8080,
        // а вход нужен настоящий — с продового бэкенда.
        app.launchArguments = ["-plink.designplayer", Self.videoLink]
        app.launchEnvironment["PLINK_SIM_LOGIN"] = Self.login
        app.launch()

        // Онбординг переживает переустановку — пропускаем, если вылез.
        let skip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Пропустить' OR label CONTAINS[c] 'Skip'")
        ).firstMatch
        if skip.waitForExistence(timeout: 8) {
            forceTap(skip)
            sleep(2)
        }

        let room = app.descendants(matching: .any)["screen.room"]
        guard room.waitForExistence(timeout: 60) else {
            saveShot(app, "live_00_no_room")
            throw XCTSkip("Комната не открылась за 60 с — не прошёл автологин")
        }
        // Ждём НЕ по таймеру: AVPlayer должен реально подняться, иначе
        // `PlayerLoadingView` ещё накрывает кадр и глотает тап по нему —
        // ровно так кейс и падал на встроенном плеере.
        let loading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Загрузка видео'")
        ).firstMatch
        for _ in 0..<30 {
            if !loading.exists { break }
            usleep(700_000)
        }
        if loading.exists {
            saveShot(app, "live_00_stuck_loading")
            throw XCTSkip("Плеер не поднялся — поверхности нет, хром проверять не на чем")
        }
        sleep(2) // дать хрому отрисоваться
        return app
    }

    func testLandscapeChromeClearsNotchAndDrawer() throws {
        let app = try launchInRoom()
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        // ── Портрет: хром на месте ───────────────────────────────────────
        XCTAssertTrue(revealChrome(app), "В портрете не показалась полоса перемотки")
        saveShot(app, "live_01_room_portrait")

        // ── Тап по кнопке хрома достаётся кнопке, а не кадру под ней ─────
        // Поверхность AVPlayer занимает всю сцену и лежит под панелью. Пока
        // на ней висел свой распознаватель, касание уходило в него: панель
        // гасла, кнопка молчала. Проверяем на звуке — у него видимый эффект
        // в самой метке, и он ничего не ломает в комнате.
        let mutePortrait = app.buttons["player.mute"]
        XCTAssertTrue(mutePortrait.waitForExistence(timeout: 8), "Нет кнопки звука")
        let muteLabelPortrait = mutePortrait.label
        mutePortrait.tap()
        usleep(900_000)
        XCTAssertTrue(
            mutePortrait.exists,
            "Хром погас от тапа по кнопке — касание ушло в поверхность плеера"
        )
        XCTAssertNotEqual(
            mutePortrait.label, muteLabelPortrait,
            "Тап по звуку не сработал: было «\(muteLabelPortrait)», стало «\(mutePortrait.label)»"
        )
        mutePortrait.tap() // возвращаем звук
        usleep(600_000)

        let fullscreen = app.buttons["player.fullscreen"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 8), "Нет кнопки полного экрана")
        XCTAssertTrue(fullscreen.isHittable, "Кнопка полного экрана не нажимается в портрете")
        forceTap(fullscreen)
        // Диагностика поворота: чем именно кончился тап — сменой варианта
        // хрома (label) или ничем. Без неё «не повернулось» неотличимо от
        // «тап не дошёл».
        var trace = "после тапа по «Полный экран»:\n"
        for i in 0..<10 {
            usleep(500_000)
            trace += "  \(i): frame=\(app.frame.size) label=\(fullscreen.exists ? fullscreen.label : "—")\n"
            if app.frame.width > app.frame.height { break }
        }
        let traceAtt = XCTAttachment(string: trace)
        traceAtt.name = "rotation_trace"
        traceAtt.lifetime = .keepAlways
        add(traceAtt)

        // ── Ландшафт, ящик закрыт ────────────────────────────────────────
        let screen = app.frame
        XCTAssertGreaterThan(screen.width, screen.height, "Плеер не ушёл в ландшафт — см. live_02")
        XCTAssertTrue(revealChrome(app), "В ландшафте не показалась полоса перемотки")
        saveShot(app, "live_02_landscape")

        let seek = app.descendants(matching: .any)["player.seek"]
        let mute = app.buttons["player.mute"]
        let chat = app.buttons["player.chatToggle"]
        let exitFull = app.buttons["player.fullscreen"]
        for (name, element) in [("полоса перемотки", seek), ("звук", mute),
                                ("чат", chat), ("полный экран", exitFull)] {
            XCTAssertTrue(element.exists, "В ландшафте нет элемента: \(name)")
            XCTAssertTrue(element.isHittable, "В ландшафте не нажимается: \(name)")
        }

        // Вырез и домашняя полоса: хром обязан держаться в стороне.
        // Порог 40 pt — вырез iPhone Pro в ландшафте 59 pt, берём с запасом
        // на разные модели, но заведомо больше нуля (было ровно 0).
        XCTAssertGreaterThanOrEqual(
            seek.frame.minX, 40,
            "Полоса перемотки уходит под вырез: minX=\(seek.frame.minX)"
        )
        XCTAssertLessThanOrEqual(
            seek.frame.maxX, screen.maxX - 40,
            "Полоса перемотки уходит под вырез справа: maxX=\(seek.frame.maxX) при ширине \(screen.width)"
        )
        XCTAssertLessThanOrEqual(
            seek.frame.maxY, screen.maxY - 15,
            "Полоса перемотки лежит на домашней полосе: maxY=\(seek.frame.maxY) при высоте \(screen.height)"
        )

        // ── Ландшафт, ящик открыт ────────────────────────────────────────
        forceTap(chat)
        sleep(2)
        // Ящик ищем по листу-якорю: у контейнера свой идентификатор не
        // держится — `screen.room` с корня комнаты его перебивает
        // (см. LandscapeChatDrawer).
        let drawer = app.descendants(matching: .any)["room.chatDrawerAnchor"]
        if !drawer.waitForExistence(timeout: 8) {
            // Снимок и дерево ДО падения: «ящик не открылся» и «ящик открыт,
            // но не адресуем» с экрана выглядят одинаково.
            saveShot(app, "live_03_no_drawer")
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "hierarchy_no_drawer"
            dump.lifetime = .keepAlways
            add(dump)
            XCTFail("Ящик чата не открылся")
        }
        revealChrome(app)
        saveShot(app, "live_03_landscape_drawer")

        let drawerLeft = drawer.frame.minX
        XCTAssertGreaterThan(drawerLeft, 0, "Ящик занял весь экран — геометрия сломана")

        for (name, element) in [("полоса перемотки", seek), ("звук", mute),
                                ("чат", chat), ("полный экран", exitFull)] {
            XCTAssertTrue(element.exists, "С открытым ящиком пропал элемент: \(name)")
            XCTAssertLessThanOrEqual(
                element.frame.maxX, drawerLeft + 1,
                "\(name) залезает под ящик чата: maxX=\(element.frame.maxX), ящик с \(drawerLeft)"
            )
            XCTAssertTrue(element.isHittable, "С открытым ящиком не нажимается: \(name)")
        }

        // Кнопка звука обязана реально срабатывать, а не только «выглядеть
        // нажимаемой» сквозь стекло ящика — именно это и было сломано.
        let muteLabelBefore = mute.label
        mute.tap() // именно tap, а не тап по координатам: проверяем hit-testing
        usleep(900_000)
        revealChrome(app)
        XCTAssertTrue(mute.exists, "Кнопка звука исчезла после тапа")
        XCTAssertNotEqual(
            mute.label, muteLabelBefore,
            "Тап по звуку рядом с ящиком ничего не изменил — кнопка перекрыта"
        )
        saveShot(app, "live_04_muted_under_drawer")
    }
}
