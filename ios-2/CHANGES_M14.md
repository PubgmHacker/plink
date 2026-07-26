# Plink — пакет улучшений M14 (UX-ревью «глазами пользователя»)

Всё из UX-ревью, кроме колокольчика уведомлений (отложен по решению).
Бэкенд НЕ менялся — все фичи работают на существующем протоколе.

## 1. Аватар на главной — настоящий
- Была жёсткая буква «П»; теперь — первая буква username + фото профиля, если загружено (`PlinkAvatarURL.resolve`).
- Файл: `V4/V4HomeViewLive.swift`.

## 2. V4-тема продолжается в комнате
- Корень сохраняет выбранную тему (`plink.v4ThemeName`), комната читает акцент через `PlinkRoomAccent.current`.
- Акцент виден: обводка кнопки play, цифры отсчёта, кнопка и шит приглашения.
- Файлы: `V4/PlinkApprovedV4Root.swift`, `Features/WatchRoom/RoomCountdown.swift` (PlinkRoomAccent), `PlayerControlLayer.swift`.

## 3. Приглашение одной кнопкой: QR + шер-линк
- Новый `RoomInviteSheet`: крупный код, QR на universal link `https://plink.app/join/<roomId>`, кнопки «Поделиться» и «Скопировать».
- Кнопка в топ-баре комнаты (`person.badge.plus`) вместо простого ShareLink.
- Файлы: `Features/WatchRoom/RoomInviteSheet.swift` (new), `PlayerControlLayer.swift`.

## 4. «Продолжить просмотр» на главной
- Карточка с постером, прогресс-баром и «Осталось N мин» для недосмотренного (2–95% прогресса).
- Тап создаёт комнату; хост автоматически делает синхронный seek к сохранённому таймкоду (`PlinkPendingResume` → `sendSeekCommand`).
- Файлы: `Services/WatchlistService.swift` (PlinkPendingResume), `V4/V4HomeViewLive.swift`, `WatchRoomScreen.swift`.

## 5. Одноразовый хинт в комнате
- При первом входе: капсула «Тапни по экрану — появятся контролы», 4 секунды, больше не показывается (`@AppStorage plink.roomControlsHintShown`).

## 6. Онбординг: wow-экран синхронности
- Первый экран — анимация `SyncedPhonesArt`: два телефона с одинаковым прогрессом и таймкодом.
- Новый текст: «один таймкод у всех. Пауза у друга — пауза у вас».

## 7. «Все» в «Смотрят сейчас» — больше не тупик
- Кнопка ведёт на вкладку «Комнаты» (`openRoomsTab` → `tab = 1`).

## 8. Картинка-в-картинке (PiP)
- Native-плеер: `canStartPictureInPictureAutomaticallyFromInline = true` — PiP сам стартует при сворачивании.
- Встроенный плеер (WKWebView): `allowsPictureInPictureMediaPlayback = true`.
- Файлы: `Playback/PlaybackCoordinator.swift`, `Playback/EmbeddedPlaybackController.swift`.

## 9. «Друг сейчас смотрит — присоединиться»
- Вкладка «Друзья»: секция «Сейчас смотрят» — друзья, хостящие активную публичную комнату (сопоставление по hostName).
- Кнопка «Присоединиться» открывает комнату через существующий механизм `.plinkRoomCreated`.
- Файлы: `V4/V4FriendsView.swift`, `V4/PlinkApprovedV4Root.swift`.

## 10. Watchlist «Посмотреть позже»
- Новый `WatchlistService` (UserDefaults, до 100 записей).
- Закладка (bookmark) в результатах поиска; горизонтальная лента на главной; удаление через долгий тап.
- Файлы: `Services/WatchlistService.swift` (new), `Views/Home/UnifiedSearchView.swift`, `V4/V4HomeViewLive.swift`.

## 11. Отсчёт 3-2-1 перед стартом
- Хост жмёт play при ≥ 2 участниках → все видят общий отсчёт (общая точка старта в epoch ms), потом синхронный play.
- Едет по чат-протоколу (маркер `\u2063plink.count\u2063`) — как голосования M13, без изменений бэкенда.
- Один в комнате — мгновенный старт без отсчёта.
- Файлы: `Features/WatchRoom/RoomCountdown.swift` (new), `WatchRoomModel.swift`, `PlayerControlLayer.swift`, `WatchRoomScreen.swift`.

## Сборка
- `xcodegen generate` — новые файлы подхватятся автоматически (папки уже в target sources).
- Новых зависимостей и изменений project.yml нет.
