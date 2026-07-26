# Plink M39 — интеграция iOS

## 1. Файлы оверлея

| Файл | Действие |
| --- | --- |
| `Core/Haptics.swift` | Добавить |
| `Core/AuthTokenStore.swift` | Добавить (мигрирует старый ключ `rave_auth_token`) |
| `Services/ClockSync.swift` | Добавить |
| `Services/PlaybackSyncEngine.swift` | Добавить |
| `Services/MediaSourceResolver.swift` | Заменяет старую логику распознавания ссылок |
| `Services/ModerationService.swift` | Добавить |
| `Services/PushNotificationService.swift` | Добавить |
| `Services/StoreKitManager.swift` | Добавить |
| `Services/AIStreamClient.swift` | Заменяет прямые SSE-вызовы в AIService |
| `Views/PaywallView.swift` | Заменяет прежний пейволл |
| `Views/ModerationViews.swift` | Добавить |
| `Views/AccountDeletionView.swift` | Добавить |
| `Views/StateViews.swift` | Добавить |
| `Views/OnboardingView.swift` | Заменяет старый онбординг |

## 2. Точки встраивания

### PlinkApp.swift

```swift
@main
struct PlinkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showEULA = !ModerationService.shared.hasAcceptedEULA

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    Haptics.prepare()
                    await ClockSync.shared.sync()
                    await StoreKitManager.shared.refreshEntitlements()
                    await PushNotificationService.shared.refreshStatus()
                    await ModerationService.shared.refreshBlockedList()
                }
                .fullScreenCover(isPresented: $showEULA) {
                    EULAGateView { showEULA = false }
                }
        }
    }
}
```

### AppDelegate

```swift
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task { @MainActor in PushNotificationService.shared.handle(deviceToken: deviceToken) }
}
```

### RoomView

```swift
@StateObject private var sync = PlaybackSyncEngine()

.onAppear { sync.attach(player: player) }
.onDisappear {
    sync.detach()
    PushNotificationService.shared.noteWatchSessionFinished()
}
.onReceive(socket.hostStatePublisher) { state in
    sync.update(hostState: .init(position: state.position,
                                 timestamp: state.timestamp,
                                 isPlaying: state.isPlaying,
                                 rate: state.rate))
}
.overlay(alignment: .topLeading) {
    SyncQualityBadge(driftMilliseconds: sync.driftMilliseconds, quality: sync.quality)
        .padding(12)
}
.contextMenu {
    Button(role: .destructive) { showReport = true } label: {
        Label("Пожаловаться", systemImage: "flag")
    }
}
```

### Запрос пушей ПОСЛЕ просмотра

```swift
.task(id: watchFinished) {
    guard watchFinished, PushNotificationService.shared.shouldAskNow else { return }
    await PushNotificationService.shared.requestAuthorization()
}
```

### Настройки

```swift
NavigationLink("Заблокированные") { BlockedUsersView() }
Button("Удалить аккаунт", role: .destructive) { showDeletion = true }
    .sheet(isPresented: $showDeletion) { AccountDeletionView() }
```

## 3. Capabilities в Xcode

- In-App Purchase
- Push Notifications
- Background Modes → Remote notifications, Audio (для PiP и голоса)
- Associated Domains → `applinks:plink.app`

## 4. Товары в App Store Connect

| Product ID | Тип | Цена |
| --- | --- | --- |
| `com.plink.app.plus.monthly` | Автопродлеваемая | 199 ₽ / мес |
| `com.plink.app.plus.yearly` | Автопродлеваемая, триал 3 дня | 1 490 ₽ / год |
| `com.plink.app.plus.lifetime` | Нерасходуемая | 2 990 ₽ |

Недельного тарифа сознательно нет: он даёт всплеск возвратов и портит LTV.

## 5. Проверка после сборки

1. `rutube.ru/video/0f1a2b3c/` без `https://` — распознаётся.
2. `evil-vk.com.ru/video-1_1` — НЕ распознаётся как VK.
3. `random-site.com/movie.mp4` — честный отказ с объяснением.
4. Пейволл в сандбоксе StoreKit: покупка, отмена, восстановление.
5. Жалоба → блокировка → человек исчезает из ленты мгновенно.
6. Удаление аккаунта требует ввода слова УДАЛИТЬ и разлогинивает.
7. Значок синхрона показывает реальные миллисекунды, а не заглушку.
8. Пуши ЗАПРАШИВАЮТСЯ только после первого просмотра.

## 6. Честное предупреждение

Этот код не компилировался: в песочнице нет Swift-компилятора.
Он опирается на существующие сущности проекта:
`APIConfig.baseURL`, `DeepLinkRouter.shared.handle(url:)`, `Cinema2026.background`,
токены `V4.ink/muted/accent/accentInk/cardBG/line/raised/danger`.
Если какого-то токена нет — добавьте его в палитру перед сборкой.
