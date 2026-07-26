# P1/P2 Polish Sprint — Status Report

**Date:** 2026-07-16  
**Branch intent:** `polish/p1-p2-mvp`

## Delivered in this pass

### Backend
- [x] `POST /api/moderation/report` — user reports (reasons: spam|harassment|nsfw|other)
- [x] `POST /api/moderation/block` / `DELETE /api/moderation/block/:userId` / `GET /api/moderation/blocks`
- [x] `POST /api/rooms/:id/kick` — host-only kick + best-effort WS notify
- [x] Routes registered in `app.ts`

### Task 1 — Onboarding
- [x] **iOS** — polished 4-step copy, skip wired, analytics, notification request on finish, version → 3
- [x] **Android** — new `OnboardingScreen` + HorizontalPager + POST_NOTIFICATIONS + TokenStore version
- [x] **Desktop** — `OnboardingPage` modal after first login (`plink_onboarding_v3`)

### Task 2 — Empty states
- [x] iOS `EmptyStateView` + 9 presets (wire remaining call sites in follow-up)
- [x] Android `EmptyState` on Home (rooms / trending / error)
- [x] Desktop `EmptyState` on Home / Rooms / Friends / DM / Settings blocked list

### Task 6 — Deep links
- [x] iOS `CFBundleURLTypes` scheme `plink` + path alias `room/`
- [x] AuthLaunchGate deferred deep link flush after onboarding/app
- [x] Android intent-filters + MainActivity join-by-code
- [x] Landing `.well-known/apple-app-site-association` + `assetlinks.json` stubs

### Task 8 — Desktop parity
- [x] Settings page (account, notifications, appearance, blocked, about, logout)
- [x] DM page + friends API client
- [x] Friends tabs: all / online / requests + search
- [x] Nav: Messages (`dms`)

### Task 7 — Themes memory
- [x] `docs/THEMES_MEMORY_TEST.md` checklist (manual Instruments)

### Analytics
- [x] `onboarding_step` / `onboarding_complete` / `onboarding_skipped` (iOS + Android + Desktop)
- [x] report/block/deep_link event helpers

## Still open / follow-up

| Item | Notes |
|------|--------|
| iOS EmptyState wiring | Component ready; plug into Friends/WatchChat/AI/shell home rails |
| iOS/Android moderation UI | Backend ready; context menus + report sheet still to wire on Watch chat |
| AI Companion Pro | Desktop chips added; room context + confirm-action cards + Android AI screen remaining |
| A11y full pass | Labels added on onboarding; shell/Watch already partial — continue |
| Desktop deep-link protocol | HTTPS + code paste; Tauri custom scheme optional |
| Deploy backend | Push moderation routes to Railway |
| TEAMID / SHA256 | Replace placeholders in AASA / assetlinks before production |

## Verify locally

```bash
# Backend
cd plink-backend && npm run build   # or tsc

# Desktop
cd windows-client && npm run build

# Android
cd android-client && ./gradlew :app:assembleDebug
```

## Suggested next commits order
1. Backend moderation + kick  
2. Onboarding 3 platforms + deep links  
3. Desktop Settings/DM/Friends + empty states  
4. Client moderation UI + AI Pro  
5. Tag `v1.0-final` after QA
EOF