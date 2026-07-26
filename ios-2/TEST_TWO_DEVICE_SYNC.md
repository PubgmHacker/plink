# Two-Device Sync Test Instruction (P0)

**Goal:** Prove the core promise of Plink — reliable synchronized playback across devices using WebSocket v2 + ClockSynchronizer.

## Prerequisites
- Two physical iOS devices (iPhone/iPad, iOS 17+) signed into same Apple ID or different for TestFlight later.
- Xcode + ability to build/run Plink on both (or one device + one simulator, note: simulator clock may drift differently).
- Backend running (production https://plink-backend-production-ef31.up.railway.app or local).
- Both devices on same WiFi or good mobile data (for minimal network variance).
- A YouTube video or public HLS/mp4 for testing (YouTube preferred for embed path).

## Recommended Test Matrix
1. Host creates room + starts YouTube video.
2. Guest joins by code.
3. Host: play / pause / seek / change rate.
4. Observe guest follows within <1-2s (target <800ms drift).
5. Reverse: make guest host (migrate).
6. Background/foreground one device.
7. Network switch (WiFi <-> LTE) on one device.
8. Long session (15+ min) for drift accumulation.
9. Custom URL (HLS) test.
10. Rutube (once wired) test.

## Step-by-step

### 1. Prepare devices
- Install latest build on both devices (same commit).
- Sign in with test accounts (or same account — different usernames).
- Make sure push registration succeeded (check logs or /api/dev/test-push later).

### 2. Start backend (if local)
```bash
cd plink-backend
# ensure .env has correct DB/REDIS/YOUTUBE_API_KEY
npm run dev
```

### 3. Device A (Host)
1. Launch Plink.
2. From Home: tap "Создать комнату" or Quick Room.
3. Choose YouTube (search or paste URL).
4. Create room, note the 6-char code.
5. Enter WatchRoom — video should load in embed view.
6. Tap Play. Note the start time.

### 4. Device B (Guest)
1. Launch Plink.
2. Use "Присоединиться по коду" and enter code from A.
3. Or use deep link if implemented: plink://room/CODE
4. WatchRoom opens, should receive initial state snapshot via WS.
5. Observe: video should start playing at same (or very close) position.

### 5. Sync actions from Host (A)
- Play / Pause — guest should match within 1s.
- Seek (scrub or jump) — guest jumps to same position.
- Change playback rate (if supported in UI) — guest follows.
- Switch video in room (if host changes media) — both reload.

Use on-screen timecodes or a stopwatch video to measure.

### 6. Measure drift
- In code there is telemetry (syncDrift metric).
- Visually: start a video with seconds counter.
- Note max observed delta between devices.
- Ideal: < 500ms. Acceptable for beta: < 1500ms.
- Check console / logs for "drift", "correction", "epoch".

In RealtimeClient / OrderedSyncController logs can be enabled.

### 7. Host migration / edge cases
- Kill host app (force quit) — guest should become host or continue with last known state.
- Rejoin on host device.
- One device loses network 10s then recovers — should resync via state request.

### 8. Record results
Document:
- Media type (YT / HLS)
- Average / max drift
- Any desync events
- Reconnect behavior
- Battery / thermal impact (long sessions)

## Debugging tips
- Enable verbose logs in RealtimeClient.swift and ClockSynchronizer.swift temporarily.
- Backend logs show `sync.command`, `state.snapshot`, seq/epoch.
- Use two devices with different timezones if possible to test clock logic.
- For production backend, watch Railway logs during test.
- If drift large: check clock offset computation, server time source, network latency in probe.

## Success criteria for closed beta
- Two devices stay in sync (<2s drift) for 30+ min session on YouTube.
- Pause/seek from either side works reliably.
- Reconnect recovers state without manual intervention.
- No crashes on rapid actions.

After successful test, update worklog or create a note in repo.

---
Last updated: 2026-07-15
Backend: stabilize/protocol-v2
iOS: main
