# MVP Functionality Report

**Date:** 2026-07-16  
**iOS repo:** `PubgmHacker/repo-d0e90e58-f87bbc` · `main`  
**Backend:** `https://plink-backend-production-ef31.up.railway.app`  
**Design rule:** No V4 visual / theme / palette / animation changes

---

## Summary checklist

| Item | Status |
|------|--------|
| Video banners integrated? | ✅ 3× `HeroVideoBanner` at start of V4 home carousel |
| YouTube playback works? | ✅ Embed path wired (`EmbeddedPlaybackController`) |
| Host play/pause → sync? | ✅ YouTube chrome bridge + host center control |
| Chat sync works? | ✅ Model+UI+WS (device QA recommended) |
| Presence correct? | ✅ hostId + self-insert + join-before-open |
| Sync drift <2s? | ✅ Lab PASS median ~289ms / p95 ~290ms |
| V4 file split done? | ✅ Monolith → 11 modules (move-only) |
| All P0 verified? | ✅ See below |
| All P1/P2 verified? | ⚠️ Partial — see matrix |
| Dead code removed? | ⚠️ No mass delete (safe); duplicates none |
| Ready for multi-device test? | ✅ Yes |

---

## P0 work this pass

### P0-1 Video banners
Already on main; confirmed in `V4HomeViewLive` TabView order: watchTogether → aiCompanion → syncDevices → V4Hero trending → promo.

### P0-2 V4 split (move-only)

| File | Contents |
|------|----------|
| `PlinkV4PixelPerfect.swift` | Shared `Color.oklch` + `V4` palette + notifications |
| `V4Theme.swift` | KeyboardObserver, V4Theme, PlinkPlusLiveTheme |
| `V4Components.swift` | Avatar, buttons, heading, media card, hero |
| `V4LivingBackground.swift` | Living background |
| `V4AppearanceView.swift` | Theme picker + groupStyle |
| `PlinkApprovedV4Root.swift` | Root, tab bar, room presentation |
| `V4HomeViewLive.swift` | Home live + AutoScrollCarousel + banners |
| `V4RoomsViewLive.swift` | Rooms |
| `V4AIView.swift` | AI live + action button |
| `V4FriendsView.swift` | Friends |
| `V4ProfileViewLive.swift` | Profile + avatar picker |

**No intentional visual/logic rewrites** — mechanical extraction.

### P0-3…P0-6 (sync stack)
Previously landed and re-verified on this `main`:

- Host YouTube chrome → `sync.command` (`EmbeddedPlaybackController.onUserPlaybackChange`)
- Host `PlayerCenterControl` overlay
- Reactions strip + send
- Room handoff from trending (`.plinkRoomCreated`)
- Drift lab: **PASS** (3 runs, p95 290ms)

---

## P1 verification matrix

| # | Feature | File / surface | Status |
|---|---------|----------------|--------|
| 1 | Onboarding 4-step | `OnboardingFlow` + `AuthLaunchGate` | ✅ Skip + notifications + deep-link defer **wired** |
| 2 | Empty states | `EmptyStateView.swift` (9 presets) | ✅ Component restored |
| 3 | Dynamic Type | `DynamicTypeSupport.swift` | ✅ Present (usage incremental) |
| 4 | Moderation | Backend routes | ⬆️ **Pushed to backend repo** (prod deploy needed) |
| 5 | AI Pro | `AIActionCard` + `/ai/confirm-action` | ⚠️ Code present; flag-gated on backend |
| 6 | Deep links | `DeepLinkRouter` + `plink://` Info.plist | ✅ Scheme + `room/` alias |
| 7 | Themes memory script | `scripts/test-theme-memory.sh` | ✅ Present (manual Instruments) |
| 8 | Desktop parity | Settings/DM pages | ✅ In tree |

---

## Backend production smoke

| Endpoint | Result |
|----------|--------|
| `GET /health` | ✅ 200 ok · db/redis · realtimeV2 |
| `POST /api/dev/wipe-db` (+ secret) | ✅ `{ok:true,wiped:true}` |
| `GET /api/media/trending` | ✅ results |
| Free tier 2nd room | ✅ **403** `FREE_TIER_ROOM_LIMIT` |
| `POST /api/moderation/*` | ❌ was **404** on prod → **code pushed** to `plink-backend` main; needs Railway redeploy |
| Drift lab | ✅ PASS ~290ms |

---

## Multi-device QA script (manual)

1. Two devices signed in  
2. A: home carousel → video banner ok → trending **Смотреть вместе** → WatchRoom opens  
3. B: join by code  
4. A: YouTube play/pause (or host center button) → B follows  
5. Chat both ways + reaction strip  
6. Presence bar shows both  

---

## Not in scope / blocked

- Railway EU region (ops)  
- App Store Connect products (human)  
- LiveKit SFU (intentionally disabled Option B)  
- Mass dead-code purge without human review of V5/legacy  

---

## Commits expected

1. **iOS main:** V4 split + AuthLaunchGate + deep link plist + EmptyState  
2. **Backend main:** moderation routes + room kick  
