# ADR-0012: Purchase receipts are verified against a pinned Apple Root CA

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** backend maintainers

## Context

StoreKit 2 hands the client a signed JWS transaction. The client posts it to
`POST /api/billing/verify`, and the backend decides whether to grant an entitlement. That
signature is the only thing standing between a request and paid features, because the request
itself comes from a device we do not control.

The July 2026 audit found the verification inverted. Four defects, in the same function:

1. **The signature was verified against a certificate taken from the JWS itself** — `x5c[0]`,
   supplied by the caller. Anyone with `curl` could generate a self-signed certificate, sign
   an arbitrary payload with it, present both, and be believed. Lifetime Premium was a
   three-line script.
2. **Apple's root certificates were loaded but never used.** Their presence was read as a
   boolean flag. The chain `leaf ← intermediate ← root` was never walked.
3. **The expected algorithm was `RS256`.** Apple signs with `ES256`. So genuine Apple
   transactions were _rejected_, and forged RSA ones were accepted — the trust relationship
   turned exactly inside out.
4. **Outside production, a missing certificate meant accept everything.** Any non-production
   deployment granted entitlements unconditionally.

The combination is worse than any one part. Defect 3 meant real purchases failed, which
generates pressure to make verification more permissive; defects 1 and 4 were where that
pressure had already landed.

## Decision

A purchase JWS is accepted only if it chains to a **pinned** Apple Root CA. The full check,
in order:

1. **`alg === 'ES256'`.** Any other value is rejected and logged. There is no algorithm
   negotiation — a different `alg` is an attempted bypass, not a compatibility case.
2. **`x5c` has at least two links.** A one-element chain is a self-signed leaf, which is the
   original attack.
3. **Every certificate in the chain is currently valid** — `validFrom`/`validTo` checked
   against now, with an unparseable date treated as invalid.
4. **Each link is verified by the next link's public key.** `certs[i].verify(certs[i+1].publicKey)`
   across the chain.
5. **The final link's SHA-256 fingerprint equals the pinned root's.** Compared by
   `fingerprint256`, deliberately **not** by subject name — a name claiming to be Apple's is
   trivially forged, a fingerprint is not.
6. **The JWS signature is verified against the leaf**, with `dsaEncoding: 'ieee-p1363'`. ECDSA
   in JWS uses the raw P1363 format, not DER. Getting this wrong is the common cause of "the
   signature is valid but verification fails", and it is what makes the difference between a
   working check and pressure to disable it.

**Fail closed, in every environment.** If the root certificate cannot be loaded, verification
is off and every purchase is rejected. The only way to accept an unverified purchase is
`ALLOW_UNVERIFIED_IAP=true`, which is itself refused when `NODE_ENV=production`. There is no
environment in which a missing certificate silently means "trust the client".

**The root comes from a trusted channel only** — `APPLE_ROOT_CA_PEM`, or
`APPLE_ROOT_CERT_PATH`, or a known on-disk location. Fetching the root over the network at
verification time was considered and removed: a root obtained from an unverified channel at
the moment of the check is not a check.

**Self-test at boot.** `JoseConfig.selfTest()` feeds a deliberately forged JWS through the real
verification path and asserts it is rejected. In production a failure is `log.fatal` and
throws, so the process does not start. The self-test calls
`verifyJWSSignature(forged, false)` with the dev bypass explicitly disabled — it answers "is
the crypto path intact", not "what mode is this environment in". Without that argument,
`ALLOW_UNVERIFIED_IAP=true` in a developer's `.env` would make "verification is broken" and
"verification is bypassed" produce the same log line.

Two supporting fixes came from the same audit. `bundleId` is now returned from the verified
payload — it previously was not, which made the bundle-ID comparison in `billing.ts` dead code
that read `undefined`. And `signedDate` is returned so events can be ordered: a stale
`DID_RENEW` must not overwrite a newer `REFUND` or `REVOKE`.

The product-ID allowlist (`PLANS` in `backend/src/routes/billing.ts`) is checked _before_ the
signature, so an identifier the client can submit but that is not sold is rejected without
spending any cryptography on it.

## Consequences

### What this makes easier

- Forged receipts do not work. The property is now cryptographic rather than a code path
  someone has to remember to enter.
- A regression is caught at boot, in the deploy log, rather than in a revenue report weeks
  later. This is the part most likely to matter: the original bug was invisible precisely
  because nothing failed.
- Genuine Apple transactions verify, which removes the pressure that produced the permissive
  fallbacks.
- Verification is local and offline — no dependency on the App Store Server API being
  reachable, and no per-request latency to Apple.

### What this makes harder

- **The root certificate is a deployment dependency.** No root, no purchases, in every
  environment. That is intended, but it makes the certificate as load-bearing as
  `DATABASE_URL`, and it has to be present _before_ the first purchase attempt rather than
  discovered missing by a paying user.
- **Pinning breaks on rotation.** Apple Root CA G3 is valid into 2039, but if Apple ever signs
  StoreKit transactions under a different root, every purchase fails until the new root is
  deployed. This is the accepted cost of pinning, and the mitigation is operational: the
  rejection log line names the cause precisely, so the diagnosis is fast.
- **Developing against it needs a real certificate or an explicit flag.** `ALLOW_UNVERIFIED_IAP`
  exists because the alternative is a developer who cannot test the purchase flow at all — and
  a flag is a hazard. It is confined by the production refusal and by the self-test ignoring
  it, but it is still a switch that turns the check off.
- Certificate handling is hand-written against `node:crypto` rather than delegated to a
  library. It is the right level for a fixed, known chain, but chain validation is
  security-critical code we now own, and the P1363-vs-DER distinction is the kind of detail
  that has to be re-derived by anyone modifying it.
- Sandbox and production environments must both be handled, and the `environment` field in the
  payload is the only thing distinguishing them — so an environment mix-up is a logic error,
  not a signature error, and this check will not catch it.

### What has to be true for this to keep working

- **The self-test keeps running at boot and keeps failing loudly.** It is the only mechanical
  guard against this regressing. If it were ever downgraded to a warning in production, the
  system would return to its original state without any visible event.
- `ALLOW_UNVERIFIED_IAP` stays unset outside local development, and the production refusal
  stays keyed on a correctly-set `NODE_ENV` (see
  [ADR-0006](0006-fail-fast-configuration.md) for why that one variable carries so much).
- The chain check keeps comparing fingerprints. Relaxing step 5 to a subject-name match — a
  plausible-looking simplification — restores the vulnerability completely.

## Alternatives considered

**Call the App Store Server API to verify each transaction.** Apple's own endpoint, always
current, no pinned root to rotate. Rejected as making entitlement grants depend on an
external service being reachable and fast, on the user's purchase path — and it still needs
authenticated requests with a signed key, so it moves the secret rather than removing it.

**Use a library** (`app-store-server-library`, or `jose` with a JWKS). Less hand-written crypto
and the maintainers track Apple's changes. Genuinely attractive, and the alternative most
likely to supersede this record. Rejected for now because the verification is a fixed, known
chain of six steps, and adding a dependency to the payment path has its own supply-chain
cost — but "we wrote it ourselves" is not a virtue here, only a current state.

**Verify the chain but skip pinning the root** — trust the system CA store. Simpler and
rotation-proof. Rejected because any publicly-trusted CA could then issue a certificate that
validates, and the set of entities able to mint valid purchase receipts becomes every CA in
the trust store rather than Apple.

**Trust the client and reconcile later** against App Store Connect reports. Rejected outright:
it grants access first and detects fraud after, which for a subscription means the
entitlement was already used.

## References

- `backend/src/utils/jose-config.ts` — `verifyCertChain`, `verifyJWSSignature`, `selfTest`
- `backend/src/app.ts` — the boot self-test and its production-fatal path
- `backend/src/routes/billing.ts` — the `PLANS` allowlist, checked before the signature
- [Deployment runbook — environment variables](../runbooks/deployment.md#3-environment-variables)
- [SECURITY.md](../../SECURITY.md)
- [ADR-0011](0011-authorization-state-read-from-the-database.md) — the same audit's finding in the auth path
