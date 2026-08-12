# Полный точечный аудит Plink — охват всех систем — 07.08.2026

**Режим:** full-аудит всех систем · **Язык:** русский · **Ветка:** `main`
**Отчёт-предшественник:** `audit-report-plink-2026-08-07.md` (проблемы №1–7 оттуда не повторяются, но учитываются в сводке).

---

## 0. Карта систем и охват

| # | Система | Путь | Что проверено | Вердикт |
| --- | --- | --- | --- | --- |
| 1 | Бэкенд | `backend-3/` | tsc, vitest, npm audit, все 20 роутеров, схема Prisma (25 моделей), 17 миграций, Dockerfile, railway.json, start.sh | 🟢 собирается, 107/108 тестов |
| 2 | Лендинг | `landing/` | next build (9 страниц), tsc, npm audit, содержимое страниц | 🟢 собирается, ⚠️ next@14.2.5 |
| 3 | iOS-клиент | `ios-2/Plink` | xcodebuild BUILD SUCCEEDED, 171 Swift-файл, 4 таргета, тесты | 🟢 |
| 4 | iOS-тесты | `ios-2/PlinkTests`, `PlinkUITests` | 36 файлов, разбивка по областям | 🟢 |
| 5 | Виджет | `ios-2/PlinkWidget` | 1 файл, включён в проект | 🟢 |
| 6 | **Android-клиент** | `ios-2/android-client` | 28 Kotlin-файлов (3.3 К строк), Compose, gradle-конфиг, манифест, безопасность | ⚠️ **не собирался** (нет Android SDK), 0 тестов |
| 7 | Десктоп | `ios-2/mac-desktop` | только README-стаб | 🟡 заглушка |
| 8 | QA-артефакты | `qa/`, `plink-preview.html` | 2 HTML-превью + PNG | 🟡 статичные снэпшоты |
| 9 | CI | `.github/workflows/ci.yml` + `ios-2/.github/workflows/ci.yml` | оба файла, шаги, пути | 🔴 **старый CI сломан** (см. №14) |
| 10 | Деплой | Dockerfile, railway.json, start.sh, prisma-миграции | full read | 🟢, один дрейф (см. №15) |
| 11 | Доки | AGENT_BRIEF, ios-2/docs (9 файлов), ios-2/*.md (30+) | сверка с кодом | 🟡 разошлись с реальностью |
| 12 | Бренд | `brand/`, `brand-v2/` | SVG/PNG-ассеты | 🟡 не в gitignore |
| 13 | Секреты | git ls-files, .gitignore | трекинг секретов | 🟢 Secrets.xcconfig не в git |
| 14 | Git-гигиена | git status, ветки | untracked-мусор, ветки | 🔴 см. №16 |

---

## 1. Бэкенд (`backend-3/`)

### Запуск-проверки
| Проверка | Результат |
| --- | --- |
| `npx tsc --noEmit` | ✅ чисто |
| `npx vitest run` | ✅ **107/108**, 1 skipped (нет `REDIS_URL`; в CI Redis поднят — там бегут все) |
| `npm audit --omit=dev` | ⚠️ 53 уязвимости (2 critical, 6 high) — см. `audit-report-plink-2026-08-07.md` №1–4 |

### Структура маршрутов (20 роутеров, ~150 эндпоинтов)
`auth, admin, ai, assets, billing, dev, featureFlags, friends, gdpr, groups, livekit, media, messages, moderation, profile, realtime, rooms, telemetry, web, webpay` — все зарегистрированы в `app.ts:203–236`. Rate-limit на чувствительных маршрутах: login 5/20min, register 10/5min, admin-stepup 5/10min, GDPR 3/1h, wipe 15/1min. Zod-валидация в auth/rooms/messages/billing.

**Особые точки:**
- `dev.ts /dev/wipe-db` — захардкожен 403 в проде без `ENABLE_DEV_WIPE`, секрет обязателен всегда. ✅
- `livekit.ts` — `hasActivePlus()` проверяет подписку НА СЕРВЕРЕ (не UI): `Subscription.isActive && !revokedAt && expiresAt > now`, fallback на `isPremium && premiumUntil > now`. ⚠️ Комментарий в коде: **`RTC_PAYWALL_BEFORE_AVAILABILITY=true` — бета-режим, продажа пэйволла ДО фактической доступности SFU. ПЕРЕД APP STORE обязательно `false`** (иначе возвраты по Guideline 3.1.1).
- `web.ts` — escHTML, CSP с nonce, `ROOM_CODE_RE=/^[A-Z0-9]{4,12}$/`, `USERNAME_RE` — XSS-защита на месте. ✅
- WebSocket: `maxPayload 64KB`, gateway + connectionRegistry + heartbeat + roomPubSub (8 файлов realtime/).

### Схема БД: 25 моделей, 17 миграций
**🔴 НОВАЯ НАХОДКА №15 — дрейф схемы `AIModerationAudit`:**
- Модель есть в `schema.prisma` (стр. 438), код **пишет в неё**: `prisma.aIModerationAudit.create()` в `moderation/autoMod.ts:175`, вызывается из `realtime/messageRouter.ts:310`, `routes/messages.ts:525,721,946,1358`, `routes/groups.ts`.
- Миграции, создающей таблицу `"AIModerationAudit"`, **нет ни в одной из 17** (проверено `grep -ril 'moderationaudit' prisma/migrations/` → 0).
- Как работает сейчас: на свежей БД (`prisma migrate deploy`) `create()` упадёт → поймается `try/catch` → `console.warn('[autoMod] audit failed')` → **аудиты модерации молча теряются**.
- Почему на проде, вероятно, не падает: существующая Railway-БД создавалась через `prisma db push` (`scripts/migrate-baseline.sh` прямо пишет про это) — там таблица могла появиться. Но **любая новая среда (CI, стейдж, свежий Railway) таблицы не получит**.
- **Фикс:** `npx prisma migrate dev --name add_ai_moderation_audit` (сгенерировать миграцию из существующей схемы), запушить, `migrate deploy` на стейдже. 20–40 мин.

Остальные 24 модели покрыты миграциями (проверено по `CREATE TABLE`).

---

## 2. Лендинг (`landing/`)

- `next build` ✅ — 9 статических страниц: `/`, `/privacy`, `/terms` + robots/sitemap. Компоненты: Hero, Features, Pricing, FAQ, Platforms, Footer, Navigation и др.
- ⚠️ `next@14.2.5` — 12 CVE (SSRF, DoS, cache poisoning) — фикс одной командой `npm i next@14.2.35`.
- README — шаблонный create-next-app, не документирует проект.

---

## 3. iOS-клиент (`ios-2/`)

### Сборка и структура
- `xcodebuild` (Debug, симулятор) ✅ **BUILD SUCCEEDED** (1 deprecation-warning).
- `project.yml` (XcodeGen): 4 таргета — `Plink`, `PlinkTests`, `PlinkUITests`, `PlinkWidget`. Sources — весь каталог `Plink/` (V4 и V5 попадают в сборку автоматически).
- **LiveKit выключен** (закомментирован в `project.yml` + `ios-2/project.yml.bak` — резервная копия до отключения). SFU не используется — голос честно решён через диктовку.
- 171 Swift-файл. Слои: `Features/` (Auth2026, Onboarding2026, Premium2026, WatchRoom), `V4/` (21 файл: Home, Rooms, Reels, Profile, Friends, AI, Appearance, LivingBackground), **`V5/` (7 файлов: PlinkAdminRoot — полноценная админ-панель с реальными API-вызовами, PlinkAuthBridge, PlinkSessionSyncGate, PlinkRoomAppearance и др.)**.
- ⚠️ Сосуществуют два поколения UI (V4 + V5 + Features) — дублирование экранов в трёх слоях. Пункт AGENT_BRIEF P2-5.12 «UI-слои» остаётся частично открытым.

### Тесты (36 файлов)
`PlinkTests` — 35 файлов: юнит (RoomService, Friends, Profile, Billing, Settings, GDPR, Admin, DM, Notification, DeepLink, Presence, Websocket, ChatComposer, ClockSynchronizer, OrderedSyncController, DanmakuEngine, ReactionPalette, RoomLiveTheme, Lifecycle, M35Regression, RegressionMatrix), интеграционные/рантайм (YouTubePlaybackControllerRuntime, AmbientVideoSampler), а также MarketingShots/DesignAuditShots (скриншоты). `PlinkUITests` — 1 файл (FunnelSmoke). Плюс `RegressionMatrix.swift` — матрица регрессий.

### Известные риски (детализация из прошлого отчёта)
- ~545 force-unwrap'ов (`!`), мега-файлы (`WatchRoomModel.swift` ~75 КБ), хардкод-строки локализации (например, «Plink+ packs require subscription» в русском UI) — открытые пункты P2.

---

## 4. Android-клиент (`ios-2/android-client/`) — НОВОЕ ПОКРЫТИЕ

### Что это
Полноценный Jetpack Compose-клиент (не «тонкий»): **28 Kotlin-файлов, ~3 330 строк**. Экраны: Onboarding, Auth, Home, Room, Profile; viewmodel-слой (Auth/Home/Room/Profile), DI (`AppContainer`), сеть (`PlinkApi` Retrofit + OkHttp), **WS-клиент (`data/ws/PlinkRealtimeClient.kt`)**, синхронизация (`data/sync/OrderedSyncController.kt`, `ClockSynchronizer.kt` — есть те же компоненты, что и в iOS), `TokenStore` (EncryptedSharedPreferences, AES-256), Analytics (Firebase).

### Конфигурация сборки (`app/build.gradle.kts`)
- Kotlin 1.9.24, AGP 8.5.2, compileSdk 34, minSdk 24, targetSdk 34, Compose BOM 2024.06.00, JVM 17.
- **R8 + shrinkResources включены** на release; подпись — через env `PLINK_KEYSTORE_*` (нет env → release без подписи, локально безопасно). ✅
- Зависимости: Retrofit/OkHttp, kotlinx-serialization, coroutines, Coil, Media3 (ExoPlayer), Firebase (analytics, crashlytics), `androidx.security:security-crypto:1.1.0-alpha06` (**alpha** — штатно Google это больше не рекомендует, но рабочая).
- Манифест: только `INTERNET` permission, `usesCleartextTraffic="false"`. ✅

### Находки
| # | Находка | Severity |
| --- | --- | --- |
| A1 | **Не собирался в аудите** (нет Android SDK/Gradle в окружении) — сборка не подтверждена. AGENT_BRIEF заявляет «кроссплатформенную синхронизацию» — пока не доказано | ⚠️ |
| A2 | **0 тестов** (нет ни одного `*Test.kt` / `*Test.java`) | ⚠️ |
| A3 | **`google-services.json` закоммичен** в git (в отличие от iOS `GoogleService-Info.plist`, который в .gitignore). Firebase-ключи Android ограничиваются по пакету/SHA в консоли — если не ограничены, чужая квота. Проверить в Firebase-консоли | ⚠️ |
| A4 | `baseURL` захардкожен: `https://plink-production.up.railway.app` (и WS `wss://…`) — без env/Config-уровня. Для стейджа придётся менять код | 🟡 |
| A5 | `security-crypto:1.1.0-alpha06` — альфа + проект Google объявил библиотеку устаревшей; миграция на `EncryptedSharedPreferences`-замену не запланирована | 🟡 |
| A6 | В корневом CI нет job для Android (сборка/тесты) | 🟡 |

---

## 5. Десктоп и артефакты

- **`mac-desktop/`** — только README, который предлагает «Option B: `windows-client/` обёрнутый в Tauri» — **каталога `windows-client` в репо нет** (проверено). Десктопа фактически нет — это заглушка.
- **`ios-2/package.json`** — скрипты `desktop:dev`, `landing:dev` (`--prefix plink-landing`), `backend:build` (`--prefix plink-backend`) ссылаются на **несуществующие** каталоги (реальные: `landing/`, `backend-3/`). Мёртвые скрипты.
- **`qa/`** — `qa_room17.html`, `qa_fr18.html` + PNG: статичные HTML-превью интерфейса (02.08.2026). Актуальны как снэпшоты.
- **`plink-preview.html`** — то же превью в корне.
- **`brand/`** — SVG/PNG логотипы (plink-* 1024, wordmark, preview-html). **`brand-v2/`** — 2 файла концептов (concept-a-duo-play.png/svg). Не в gitignore.

---

## 6. Деплой и CI

### Dockerfile / railway.json / start.sh — ✅ хорошо
- Двухстадийная сборка, prod-only deps, **yt-dlp запинен** (`2026.07.04`), **не-root** (`USER node`), certs Apple включены в образ (P0 из июльского аудита), `healthcheckPath: /health/ready` (эндпоинт существует в `app.ts:289`), restartPolicy ON_FAILURE, старт через `prisma migrate deploy` (миграции применяются до бутстрапа, фатальные ошибки валят контейнер).

### CI
- **Корневой `.github/workflows/ci.yml`** — только backend job: checkout, node 20, `npm ci`, `prisma generate`, `tsc --noEmit`, `vitest run` (Redis поднят как service → интеграционные тесты бегут, а не скипаются). iOS — намеренно заглушка с пояснением (репозиторий GitHub устарел относительно локального монорепо, macos-runner не настроен).
- **🔴 НОВАЯ НАХОДКА №14 — `ios-2/.github/workflows/ci.yml` — сломанный/устаревший дубль:**
  - Ссылается на пути, которых нет: `working-directory: backend` (реально `backend-3/`), `cache-dependency-path: backend/package-lock.json` (нет), `backend/src/routes/web.ts` (нет), `ios/Plink.xcodeproj` (реально `ios-2/`), `ios/Plink/Services/MediaSourceResolver.swift` (нет такого файла).
  - Содержит осмысленные шаги (запрет `<script>` в web.ts, поиск приватных ключей, iOS-сборка через xcpretty) — но **выполниться не может**: на шаге `npm ci` упадёт из-за неверного пути к package-lock.
  - GitHub Actions игнорирует `.github` во вложенных каталогах (работает только корневой), поэтому этот файл молча мёртв, а не крашит — но вводит в заблуждение.
  - **Фикс:** удалить `ios-2/.github/` (вся логика должна жить в корневом CI) или синхронизировать пути на `backend-3/` + `ios-2/` и перенести security-job в корневой CI.

---

## 7. Секреты и гигиена

### Секреты — 🟢
- `ios-2/Secrets.xcconfig` **не в git** (только `.template`); `.gitignore` покрывает `.env*`, `Secrets.xcconfig`, `GoogleService-Info.plist`, `*.p8`, `*.p12`.
- `backend-3/.env.example` — только шаблон (15 переменных). Приватных ключей в коде нет (проверка `BEGIN ... PRIVATE KEY` чистая, и корневой CI это стережёт).
- ⚠️ Исключение — `android-client/app/google-services.json` закоммичен (см. A3).

### 🔴 НОВАЯ НАХОДКА №16 — untracked-мусор и ветки
- `?? .freebuff/` — **14 МБ** SQLite (desktop-v2.db + WAL/SHM) — **не в .gitignore** → риск закоммитить чужую БД.
- `?? ios-2/project.yml.bak` — бэкап до отключения LiveKit, не в gitignore (`*.bak` не покрыт).
- `?? brand/`, `?? brand-v2/`, `?? audit-report-plink-2026-08-07.md` — не игнорятся (первые два, вероятно, нужно коммитить осознанно; отчёт — да).
- Локальные ветки `backup-before-merge-2026-08-03`, `backup-design-2026-08-03` не смержены и не удалены.
- **Фикс:** в `.gitignore` добавить `.freebuff/` и `*.bak`; удалить `project.yml.bak`; решить судьбу `brand/` (коммитить или игнорить).

---

## 8. Сверка документации с реальностью

| Утверждение (док) | Реальность |
| --- | --- |
| `AGENT_BRIEF.md`: «246 Swift-файлов» | 171 файл |
| `AGENT_BRIEF.md` ссылается на `PLINK_AUDIT_2026-07.md` | **файл отсутствует** |
| `AGENT_BRIEF.md` ссылается на `AUDIT_REPORT.md` | есть только `ios-2/AUDIT_REPORT.md` (не в корне) |
| `ios-2/package.json`: `desktop:dev → windows-client` | каталога нет |
| `mac-desktop/README.md`: Option B → `windows-client/` | каталога нет |
| `ios-2/.github/workflows/ci.yml` → `backend/`, `ios/` | реальные пути `backend-3/`, `ios-2/` |
| `docs/` (`ios-2/docs/`): APP_STORE_SUBMISSION, LIVEKIT_SETUP, MVP_FINAL_AUDIT_REPORT и др. (9 файлов) | существуют, но LIVEKIT_SETUP описывает выключенный SFU |
| `backend-3/docs/release` | существует |
| `backend-3/src/docs/openapi.yaml` (346 строк) | существует ✅ |

---

## 9. Сводная таблица систем

| Система | Оценка | Главное |
| --- | --- | --- |
| Бэкенд | 8/10 | 🟢 зелёный; 🔴 дрейф `AIModerationAudit`; 🔴 fastify-jwt (из прошлого отчёта) |
| Лендинг | 7/10 | 🟢 собирается; ⚠️ next@14.2.5 |
| iOS | 7.5/10 | 🟢 BUILD SUCCEEDED + 36 тестов; ⚠️ V4/V5-дубли, force-unwraps |
| Android | 5.5/10 | ⚠️ не собран, 0 тестов, alpha-крипта; закоммичен google-services |
| Десктоп | 2/10 | заглушка README, несуществующий windows-client |
| CI | 5/10 | 🟢 backend в корневом CI; 🔴 мёртвый ios-2 CI |
| Деплой | 9/10 | Dockerfile/railway/start.sh — образцовые |
| Доки | 5/10 | разошлись с реальностью (пути, цифры, файлы) |
| Git-гигиена | 4/10 | 14 МБ untracked БД, .bak, ветки |
| **Общий** | **7.0/10 (B)** | с учётом прошлого отчёта (7.4) — минус за новые находки №14–16 |

---

## 10. Итоговый список новых находок (дополнение к прошлому отчёту)

| # | Severity | Находка | Фикс | Усилия |
| --- | --- | --- | --- | --- |
| 14 | 🔴 High | `ios-2/.github/workflows/ci.yml` — мёртвый дубль с несуществующими путями (`backend/`, `ios/`, `windows-client`), логика security-job не работает | удалить или перенести шаги в корневой CI с путями `backend-3/`, `ios-2/` | 30 мин |
| 15 | 🔴 High | Дрейф схемы: `AIModerationAudit` в schema.prisma + пишется кодом, но **нет миграции** — на новой БД аудит модерации молча теряется | `prisma migrate dev --name add_ai_moderation_audit`, прогнать `migrate deploy` на стейдже | 30 мин |
| 16 | 🟡 Medium | 14 МБ untracked `.freebuff/`, `project.yml.bak`, `brand/`, ветки-бэкапы | .gitignore + решить судьбу brand/ + почистить ветки | 20 мин |
| 17 | 🟡 Medium | Android: 0 тестов, сборка не подтверждена, `google-services.json` в git, alpha-криптография | собрать в CI, добавить smoke-тесты, проверить ключи в консоли | 2–4 ч |
| 18 | 🟡 Medium | Скрипты `ios-2/package.json` (`desktop:dev`, `landing:dev`, `backend:build`) ведут в несуществующие каталоги | поправить на `landing/`, `backend-3/` или удалить | 10 мин |
| 19 | 🟡 Low | `mac-desktop/` ссылается на отсутствующий `windows-client` | пометить заглушкой или удалить README-миф | 10 мин |
| 20 | 🟡 Low | `RTC_PAYWALL_BEFORE_AVAILABILITY=true` (бета-пэйволл ДО готовности SFU) — должен стать `false` перед App Store | env-переменная перед релизом (в коде есть предупреждение) | 1 мин + релиз |

---

## 11. Приоритетный порядок исправлений (с учётом прошлого отчёта)

1. **Безопасность (сегодня):** `@fastify/jwt@10.2.1` → тесты; `next@14.2.35`; апгрейд `fastify@5.x`. (из прошлого отчёта)
2. **Целостность данных (сегодня):** миграция `AIModerationAudit` (#15).
3. **CI (сегодня-завтра):** убрать/починить `ios-2/.github/workflows/ci.yml` (#14); добавить job лендинга и шаг `npm audit --omit=dev` в корневой CI.
4. **Гигиена (завтра):** `.gitignore` (+`.freebuff/`, `*.bak`), удалить `project.yml.bak`, решить судьбу `brand/`, почистить ветки (#16).
5. **Android (на неделе):** собрать в CI, smoke-тесты, проверить google-services ключи (#17), заменить alpha-крипту.
6. **Релиз App Store:** `RTC_PAYWALL_BEFORE_AVAILABILITY=false` (#20), Universal Links, force-unwrap-аудит.

---

*Методология: проверки запуском (tsc, vitest, next build, xcodebuild) + статический разбор всех систем. Android не компилировался (нет Android SDK). Продакшен-окружение (Railway) недоступно. Секреты в отчёт не выводились.*
