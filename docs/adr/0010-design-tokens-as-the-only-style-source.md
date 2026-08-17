# ADR-0010: Design tokens are the only source of style

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** iOS maintainers, product

## Context

The iOS app has been through three visual generations. Each one added views, and each one
set its own colours, corner radii, ring thicknesses, and animation durations at the point of
use, because that is the fastest way to build a screen that looks right.

The result was not a subtle inconsistency. Taking one component as the measured example — the
ring drawn around an avatar — there were **four independent implementations** in the shipping
app at once: `VIPAvatarRingModifier` in the cinematic components, `RingModifier` in
`AvatarView`, `V4Avatar` in the V4 module, and a fourth path that tinted the background in the
watch-room overlays. They disagreed on:

- **colour** — the admin ring was `#FF2D55` in one place, `RGB(1, 0.2, 0.3)` in another, and
  amber in a third;
- **thickness** — 2 pt, 2.5 pt, and 1.5 pt;
- **animation** — a 3.2-second rotation against a 4-second one, visibly out of phase when both
  appeared on screen;
- **meaning** — in one view the ring indicated account role, in another it indicated who was
  speaking.

That last one matters most. When the same visual element means two different things depending
on which screen you are looking at, the design is not merely inconsistent; it is
communicating incorrectly. A user who learns that a glowing ring means "speaking" reads a
role ring as a speaker.

Style values scattered across call sites also make a redesign impossible to scope. Changing
the accent colour is a repository-wide search for every literal that happened to be that
colour, and the ones that were written slightly differently are missed.

## Decision

Style values are declared once, in a token layer, and views reference tokens. No typography,
colour, spacing, radius, or motion literal is written at a call site.

The layer has four parts, each with a single owner:

| Concern             | Owner                                | Contents                                                   |
| ------------------- | ------------------------------------ | ---------------------------------------------------------- |
| Colour              | `V4` in `ios/Plink/V4/V4Theme.swift` | Every palette value, declared in OKLCH                     |
| Density and metrics | `CompactPhoneMetrics`                | Insets, spacings, poster and card geometry, row heights    |
| Surfaces            | `PlinkGlass`                         | The glass treatment, by role — navigation, control, chrome |
| Identity signals    | `PlinkIdentityRing`                  | Rings and badges around avatars, with their meanings       |

Three properties of the layer are load-bearing:

**Colours are OKLCH, not hex.** `Color.oklch(l, c, h)` converts through linear sRGB with the
exact CSS matrices. Perceptual lightness is a coordinate, so "the same colour one step
darker" is `l - 0.05` rather than a guess, and a hue rotation does not change perceived
brightness. A palette that is edited by hand in hex drifts in luminance; this one cannot.

**Signals are rationed, not accumulated.** `PlinkIdentityRing` enforces at most two
simultaneous signals on an avatar — one role ring and one corner badge — with the online dot
placed in a free corner inside a groove of the background colour so it cannot merge into
whatever is behind it. The constraint is the design decision; the file is where it is
expressible.

**Glass lives on the control layer only.** Following Apple's HIG: tab bars, buttons, chips,
and floating chrome get glass; content does not. Poster cards are never glass. `PlinkGlass`
is the only place that decides, and it adapts by OS — the native iOS 26 `glassEffect` where
available, a hand-rolled approximation (material, gradient stroke, top specular, shadow)
on iOS 17–25, since the deployment target is iOS 17.

## Consequences

### What this makes easier

- A palette change is one edit. The accent colour is one line, and every screen follows.
- Ring semantics are now a single answer to a single question, so the same visual means the
  same thing everywhere.
- Accessibility settings are honoured centrally. Reduce Transparency and Reduce Motion are
  handled in the token layer rather than remembered per view — `VideoThemeMotionPolicy`
  exists because the animated backgrounds had ignored every energy and accessibility mode.
- Reviewers get a mechanical rule: a colour literal, a magic radius, or a hardcoded duration
  in a view diff is wrong, without a discussion about whether this particular one is fine.
- New screens look like the app by default, which is the only version of consistency that
  survives schedule pressure.

### What this makes harder

- **The token layer is a bottleneck by design.** A view that needs a value the layer does not
  have cannot just write it; the layer has to grow first. That is friction at exactly the
  moment someone is trying to finish a screen, and it is the pressure that produced the
  original drift.
- **The names are generation labels, not semantic ones.** `V4` and `Cinema2026` say _when_
  a token was introduced, not what it is for. Nothing in the name `V4.raised` explains when
  to use it rather than `V4.surface`, so the layer needs its own documentation to be usable —
  which is a cost this decision has not eliminated, only relocated.
- **`Cinema2026` is a compatibility shim, and it looks like a second source of truth.** It is
  referenced around 430 times across dozens of files, so rather than rewrite every call site,
  it was redefined as aliases over `V4`. It also carries aliases-of-aliases (`bg` →
  `background`, `void` → `background`, `tertiary` → `divider`) added to satisfy call sites
  that guessed at names. Two namespaces for one palette is confusing in exactly the way this
  record exists to prevent, and the alias layer is a debt against it.
- Some tokens are absent from the layer even now — motion curves and shadow specifications are
  still partly per-view. The rule is stated absolutely; the implementation has not caught up
  everywhere, and claiming otherwise would make this record useless.
- Indirection costs reading time. `V4.canvas` requires a jump to know what colour it is, where
  `#0A0F10` does not.

### What has to be true for this to keep working

- That adding a token stays cheap. If it needs a review round trip, contributors will inline
  the value instead, and the fourth generation of drift begins.
- That the alias layer shrinks rather than grows. Each new `Cinema2026` alias makes the
  eventual consolidation more expensive, and there is nothing mechanical stopping one from
  being added.
- That `Design/` and `V4/` stay the only writers. A token defined inside a feature folder
  because it is "only used here" is how the previous generations started.

## Alternatives considered

**Xcode asset catalog colour sets.** The platform-native answer, with light/dark variants and
Xcode previews for free. Rejected as insufficient rather than wrong: it covers colour only,
leaves spacing and motion unowned, and asset catalogs are edited through a UI, which puts the
palette outside code review. The OKLCH relationships between palette entries also cannot be
expressed in a catalog.

**A SwiftUI `EnvironmentKey`-based theme, injected.** More flexible, and the right shape if
the app needed runtime-swappable themes across the whole surface. Rejected as more machinery
than a single-theme app requires; static namespaces are simpler to read and cannot be
accidentally unset. (Note that `V4Theme` does provide per-room theme selection — that is a
content-layer feature layered on top of these tokens, not a replacement for them.)

**A separate design-system Swift package.** Enforces the boundary at the compiler level:
tokens cannot import features. Rejected for now on build-cost and workflow grounds, and
because the boundary is currently maintained by convention successfully. This is the
alternative most likely to supersede this record if the app grows another client.

**Accept the drift and normalise periodically.** What happened by default for three
generations. Rejected on evidence: the normalisation never happened, and the cost of the
fourth generation would be paid on a codebase twice the size.

## References

- `ios/Plink/V4/V4Theme.swift` — the `V4` palette and the OKLCH conversion
- `ios/Plink/Design/Cinematic/CompactPhoneMetrics.swift` — density tokens and the `Cinema2026` alias layer
- `ios/Plink/Design/Glass/PlinkGlass.swift` — surface roles and the iOS 17 fallback
- `ios/Plink/Design/Identity/PlinkIdentityRing.swift` — the four implementations it replaced
- `ios/Plink/Design/Cinematic/VideoThemeMotionPolicy.swift` — motion under accessibility and thermal limits
- [Code style rules in CONTRIBUTING.md](../../CONTRIBUTING.md#code-style)
