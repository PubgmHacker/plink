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
//     TEST_RUNNER_PLINK_FUNNEL_BACKEND=http://localhost:8080 \
//     -resultBundlePath /tmp/plink_funnel.xcresult
//

import XCTest
import UIKit

final class FunnelSmokeUITests: XCTestCase {

    private var backendURL: String? {
        guard let raw = ProcessInfo.processInfo.environment["PLINK_FUNNEL_BACKEND"],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let consent = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Принять условия'")
        ).firstMatch
        if consent.waitForExistence(timeout: 3) {
            for _ in 0..<3 {
                if (consent.value as? String) == "Принято" { break }
                consent.tap()
                usleep(500_000)
            }
            XCTAssertEqual(consent.value as? String, "Принято", "Согласие с правилами не включилось")
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
        let authGone = NSPredicate(format: "exists == false")
        expectation(for: authGone, evaluatedWith: createButton)
        waitForExpectations(timeout: 25)
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
        // Ищем кнопку создания комнаты по типовым лейблам.
        let createRoom = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Создать комнату' OR label CONTAINS[c] 'Новая комната' OR label CONTAINS[c] 'Смотреть' OR identifier == 'home.createRoom'")
        ).firstMatch
        if createRoom.waitForExistence(timeout: 10) {
            forceTap(createRoom)
            sleep(3)
            saveShot(app, "ui_04_room_create")

            // Если открылся шит создания — жмём подтверждение.
            let confirm = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Создать' OR label CONTAINS[c] 'Начать'")
            ).firstMatch
            if confirm.exists && confirm.isHittable {
                forceTap(confirm)
                sleep(4)
                saveShot(app, "ui_05_room")
            }
        } else {
            saveShot(app, "ui_04_no_create_room_button")
            XCTFail("Не нашёл кнопку создания комнаты на главном экране — см. ui_03_home.png/ui_04_no_create_room_button.png")
        }
    }
}
