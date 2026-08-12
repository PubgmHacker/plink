# Аудит Plink — 07.08.2026

**Режим:** full-аудит · **Язык:** русский · **Формат:** markdown
**Коммит на момент аудита:** `4917109` (fix: актуальный домен Railway) · ветка `main`
**Монорепо:** iOS-клиент (SwiftUI, XcodeGen) + бэкенд (Fastify/Prisma/Postgres/Redis) + лендинг (Next.js 14) + Android-клиент (тонкий)

---

## Резюме для владельца

Проект в **хорошем состоянии**: всё собирается, тесты зелёные, критические проблемы безопасности из июльского аудита закрыты (подделка IAP, хардкод-код админа, открытые 2FA-секреты, XSS-санитайзер, публичный /metrics, dev-wipe в проде). Основные риски сейчас — **устаревшие зависимости** (`@fastify/jwt` — критичная уязвимость, `next@14.2.5` — пачка CVE), **репозиторный мусор** (неотслеживаемая БД в `.freebuff/`, бэкап-файл, две запасные ветки) и **незакрытый Universal Links** (приглашения открывают сайт, а не приложение).

Общий балл: **7.4 / 10 (B)**.

---

## Охват и методология

**Проверено запуском (не рассуждением):**
| Проверка | Результат |
| --- | --- |
| `xcodebuild` iOS (Debug, симулятор) | ✅ **BUILD SUCCEEDED** (1 deprecation-warning) |
| `tsc --noEmit` бэкенд | ✅ чисто |
| `vitest run` бэкенд | ✅ 107/108 passed, 1 skipped (нет REDIS_URL) |
| `next build` лендинг | ✅ 9 статических страниц |
| `npm audit --omit=dev` бэкенд | ⚠️ 53 уязвимости (2 critical, 6 high) |
| `npm audit --omit=dev` лендинг | ⚠️ 2 уязвимости (1 critical, 1 high) |
| Git-гигиена (лог, ветки, статус, трекер секретов) | ⚠️ см. находки |

**Прочитано статически:** `config/index.ts`, `app.ts`, `prisma/schema.prisma`, `routes/auth.ts`, `middleware/security.ts`, `middleware/validate.ts`, `Dockerfile`, `railway.json`, `.env.example`, `.github/workflows/ci.yml`, `ios-2/project.yml`, ключевые iOS-файлы (WatchChatComposer, V4AIView, WatchRoomModel, AuthTokenStore).

**Исключено/ограничено:** полный исходник iOS (171 файл — выборочно), внутренности realtime-gateway (покрыты интеграционными тестами), исходник Android-клиента, большинство doc-файлов. Охват по каждой размерности указан в таблице ниже.

| Размерность | Охват | Балл |
| --- | --- | --- |
| Архитектура и сопровождаемость | High | 7.0 |
| Безопасность | High | 7.5 |
| Стабильность | Medium | 8.0 |
| Тестирование и CI | High | 7.5 |
| Релизная готовность | Medium | 7.0 |
| Наблюдаемость | Medium | 8.0 |
| Конфигурация и документация | High | 7.5 |
| **Общий** | — | **7.4 (B)** |

---

## Топ-риски

| # | Риск | Severity | Усилия |
| --- | --- | --- | --- |
| 1 | `@fastify/jwt@9.1.0` → `fast-jwt`: **критичные** уязвимости (алгоритм-конфьюжн, cache-коллизии токенов → путаница идентичности, ReDoS, приём `crit` заголовков) | Critical | 2–4 ч |
| 2 | Лендинг на `next@14.2.5`: SSRF, DoS, cache poisoning, i18n-middleware bypass, раскрытие Server Function эндпоинтов | High | 1 ч |
| 3 | **545** строк с `!` (force-unwrap) в iOS — поверхность крашей | Medium | 2–3 дня (Instruments) |
| 4 | Universal Links не включены (Personal Team) — приглашения ведут на сайт, не в приложение | Medium | требует Apple Developer Program |
| 5 | Репо-мусор: `.freebuff/` (1.5 МБ SQLite) и `project.yml.bak` не в gitignore; 2 запасные ветки | Low | 15 мин |
| 6 | Доки разошлись с реальностью: `AGENT_BRIEF.md` ссылается на несуществующие `PLINK_AUDIT_2026-07.md` и `AUDIT_REPORT.md`, «246 Swift-файлов» → фактически 171, «42 обращения к Keychain в 26 файлах» → фактически 4 | Low | 30 мин |

---

## Детальные находки

### 🔴 Confirmed

**1. [Critical] Критичная уязвимость в JWT-библиотеке**
- **Evidence:** `npm audit`: `@fastify/jwt@9.1.0` (direct dep) зависит от `fast-jwt` с 6 уязвимостями критического уровня: алгоритм-конфьюжн (CVE-2023-48223 + whitespace-RSA обход), cache-коллизии `cacheKeyBuilder` → возврат claims чужого токена (путаница авторизации), ReDoS, stateful-RegExp DoS, auth bypass при пустом HMAC-секрете через async-резолвер, приём неизвестных `crit`-заголовков.
- **Реалистичный сценарий:** настройка `verify` сейчас НЕ использует async-резолвер (секрет синхронный), но cache-коллизии и алгоритм-конфьюжн затрагивают текущую конфигурацию `sign/verify` (HS256, allowedAud/allowedIss). Это библиотека, подписывающая access-, refresh- и WS-тикеты.
- **Фикс:** `@fastify/jwt@^10.2.1` (breaking-major, но API совместим для текущего использования: `fastify.jwt.sign/verify`; имена опций `allowedAud/allowedIss` не меняются). Прогнать все тесты + интеграционные.
- **Регрессионный тест:** существующий `jwtClaims.unit.test.ts` + прогон `ticket.integration.test.ts` и `gateway.integration.test.ts`.
- **Оценка:** 2–4 часа.

**2. [High] Лендинг на устаревшем Next.js**
- **Evidence:** `landing/package.json`: `next: 14.2.5`; `npm audit`: 12 CVE (Image Optimization DoS, SSRF через WebSocket upgrades, cache poisoning RSC, Pages-Router i18n bypass, Server Actions DoS/SSRF, cache confusion, unbounded payload, SSRF в rewrites, раскрытие Server Function эндпоинтов) + postcss XSS/path traversal. Фикс в рамках мажора: `next@14.2.35`.
- **Фикс:** `npm i next@14.2.35` (или последний 14.2.x), пересобрать. Малый риск регрессии: мажор тот же, App Router, статические страницы.
- **Оценка:** 1 час.

**3. [Medium] `@opentelemetry/core` — unbounded memory в W3C Baggage propagation (цепочка ~40 пакетов)**
- **Evidence:** `npm audit`: moderate у всего OTel-дерева (sentry/node, sdk-node, auto-instrumentations-node, 40+ пакетов) из-за `@opentelemetry/core`.
- **Реалистичный сценарий:** OTel-трейсинг включён только при заданном `OTEL_ENDPOINT`; Baggage-заголовок не принимается на входе (внутренняя телеметрия), поэтому эксплуатация маловероятна. Но шум в audit-выводе скрывает реальные проблемы.
- **Фикс:** поднять `@opentelemetry/*` до актуальных версий (некоторые — breaking внутри мейджора); либо, если OTel не используется в проде, убрать `auto-instrumentations-node` и `sdk-node` из prod-deps.
- **Оценка:** 1–2 часа.

**4. [Medium] `fast-uri` (host confusion) и `find-my-way` (DDoS HTTP2) в ядре Fastify**
- **Evidence:** `npm audit`: high. `fastify@5.9.0`.
- **Фикс:** апгрейд `fastify@^5.x` последней (5.9.0 → актуальная 5.x), он тянет исправленные `fast-uri`/`find-my-way`. Non-breaking.
- **Оценка:** 30–60 мин.

**5. [Medium] ~545 force-unwrap'ов в iOS**
- **Evidence:** `grep -rn '!' ios-2/Plink --include='*.swift'` (без `!=`, `!in`, `!has`, `isActive`) ≈ 545 строк. Известно из AGENT_BRIEF P2-5.14; проверено, что пункт не закрыт.
- **Реалистичный сценарий:** `try!`, `!` на optional из сети/декодинга — краши на проде (Crashlytics уже подключён, но телеметрия прода не развёрнута).
- **Фикс:** прогон Instruments/статистики по файлам, приоритет — сетевые модели и WatchRoomModel (75 КБ).
- **Оценка:** 2–3 дня.

**6. [Low] Репозиторный мусор**
- **Evidence:** `git status`: `?? .freebuff/` (desktop-v2.db + wal/shm, ~1.5 МБ), `?? ios-2/project.yml.bak` (дубль project.yml до отключения LiveKit). `.gitignore` их не покрывает. Локальные ветки `backup-before-merge-2026-08-03`, `backup-design-2026-08-03` не смержены.
- **Фикс:** добавить `.freebuff/` и `*.bak` в `.gitignore`, удалить `project.yml.bak`, почистить/смёржить ветки. Это не commit за вас — оставляю как рекомендацию.
- **Оценка:** 15 мин.

**7. [Low] Universal Links не работают**
- **Evidence:** `project.yml` (entitlements): Associated Domains НЕ добавлены осознанно — «Personal development teams do not support the Associated Domains capability». При этом бэкенд уже отдаёт `/.well-known/apple-app-site-association` (routes/web.ts). Диплинки `plink://` работают.
- **Следствие:** пункт MVP-чеклиста «Приглашение по ссылке открывает приложение» не закрыт.
- **Фикс:** покупка Apple Developer Program ($99/год) + добавление `applinks:plink.app` / `applinks:plink-production.up.railway.app` в entitlements.
- **Оценка:** 1–2 ч после покупки подписки.

### 🟡 Suspected (не проверено запуском/требует окружения)

**8. [Suspected] Android-паритет синхронизации не подтверждён**
- **Evidence:** `ios-2/android-client/` существует; `UserBlockManager.kt:46` — `TODO: call api.moderationReport(...)`; по брифу P0-5.4 `sync.command` не применяется к плееру. Не компилировал (нет Gradle/Android SDK в рамках аудита).
- **Рекомендация:** до подтверждения не заявлять «кроссплатформенная синхронизация».

**9. [Suspected] `android-client/app/google-services.json` закоммичен**
- **Evidence:** `git ls-files` содержит файл; ключи API не печатаю (редакция). Google-ключи Android-клиентов принято ограничивать по пакету/SHA — если не ограничены, любой может использовать квоту. Проверить в Firebase-консоли и, при необходимости, сузить.
- **Оценка:** 30 мин.

**10. [Suspected] Домен и метаданные промо**
- **Evidence:** `web.ts`: `APP_STORE_URL` default `https://apps.apple.com/app/id0000000000` (заглушка), `TESTFLIGHT_URL` пуст, `ANDROID_STORE_URL` пуст; `PUBLIC_ORIGIN`/`PUBLIC_BASE_URL` — домен Railway. `README` заявляет прод-URL Railway. App Store id и/или TestFlight не подставлены в env.
- **Следствие:** кнопки установки на лендингах ведут в никуда до настройки env.

---

## Прогресс по AGENT_BRIEF (пункты P0/P1)

| Пункт | Статус на 07.08.2026 |
| --- | --- |
| P0 5.1 Голосовой чат | ✅ **Решено**: LiveKit отключён (`project.yml` + `LIVEKIT_SFU=false`), UI комнаты скрыт за `FeatureFlags.liveKitVoiceEnabled=false` (PresenceBar). Диктовка (V4VoiceCapture) — отдельная фича, работает без SFU. Микрофон в композере чата — это распознавание речи, не голосовая связь |
| P0 5.2 Замер синхронизации на 3 устройствах | ⏳ Требует человека (физических устройств) |
| P0 5.3 Экран пустой комнаты | ⚠️ Частично: `RoomInviteSheet` (deep link + QR) существует; большой CTA «Позвать друга» на пустом экране не проверял |
| P0 5.4 Android-паритет | ⚠️ Открыт (тонкий клиент, TODO в UserBlockManager) |
| P1 5.5 Пустые кнопки | ✅ В основном: `openInRutubeExternal` реализован; `startPiP`/`openPlayerSettings` удалены; `toggleCamera` гейтится Plink+ и шлёт нотификацию; остался только stub микрофона в `RoomRTCController` (UI скрыт флагом) |
| P1 5.6 Шифрование 2FA | ✅ Закрыт: `utils/secretBox.ts` (AES-256-GCM, префикс, легаси-чтение), скрипт `encrypt-2fa-secrets.js`, расшифровка при verify |
| P1 5.7 zod-валидация | ✅ Закрыт: `validateBody` подключён в `auth.ts`, `rooms.ts`, `messages.ts`, `billing.ts`; все три хелпера fail-closed (ревью 02.08.2026) |
| P1 5.8 Админ-код | ✅ Закрыт: `ADM873IN7` удалён; `ADMIN_STEPUP_CODE` из env + TOTP, сравнение за постоянное время, role-check до выдачи mfa-токена |
| P1 5.9 `invalidateUserSnapshot` | ✅ Закрыт: вызывается в `admin.ts` (бан, роль), `moderation.ts`, `gdpr.ts` |
| P1 5.10 Keychain-ключ | ✅ Закрыт через dual-write: `AuthTokenStore` пишет в оба ключа и читает легаси; осталось 4 файла с упоминанием `rave_auth_token` (в основном комментарии) |
| P1 5.11 Лимиты тарифа | ✅ Частично: серверные лимиты участников (10 free / 50 premium) и автозавершение старых комнат на free-тарифе в `rooms.ts` |
| P2 5.12 UI-слои | ⚠️ Rave-наследие вычищено (0 файлов `*Rave*`), но остались V4 (21 файл) + V5 (7 файлов) |
| P2 5.13 Мега-файлы | ⚠️ Не разбиты (`WatchRoomModel.swift` ~75 КБ и др.) |
| P2 5.14 Force-unwrap | ⚠️ Открыт (~545 строк с `!`) |
| P2 5.15 Локализация | ⚠️ Частично: `LocalizationManager` есть, но в UI остаются хардкоды, включая английскую строку «Plink+ packs require subscription» в русском интерфейсе (WatchChatComposer/PacksPopover) |

**Что закрылось с прошлого аудита (дополнительно):** IAP fail-closed + самопроверка на старте; подпись StoreKit против корневого сертификата Apple; `trustProxy`; аудитории/issuer в JWT (fast-jwt-именование опций); /metrics под токеном; dev-wipe только в dev; XSS-санитайзер чата; автоскрытие сообщений по 3 жалобам; дедупликация App Store Notifications; теневая бан-модель; GDPR-таймер удаления; веб-оплата ЮKassa; сборка `BUILD SUCCEEDED`.

---

## MVP-чеклист (§7 AGENT_BRIEF)

- [x] `xcodebuild build` — зелёная (07.08.2026)
- [x] `tsc --noEmit` + `vitest` — зелёные (107/108)
- [ ] Миграция применена на живой БД; `[iap] самопроверка ... пройдена` в логах прода — не проверялось в этом аудите (нет доступа к Railway)
- [ ] Покупка в sandbox StoreKit (покупка/отмена/восстановление) — требуется человек
- [x] Бан вступает в силу и на HTTP, и на WS (invalidateUserSnapshot + gateway)
- [ ] Синхронизация на двух устройствах, замер дрейфа — требуется человек
- [ ] Приглашение по ссылке открывает приложение — **не закрыт** (Universal Links)
- [x] Жалоба → блокировка → исчезновение из ленты (moderation.ts, автоскрытие)
- [x] Удаление аккаунта (GDPR-каскад, tombstone, отзыв токенов)
- [x] Кнопки-пустышки в основном убраны
- [x] Эмодзи отображаются (фикс каталога + SF Symbol fallback + кэш)

---

## Порядок исправлений (предложенный)

1. **Срочно (безопасность):** `@fastify/jwt@10.2.1` → прогнать тесты; `next@14.2.35`; апгрейд `fastify@5.x`.
2. **Сегодня-завтра:** `.gitignore` (+`.freebuff/`, `*.bak`), удалить `project.yml.bak`, почистить ветки; причесать доки (создать отсутствующие, обновить цифры в AGENT_BRIEF).
3. **На этой неделе:** проверить ограничение google-services.json в консоли Firebase; подставить `TESTFLIGHT_URL`/`APP_STORE_URL` в env; решение по OTel (апгрейд или выпил из prod-deps).
4. **До релиза в App Store:** Universal Links (после покупки программы разработчика), Instruments по force-unwrap, локализация хардкодов, разбивка мега-файлов.

## Quick wins

- `npm i next@14.2.35` в `landing/` — закрывает 12 CVE одной командой.
- В `.gitignore` добавить `.freebuff/` и `*.bak` — убирает риск коммита чужой БД.
- В CI добавить шаг `npm audit --omit=dev` (gate на critical/high) и job для лендинга; iOS-сборку — после синхронизации репозиториев.
- `ADMIN_STEPUP_CODE` держать пустым, когда админы завёл TOTP (env-мост уже задепрекейчен комментарием).

---

*Охват честно ограничен: iOS прочитан выборочно (171 файл), Android не компилировался, продакшен-окружение (Railway, живая БД, Redis) недоступно. Никаких секретов в отчёт не выводилось.*
