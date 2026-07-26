# Plink Closed Beta Checklist

**Version:** 1.0
**Date:** 2026-07-13
**GPT-5.6 ADR-003:** versioned release gate document

---

## 1. Release Gate

- [ ] iOS build собран из зафиксированного commit ветки `feat/v5-on-v4`
- [ ] Backend развёрнут из зафиксированного commit ветки `feat/billing-admin-implementation`
- [ ] Версии commit, build number, API и migration записаны в release notes
- [ ] Staging использует отдельный Railway service и отдельную базу данных
- [ ] Production secrets не скопированы в staging без необходимости
- [ ] Все миграции проходят на чистой staging-базе и на копии актуальной схемы
- [ ] Подготовлен rollback приложения, backend deploy и последней миграции
- [ ] Публичный `promote-self` отключён; роли назначаются через `scripts/bootstrap-admin.js`
- [ ] Логи не содержат access tokens, refresh tokens, пароли, приватные сообщения и base64 аватаров

## 2. Устройства и окружения

Проверить минимум на двух реальных iPhone с разными аккаунтами:

- [ ] Актуальная поддерживаемая версия iOS
- [ ] Минимальная поддерживаемая версия iOS
- [ ] Wi-Fi ↔ Wi-Fi
- [ ] Wi-Fi ↔ cellular
- [ ] Слабая сеть, потеря соединения и восстановление
- [ ] Light и Dark Mode
- [ ] Чистая установка и обновление поверх предыдущего build
- [ ] Обычный пользователь и admin-пользователь

## 3. Auth и onboarding

- [ ] Регистрация с валидным nickname проходит
- [ ] Nickname короче 5 и длиннее 32 символов отклоняется
- [ ] Кириллица, Unicode-шрифты, пробелы и запрещённые символы отклоняются
- [ ] Case-insensitive duplicate nickname отклоняется backend
- [ ] Вход, выход и повторный вход работают
- [ ] `signout-others` отзывает остальные refresh tokens
- [ ] Biometric RecentAuthGate появляется перед destructive actions
- [ ] Scheduled deletion отменяется при входе в grace period
- [ ] Ошибки сети и неверные credentials показаны понятно, без зависшего loading

## 4. Home и Unified Search

- [ ] Тап по Home search всегда открывает UnifiedSearchView
- [ ] Chips Всё, Видео, Сервисы, Комнаты фильтруют корректно
- [ ] Пустой запрос, отсутствие результатов и ошибка сети имеют отдельные states
- [ ] Быстрый ввод не создаёт гонки или устаревшие результаты
- [ ] Видео открывает ожидаемый сценарий выбора/создания комнаты
- [ ] Room result выполняет join и открывает WatchRoom
- [ ] Несинхронизируемые сервисы явно помечены как watch alongside
- [ ] Нет обещания sync для Netflix, Disney+, Кинопоиска и аналогов

## 5. Room Creation

- [ ] Все четыре шага доступны: Service → Content → Settings → Creating
- [ ] Назад/вперёд не сбрасывает введённые данные неожиданно
- [ ] YouTube search возвращает и выбирает видео
- [ ] VK/Rutube доступны только если их фактический provider работает
- [ ] Cinema service принимает URL и показывает предупреждение до создания
- [ ] Custom URL валидирует scheme, тип и поддерживаемый stream
- [ ] Privacy public и private сохраняется backend
- [ ] Лимиты участников 4/50 реально проверяются server-side
- [ ] Двойной тап Create не создаёт две комнаты
- [ ] Ошибка create позволяет retry без потери настроек
- [ ] Успешное создание открывает ровно одну WatchRoom

## 6. WatchRoom и синхронизация

- [ ] Manual create, room card, search result и AI confirm используют единый coordinator
- [ ] Join двух устройств показывает одинаковую комнату и media item
- [ ] Play/pause/seek хоста отражается у второго участника
- [ ] Замерены median drift и p95 drift
- [ ] Цель: median <500 ms, p95 <1.5 s
- [ ] Correction count не создаёт заметного дёргания playback
- [ ] 30-минутная сессия проходит без необработанного disconnect
- [ ] Протокол включает background на 30 секунд и 2 минуты
- [ ] Протокол включает Wi-Fi → cellular → Wi-Fi
- [ ] После reconnect участник возвращается к актуальной позиции
- [ ] Host leave, participant leave и room close обрабатываются корректно

## 7. AI actions

- [ ] Обычный chat не создаёт action случайно
- [ ] `create_room` возвращает preview, а не выполняется сразу
- [ ] Confirm выполняет action один раз
- [ ] Повторный confirm возвращает безопасный idempotent результат
- [ ] Чужой confirmationId отклоняется
- [ ] Истёкший через 5 минут action отклоняется с понятным UX
- [ ] Cancel не выполняет action
- [ ] AI не пишет «готово», пока backend не подтвердил success
- [ ] `get_friend_activity` не раскрывает активность без разрешённого relationship/privacy
- [ ] `build_queue` требует подтверждения выбранных элементов
- [ ] Audit log содержит actor, action, source, timestamp и result без чувствительного payload

## 8. Profile и avatar

- [ ] PhotosPicker запрашивает корректное разрешение
- [ ] Фото обрезается/масштабируется до лимита и не искажает ориентацию
- [ ] Файл >2 MB корректно обрабатывается до upload или отклоняется
- [ ] Backend проверяет MIME, размер и валидность изображения
- [ ] Avatar сохраняется после relaunch
- [ ] Avatar отображается на втором устройстве
- [ ] При ошибке изображения работает letter/color fallback
- [ ] Изменение nickname повторно проверяется client и server

## 9. Security и privacy

- [ ] Все protected endpoints без токена возвращают 401
- [ ] Обычный пользователь не получает admin endpoints и UI
- [ ] IDOR-проверка выполнена для rooms, profile, confirmations и avatar
- [ ] Rate limit включён для auth, username check, AI chat/confirm и avatar upload
- [ ] URL inputs не допускают `file:`, локальные адреса и SSRF через backend fetch
- [ ] Account deletion требует recent auth и имеет корректный grace period
- [ ] Privacy settings реально влияют на room visibility и friend activity

## 10. Performance и стабильность

- [ ] Cold launch не имеет заметного зависания после launch animation
- [ ] Unified Search не блокирует main thread
- [ ] Avatar upload не вызывает memory spike/crash
- [ ] 30-минутная WatchRoom не демонстрирует устойчивый рост памяти
- [ ] Повторное открытие sheets/fullScreenCover не создаёт дублированные экраны
- [ ] Crash-free rate beta ≥99%
- [ ] API error rate по core endpoints <1% без учёта намеренно вызванных 4xx

## 11. Beta operations

- [ ] Определены 10-25 тестировщиков и их типы устройств
- [ ] Есть короткая инструкция: что тестировать, куда писать баги, какие данные прикладывать
- [ ] Для багов используется шаблон: build, device/iOS, account role, steps, expected, actual, video/log timestamp
- [ ] Определён владелец triage и ежедневное окно разбора
- [ ] P0/P1/P2 severity согласована
- [ ] Есть kill switch или быстрый rollback для AI actions и проблемных providers

---

## Exit Criteria

Закрытая beta допускается, если:

- [ ] Нет открытых P0: security bypass, data loss, crash в core loop, duplicate room/action, невозможность войти или выйти из комнаты
- [ ] Все P1 имеют workaround и владельца с датой исправления
- [ ] Core flow проходит 10 раз подряд на двух реальных устройствах
- [ ] 30-минутный sync test соответствует drift targets (median <500ms, p95 <1.5s)
- [ ] Staging отделён от production
- [ ] Публичный self-promotion закрыт
- [ ] Rollback проверен, а не просто описан

---

## Release Record Template

```
Build: Plink-ios <commit> / Plink-backend <commit>
Build number: <CFBundleVersion>
API version: <version>
Migration: <name>
Date: <YYYY-MM-DD>
Staging URL: <url>
Tested by: <names>
Checklist version: 1.0
Result: GO / NO-GO
Notes: <any deviations or follow-ups>
```
