# ADR-0006: Fail-fast configuration

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** backend maintainers

## Context

The backend reads around sixty environment variables. They fall into three groups:
required everywhere, required only when a feature is enabled, and safety flags whose
wrong value is a security problem rather than a malfunction.

Reading `process.env` at the point of use gives every one of them the same failure mode:
`undefined` flows into the code and something downstream misbehaves in a way that does
not name the variable. A missing `JWT_SECRET` becomes a signature mismatch. A missing
`REDIS_URL` becomes rooms that cannot be created. A `CORS_ORIGIN` left at `*` becomes a
credentialed cross-origin read that nothing reports at all.

Defaults make this worse rather than better. A development default that survives into
production is not a missing configuration — it is a _wrong_ configuration that boots
successfully, passes health checks, and serves traffic. `JWT_SECRET=dev-secret-change-me`
is the whole authentication system, silently public.

## Decision

Configuration is read once, validated at boot, and the process refuses to start if it is
wrong.

- All reads live in `backend/src/config/`. Raw `process.env` access elsewhere is a lint
  error.
- Required values with no safe default throw at module load, naming the variable:
  `Missing env: DATABASE_URL`.
- `assertProductionInvariants()` runs from bootstrap when `NODE_ENV=production` and
  throws on any of:
  - `JWT_SECRET` weak, defaulted, or shorter than 32 characters;
  - `JWT_REFRESH_SECRET` weak, short, or equal to `JWT_SECRET`;
  - `CORS_ORIGIN` still `*`, which is forbidden with credentials;
  - an empty `JWT_AUDIENCES` allowlist.
- Development keeps permissive defaults deliberately, so a fresh clone runs without a
  `.env`. Production is where the invariants bite, and the check is keyed on `NODE_ENV`
  rather than on the presence of values.
- Optional integrations degrade rather than fail: an unset `SENTRY_DSN` means no
  reporting, an unset `OTEL_ENDPOINT` means the tracer is a no-op. These are absent
  features, not misconfiguration.

The messages are written for whoever is reading a deploy log at an inconvenient hour:
they say which variable, what is wrong with it, and what to set it to.

## Consequences

### What this makes easier

- Misconfiguration is a failed deploy with a one-line cause, instead of an incident with
  a diagnosis phase.
- The platform health check does the rest: a process that will not start never gets
  promoted, so a bad variable rolls itself back.
- The config module is the environment's documentation, and it cannot drift from the code
  that consumes it.
- `curl /health/ready` distinguishes "configured but the dependency is down" from
  "not configured", because `REDIS_URL` being unset is a distinct reported state.

### What this makes harder

- **A required variable added without setting it first takes production down on the next
  deploy.** This is the intended trade, but it makes ordering a rule people have to know:
  set the variable, then push.
- Boot-time validation cannot catch a value that is present and wrong — a valid-looking
  `DATABASE_URL` pointing at the wrong database passes every check.
- The permissive development defaults are a hazard of their own. They only stay safe
  because `NODE_ENV=production` is set correctly, which makes that one variable
  load-bearing for all the others.
- Adding a variable means touching the config module, the deployment runbook, and
  `.env.example`. Three places is friction, and friction is how they fall out of sync.

### What has to be true for this to keep working

- `NODE_ENV=production` is actually set in production. Every invariant is behind it, so a
  missing or misspelled value silently disables all of them. This is the single point of
  failure in the design.
- The weak-secret list stays a _floor_, not the check. It catches known placeholders and
  a length; it cannot tell a random 32-character string from a reused one.

## Alternatives considered

**Zod-validated schema over the whole environment.** Declarative, and the natural fit
given Zod is already a dependency for the realtime contracts. Rejected only on scope:
the current module is hand-written and works, and converting it is a refactor with no
behavioural change. Worth revisiting — this is the alternative most likely to supersede
this record.

**Warn and continue.** Log an error, start anyway. Rejected because it produces the exact
failure this decision exists to prevent: a running service that is quietly wrong, where
the log line scrolls past and the fault surfaces days later as something unrelated.

**Validate in CI only.** Cheaper, and it catches most mistakes before a deploy. Rejected
because CI does not know production's variables. The values live in the platform, so the
platform is where they have to be checked.

## References

- `backend/src/config/index.ts` — `required()` and `assertProductionInvariants()`
- [Deployment runbook — environment variables](../runbooks/deployment.md#3-environment-variables)
- [Code style rules in CONTRIBUTING.md](../../CONTRIBUTING.md#code-style)
