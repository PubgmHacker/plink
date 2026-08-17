# ADR-0008: Keep the legacy bundle identifier

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** iOS maintainers, project maintainers

## Context

The product is called Plink. Its bundle identifier is `com.syncwatch.plink`.

`syncwatch` was the working name before the rename. The identifier was registered under it,
the App Store record was created under it, and by the time the product had a name it had
also accumulated everything that hangs off an identifier:

- the App Store Connect app record, which is keyed on the bundle ID permanently;
- the `plink.plus.1m` / `3m` / `12m` in-app purchase products, which belong to that record;
- three child identifiers — `.tests`, `.uitests`, `.widget`;
- the app group `group.com.syncwatch.plink`, which is how the widget reads the schedule;
- the WebAuthn relying-party appID `2QAMUC4Z4P.com.syncwatch.plink`, served in the
  apple-app-site-association file;
- the backend's `APPLE_BUNDLE_ID`, `APNS_BUNDLE_ID`, and the `APPLE_CLIENT_ID` default,
  each of which is compared against the `bundleId` claim in a StoreKit or Sign-in-with-Apple
  token;
- installed builds on real devices, whose Keychain items and `UserDefaults` are scoped to
  it.

It is a visible inconsistency. Someone reading the project for the first time finds a name
that is not the product's name in the place that looks most authoritative, and reasonably
assumes it is a mistake nobody got round to fixing.

## Decision

The bundle identifier stays `com.syncwatch.plink`. It is not renamed, and this is recorded
rather than left to look like neglect.

A bundle identifier is not a name — it is a primary key. Apple treats it as immutable: an
App Store record's bundle ID cannot be changed after the first submission, so "renaming"
means creating a second app. That is not a refactor, it is a relaunch:

- the existing App Store record is abandoned, along with its reviews and ranking history;
- in-app purchase products are per-record, so `plink.plus.*` would have to be recreated and
  re-approved, and existing subscribers would not transfer;
- every installed copy becomes a different app that does not update — users keep the old
  one until they notice, and their local state does not migrate;
- the app group, the WebAuthn appID, and the APNs topic all change together, so a mismatch
  in any one of them breaks widgets, passkeys, or push for the transition period.

The cost of the inconsistency is that a reader is briefly confused. The cost of fixing it is
the install base.

The identifier is therefore treated as an opaque constant. The product name lives in
`CFBundleDisplayName`, the marketing name lives in App Store Connect, and neither depends
on the identifier reading correctly.

Where a _new_ identifier is being chosen, it uses the current name: the Android client is
`com.plink.app`. This decision constrains the existing iOS record, not future ones.

## Consequences

### What this makes easier

- Nothing breaks. Subscriptions keep resolving, installed builds keep updating, passkeys
  keep verifying against the same appID.
- The backend's bundle-ID checks stay meaningful. `APPLE_BUNDLE_ID` is compared against the
  `bundleId` in a StoreKit JWS
  ([ADR-0012](0012-pinned-apple-root-ca.md)); if it drifted from what Apple signs, every
  purchase would be rejected.
- The legacy `com.syncwatch.plink.premium.*` product aliases in `backend/src/routes/billing.ts`
  stay honoured, so transactions issued under the older naming still resolve to a tier.

### What this makes harder

- **It reads as sloppiness.** This is the real cost, and it recurs with every new
  contributor. The mitigation is this record and a comment at the declaration in
  `project.yml`; there is no way to make the string itself look intentional.
- Grepping for the product name does not find the identifier, and grepping for the
  identifier does not find the product. Both are load-bearing strings and they do not
  match.
- `syncwatch` appears in the deployment runbook, the Info.plist, the app group, and the
  association file, so anyone auditing for stale naming has to know which occurrences are
  deliberate. That is what this record is for.
- Analytics or third-party dashboards keyed on the bundle ID display a name no team member
  uses.

### What has to be true for this to keep working

- That the identifier stays invisible to users. It appears in no UI; if it ever surfaced in
  a user-facing surface, the calculus would change.
- That nobody "tidies" it. A find-and-replace of `syncwatch` → `plink` across the repository
  is a plausible cleanup that would break the App Store link, the app group, and the
  purchase verification simultaneously — and the failures would appear in three unrelated
  subsystems.

## Alternatives considered

**Rename and relaunch as a new record.** Consistent, and the only way to actually change
the string. Rejected on the install base, the subscriptions, and the fact that it buys
nothing a user can perceive.

**Keep both identifiers — old app redirects to new.** The standard migration path for a
genuine rebrand. Rejected as disproportionate: it is weeks of work, two App Store records
to maintain, and a forced-update prompt for existing users, to fix a string they never see.

**Rename only the child identifiers** (`.tests`, `.uitests`) since they never ship.
Rejected as the worst option — it makes the naming _inconsistent within the project_ while
still leaving `syncwatch` on the app itself, so a reader now has to work out why the tests
disagree with the target they test.

## References

- [`ios/project.yml`](../../ios/project.yml) — `bundleIdPrefix`, and `PRODUCT_BUNDLE_IDENTIFIER` per target
- `backend/src/routes/billing.ts` — the `PLANS` map and its legacy aliases
- `backend/src/routes/web.ts` — `APPLE_BUNDLE_ID` in the association file
- [Deployment runbook — environment variables](../runbooks/deployment.md#3-environment-variables)
- [iOS build and release runbook — targets](../runbooks/ios-build-and-release.md)
