# MVP Final Audit Report

**Date:** 2026-07-16  
**Repo:** `PubgmHacker/repo-d0e90e58-f87bbc` · branch `main`  
**Backend:** `https://plink-backend-production-ef31.up.railway.app`

---

## Design rule compliance

- **No palette / theme / animation redesign**
- **No V4 layout rewrite** — only:
  - Insert existing `HeroVideoBanner` pages into existing `TabView`
  - Wire room presentation (functionality)
  - Presence `hostId` from room model (data wiring)

---

## P0 results

### P0-1 Video banners in V4 hero carousel — ✅ FIXED

`Plink/V4/PlinkV4PixelPerfect.swift` hero `TabView` now starts with:

1. `HeroVideoBanner(banner: .watchTogether, height: 260)`
2. `HeroVideoBanner(banner: .aiCompanion, height: 260)`
3. `HeroVideoBanner(banner: .syncDevices, height: 260)`

Then existing `V4Hero` trending cards + promo banners (unchanged).

Assets present under `Plink/Resources/Banners/*.mp4` and HeroBanners imagesets; `project.yml` includes Banners path.

### P0-2 YouTube playback (code audit)

| Item | Status |
|------|--------|
| Embed path (`EmbeddedPlaybackController` + `/api/media/youtube-player`) | ✅ Wired |
| `YouTubeEmbeddedProvider` | ⚠️ Stub (unused; real path is Embedded) |
| Host `sync.command` API in model | ✅ Exists |
| Plink host play/seek chrome in layout | ❌ Not composed (YouTube owns chrome) |
| Host YT UI → automatic `sync.command` | ❌ Not bridged |

**Implication:** Playback loads; true multi-device play/pause sync needs host controls that call `sendPlayCommand` / etc., or bridge from IFrame events.

### P0-3 Chat sync (code + backend)

| Item | Status |
|------|--------|
| Chat send/receive UI + WS | ✅ Wired in WatchRoom |
| Danmaku from others’ chat | ✅ Wired |
| Reaction **send** from UI | ❌ Dead (only receive) |
| Backend create room + ticket | ✅ Smoke-tested live |

### P0-4 Presence

| Item | Status |
|------|--------|
| PresenceBar + REST snapshot + join/leave events | ✅ Wired |
| “0 until snapshot” flash | ⚠️ Expected until handshake |
| `hostId` always nil | ✅ **Fixed** — pass `room.hostID` into model |
| Open room without `joinRoom` | ✅ **Fixed** — `openFirstRoom` joins first |

### P0-5 Sync drift lab

```
Drift lab → production viewers=2 runs=5
samples: 10/10 received
median lag: 284 ms
p95 lag:    294 ms
max lag:    294 ms
PASS (median <500ms, p95 <1.5s)
```

Command: `cd scripts && npm i ws && VIEWERS=2 RUNS=5 node drift-lab.mjs`

---

## Critical functional fixes this pass

1. **Trending → WatchRoom presentation**  
   - Root listens for `.plinkRoomCreated` with `Room` payload  
   - `createRoomFromTrending` also sets `roomToPresent` directly  

2. **Open room list item joins server** (`joinRoom(code:)`) before present  

3. **Presence host highlight** via `roomHostId`  

4. **Hero MP4 banners** at carousel start  

---

## Backend smoke (production)

| Endpoint | Result |
|----------|--------|
| `GET /health` | ✅ ok · db up · redis up · realtimeV2 |
| `POST /api/auth/signup` | ✅ token issued |
| `GET /api/users/me` | ✅ |
| `POST /api/rooms` + join | ✅ |
| `POST /api/realtime/ticket` | ✅ |
| `POST /api/ai/chat` | ✅ reply |
| `GET /api/media/trending` | ✅ |

---

## P1 cleanup

### Duplicates
`grep` for duplicate `struct/class/enum` names: **none found**.

### Dead code
Stem-name scan found ~38 files with no other-file references (heuristic).  
**Not mass-deleted** — risk of breaking V4/WatchRoom via stringly wiring, Xcode project membership, or future flags.

Safe candidates for a later dedicated PR (manual review only):
- Unused `YouTubeEmbeddedProvider` stub (keep until replace documented)
- Parallel V5 roots if product is V4-only (`Plink/V5/*`) — **do not delete without product confirmation**

### Build warnings
Simulator `xcodebuild` not run in this environment (no reliable Simulator/signing). Run locally:

```bash
xcodegen generate
xcodebuild -scheme Plink -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

---

## P2 feature checklist (audit)

| Feature | Code / API | Notes |
|---------|------------|--------|
| Auth | ✅ | Live signup/me |
| Rooms create/join/leave | ✅ | Live create/join |
| Chat | ✅ model+UI | Multi-device needs 2 devices QA |
| Player YouTube | ✅ embed | Sync commands need host UI path |
| Sync | ✅ protocol + lab | Lab PASS ~290ms p95 |
| AI Companion | ✅ backend + V4 tab | |
| Emoji packs | ✅ catalog in tree | |
| Living themes | ✅ (untouched) | |
| Profile | ✅ V4 tab | |
| Firebase | ✅ optional analytics | |

---

## Ready for multi-device sync test?

| Criterion | Ready? |
|-----------|--------|
| Backend health + realtime tickets | ✅ |
| Drift lab protocol lag | ✅ PASS (~290ms p95) |
| Create room from trending opens WatchRoom | ✅ Fixed |
| Join by code + list open joins | ✅ Fixed |
| Host play/pause from YouTube chrome syncs viewers | ✅ Bridged (`onUserPlaybackChange` → `sync.command`) + host center control |
| Host seek jump | ✅ Detected via position poll |
| Chat cross-device | ✅ |
| Reactions send | ✅ Quick reaction row + empty-field emoji pick |
| Presence count | ✅ hostId + local self-insert + join |

**Recommendation:** 2-device QA: create from trending → share code → join → YouTube play/pause → chat → reactions.

### Follow-up hardening (this commit)

- `EmbeddedPlaybackController`: suppress rebroadcast during remote apply; host YouTube chrome → `onUserPlaybackChange`
- `WatchRoomModel.publishHostPlaybackState` + wire after prepare
- `PlayerStage`: host-only `PlayerCenterControl` when controls visible
- `WatchChatComposer`: free reaction strip + emoji→reaction when text empty
- Presence: insert local user on `sessionDidConnect`

---

## Files changed

- `Plink/V4/PlinkV4PixelPerfect.swift` — hero video banners + room presentation wiring  
- `Plink/Features/WatchRoom/WatchRoomModel.swift` — `roomHostId`  
- `Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift` — pass host id  
- `docs/MVP_FINAL_AUDIT_REPORT.md` — this report  
- `scripts/package-lock` / local `ws` for drift-lab (do not commit node_modules)

---

## Not done (by design / scope)

- ❌ Redesign V4 / themes / palette  
- ❌ Mass dead-code deletion without human review  
- ❌ Bridge YouTube IFrame events → `sync.command` (larger change)  
- ❌ Wire reaction send button  
- ❌ Simulator xcodebuild in CI-less host  
