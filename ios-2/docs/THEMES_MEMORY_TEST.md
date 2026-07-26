# Living Themes — 30-minute Memory Test

## Goal
Confirm living backgrounds / theme video do not leak memory under closed-beta load.

| Platform | Target RSS after 30 min active room |
|----------|-------------------------------------|
| iOS | < 200 MB |
| Android | < 150 MB |

## Preconditions
- Build Release (or Profile) — not Debug with Instruments overhead alone
- Reduce Motion **OFF** for motion path; re-run with **ON** for static path
- Join a room with a living theme / ambient backdrop enabled

## iOS (Instruments)
1. Xcode → Product → Profile → Allocations + Leaks
2. Launch Plink, complete onboarding if needed
3. Open Watch Room with theme/backdrop for **30 minutes**
4. Background app 2 minutes → foreground
5. Switch theme 5× (if picker available)
6. Leave room → return home

### Pass criteria
- No unbounded growth after first 5 minutes (slope ≈ 0)
- Leaks instrument: 0 persistent theme-related objects after leave room
- Reduce Motion: no looping video / infinite orb animation

## Android
1. Android Studio Profiler → Memory
2. Same scenario as iOS for 30 minutes
3. Force GC mid-session; RSS should return near baseline after leave

## Reduce Motion / Thermal
- `CompactLivingBackdrop` and ambient video must respect reduce motion / thermal / LPM gates
- On reduce motion: static gradient/poster only

## Record results
| Date | Build | Device | Peak MB | Pass? | Notes |
|------|-------|--------|---------|-------|-------|
| | | | | | |
