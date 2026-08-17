# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Email **security@plink.app** with:

- what the issue is and which component it affects (`ios/`, `backend/`, `landing/`);
- steps to reproduce, or a proof of concept;
- the impact you believe it has;
- whether any user data was accessed or exposed.

If you need to send something sensitive, say so in your first message and we will
arrange an encrypted channel.

### What to expect

| Stage                           | Target                    |
| ------------------------------- | ------------------------- |
| Acknowledgement of your report  | 2 business days           |
| Initial assessment and severity | 5 business days           |
| Fix for critical severity       | 7 days from confirmation  |
| Fix for high severity           | 30 days from confirmation |
| Fix for medium and low severity | Next scheduled release    |

We will tell you when the issue is confirmed, when a fix ships, and — if you want
credit — name you in the release notes. We ask that you give us a reasonable
window to ship a fix before disclosing publicly.

Please avoid, while testing: accessing accounts that are not yours, degrading
service for other users, and running automated scans against production. A local
environment (`make setup`) reproduces the full stack.

## Supported versions

Fixes land on `main` and ship in the next release. Only the latest released
version of each client is supported; there are no long-term support branches.

| Component                       | Supported                                      |
| ------------------------------- | ---------------------------------------------- |
| Backend (production deployment) | Current deployment only                        |
| iOS app                         | Latest App Store version and the one before it |
| Landing / web join flow         | Current deployment only                        |

## Scope

In scope: authentication and session handling, the realtime gateway and room
authority, payment and entitlement flows, moderation and admin surfaces, media
proxying, and the web join flow.

Out of scope: findings that require a jailbroken device or a physically
compromised machine; missing hardening headers with no demonstrated impact;
vulnerabilities in third-party services we consume, which should be reported to
those vendors; social engineering of our team; and volumetric denial of service.

## Controls this codebase enforces

These are verified mechanically, and CI fails when one regresses. They are listed
so a reviewer can see the intent, and so nobody removes one by accident.

- **Configuration fails closed.** Production refuses to boot on a weak or default
  `JWT_SECRET`, on `CORS_ORIGIN="*"` with credentials, or without `REDIS_URL`.
  See [ADR-0006](docs/adr/0006-fail-fast-configuration.md).
- **Strict host matching.** Service URLs are matched through a single
  `PlinkHost` helper. Substring matching is forbidden and CI greps for it, because
  `evil-vk.com.ru` contains `vk.com` and would otherwise load in every
  participant's WebView. See [ADR-0004](docs/adr/0004-strict-host-matching.md).
- **Server-rendered pages ship a strict CSP.** `default-src 'none'`, scripts only
  inline with a per-response nonce. External `<script src>` is rejected by CI.
- **Realtime tickets are single-use.** WebSocket upgrades require a short-lived
  nonce redeemed in Redis, so a leaked URL cannot be replayed.
- **Roles come from the database, not the token.** Privilege checks re-read the
  user's role on each request; a stale token cannot carry stale privilege.
- **Secrets never enter the repository.** Private keys are blocked by CI, request
  logs redact credentials, and `Secrets.xcconfig` is ignored by git.
- **Dependencies are gated.** `npm audit` fails the build at `high` for the
  backend and `critical` for the landing site; Dependabot opens weekly updates.

## Handling a live incident

If you believe an incident is in progress rather than a latent bug, follow
[docs/runbooks/incident-response.md](docs/runbooks/incident-response.md) and mark
your email subject `INCIDENT`.
