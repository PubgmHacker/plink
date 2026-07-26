# Sprint Execution Report — Closed Beta Ready

**Date:** 2026-07-15/16  
**Against:** GLM P0/P1 sprint from AUDIT  

## P0 status matrix

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| P0-1 | Android playback sync | ✅ **DONE** | `RoomViewModel` + `OrderedSyncController` + `YouTubePlayerHtml` + `plinkCmd` + host controls + drift UI |
| P0-2 | LiveKit voice | ✅ **Option B** | Mic hidden unless `/api/rtc/status` → livekitEnabled; `docs/LIVEKIT_SETUP.md` for Option A |
| P0-3 | API RTT | ⚠️ **Partial** | Trending/search Redis-cached; keep-alive workflow; **Railway EU region needs ops**; p50 health still ~1.1–1.8s from this network |
| P0-4 | 3-device drift lab | ✅ **PASS** | `scripts/drift-lab.mjs` median ~300ms p95 ~350ms; `public/proof/sync/` |
| P0-5 | Rebuild installers | ✅ **DONE** | CI SUCCESS — DMG arm/intel + EXE + MSI in `downloads/` |
| P0-6 | Analytics 12 events | ✅ **DONE** | iOS `AnalyticsService` + Android `Analytics` + desktop hooks |
| P0-7 | App Store Connect | 📋 **Kit only** | Products/screenshots need human ASC — `docs/APP_STORE_SUBMISSION.md` |

## P1 shipped this sprint

| ID | Task | Status |
|----|------|--------|
| P1-1 | Free tier server limits | ✅ 1 active room free · max 10 participants · 403 codes |
| P1 chat | Profanity/spam filter | ✅ `chatFilter.ts` on `chat.send` |
| Keep-alive | Railway warm | ✅ `.github/workflows/keep-alive.yml` every 5m |

## P0 already true before this sprint (verify, don't re-do)

- YouTube 153 hosted player  
- ENABLE_CINEMA false  
- wipe-db / leave body / AI message compat  
- Desktop sync + AI page  

## Commits / artifacts

| Item | Location |
|------|----------|
| Backend free tier + chat filter | push `plink-backend` |
| Android analytics | `android-client/.../Analytics.kt` |
| Drift proof | `plink-landing/public/proof/sync/` |
| Installers | `plink-landing/public/downloads/` |
| Master zip | `Desktop/PLINK-MVP-COMPLETE.zip` |

## What ops must do (cannot code)

1. Railway → Region **EU-Central** (biggest RTT win for RU)  
2. LiveKit Cloud keys if voice wanted  
3. App Store Connect products + screenshots + TestFlight  
4. Firebase DebugView verify event names  

## Closed Beta Ready checklist

- [x] Cross-platform sync code on iOS / Android / Desktop  
- [x] Drift lab PASS (<2s)  
- [x] Installers built  
- [x] Voice UI not broken (hidden)  
- [x] Free tier enforced server-side  
- [x] Cinema safe for App Store  
- [ ] ASC products (human)  
- [ ] TestFlight 25 (human)  
- [ ] Railway EU (human)  

**Verdict:** **Closed Beta Ready** for friends/internal (sideload + Railway).  
**Soft Launch Ready** after ASC + TestFlight + optional EU region + LiveKit.
