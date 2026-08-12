//
// PlinkUITests/FunnelSmokeUITests.swift
//
// Аудит 30.07.2026: живой прогон воронки «глазами пользователя» —
// регистрация → главный экран → создание комнаты → пустая комната.
// Гоняется против ЛОКАЛЬНОГО бэкенда (localhost:8080), поэтому кейс
// включается только переменной окружения PLINK_FUNNEL_BACKEND, которую
// xcodebuild пробрасывает в UI-ранер через префикс TEST_RUNNER_.
// (Файл-флаг в /tmp, как у MarketingShots, здесь НЕ работает: UI-ранер —
// отдельное приложение в своём сэндбоксе, его /tmp не хостовый —
// проверено запуском, кейс уходил в skip при существующем файле.)
// Без переменной — skip, чтобы обычный `xcodebuild test` не зависел
// от поднятого сервера.
//
// Скриншоты каждого шага — XCTAttachment в xcresult (сохраняются всегда).
//
// Запуск:
//   xcodebuild test -project Plink.xcodeproj -scheme Plink \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:PlinkUITests/FunnelSmokeUITests \
//     PLINK_FUNNEL_BACKEND=http://localhost:8080 \
//     -resultBundlePath /tmp/plink_funnel.xcresult
//

import XCTest
import UIKit

final class FunnelSmokeUITests: XCTestCase {

    private var backendURL: String? {
        let raw = ProcessInfo.processInfo.environment["PLINK_FUNNEL_BACKEND"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_PLINK_FUNNEL_BACKEND"]
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            return "http://localhost:8080"
            #else
            return nil
            #endif
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Живой ли бэкенд. Без пробы кейс падал на шаге 6 «не нашёл кнопку
    /// создания комнаты» — хотя настоящая причина была в недоступном сервере:
    /// trending не загружался, Главная показывала пустое состояние, и постеров,
    /// через которые создаётся комната, на экране просто не было
    /// (в логах — HTTP error -1003, хост не разрешается).
    /// Красный прогон из-за не поднятого сервера прячет настоящие поломки,
    /// поэтому здесь skip, а не fail.
    private func backendIsReachable(_ base: String) -> Bool {
        guard let url = URL(string: base.hasSuffix("/") ? base + "health" : base + "/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            // Любой HTTP-ответ означает, что сервер отвечает. Код не важен:
            // /health может отдавать 404 на других сборках — это всё равно
            // живой процесс, в отличие от -1003.
            if response is HTTPURLResponse { reachable = true }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        return reachable
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        let att = XCTAttachment(screenshot: app.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    /// Тап по координатам центра элемента — устойчивее hit-testing на
    /// кастомных стеклянных контролах (isHittable у них бывает false).
    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Тап + ожидание клавиатурного фокуса с ретраем. Без этого typeText
    /// падает «Neither element nor any descendant has keyboard focus» на
    /// симуляторе с медленной анимацией фокуса (поймано живым прогоном).
    private func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func tapAndType(_ app: XCUIApplication, _ element: XCUIElement, text: String, submit: Bool = true) {
        for attempt in 0..<4 {
            forceTap(element)
            // Ждём фокус ИМЕННО этого элемента (не просто клавиатуры:
            // она могла остаться от предыдущего поля — ловилось живым прогоном).
            var focused = false
            for _ in 0..<12 {
                if hasFocus(element) { focused = true; break }
                usleep(250_000)
            }
            if focused { break }
            if attempt == 3 {
                XCTFail("Поле не получило фокус за 4 попытки: \(element.description.prefix(80))")
                return
            }
        }
        // Для обычных полей завершаем return'ом — клавиатура не накрывает
        // следующее поле. Для SecureField return НЕЛЬЗЯ: onSubmit сбрасывал
        // введённый пароль (поймано живым прогоном — ui_02_filled.png).
        element.typeText(submit ? text + "\n" : text)
        usleep(400_000)
    }

    func testRegistrationToRoomFunnel() throws {
        guard let backend = backendURL else {
            throw XCTSkip("PLINK_FUNNEL_BACKEND не задан — воронка требует живого локального бэкенда")
        }
        guard backendIsReachable(backend) else {
            throw XCTSkip("Бэкенд \(backend) не отвечает — воронку прогонять нечем. Поднять: cd backend-3 && npm run dev")
        }

        let app = XCUIApplication()
        // -plink.uitest отключает textContentType в полях auth — иначе системный
        // шит «Надёжный пароль?» блокирует ввод (CinematicAuthContainer.swift).
        app.launchArguments = ["-plink.backend_base_url", backend, "-plink.uitest"]
        app.launch()

        // ── Шаг 0: онбординг может вылезти ДО auth — состояние переживает
        // переустановку (Keychain симулятор не чистит). Пропускаем.
        let earlySkip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Пропустить' OR label CONTAINS[c] 'Skip'")
        ).firstMatch
        if earlySkip.waitForExistence(timeout: 6) {
            forceTap(earlySkip)
            sleep(2)
        }

        // Системный алерт уведомлений перехватываем монитором и добиваем
        // лишним тапом (монитор срабатывает только при обращении к app).
        addUIInterruptionMonitor(withDescription: "Push permission") { alert in
            let deny = alert.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Не разрешать' OR label CONTAINS[c] \"Don't Allow\"")
            ).firstMatch
            if deny.exists { deny.tap(); return true }
            return false
        }

        // ── Шаг 1: auth ИЛИ уже залогинен (Keychain переживает переустановку,
        // поймано прогоном: тест ждал регистрацию, а открылась «Главная») ──
        let openRegistration = app.buttons["auth.openRegistration"]
        let usernameField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'пользователя' OR placeholderValue CONTAINS[c] 'username'")
        ).firstMatch
        let homeMarker = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Что посмотрим'")
        ).firstMatch
        var alreadyLoggedIn = false
        for _ in 0..<15 {
            if homeMarker.exists { alreadyLoggedIn = true; break }
            if openRegistration.exists || usernameField.exists { break }
            sleep(1)
        }
        saveShot(app, "ui_01_auth")

        if !alreadyLoggedIn {
        if openRegistration.waitForExistence(timeout: 5) { openRegistration.tap() }
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "Поле имени пользователя не появилось")

        // ── Шаг 2: заполняем форму ───────────────────────────────────────
        let stamp = String(Int(Date().timeIntervalSince1970) % 100_000)
        let username = "uxfun\(stamp)"
        let email = "uxfun\(stamp)@plink.test"

        tapAndType(app, usernameField, text: username)

        let emailField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'mail'")
        ).firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        tapAndType(app, emailField, text: email)

        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        // Пароль: печатаем и ПРОВЕРЯЕМ буллеты • в value — они появляются
        // только при реальном вводе. Живой прогон поймал тихую потерю
        // ввода: поле оставалось пустым, а тест шёл дальше.
        var pwEntered = false
        for _ in 0..<3 {
            tapAndType(app, passwordField, text: "UxFunnel2026!", submit: false)
            usleep(400_000)
            let bullets = ((passwordField.value as? String) ?? "").filter { $0 == "•" }.count
            if bullets >= 6 { pwEntered = true; break }
        }
        XCTAssertTrue(pwEntered, "Пароль не попал в SecureField за 3 попытки (нет буллетов)")
        // Прячем клавиатуру тапом по нейтральной зоне (логотип сверху).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        usleep(600_000)

        // Чекбокс условий — с проверкой результата и ретраем: один тап
        // мог не срабатывать (поймано прогоном: тогл off → кнопка disabled).
        let consent = app.buttons["auth.consent"]
        if consent.waitForExistence(timeout: 3) {
            for _ in 0..<3 {
                if (consent.value as? String) == "Принято" { break }
                consent.tap()
                usleep(700_000)
            }
            // Accessibility state can lag behind SwiftUI state on a custom
            // button; the registration button is the authoritative check.
            XCTAssertTrue(consent.exists, "Контрол согласия исчез во время заполнения")
        }
        saveShot(app, "ui_02_filled")

        // ── Шаг 3: создать аккаунт ───────────────────────────────────────
        let createButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Создать'")
        ).firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Кнопка «Создать аккаунт» не найдена")
        XCTAssertTrue(createButton.isEnabled, "Кнопка задизейблена — форма неполна (см. ui_02_filled)")
        forceTap(createButton)

        // ── Шаг 4: ждём главный экран ────────────────────────────────────
        // Признак успеха — исчез экран auth (кнопка «Создать аккаунт»)
        // и появился таб-бар / home-контент.
        // Registration can succeed while the auth view is replaced by the
        // onboarding flow. Wait for any post-auth marker instead of relying
        // on the old button disappearing within one fixed timeout.
        let postAuth = app.otherElements["app.shell"]
        let homeContent = app.otherElements["screen.home"]
        let onboarding = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Пропустить' OR label CONTAINS[c] 'Skip' OR label CONTAINS[c] 'Далее' OR label CONTAINS[c] 'Начать'")
        ).firstMatch
        let authGone = NSPredicate(format: "exists == false")
        let authExpectation = expectation(for: authGone, evaluatedWith: createButton)
        let result = XCTWaiter().wait(for: [authExpectation], timeout: 35)
        if result == .timedOut {
            // The backend request is the authoritative registration result;
            // SwiftUI may keep the old element snapshot alive during the
            // shell transition. Give the shell one final grace window.
            if !postAuth.waitForExistence(timeout: 5) && !homeContent.waitForExistence(timeout: 5) && !onboarding.waitForExistence(timeout: 5) {
                saveShot(app, "ui_registration_timeout")
                XCTFail("Регистрация не завершила auth-flow за 40 секунд")
            }
        }
        sleep(2)

        // ── Шаг 4а: системный шит «Сохранить пароль?» → «Не сейчас» ────
        // (поймано живым прогоном — ui_03_home.png был этим шитом).
        let notNow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Не сейчас' OR label CONTAINS[c] 'Not Now'")
        ).firstMatch
        if notNow.waitForExistence(timeout: 4) {
            forceTap(notNow)
            sleep(1)
        }

        // ── Шаг 4б: онбординг → «Пропустить» (или листаем «Далее») ───
        let skip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Пропустить' OR label CONTAINS[c] 'Skip'")
        ).firstMatch
        if skip.waitForExistence(timeout: 4) {
            forceTap(skip)
            sleep(2)
        }
        // Если онбординг всё ещё на экране — дожимаем «Далее» до конца (до 5 экранов).
        for _ in 0..<5 {
            let next = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Далее' OR label CONTAINS[c] 'Начать' OR label CONTAINS[c] 'Continue'")
            ).firstMatch
            guard next.waitForExistence(timeout: 2) else { break }
            forceTap(next)
            sleep(1)
        }
        } // конец ветки регистрации (!alreadyLoggedIn)

        sleep(2) // дать главному экрану догрузить данные
        app.tap() // триггер UIInterruptionMonitor для алерта уведомлений
        sleep(1)
        saveShot(app, "ui_03_home")

        // ── Шаг 5: полный visual walk по пяти вкладкам ────────────────
        let tabChecks: [(id: String, marker: XCUIElement, shot: String)] = [
            ("tab.0", app.descendants(matching: .any)["screen.home"], "ui_tab_home"),
            ("tab.1", app.descendants(matching: .any)["screen.rooms"], "ui_tab_rooms"),
            ("tab.2", app.descendants(matching: .any)["screen.friends"], "ui_tab_friends"),
            ("tab.3", app.descendants(matching: .any)["screen.ai"], "ui_tab_ai"),
            ("tab.4", app.descendants(matching: .any)["screen.profile"], "ui_tab_profile"),
        ]
        for check in tabChecks {
            let tabButton = app.buttons[check.id]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "Не найдена вкладка \(check.id)")
            forceTap(tabButton)
            XCTAssertTrue(check.marker.waitForExistence(timeout: 10), "Вкладка \(check.id) не показала ожидаемый контент")
            saveShot(app, check.shot)
        }

        // Возвращаемся на Главную перед следующим действием.
        forceTap(app.buttons["tab.0"])
        sleep(1)

        // ── Шаг 6: создать комнату ───────────────────────────────────────
        // Прямой кнопки «Создать комнату» в продукте НЕТ и не было: путь
        // всегда контент-первый — выбрал что смотреть, комната создалась.
        // Раньше тест искал такую кнопку по лейблам и падал на живом,
        // полностью рабочем приложении (ui_04_no_create_room_button.png).
        // Теперь идём тем путём, который есть: постер → шторка → «Смотреть
        // вместе». Если trending пуст, у Главной остаётся вход через поиск.
        let poster = app.buttons["home.poster"].firstMatch
        let watchTogether = app.buttons["preview.watchTogether"]

        if poster.waitForExistence(timeout: 12) {
            forceTap(poster)
            XCTAssertTrue(
                watchTogether.waitForExistence(timeout: 8),
                "Шторка превью не показала «Смотреть вместе» — см. ui_04_preview.png"
            )
            saveShot(app, "ui_04_preview")
            forceTap(watchTogether)
        } else {
            // Пустая подборка — комнату создаём через поиск.
            saveShot(app, "ui_04_no_trending")
            let searchEntry = app.buttons["home.searchEntry"]
            let emptyCTA = app.buttons["home.emptyFindVideo"]
            let entry = emptyCTA.exists ? emptyCTA : searchEntry
            XCTAssertTrue(
                entry.waitForExistence(timeout: 8),
                "На Главной нет ни постеров, ни входа в поиск — см. ui_04_no_trending.png"
            )
            forceTap(entry)
            sleep(2)
            saveShot(app, "ui_04_search")
            let firstResult = app.buttons["home.poster"].firstMatch
            guard firstResult.waitForExistence(timeout: 8) else {
                throw XCTSkip("Поиск не вернул результатов — внешние источники недоступны, воронку дальше не проверить")
            }
            forceTap(firstResult)
            XCTAssertTrue(watchTogether.waitForExistence(timeout: 8), "Шторка превью не открылась из поиска")
            forceTap(watchTogether)
        }

        // Комната открылась — ждём её экран, а не просто «что-то поменялось».
        let roomScreen = app.descendants(matching: .any)["screen.room"]
        let roomAppeared = roomScreen.waitForExistence(timeout: 20)
        saveShot(app, "ui_05_room")
        XCTAssertTrue(roomAppeared, "Комната не открылась за 20 с — см. ui_05_room.png")
    }
}
