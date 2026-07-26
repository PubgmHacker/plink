# Screenshot capture kit

## iOS Simulator (preferred)

```bash
cd Desktop/Grok
# Generate Xcode project if needed
xcodegen generate   # if project.yml present

# Boot device
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
open -a Simulator

# After logging in and opening each screen:
mkdir -p docs/screenshots
xcrun simctl io booted screenshot docs/screenshots/01-home.png
xcrun simctl io booted screenshot docs/screenshots/02-watchroom.png
xcrun simctl io booted screenshot docs/screenshots/03-ai.png
xcrun simctl io booted screenshot docs/screenshots/04-friends.png
xcrun simctl io booted screenshot docs/screenshots/05-profile.png
xcrun simctl io booted screenshot docs/screenshots/06-paywall.png
```

## Required ASC sizes

| Display | Width | File prefix |
|---------|-------|-------------|
| 6.7" | 1290×2796 | iphone67- |
| 6.5" | 1242×2688 | iphone65- |
| iPad 12.9" | 2048×2732 | ipad- |

Scale with:

```bash
sips -z 2796 1290 docs/screenshots/01-home.png --out docs/screenshots/iphone67-01-home.png
```

## Content rules

- ✅ YouTube / VK / Rutube only  
- ❌ No Netflix / Disney / cinema logos  
- Show room code + sync pill if possible  
