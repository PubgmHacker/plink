# M17 — Финальная полировка до 10/10 (все рекомендации аудита)

## Бэкенд

### Очередь видео — Redis-персист + управление (рек. №4 + Redis)
- `src/realtime/roomQueueStore.ts` — write-through в Redis (`roomqueue:<roomId>`, TTL 24ч, fail-open в память). Очередь переживает рестарт сервера.
- `DELETE /api/rooms/:id/queue/:itemId` — убрать из очереди (участник).
- `POST /api/rooms/:id/queue/:itemId/play` — «включить сейчас»: промоут в начало + `nowPlaying` в wire-бродкасте.
- Оба роута бродкастят обновлённую очередь всем участникам по чат-протоколу.

### Беседы — unread / удаление / реакции (рек. №2, №5)
- Prisma: `GroupMember.lastReadAt`, `GroupMessage.deletedAt`, `GroupMessage.reactions Json` + миграция `20260719160000_group_reads_reactions`.
- `GET /api/groups` — теперь отдаёт `unreadCount` по каждой беседе.
- `POST /api/groups/:id/read` — отметка прочтения.
- `DELETE /api/groups/:id/messages/:messageId` — soft delete (своё — любой; чужое — owner/admin).
- `POST /api/groups/:id/messages/:messageId/react` — тогл-реакция `{emoji}`, хранение `{emoji: [userIds]}`.
- Удалённые сообщения скрыты из выдачи и unread-счётчиков.

## iOS

### Фото в беседах картинкой (рек. №1)
- `GroupPhotoView` — авторизованная загрузка (Bearer-заголовок, надёжнее AsyncImage), скруглённая карточка 220pt, плейсхолдер/ошибка, подпись под фото.

### Unread-бейджи и прочтение (рек. №2)
- Бейдж непрочитанного в строке беседы; `markRead` при открытии и при новых сообщениях в открытом чате.
- `GroupChatService.unreadTotal` — для колокольчика.

### Быстрый поллинг (рек. №3)
- Поллинг открытой беседы ускорен 3с → 2с.

### Управление очередью (рек. №4)
- Чипы очереди над чатом — теперь меню: «Включить сейчас» (только хост) и «Убрать из очереди».
- `WatchRoomModel.removeFromQueue / playFromQueue` (REST + wire-бродкаст), `RoomQueueWire.Event.nowPlaying`.

### Реакции и удаление в беседах (рек. №5)
- Контекстное меню на сообщении: 5 быстрых реакций (❤️ 😂 🔥 👍 😮) + «Удалить» (своё / owner / admin).
- Лента реакций под баблом с счётчиками; своя реакция подсвечена; тап — тогл.

### Единый paywall (рек. №6)
- Все 3 вызова старого `PaywallView` (ProfileView, SettingsSlidePanel, V4ProfileViewLive) заменены на `PlinkPlusPaywall(trigger: .settings)`.
- Копирайт capacity приведён к реальному лимиту бэкенда: «20 участников вместо 10» — функциональная фича Plink+ (лимит уже есть на сервере: free = 10).

### Центр уведомлений (рек. №7)
- Новый `PlinkInboxView` — sheet с непрочитанными личными сообщениями и беседами (pull-to-refresh, empty state «Всё прочитано»).
- Колокольчик на главной теперь живой: бейдж = DM unread + unread бесед, заглушка-alert удалена.
- Без remote push (не требует Apple Developer) — всё in-app.

## Деплой
1. `npx prisma migrate deploy` — применить миграции `20260719120000_group_chats` и `20260719160000_group_reads_reactions`.
2. Redis опционален: без него очередь работает в памяти (fail-open).
3. Переменные: `OPENROUTER_API_KEY` (NSFW-модерация фото), `AI_ACTIONS_ENABLED` (ИИ ставит очереди).
