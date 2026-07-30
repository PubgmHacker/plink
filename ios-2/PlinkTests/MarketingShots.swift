// PlinkTests/MarketingShots.swift — рендер продуктовых кадров для лендинга.
//
// Это НЕ регрессионный тест: он ничего не проверяет пиксельно, а собирает
// живые продуктовые вьюхи с моковыми данными и складывает PNG на диск, чтобы
// на сайте стояли настоящие кадры приложения, а не CSS-макеты.
//
// Кейс выключен по умолчанию (как ThemeSnapshotTests) и включается одним из
// двух способов:
//
//  1) переменные окружения MARKETING_SHOTS=1 и MARKETING_SHOTS_DIR=<путь>
//     — работают, если запускать бандл напрямую или прописать их в схеме;
//
//  2) файл-флаг /tmp/plink-marketing-shots на хосте — внутри лежит абсолютный
//     путь каталога для PNG (пустой файл → /tmp/plink-marketing-shots-output).
//
// Второй способ нужен потому, что `xcodebuild test` НЕ пробрасывает окружение
// оболочки в процесс на симуляторе: переменные до теста не долетают
// (проверено — кейсы уходили в skip). Флаг лежит именно в /tmp: приложение
// в симуляторе — обычный процесс macOS, и чтение файла из ~/Desktop или
// ~/Documents вешает тест на системном запросе доступа (TCC).
//
// Запуск:
//   cd ios-2 && xcodegen generate
//   echo /абсолютный/путь/для/PNG > /tmp/plink-marketing-shots
//   xcodebuild test -scheme Plink \
//     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//     -only-testing:PlinkTests/MarketingShots
//   rm /tmp/plink-marketing-shots   # иначе кадры снимаются каждый прогон
//
// Что снимается:
//   room-watching.png — комната во время просмотра (плеер-хром, пилюля
//                       синхрона, участники, полоса перемотки, чат, реакции)
//   room-chat.png     — та же комната с раскрытым чатом
//   friends.png       — живой экран «Друзья» (V4FriendsViewLive)
//   themes.png        — живой экран «Оформление» (V4AppearanceView)
//
// Реализация намеренно опирается на настоящие продуктовые компоненты
// (PlayerTopChrome, PlinkPlayerControls, PresenceBar, WatchChatView,
// WatchChatComposer, WatchReactionLayer, V4FriendsViewLive, V4AppearanceView).
// Подменяется только то, что физически невозможно отрендерить офскрин:
// пиксели видео (берётся кадр из бандл-ассета через AVAssetImageGenerator).

import XCTest
import SwiftUI
import UIKit
import AVFoundation
@testable import Plink

@MainActor
final class MarketingShots: XCTestCase {

    // MARK: - Конфигурация кадра

    /// Логический размер экрана iPhone 17 Pro.
    private static let canvas = CGSize(width: 402, height: 874)
    private static let scale: CGFloat = 3
    /// Комната — почти во весь экран: пустая чёрная полоса под вырезом на
    /// кадре без статус-бара читается как дефект.
    private static let roomSafeArea = UIEdgeInsets(top: 12, left: 0, bottom: 10, right: 0)
    /// Обычные экраны с шапкой — обычные отступы устройства.
    private static let screenSafeArea = UIEdgeInsets(top: 44, left: 0, bottom: 20, right: 0)

    private static let meId = "u-timur"
    private static let meName = "Тимур"

    // MARK: - Gate

    /// Файл-флаг на хосте (см. шапку файла).
    ///
    /// Путь ДОЛЖЕН лежать вне TCC-защищённых каталогов (~/Desktop, ~/Documents,
    /// ~/Downloads): приложение в симуляторе — это обычный процесс macOS, и
    /// `open()` такого файла подвешивает тест на системном запросе доступа.
    /// Поэтому здесь /tmp, а не путь из #filePath.
    private static let flagFile = URL(fileURLWithPath: "/tmp/plink-marketing-shots")

    private static var flagContents: String? {
        guard let raw = try? String(contentsOf: flagFile, encoding: .utf8) else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["MARKETING_SHOTS"] == "1" { return true }
        return flagContents != nil
    }

    private func requireEnabled() throws {
        try XCTSkipUnless(
            Self.isEnabled,
            """
            Кадры для лендинга снимаются по требованию. Включи одним из способов:
            MARKETING_SHOTS=1 (+ MARKETING_SHOTS_DIR) или файл
            /tmp/plink-marketing-shots с путём выходного каталога внутри.
            """
        )
    }

    private var outputDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["MARKETING_SHOTS_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let flag = Self.flagContents, !flag.isEmpty {
            return URL(fileURLWithPath: flag, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/plink-marketing-shots-output", isDirectory: true)
    }

    // MARK: - Сохранение/восстановление глобального состояния

    private var savedDefaults: [String: Any?] = [:]
    private static let touchedKeys = [
        "plink_current_user_id",
        "rave_saved_user",
        "plink_app_language",
        "plink.liveTheme",
        "plink.v4ThemeName",
        "plink.bubbleStyleID",
        "rave_room_theme",
    ]

    override func setUp() async throws {
        try await super.setUp()
        guard Self.isEnabled else { return }
        let defaults = UserDefaults.standard
        for key in Self.touchedKeys { savedDefaults[key] = defaults.object(forKey: key) }
        savedDefaults[Self.friendsCacheKey] = defaults.object(forKey: Self.friendsCacheKey)
        LocalizationManager.shared.currentLanguage = .russian
    }

    override func tearDown() async throws {
        let defaults = UserDefaults.standard
        for (key, value) in savedDefaults {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        savedDefaults.removeAll()
        try await super.tearDown()
    }

    // MARK: - 1. Комната во время просмотра (главный кадр)

    func testRoomWatchingShot() async throws {
        try requireEnabled()

        let model = makeRoomModel()
        try? await prepareTimeline(for: model, duration: 3130, position: 1104)

        let reactions = MarketingReactionBox()
        let stage = try mount(
            MarketingRoomView(
                model: model,
                videoFrame: Self.videoFrame(),
                controlsVisible: true,
                reactions: reactions
            ),
            safeArea: Self.roomSafeArea
        )
        defer { stage.dismiss() }

        await settle(0.7)
        seedChat(model, Self.longConversation)
        await settle(0.45)
        await stageReactions(reactions)

        try await capture(stage, named: "room-watching")
    }

    // MARK: - 2. Комната с раскрытым чатом

    func testRoomChatShot() async throws {
        try requireEnabled()

        let model = makeRoomModel()
        try? await prepareTimeline(for: model, duration: 3130, position: 1547)

        let stage = try mount(
            MarketingRoomChatView(model: model, videoFrame: Self.videoFrame()),
            safeArea: Self.roomSafeArea
        )
        defer { stage.dismiss() }

        await settle(0.7)
        seedChat(model, Self.longConversation)
        await settle(0.6)

        try await capture(stage, named: "room-chat")
    }

    // MARK: - 3. Друзья

    func testFriendsShot() async throws {
        try requireEnabled()

        let store = try await makeFriendsStore()
        let stage = try mount(MarketingFriendsView(store: store), safeArea: Self.screenSafeArea)
        defer { stage.dismiss() }

        // Экран сам дозагружает список на .onAppear — ждём, пока спиннер уйдёт.
        let deadline = Date().addingTimeInterval(10)
        while store.state == .loading, Date() < deadline { await settle(0.1) }
        await settle(0.9)
        XCTAssertNotEqual(store.state, .loading, "В кадре «Друзья» остался спиннер загрузки")
        try await capture(stage, named: "friends")
    }

    // MARK: - 4. Темы (Оформление / Plink+)

    func testThemesShot() async throws {
        try requireEnabled()

        // Живые темы Plink+ гаснут без подписки — для кадра показываем их
        // в разблокированном виде и откатываем состояние сразу после съёмки.
        let premium = PremiumStatusManager.shared
        let wasPremium = premium.isPremium
        premium.activatePremium(expiryDate: Date().addingTimeInterval(60 * 60 * 24 * 30))
        defer { if !wasPremium { premium.deactivatePremium() } }

        UserDefaults.standard.set(0, forKey: "plink.liveTheme")

        let stage = try mount(MarketingThemesView(), safeArea: Self.screenSafeArea)
        defer { stage.dismiss() }

        await settle(1.1)
        try await capture(stage, named: "themes")
    }

    // MARK: - Данные комнаты

    private struct Line {
        let senderId: String
        let senderName: String
        let text: String
    }

    // Живой бабл (PlinkEmojiFlowLayout) меряет текст без переноса, поэтому
    // длинные реплики уезжают за край экрана. Держим строки короткими —
    // это ограничение продукта, а не кадра.
    private static let longConversation: [Line] = [
        Line(senderId: "u-anya", senderName: "Аня", text: "Наконец-то! Я думала, начнёте"),
        Line(senderId: "u-kirill", senderName: "Кирилл", text: "Звук у всех нормальный?"),
        Line(senderId: meId, senderName: meName, text: "Да, всё слышно 👌"),
        Line(senderId: "u-marina", senderName: "Марина", text: "Это мой любимый момент"),
        Line(senderId: "u-anya", senderName: "Аня", text: "Тише, сейчас будет"),
        Line(senderId: "u-kirill", senderName: "Кирилл", text: "Я к такому не готов 😅"),
        Line(senderId: meId, senderName: meName, text: "Обсудим после титров"),
        Line(senderId: "u-marina", senderName: "Марина", text: "У меня есть теория!"),
    ]

    private func makeRoomModel() -> WatchRoomModel {
        let model = WatchRoomModel(
            roomId: "room-marketing",
            currentUserId: Self.meId,
            currentUsername: Self.meName,
            baseEndpoint: URL(string: "ws://127.0.0.1:9/ws")!,
            ticketProvider: { _ in throw URLError(.cannotConnectToHost) },
            mediaSource: nil,
            mediaId: "demo-media",
            roomCode: "PLNK42",
            chatCatchupClient: nil,
            clock: nil,
            coordinator: nil,
            roomHostId: Self.meId
        )
        // Хост-сессия: контролы активны, пилюля синхрона зелёная.
        model.sessionDidConnect(role: .host)
        for (id, name) in [("u-anya", "Аня"), ("u-kirill", "Кирилл"), ("u-marina", "Марина")] {
            model.handleOtherMessage(.participantJoined(.init(
                type: "participant.joined",
                protocolVersion: 2,
                roomId: "room-marketing",
                userId: id,
                username: name,
                joinedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                leftAtMs: nil
            )))
        }
        return model
    }

    private func seedChat(_ model: WatchRoomModel, _ lines: [Line]) {
        var stamp = Int64(Date().timeIntervalSince1970 * 1000) - Int64(lines.count) * 45_000
        for (index, line) in lines.enumerated() {
            model.handleOtherMessage(.chatBroadcast(.init(
                type: "chat.broadcast",
                protocolVersion: 2,
                roomId: "room-marketing",
                messageId: "m-\(index)",
                clientMessageId: nil,
                senderId: line.senderId,
                senderName: line.senderName,
                text: line.text,
                createdAtMs: stamp,
                mediaType: nil,
                hasMedia: nil
            )))
            stamp += 45_000
        }
    }

    /// Реакции летят снизу вверх, а стартовая X у `WatchReactionEvent`
    /// случайная. Для кадра подбираем события с нужной X и выпускаем их
    /// с паузами: высота полёта считается от `receivedAt`, поэтому к моменту
    /// съёмки три эмодзи оказываются на разной высоте внутри вьюпорта видео.
    private func stageReactions(_ box: MarketingReactionBox) async {
        // Полёт реакции длится 2.5 с и дальше упирается в потолок формулы
        // (progress = 1). Выдерживаем паузу больше 2.5 с — тогда высота
        // перестаёт зависеть от того, в какую миллисекунду сделан снимок,
        // и кадр воспроизводится стабильно. По горизонтали разносим сами.
        let plan: [(String, String, String, ClosedRange<CGFloat>, TimeInterval)] = [
            ("u-anya", "Аня", "❤️", 0.54...0.60, 0.10),
            ("u-kirill", "Кирилл", "🔥", 0.69...0.75, 0.10),
            ("u-marina", "Марина", "😂", 0.84...0.90, 3.10),
        ]
        for (userId, username, emoji, xRange, pause) in plan {
            box.events.append(Self.reaction(userId: userId, username: username, emoji: emoji, startX: xRange))
            await settle(pause)
        }
        // Высота полёта считается в момент отрисовки слоя, а перерисовку
        // вызывает только изменение массива. Снимок берётся с последнего
        // закоммиченного кадра, поэтому «тычок» должен быть настоящим
        // элементом: добавляем пустую (невидимую) реакцию — она заставляет
        // слой перерисоваться уже с нужными высотами.
        box.events.append(Self.reaction(userId: "u-timur", username: "Тимур", emoji: "", startX: 0...1))
        await settle(0.08)
    }

    /// `startX` у события рандомная и readonly — подбираем экземпляр,
    /// попавший в нужный диапазон.
    private static func reaction(
        userId: String, username: String, emoji: String, startX: ClosedRange<CGFloat>
    ) -> WatchReactionEvent {
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        var fallback = WatchReactionEvent(userId: userId, username: username, emoji: emoji, timestampMs: stamp)
        for _ in 0..<2000 {
            let candidate = WatchReactionEvent(userId: userId, username: username, emoji: emoji, timestampMs: stamp)
            if startX.contains(candidate.startX) { return candidate }
            fallback = candidate
        }
        return fallback
    }

    /// Кладёт под координатор настоящий AVPlayer с синтетическим длинным
    /// роликом, чтобы продуктовая панель управления показала осмысленные
    /// таймкоды и заполненную полосу перемотки, а не «0:00 / 0:00».
    private func prepareTimeline(for model: WatchRoomModel, duration: Double, position: Double) async throws {
        let url = try await Self.makeSilentTimelineVideo(duration: duration)
        // Прогреваем разбор контейнера до подключения к AVPlayer, иначе на
        // свежесозданном файле айтем задерживается в .unknown и панель
        // управления успевает сняться с нулевой длительностью.
        _ = try? await AVURLAsset(url: url).load(.duration)
        try await model.coordinator.prepare(.mp4(url, headers: [:]))

        // Просто присоединённый к AVPlayer айтем остаётся в .unknown: статус
        // (а значит и duration в контроллере) появляется только когда плеер
        // реально начинает воспроизведение. Поэтому сначала play(), потом
        // ждём duration, и только затем перематываем в нужную точку.
        await model.coordinator.currentController?.play()

        let deadline = Date().addingTimeInterval(25)
        while model.coordinator.duration <= 0, Date() < deadline { await settle(0.05) }

        _ = await model.coordinator.currentController?.seek(to: position, precise: true)
        await model.coordinator.currentController?.play()

        let seekDeadline = Date().addingTimeInterval(4)
        while model.coordinator.position < position - 1, Date() < seekDeadline { await settle(0.05) }
        let item = model.coordinator.nativePlayer?.currentItem
        print("""
        MARKETING_TIMELINE duration=\(model.coordinator.duration) \
        position=\(model.coordinator.position) \
        itemStatus=\(item?.status.rawValue ?? -1) \
        itemDuration=\(item.map { CMTimeGetSeconds($0.duration) } ?? -1) \
        itemError=\(String(describing: item?.error))
        """)
    }

    // MARK: - Данные друзей

    private static let friendsCacheKey = "plink.friends.cache.v1." + meId

    private func makeFriendsStore() async throws -> V4FriendsStore {
        let defaults = UserDefaults.standard
        defaults.set(Self.meId, forKey: "plink_current_user_id")

        let now = Date()
        let cached: [Friend] = [
            Friend(id: "u-anya", username: "anya", avatarURL: nil, isOnline: true,
                   friendsSince: now.addingTimeInterval(-86_400 * 120),
                   displayName: "Аня", lastSeenAt: now),
            Friend(id: "u-kirill", username: "kirill", avatarURL: nil, isOnline: true,
                   friendsSince: now.addingTimeInterval(-86_400 * 64),
                   displayName: "Кирилл", lastSeenAt: now),
            Friend(id: "u-marina", username: "marina", avatarURL: nil, isOnline: true,
                   friendsSince: now.addingTimeInterval(-86_400 * 31),
                   displayName: "Марина", lastSeenAt: now),
            Friend(id: "u-lev", username: "lev", avatarURL: nil, isOnline: false,
                   friendsSince: now.addingTimeInterval(-86_400 * 210),
                   displayName: "Лев", lastSeenAt: now.addingTimeInterval(-2_400)),
            Friend(id: "u-dasha", username: "dasha", avatarURL: nil, isOnline: false,
                   friendsSince: now.addingTimeInterval(-86_400 * 15),
                   displayName: "Даша", lastSeenAt: now.addingTimeInterval(-86_400)),
            Friend(id: "u-oleg", username: "oleg", avatarURL: nil, isOnline: false,
                   friendsSince: now.addingTimeInterval(-86_400 * 9),
                   displayName: "Олег", lastSeenAt: now.addingTimeInterval(-3 * 86_400)),
        ]
        defaults.set(try JSONEncoder().encode(cached), forKey: Self.friendsCacheKey)

        // Локальный APIClient в никуда: запрос падает транспортной ошибкой,
        // и FriendManager честно поднимает офлайн-снимок из кэша.
        let api = APIClient(baseURL: "http://127.0.0.1:9/api")
        api.authToken = "marketing-shot"
        let manager = FriendManager(api: api)
        let store = V4FriendsStore(friendManager: manager)
        await store.load()

        // Кэш гасит presence — возвращаем «в сети» тем, кто должен светиться.
        for id in ["u-anya", "u-kirill", "u-marina"] {
            manager.noteActivity(friendId: id, at: Date())
        }
        await store.refreshQuietly()

        // Экран на .onAppear зовёт load() ещё раз. Без токена запрос не
        // уходит вовсе: уже загруженный список сохраняется, а состояние
        // мгновенно становится .loaded — иначе в кадре висит спиннер.
        api.authToken = nil
        return store
    }

    // MARK: - Кадр видео

    private static var cachedVideoFrame: UIImage?

    /// Ресурсы из `Resources/Banners` копируются в бандл ПЛОСКО (без папки),
    /// поэтому ищем и с подкаталогом, и без него.
    private static func bundledResource(_ name: String, _ ext: String, _ folder: String) -> URL? {
        let bundle = Bundle(for: PlaybackCoordinator.self)
        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: folder)
    }

    private static func videoFrame() -> UIImage? {
        if let cachedVideoFrame { return cachedVideoFrame }
        if let url = bundledResource("hero_banner_watch_together", "mp4", "Banners") {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            if let cgImage = try? generator.copyCGImage(
                at: CMTime(seconds: 3.0, preferredTimescale: 600), actualTime: nil
            ) {
                cachedVideoFrame = UIImage(cgImage: cgImage)
                return cachedVideoFrame
            }
        }
        if let url = bundledResource("hero_banner_watch_together_poster", "png", "Banners"),
           let data = try? Data(contentsOf: url) {
            cachedVideoFrame = UIImage(data: data)
            return cachedVideoFrame
        }
        // Последний рубеж: собственная кинематографичная заливка, чтобы
        // вьюпорт плеера никогда не превратился в чёрный прямоугольник.
        cachedVideoFrame = syntheticCinematicFrame()
        return cachedVideoFrame
    }

    /// Мягкое бирюзовое свечение с виньеткой — собственная графика, рисуется
    /// кодом. Используется только если ассет из бандла недоступен.
    private static func syntheticCinematicFrame() -> UIImage {
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.02, green: 0.05, blue: 0.06, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            let space = CGColorSpaceCreateDeviceRGB()
            let glow = CGGradient(colorsSpace: space, colors: [
                UIColor(red: 0.24, green: 0.86, blue: 0.75, alpha: 0.85).cgColor,
                UIColor(red: 0.08, green: 0.38, blue: 0.42, alpha: 0.35).cgColor,
                UIColor(red: 0.01, green: 0.04, blue: 0.05, alpha: 0).cgColor,
            ] as CFArray, locations: [0, 0.45, 1])!
            cg.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.44), startRadius: 0,
                endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.44), endRadius: size.width * 0.55,
                options: []
            )

            let vignette = CGGradient(colorsSpace: space, colors: [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.85).cgColor,
            ] as CFArray, locations: [0.35, 1])!
            cg.drawRadialGradient(
                vignette,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width * 0.72,
                options: []
            )
        }
    }

    /// Немой h264-ролик заданной длительности (кадр раз в 5 секунд).
    /// Нужен только ради честных duration/position у AVPlayer — картинка
    /// из него никогда не показывается.
    private static func makeSilentTimelineVideo(duration: Double) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plink-marketing-timeline-v2-\(Int(duration)).mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        try await Task.detached(priority: .userInitiated) {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 180,
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 320,
                    kCVPixelBufferHeightKey as String: 180,
                ]
            )
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? URLError(.cannotCreateFile) }
            writer.startSession(atSourceTime: .zero)

            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pixelBuffer = buffer else { throw URLError(.cannotCreateFile) }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * 180)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            var seconds: Double = 0
            while seconds <= duration {
                while !input.isReadyForMoreMediaData { usleep(500) }
                adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600))
                seconds += 5
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            if writer.status != .completed { throw writer.error ?? URLError(.cannotCreateFile) }
        }.value

        return url
    }

    // MARK: - Рендер

    /// Живое окно поверх хост-приложения: только так `drawHierarchy`
    /// корректно снимает `.ultraThinMaterial` и прочие визуальные эффекты.
    private final class Stage {
        let window: UIWindow
        let host: UIViewController
        init(window: UIWindow, host: UIViewController) {
            self.window = window
            self.host = host
        }
        @MainActor func dismiss() {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
    }

    private func mount(_ view: some View, safeArea: UIEdgeInsets = .zero) throws -> Stage {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window: UIWindow = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.canvas))
        window.frame = CGRect(origin: .zero, size: Self.canvas)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .normal + 10

        // .frame(width:height:) на корне гарантирует, что SwiftUI предлагает
        // детям ровно 402pt по ширине, чем бы ни оказалась сцена симулятора.
        let host = UIHostingController(
            rootView: view
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        // Safe area приходит от реальной сцены симулятора (вырез + домашний
        // индикатор). additionalSafeAreaInsets тут НЕ нужен — он складывается
        // с системным и удваивает отступы.

        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        window.frame = CGRect(origin: .zero, size: Self.canvas)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Нормализуем safe area до запрошенной: additionalSafeAreaInsets
        // складывается с системной, поэтому вычитаем то, что уже есть.
        let ambient = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, safeArea.top - ambient.top),
            left: 0,
            bottom: max(0, safeArea.bottom - ambient.bottom),
            right: 0
        )
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        XCTAssertEqual(host.view.bounds.size, Self.canvas,
                       "Хост-вью должен быть ровно 402x874pt, иначе кадр обрежется")
        return Stage(window: window, host: host)
    }

    /// Отдаёт главный поток рантайму, чтобы SwiftUI успел прогнать
    /// .task/.onAppear и анимации, а AVFoundation — довести айтем до
    /// readyToPlay. Вложенный RunLoop.run здесь не годится: он держит
    /// главный поток и AVPlayer так и остаётся в .unknown.
    private func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    private func capture(_ stage: Stage, named name: String) async throws {
        stage.host.view.setNeedsLayout()
        stage.host.view.layoutIfNeeded()
        await settle(0.1)
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        format.opaque = true
        format.preferredRange = .standard

        let bounds = CGRect(origin: .zero, size: Self.canvas)
        let renderer = UIGraphicsImageRenderer(size: Self.canvas, format: format)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            // afterScreenUpdates: false — снимаем уже закоммиченный кадр.
            // С true UIKit ждёт следующий цикл отрисовки, SwiftUI успевает
            // пересчитать анимации (реакции уезжают вверх на ~1.5 с полёта),
            // и кадр расходится с тем, что подготовил тест.
            stage.host.view.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        guard let data = image.pngData() else {
            XCTFail("Не удалось закодировать PNG для \(name)")
            return
        }
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name).png")
        try data.write(to: file, options: .atomic)

        XCTAssertGreaterThan(data.count, 20_000, "Кадр \(name) подозрительно пустой")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MARKETING_SHOT \(file.path) \(data.count) bytes \(Int(image.size.width * Self.scale))x\(Int(image.size.height * Self.scale))")
    }
}

// MARK: - Композиции кадров

/// Держатель реакций для кадра: тест выпускает их с паузами уже после того,
/// как экран смонтирован, — высота полёта считается от времени получения.
private final class MarketingReactionBox: ObservableObject {
    @Published var events: [WatchReactionEvent] = []
}

/// Портретная комната: та же сборка, что и в `PortraitWatchLayout`, но
/// пиксели видео берутся из готового кадра — офскрин AVPlayer-слой снять
/// невозможно.
private struct MarketingRoomView: View {
    let model: WatchRoomModel
    let videoFrame: UIImage?
    @ObservedObject var reactions: MarketingReactionBox
    @State private var ui: WatchRoomUIState

    init(model: WatchRoomModel, videoFrame: UIImage?, controlsVisible: Bool, reactions: MarketingReactionBox) {
        self.model = model
        self.videoFrame = videoFrame
        self.reactions = reactions
        var state = WatchRoomUIState()
        state.controlsVisible = controlsVisible
        _ui = State(initialValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            MarketingPlayerSurface(videoFrame: videoFrame)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if ui.controlsVisible {
                        ZStack {
                            LinearGradient(
                                colors: [Color.black.opacity(0.55), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 80)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .allowsHitTesting(false)

                            PlayerTopChrome(model: model, variant: .portrait)
                            PlinkPlayerControls(model: model, ui: $ui, variant: .portrait)
                        }
                    }
                }
                // Слой реакций — настоящий продуктовый `WatchReactionLayer`.
                // Вешаем его именно на вьюпорт видео: тогда его система
                // координат — ровно кадр 16:9, эмодзи гарантированно летят
                // по видео и не садятся на имена в чате.
                .overlay {
                    WatchReactionLayer(events: reactions.events, reduceMotion: false)
                        // Потолок полёта — 20% высоты слоя от верха кадра, то
                        // есть у самого верхнего хрома. Сдвигаем полосу вниз,
                        // в середину видео, где эмодзи ничего не перекрывают.
                        .offset(y: 78)
                        .allowsHitTesting(false)
                }
                .clipped()

            PresenceBar(model: model)

            WatchChatView(model: model)
                .frame(maxHeight: .infinity)

            WatchChatComposer(model: model)
        }
        .background(Cinema2026.background)
    }
}

/// Комната с раскрытым чатом — повторяет продуктовую презентацию
/// `WatchChatSheet` (детент .medium/.large) поверх плеера.
private struct MarketingRoomChatView: View {
    let model: WatchRoomModel
    let videoFrame: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                MarketingPlayerSurface(videoFrame: videoFrame)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Cinema2026.background)
            .overlay(Color.black.opacity(0.32).ignoresSafeArea())

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)
                    .padding(.bottom, 6)

                WatchChatView(model: model)
                    .frame(maxHeight: .infinity)

                WatchChatComposer(model: model)
            }
            .frame(height: 612)
            .background(Cinema2026.background)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 14,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.6), radius: 18, y: -6)
        }
    }
}

/// Чёрный вьюпорт плеера с кадром видео — прямой аналог `PlayerStage`
/// без декора (та же плоская чёрная подложка, тот же clipped()).
private struct MarketingPlayerSurface: View {
    let videoFrame: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let videoFrame {
                Image(uiImage: videoFrame)
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

/// Экран «Друзья» так, как он живёт в приложении: живой фон темы, сам
/// `V4FriendsViewLive` и продуктовый таб-бар снизу.
private struct MarketingFriendsView: View {
    let store: V4FriendsStore
    @State private var tab = 2

    var body: some View {
        ZStack {
            V4LivingBackground(theme: .plink).ignoresSafeArea()
            V4FriendsViewLive(theme: .plink, store: store, roomsStore: nil, isActive: false)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                PlinkLiquidTabBar(selection: $tab, theme: .plink, friendsUnread: 0)
            }
        }
        .background(V4.canvas)
    }
}

/// Обёртка над живым экраном «Оформление» — ему нужны биндинги темы.
private struct MarketingThemesView: View {
    @State private var theme: V4Theme = .plink
    @State private var presented = true

    var body: some View {
        V4AppearanceView(theme: $theme, presented: $presented)
    }
}
