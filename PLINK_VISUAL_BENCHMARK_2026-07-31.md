# Plink visual benchmark — 31 July 2026

## Direction

Preserve Plink's cinematic living background. Do not copy competitor assets,
layouts, gradients, sounds, or motion signatures. Benchmark behavioral quality:
Telegram for scanning and communication speed, Discord for room/presence clarity,
Netflix for content hierarchy/playback, and modern voice assistants for explicit
AI state and interruption.

## Release scorecard (100)

| Area | Weight | Plink target |
|---|---:|---|
| Navigation | 18 | Five top-level tabs, one tap each, predictable back/deep links |
| Button hierarchy/targets | 14 | One dominant CTA per viewport, all hit targets ≥44×44 pt |
| Card density/readability | 12 | ≥4 list rows or ≥2 media cards on standard viewport; critical status survives Dynamic Type |
| Watch/media state | 12 | Media, sync, participants and control ownership are continuously clear |
| Loading/empty/error | 12 | State-specific copy and next action; no fake skeleton for a real empty/error state |
| Dark-mode contrast | 12 | Normal text ≥4.5:1, essential non-text ≥3:1, semantic theme colors |
| Safe areas/adaptation | 10 | No essential control overlaps home indicator, keyboard, notch or Dynamic Island |
| AI orb/privacy/motion | 10 | Explicit idle/listening/thinking/speaking/error, stop in one tap, Reduce Motion |

Gate: ≥85/100 and zero blockers. A score of 10/10 requires physical-device,
StoreKit sandbox and deployed-service evidence; simulator-only evidence cannot earn it.

## What was changed in this pass

- Standardized tab targets and stable UI-test identifiers.
- Raised undersized Rooms/AI/Profile controls to 44 pt minimum.
- Replaced brittle loaded-empty room behavior with an actionable state.
- Distinguished Home room loading, empty and failure states.
- Added retry to Friends failure and honest unavailable values to Profile stats.
- Improved selected-pill foreground colors to respect theme button text.
- Refined the AI orb with layered specular highlights, caustic rim, lower metalness,
  denser geometry, neutral key light, state value accessibility, and background pause.
- Extended the live XCUITest to visit all five tabs and capture evidence.

## Device validation matrix

Automated simulator targets:

- compact: iPhone 17e
- standard: iPhone 17
- large: iPhone 17 Pro Max

For each target: dark appearance, all tabs, living background, auth/home/search,
portrait safe area, and no critical clipping. Physical devices remain a release
blocker for thermal behavior, OLED contrast, haptics, microphone, APNs, StoreKit,
and multi-device sync latency.

## Honest remaining external gates

1. StoreKit sandbox purchase/restore/refund with an Apple sandbox account.
2. Two or more physical devices for sync drift and reconnect measurements.
3. Physical microphone/speaker and permission testing.
4. Railway production deployment using owner-controlled secrets.
5. LiveKit remains disabled until a valid project and Apple entitlements exist.
