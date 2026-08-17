## What this changes

<!-- One or two sentences. What behaviour is different after this merges? -->

## Why

<!-- The problem, the bug report, or the decision this implements. Link the issue:
     Closes #123 -->

## How it was verified

<!-- Be specific. "Tested locally" tells a reviewer nothing.
     Name the test, the device, the scenario, the command. -->

- [ ] `make check` passes locally
- [ ] New behaviour has a test / the bug fix has a test that failed before it
- [ ] Manually exercised on: <!-- e.g. iPhone 17 Pro (18.2) + iPhone 15 (17.6), two accounts -->

<!-- If this touches realtime sync, say what you did with more than one device.
     Single-device verification cannot catch a sync regression. -->

## Scope check

<!-- Tick what applies. Anything ticked pulls in the matching requirement. -->

- [ ] **UI change** — screenshots or a recording below, light **and** dark
- [ ] **User-facing copy** — localized in every supported locale, no literals in views
- [ ] **Realtime protocol** — TypeScript contract _and_ Swift decoder updated together, parity test extended
- [ ] **Database** — migration included, and it is backward compatible with the currently deployed backend
- [ ] **Configuration** — documented in `backend/.env.example`, validated at boot
- [ ] **New dependency** — justified below, license checked, added to third-party notices
- [ ] **Architectural decision** — ADR added under `docs/adr/`
- [ ] **Breaking change** — migration path described, `BREAKING CHANGE:` footer in the commit

## Risk

<!-- What breaks if this is wrong, and how would we notice?
     If the answer is "nothing", say so — that is a useful signal too. -->

**Rollback:** <!-- revert is enough / needs a migration rollback / needs a client release -->

## Changelog

<!-- The line you added under [Unreleased] in CHANGELOG.md, written for a user
     rather than a reviewer. Delete this section only for changes with no
     user-visible effect (refactors, CI, internal docs). -->
