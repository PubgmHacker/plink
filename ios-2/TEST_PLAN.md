# Plink Regression Test Plan

**Version:** 1.0 · 2026-07-15  
**Applies to:** iOS, Android, Desktop, Backend `2.0.0-stabilize`

## 1. Environments

| Env | API | Notes |
|-----|-----|-------|
| Production | `https://plink-backend-production-ef31.up.railway.app` | Smoke only; no wipe |
| Staging | (create Railway clone) | Preferred for destructive tests |

## 2. Core happy path (every build)

| # | Step | iOS | Android | Desktop | Pass criteria |
|---|------|-----|---------|---------|---------------|
| 1 | Sign up | ☐ | ☐ | ☐ | Token stored securely |
| 2 | Sign in / out / re-in | ☐ | ☐ | ☐ | Session restores |
| 3 | Trending loads | ☐ | ☐ | ☐ | Thumbnails visible |
| 4 | Create room from YT | ☐ | ☐ | ☐ | Code shown; single room |
| 5 | Join by code (2nd device) | ☐ | ☐ | ☐ | Same media title |
| 6 | Chat send/receive | ☐ | ☐ | ☐ | &lt;1s perceived |
| 7 | Host play/pause/seek | ☐ | ☐ | ☐ | Guest follows &lt;2s |
| 8 | Leave room | ☐ | ☐ | ☐ | No crash; list updates |
| 9 | Avatar upload | ☐ | ☐ | ☐ | Visible after relaunch |
| 10 | Background 30s + resume | ☐ | ☐ | ☐ | WS reconnects |

## 3. Sync lab (P0)

**Setup:** 1 host + 2 viewers, same Wi‑Fi, then mixed Wi‑Fi/cellular.

| Scenario | Measure | Target |
|----------|---------|--------|
| Host play | Time to guest playing | median &lt;500ms, p95 &lt;1.5s |
| Host pause | Guest paused | p95 &lt;1.5s |
| Seek +30s | Position error | &lt;2s after settle |
| 30-min session | Disconnects | 0 unhandled |
| Host leave | Role migrate / room end | No zombie room |

Record: device, OS, build, room code, timestamps, drift ms (desktop UI).

## 4. YouTube / providers

| Case | Expected |
|------|----------|
| Normal public video | Plays, no error 153 |
| Age-restricted | Graceful error |
| Invalid id | Error UI |
| VK / Rutube | Plays if available; no crash |
| Cinema services | **Hidden** when ENABLE_CINEMA false |

## 5. Security / abuse

| Case | Expected |
|------|----------|
| No token on /rooms | 401 |
| Non-host sync.command | NOT_HOST error |
| Rate limit auth | 429 after burst |
| wipe-db no secret | 401/403, never 500 |
| XSS in chat text | Escaped in UI |

## 6. Premium / IAP (sandbox)

| Case | Expected |
|------|----------|
| Purchase 1m | isPremium true server |
| Restore | Entitlement returns |
| Free user voice | Gated or hidden |
| Premium theme | Applies for host guests |

## 7. Platform-specific

### iOS
- Landscape watch room drawer  
- PiP / background audio policy  
- Push test (admin)  
- iPad split layout  

### Android
- Back stack from room → home  
- Rotation  
- WebView player after process death  

### Desktop
- Keyboard shortcuts  
- Mini player pop-out  
- Tray (if enabled)  
- Offline network error copy  

## 8. Exit criteria for release candidate

- [ ] Core path 10/10 on iOS + Desktop  
- [ ] Core path 8/10 on Android (sync may still be WIP — label beta)  
- [ ] Zero P0 open  
- [ ] Sync lab recorded for 2 sessions  
- [ ] No 153 on 5 random trending videos  
