# Plink MVP — COMPLETE (16 July 2026)

## Verdict: **Closed-beta MVP SHIPPED**

| Platform | Auth | Room | Chat | YouTube | Sync | Installer |
|----------|------|------|------|---------|------|-----------|
| iOS | ✅ | ✅ | ✅ | ✅ | ✅ | IPA |
| Android | ✅ | ✅ | ✅ | ✅ | ✅ | **APK (36MB, rebuild)** |
| Mac arm64 | ✅ | ✅ | ✅ | ✅ | ✅ | **DMG from CI 21MB** |
| Mac Intel | ✅ | ✅ | ✅ | ✅ | ✅ | **DMG from CI** |
| Windows | ✅ | ✅ | ✅ | ✅ | ✅ | **EXE+MSI from CI SUCCESS** |
| Backend | ✅ | ✅ | ✅ | ✅ | ✅ | Railway live |

## Downloads

`plink-landing/public/downloads/`:

- `Plink.dmg` / `Plink-1.0.0-arm64.dmg` — macOS Apple Silicon  
- `Plink-1.0.0-x64.dmg` — macOS Intel  
- `Plink-1.0.0-x64-setup.exe` — Windows NSIS  
- `Plink-1.0.0-x64.msi` — Windows MSI  
- `app-debug.apk` — Android  
- `Plink.ipa` — iOS  

**Master pack:** `/Users/hellcart/Desktop/PLINK-MVP-COMPLETE.zip` (~docs + installers)

## Drift lab PASS

```
median lag: ~300 ms · p95: ~350 ms · 20/20 samples
```

`npm run drift-lab` / `node scripts/drift-lab.mjs`

## CI

- Windows EXE: https://github.com/PubgmHacker/repo-d0e90e58-f87bbc/actions/runs/29424701328 **success**
- Desktop matrix: https://github.com/PubgmHacker/repo-d0e90e58-f87bbc/actions/runs/29424706090 **success**

## Still needs human (cannot automate without accounts)

1. **LiveKit keys** → `docs/LIVEKIT_SETUP.md` (mic stays hidden until then)  
2. **App Store Connect** products + screenshots → `docs/APP_STORE_SUBMISSION.md`  
3. **TestFlight** invites → `docs/BETA_LAUNCH.md`  
4. **Android signing** for Play Internal (debug APK is for sideload)  

## Core test path

1. Install Mac/Win/Android  
2. Sign up → create room from trending  
3. Second device join by code  
4. Host play/pause/seek → guest follows · chat works  
