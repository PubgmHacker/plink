# Plink MVP Audit Report

**Date:** 2026-07-15  
**Auditor:** Grok 4.5 (codebase + live production smoke + public competitor research)  
**Scope:** Backend (Railway prod), iOS SwiftUI, Android Compose, Desktop Tauri, Landing  
**Method honesty:** Competitors were researched from public sources (Play/App Store listings, rave.io, Teleparty/Kast/Discord comparisons). Physical install of every rival app was **not** performed in this pass. Plink was audited via live API tests + static/dynamic code review.

**Verdict:** **Conditional MVP (demo / closed beta) — not ready for 50–100M “killer app” launch.**  
Core loop works on **iOS + Desktop + Backend**. Android is a thin companion. LiveKit voice, AI production key, full parity UX, and App Store polish remain gaps.

---

## Executive Summary

| Area | Score (0–10) | Notes |
|------|--------------|--------|
| Product vision / positioning | 8 | Clear “watch together + AI + themes” differentiation |
| Backend readiness | 7 | Auth, rooms, sync v2, media OK; high RTT from client; LiveKit off |
| iOS readiness | 7.5 | Fullest client; cinema flag was always-on (fixed); analytics thin |
| Desktop readiness | 6.5 | YouTube hosted player + sync just landed; UI parity incomplete |
| Android readiness | 3.5 | Auth/rooms/chat/player; **no playback sync** |
| Sync quality | 7 (iOS/Desktop design) | Protocol v2 solid; multi-device lab measurement still needed |
| Design / brand | 8 | Cinema2026 strong on iOS; desktop/landing catching up |
| Monetization | 5 | StoreKit IDs exist; free-tier limits not enforced product-wide |
| App Store readiness | 4 | Metadata draft only; screenshots/preview incomplete; cinema risk reduced |
| Security | 6.5 | JWT + rate limits + HTTPS; wipe-db hardened this audit; audit logging gaps |
| Analytics / growth | 3 | Few Firebase events; no retention funnels |
| Competitive moat today | 5 | AI + themes + RU services (VK/Rutube) are real; Netflix depth loses to Rave/Teleparty |

### GO / NO-GO for public launch

| Gate | Status |
|------|--------|
| Closed beta (friends / TestFlight 25 users) | **GO** after P0 checklist below |
| Soft launch RU/CIS | **NO-GO** until Android sync + voice optional + crash metrics |
| Global / “killer Rave” | **NO-GO** (12–18 months of product + growth, not 30 days of polish alone) |

### P0 fixed in this audit pass

1. **YouTube 153 / framing** — hosted player + `frame-ancestors *` (prior session, live).
2. **`ENABLE_CINEMA` always true** → default **false** (`VideoService.swift`).
3. **`POST /api/dev/wipe-db` 500 on empty body** → safe 401 (`dev.ts`); deployed.
4. **AI chat rejects `{message}`** → accepts message string (`ai.ts`); deployed.
5. **Desktop leave room empty JSON body 400** → Content-Type only when body present (`api.ts`).

---

## 1. Competitive Analysis

### 1.1 Landscape (public data, 2026)

| Competitor | Platforms | Scale (order of magnitude) | Rating (approx) | Core model |
|------------|-----------|----------------------------|-----------------|------------|
| **Rave** | iOS, Android, Mac, Win, (VR history) | 50M+ Android installs | ~4.4 Play | In-app multi-service co-watch + chat |
| **Teleparty** | Chrome/Edge/Opera + limited mobile | 10M+ extension users | ~4.5 | Extension sync on Netflix/Disney/etc. |
| **Discord** | All | 500M+ | ~4.7 | Voice/video/communities; watch via screen share |
| **Kast** | Mobile + desktop | ~1M | ~4.0 | Watch party + video/voice |
| **Hearo** | Mobile + web | ~1M | ~4.2 | Family/friends co-watch |
| **Watch2gether** | Web | ~1M | ~4.3 | Browser rooms, casual |
| **Syncplay** | Desktop | niche | ~4.5 | Precision local/file sync |
| **TwoSeven** | Web | niche | ~4.0 | Couples distance watching |
| **Plink** | iOS + Desktop + Android (thin) + BE | 0 public | n/a | Native apps + AI + themes + RU video |

Sources: Play Store Rave listing (50M+), rave.io, Teleparty pricing/docs, industry comparisons (SyncUp/CNET/MakeUseOf 2025–2026).

### 1.2 Feature matrix (simplified)

| Feature | Rave | Teleparty | Kast | Discord | Plink |
|---------|------|-----------|------|---------|-------|
| YouTube sync | ✅ | ⚠️ | ✅ | Screen share | ✅ iOS/Desktop |
| Netflix / Disney | ✅ login/embed | ✅ extension | Partial | Screen share | ❌ off by default (App Store safe) |
| VK / Rutube | Partial | ❌ | ❌ | ❌ | ✅ |
| Voice | ✅ | Premium/limited | ✅ | ✅ best-in-class | Code yes; **LiveKit prod OFF** |
| Video chat / cam | Partial | Premium | ✅ | ✅ | ❌ / incomplete |
| Screen share | Partial | ❌ | ✅ | ✅ | Partial iOS only |
| AI companion | ❌ | ❌ | ❌ | Bots (not watch-native) | ✅ design + API |
| Living themes | ❌ | ❌ | ❌ | ❌ | ✅ Plink+ |
| Custom emoji packs | Basic | Basic | ✅ | ✅ | ✅ PNG packs |
| Sync accuracy claim | Soft | Soft | Soft | N/A | Target ±2s, clock v2 |
| Cross-platform | Strong | Browser-first | Strong | Strongest | iOS↔Desktop yes; Android no sync |
| Free tier | Ads | Free + Premium $3.99–6.59 | Free/paid | Free + Nitro | Core free / Plink+ ~149₽ |
| Communities / servers | Weak | ❌ | Weak | ✅ | ❌ |

Full table: [`COMPETITIVE_MATRIX.md`](./COMPETITIVE_MATRIX.md)

### 1.3 SWOT

**Strengths**
- Realtime protocol v2 (epoch/seq, clock probe, host-only commands) — better engineered than many “chat next to video” clones.
- RU stack (VK/Rutube) underserved by US competitors.
- Cinema2026 design system + living themes + custom emoji — brand differentiation.
- AI companion concept (OpenRouter) unique in pure watch-party category.
- Multi-client monorepo: iOS depth + Desktop Tauri + Landing downloads.

**Weaknesses**
- No Netflix-class catalog without ToS risk (Rave/Teleparty win here).
- Android not parity (no sync) → cannot claim “true cross-platform ±2s” yet.
- Voice **not production** (`LIVEKIT_SFU=false`, RTC 503).
- Analytics/retention instrumentation insufficient for 35% D7 target.
- Launch latency to Railway from distant clients ~1–3s (see backend metrics).
- App Store assets incomplete; crash-free 99.9% unproven.

**Opportunities**
- CIS/RU first: YouTube + VK + Rutube + cheap Plink+ (149₽ vs $4–7).
- “Honest sync” marketing: show drift ms (already on desktop UI).
- AI watch companion as retention engine (highlights, recs, “what did I miss”).
- Desktop + mobile same room as Discord-killer for *movie* nights (not gaming).
- Partnerships: RU AVOD, creators, university clubs.

**Threats**
- Rave can copy themes/emoji quickly; Discord owns social graph.
- Streaming ToS / App Store 4.2 / 5.x rejection for cinema embeds.
- YouTube embed policy / error 153 class issues recur on WebViews.
- Low trust brand (new) → CAC may exceed $2 without viral loops.
- Competitors’ free tiers + ads may undercut paid conversion.

### 1.4 Killer features (keep / build)

| Rank | Feature | Vs competitors | Priority |
|------|---------|----------------|----------|
| 1 | Sync ±2s + visible drift | Unique marketing if proven | P0 measure + ship |
| 2 | AI Companion in-room | Unique | P1 reliability + actions |
| 3 | Living themes | Unique visual | P1 premium conversion |
| 4 | VK/Rutube first-class | Regional moat | P1 sync quality |
| 5 | Cross-platform native apps | Beats Teleparty extension-only | P0 Android sync |

---

## 2. Technical Audit

### 2.1 Backend (production)

**Base:** `https://plink-backend-production-ef31.up.railway.app`  
**Health (2026-07-15):** `status=ok`, DB up, Redis up, `realtimeV2=true`, `livekitSfu=false`, RSS ≈ 96 MB, version `2.0.0-stabilize`.

#### Endpoint smoke (authenticated audit user)

| Endpoint | Result | Latency (single shot, from auditor net) |
|----------|--------|------------------------------------------|
| `GET /health` | 200 | p50 ≈ **1.5s**, p90 ≈ **3.3s** (10 samples) — **misses &lt;200ms target** (geo + cold path) |
| `POST /api/auth/signup` | 200 + JWT + refresh | ~1–2s |
| `POST /api/auth/signin` | 200 | ~1–2s |
| `GET /api/users/me` | 200 | ~1.5s |
| `GET /api/rooms` | 200 `[]` | ~1.3s |
| `POST /api/rooms` | 200 room+code | ~3.3s |
| `POST /api/rooms/join` | 200 | ok |
| `GET /api/rooms/:id/participants` | 200 | ~2.4s |
| `GET /api/rooms/:id/messages` | 200 | ~1.8s |
| `POST /api/realtime/ticket` | 200 ticket | ok |
| `POST /api/rooms/:id/leave` + empty JSON CT | **400** (client) — fixed desktop client | — |
| `GET /api/media/trending` | 200 | ok |
| `GET /api/media/search?q=lofi` | 200 | ok |
| `GET /api/friends` | 200 `[]` | ok |
| `POST /api/ai/chat` `{message}` | was 400; compat fix deployed | — |
| `POST /api/rtc/token` | **503 LiveKit not configured** | P0 for voice |
| Unauth `GET /api/rooms` | **401** | good |
| `POST /api/dev/wipe-db` no body | was **500**; now hardened | P0 security |
| `GET /api/media/youtube-player` | 200, `frame-ancestors *` | good for desktop |

#### Backend findings

| ID | Sev | Finding | Action |
|----|-----|---------|--------|
| B-P0-1 | P0 | LiveKit SFU disabled in prod | Configure keys or hide mic UI |
| B-P0-2 | P0 | wipe-db 500 / production exposure risk | Fixed body; verify `ENABLE_DEV_WIPE=false` on Railway |
| B-P1-1 | P1 | API RTT p50 &gt;1s from remote | Edge region, connection pooling, CDN for static media player HTML |
| B-P1-2 | P1 | AI requires OpenRouter key; opaque errors | Health flag + client UX |
| B-P2-1 | P2 | leave requires careful Content-Type | Client fixed; document POST no-body |

**Security positives:** JWT auth, rate limits on media/AI/GDPR/billing, helmet-like headers, WSS tickets, no unauth room list.

**Security gaps:** Confirm wipe flag off; expand audit logs for admin; chat moderation filters not fully verified; refresh rotation client-side uneven across platforms.

### 2.2 iOS

| Check | Status |
|-------|--------|
| Architecture | SwiftUI + services + realtime v2 + playback coordinators |
| Tests | ~27 unit test files (sync, auth, DM, etc.) |
| YouTube | Embedded IFrame + hosted origin strategy |
| Sync | ClockSynchronizer + OrderedSyncController patterns |
| LiveKit | `RoomRTCController` present; depends on backend tokens |
| StoreKit 2 | `plink.plus.1m/3m/12m` + server verify path |
| Analytics | Only 6 events (missing funnel events) |
| Cinema services | **Was always enabled** → **default OFF** (this audit) |
| Force unwraps | High raw count (~200+ `!` matches — needs Instruments pass) |
| TODOs | Auth2026 Google, RoomsHub share, Settings isAdmin wiring |

**Runtime (not instrumented this pass):** launch &lt;2s, battery, 30-min memory — **require TestFlight Instruments**.

### 2.3 Android

| Check | Status |
|-------|--------|
| Module size | ~20 Kotlin files — MVP skeleton |
| Auth / rooms / chat | Present |
| YouTube | Hosted player WebView URL |
| Sync | **Missing** (`sync.command` not applied to player) |
| ExoPlayer | Not primary path (WebView) |
| Lint/tests | assembleDebug OK; full lint suite not gated in CI claim |

**P0 product claim:** cannot market “true cross-platform sync” until Android applies room state.

### 2.4 Desktop (Tauri)

| Check | Status |
|-------|--------|
| Stack | React + Vite + Tauri 1.x |
| YouTube | Backend hosted iframe + postMessage (153 fix) |
| Sync | Host publish + viewer OrderedSyncController |
| AI / Friends / Rooms pages | Shell present; depth &lt; iOS |
| Voice | Not wired to LiveKit |
| Installers | DMG/EXE exist on landing; **rebuild after player fix** |

### 2.5 Landing

| Check | Status |
|-------|--------|
| Next.js pages | Home, features, privacy, terms, plus, android |
| Downloads | APK, DMG, EXE, IPA present under `public/downloads` |
| Rave-style polish | Improved; still iterate vs rave.io video brightness |

---

## 3. UX / UI Audit (code + structure)

### 3.1 Onboarding
- iOS: `PlinkOnboardingFlow` / Onboarding2026 present.
- Desktop: auth only — weak FTUE.
- Missing: progressive permission rationale (mic/notifications), measured completion funnel.

### 3.2 Home
- iOS Discovery: hero, rails, empty states (`DiscoveryEmptyState`).
- Desktop ProHome: cinema sections + living backdrop (WIP parity).
- Risk: “Смотрят сейчас” quality depends on real public rooms (empty early).

### 3.3 Watch Room (heart)
| Item | iOS | Desktop | Android |
|------|-----|---------|---------|
| Play start | Strong | Hosted YT | Hosted YT |
| Host control | Strong | Play/Pause/±10s | Weak |
| Sync &lt;2s | Designed | Designed | **No** |
| Chat | Full + emoji | Basic | Basic |
| Drift UI | Telemetry | Shown ms | No |
| Voice | Gated premium | No | No |
| Danmaku | Present | No | No |

### 3.4 Profile / Settings / Accessibility
- Profile avatar base64 path exists (backend + iOS).
- GDPR routes on backend; client surface needs verification.
- Accessibility: incomplete VoiceOver audit; Dynamic Type not systematically verified.
- Empty states: rooms/discovery exist; friends/messages uneven across platforms.

### 3.5 Design system Cinema2026
- Tokens: obsidian `#0E1113`, cyan `#2DE2E6`, emerald `#26D9A4` — iOS strongest.
- Desktop tokens.css / living themes — approaching parity, not 1:1.
- Risk: dual shells (legacy RaveClone views + 2026 features) confuse navigation.

---

## 4. Performance Audit

| Metric | Target | Observed / Expected |
|--------|--------|---------------------|
| API health RTT | p95 &lt;200ms | **p50 ~1.5s** remote — investigate region |
| Room create | &lt;1s | ~3.3s remote |
| App launch | &lt;2s | Unmeasured (need Xcode) |
| Sync drift | &lt;2s | Protocol OK; **lab 3-device test pending** |
| Memory RSS BE | &lt;200MB | ~96MB OK |
| Desktop memory | &lt;300MB | Unmeasured |
| Crash-free | 99.9% | **No production telemetry yet** |

---

## 5. Monetization Audit

| Item | Status |
|------|--------|
| Products | `plink.plus.1m`, `3m`, `12m` (matches 149 / 349 / 990₽ intent) |
| StoreKit 2 + restore | Implemented server-authoritative design |
| ASC products created | **Unknown — verify App Store Connect** |
| Premium gates | Themes, voice, some features — **inconsistent enforcement** |
| Free tier limits (1 room, 5 users, etc.) | **Not productized server-side** |
| Ads | AdSessionManager exists; strategy unclear for CIS |

**Recommendation:** Free = YouTube + chat + 10 participants; Plink+ = themes, emoji packs, voice priority, higher caps. Enforce **server-side**.

---

## 6. App Store Readiness

| Item | Status |
|------|--------|
| Metadata draft | `APP_STORE_METADATA.md` exists |
| Screenshots / preview | Incomplete |
| Privacy / Terms URLs | Landing pages exist |
| Age rating | 12+ vs 17+ inconsistency in docs |
| Cinema risk | **Mitigated** default OFF |
| IAP Guideline 3.1 | StoreKit path present |
| UGC / reporting | Report/block partially present |
| Completeness 2.1 | Voice 503 if exposed | Hide mic if LiveKit off |

---

## 7. Security Audit

| Control | Status |
|---------|--------|
| HTTPS / WSS | Yes (Railway) |
| JWT + refresh | Yes |
| Rate limits | Yes on sensitive routes |
| Unauth API | Rooms 401 OK |
| wipe-db | Hardened; ensure flag false in prod |
| Password hashing | bcrypt path (verify rounds=12 in code review) |
| Chat moderation | Incomplete for 1.1/1.2 |
| Account deletion | GDPR routes exist |
| CORS | Native Tauri + Vite origins allowlisted |

---

## 8. Analytics Audit

**Implemented (iOS):** `room_created`, `room_joined`, `message_sent`, `theme_changed`, `ai_chat_used`, `premium_purchased`.

**Missing vs target funnel:** `app_open`, `sign_up`, `login`, `voice_chat_started`, `emoji_used`, `premium_canceled`, `share_room`, `invite_friend`, onboarding steps, first_room_time.

**Retention KPIs (D1/D7/D30)** cannot be measured until analytics + beta cohort.

---

## 9. Feature Gaps (effort × impact)

| Feature | Effort | Impact | Priority | Notes |
|---------|--------|--------|----------|-------|
| Android sync | 6 | 10 | **P0** | Parity claim |
| LiveKit prod | 4 | 8 | **P0** | Or hide voice |
| 3-device drift lab | 3 | 10 | **P0** | Marketing claim proof |
| Free tier server limits | 5 | 8 | P1 | Monetization |
| Analytics funnel | 3 | 9 | P1 | Growth |
| Rebuild desktop installers | 2 | 7 | P1 | 153 fix ship |
| Screen share polish | 7 | 6 | P2 | Kast parity |
| Browser extension | 8 | 5 | P2 | Teleparty niche |
| Discord-like servers | 10 | 4 | P2 | Scope trap |
| VR | 10 | 2 | P3 | Rave vanity |

---

## 10. Prioritized Roadmap (30 days)

### Days 1–3 Audit — **DONE (this report)**

### Days 4–10 P0/P1 fixes
1. Android `sync.state` → player seek/play  
2. LiveKit env or hide mic all clients  
3. Railway `ENABLE_DEV_WIPE=false` confirm  
4. Multi-device drift test harness + log  
5. Rebuild Mac/Win installers + landing  
6. Analytics core 12 events  
7. ASC products + sandbox IAP dry run  

### Days 11–20 Differentiation
1. AI confirm actions reliability  
2. Living themes stability 30-min session  
3. Friends invite → deep link join  
4. Empty states + onboarding polish all platforms  
5. Chat report/block completion  

### Days 21–30 Polish + beta
1. TestFlight + Play internal  
2. Soft launch RU checklist  
3. Crash/ANR dashboards  
4. App Store screenshots + review notes  
5. Do **not** claim 50–100M path until D7 ≥25% in beta  

---

## 11. Acceptance vs stated criteria

| Criterion | Met? |
|-----------|------|
| AUDIT_REPORT.md | ✅ |
| Competitive matrix | ✅ COMPETITIVE_MATRIX.md |
| All P0 bugs fixed | ⚠️ partial (cinema, wipe, AI, leave, YT153); Android sync + LiveKit remain |
| All P1 implemented | ❌ next sprint |
| ASC metadata complete | ❌ draft only |
| Crash-free 99.9% | ❌ unproven |
| Sync &lt;2s on 3 devices | ❌ lab pending |
| Onboarding &gt;70% | ❌ unmeasured |
| D1 retention &gt;40% | ❌ unmeasured |
| 1:1 UX 3 platforms | ❌ Android lagging |
| Landing converts | ⚠️ functional, conversion unknown |

---

## 12. Honest “50–100M downloads” note

Rave’s scale comes from years of multi-service co-watch + distribution + network effects. Plink’s realistic 18-month path:

1. **0–3 mo:** Closed beta → soft RU (YouTube/VK/Rutube), prove sync + retention.  
2. **3–9 mo:** Android parity, voice, creator growth loops, ASC featuring attempt.  
3. **9–18 mo:** Category leadership in CIS; global only if Netflix-class problem solved **without** ToS suicide **or** screen-share mode.

Target **50–100M** is aspirational marketing, not a 30-day engineering outcome. Optimize for **D7 retention and sync trust** first.

---

## Appendices

- Live smoke user created during audit (disposable): `audit_*@plink.test` — can wipe via admin later.  
- Related docs: `MVP_STATUS.md`, `COMPETITOR_ANALYSIS.md`, `APP_STORE_METADATA.md`, `CLOSED_BETA_CHECKLIST.md`, `TEST_PLAN.md`, `BETA_TEST_PLAN.md`, `LAUNCH_PLAN.md`.

**— End of audit report —**
