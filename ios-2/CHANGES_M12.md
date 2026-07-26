# Plink M12 — пакет улучшений (без войс-чатов и Apple Developer)

Дата: 18.07.2026. База: M11 (plink-ios-m11-update).

## 1. Синхронизация (цель — дрифт <150–200 мс)
`Plink/Realtime/OrderedSyncController.swift`
- **P-контроллер скорости**: вместо ступенек ±2%/±5% — коррекция
  пропорциональна дрифту (kP=0.0002, кламп ±5%). Плавнее и быстрее сходится.
- **Компенсация задержки seek**: EMA измеренной латентности precise-seek;
  при hard-seek во время воспроизведения цель «упреждается» на эту величину —
  после seek позиция ближе к эталонной.
- **Адаптивное окно перепроверки**: 1 с при дрифте ≥250 мс (было всегда 2 с).

## 2. Надёжность соединения
`Plink/Realtime/RealtimeClient.swift`
- **Очередь исходящих сообщений**: чат и реакции, написанные офлайн/при
  реконнекте, больше не теряются — копятся (до 50 шт.) и отправляются после
  восстановления сессии. Служебные сообщения (probe/state) не копятся.

## 3. Планирование сеансов (новая фича)
- `Plink/Services/ScheduledSessionsService.swift` — хранение, пуш-напоминания
  (за 15 мин + в момент старта), добавление в календарь (EventKit).
- `Plink/Views/Home/ScheduleSessionSheet.swift` — шторка с датой/временем и списком.
- Кнопка «Запланировать сеанс» на главной (под «Быстрой комнатой»).

## 4. AI
`Plink/Services/AIService.swift`
- `catchUpSummary(...)` — «что я пропустил»: сводка чата и позиции для опоздавших, без спойлеров.
- `watchTogetherRecommendations(...)` — рекомендации по локальной истории просмотров (WatchHistory).

## 5. Crash-репортинг (без Firebase)
- `Plink/Services/CrashReporter.swift` — перехват NSException + фатальных сигналов,
  JSON-отчёт на диск, отправка на `/api/telemetry/crash` при следующем запуске.
- Подключён в `RaveCloneApp.swift` (AppDelegate).
- Бэкенд: новый эндпоинт `POST /api/telemetry/crash` (rate limit 20/час).

## 6. Deep links
- Android: intent-фильтры `https://plink.app/r/*`, `/u/*` (autoVerify) + `plink://`.
- Бэкенд: `/.well-known/apple-app-site-association` и `/.well-known/assetlinks.json`
  (TEAMID/SHA256 — через env, когда появятся аккаунты). См. `docs/UNIVERSAL_LINKS.md`.

## 7. Android release
- `app/build.gradle.kts`: R8 (`isMinifyEnabled=true`) + `shrinkResources` +
  signing из env (`PLINK_KEYSTORE_*`), локально — безопасный no-op.
- `proguard-rules.pro`: keep-правила для kotlinx.serialization/сети/Firebase.

## 8. Тесты и CI
- `PlinkTests/ThemeRegressionTests.swift` — защита каталога тем (5 V4-тем +
  4 Plink+ live-темы, имена/порядок/акценты/уникальность) — чтобы история
  с потерей тем при рефакторинге не повторилась.
- `.github/workflows/ios-tests.yml` — юнит-тесты на симуляторе без подписи
  (xcodegen + xcodebuild, Apple Developer не нужен).

## Уже было готово (проверено, не трогал)
- Локализация EN/ZH (201/201 ключей), триал + restore purchases (StoreKit 2),
  универсальный URL-режим (браузер + custom URL), health-checks и rate limiting на бэкенде.

## Отложено (нужен Apple Developer / по решению)
- Войс-чаты (LiveKit), TestFlight/App Store, Associated Domains entitlement,
  подпись iOS-сборок.
