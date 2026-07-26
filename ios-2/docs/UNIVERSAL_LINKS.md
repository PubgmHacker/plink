# Universal Links / App Links (M12)

Глубокие ссылки вида `https://plink.app/r/<код-комнаты>` и `https://plink.app/u/<userId>`.

## Что уже сделано

- **iOS**: `DeepLinkRouter.swift` разбирает `plink://` и `https://plink.app/...` (было раньше).
- **Android**: в `AndroidManifest.xml` добавлены intent-фильтры:
  - `https://plink.app/r/*`, `https://plink.app/u/*` с `android:autoVerify="true"`;
  - fallback-схема `plink://`.
- **Бэкенд** отдаёт файлы ассоциации:
  - `GET /.well-known/apple-app-site-association`
  - `GET /.well-known/assetlinks.json`

## Что нужно, когда появится Apple Developer аккаунт

1. Задать env-переменную бэкенда `APPLE_TEAM_ID=<TeamID>` (сейчас заглушка `TEAMID`).
2. В Xcode включить capability **Associated Domains** и добавить `applinks:plink.app`
   (в `project.yml` — через `entitlements`).
3. Проверить: https://app-site-association.cdn-apple.com/a/v1/plink.app

## Что нужно для Android App Links

1. Собрать release с подписью (env: `PLINK_KEYSTORE_PATH`, `PLINK_KEYSTORE_PASSWORD`,
   `PLINK_KEY_ALIAS`, `PLINK_KEY_PASSWORD`).
2. Получить SHA256 отпечаток: `keytool -list -v -keystore plink.keystore`.
3. Задать env бэкенда `ANDROID_CERT_SHA256=<отпечаток>`.
4. Проверить: `adb shell pm verify-app-links --re-verify com.plink.app`.
