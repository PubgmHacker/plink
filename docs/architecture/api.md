# API reference

The HTTP surface of the backend: what the prefixes are, how a request is authorized,
what an error looks like, and where every route lives. Counts were measured on
2026-08-16; the command to re-measure them is at the [bottom of the page](#regenerating-the-route-index).

Realtime messages are not documented here. The websocket protocol has its own
contract and its own page: [realtime protocol](realtime-protocol.md).

## Shape

168 routes across 20 modules in [`backend/src/routes/`](../../backend/src/routes/),
plus seven operational routes defined directly in
[`backend/src/app.ts`](../../backend/src/app.ts).

| Prefix              | Modules                          | Registered in                        |
| ------------------- | -------------------------------- | ------------------------------------ |
| `/api`              | 18 modules, 155 routes           | `app.ts` — one `register` per module |
| _(none)_            | `web.ts` (11), `assets.ts` (2)   | `app.ts`, deliberately unprefixed    |
| `/health`, `/metrics`, `/ws`, `/.well-known` | —      | `app.ts` directly                    |

`web.ts` and `assets.ts` are registered without a prefix on purpose: they serve the
share links (`/r/:code`, `/u/:username`, `/w/:code`, `/join/:code`), the `/plus`
purchase page, the Open Graph images those links unfurl into, and
`/.well-known/apple-app-site-association`. A share link with `/api` in it would be
wrong in every message it appears in, and the association file must sit at that exact
path or Universal Links stop working — an invite would open the website instead of the
app.

`assets.ts` is registered **before** `web.ts` because `web.ts` owns the catch-all
landing behaviour; registered the other way round, `/assets/*` resolves into the
landing 404 page.

## Authorization

Three postures, and the difference between them is load-bearing.

**`fastify.authenticate`** — the decorator declared at `app.ts:183`, implemented in
[`backend/src/middleware/auth.ts`](../../backend/src/middleware/auth.ts). It verifies
the bearer token *and then reconciles the user against the database* on every request,
behind a 30-second cache. The role on `request.user` comes from Postgres, never from
the token. This is [ADR-0011](../adr/0011-authorization-state-read-from-the-database.md),
and it is the reason a ban, a demotion or an account deletion takes effect within 30
seconds instead of at token expiry.

Two claims are the exception and are read from the *signed token*, because they
describe the session rather than the user and are not stored anywhere:

- `mfa` — the user completed two-factor authentication in this session.
- `auth_time` — when they last authenticated.

**`optionalAuth`** — same reconciliation, but silent. Populates `request.user` when a
valid token is present and does nothing when it is absent, expired, banned or deleted.
Never rejects a request.

**None** — the route is reachable without a token. Every such route is listed under
[unauthenticated by design](#unauthenticated-by-design) below; there are no others.

### Admin routes

All 22 routes in `admin.ts` are gated by `requireAdmin`, which installs two
`preHandler` hooks in a deliberate order — `fastify.authenticate` first, because it
answers 401/403/503 itself and Fastify stops the chain as soon as a hook replies, then
the privilege check, which needs a populated `request.user`.

The privilege check is four gates, and a request must clear all of them:

| Gate | Failure response |
| ---- | ---------------- |
| `request.user` is populated | `401 Authentication required` |
| role is `ADMIN` or `FOUNDER` | `403 Admin access required`, **plus an `admin.unauthorized` audit row** |
| `mfa === true` | `401 step_up_required`, `reason: 'mfa'` |
| `auth_time` present and within 10 minutes | `401 step_up_required`, `reason: 'stale_auth'` |

The last two are step-up authentication: holding an admin role is not enough, the
session must have completed 2FA and authenticated recently. The stale-auth response
includes `auth_age_seconds` and `max_age_seconds` so the client can tell the user how
long ago they signed in rather than guessing.

`featureFlags.ts` gates its two `/admin/feature-flags` routes with an inline role
check rather than `requireAdmin`, so those two carry no 2FA or recency requirement.
That is an inconsistency, not a design: it is listed under [known
gaps](#known-gaps).

### Unauthenticated by design

| Route | Why, and what protects it instead |
| ----- | --------------------------------- |
| `POST /api/auth/signup`, `signin`, `refresh`, `forgot-password`, `reset-password`, `guest`, `apple` | Sign-in cannot require sign-in. Body-schema validation via `validateBody`, plus a rate limit on every one of them. |
| `GET /api/auth/check-username` | Username availability, needed on the sign-up form before an account exists. |
| `POST /api/billing/webhooks/apple` | Apple calls it. The body is a signed JWS verified against Apple's certificate chain ([ADR-0012](../adr/0012-pinned-apple-root-ca.md)) — the signature *is* the authentication. |
| `POST /api/webpay/yookassa/webhook` | Same shape, different provider, and the body is not trusted at all: the payment id is re-fetched from the YooKassa API and the grant is issued from that response, never from the webhook body. |
| `POST /api/webpay/create`, `GET /api/webpay/status` | The `/plus` web purchase flow, which authenticates with email and password in the request body because the browser has no app token. |
| `POST /api/telemetry/crash` | A client that just crashed may not have a usable token. Rate-limited to 20/hour. |
| `GET /api/rtc/status` | Reports whether the SFU is configured at all. No room or user data. |
| `GET /api/media/search`, `trending`, `categories`, `youtube-player`, `youtube-embed` | Public catalog and player-shell endpoints, all rate-limited. |
| `GET /api/users/:id/avatar`, `GET /api/uploads/*` | Image bytes, served to unauthenticated contexts — Open Graph unfurls and the landing pages. |
| `GET /assets/*`, everything in `web.ts` | Public web pages, share links, OG images, the Apple association file. |
| `POST /api/dev/wipe-db` | Not registered in production at all — see below. |

Two of these deserve reading in full rather than trusting the summary.

**`POST /api/dev/wipe-db` does not exist in production.** It used to be registered
unconditionally and defended only by an environment variable, which meant one typo in
production config was total data loss. It is now inside `if (!config.isProduction)`, so
the protection does not depend on the *value* of a flag — the route is absent. It
additionally requires `DEV_WIPE_SECRET` to match, and refuses when that secret is
unset.

**`GET /api/media/youtube-stream` authenticates via `?token=` in the query string**,
verified inline with `fastify.jwt.verify` rather than through `fastify.authenticate`.
This is not an oversight: AVPlayer drops the `Authorization` header on Range requests,
so a header-authenticated video proxy fails the moment the user seeks. The cost is
real and worth stating — that path verifies the token signature only, so it does
**not** get the database reconciliation described above. A banned user with an
unexpired access token can still stream through it until the token expires. The route
is rate-limited to 30/minute.

## Errors

Every error response is JSON. The shape is `{ error: string }`, with a machine-readable
`code` on the cases a client must branch on:

| Status | `code` | Meaning |
| -----: | ------ | ------- |
| 401 | `TOKEN_EXPIRED` | Access token expired. Refresh and retry. |
| 401 | `ACCOUNT_GONE` | The account was deleted. Sign out. |
| 401 | `step_up_required` | Admin route, session needs 2FA or a fresh sign-in. |
| 403 | `ACCOUNT_BANNED` | Includes `until` as an ISO-8601 timestamp. |
| 503 | `AUTH_BACKEND_DOWN` | The database was unreachable during authorization. |

`AUTH_BACKEND_DOWN` is the interesting one. When authorization cannot reach Postgres
the middleware answers 503, not 401 — deliberately. Answering 401 would make every
client sign its user out over an infrastructure problem, turning a brief outage into a
support queue. 503 tells the client to retry. It also means the middleware does not
fall back to trusting the token alone, which would defeat the whole reconciliation.

The `error` strings are Russian, because they are shown to users of a Russian-language
product. **Do not branch on them** — branch on `code` and on the status. See
[localization](localization.md) for why user-facing copy is output only.

## Rate limiting

`@fastify/rate-limit` is registered with `global: false` (`app.ts:154`), so the
100/minute default is **not** applied anywhere by itself: a route is limited only if it
declares `config: { rateLimit: … }`. 63 of the 168 routes do. The remaining 105 have no
limit, and that is a gap rather than a decision — recorded below.

Where limits exist they are scaled to cost: 10 per 10 minutes on `POST
/api/webpay/create`, 20 per hour on `POST /api/telemetry/crash`, 30 per minute on the
YouTube endpoints because each one can trigger a `yt-dlp` extraction.

## Operational routes

Defined directly in `app.ts`, outside any route module and outside `/api`.

| Route | Auth | Notes |
| ----- | ---- | ----- |
| `GET /health/live` | none | Liveness. Returns `{status:'alive'}` unconditionally — it answers "is the process up", nothing more. |
| `GET /health/ready` | none | Readiness. Checks Postgres and Redis and **returns 503 when either is down**, so Railway stops routing traffic to the instance. |
| `GET /health` | none | Kept for older monitors. Same checks as `/health/ready` plus uptime, version, memory and resolved feature flags. |
| `GET /metrics` | token in production | Prometheus text format. |
| `GET /ws`, `GET /ws/room/:id` | ticket | Websocket upgrade. The handlers are intentionally empty — see below. |
| `GET /.well-known/assetlinks.json` | none | Android App Links. The certificate fingerprint comes from `ANDROID_CERT_SHA256`. |

`GET /metrics` was public once, which exposed internal counters — users online, room
counts, error rates — to anyone who asked. In production it now requires
`Authorization: Bearer $METRICS_TOKEN`, and when `METRICS_TOKEN` is unset it answers
**404 rather than 401**, so the endpoint does not advertise its own existence. Outside
production it is open, because a metrics endpoint you have to authenticate to during
development is a metrics endpoint nobody looks at.

The two `/ws` handlers are empty on purpose. The realtime gateway subscribes to
`connection` events on the websocket server rather than handling routes; the route
declarations exist only so Fastify performs the upgrade. The gateway is constructed
only when Redis is available ([ADR-0009](../adr/0009-redis-as-room-state-authority.md)),
and logs a warning rather than failing when it is not. Authentication happens through a
single-use ticket from `POST /api/realtime/ticket`, not a bearer header — the details
are in the [realtime protocol](realtime-protocol.md).

`/.well-known/apple-app-site-association` is **not** here: it is served by `web.ts`. It
was registered in both places once, and duplicate registration is a startup crash in
Fastify (`FST_ERR_DUPLICATED_ROUTE`) rather than a silent shadow, which is how it was
found.

## Route index

Every route the backend serves, grouped by the module that declares it. Paths are the
contract; request and response bodies are not reproduced here, because a body schema
pasted into markdown drifts from the code within a release — read the handler.

**○** marks a route with no `fastify.authenticate` preHandler (36 of 168).
**†** marks the five where that is not the same thing as unauthenticated: they
authenticate by another mechanism — a query-string token, credentials in the body, or a
JWS signature over the payload — described under [unauthenticated by
design](#unauthenticated-by-design).

### `admin.ts` — 22 routes

Admin panel: users, rooms, moderation queue, audit log, broadcasts, blocklists. _(all routes admin-gated.)_

- `GET    /api/admin/analytics/overview`
- `GET    /api/admin/audit`
- `GET    /api/admin/blocklists`
- `DELETE /api/admin/blocklists/:id`
- `POST   /api/admin/blocklists/add`
- `GET    /api/admin/broadcasts/history`
- `POST   /api/admin/broadcasts/send`
- `GET    /api/admin/flags`
- `POST   /api/admin/flags/:id/resolve`
- `POST   /api/admin/moderation/messages/:id/delete`
- `GET    /api/admin/moderation/queue`
- `POST   /api/admin/premium/comp`
- `GET    /api/admin/premium/metrics`
- `GET    /api/admin/rooms`
- `POST   /api/admin/rooms/:id/close`
- `GET    /api/admin/system/flags`
- `GET    /api/admin/system/health`
- `POST   /api/admin/system/maintenance`
- `GET    /api/admin/users`
- `POST   /api/admin/users/:id/ban`
- `POST   /api/admin/users/:id/role`
- `POST   /api/admin/users/:id/unban`

### `ai.ts` — 4 routes

Assistant: chat, room recap, recommendations, action confirmation. _(authenticated unless marked ○.)_

- `POST   /api/ai/chat`
- `POST   /api/ai/confirm-action`
- `POST   /api/ai/recommend`
- `POST   /api/ai/room-recap`

### `assets.ts` — 2 routes

Static font and screenshot files for the landing pages. _(no auth.)_

- `GET    /assets/fonts/:file ○`
- `GET    /assets/shots/:file ○`

### `auth.ts` — 13 routes

Sign-up, sign-in, refresh, password reset, Apple sign-in, guest sessions, FCM tokens. _(authenticated unless marked ○.)_

- `POST   /api/auth/admin-verify`
- `POST   /api/auth/apple ○`
- `GET    /api/auth/check-username ○`
- `POST   /api/auth/fcm-token`
- `POST   /api/auth/forgot-password ○`
- `POST   /api/auth/guest ○`
- `POST   /api/auth/heartbeat`
- `POST   /api/auth/logout`
- `POST   /api/auth/refresh ○`
- `POST   /api/auth/reset-password ○`
- `POST   /api/auth/signin ○`
- `POST   /api/auth/signout-others`
- `POST   /api/auth/signup ○`

### `billing.ts` — 5 routes

In-app purchase verification and entitlements. _(authenticated unless marked ○.)_

- `POST   /api/billing/cancel`
- `GET    /api/billing/entitlements`
- `GET    /api/billing/status`
- `POST   /api/billing/verify`
- `POST   /api/billing/webhooks/apple ○†`

### `dev.ts` — 1 route

Development-only database wipe. Not registered in production. _(no auth.)_

- `POST   /api/dev/wipe-db ○`

### `featureFlags.ts` — 3 routes

Flag reads for clients, flag writes for admins. _(authenticated unless marked ○.)_

- `GET    /api/admin/feature-flags`
- `PATCH  /api/admin/feature-flags/:key`
- `GET    /api/feature-flags`

### `friends.ts` — 8 routes

Friend list, requests, search, pinning. _(authenticated unless marked ○.)_

- `GET    /api/friends`
- `DELETE /api/friends/:friendId`
- `POST   /api/friends/:friendId/pin`
- `POST   /api/friends/request`
- `PUT    /api/friends/requests/:id`
- `GET    /api/friends/requests/incoming`
- `GET    /api/friends/requests/outgoing`
- `GET    /api/friends/search`

### `gdpr.ts` — 4 routes

Data export, summary, account deletion, anonymization. _(authenticated unless marked ○.)_

- `DELETE /api/gdpr/account`
- `POST   /api/gdpr/anonymize`
- `GET    /api/gdpr/export`
- `GET    /api/gdpr/summary`

### `groups.ts` — 11 routes

Group chats: membership and messages. _(authenticated unless marked ○.)_

- `GET    /api/groups`
- `POST   /api/groups`
- `PATCH  /api/groups/:id`
- `POST   /api/groups/:id/leave`
- `POST   /api/groups/:id/members`
- `GET    /api/groups/:id/messages`
- `POST   /api/groups/:id/messages`
- `DELETE /api/groups/:id/messages/:messageId`
- `GET    /api/groups/:id/messages/:messageId/photo`
- `POST   /api/groups/:id/messages/:messageId/react`
- `POST   /api/groups/:id/read`

### `livekit.ts` — 3 routes

SFU tokens, config and availability. _(authenticated unless marked ○.)_

- `GET    /api/rtc/config`
- `GET    /api/rtc/status ○`
- `POST   /api/rtc/token`

### `media.ts` — 10 routes

Catalog search, metadata extraction, and the YouTube streaming proxy. _(authenticated unless marked ○.)_

- `GET    /api/media/categories ○`
- `GET    /api/media/extract`
- `POST   /api/media/extract-url`
- `GET    /api/media/metadata`
- `GET    /api/media/search ○`
- `POST   /api/media/stream-token`
- `GET    /api/media/trending ○`
- `GET    /api/media/youtube-embed ○`
- `GET    /api/media/youtube-player ○`
- `GET    /api/media/youtube-stream ○†`

### `messages.ts` — 19 routes

Direct messages: text, voice, photo, reactions, pins, typing, forwarding. _(authenticated unless marked ○.)_

- `POST   /api/messages/dm`
- `DELETE /api/messages/dm/:friendId`
- `GET    /api/messages/dm/:friendId`
- `POST   /api/messages/dm/:friendId/pin`
- `DELETE /api/messages/dm/:friendId/pin/:messageId`
- `GET    /api/messages/dm/:friendId/pins`
- `POST   /api/messages/dm/:friendId/read`
- `GET    /api/messages/dm/:friendId/typing`
- `POST   /api/messages/dm/:friendId/typing`
- `POST   /api/messages/dm/:messageId/react`
- `POST   /api/messages/dm/forward`
- `DELETE /api/messages/dm/message/:messageId`
- `PATCH  /api/messages/dm/message/:messageId`
- `POST   /api/messages/dm/photo`
- `POST   /api/messages/dm/voice`
- `GET    /api/messages/invites`
- `GET    /api/messages/photo/:messageId`
- `GET    /api/messages/unread`
- `GET    /api/messages/voice/:messageId`

### `moderation.ts` — 7 routes

User reports, blocking, and the moderation queue. _(authenticated unless marked ○.)_

- `POST   /api/moderation/block`
- `DELETE /api/moderation/block/:userId`
- `GET    /api/moderation/blocked`
- `GET    /api/moderation/queue`
- `POST   /api/moderation/queue/:id/resolve`
- `POST   /api/moderation/report`
- `POST   /api/moderation/users/:id/unban`

### `profile.ts` — 15 routes

The current user, other users, avatars, appearance, presence, history. _(authenticated unless marked ○.)_

- `GET    /api/profile/appearance`
- `PUT    /api/profile/appearance`
- `POST   /api/profile/delete`
- `GET    /api/uploads/* ○`
- `GET    /api/users/:id`
- `GET    /api/users/:id/avatar ○`
- `GET    /api/users/:id/profile`
- `DELETE /api/users/me`
- `GET    /api/users/me`
- `PATCH  /api/users/me`
- `POST   /api/users/me/avatar`
- `POST   /api/users/me/create-subscription`
- `GET    /api/users/me/history`
- `POST   /api/users/me/presence`
- `GET    /api/users/me/profile`

### `realtime.ts` — 2 routes

Websocket tickets and server time for clock sync. _(authenticated unless marked ○.)_

- `POST   /api/realtime/ticket`
- `GET    /api/realtime/time`

### `rooms.ts` — 21 routes

Rooms: lifecycle, participants, queue, playback, messages, privacy, appearance. _(authenticated unless marked ○.)_

- `GET    /api/rooms`
- `POST   /api/rooms`
- `DELETE /api/rooms/:id`
- `GET    /api/rooms/:id`
- `PATCH  /api/rooms/:id/appearance`
- `POST   /api/rooms/:id/end`
- `POST   /api/rooms/:id/kick`
- `POST   /api/rooms/:id/leave`
- `GET    /api/rooms/:id/messages`
- `GET    /api/rooms/:id/messages/:messageId/photo`
- `POST   /api/rooms/:id/messages/photo`
- `GET    /api/rooms/:id/participants`
- `POST   /api/rooms/:id/playback`
- `PATCH  /api/rooms/:id/privacy`
- `GET    /api/rooms/:id/queue`
- `PATCH  /api/rooms/:id/queue`
- `POST   /api/rooms/:id/queue`
- `DELETE /api/rooms/:id/queue/:itemId`
- `POST   /api/rooms/:id/queue/:itemId/play`
- `POST   /api/rooms/join`
- `GET    /api/rooms/mine`

### `telemetry.ts` — 4 routes

Sync-drift samples and sessions, crash reports, feedback. _(authenticated unless marked ○.)_

- `POST   /api/telemetry/crash ○`
- `POST   /api/telemetry/feedback`
- `POST   /api/telemetry/sync-sample`
- `POST   /api/telemetry/sync-session`

### `web.ts` — 11 routes

Public pages: share links, the /plus page, Open Graph images, the Apple association file. _(no auth.)_

- `GET    / ○`
- `GET    /.well-known/apple-app-site-association ○`
- `GET    /join/:code ○`
- `GET    /og/default.png ○`
- `GET    /og/r/:code.png ○`
- `GET    /og/u/:username.png ○`
- `GET    /plus ○`
- `GET    /plus/success ○`
- `GET    /r/:code ○`
- `GET    /u/:username ○`
- `GET    /w/:code ○`

### `webpay.ts` — 3 routes

Plink+ purchase from the web, via YooKassa. _(no auth.)_

- `POST   /api/webpay/create ○†`
- `GET    /api/webpay/status ○†`
- `POST   /api/webpay/yookassa/webhook ○†`

## Regenerating the route index

The index above is generated, not hand-maintained. To re-derive it after adding or
moving a route:

```bash
cd backend
for f in src/routes/*.ts; do
  tr '\n' ' ' < "$f" \
    | grep -oE "\.(get|post|put|patch|delete)(<[^>]*>)? *\( *['\"]/[^'\"]*['\"]" \
    | sed -E "s|^\.||; s|<[^>]*>||; s| *\( *['\"]|  |; s|['\"]\$||" \
    | sed "s|^|$(basename $f)  |"
done | sort | tee /tmp/plink-routes.txt | wc -l    # expect 168
```

Three details in that command are not decoration. `tr '\n' ' '` flattens each file
first, because a handler whose options object starts on the next line is invisible to a
line-oriented grep — that alone accounts for 31 of the 168. `(<[^>]*>)?` catches the
`fastify.get<{ Params: … }>(…)` generic form. And requiring the path to start with `/`
is what keeps `response.headers.get('content-length')` out of the list.

The method and path are all this extracts. The auth marker is the presence of
`fastify.authenticate` in the route options, and you must check it by hand for anything
the grep reports as open: five routes authenticate without that preHandler, and no
generated table can tell them apart from a genuinely public one.

## Known gaps

Recorded so nobody has to rediscover them:

- **105 of 168 routes have no rate limit.** `@fastify/rate-limit` is registered with
  `global: false`, so the default never applies. The admin module has none at all; so do
  all 11 public web pages. This is the largest open item on this page.
- **`featureFlags.ts` gates its admin routes with an inline role check**, bypassing
  `requireAdmin` and therefore the 2FA and recent-auth requirements that every other
  admin route enforces.
- **`GET /api/media/youtube-stream` does not reconcile against the database**, so a ban
  does not stop an in-flight stream until the access token expires.
- **There is no generated OpenAPI document.** The route index above is the reference,
  which means it can fall out of step with the code between edits. A Fastify schema pass
  would fix both this and request validation, which is currently applied by
  `validateBody` on the auth routes only.
