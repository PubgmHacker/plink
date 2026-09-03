# Deploying the backend

The backend runs on Railway from the checked-in `Dockerfile`, and applies its own
migrations at boot. This page covers a normal deploy, first-time environment setup,
the full variable reference, and the two failure modes that need a human.

- **Normal deploy:** [§1](#1-a-normal-deploy)
- **New environment from scratch:** [§2](#2-setting-up-a-new-environment) → [§3](#3-environment-variables)
- **Something went wrong:** [§5](#5-when-a-deploy-fails)
- **Rollback:** [§6](#6-rollback)

---

## 1. A normal deploy

Deploys are triggered by pushing to the deployment branch. Railway builds
`backend/Dockerfile` and runs `backend/start.sh`, which applies migrations and
then boots the server.

```
push  →  docker build  →  prisma migrate deploy  →  node dist/server.js  →  /health/live
```

**Before pushing:**

1. `make check` passes locally (typecheck, lint, tests).
2. If the change includes a migration, read [§4](#4-deploying-a-schema-change) first —
   migration order matters and is not automatic.
3. If the change adds a required environment variable, set it in Railway **before**
   pushing. Configuration is validated at startup and a missing required variable
   fails the boot deliberately, which will roll the deploy back.

**After the deploy reports success:**

```bash
curl -fsS https://<backend-host>/health/ready | jq
```

Expected:

```json
{ "status": "ready", "services": { "database": "up", "redis": "up" } }
```

`"status": "degraded"` with a `503` means the process is running but a dependency is
not reachable. The deploy is _not_ healthy — go to [§5](#5-when-a-deploy-fails).

Then check the boot log for the in-app-purchase self-check:

```
[iap] verification self-check passed
```

If that line is absent, or reports a failure, purchase verification is not trustworthy
on this deploy. Treat it as a production incident — see
[incident-response.md](incident-response.md#in-app-purchase-verification-self-check-failed).

### Why the Railway health check is `/health/ready` and not `/health/live`

`railway.json` points the platform health check at `/health/ready`, which returns 200
only when the process is up **and** Postgres and Redis answer.

That is deliberate. Railway's health check gates _promotion of a new deploy_: the old
deploy keeps serving until the new one passes. A build that boots but cannot reach its
database or Redis — a wrong `DATABASE_URL`, a rotated Redis password — would pass
`/health/live` and be promoted straight into an outage. With `/health/ready` it is never
promoted, and the previous deploy stays live while you fix the variable.

The trade-off is a transient dependency blip during rollout. `healthcheckTimeout` is
300 seconds and Railway keeps polling until the check passes, so a blip that clears
within five minutes delays promotion rather than failing it. Only a sustained outage
fails the deploy, and in that case promoting would not have helped.

`/health/live` is for the container runtime (the Dockerfile `HEALTHCHECK`) and for
"is the process alive" monitors. `/health` still exists and behaves like
`/health/ready`, for monitors configured before the split.

---

## 2. Setting up a new environment

Do this once per environment. Use a **separate Railway service and a separate
database** for staging; do not point staging at the production database, and do not
copy production secrets into it.

1. In the Railway project, create a **PostgreSQL** service and a **Redis** service.
2. Open the backend service → **Variables**, and add _references_ rather than pasted
   credentials, so rotating the database does not require editing the backend:

   ```
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   REDIS_URL=${{Redis.REDIS_URL}}
   ```

3. Generate the secrets locally. Each is unique per environment:

   ```bash
   openssl rand -hex 32      # JWT_SECRET
   openssl rand -hex 32      # JWT_REFRESH_SECRET  (must differ from JWT_SECRET)
   openssl rand -base64 32   # TWOFA_ENC_KEY
   openssl rand -hex 32      # METRICS_TOKEN
   ```

   Paste each value directly into Railway Variables. Do not route them through a
   file, a shell history, or a chat message.

4. Set every variable in [§3](#3-environment-variables) marked **required**.
5. Configure the service:
   - **Root Directory:** blank. `/railway.json` at the repository root is the single
     source of truth and points at `backend/Dockerfile`.
   - **Builder:** Dockerfile.
   - Remove any build or start command overrides in the dashboard. If the dashboard
     and `railway.json` disagree, the dashboard wins and the repository stops
     describing reality.
6. Deploy, then verify as in [§1](#1-a-normal-deploy).
7. Run the integration suite against the deployed URL before pointing a client at it.

`TWOFA_ENC_KEY` deserves a specific warning: it encrypts stored two-factor secrets.
Changing or losing it makes every existing 2FA enrolment permanently undecryptable,
and the only recovery is disabling 2FA for every affected account. Back it up wherever
you keep break-glass material.

---

## 3. Environment variables

Values are validated at startup. A missing required variable stops the boot rather
than degrading silently — see [ADR-0006](../adr/0006-fail-fast-configuration.md).

### Required in every environment

| Variable                  | Value                        | Notes                                                                                                                           |
| ------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `NODE_ENV`                | `production`                 | Exactly this string. Several safety branches key off it.                                                                        |
| `PORT`                    | injected by Railway          | Do not override unless the platform does not provide it.                                                                        |
| `DATABASE_URL`            | `${{Postgres.DATABASE_URL}}` | Service reference, not pasted plaintext.                                                                                        |
| `REDIS_URL`               | `${{Redis.REDIS_URL}}`       | Service reference. Room state and presence depend on it — see [ADR-0009](../adr/0009-redis-as-room-state-authority.md).         |
| `JWT_SECRET`              | 64 hex chars                 | Unique per environment.                                                                                                         |
| `JWT_REFRESH_SECRET`      | 64 hex chars                 | Must differ from `JWT_SECRET`.                                                                                                  |
| `JWT_ISSUER`              | `plink`                      |                                                                                                                                 |
| `JWT_AUDIENCES`           | `plink-ios`                  | Add an audience only once a client actually exists.                                                                             |
| `ACCESS_TOKEN_TTL`        | `1h`                         |                                                                                                                                 |
| `REFRESH_TOKEN_TTL_DAYS`  | `90`                         |                                                                                                                                 |
| `REALTIME_TICKET_TTL_SEC` | `60`                         | WebSocket tickets are single-use and short-lived.                                                                               |
| `SIGNED_MEDIA_URL_TTL`    | `120`                        | Seconds.                                                                                                                        |
| `CORS_ORIGIN`             | `https://<frontend-host>`    | Exact origins. Never `*` in production.                                                                                         |
| `PUBLIC_BASE_URL`         | `https://<backend-host>`     | No trailing slash.                                                                                                              |
| `PUBLIC_ORIGIN`           | `https://<backend-host>`     | Origin that actually serves `/plus`, `/r/*`, `/u/*`. Use the backend origin unless a custom domain reverse-proxies those paths. |
| `TWOFA_ENC_KEY`           | base64, 32 bytes             | See the warning in [§2](#2-setting-up-a-new-environment).                                                                       |
| `METRICS_TOKEN`           | 64 hex chars                 | Gates `/metrics`.                                                                                                               |
| `APPLE_BUNDLE_ID`         | `com.syncwatch.plink`        | Verify against App Store Connect. See [ADR-0008](../adr/0008-legacy-bundle-identifier.md).                                      |

### Safety flags — set explicitly, do not rely on defaults

| Variable                     | Production value | What it does if wrong                                                                        |
| ---------------------------- | ---------------- | -------------------------------------------------------------------------------------------- |
| `ALLOW_UNVERIFIED_IAP`       | `false`          | `true` accepts unverified purchase receipts. Refused in production.                          |
| `ALLOW_SANDBOX_IAP`          | `false`          | `true` grants entitlements from sandbox transactions.                                        |
| `ENABLE_DEV_WIPE`            | `false`          | Development routes, including a full database wipe, are not registered in production at all. |
| `ENABLE_LEGACY_STREAM_RELAY` | `false`          | Legacy relay path.                                                                           |
| `APP_STORE_COMPLIANT`        | `true`           | Gates behaviour App Review requires.                                                         |

### Feature rollout flags

The values below are the current production settings, not aspirations.

| Variable                | Value   |
| ----------------------- | ------- |
| `REALTIME_PROTOCOL_V2`  | `true`  |
| `NATIVE_PLAYER_V2`      | `true`  |
| `WATCH_SCREEN_V2`       | `false` |
| `LIVEKIT_SFU`           | `false` |
| `AI_ACTIONS_ENABLED`    | `false` |
| `YOOKASSA_SEND_RECEIPT` | `false` |

### Required only when the corresponding feature is enabled

**Apple in-app purchase verification**

| Variable               | Where it comes from                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| `APPLE_TEAM_ID`        | Apple Developer → membership details                                                             |
| `APPLE_ROOT_CA_PEM`    | Apple PKI, public root certificate (PEM text)                                                    |
| `APPLE_ROOT_CERT_PATH` | Path to the root certificate inside the image — use instead of the PEM when the image bundles it |

Without a root certificate, receipt verification fails closed: **genuine purchases
stop being confirmed.** That is the intended trade-off — see
[ADR-0012](../adr/0012-pinned-apple-root-ca.md) — but it means the certificate is
operationally required, not optional.

**Apple push notifications**

| Variable           | Where it comes from                           |
| ------------------ | --------------------------------------------- |
| `APNS_KEY_ID`      | Apple Developer → Keys (10 characters)        |
| `APNS_TEAM_ID`     | Apple Developer → membership details          |
| `APNS_PRIVATE_KEY` | The `.p8` contents, downloadable exactly once |
| `APNS_BUNDLE_ID`   | `com.syncwatch.plink`                         |
| `APNS_PRODUCTION`  | `true` on production                          |

`APNS_PRIVATE_KEY` must keep its line breaks, or carry `\n` escapes — the loader
accepts both.

**Password-reset mail (Resend)**

| Variable         | Notes                                                                                                 |
| ---------------- | ----------------------------------------------------------------------------------------------------- |
| `RESEND_API_KEY` | Resend → API Keys. Unset means the reset code is written to the server log, not sent.                 |
| `MAIL_FROM`      | Sender shown to the user; the domain must be verified in Resend. Default `Plink <noreply@plink.app>`. |

**AI features**

| Variable             | Where it comes from                                                  |
| -------------------- | -------------------------------------------------------------------- |
| `OPENROUTER_API_KEY` | OpenRouter → Keys. Server-side only, never in the app bundle.        |
| `AI_MODEL`           | OpenRouter model catalogue                                           |
| `AI_NSFW_MODEL`      | Optional; falls back to `AI_MODEL`                                   |
| `YOUTUBE_API_KEY`    | Google Cloud Console → YouTube Data API v3                           |
| `VK_SERVICE_TOKEN`   | VK → service token. Unset means the VK video-search provider is off. |

**Web billing (YooKassa)**

| Variable                                           | Notes                                                  |
| -------------------------------------------------- | ------------------------------------------------------ |
| `YOOKASSA_SHOP_ID`                                 |                                                        |
| `YOOKASSA_SECRET_KEY`                              |                                                        |
| `YOOKASSA_SEND_RECEIPT`                            | `true` only after fiscalization fields are implemented |
| `PLUS_PRICE_1M`, `PLUS_PRICE_3M`, `PLUS_PRICE_12M` | Pricing decision                                       |

**Voice and video (LiveKit)**

`LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` — all three from a single
LiveKit Cloud project. The API secret never goes near the iOS client. `LIVEKIT_SFU`
is a separate flag: the credentials make voice _possible_, the flag makes it _on_.

`RTC_PAYWALL_BEFORE_AVAILABILITY` stays unset (or `false`) unless LiveKit is configured
on that deployment: by default the availability check runs before the Plink+ paywall,
so a server without media credentials answers 503 instead of asking for money for a
feature it cannot deliver.

Confirm what the server thinks it has, since a typo in a secret looks identical to a
missing feature from the client side:

```bash
curl -s https://<backend-host>/api/rtc/status
# {"livekitEnabled":true,"livekitSfuFlag":true,"requiresPlus":true}

curl -s https://<backend-host>/health | jq .services.livekitSfu
# true once all three credentials are present
```

`livekitEnabled` reflects the credentials; `livekitSfuFlag` reflects `LIVEKIT_SFU`.
Voice needs both. Note that no shipping client polls this endpoint — it is an
operator's check, not the mechanism the app uses to show or hide the microphone.

**Monitoring and administration**

| Variable                    | Notes                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------- |
| `SENTRY_DSN`                | Recommended before any external beta                                               |
| `OTEL_ENDPOINT`             | Optional. Empty means the tracer is a no-op — see `src/services/telemetry.ts`.     |
| `SLACK_WEBHOOK_URL`         | Optional alert delivery                                                            |
| `PRIVILEGED_ADMIN_EMAILS`   | Comma-separated. Verified accounts only.                                           |
| `PRIVILEGED_FOUNDER_EMAILS` | Same.                                                                              |
| `ADMIN_STEPUP_CODE`         | Rotate operationally. Never a memorable static string.                             |
| `ANDROID_CERT_SHA256`       | Play App Signing certificate fingerprint, served in `/.well-known/assetlinks.json` |
| `ANDROID_STORE_URL`         | Play Console listing                                                               |

### Leave unset

Prefer omitting a variable to setting it empty:

`LIVEKIT_*`, `YOOKASSA_*`, `PLUS_PRICE_*`, `APNS_*`, `OPENROUTER_API_KEY`,
`YOUTUBE_API_KEY`, `VK_SERVICE_TOKEN`, `RESEND_API_KEY`, `SENTRY_DSN`, `OTEL_ENDPOINT`,
`SLACK_WEBHOOK_URL`,
`APP_STORE_URL`, `TESTFLIGHT_URL`, `ANDROID_STORE_URL`, `ANDROID_CERT_SHA256`,
`PRIVILEGED_*`, `ADMIN_STEPUP_CODE`, `DEV_WIPE_SECRET`.

`API_BASE`, `WS_BASE`, `E2E`, and `APP_VERSION` are test-harness variables. They have
no place in a production environment.

---

## 4. Deploying a schema change

`start.sh` runs `prisma migrate deploy` before the server starts, so a migration and
the code that needs it ship together. Two rules make that safe:

**Migrations are additive.** A deploy that drops a column the previous version still
reads will break every request served by an instance that has not rolled over yet.
Split destructive changes across two releases: stop reading the column, ship, then
drop it.

**Applied migration SQL is immutable.** Prisma checksums each applied migration.
Editing a file under `prisma/migrations/` after it has been applied anywhere makes
`migrate deploy` fail with a checksum mismatch, and the fix is manual database
surgery. To change a migration, write a new one.

To verify migration state without deploying:

```bash
DATABASE_URL=<url> npx prisma migrate status
```

### Baselining a database that predates the migration history

A database created with `prisma db push` has tables but no `_prisma_migrations`
rows, so `migrate deploy` tries to create tables that already exist and fails.
`backend/scripts/migrate-baseline.sh` performs the baseline safely: it diffs the
live schema against `schema.prisma`, and only marks the migration applied when there
is no drift. Run it against a clone first. Never against production without a backup.

---

## 5. When a deploy fails

### `/health/ready` returns 503

Read the body. It names the dependency:

```json
{ "status": "degraded", "services": { "database": "up", "redis": "down" } }
```

- **`database: down`** — check the PostgreSQL service is running and `DATABASE_URL`
  still resolves. If the database is up and reachable, suspect connection exhaustion.
- **`redis: down`** — rooms cannot be created or joined. Presence and room state live
  in Redis ([ADR-0009](../adr/0009-redis-as-room-state-authority.md)).
- **`redis: not_configured`** — `REDIS_URL` is unset. This is a configuration error,
  not an outage.

### The boot fails on a migration

The deploy log will show a Prisma error code:

- **`P3009`** — a previous migration is recorded as failed. The database may hold
  partial DDL from that attempt. **Inspect `_prisma_migrations` and the actual schema
  before changing anything.** Only after confirming the partial changes are gone:

  ```bash
  ./node_modules/.bin/prisma migrate resolve --rolled-back <migration_name>
  ```

- **`P3018`** — a migration failed to apply. Same procedure: understand what was
  partially applied before touching migration state.

Never mark a migration as applied to get past an error. That starts the API against a
schema Prisma Client does not match, and the failures that follow are much harder to
diagnose than a failed deploy.

### The boot fails on configuration

The error names the missing variable. Set it and redeploy. This is the fail-fast
behaviour working as intended.

---

## 6. Rollback

Railway keeps previous deploys. Roll back from the service's deploy history.

**A code-only change** rolls back cleanly.

**A change that included a migration** does not, because the migration has already
been applied and the previous code may not tolerate the new schema. This is why
migrations are additive: an additive migration is, by construction, safe for the
previous version to run against. If you shipped a destructive migration and need to
roll back, you need a database restore, not a deploy rollback — go to
[incident-response.md](incident-response.md).

Verify after rolling back exactly as in [§1](#1-a-normal-deploy). A rollback is not
done until `/health/ready` says so.
