# M35 — «Честные 10/10»: закрытие пробелов по пяти ролям аудита

## Пользователь
- Превью-шит перед созданием комнаты (hero + тап по карточке трендов) — TrendingPreviewSheet
- Реальный голосовой ввод в ИИ: V4SpeechRecognizer (SFSpeechRecognizer ru-RU + AVAudioEngine, partial results в поле, повторный тап — отправка)
- Динамические чипы-подсказки в ИИ из ответа сервера (lastSuggestions)
- Очистка истории чата ИИ (trash) + персистентная история между запусками
- История просмотров с прогресс-барами + подсказка при пустой; умный heroRoom (приоритет комнат друзей)
- CTA «Создать беседу» в Чатах (CreateGroupSheet)

## Маркетолог
- Виральная петля: ShareLink «Поделиться профилем» (https://plink.app/u/<username>, пара к DeepLinkRouter /u/)
- Funnel-аналитика: room_create_from_trending, ai_message_sent, home_preview_opened (AnalyticsService)

## Архитектор / Фулл-стак
- GET /api/realtime/time — authoritative server clock (REST fallback для clock-sync, rate limit 120/min)
- Уже было подтверждено в коде: rate-limit на /api/ai (30/min), Redis + in-memory fallback, cursor-пагинация сообщений, one-time WS-тикеты, ClockSynchronizer, reconnect/backoff с очередью, CrashReporter -> /api/telemetry/crash, feature flags, GDPR

## Разработчик
- Новые тесты: PlinkTests/M35RegressionTests.swift (HomeFilter, WatchHistoryItem.progress)
- Accessibility-лейблы на новых кнопках (trash, превью, беседа); Reduce Motion уже поддержан в V4LivingBackground
- Info.plist: NSSpeechRecognitionUsageDescription
