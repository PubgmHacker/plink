# Railway environment setup — Plink MVP

This is the production deployment checklist derived from the actual backend code.
Never commit real values. Enter secrets in Railway → backend service → Variables.

## 1. Add managed services

1. In the same Railway project, create **PostgreSQL**.
2. Create **Redis**.
3. Open the backend service → Variables → add references rather than copying credentials:
   - `DATABASE_URL=${{Postgres.DATABASE_URL}}`
   - `REDIS_URL=${{Redis.REDIS_URL}}`
4. Generate secrets locally:
   ```bash
   openssl rand -hex 32   # JWT_SECRET
   openssl rand -hex 32   # JWT_REFRESH_SECRET
   openssl rand -base64 32 # TWOFA_ENC_KEY
   openssl rand -hex 32   # METRICS_TOKEN
   ```
5. Paste each generated value only into Railway Variables.

## 2. Put these in Railway now

| KEY = value | Where it comes from | What to set now |
|---|---|---|
| `NODE_ENV=production` | Fixed production mode | Exactly `production` |
| `PORT=${{PORT}}` | Railway injects `PORT`; usually do not override | Omit if Railway injects it; otherwise `8080` |
| `DATABASE_URL=${{Postgres.DATABASE_URL}}` | Railway PostgreSQL service | Service reference, not copied plaintext |
| `REDIS_URL=${{Redis.REDIS_URL}}` | Railway Redis service | Service reference |
| `JWT_SECRET=<64 hex chars>` | `openssl rand -hex 32` | Unique new value |
| `JWT_REFRESH_SECRET=<different 64 hex chars>` | `openssl rand -hex 32` | Unique, never equal to JWT_SECRET |
| `JWT_ISSUER=plink` | Product identifier | Exactly `plink` |
| `JWT_AUDIENCES=plink-ios` | Current shipping client | `plink-ios`; add others only when they exist |
| `ACCESS_TOKEN_TTL=1h` | Security policy | `1h` |
| `REFRESH_TOKEN_TTL_DAYS=90` | Session policy | `90` |
| `REALTIME_TICKET_TTL_SEC=60` | Short-lived WebSocket ticket | `60` |
| `SIGNED_MEDIA_URL_TTL=120` | Signed media policy | `120` |
| `CORS_ORIGIN=https://<frontend-domain>` | Exact browser origins allowed to call the API | Real HTTPS frontend origin; never `*` in prod |
| `PUBLIC_BASE_URL=https://<backend>.up.railway.app` | Railway backend public domain | Backend URL, no trailing slash |
| `PUBLIC_ORIGIN=https://<backend>.up.railway.app` | Origin that actually serves backend `/plus`, `/r/*`, `/u/*` routes | Use backend origin unless your custom/landing domain reverse-proxies those routes to backend |
| `TWOFA_ENC_KEY=<base64 random>` | `openssl rand -base64 32` | Required before enabling 2FA; keep stable or encrypted secrets become unreadable |
| `METRICS_TOKEN=<64 hex chars>` | `openssl rand -hex 32` | Protects metrics endpoint |
| `APP_STORE_COMPLIANT=true` | Release safety flag | `true` |
| `ENABLE_LEGACY_STREAM_RELAY=false` | Security/rollout flag | `false` |
| `REALTIME_PROTOCOL_V2=true` | Current realtime path | `true` |
| `NATIVE_PLAYER_V2=true` | Current native player | `true` |
| `WATCH_SCREEN_V2=false` | Optional rollout | `false` until explicitly tested |
| `LIVEKIT_SFU=false` | LiveKit unavailable now | Exactly `false` |
| `ENABLE_DEV_WIPE=false` | Destructive dev endpoint | Exactly `false` |
| `ALLOW_UNVERIFIED_IAP=false` | IAP verification safety | Exactly `false` |
| `ALLOW_SANDBOX_IAP=false` | Production IAP safety | Exactly `false` |
| `YOOKASSA_SEND_RECEIPT=false` | Web billing rollout | `false` until YooKassa/fiscalization is configured |
| `AI_ACTIONS_ENABLED=false` | AI tool/action rollout | `false` until AI actions are acceptance-tested |
| `APPLE_BUNDLE_ID=com.syncwatch.plink` | Xcode bundle id | Verify in App Store Connect before production |
| `APNS_BUNDLE_ID=com.syncwatch.plink` | Same iOS bundle id | Set now; credentials can follow later |
| `APNS_PRODUCTION=true` | Production APNs endpoint | `true` on production backend |

## 3. Required only when enabling a feature

### AI

| KEY = value | Where to get it | Set now? |
|---|---|---|
| `OPENROUTER_API_KEY=<secret>` | OpenRouter dashboard → Keys | Only if AI must work in MVP; server only |
| `AI_MODEL=openai/gpt-4o-mini` | OpenRouter model catalog | Set with the key; verify model availability/pricing |
| `AI_NSFW_MODEL=<model id>` | OpenRouter model catalog | Optional; defaults to AI_MODEL |
| `YOUTUBE_API_KEY=<secret>` | Google Cloud Console → enable YouTube Data API v3 → Credentials | Only if search/trending calls require it |

### APNs push notifications

| KEY = value | Where to get it | Set now? |
|---|---|---|
| `APNS_KEY_ID=<10-char id>` | Apple Developer → Certificates, Identifiers & Profiles → Keys | When push is enabled |
| `APNS_TEAM_ID=<team id>` | Apple Developer membership details | When push is enabled |
| `APNS_PRIVATE_KEY=<entire .p8 content>` | Download once when creating APNs key | Railway secret; preserve line breaks or use `\n` as code expects |
| `APNS_BUNDLE_ID=com.syncwatch.plink` | App identifier | Already set |
| `APNS_PRODUCTION=true` | Production endpoint | `true` in prod |

### StoreKit / Apple verification

| KEY = value | Where to get it | Set now? |
|---|---|---|
| `APPLE_TEAM_ID=<team id>` | Apple Developer membership | Before production IAP verification |
| `APPLE_ROOT_CA_PEM=<PEM text>` | Public Apple Root CA from Apple PKI | Prefer bundled public cert if code already ships it; never a private key |
| `APPLE_ROOT_CERT_PATH=<container path>` | Docker image path to bundled public Apple root cert | Use instead of PEM if deployment image contains it |
| `ALLOW_SANDBOX_IAP=true` | Temporary test deployment only | Never on production; use a separate staging service |

### YooKassa web billing

| KEY = value | Where to get it | Set now? |
|---|---|---|
| `YOOKASSA_SHOP_ID=<shop id>` | YooKassa cabinet → Integration → API keys | Only when web billing launches |
| `YOOKASSA_SECRET_KEY=<secret>` | Same cabinet | Railway secret only |
| `YOOKASSA_SEND_RECEIPT=true` | Fiscalization decision | Only after legal/fiscal fields are implemented |
| `PLUS_PRICE_1M=<price>` | Product pricing decision | Only with web billing |
| `PLUS_PRICE_3M=<price>` | Product pricing decision | Only with web billing |
| `PLUS_PRICE_12M=<price>` | Product pricing decision | Only with web billing |

### LiveKit — leave disabled now

```env
LIVEKIT_SFU=false
LIVEKIT_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
```

Later, get all three values from one LiveKit Cloud project. Never place API secret in iOS.

### Monitoring/admin

| KEY = value | Where to get it | Set now? |
|---|---|---|
| `SENTRY_DSN=<dsn>` | Sentry project → Client Keys (DSN) | Recommended before external beta |
| `OTEL_ENDPOINT=<https endpoint>` | Your OpenTelemetry collector/provider | Optional |
| `SLACK_WEBHOOK_URL=<secret url>` | Slack app → Incoming Webhooks | Optional alerts |
| `PRIVILEGED_ADMIN_EMAILS=a@b.com` | Owner decision | Only trusted verified accounts |
| `PRIVILEGED_FOUNDER_EMAILS=a@b.com` | Owner decision | Only trusted verified accounts |
| `ADMIN_STEPUP_CODE=<random one-time policy>` | Generate/rotate operationally | Do not use a human-memorable static code in production |
| `ANDROID_CERT_SHA256=<sha256>` | Play App Signing certificate | Only when Android client exists |
| `ANDROID_STORE_URL=<url>` | Play Console listing | Later |

## 4. Leave empty/omit until next phase

Omit instead of setting empty secrets where possible:

- `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- `YOOKASSA_SHOP_ID`, `YOOKASSA_SECRET_KEY`, `PLUS_PRICE_*`
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`
- `OPENROUTER_API_KEY`, `AI_NSFW_MODEL`, `YOUTUBE_API_KEY` if AI/search are not MVP requirements
- `SENTRY_DSN`, `OTEL_ENDPOINT`, `SLACK_WEBHOOK_URL`
- `APP_STORE_URL`, `TESTFLIGHT_URL`, `ANDROID_STORE_URL`
- `ANDROID_CERT_SHA256`
- `PRIVILEGED_ADMIN_EMAILS`, `PRIVILEGED_FOUNDER_EMAILS`, `ADMIN_STEPUP_CODE`
- `DEV_WIPE_SECRET` because `ENABLE_DEV_WIPE=false`

Do not set test-only `API_BASE`, `WS_BASE`, `E2E`, or `APP_VERSION` in production unless a deployment script explicitly requires them.

## 5. Deploy and verify

1. Railway backend service → Settings → source repository. This repository now supports the current monorepo-root setup through `/railway.json`; it points explicitly to `backend-3/Dockerfile` and starts `backend-3/start.sh`.
2. Keep **Root Directory blank** for this checked-in configuration. Builder: Dockerfile. Remove dashboard build/start overrides so `/railway.json` remains the single source of truth. If you instead set Root Directory to `backend-3`, also change the service config path to `/backend-3/railway.json`.
3. `start.sh` applies the pinned Prisma migrations and then starts `node dist/server.js`. A migration error intentionally fails the deployment instead of booting against a mismatched schema.
4. Attach PostgreSQL and Redis, then provide every required production variable from sections 1–2 before deploying.
5. Railway readiness path is `/health/ready`; `/health/live` only proves that the process is alive.
6. Deploy and confirm `/health/ready` returns 200.
7. Run a staging E2E against the deployed URL before pointing iOS at it.
8. Set the iOS production backend URL in the non-secret client configuration. This URL is public configuration, not a secret.

### If Railway previously failed on migration `20260712000000_billing_admin_v2`

The old migration used the non-PostgreSQL type `DATETIME(3)`. The checked-in SQL now uses `TIMESTAMP(3)`, but Prisma may have recorded the earlier attempt as failed.

1. Inspect the deployment log for `P3009` or `P3018` and inspect `_prisma_migrations` in the attached PostgreSQL database.
2. Confirm whether the migration's tables/columns were partially created before changing migration state.
3. If it failed and its partial DDL has been safely rolled back/removed, run the pinned CLI once against that database:
   `./node_modules/.bin/prisma migrate resolve --rolled-back 20260712000000_billing_admin_v2`
4. Redeploy. Do **not** mark the migration applied unless the production schema fully matches it.

## Security notes

- Rotate the previously exposed TokenRouter/OpenAI-compatible key immediately; gitignore does not revoke it.
- Never put OpenRouter, LiveKit secret, YooKassa secret, APNs `.p8`, JWT secrets, or database URLs in Xcode, Info.plist, xcconfig committed files, or the app bundle.
- Use a separate Railway staging service for sandbox IAP and experimental flags.
