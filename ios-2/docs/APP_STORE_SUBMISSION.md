# App Store submission kit (MVP)

## Product IDs (StoreKit)

| Product | ID | Price intent |
|---------|-----|--------------|
| 1 month | `plink.plus.1m` | 149₽ |
| 3 months | `plink.plus.3m` | 349₽ |
| 12 months | `plink.plus.12m` | 990₽ |

Create auto-renewable subscription group **Plink+** in App Store Connect.

## Metadata

See `APP_STORE_METADATA.md`.

- **Name:** Plink — Watch Together / Плинк — смотрите вместе  
- **Category:** Entertainment  
- **Age:** 12+ or 17+ if UGC chat unmoderated  
- **Privacy / Terms:** landing `/privacy` `/terms`

## Screenshots checklist

| Device | Required | Content |
|--------|----------|---------|
| 6.7" iPhone | ☐ | Home hero, Watch room, AI, Friends, Profile+ |
| 6.5" iPhone | ☐ | Same set |
| 12.9" iPad | ☐ | Split watch room |

### Capture (Simulator)

```bash
# After xcodegen + build
xcrun simctl io booted screenshot ~/Desktop/plink-home.png
```

Or use Xcode → Simulator → Device → Screenshots.

Service logos (Netflix, Disney+, Kinopoisk, ivi, Okko, etc.) may appear as
**host-selectable destinations**. Screenshots should show the in-app disclaimer:
“Требуется активная подписка… Plink не предоставляет контент”.

## Review notes template (copy into App Store Connect)

```
Demo account: <email> / <password>

Core flow:
1. Sign in → Home → Create room (YouTube)
2. Join from a 2nd device with room code
3. Host play/pause → guest follows (<2s)
4. Chat send → receive (<1s)
5. Long-press chat message → Report / Block
6. Host can Kick participant from chat context menu

Content & services (Guideline 5.2):
Plink does not stream, redistribute, or circumvent DRM.
Host logs into their own subscription account in a WebView
(Netflix, Disney+, Kinopoisk, ivi, Okko, etc.).
Guests see the host’s session via sync technology
(embedded official players / screen-sync). No content is
copied, downloaded, or re-streamed by Plink.
Direct googlevideo.com / CDN extract URLs are blocked in
Release builds. YouTube uses the official IFrame player.

IAP: Plink+ sandbox products plink.plus.1m / 3m / 12m
Voice: disabled until LiveKit configured (mic hidden)
UGC: Report (spam/harassment/nsfw/other) + Block + Host Kick
```

## Guidelines risk map

| Guideline | Status |
|-----------|--------|
| 2.1 Completeness | Core loop works; voice hidden not broken |
| 3.1.1 IAP | StoreKit 2 only |
| 4.2 Min functionality | Native app, not shell browser |
| 5.1 Privacy | Policy URL required |
| 5.2 Intellectual property | Host-subscription WebView + disclaimer; no DRM circumvention |
| UGC (chat) | Report / Block / Host Kick |

## Demo account checklist

- [ ] Create `review@plink.app` (or ASC demo) on prod
- [ ] Seed 1 public YouTube room + 1 friend
- [ ] Verify auth → Keychain token persists
- [ ] Verify YouTube IFrame play on device

## Upload

1. Archive in Xcode (Release, team signing)  
2. Upload via Organizer / Transporter  
3. Attach screenshots + review notes above  
4. Submit for review  
