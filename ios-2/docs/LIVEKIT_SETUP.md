# LiveKit setup (voice)

MVP ships with **mic UI hidden** until LiveKit is configured.

## Railway

```bash
cd plink-backend
railway variables set LIVEKIT_URL="wss://YOUR_PROJECT.livekit.cloud"
railway variables set LIVEKIT_API_KEY="APIxxxx"
railway variables set LIVEKIT_API_SECRET="secretxxxx"
railway variables set LIVEKIT_SFU=true
```

Create a free project at https://cloud.livekit.io

## Verify

```bash
curl -s https://YOUR_API/api/rtc/status
# {"livekitEnabled":true,"livekitSfuFlag":true}

curl -s https://YOUR_API/health | jq .services.livekitSfu
# true when keys present
```

## Clients

| Client | Behavior |
|--------|----------|
| iOS | Polls `/api/rtc/status` on launch; shows mic when `livekitEnabled` |
| Desktop | Voice not wired (chat-only MVP) |
| Android | Voice not wired |

Force-enable iOS UI for local testing: Info.plist `ENABLE_LIVEKIT_VOICE` = `true`.
