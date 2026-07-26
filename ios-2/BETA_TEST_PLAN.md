# Plink Closed Beta Plan

**Version:** 1.0 · 2026-07-15  
**Goal:** Validate core “watch together” loop before soft launch.

## 1. Cohort

| Segment | Count | Devices |
|---------|-------|---------|
| Friends / power users | 10 | iPhone + Mac |
| Android-only | 5 | Android 12–14 |
| Cross-platform pairs | 5 pairs | iOS↔Desktop, iOS↔Android |
| **Total seats** | **20–25** | |

## 2. Builds

| Platform | Channel | Build |
|----------|---------|-------|
| iOS | TestFlight | latest main IPA |
| Android | Internal Play / APK link | `app-debug.apk` → signed release ASAP |
| Desktop | DMG / EXE from landing | rebuild after YT player fix |
| Backend | Railway production or staging | pin commit in release notes |

## 3. What to test (week 1)

Daily prompt (Telegram/Discord beta chat):

1. Create room with trending YouTube  
2. Invite 1 friend by code  
3. Chat + play/pause 10 minutes  
4. Optional: avatar, friends request  
5. File bug with template below  

## 4. Bug template

```
Build:
Platform / OS:
Account role (host/guest):
Steps:
Expected:
Actual:
Video/screenshot:
Room code:
Approx time (UTC):
```

## 5. Severity

| Sev | Definition | SLA |
|-----|------------|-----|
| P0 | Crash core loop, auth broken, data loss, security | 24h |
| P1 | Sync &gt;5s, chat lost, player 153, leave broken | 72h |
| P2 | UI polish, empty states, copy | weekly |

## 6. Success metrics (beta)

| Metric | Target |
|--------|--------|
| Crash-free sessions | ≥99% |
| Room create success | ≥95% |
| Pair sync “felt in sync” survey | ≥80% yes |
| D1 return (install → day2 open) | ≥40% of cohort |
| NPS | ≥30 |

## 7. Ops

- Owner: product/eng on-call daily 30 min triage  
- Kill switch: disable AI actions / cinema flags via env  
- Rollback: previous Railway deploy + previous TestFlight build  

## 8. Exit to soft launch

- [ ] No open P0  
- [ ] Android can at least play + chat (sync preferred)  
- [ ] 2× successful 3-device sessions documented  
- [ ] Privacy/Terms links live  
- [ ] Support channel staffed  
