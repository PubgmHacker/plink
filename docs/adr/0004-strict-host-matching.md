# ADR-0004: Strict host matching for embedded content

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** iOS maintainers

## Context

When a user pastes a URL, the app decides which service it belongs to. That decision
sets `DetectedVideo.embedURL`, which loads in the room's `WKWebView` **for every
participant**. It is not a display detail; it is a decision about whose page runs on
other people's devices.

The original implementation used substring matching:

```swift
host.contains("vk.com")
```

`evil-vk.com.ru` contains `vk.com`. It therefore passed as a VK video and rendered with
VK's header, VK's icon, and the trust a recognised brand carries — a VK login phishing
page, inside our app, on every participant's screen, delivered by a link the host pasted
without knowing what it was.

The same code had a second variant. `serviceFromURL` matched the bare string `"rutube"`,
so `rutube.evil.com` classified as Rutube, while `detectVideoURL` a few hundred lines
away knew about `rutube.ru` and `rutube.video`. Two matchers, two answers, one of them
exploitable.

The pattern also survived a refactor: the file it originally lived in was deleted, and
the substring check reappeared in the code that replaced it. Deleting the site did not
delete the habit.

## Decision

All host matching goes through `PlinkHost`. A host matches a domain when it _is_ that
domain, or is a subdomain of it — meaning it ends with `"." + domain`. Nothing else
counts.

```swift
PlinkHost.matches("m.vk.com",       anyOf: ["vk.com"])  // true  — subdomain
PlinkHost.matches("vk.com",         anyOf: ["vk.com"])  // true  — the domain
PlinkHost.matches("evil-vk.com.ru", anyOf: ["vk.com"])  // false
PlinkHost.matches("notvk.com",      anyOf: ["vk.com"])  // false — prefix
```

Comparison is case-insensitive, since DNS names are, and a trailing dot is dropped,
since `vk.com.` is a valid absolute name for the same host.

There is one domain list per service, in `PlinkHost`, and both entry points read it. A
service added to the list is a service known to every call site.

A CI step fails the build on any reintroduction of substring host matching in Swift, and
fails if `PlinkHost.swift` is deleted. The check excludes comment lines, so documentation
of the hazard is not itself a violation of it.

## Consequences

### What this makes easier

- Adding a service is one list entry, and it cannot be half-added.
- The security property is checked mechanically rather than remembered. It survives the
  next refactor, which is the specific failure mode this had already exhibited once.
- Reviewers have a bright line: any `host.contains(` in a diff is wrong, with no
  case-by-case judgement.

### What this makes harder

- Adding a service means enumerating its domains, including the country variants and the
  short link host. `youtu.be` is not a subdomain of `youtube.com` and has to be listed.
- A provider that starts serving from a genuinely new registrable domain breaks until
  the list is updated. That is the correct failure direction, but it is a failure.
- The CI grep is a text match, so it can be worked around by someone determined to. It
  raises the cost of the mistake; it does not make it impossible.

### What has to be true for this to keep working

That embedded content stays allowlist-based. If Plink ever loads arbitrary user-supplied
pages into the room WebView by design, this record no longer describes the boundary and
the whole area needs rethinking.

## Alternatives considered

**Suffix matching without the dot** (`hasSuffix("vk.com")`). One character shorter and
still wrong: `notvk.com` ends with `vk.com`.

**Parse with a public-suffix list** and compare registrable domains. More correct in
principle, and it handles cases like a service moving to a different eTLD. Rejected as
disproportionate: it adds a dependency with its own update cadence to solve a problem an
exact-or-subdomain check already solves for an allowlist we control.

**`URLComponents` plus a regex per service.** Rejected as the same class of mistake with
more places to get it wrong — a regex that is right for eleven services and subtly wrong
for the twelfth is worse than one function.

## References

- `ios/Plink/Utilities/PlinkHost.swift`
- Security invariants in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)
- [SECURITY.md](../../SECURITY.md)
- [ADR-0003](0003-honest-service-catalog.md) — what the allowlist is for
