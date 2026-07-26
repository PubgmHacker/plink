# M20 — App Store Ready: Universal Links, Offline, Skeleton, Dynamic Type, Shake-to-Report

## Что было до
В M19 был закрыт UX-аудит и полная локализация. M20 закрывает всё остальное до App Store.

## 1. «Иконка приложения»
- Сгенерирован полный AppIcon-1024.png (V4-палитра: тёмный фон + mint-кольцо + белый play-треугольник).
- Contents.json обновлён — Xcode подхватит иконку автоматически.

## 2. Universal Links
- `Plink.entitlements`: добавлены `applinks:plink.app` и `applinks:www.plink.app`.
- Бэкенд: `GET /.well-known/apple-app-site-association` уже есть (app.ts:190), подставляет `APPLE_TEAM_ID` из env.
- При получении Apple Developer аккаунта: задай `APPLE_TEAM_ID` в Railway-переменных.

## 3. Оффлайн-баннер (NetworkMonitor)
- `Plink/Utilities/NetworkMonitor.swift` — `NWPathMonitor`-обёртка, `@Published isConnected`.
- `OfflineBannerModifier` — появляется сверху приложения анимированным spring-слайдом.
- `.withOfflineBanner()` навешан на `AuthLaunchGate` — виден повсюду в приложении.
- Локализация: «Нет сети» / «No internet» / 无网络.

## 4. scenePhase — фикс батареи
- `GroupChatsView.swift`: поллинг сообщений (2с) теперь проверяет `UIApplication.applicationState == .active` перед каждым запросом.
- В фоне запросы не идут, Timer игра–анимации останавливаются при `onDisappear` (V4HomeViewLive).

## 5. Skeleton-загрузка
- `Plink/Views/Components/SkeletonView.swift`: shimmer-эффект (на NWPathMonitor), `SkeletonRect`, `SkeletonCircle`, `SkeletonRoomCard`, `SkeletonGroupRow`, `HomeSkeletonView`, `GroupsSkeletonView`.
- `GroupChatsView`: показывает 5 `SkeletonGroupRow` пока `isLoading && groups.isEmpty` — вместо спиннера.

## 6. Shake-to-Report
- `Plink/Views/Feedback/ShakeFeedbackView.swift`: `PlinkShakeWindow` (перехват `motionEnded`), `ShakeDetectorModifier`, `FeedbackSheetView`.
- Типы фидбэка: Ошибка / Предложение / Другое.
- `.shakeToReport()` навешан на `AuthLaunchGate`.
- Бэкенд: `POST /api/telemetry/feedback` (тип, текст, appVersion, device, userId) — structured log, rate limit 10/10min.

## 7. Локализация
- 233 строки в ru/en/zh.lproj (добавлены `network.offline`, `network.retry`).

## Деплой
- Новых миграций нет.
- Переменные для Railway: добавь `APPLE_TEAM_ID=<твой Team ID>` после получения Apple Developer аккаунта.
