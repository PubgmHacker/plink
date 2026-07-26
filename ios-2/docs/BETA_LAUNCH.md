# Closed beta launch pack

## Builds

| Platform | Artifact |
|----------|----------|
| iOS | TestFlight (archive from Xcode) or `downloads/Plink.ipa` |
| Android | `plink-landing/public/downloads/app-debug.apk` → sign for Play Internal |
| Mac | `downloads/Plink.dmg` / `Plink-1.0.0-arm64.dmg` |
| Windows | GitHub Actions `Build Windows .exe` → artifact |

## Cohort (20–25)

- 10 iOS + Mac  
- 5 Android  
- 5 cross-platform pairs  

## Day-0 script (Telegram)

1. Install build  
2. Register  
3. Create room from trending  
4. Friend joins by code  
5. 10 min play/pause/chat  
6. File bugs with template in `BETA_TEST_PLAN.md`  

## Ops

- Backend: Railway production  
- Kill switches: `AI_ACTIONS_ENABLED=false`, cinema off, voice off until LiveKit  
- Daily triage 30 min  

## Success gates → soft launch

- [ ] No P0 for 48h  
- [ ] Drift lab PASS (`node scripts/drift-lab.mjs`)  
- [ ] D1 return ≥40% of cohort  
- [ ] Crash-free ≥99% (Firebase Crashlytics)  
