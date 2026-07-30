# Аудит Plink — 26.07.2026 (методика: skill fuck-my-shit-mountain, mode full)

9 систем, 15 агентов-аудиторов + верификация фиксов запуском. Формат находки:
severity · файл:строка · суть · улика · фикс. P0 применены сразу (помечены).


## ОБНОВЛЕНИЕ (та же дата, вторая волна): P1-очередь закрыта

Рой из 7 фиксеров применил P1-находки по непересекающимся зонам:
**38 исправлено, 0 пропущено** (частности — в примечаниях к находкам
в отчёте роя). Плюс отдельно: sharp добавлен в dependencies — OG-афиши отдаются
PNG (проверено: content-type image/png). Ключевые доработки сверх рецептов:
курсорная пагинация GET /messages/dm/:friendId (before/limit), typed-событие
participant.kicked в realtime (кик реально закрывает сокет на всех репликах),
appAccountToken-привязка покупок (UUIDv5, сервер+клиент по общей формуле),
retry/failed-статусы сообщений в DM.

Верификация после правок: backend tsc чистый, 35 тестов зелёные; iOS BUILD
SUCCEEDED (полный прогон тестов — см. журнал сессии).

## Сводка оценок

| Система | Оценка | P0 | P1 | P2 |
|---|---|---|---|---|
| ios-store | 2.5/10 | 3 | 6 | 3 |
| be-social | 4.5/10 | 0 | 7 | 10 |
| ios-dm-friends | 4.5/10 | 0 | 6 | 5 |
| ios-auth-nav | 4.5/10 | 0 | 7 | 5 |
| ios-watchroom | 5.5/10 | 2 | 2 | 5 |
| be-billing | 6/10 | 0 | 2 | 4 |
| be-realtime | 6.5/10 | 0 | 5 | 6 |
| be-auth | 7/10 | 0 | 1 | 5 |
| be-web | 7/10 | 0 | 1 | 12 |
| **итого** |  | **5** | **37** | **55** |

Все 5 P0 исправлены в этой сессии (см. пометки ниже); P1 — приоритетная очередь на след. итерацию.

## ios-store — 2.5/10

- **[P0]** `ios-2/Plink/Services/StoreManager.swift:93` — apiBaseURL никогда не устанавливается — покупка не доходит до сервера, и сервер отзывает Plink+ при следующем запуске
  - Улика: StoreManager.swift:93 `var apiBaseURL: URL?` — по всему репозиторию нет ни одного присваивания (grep 'StoreManager.shared.apiBaseURL' пуст), а `refreshEntitlement()` не имеет ни одного вызова. Значит verifyWithBackend всегда идёт в ветку `guard let apiBaseURL else { applyLocalTransaction(transaction
  - Фикс: При старте приложения (RaveCloneApp/бутстрап V4) выставить `StoreManager.shared.apiBaseURL = URL(string: PlinkConfig.baseURLString)` и вызвать `await StoreManager.shared.refreshEntitlement()`. Регрессионный тест: unit-тест, что после purchase() выполняется POST /api/billing/verify (mock URLProtocol)
  - ✅ ИСПРАВЛЕНО: RaveCloneApp.init задаёт apiBaseURL + refreshEntitlement()
- **[P0]** `backend-3/src/routes/billing.ts:40` — Product ID трёх разных поколений: клиент продаёт plink.plus.*, сервер принимает только com.syncwatch.plink.premium.*
  - Улика: billing.ts:39-43 allowlist PLANS = 'com.syncwatch.plink.premium.monthly/yearly/lifetime' и строка 80-82 `if (!ALLOWED_PRODUCT_IDS.has(productId)) return 400 'Invalid productId'`. Реальный клиент покупает 'plink.plus.1m/3m/12m' (StoreManager.swift:52-54, закреплено тестами PlinkTests/BillingTests.swi
  - Фикс: Синхронизировать PLANS с PlinkProductID: ключи 'plink.plus.1m' (30 дн), 'plink.plus.3m' (90 дн — в PLANS сейчас вообще нет квартального плана), 'plink.plus.12m' (365 дн). Регрессионный тест: интеграционный тест billing.verify с productId из PlinkProductID.all — все должны проходить allowlist.
  - ✅ ИСПРАВЛЕНО: billing.ts PLANS = plink.plus.1m/3m/12m (+легаси-алиасы)
- **[P0]** `ios-2/Plink/Services/StoreManager.swift:304` — В поле jws уходит transaction.jsonRepresentation — это не JWS, серверная проверка подписи не может пройти никогда
  - Улика: StoreManager.swift:303-307: `"jws": String(data: transaction.jsonRepresentation, encoding: .utf8)`. jsonRepresentation — это неподписанный JSON транзакции; подписанный компактный JWS доступен только как `VerificationResult.jwsRepresentation`, который теряется в хелпере verifiedTransaction (строки 37
  - Фикс: Прокидывать `verification.jwsRepresentation` из purchase/Transaction.updates/currentEntitlements (заменить хелпер на switch, сохраняющий и транзакцию, и jwsRepresentation) и отправлять его в поле jws. Регрессионный тест: e2e в сендбоксе — verify возвращает 200 и entitlement.active=true.
  - ✅ ИСПРАВЛЕНО: во всех трёх путях уходит verification.jwsRepresentation
- **[P1]** `ios-2/Plink/Services/StoreManager.swift:311` — Fail-open: отказ сервера (4xx) всё равно включает премиум локально
  - Улика: StoreManager.swift:310-322: при любом не-200 (в т.ч. 400 'Transaction revoked', 403 'Transaction belongs to a different user' из billing.ts:145-164) и при любой сетевой ошибке вызывается `applyLocalTransaction(transaction)` → `PremiumStatusManager.activatePremium(...)`. Все клиентские гейты (4K, AdS
  - Фикс: Различать причины: сетевые ошибки — офлайн-грейс по локальному StoreKit-состоянию (это честный источник), ответы 4xx от сервера — авторитетный отказ без applyLocalTransaction. Регрессионный тест: mock-сервер отвечает 403 → PremiumStatusManager.isPremium остаётся false.
- **[P1]** `ios-2/Plink/Services/StoreManager.swift:174` — transaction.finish() вызывается безусловно, даже когда сервер не подтвердил покупку
  - Улика: StoreManager.swift:172-174 (purchase) и 270-277 (Transaction.updates): `await verifyWithBackend(...)` игнорирует результат, затем всегда `await transaction.finish()`. После finish() StoreKit перестаёт редоставлять транзакцию через Transaction.updates, т.е. сервер, не узнавший о покупке (см. P0-наход
  - Фикс: Возвращать Bool из verifyWithBackend и вызывать finish() только после подтверждения сервером (или после локального применения при заведомо офлайн-режиме с последующим re-verify). Регрессионный тест: при 500 от сервера транзакция остаётся незавершённой и повторно приходит в Transaction.updates.
- **[P1]** `ios-2/Plink/Services/StoreManager.swift:240` — Нет сверки entitlement при запуске: refreshEntitlement() не вызывается, слушатель Transaction.updates стартует только при открытии пейволла
  - Улика: grep по репозиторию: `refreshEntitlement()` определён (StoreManager.swift:240), вызовов ноль. StoreManager.shared — lazy singleton, впервые трогается только из PlinkPlusPaywall (.task loadProducts), значит слушатель Transaction.updates (init, строка 117) не работает до первого открытия пейволла: про
  - Фикс: В бутстрапе приложения: тронуть StoreManager.shared (запуск слушателя) и вызвать refreshEntitlement(); при 200 от /api/billing/entitlements не падать в checkLocalEntitlement. Регрессионный тест: сценарий «чистая установка + активная подписка в сендбоксе» — премиум активируется без ручного Restore.
- **[P1]** `ios-2/Plink/Services/StoreManager.swift:329` — applyEntitlement молча теряет платный премиум: ISO8601DateFormatter не парсит миллисекунды из toISOString()
  - Улика: StoreManager.swift:329 `ISO8601DateFormatter().date(from: $0)` — без .withFractionalSeconds, а billing.ts:259 отвечает `expiryDate.toISOString()` (JS всегда даёт '2026-08-25T10:00:00.000Z'). Парсинг вернёт nil → в ветке `case .premium: if let expiry = expiryDate { ... }` (строки 336-339) активация п
  - Фикс: Формиттер с [.withInternetDateTime, .withFractionalSeconds] + fallback без опции; при tier=premium и неразобранной дате активировать с разумным дефолтом и логом, а не молчать. Регрессионный тест: декодирование ответа с '....000Z' активирует премиум.
- **[P1]** `ios-2/Plink/Views/Settings/SettingsSlidePanel.swift:411` — Кнопка «Отменить подписку» лишь сбрасывает локальный флаг — Apple продолжает списывать деньги
  - Улика: SettingsSlidePanel.swift:410-415: destructive-кнопка вызывает `PremiumStatusManager.shared.deactivatePremium()` и анимирует isPremium=false. Автопродление в App Store при этом не трогается (реальная отмена возможна только через страницу подписок Apple, на которую ведёт соседняя кнопка «Управление по
  - Фикс: Удалить кнопку либо заменить её на тот же deep-link itms-apps://apps.apple.com/account/subscriptions (и/или showManageSubscriptions). Регрессионный тест: UI-тест, что «отмена» ведёт на управление подпиской, а не мутирует локальный статус.
- **[P1]** `ios-2/Plink/V5/PlinkAppearanceScreen.swift:309` — Пейволл-шит в «Оформлении» — тупик: кнопка «Оформить Plink+» не открывает покупку, а повторно вызывает select()
  - Улика: PlinkPlusPaywallSheet.swift-часть (PlinkAppearanceScreen.swift:309-317): кнопка делает `onSubscribe(); dismiss()`. В AppearanceRootView (строки 82-86) onSubscribe = `{ paywallItem = nil; Task { await store.select(item) } }` — никакого StoreKit-флоу, select() снова упирается в `guard !item.premium ||
  - Фикс: В onSubscribe презентовать PlinkPlusPaywall(trigger: .theme), после успешной покупки вызвать entitlement.refresh() и затем select(item); показать lastError тостом. Регрессионный тест: после activatePremium() select() премиум-темы проходит без рестарта.
- **[P2]** `ios-2/Plink/Services/StoreKitManager.swift:135` — Мёртвый параллельный IAP-стек (StoreKitManager + ContextualPaywallView + PaywallView) с третьим набором product ID и несуществующими эндпоинтами
  - Улика: StoreKitManager бьёт в /api/subscription/verify и /api/subscription/status (строки 135, 161), но subscription.ts не зарегистрирован в app.ts и его шапка прямо запрещает подключение — в рантайме это 404. Product ID 'com.plink.app.plus.*' (строки 18-20) — третий набор, не совпадающий ни с клиентом, ни
  - Фикс: Удалить StoreKitManager, ContextualPaywallView и PaywallView (или свести к единственному StoreManager-стеку). Регрессионный тест: линт/грep-проверка в CI, что упоминание '/api/subscription/' и второго Transaction.updates-слушателя отсутствует.
  - ✅ ИСПРАВЛЕНО: billing.ts PLANS = plink.plus.1m/3m/12m (+легаси-алиасы)
- **[P2]** `ios-2/Plink/V5/PlinkAppearanceRegistry.swift:283` — handleEntitlementExpiry() никто не вызывает; при даунгрейде остаются премиум-тема приложения и эмоджи-пак
  - Улика: grep: единственное упоминание handleEntitlementExpiry — его определение (PlinkAppearanceRegistry.swift:283). Ролбэк при истечении Plink+ не выполняется. Страховочный clamp в PremiumStatusManager.loadPersistedState (строки 181-195) чистит только bubbleStyleID и plink.liveTheme, но не 'plink.appThemeI
  - Фикс: В PremiumStatusManager.onPremiumStatusChanged(false) вызывать AppearanceRootView.sharedStore.handleEntitlementExpiry(); в loadPersistedState добавить clamp для appThemeID/emojiPackID. Регрессионный тест: deactivatePremium() возвращает appThemeID к fallback.
- **[P2]** `ios-2/Plink/Services/PremiumStatusManager.swift:153` — syncFromServer не получает серверный expiry, а флаг serverConfirmed — мёртвый
  - Улика: AuthService.swift:146-149 и 177-180 передают `expiry: PremiumStatusManager.shared.subscriptionExpiry` (эхо локального состояния), PlinkApprovedV4Root.swift:311 — `expiry: nil`, хотя сервер знает premiumUntil (/api/billing/entitlements его отдаёт, но эндпоинт никем не вызывается). В результате премиу
  - Фикс: Прокинуть premiumUntil из ответа /users/me (или /api/billing/entitlements) в syncFromServer; удалить serverConfirmed либо использовать его как гейт для activate* из локального fallback. Регрессионный тест: syncFromServer(true, date) сохраняет именно серверную дату.

## be-social — 4.5/10

- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:421` — Голосовые DM обходят блокировку: /messages/dm/voice не проверяет UserBlock
  - Улика: В хендлере voice проверяется только существование получателя и tombstone (строки 441-456), запроса к prisma.userBlock нет вообще — в отличие от текстового DM (строка 344) и фото (строка 620), где есть findFirst по userBlock в обе стороны. Заблокированный пользователь продолжает слать голосовые забло
  - Фикс: Скопировать в voice-хендлер тот же блок: prisma.userBlock.findFirst({ OR: [{blockerID: me, blockedID: receiverId}, {blockerID: receiverId, blockedID: me}] }) → 403 BLOCKED; добавить muteRemainingSec('dm', me) и containsProfanity(body.content) как в POST /messages/dm.
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:1053` — PATCH-редактирование сообщения обходит лимит 280 символов и всю модерацию
  - Улика: Отправка ограничена 280 символами (dmSendBody, schemas/requests.ts:64) и проходит muteRemainingSec/containsProfanity (строки 299-321). Редактирование же принимает до 4000: `if (!content || typeof content !== 'string' || content.length > 4000)` и не вызывает ни containsProfanity, ни проверку мута. Сц
  - Фикс: В PATCH /messages/dm/message/:messageId выровнять лимит до 280 и прогнать content через muteRemainingSec('dm', me) + containsProfanity с тем же ответом MODERATION_MUTED.
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/friends.ts:231` — Заявку в друзья можно слать заблокировавшему: POST /friends/request не смотрит UserBlock
  - Улика: В хендлере нет ни одного обращения к prisma.userBlock; при этом на строке 342 уходит APNs-пуш получателю: pushToUser(targetId, { body: `@... хочет добавить вас в друзья` }). moderation.ts при блокировке специально удаляет висящие заявки («иначе блокировка обходится повторным принятием старого запрос
  - Фикс: Перед созданием заявки проверить userBlock в обе стороны; при наличии блока отвечать 404 'User not found' (не раскрывая факт блокировки), пуш не отправлять.
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/groups.ts:48` — В группу можно добавить любого пользователя без согласия, дружбы и вопреки блокировке
  - Улика: POST /groups (строки 48-60) и POST /groups/:id/members (319-330) принимают произвольные userID: нет проверки существования пользователя, дружбы и UserBlock. GroupMember.userID в схеме без FK на User (schema.prisma:457), так что даже несуществующие id молча записываются. Сценарий: заблокированный соз
  - Фикс: При создании/добавлении: отфильтровать ids через prisma.user.findMany (существование, deletedAt=null), исключить пары с UserBlock в любую сторону, в идеале требовать дружбу с добавляющим; в схему добавить FK GroupMember.userID → User с onDelete: Cascade.
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/groups.ts:209` — Все групповые write-эндпоинты без rate limit при global: false
  - Улика: rateLimit зарегистрирован с `global: false` (app.ts:118), лимиты действуют только там, где объявлен config.rateLimit. В groups.ts нет ни одного `config: { rateLimit }` — POST /groups, POST /groups/:id/messages (включая base64-фото до ~1.5MB в БД), POST /:id/members, react не троттлятся вовсе. Для ср
  - Фикс: Добавить config.rateLimit на все write-роуты groups: сообщения ~30/мин, фото ~10/мин, создание групп ~5/мин, добавление участников ~20/мин.
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/moderation.ts:62` — 3 сговорившихся аккаунта автоматически шадоу-банят любого пользователя
  - Улика: autoHide: при 3 нерассмотренных жалобах от разных reporterID на targetType='user' выполняется `prisma.user.update({ data: { shadowbanned: true } })` + invalidateUserSnapshot — мгновенно, без участия модератора. Существование цели при подаче жалобы не проверяется, регистрация открытая: три самореганн
  - Фикс: Для targetType='user' убрать автодействие (оставить только приоритет в очереди) либо поднять порог и требовать минимальный возраст/репутацию аккаунта заявителя; скрывать автоматически только контент (message/room).
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:244` — DELETE /messages/dm/:friendId физически удаляет весь тред у обоих участников
  - Улика: «Clears the entire DM thread between me and friendId (both directions)» — deleteMany по OR обеих направлений (строки 278-285). Один участник в одностороннем порядке безвозвратно уничтожает копию переписки второго (включая его собственные сообщения и медиа), без подтверждения и без варианта «удалить 
  - Фикс: По умолчанию делать per-user скрытие (дописать me в deletedForIDs всем сообщениям треда), физическое удаление у обоих — только по явному параметру forBoth=true; физически чистить сообщения, скрытые обоими.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:356` — Проверка блокировки/tombstone в DM fail-open при ошибке БД
  - Улика: Весь блок peer-check (findUnique + userBlock.findFirst) обёрнут в try/catch: `catch (e) { console.warn('[dm] peer check:', e?.message); }` — при любом исключении (schema drift, таймаут) проверки пропускаются и сообщение создаётся. Тот же паттерн в фото (строка 630) и voice (454). Enforcement блокиро
  - Фикс: Ловить только известные ошибки отсутствующих колонок; на прочие отвечать 503, а не продолжать отправку. Минимум — вынести userBlock-проверку из try/catch.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:1132` — Typing-эндпоинт шлёт события произвольному пользователю без проверки дружбы и блокировок
  - Улика: POST /messages/dm/:friendId/typing без какой-либо валидации friendId вызывает gateway.notifyUser(request.params.friendId, { event: 'typing', fromUserId: me }) — заблокированный (или вообще посторонний) может дёргать «печатает…» у любого пользователя по id.
  - Фикс: Перед notifyUser проверять дружбу или отсутствие UserBlock (можно кэшировать), иначе отвечать success без фактической рассылки.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/groups.ts:98` — N+1 в GET /groups: отдельный count непрочитанных на каждую группу
  - Улика: `await Promise.all(groups.map(async (g) => { const unread = await prisma.groupMessage.count({ where: { groupID: g.id, ... } }) }))` — пользователь в 50 группах генерирует 50 count-запросов на каждый поллинг списка чатов; плюс отдельный count для пагинации в GET /:id/messages (строка 145).
  - Фикс: Один groupBy: prisma.groupMessage.groupBy({ by: ['groupID'], where: { groupID: { in: groupIds }, deletedAt: null, senderID: { not: me } }, _count: true }) с фильтром по lastReadAt на приложении, либо raw SQL с JOIN по groupMember.lastReadAt.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/groups.ts:200` — Реакции группы — read-modify-write JSON без транзакции: потерянные обновления
  - Улика: Хендлер react читает msg.reactions, модифицирует Set в памяти и целиком перезаписывает JSON: `await prisma.groupMessage.update({ data: { reactions } })`. Две одновременные реакции разных участников → last-write-wins, реакция одного из них молча исчезает.
  - Фикс: Перейти на таблицу реакций как в DM (DirectMessageReaction с @@unique([messageID, userID])) либо обновлять JSON атомарно через $transaction с повторным чтением/raw jsonb_set.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/groups.ts:340` — Выход из группы и передача владельца — четыре запроса без транзакции
  - Улика: delete member → findMany rest → update role → update ownerID выполняются последовательно вне $transaction. Падение между шагами или два одновременных leave оставляют группу с ownerID, указывающим на вышедшего, либо без участника-владельца (все дальнейшие admin-действия отваливаются 403).
  - Фикс: Обернуть в prisma.$transaction([...]) c выбором нового владельца внутри транзакции.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/friends.ts:144` — Self-heal дружбы пишет в БД на каждом GET /friends и делает O(n²) сканы
  - Улика: Два цикла с `asTarget.some(...)`/`asInitiator.some(...)` (квадратичная сложность по числу друзей) и последовательными await prisma.friendship.create внутри read-эндпоинта, который клиент поллит. При асимметричных строках каждый GET порождает write-запросы; ответ клиенту при этом уже сформирован без 
  - Фикс: Вынести self-heal в accept-хендлер (там уже createMany обеих направлений) или в фоновую задачу; в GET заменить some на Set по userID.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/friends.ts:538` — Поиск друзей: id endsWith — несиндексируемый скан и перебор пользователей по суффиксу uuid
  - Улика: `{ id: { endsWith: q } }` в OR поиска: LIKE '%q' не использует индекс (full scan users на каждый кейстрок), однобуквенный запрос отдаёт до 20 произвольных аккаунтов — дискавери/enumeration чужих профилей практически без усилий.
  - Фикс: Убрать endsWith по id (оставить equals), поднять минимальную длину запроса до 2-3 символов.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/messages.ts:89` — Список чатов строится по последним 800 сообщениям — старые треды исчезают из инбокса
  - Улика: GET /messages/unread берёт `take: 800` последних DM по всем перепискам и агрегирует в памяти. У активного пользователя один болтливый тред вытесняет остальные: чаты, чьи сообщения не попали в последние 800, пропадают из списка вместе с unread-счётчиками, хотя переписка существует.
  - Фикс: Заменить на groupBy/raw SQL: DISTINCT ON (пара) последнее сообщение + count(isRead=false) по receiverID=me — один запрос без лимита 800.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/moderation/autoMod.ts:49` — Map strikes растёт бесконечно — записи никогда не удаляются
  - Улика: `const strikes = new Map(...)`: muteUser только добавляет/обновляет ключи `scope::userId` (строка 64), удаления нет нигде (mutes чистятся лениво в muteRemainingSec, strikes — никогда). Ключи со scope вида group:<uuid> и dm накапливаются до рестарта процесса — медленная утечка памяти на долгоживущем 
  - Фикс: При muteRemainingSec()===0 удалять и strikes-ключ, если окно истекло; либо периодический prune по windowStart старше STRIKE_WINDOW_MS.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/moderation.ts:286` — dismiss жалобы снимает shadowbanned безусловно — отменяет и ручной бан
  - Улика: Ветка dismiss для targetType='user' выполняет `data: { shadowbanned: false }` без проверки, чем бан был вызван. Модератор, отклоняя одну ложную жалобу, молча разбанивает пользователя, которого другой модератор забанил через action:'ban' по другой жалобе (updateMany закрывает все открытые, но уже зак
  - Фикс: Снимать shadowbanned при dismiss только если он был выставлен автоскрытием (например, отдельное поле autoHiddenAt) либо требовать явного action:'unban'.

## ios-dm-friends — 4.5/10

- **[P1]** `ios-2/Plink/Services/DMChatService.swift:298` — Удалённые собеседником сообщения воскресают как «призраки» и не исчезают
  - Улика: Фильтр «оптимистичных локальных» в loadHistory: `!serverIds.contains(msg.id) && msg.id.count > 20 // UUID optimistic && msg.timestamp >= newestServer.addingTimeInterval(-60)`. Но серверные id — тоже UUID (prisma/schema.prisma:162 `id String @id @default(uuid())`, 36 символов > 20). Любое недавнее со
  - Фикс: Заменить эвристику по длине id на явный признак: хранить Set<String> pendingLocalIDs при создании оптимистичного сообщения и в merge оставлять только их; после ответа POST/таймаута — удалять из set.
- **[P1]** `ios-2/Plink/Services/DMChatService.swift:720` — Тихая потеря сообщения при неудачной отправке: ошибка не показывается, ретрая нет, пузырь потом исчезает
  - Улика: catch в sendMessage лишь пишет `errorMessage = error.localizedDescription`. В DMChatView этот errorMessage рендерится только если содержит «Мут»/«замучены»/«отклонено» (DMChatView.swift:862-863), т.е. сетевые ошибки пользователь не видит вообще; пузырь остаётся с одной серой галочкой, как будто отпр
  - Фикс: Добавить у DirectMessage статус sendState (.sending/.failed/.sent): failed показывать красным с кнопкой «Повторить», в merge никогда не выбрасывать .sending/.failed; генерические ошибки отправки показывать (alert/баннер без фильтра по ключевым словам).
- **[P1]** `ios-2/Plink/Services/DMChatService.swift:236` — Пагинации истории нет: доступны только последние 200 сообщений, и это окно перекачивается каждые 5 секунд
  - Улика: Клиент всегда зовёт `api.request("messages/dm/\(friendId)")` без cursor/offset; бэкенд отдаёт фиксированное окно `orderBy: { createdAt: 'desc' }, take: 200` (backend-3/src/routes/messages.ts:172-173). В DMChatView нет «загрузить раньше», а разделитель дней захардкожен `DMDayDivider(label: "Сегодня")
  - Фикс: Добавить cursor-параметр (before=<createdAt|id>, limit) на GET /messages/dm/:friendId, в клиенте — подгрузку старой страницы при скролле вверх с prepend в conversations; квайет-поллинг заменить на after=<lastKnownId> (только дельта).
- **[P1]** `ios-2/Plink/V4/V4FriendsView.swift:1338` — «Отметить как прочитанное» подменяет chatDidOpen: чат «висит открытым», все будущие сообщения авточитаются, бейдж молчит
  - Улика: Контекст-меню и свайп зовут `dmService.chatDidOpen(friendId: friend.id)` (строки 1338 и 1430), но парного chatDidClose нет — openFriendId остаётся установленным, пока пользователь не откроет/закроет какой-нибудь настоящий чат. Пока это так: unreadCount(for:) всегда 0 для этого друга, refreshUnread п
  - Фикс: Для mark-as-read использовать существующий POST /messages/dm/:friendId/read + локально обнулить unreadByFriend, не трогая openFriendId.
- **[P1]** `ios-2/Plink/V4/V4FriendsView.swift:1384` — Все swipeActions в списке чатов — мёртвый код: строки лежат в VStack/ScrollView, а не в List
  - Улика: friendChatRow и groupChatRow навешивают `.swipeActions(edge: .trailing/.leading, ...)` (строки 1138-1163, 1384-1436), но рендерятся внутри `sectionCard { ForEach(...) }`, где sectionCard = `VStack(spacing: 0)` (строка 600) внутри обычного `ScrollView` (строка 142). Модификатор swipeActions работает 
  - Фикс: Перевести список чатов на List с .listStyle(.plain) и прозрачным фоном, либо удалить swipeActions и оставить contextMenu, чтобы не держать нерабочий код.
- **[P1]** `ios-2/Plink/Views/Chat/DMChatView.swift:191` — Скролл дёргает читателя в самый низ по глобальному historyEpoch — включая события чужих чатов и смену isRead
  - Улика: `.onChange(of: dmService.historyEpoch) { _, _ in ... scrollToBottom(proxy:) }` — historyEpoch один на все диалоги и инкрементируется на любое применение снапшота: флип isRead (когда собеседник прочитал ваше сообщение, `changed` учитывает `$0.isRead != $1.isRead`, DMChatService.swift:320), реакции, а
  - Фикс: Сделать epoch per-conversation (или публиковать id изменённого диалога) и автоскроллить только если пользователь у низа ленты либо это его собственная отправка/новое входящее в текущем чате.
- **[P2]** `ios-2/Plink/Services/DMChatService.swift:303` — Возможен дубль сообщения с одинаковым id при медленной отправке или расхождении часов >45 с
  - Улика: Дедуп локального против серверного снапшота — только по тексту и окну времени: `$0.text == loc.text && abs($0.timestamp.timeIntervalSince(loc.timestamp)) < 45` (без сравнения senderID). Если квайет-полл принесёт серверную копию in-flight сообщения, а |server createdAt − локальный Date()| ≥ 45 с (пер
  - Фикс: Дедупить по pendingLocalIDs (см. фикс призраков) и после замены localID→saved.id удалять из массива возможную вторую копию с тем же id.
- **[P2]** `ios-2/Plink/Services/DMChatService.swift:15` — Offline-состояния нет: история, превью и «удаление чата» живут только в памяти
  - Улика: `conversations`, `lastMessages`, `unreadByFriend`, `lastPreviewByFriend`, `lastActivityAtByFriend` — обычные @Published-словари без персистентности (сохраняется только archivedFriendIDs в UserDefaults). Холодный старт без сети = пустой список чатов без превью и пустые диалоги. deleteChat при ошибке 
  - Фикс: Минимум: кэшировать последний снапшот диалога и превью инбокса на диск (JSON/SwiftData) и показывать до первого ответа сети; для deleteChat — очередь отложенных операций с повтором при восстановлении сети.
- **[P2]** `ios-2/Plink/V4/V4FriendsView.swift:319` — Поллинг-шторм: ~3 запроса в секунду на вкладке друзей, 1-секундный unread-цикл никогда не останавливается
  - Улика: Одновременно крутятся: refreshUnread каждую 1 с (DMChatService.swift:76-84; startUnreadPolling зовётся из V4FriendsView:326,337 и PlinkApprovedV4Root:322, вызовов stopUnreadPolling в проекте нет), loadFriends каждую 1 с (`try? await Task.sleep(nanoseconds: 1_000_000_000) ... store?.refreshQuietly()`
  - Фикс: Опираться на уже подключённый DMRealtimeClient, поллинг сделать fallback-ом 15-30 с; останавливать unread-цикл при уходе в фон/с вкладки; в loadFriends публиковать только при фактическом изменении (Equatable-сравнение).
- **[P2]** `ios-2/Plink/Services/DMChatService.swift:650` — Молчаливое обрезание текста ниже заявленного лимита 280 из-за маркера стиля пузыря
  - Улика: UI обещает и принуждает 280 символов (DMChatView.swift `charLimit = 280`, счётчик «280/280»), но сервис резервирует место под wire-маркер: `let body = String(payload.prefix(max(1, 280 - markerLen)))`, где markerLen = длина `"[[bs:...]]"` (~10-16 символов). Сообщение в 280 символов молча теряет хвост
  - Фикс: Считать лимит в композере как 280 − markerLen (динамически от текущего стиля) либо передавать styleID отдельным полем API, не встраивая в content.
- **[P2]** `ios-2/Plink/Services/FriendManager.swift:204` — setPinned возвращает true при ошибке сети — закреп не синхронизируется и молча расходится между устройствами
  - Улика: catch: `// Local pin already applied — list still works offline; Logger.api.warn("Friend pin sync failed"); return true` — вызывающий togglePin в V4FriendsView (строки 1443-1451) показывает тост «закреплён», хотя сервер не узнал о пине; повторной синхронизации нет, на втором устройстве и после переу
  - Фикс: Возвращать false/статус sync-failed и ретраить пин при следующем loadFriends (сервер уже присылает isPinned/pinOrder — сверять и досылать расхождения).

## ios-auth-nav — 4.5/10

- **[P1]** `ios-2/Plink/RaveCloneApp.swift:240` — Deep links — тупик: комната джойнится на сервере, но UI никогда не открывается
  - Улика: handleDeepLink: `let room = try await roomService.joinRoom(code: code); deepLinkRoom = room` (стр. 239-241), но в body PlinkApp (стр. 195-221) нет ни .fullScreenCover(item: $deepLinkRoom), ни .alert для friendInviteAlert (стр. 255) — оба @State пишутся и никогда не читаются. Параллельно AuthLaunchGa
  - Фикс: Один консьюмер: в PlinkApprovedV4Root подписаться на DeepLinkRouter (onReceive/onChange pendingLink), по .room(code) звать joinRoom и ставить roomToPresent, по .friendInvite показывать алерт и слать POST заявку; из PlinkApp убрать дублирующий .onOpenURL/handleDeepLink (оставить единственный в AuthLa
- **[P1]** `ios-2/Plink/AppShell/PlinkSidebarShell.swift:13` — iPad/Mac: сайдбар-навигация мертва — List без selection, NavigationLink(value:) без destination
  - Улика: `List {` (стр. 13) без параметра selection, а пункты — `NavigationLink(value: section)` (стр. 53). Value-based ссылки в сайдбаре NavigationSplitView работают только через List(selection:) или navigationDestination — ни того, ни другого нет, поэтому `selection` (Binding из PlinkAppShell) никогда не м
  - Фикс: Заменить на `List(selection: $selection)` c `.tag(section)`/NavigationLink(value:) (тип selection совпадает — AppSection), и заменить заглушку «Комнаты» реальным списком комнат (V4RoomsViewLive или его адаптация).
- **[P1]** `ios-2/Plink/Features/Auth2026/AuthLaunchGate.swift:95` — RegistrationView2026 недостижим: LoginView2026 никогда не вызывает onRegister — регистрация идёт в обход условий и правил пароля
  - Улика: AuthLaunchGate передаёт `onRegister: { authRoute = .registration }` (стр. 95-98), но в LoginView2026 колбэк только объявлен (`let onRegister: () -> Void`, LoginView2026.swift:19) и ни разу не вызван — обе кнопки-переключателя лишь делают `isSignUp.toggle()` (стр. 87-95, 242-256). Маршрут .registrati
  - Фикс: В LoginView2026 заменить внутренний signup-режим вызовом onRegister() (убрать isSignUp-ветку), чтобы регистрация всегда шла через RegistrationView2026; либо перенести туда terms-чекбокс и валидацию пароля.
- **[P1]** `ios-2/Plink/Networking/APIClient.swift:161` — plinkSessionExpired постится с фонового потока — AuthLaunchGate мутирует @State и зовёт @MainActor-метод вне main
  - Улика: `NotificationCenter.default.post(name: Notification.Name("plinkSessionExpired"), object: nil)` (стр. 161 и 232) выполняется внутри async request APIClient — на фоновом экзекьюторе (класс не @MainActor). NotificationCenter.publisher доставляет на потоке отправителя, а в AuthLaunchGate.swift:69-75 обр
  - Фикс: В APIClient оборачивать post в DispatchQueue.main.async (оба места), либо в AuthLaunchGate подписываться через .receive(on: DispatchQueue.main) / Task { @MainActor in ... } внутри обработчика.
- **[P1]** `ios-2/Plink/AppShell/PlinkAppShell.swift:26` — На Max/Plus iPhone поворот в landscape меняет size class → подмена шелла V4Root↔Sidebar, сброс состояния и дисмисс fullScreenCover комнаты
  - Улика: `if horizontalSizeClass == .regular { PlinkSidebarShell(...) } else { PlinkApprovedV4Root() }` (стр. 26-35). На iPhone Pro Max/Plus в landscape horizontalSizeClass = .regular, поэтому поворот телефона живьём пересобирает корневой шелл: PlinkApprovedV4Root уничтожается вместе со всеми @State-сторами 
  - Фикс: Для iOS различать устройство, а не size class: `UIDevice.current.userInterfaceIdiom == .pad ? PlinkSidebarShell : PlinkApprovedV4Root` (size-class-ветку оставить только для macOS/iPad), либо поднять fullScreenCover комнаты выше переключателя шеллов.
- **[P1]** `ios-2/Plink/Networking/APIClient.swift:283` — Неверный пароль на логине показывает «Сессия истекла. Войдите заново.»
  - Улика: Бэкенд на неверные креды отвечает 401 `{ error: 'Invalid credentials' }` (backend-3/src/routes/auth.ts:112,118). APIClient на любой 401 бросает APIError.unauthorized, чей errorDescription — «Сессия истекла. Войдите заново.» (стр. 283); тело ответа сервера отбрасывается. LoginView2026 показывает имен
  - Фикс: Для isPublicAuthEndpoint-путей парсить тело 401 (parseErrorMessage) и бросать serverError/conflict с текстом сервера, а unauthorized со «Сессия истекла» оставить только для авторизованных маршрутов; на клиенте маппить в «Неверный email или пароль».
- **[P1]** `ios-2/Plink/RaveCloneApp.swift:157` — Два экземпляра DeepLinkRouter: тапы по пушам уходят в .shared, UI подписан на другой
  - Улика: PlinkApp создаёт `@StateObject private var deepLinkRouter = DeepLinkRouter()` (стр. 157), а PushNotificationService при тапе на пуш вызывает `DeepLinkRouter.shared.handle(url)` (PushNotificationService.swift:116). Комментарий в самом DeepLinkRouter.swift:20-23 прямо требует единый объект («им нужен 
  - Фикс: В PlinkApp использовать `@StateObject private var deepLinkRouter = DeepLinkRouter.shared` (или ObservedObject на .shared), чтобы пуш и SwiftUI-иерархия работали с одним роутером.
- **[P2]** `ios-2/Plink/Features/Auth2026/RegistrationView2026.swift:20` — Чек-лист пароля требует цифру, но canRegister её не проверяет
  - Улика: passwordIssues показывает пункт «Минимум 1 цифра» (стр. 31), однако `canRegister` (стр. 20-26) проверяет только `password.count >= 6` — кнопка активна и регистрация проходит при неснятом требовании в чек-листе. Противоречивый UX: список «невыполненных» условий горит, а форма отправляется.
  - Фикс: Синхронизировать: `canRegister` должен требовать `passwordIssues.isEmpty`, либо убрать пункт про цифру из подсказки (согласовать с серверной валидацией zod).
- **[P2]** `ios-2/Plink/Features/Auth2026/AuthLaunchGate.swift:108` — Нет таймаута на restore-сплэше: медленная сеть держит юзера на заставке до 60 секунд
  - Улика: restoreSession ждёт `dependencies.authService.restoreAndValidateSession()` (стр. 110) без собственного таймаута; внутри — refreshJWT + fetchCurrentUser через URLSession.shared с дефолтным timeoutIntervalForRequest = 60 c. При «висящем» соединении (плохой Wi-Fi, captive portal) CinematicSplashView по
  - Фикс: Обернуть валидацию в race с таймаутом 5-8 c: по истечении при наличии кэшированного пользователя уходить в .offlineAuthenticated (ревалидация — фоном), иначе в .authentication.
- **[P2]** `ios-2/Plink/AppShell/PlinkPhoneTabShell.swift:10` — Мёртвый код навигации: PlinkPhoneTabShell и storePending/consumePending не используются
  - Улика: PlinkPhoneTabShell не инстанцируется нигде (grep "PlinkPhoneTabShell(" — только определение); PlinkAppShell для compact использует PlinkApprovedV4Root. Внутри мёртвого шелла — заглушка Rooms (стр. 31) и двойной пост plinkSignedOut (стр. 61-62: signOut() уже постит, затем post ещё раз). Аналогично De
  - Фикс: Удалить PlinkPhoneTabShell, неиспользуемые @State в PlinkApp и либо удалить storePending/consumePending, либо реально задействовать их в AuthLaunchGate вместо pendingURL (у них есть персист через UserDefaults, переживающий kill приложения — у pendingURL нет).
- **[P2]** `ios-2/Plink/RaveCloneApp.swift:198` — AppDependencies пересоздаётся при каждом рендере body PlinkApp — DiscoveryService теряет состояние
  - Улика: В body: `AuthLaunchGate(dependencies: AppDependencies(apiClient: ..., ...))` (стр. 198-206) — новый объект класса на каждую переоценку body (её триггерит любой @Published deepLinkRouter). AppDependencies.init при nil-параметре создаёт новый `DiscoveryService(apiClient:roomService:)` (AppDependencies
  - Фикс: Создать AppDependencies один раз в init PlinkApp (let/@State) и передавать готовый экземпляр в AuthLaunchGate.
- **[P2]** `ios-2/Plink/Features/Auth2026/LoginView2026.swift:290` — authenticate() без клиентской валидации и без индикатора загрузки
  - Улика: authenticate (стр. 290-309) шлёт запрос при пустых email/password (нет guard), email не триммится от пробелов автодополнения; во время isLoading кнопка лишь disabled — ни ProgressView (в RegistrationView2026 он есть, стр. 104), ни блокировки второй кнопки-переключателя. Поля не имеют textContentType
  - Фикс: Добавить guard на непустые trimmed email/password с локальной ошибкой, ProgressView в кнопку на время isLoading, и .textContentType(.emailAddress)/.password для автозаполнения.

## ios-watchroom — 5.5/10

- **[P0]** `ios-2/Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift:29` — WatchRoomModel создаётся заново при каждом пересчёте body — комната сбрасывается, старый WebSocket утекает
  - Улика: makeScreenForRoom(): `let model = makeV2Model(...) ... return AnyView(WatchRoomScreen(model: model))` вызывается напрямую из WatchRoomContainer.body (WatchRoomContainer.swift:22). WatchRoomScreen держит модель как простое `@Bindable var model` (WatchRoomScreen.swift:24) — никто не владеет ею через @
  - Фикс: Владеть моделью в WatchRoomContainer: `@State private var model: WatchRoomModel?`, создавать один раз в hydrateSession() (перенести makeV2Model туда), передавать в WatchRoomScreen готовый экземпляр. В onDisappear контейнера вызывать model?.leaveRoom() (он идемпотентен), а не только REST-leave. Допол
  - ✅ ИСПРАВЛЕНО: модель в @State контейнера, создаётся один раз в hydrateSession
- **[P0]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:90` — lastError никогда не очищается и рисуется полноэкранной ошибкой ПОВЕРХ играющего видео
  - Улика: `public private(set) var lastError: String?` — 13 мест записи (строки 306, 310, 676, 686, 934, 955, 1095, 1097, 1366, 1569, 1584), ни одного `lastError = nil`. PlayerStage.swift:22 передаёт его как roomError в PlayerSurfaceView, где `activeError = coordinator.lastError ?? ... ?? roomError` (PlayerVi
  - Фикс: Разделить каналы: в PlayerSurfaceView передавать только медиа-ошибку (отдельное поле mediaError, заполняемое лишь в connect()/prepare-фейлах), а остальные lastError показывать как RoomToast с автоскрытием. Очищать mediaError при успешном prepare/recovery.
  - ✅ ИСПРАВЛЕНО: отдельный канал mediaError; в оверлей плеера идёт только он
- **[P1]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:692` — Подтверждение pending-команд — no-op: каждая команда хоста даёт ложный «Command timeout» через 10 с
  - Улика: clearPendingActionsIfConfirmed(state:) игнорирует параметр state и лишь фильтрует записи СТАРШЕ 10 с: `pendingActions.filter { Date().timeIntervalSince(action.timestamp) < 10 }`. RealtimeRoomState не содержит actionId (RealtimeEnvelope.swift:25-35) — сматчить подтверждение не по чему. Значит подтвер
  - Фикс: Считать команду подтверждённой, когда пришло авторитетное состояние с seq/epoch, выпущенное после отправки команды (сохранять lastSeq на момент отправки и сравнивать в clearPendingActionsIfConfirmed), либо добавить actionId в sync.state на сервере. Таймаут-ошибку ставить только если подтверждение ре
- **[P1]** `ios-2/Plink/Features/WatchRoom/PlayerControlLayer.swift:348` — Меню скорости не закрыто guard'ом canControl — гость ломает себе синхрон, хост — зрителям
  - Улика: В bottomBar меню «Скорость» вызывает `embedded?.setRate(Float(rate))` без проверки canControl (в отличие от seekZone:246, transportButton:296 и play/pause:265). Гость ставит 2× → локальная позиция убегает; OrderedSyncController при следующем авторитетном состоянии делает жёсткий seek и возвращает ra
  - Фикс: Спрятать/задизейблить меню скорости для не-хоста (по образцу `Label("Управляет хост")`), а для хоста либо добавить rate в протокол sync.command, либо честно пометить функцию как локальную и исключить конфликт с sync (не применять коррекцию поверх пользовательского rate).
- **[P2]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:476` — countdownTask не отменяется в disconnect(), а повторный тап Play во время отсчёта запускает мгновенный play
  - Улика: disconnect() отменяет stateChangesTask/statePumpTask/reactionExpiryTask/danmakuPollTask/ambientSampleTask, но не countdownTask (строка 89). Выход из комнаты во время отсчёта 3-2-1: задача доживает до дедлайна и вызывает sendPlayCommand() по уже разобранному координатору (isHost не сбрасывается). Плю
  - Фикс: В disconnect() добавить `countdownTask?.cancel(); countdownTask = nil; countdownRemaining = nil`. В sendPlayWithCountdown обрабатывать `countdownRemaining != nil` отдельной ранней веткой `return`, а не общим else.
- **[P2]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:217` — Force-unwrap URL из серверного roomCode — краш шита приглашения на невалидном коде
  - Улика: `URL(string: "plink://r/\(displayRoomCode)")!` и строкой ниже `URL(string: "https://plink.app/r/\(displayRoomCode)")!` (строка 221). displayRoomCode = серверный roomCode.uppercased() без валидации; пробел или не-ASCII символ в коде (баг/смена формата на бэкенде) → URL(string:) вернёт nil → краш при 
  - Фикс: Санитизировать код (`filter { $0.isLetter || $0.isNumber }`) перед интерполяцией или собирать через URLComponents с фолбэком на roomId-префикс.
- **[P2]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:404` — Фолбэк кладёт долгоживущий session JWT в query string — ровно то, от чего защищались строкой выше
  - Улика: extractYouTubeNativePlaybackSource: при недоступности /media/stream-token — `guard let legacy = api.authToken else { return nil }; token = legacy`, дальше строка 413-416 кладёт его в `URLQueryItem(name: "token", value: token)`. Комментарий на строке 395 сам это запрещает: «never put the long-lived s
  - Фикс: Убрать legacy-ветку (бэкенд уже отдаёт stream-token) — при ошибке возвращать nil и падать на встроенный плеер; либо логировать метрику и требовать медиа-скоуп токен всегда.
- **[P2]** `ios-2/Plink/Features/WatchRoom/PlayerStage.swift:50` — BufferingOverlay не показывается именно в mid-playback rebuffer, для которого создан
  - Улика: Условие: `if model.coordinator.isBuffering && hasSurface && model.coordinator.isPlaying == false && ...`. Но при ребуфере YouTube шлёт state 3, который выставляет только isBuffering=true, не трогая isPlaying (EmbeddedPlaybackController.swift:475-477: `case 3: isBuffering = true`), т.е. во время восп
  - Фикс: Убрать `isPlaying == false` из условия (ребуфер как раз случается при isPlaying=true) либо ориентироваться на `state == 3 && isReady`.
- **[P2]** `ios-2/Plink/Features/WatchRoom/WatchRoomModel.swift:1253` — Таймер очистки реакций сбрасывается каждой новой реакцией — при потоке реакции не исчезают
  - Улика: scheduleReactionExpiry(): `reactionExpiryTask?.cancel(); reactionExpiryTask = Task { sleep 3s; reactions.removeAll { $0.timestampMs < cutoff } }` вызывается из handleReaction на КАЖДУЮ реакцию. Если реакции приходят чаще, чем раз в 3 с (активная комната), таймер бесконечно отменяется и чистка не вып
  - Фикс: Не отменять предыдущий таймер (пусть каждый Task чистит свой срез), либо один периодический sweep-Task, запускаемый в connect() и отменяемый в disconnect().

## be-billing — 6/10

- **[P1]** `backend-3/src/routes/billing.ts:444` — Renewal webhook is a permanent no-op (reads non-existent field expiresDateMs)
  - Улика: handleRenewal is called with the object returned by JoseConfig.verifySignedTransaction (line 365 → line 338), whose shape (jose-config.ts lines 227-235) exposes `expiresAt: number|null` and has NO `expiresDateMs` field. Yet handleRenewal reads it: `const expiresAt = txInfo.expiresDateMs ? new Date(p
  - Фикс: Read `txInfo.expiresAt` (already ms since epoch): `const expiresAt = txInfo.expiresAt ? new Date(txInfo.expiresAt) : null;`. Add a unit test that feeds a VerifiedTransaction with expiresAt set and asserts Subscription.expiresAt and User.premiumUntil are updated. Impact: every SUBSCRIPTION_RENEWED/DI
- **[P1]** `backend-3/src/routes/billing.ts:133` — No appAccountToken binding — a valid Apple JWS can be claimed by any account (first-submit-wins)
  - Улика: The header comment promises `- Bind appAccountToken or originalTransactionId to authenticated user` (line 56), but grep across backend-3/src shows appAccountToken is referenced only in that comment — never read or verified. The only ownership control is: if `existingTx && existingTx.userId !== reque
  - Фикс: Extract appAccountToken from the verified JWS payload and require it to equal a per-user token the client obtained at purchase time (bind at StoreKit purchase via Product.PurchaseOption.appAccountToken). Reject verify when the JWS appAccountToken does not match request.user. Regression test: submit 
- **[P2]** `backend-3/src/routes/billing.ts:196` — Subscription upsert keyed on id=originalTransactionId but create omits id → update branch is dead, duplicate active rows accumulate
  - Улика: `tx.subscription.upsert({ where: { id: originalTransactionId }, create: { userID: ..., /* no id set */ }, update: {...} })` (lines 196-215). Subscription.id is `@id @default(uuid())` (schema.prisma:281) and the create block never sets id, so the row is created with a random uuid, not originalTransac
  - Фикс: Key the upsert on a unique field that is actually populated — add `@unique` to Subscription.originalTransactionId and use `where: { originalTransactionId }`, or set `id: originalTransactionId` in the create block. Regression test: call verify twice with the same originalTransactionId and assert exac
- **[P2]** `backend-3/src/routes/billing.ts:135` — Idempotency/ownership key uses client-supplied body.transactionId, not the verified JWS transactionId
  - Улика: `existingTx = await prisma.transactionRecord.findUnique({ where: { transactionId: transactionId || originalTransactionId } })` (lines 135-137) and the TransactionRecord upsert (line 176) both key on `transactionId || originalTransactionId`, where `transactionId` comes from request.body (validated on
  - Фикс: Use the verified JWS transactionId as the record/idempotency key and ignore or validate-against-JWS the body value. Regression test: submit a valid JWS with a mismatched body.transactionId and assert the stored record uses the JWS value. Impact: a client can replay one valid JWS under different arbi
- **[P2]** `backend-3/src/routes/webpay.ts:68` — Web-payment grant idempotency is check-then-act with no unique DB constraint (double-grant on concurrent webhook delivery)
  - Улика: grantWebPremium guards only with `findFirst({ where: { originalTransactionId: 'yookassa:'+paymentId } })` then create (lines 68-97). Subscription.originalTransactionId has no @unique (schema.prisma:294). YooKassa can deliver payment.succeeded more than once and retries on non-2xx; two overlapping de
  - Фикс: Add `@unique` to Subscription.originalTransactionId and rely on a caught unique-violation (or upsert) instead of check-then-act, so a duplicate delivery is a no-op. Regression test: invoke grantWebPremium twice for the same paymentId concurrently and assert one row / one extension. Impact: retried o
- **[P2]** `backend-3/src/routes/billing.ts:60` — Apple webhook lacks notificationUUID dedup and timestamp precedence claimed in the header
  - Улика: Header claims `- Webhook processing idempotent by notification UUID` and `- Refund/revoke wins over stale purchase events using timestamps` (lines 60-61). The handler (lines 314-398) never reads or stores notificationUUID and never compares signedDate/transaction timestamps; handleRenewal unconditio
  - Фикс: Persist processed notificationUUIDs (unique) and short-circuit duplicates; before re-activating in handleRenewal, skip when a more recent revokedAt/revocationDate exists. Regression test: deliver REFUND then a stale DID_RENEW and assert premium stays revoked; deliver the same notification twice and 

## be-realtime — 6.5/10

- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/roomEventBus.ts:76` — Zod-схема шины дропает все системные броадкасты: senderId обязан быть UUID
  - Улика: roomEventBus.ts:76 — `senderId: z.string().uuid()` в схеме chat.broadcast, а публикуют не-UUID: rooms.ts:128/152/178 и ai.ts:461 шлют `senderId: 'plink-ai'`, messageRouter.ts:322 и rooms.ts:982 — `senderId: 'plink-ai-moderator'`. Подписчик (roomEventBus.ts:137-139) при ошибке валидации молча дропает
  - Фикс: Ослабить схему: `senderId: z.string().min(1).max(64)` (или union UUID | литералы сервисных id 'plink-ai', 'plink-ai-moderator'). Дополнительно валидировать событие в publish(), чтобы расхождение падало у отправителя, а не молча у получателя. Регресс-тест: опубликовать в bus событие с senderId 'plink
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/rooms.ts:697` — Кик не отзывает WebSocket: gateway.broadcastToRoom не существует, сокет кикнутого остаётся в комнате
  - Улика: rooms.ts:697-698 — `if (gateway?.broadcastToRoom) { await gateway.broadcastToRoom(...) }`, но у RealtimeGateway (gateway.ts) такого метода нет (есть только notifyUser, publishChatMessage, shutdown; grep по репо подтверждает — единственное упоминание broadcastToRoom это сам вызов). Optional chaining 
  - Фикс: Добавить в RealtimeGateway метод kickUser(roomId, userId): публикация типизированного события participant.kicked через RoomEventBus; каждая реплика в eventToServerMessage/листенере закрывает локальные сокеты этого userId в этой комнате (code 4003) и чистит presence-lease. Вызвать из kick-роута. Регр
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/roomPubSub.ts:85` — Гонка unsubscribe/subscribe: subscribedChannels чистится после await — быстрый реконнект теряет Redis-подписку
  - Улика: roomPubSub.ts:84-87 — в unsubscribe(): `await this.subscriber.unsubscribe(...)` и только ПОТОМ `this.subscribedChannels.delete(roomId)`; subscribe() (строки 68-71) проверяет `subscribedChannels.has(roomId)` и при true пропускает реальный SUBSCRIBE. Сценарий: последний сокет комнаты закрылся → releas
  - Фикс: В обоих классах удалять roomId из subscribedChannels ДО await subscriber.unsubscribe (и при ошибке возвращать), либо сериализовать subscribe/unsubscribe per-channel через цепочку промисов. Регресс-тест: unsubscribe и сразу subscribe того же канала конкурентно; убедиться, что после resolve обоих сооб
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/gateway.ts:459` — retainRoom: ранний return без ожидания in-flight подписки; ошибка doRetainRoom навсегда отравляет refcount
  - Улика: gateway.ts:456-459 — `this.roomRefs.set(roomId, currentRefs + 1); if (currentRefs > 0) return;` — второй конкурентный join возвращается, не дожидаясь in-flight doRetainRoom (ветка ожидания на 463-467 достижима только при currentRefs===0). Если doRetainRoom бросил (транзиентная ошибка Redis subscribe
  - Фикс: Хранить не только промис, но и признак «подписка установлена»: если листенеры ещё не зарегистрированы — всегда `await roomRetainInFlight`; при ошибке doRetainRoom откатывать refs и удалять частично созданные листенеры, чтобы следующий join повторил subscribe. Регресс-тест: замокать pubsub.subscribe 
- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/rooms.ts:1155` — GET /rooms/:id/messages тянет полный base64 фото (mediaData) ради Boolean — до сотен МБ на запрос
  - Улика: rooms.ts:1149-1156 — select включает `mediaData: true`, но поле используется только в `hasMedia: Boolean(m.mediaType && m.mediaData)` (строка 1189) и в ответ не попадает. limit до 200 (строка 1097), фото до 2.25MB → base64 ~3MB (rooms.ts:952). Комната с 200 фото-сообщениями: один запрос catch-up под
  - Фикс: Убрать mediaData из select; hasMedia получать без загрузки тела: отдельное boolean-поле в схеме (hasMedia/mediaSize) либо raw-запрос `mediaData IS NOT NULL`. Регресс-тест: комната с фото-сообщениями — проверить, что ответ содержит hasMedia:true, а RSS процесса не растёт пропорционально размеру фото.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/roomStateStore.ts:95` — Механизм эпох мёртв: bumpEpoch нигде не вызывается и не персистит, STALE_EPOCH недостижим
  - Улика: Три улики: (1) BUMP_EPOCH Lua (roomStateStore.ts:87-96) вычисляет epoch+1 и возвращает его БЕЗ записи в state — два последовательных bump вернут одно и то же число; (2) grep: bumpEpoch вызывается только из integration-теста, в проде — ни разу; role.changed (contracts P1-64) тоже никогда не эмитится;
  - Фикс: Либо достроить: BUMP_EPOCH должен SET state с новой эпохой (и seq=0), появиться вызов на смене хоста + эмит role.changed, а sync.command — принимать epoch клиента и валидировать; либо честно выпилить epoch из контракта до появления миграции хоста. Регресс-тест: bumpEpoch дважды подряд возвращает раз
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/gateway.ts:410` — decrementRoomPresence неатомарен (zrem + zcount) — дубли participant.left; 2s-таймаут finalize бросает decrement
  - Улика: gateway.ts:410-415 — zrem и zcount раздельными командами: два одновременно закрывающихся сокета одного юзера могут оба увидеть count 0 и оба опубликовать participant.left (в отличие от bumpRoomPresence, где MULTI-пайплайн). Плюс finalize (gateway.ts:154-157) оборачивает distributed cleanup в Promise
  - Фикс: Свернуть zrem+zcount (+обновление room-index) в один Lua-скрипт, возвращающий финальный count — тогда ровно один вызывающий увидит 0. Таймаут оставить, но логировать проигрыш гонки. Регресс-тест: конкурентное закрытие двух соединений одного юзера — ровно один participant.left.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/roomQueueStore.ts:28` — Очередь комнаты и муты — in-memory-first: расхождение между репликами и lost-update при конкурентных enqueue
  - Улика: roomQueueStore.ts:28-30 — `const mem = queues.get(roomId); if (mem) return mem;` — память первична и никогда не инвалидируется из Redis: на второй реплике enqueue уйдёт в Redis, но первая продолжит отдавать свой кэш вечно. enqueueRoomMedia (48-69) — неатомарный read-modify-write: два конкурентных PO
  - Фикс: Минимально: убрать memory-first чтение (Redis — источник истины, память только как fallback при недоступности) и сериализовать enqueue через WATCH/Lua RPUSH-структуру; муты — в Redis SET с TTL. Регресс-тест: два параллельных enqueue — в очереди оба элемента.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/rooms.ts:118` — Очередь видео: streamURL обходит SSRF/scheme-валидацию, delete/play доступны любому участнику
  - Улика: rooms.ts:118 — `streamURL: typeof body.streamURL === 'string' ? body.streamURL : ''` — принимается любой URL (javascript:, file:, внутренние хосты) и броадкастится всем клиентам для проигрывания, тогда как POST /rooms для того же mediaItem.streamURL валидирует схему и блокирует приватные сети (rooms
  - Фикс: Переиспользовать B6-валидатор URL для body.streamURL в POST /queue; на delete/play добавить проверку `room.hostID === request.user.id` (или authorId элемента). Регресс-тест: участник-не-хост получает 403 на play/delete; streamURL 'http://169.254.169.254/' отклоняется.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/rooms.ts:516` — PATCH /rooms/:id/appearance «броадкастит» через fastify.io, которого не существует — реалтайм-доставка тем мертва
  - Улика: rooms.ts:516 — `fastify.io?.to(`user:${p.userID}`).emit(...)` — Socket.IO нигде в проекте не регистрируется (grep по `socket.io`/`decorate('io'` — ноль совпадений; реалтайм построен на ws + RealtimeGateway). Optional chaining превращает весь цикл по участникам в no-op: смена темы комнаты никому не д
  - Фикс: Заменить на существующий механизм: gateway.notifyUser(p.userID, {...}) либо типизированное событие room.appearance.updated через RoomEventBus (+ ветка в eventToServerMessage). Регресс-тест: два клиента в комнате, хост меняет тему — второй получает событие по WS без рефетча.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/realtime/connectionRegistry.ts:148` — broadcastLocal молча пропускает сокеты с backpressure >256KB, не закрывая их — тихая потеря sync/чата
  - Улика: connectionRegistry.ts:147-149 — `if ((s.bufferedAmount ?? 0) > 256 * 1024) continue;` — сообщение просто не отправляется. Гард на 512KB (messageRouter.ts:142-150, checkSlowConsumer) срабатывает только при ВХОДЯЩЕМ сообщении; зритель, который ничего не шлёт (типовой кейс — пассивный просмотр), на мед
  - Фикс: Считать пропуски на сокете (счётчик на PlinkSocket); после N подряд пропусков или M секунд непрерывного backpressure — socket.close(1011, 'Slow consumer'), клиент переподключится и заберёт снапшот. Регресс-тест: замокать bufferedAmount>лимита на N броадкастов — сокет должен быть закрыт, а не вечно п

## be-auth — 7/10

- **[P1]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/middleware/auth.ts:129` — authenticate drops mfa/auth_time claims — admin step-up 2FA can never pass
  - Улика: authenticate builds `request.user = { id: payload.id, username: snapshot.username, email: snapshot.email, role: snapshot.role };` (auth.ts:129-136), omitting the `mfa` and `auth_time` claims that issueTokenPair signs into the JWT (tokens.ts:36-37). But routes/admin.ts requireAdmin gates EVERY admin 
  - Фикс: Propagate the verified claims onto request.user: add `mfa: payload.mfa === true` and `auth_time: typeof payload.auth_time === 'number' ? payload.auth_time : undefined` in both authenticate (auth.ts:129) and optionalAuth (auth.ts:154). Role/ban/deletion must still come from the DB snapshot; only mfa/
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/utils/tokens.ts:57` — JWT audience allowlist is never enforced (tokens signed without aud)
  - Улика: issueTokenPair signs via `fastify.jwt.sign(payload)` (tokens.ts:57) and the payload (tokens.ts:32-53) contains no `aud`; app.ts sign opts set only `{ algorithm:'HS256', iss }` (app.ts:114). Verification requests `verify: { audience: config.JWT_AUDIENCES }` (app.ts:115), but fast-jwt skips a claim va
  - Фикс: Add `aud: config.JWT_AUDIENCES` to the sign config (app.ts:114) or set an `aud` claim in the payload (tokens.ts:32) so the verify-side allowlist actually rejects mismatches; alternatively drop the audience option to avoid a false sense of enforcement.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/gdpr.ts:58` — GDPR export leaks twofaSecret, twofaBackupCodes and fcmToken
  - Улика: `const { password, ...safeData } = userData as any;` (gdpr.ts:58) strips only the password. The findUnique returns all User scalar columns, which per schema.prisma include twofaSecret (line 46), twofaBackupCodes (line 48) and fcmToken (line 42). These are written verbatim into the downloadable JSON 
  - Фикс: Destructure out the security-sensitive fields before sending: `const { password, twofaSecret, twofaBackupCodes, fcmToken, ...safeData } = userData as any;` (gdpr.ts:58), matching the treatment already applied to password.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/gdpr.ts:160` — anonymize does not revoke sessions or block existing tokens
  - Улика: The /gdpr/anonymize handler (gdpr.ts:160-218) rewrites username/email/avatar/fcmToken and scrubs messages but never calls revokeAllUserTokens and never sets deletedAt. authenticate only blocks on deletedAt/bannedUntil (auth.ts:117-127), so existing access tokens keep working, and /auth/refresh (whic
  - Фикс: Call `await revokeAllUserTokens(userId)` inside the anonymize handler (gdpr.ts, before the reply at line 214), and consider setting deletedAt so authenticate/refresh reject the account.
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/routes/auth.ts:322` — refresh path does not check deletedAt
  - Улика: /auth/refresh selects `{ id, username, email, role, isPremium, bannedUntil }` (auth.ts:322-324) and only guards on bannedUntil (auth.ts:327). deletedAt is not selected or checked. tombstoneAccount revokes tokens best-effort with `.catch(() => {})` (accountTombstone.ts:134), so if revocation fails th
  - Фикс: Add `deletedAt: true` to the select (auth.ts:324) and return 401 when set, mirroring the signin deletedAt guard (auth.ts:126).
- **[P2]** `/Users/hellcart/Desktop/PROJECTS/PLINK/backend-3/src/utils/tokens.ts:132` — refresh-token reuse detection only scans the last 20 revoked tokens
  - Улика: verifyRefreshToken's theft-detection scan is limited with `take: 20` on revoked tokens ordered by createdAt desc (tokens.ts:128-133). A stolen refresh token that was rotated out more than 20 generations ago no longer matches any of the scanned rows, so presenting it returns a plain null/401 (tokens.
  - Фикс: Widen or remove the take limit (e.g. scan all revoked tokens for the user, or key reuse detection off a persisted token family/jti) so reuse of any previously issued token in the chain revokes the whole family.

## be-web — 7/10

- **[P1]** `backend-3/src/routes/web.ts:181` — OG-афиши всегда отдаются как SVG (sharp не установлен) — мессенджеры не показывают превью
  - Улика: sendOG: `const { default: sharp } = await import('sharp')` c комментарием «sharp не входит в зависимости» и фолбэком `return reply.type('image/svg+xml').send(svg)`. Проверено: в backend-3/package.json пакета sharp нет, т.е. catch-ветка срабатывает всегда. При этом og:image указывает на /og/….png (we
  - Фикс: Добавить sharp (или @resvg/resvg-js) в dependencies и убрать @ts-expect-error; либо на старте рендерить статичный default.png и для комнат отдавать его, пока нет растеризатора. Дополнительно логировать попадание в catch, чтобы регресс был виден.
- **[P2]** `backend-3/src/routes/web.ts:143` — QR-код инвертирован (светлые модули на тёмном фоне) — часть камер его не читает
  - Улика: qrSVG: `color: { dark: '#eafaf7ff', light: '#00000000' }` — «тёмные» модули рисуются почти белым на прозрачном фоне, а страница тёмная (--velvet:#060d0f). Это инвертированный QR: по спецификации модули должны быть темнее фона; штатные камеры старых iOS и ряд Android-сканеров инвертированные коды не 
  - Фикс: Рисовать классический QR: тёмные модули (#04201b) на светлой подложке — например, light:'#eafaf7ff', dark:'#04201bff' и белая карточка-подложка с padding у .qr-block svg.
- **[P2]** `backend-3/src/routes/web.ts:292` — font:600 13px/1 inherit — невалидный шорткат, кнопка «Скопировать код» рендерится шрифтом браузера
  - Улика: button.copy { … font:600 13px/1 inherit; … }. CSS-wide keyword `inherit` нельзя использовать как компонент шортката (только как всё значение целиком) — декларация отбрасывается парсером целиком. Кнопки не наследуют шрифт по умолчанию, поэтому «Скопировать код» отображается дефолтным UA-шрифтом форм 
  - Фикс: Заменить на `font-family:inherit; font-size:13px; line-height:1; font-weight:600` (или `font:600 13px/1 -apple-system,…` полным стеком).
- **[P2]** `backend-3/src/routes/web.ts:460` — /plus: input font-size 15px — iOS Safari авто-зумит страницу при фокусе на email/пароле
  - Улика: .checkout input { … font-size:15px; … }. Mobile Safari автоматически масштабирует страницу при фокусе на поле с font-size < 16px; после blur зум не откатывается — layout чекаута «уезжает» ровно в момент оплаты. Viewport (web.ts:198) без maximum-scale (что правильно для a11y), поэтому зум реально сра
  - Фикс: Поднять font-size инпутов до 16px.
- **[P2]** `backend-3/src/routes/web.ts:254` — h1 без overflow-wrap: длинное неразрывное имя комнаты/профиля вылезает за карточку и обрезается
  - Улика: h1 { font-size:clamp(30px,7.4vw,44px); … } — нет overflow-wrap/word-break. Имя комнаты допускает до 120 символов без пробелов (backend-3/src/schemas/requests.ts:45 `name: z.string().min(1).max(120)`), username — до 32 символов слитно. На /r/:code имя подставляется в `<h1 class="rise d1">${escHTML(op
  - Фикс: Добавить в h1 (и p.sub) `overflow-wrap:anywhere`; опционально ограничить видимую длину заголовка на сервере.
- **[P2]** `backend-3/src/routes/web.ts:570` — /r/:code на мобильном: пустая вторая ячейка hero-grid даёт двойной вертикальный зазор
  - Улика: Разметка: `<div class="rise d3">${phoneMockup(…)}</div>` — вторая ячейка .hero-grid. Ниже 900px .phone { display:none } (web.ts:378), но ячейка-обёртка остаётся в потоке: .hero-grid { grid-template-columns:1fr; gap:34px } (web.ts:368) добавляет 34px row-gap перед нулевой строкой, плюс .steps { margi
  - Фикс: Скрывать обёртку целиком: перенести display:none на ячейку (например, класс .phone-cell { display:none } / media ≥900px { display:block }), либо выносить мокап из грида на мобильном.
- **[P2]** `backend-3/src/routes/web.ts:792` — Разрыв каскада rise: appIdentity и storeBadges появляются мгновенно посреди анимируемых блоков
  - Улика: На / порядок: `p.sub rise d2` → `${storeBadges()}` (без .rise) → `.filmstrip rise d4`; на /r: `a.btn rise d3` → `${storeBadges()}` (web.ts:562, без .rise) → `.qr-block rise d4`; appIdentity() (web.ts:540, 785) тоже без .rise. Пока соседние элементы ещё в opacity:0 (fill-mode both + delay до .32s), б
  - Фикс: Дать .rise с соответствующей задержкой блокам appIdentity и .badges (d3 на главной, d3/d4 на /r), либо убрать стаггер вовсе.
- **[P2]** `backend-3/src/routes/web.ts:685` — A11y: динамические статусы без aria-live — ошибка оплаты и подсказки не озвучиваются
  - Улика: `<div class="err" id="pay-err"></div>` заполняется через textContent при ошибке платежа (web.ts:728-735), `#install-hint` (web.ts:561) показывается по таймеру, `#copy-text` меняется на «Скопировано» (web.ts:594) — ни у одного нет aria-live/role=status, скринридер об изменениях не узнаёт. Дополнитель
  - Фикс: Добавить role="status" (aria-live="polite") на #pay-err, #install-hint и обёртку #copy-text; тикету дать role="group" или заменить aria-label на визуально скрытый текст.
- **[P2]** `backend-3/src/routes/web.ts:348` — A11y: контраст мелкого текста ниже WCAG — footer ~1.9:1, тексты на --dim ~3:1
  - Улика: footer { …; color:#2c443f } на фоне --velvet:#060d0f — контраст ~1.9:1 при 10px тексте. --dim:#48645f (web.ts:216) даёт ~3.05:1 и используется для содержательного мелкого текста: .ticket-label (10px, web.ts:272), .meta (12px, web.ts:259), .ticket-note (11px), .plan .per, .checkout label. Для текста 
  - Фикс: Осветлить токены: footer до уровня --dim и выше, --dim до ~#6f938c (проверить до ≥4.5:1 на #060d0f); декоративные надписи внутри aria-hidden мокапа можно не трогать.
- **[P2]** `backend-3/src/routes/web.ts:864` — /r/:code не фильтрует isActive — завершённые комнаты рендерятся как «СЕАНС ИДЁТ»
  - Улика: `prisma.room.findFirst({ where: { code, hidden: false }, … })` — поле isActive (schema.prisma:98) не учитывается. Для неактивной комнаты лендинг показывает штамп «СЕАНС ИДЁТ» (web.ts:555), «синхрон» и счётчик «в зале: N», хотя сеанс закончился; ветка «Комната закрыта» срабатывает только для hidden/н
  - Фикс: Либо добавить isActive в where (показывая «Комната закрыта»), либо для isActive:false менять штамп/мету на «Сеанс завершён» и убирать счётчик.
- **[P2]** `backend-3/src/routes/web.ts:359` — Мобильная вёрстка: .badges без flex-wrap — на узких экранах бейджи сторов сжимаются/переносят текст
  - Улика: .badges { display:flex; gap:10px; justify-content:center; margin-top:12px } — без flex-wrap. Два двухстрочных бейджа (иконка 22px + паддинги 32px + текст «Загрузите в / App Store», «Скоро в / Google Play») суммарно ~275-310px; при заданном ANDROID_STORE_URL (второй бейдж с иконкой) на 320px-экранах 
  - Фикс: Добавить `flex-wrap:wrap` в .badges (бейджи станут в столбик на узких экранах) или уменьшить паддинги/шрифт в @media (max-width:390px).
- **[P2]** `backend-3/src/routes/web.ts:302` — Мёртвый CSS-блок .stores — разметка использует .badges/.store-badge
  - Улика: Правила .stores / .stores a / .stores a:hover / .stores a.disabled (web.ts:302-308) не соответствуют ни одному элементу: storeBadges() генерирует `<div class="badges">` c `<a class="store-badge">` (web.ts:108-112), а disabled-вариант — `<span class="store-badge disabled">`, для которого есть отдельн
  - Фикс: Удалить блок .stores целиком.
- **[P2]** `backend-3/src/routes/web.ts:888` — /r/:code отдаётся без Cache-Control — непоследовательно с соседними роутами
  - Улика: Хендлер /r/:code вызывает только securityHeaders(reply, nonce) и send() — заголовка Cache-Control нет, тогда как `/` ставит `public, max-age=300` (web.ts:839), а /plus — `no-store` (web.ts:902). Без явного заголовка разрешено эвристическое кэширование (браузер/прокси): счётчик «в зале: N» и название
  - Фикс: Явно ставить `Cache-Control: no-store` (или `private, max-age=30`) в хендлере /r/:code, включая обе 404-ветки.
