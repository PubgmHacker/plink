# Android Client Specification for Plink

## Tech Stack
- Kotlin + Jetpack Compose + Material 3 dark
- OkHttp for REST + WebSocket
- ExoPlayer for HLS/MP4
- WebView for YouTube embed / cinema pages
- LiveKit Android SDK for voice
- EncryptedSharedPreferences for tokens

## API Endpoints (same as iOS)
- POST /auth/signin, /auth/signup, /auth/refresh
- GET /users/me (now includes avatarData)
- POST /users/me/avatar (avatar base64)
- POST /rooms (with appearanceTheme optional)
- GET /rooms, POST /rooms/join
- WebSocket /ws/room/:id for realtime v2 (see contracts/realtime-v2.ts)
- POST /api/rtc/token (premium required)
- POST /api/billing/verify (JWS or receipt)
- GET /api/billing/entitlements
- POST /api/media/search etc for YouTube

## Data Models (Kotlin)
data class User(
  val id: String,
  val username: String,
  val email: String,
  val avatarURL: String?,
  val avatarData: String?, // base64
  val displayName: String?,
  val isPremium: Boolean,
  val role: String?
)

Similar for Room, MediaItem, Message, etc. Mirror iOS Codable.

## Realtime Protocol
Use same as contracts/realtime-v2.ts :
- sync.command, sync.state.request, chat.send, reaction.send
- Use Gson or kotlinx.serialization for JSON
- Heartbeat ping every 30s

## Screen Flow
Bottom nav: Home | Rooms | AI | Friends | Profile

- Home: Hero carousel (HorizontalPager), trending, create button
- Rooms: list, search by code
- AI: chat with orb (Canvas or Lottie)
- Friends: list + requests
- Profile: avatar 80dp with ring, badges, grouped cards, logout

## Auth
- Store access/refresh in EncryptedSharedPreferences
- 7 day token TTL
- Auto refresh on 401

## Deep Links
- plink://room/CODE
- https://plink.app/r/CODE (App Links)

## Push
FCM, register token to /auth/device-token

## Voice
LiveKit SDK, connect with token from /api/rtc/token
Premium check before publish audio.

## Design
Colors from V4Theme (electric etc) + live themes.
Typography Material 3.
Spacing 16dp grid.

## Build
Min SDK 24, target 34.
Add to build.gradle the deps.

See iOS for exact flow and edge cases.
