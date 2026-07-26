# Plink+ StoreKit Sandbox Testing Guide (P1)

## Prerequisites (App Store Connect)

1. Go to App Store Connect → My Apps → Plink.
2. Create in-app purchases (non-renewing or auto-renewable subscriptions):
   - `plink.plus.1m`   (monthly)
   - `plink.plus.3m`   (quarterly)
   - `plink.plus.12m`  (yearly)
3. Set prices, add localization, submit for review (or use "Clear for Sale" + "Ready to Submit").
4. Create a Sandbox Tester account (Users and Access → Sandbox Testers). **Do not use your real Apple ID**.
5. On the test device: Settings → App Store → Sandbox Account → sign in with the tester.

## On-device testing steps

1. Build & run the app with a **Development** signing profile (not Release).
2. Log in with a test user.
3. Go to Settings → Plink+ section or tap the Paywall.
4. Tap "Load products" (or it loads automatically).
5. Choose a plan and purchase.
   - You should see the Apple sandbox purchase sheet (with "[Environment: Sandbox]" in the title on iOS 17+).
   - Do **not** use a real payment method.
6. After success, the app calls backend `/api/billing/verify` with the JWS.
7. Backend should return entitlement and mark the user as premium.

## Verify on backend

- Call (with auth token):
  ```
  GET https://plink-backend-production-ef31.up.railway.app/api/billing/entitlements
  ```
- Or use the dev endpoint if you added test helpers.
- Check `isPremium` and `premiumUntil` on the user.

## Common sandbox gotchas & fixes

- Product IDs must **exactly** match between Xcode / App Store Connect and `PlinkProductID`.
- Backend `PLANS` must include the IDs (we updated them to `plink.plus.*`).
- First purchase after adding products can take a few minutes to propagate in sandbox.
- Use **AppStore.sync()** + restore if entitlements look stale.
- For receipt-based fallback, set `APP_STORE_SHARED_SECRET` in backend env (from App Store Connect → In-App Purchases → App-Specific Shared Secret).
- JWS path is preferred (StoreKit 2). The backend now handles both JWS and legacy receipts.

## Useful logs

iOS:
- `StoreManager` prints state changes.
- Look for "verifying", "BackendEntitlementResponse".

Backend:
- Logs in `/billing/verify`.
- Check `AuditLog` for `USER_PREMIUM_GRANTED`.

## Restoring purchases

- Always implement and expose Restore (App Review requirement).
- Test: Purchase on one device → sign in with same sandbox tester on second device → tap Restore.

## After successful sandbox tests

- Switch to production products (same IDs).
- Backend will automatically try production verify URL first, then fall back to sandbox if Apple says 21007.
- Set up App Store Server Notifications V2 endpoint (`/api/billing/webhooks/apple`) for server-side renewals/cancellations.

Good luck with closed beta monetization!
