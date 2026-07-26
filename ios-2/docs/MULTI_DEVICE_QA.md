# Human 2-device QA (P0-3)

**Prod API:** `https://plink-backend-production-ef31.up.railway.app`  
**Team ID:** `2QAMUC4Z4P`  
**Devices:** 2 physical iPhones (user ready)

## Pre-flight

1. `xcodegen generate` in iOS monorepo root  
2. Xcode → scheme **Plink** → Release or Debug on Device A & B  
3. Sign with team `2QAMUC4Z4P`  
4. Confirm backend health: `GET /health` → 200  

## Checklist

| # | Step | Pass? |
|---|------|-------|
| 1 | Build installs without crash | ☐ |
| 2 | Device A: Sign up / sign in → token in Keychain | ☐ |
| 3 | Device B: Sign in (second account) | ☐ |
| 4 | A: Create room YouTube → play | ☐ |
| 5 | B: Join by code | ☐ |
| 6 | A: play/pause → B follows **&lt;2s** | ☐ |
| 7 | Chat A→B receive **&lt;1s** | ☐ |
| 8 | Presence count matches participants | ☐ |
| 9 | Long-press message → Report (4 reasons) | ☐ |
| 10 | Block user → messages hidden | ☐ |
| 11 | Host kick from context menu | ☐ |
| 12 | Friends tab → DM → history persists | ☐ |
| 13 | DM → «Смотреть вместе» → RoomCreation | ☐ |
| 14 | Profile stats load (me + friend) | ☐ |
| 15 | Netflix/Disney pick shows subscription disclaimer | ☐ |

## Auth smoke (API)

```bash
# Replace with test credentials
BASE=https://plink-backend-production-ef31.up.railway.app
curl -sS -X POST "$BASE/api/auth/signin" \
  -H 'Content-Type: application/json' \
  -d '{"email":"REVIEW_EMAIL","password":"REVIEW_PASSWORD"}' | head -c 200
```

## Sync notes

- Drift lab baseline: **284ms median / 292ms p95** (PASS)  
- Host publishes via `EmbeddedPlaybackController.onUserPlaybackChange` → `sync.command`  
- Guests apply ordered sync state  

## Failures → file

If any row fails, capture: device model, iOS version, room code, approx timestamp (UTC), and last 20 Xcode console lines tagged `[WS]` / `[Sync]`.
