# Plink M16 — ИИ-модератор, беседы, реальные очереди, новые баблы и темы

## 1. ИИ-модератор в комнатах (backend + iOS)
- `src/moderation/autoMod.ts` — ядро модерации: словарь матов (RU/EN + обфускации), запрещённый контент (порнография и пр.), муты с эскалацией 60→180→600 сек, NSFW-проверка фото через vision-модель (OpenRouter, fail-open), аудит в `AIModerationAudit`.
- Чат комнаты (`messageRouter.ts`): маты → мут + системное сообщение «ИИ-модератор» всем участникам (wire `plink.mod`).
- Фото в комнате (`rooms.ts`): NSFW → фото не публикуется (скрыто), мут 600 сек, бродкаст события.
- iOS: `RoomAIModeration.swift` (декодер wire), `WatchRoomModel` (mutedUntil/mutedRemainingSec + перехват событий + код MUTED), `WatchChatComposer` (баннер мута с живым таймером M:SS, блокировка отправки).

## 2. Модерация в личке (DM)
- `messages.ts`: текст — мут за маты; фото — NSFW-проверка, отклонение + мут 600 сек.
- iOS `DMChatView`: красный баннер ИИ-модератора над полем ввода.

## 3. Модерация создания комнат
- POST /rooms: название/контент проверяются `violatesContentPolicy` → 422 CONTENT_BLOCKED. Нельзя создать комнату с порнографией/запрещёнкой.

## 4. Беседы (групповые чаты, как в Telegram)
- Prisma: модели GroupChat/GroupMember/GroupMessage + миграция `20260719120000_group_chats` (ЗАПУСТИТЬ: `npx prisma migrate deploy`).
- `src/routes/groups.ts`: создание (с модерацией названия), список с превью, сообщения (+after-поллинг), отправка текста/фото с полной ИИ-модерацией (мут по scope `group:<id>`), добавление участников, выход (с передачей владельца), переименование, отдача фото.
- iOS: `GroupChatService.swift` (API + поллинг), `GroupChatsView.swift` (список бесед, создание с выбором друзей, экран чата с баблами Plink, отправка фото, баннер модератора). Вход: карточка «Беседы» в «Чаты и общение».

## 5. Реальные очереди от ИИ (не шаблон)
- `src/realtime/roomQueueStore.ts` — очередь комнаты в памяти + wire `plink.queue`.
- `ai.ts`: детекция интента «поставь/добавь/очередь» в контексте комнаты → proposedAction `queue_video`; /ai/confirm-action РЕАЛЬНО вставляет в очередь и бродкастит всем.
- REST: GET/POST `/rooms/:id/queue` (с модерацией контента).
- iOS: `RoomQueue.swift` + перехват в `WatchRoomModel.roomQueue` + лента «Очередь N» над чатом.

## 6. Баблы — пересмотр
- Бесплатно только 2: «Тихий» (bubble-quiet) и «Неон» (bubble-accent). Животные/рамки убраны из free.
- Plink+ — 5 кино-баблов из референса 1:1 (PNG 9-slice из `CinemaBubbles/`): Арт-деко, Киноплёнка, Афиша, VIP Pass, Film Noir.
- Миграция старых ID в `migrateLegacyID` — ничего не ломается у существующих юзеров.

## 7. Анимированные темы Plink+
- 4 новых mp4 (референсы video-2..5) заменили старые: без звука, H.264 High@4.1, 720p/30fps, faststart — совместимо с iPhone X … iPhone 17 Pro Max.

## Деплой
1. Backend: `npx prisma migrate deploy` (миграция group_chats), затем рестарт.
2. Опционально env: `AI_NSFW_MODEL` (дефолт в autoMod.ts), требуется `OPENROUTER_API_KEY` для NSFW-проверки фото (без него — fail-open, текстовая модерация работает всегда).
3. iOS: `xcodegen generate` (добавлена папка CinemaBubbles) → сборка.
