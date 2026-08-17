# ADR-0011: Authorization state is read from the database, not the token

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** backend maintainers

## Context

The HTTP layer authenticated a request by verifying the JWT signature and then trusting its
claims. `role` came from the token. Whether the account existed, was banned, or had been
deleted was never asked.

That is the textbook stateless-JWT design, and its documented trade-off is a window between
a state change and the moment tokens reflect it — bounded by the token's lifetime. The
July 2026 audit found that the window here was not bounded, because two defects composed.

**The token never expired.** `issueTokenPair` signed with
`{ expiresIn: config.ACCESS_TOKEN_TTL as any }`, passing the string `'1h'`. fast-jwt, under
`@fastify/jwt`, expects a _number of milliseconds_. It computed
`exp = iat + Math.floor('1h' / 1000)` — `NaN` — so the `exp` claim was effectively not set at
all. Every access token was permanent. The `as any` is what let the type mismatch through.

**Nothing was checked against the database.** So the consequences of a permanent token were:

- a banned user kept posting in chat and creating rooms — the ban never took effect, ever;
- a demoted administrator kept administrator privileges;
- a deleted account kept working;
- a privilege grant survived its own revocation.

A leaked token was a permanent credential, and no moderation action could revoke it. There
was no expiry to wait out.

The WebSocket gateway had been doing this correctly all along — it consulted the database on
connect. Only the HTTP layer diverged, which is why the gap was invisible: the realtime path,
where the sensitive actions appear to happen, behaved as documented.

## Decision

Account state is read from the database on every authenticated request. The token is
authoritative only for facts about the _session_; the database is authoritative for facts
about the _account_.

That split is the substance of the decision:

| Fact          | Source       | Why                                                                                                     |
| ------------- | ------------ | ------------------------------------------------------------------------------------------------------- |
| `id` / `sub`  | signed token | Identity, established at login                                                                          |
| `mfa`         | signed token | A session property — whether 2FA was completed _in this session_. Not in the database, and must not be. |
| `auth_time`   | signed token | When this session authenticated. Admin routes require it within 10 minutes for step-up.                 |
| `role`        | **database** | A revoked privilege must stop working. The token's `role` claim is deliberately ignored.                |
| `bannedUntil` | **database** | A ban must take effect without waiting for a token to expire.                                           |
| `deletedAt`   | **database** | A deleted account must stop working.                                                                    |

A per-request `SELECT` would make every API call a Postgres round trip, so reads go through a
short-lived snapshot cache: `SNAPSHOT_TTL_MS = 30_000`, capped at `MAX_SNAPSHOTS = 10_000`
entries. A ban therefore takes effect within 30 seconds on its own.

`invalidateUserSnapshot(userId)` drops the entry so a decision applies immediately. Every
route that changes account state calls it — ban and role changes in `admin.ts` and
`moderation.ts`, account deletion in `gdpr.ts`. The TTL is the backstop; the invalidation is
the mechanism.

The failure modes are distinguished by status code, and the distinction is deliberate:

- **401 `TOKEN_EXPIRED`** — signature or expiry failed. The client should re-authenticate.
- **401 `ACCOUNT_GONE`** — no such user, or soft-deleted.
- **403 `ACCOUNT_BANNED`**, with `until` — authenticated correctly, not permitted.
- **503 `AUTH_BACKEND_DOWN`** — the database could not be reached. _Not_ 401: a 401 would make
  every client log its user out over an infrastructure problem, turning a brief outage into a
  mass re-authentication event and a support queue.

`optionalAuth` performs the same database check but degrades silently — a banned or deleted
user is simply treated as a guest rather than rejected, since the endpoint does not require
authentication in the first place.

Separately, `exp` is now computed explicitly in Unix seconds
(`exp: now + Math.floor(accessTtlMs / 1000)`) rather than delegated to a library whose TTL
units differ from the config format.

## Consequences

### What this makes easier

- Moderation works. A ban, a demotion, or a deletion takes effect in bounded time — instantly
  where the invalidation hook fires.
- A leaked token stops being a permanent credential. It now expires, and the account behind
  it can be disabled.
- HTTP and WebSocket agree about who a user is, so an authorization rule means one thing
  across the whole surface.
- The database is the single place to look when asking why a request was allowed, rather than
  needing to decode whatever token the client happens to hold.
- Infrastructure failure is legible to clients. 503 says "retry"; it does not say "your
  session is invalid".

### What this makes harder

- **Authentication now depends on Postgres.** The database being down means the API is down.
  This is a deliberate exchange of availability for correctness, and it is the right way
  round for an authorization decision — but it does mean auth is no longer stateless, and the
  word "stateless JWT" no longer describes this system.
- **The cache is per-process, so invalidation is per-process.** `invalidateUserSnapshot` clears
  the map in the replica that handled the request. On another replica the stale snapshot
  survives until its 30-second TTL. Instant revocation is therefore instant only on one
  instance; across a scaled deployment the real bound is the TTL. Fixing this properly means
  moving invalidation to Redis pub/sub, alongside the room fan-out
  ([ADR-0009](0009-redis-as-room-state-authority.md)).
- **The eviction policy is a full flush.** At `MAX_SNAPSHOTS` the map is cleared outright
  rather than evicting least-recently-used entries, so crossing the threshold sends every
  active user's next request to Postgres at once. Bounded and simple, but it is a thundering
  herd waiting for enough concurrent users.
- There is a 30-second window in which a demoted administrator still holds privileges on any
  replica that has not invalidated. For a ban this is acceptable; for a compromised
  administrator account, 30 seconds is a long time.
- Added latency on cache misses, and a load pattern on Postgres that scales with request
  volume rather than login volume.

### What has to be true for this to keep working

- **Every state-changing route calls `invalidateUserSnapshot`.** Nothing enforces this. A new
  ban endpoint that forgets it still works, still passes tests, and silently degrades to
  eventual consistency — the fault only appears as "the ban took a while", which nobody files.
  This is the weakest point in the design.
- The TTL stays short enough to be a credible backstop. Raising it to reduce database load
  directly extends the window in which a revoked privilege still works.
- `mfa` and `auth_time` stay out of the database. They describe a session, and persisting them
  per-user would make a second session inherit the first one's step-up.

## Alternatives considered

**Short token TTL with no database check.** The stateless answer: a 5-minute access token
bounds the staleness window without touching Postgres per request. Rejected because the
window is still real for the most sensitive actions, and because refresh-token rotation would
have to consult the database anyway — which reintroduces the dependency while leaving five
minutes of stale authority in the middle.

**A token denylist in Redis.** Check a revocation set on each request; instant revocation
without querying Postgres. Rejected as covering only part of the problem: it revokes tokens
but does not answer "what is this user's role now", so a demotion still needs a database read
or a full token reissue. It would also add a second authorization source of truth, which is
the shape of the original bug.

**Signed short-lived claims refreshed on state change** (push-based). Correct in principle and
what a dedicated identity provider does. Rejected as requiring infrastructure — reliable
delivery, reissue on the client, ordering — that is disproportionate for a single API.

**Check only on privileged routes.** Cheaper: verify against the database for admin and
moderation endpoints, trust the token elsewhere. Rejected because a banned user posting in
chat is precisely the case that mattered, and chat is not a privileged route. The distinction
would also have to be maintained by hand on every new endpoint.

## References

- `backend/src/middleware/auth.ts` — `loadSnapshot`, `invalidateUserSnapshot`, `authenticate`, `optionalAuth`
- `backend/src/utils/tokens.ts` — explicit `exp` computation
- `backend/src/routes/admin.ts`, `moderation.ts`, `gdpr.ts` — invalidation call sites
- [SECURITY.md](../../SECURITY.md)
- [ADR-0012](0012-pinned-apple-root-ca.md) — the same audit's finding in the purchase path
