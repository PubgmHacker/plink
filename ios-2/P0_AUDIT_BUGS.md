# P0.7 Full Audit of Tabs - Results

| Вкладка | Что проверить | Статус | Фикс / Примечание |
|---------|---------------|--------|-------------------|
| Главная | Hero карусель, auto-scroll, быстрая комната, смотрят сейчас | ✅ Работает | DiscoveryHomeView + FeaturedCarousel, swipe hint added |
| Комнаты | Создание, вход, по коду | ✅ | RoomCreationView, ServiceSelection, join by code |
| ИИ | Чат, орб, клавиатура сворачивает орб | ✅ | AIAssistantView, orb reacts to state |
| Друзья | Список, приглашения, запросы | ✅ | FriendsView, FriendManager |
| Профиль | Аватар, имя, настройки, выйти | ✅ | ProfileView redesigned to spec, test push button for admin |
| WatchRoom | Player (YouTube landscape full + drawer), чат, реакции, sync | ✅ | Landscape drawer default, composer works, custom emoji in bubbles, sync via model |

**Общие баги найдены и исправлены:**
- Emoji: теперь custom packs с PNG support (asset names), long tap popover.
- Аватар: base64 в БД.
- Premium gates on voice/emoji.
- Fallback cinema services.
- Offline state with retry.
- Onboarding tutorial + hints.

No critical crashes found in main paths. All tabs functional.
