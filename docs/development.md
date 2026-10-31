# Development setup

Flutter planner for **Windows and Android**, with Google sign-in, a local Node.js
API and private per-user data in MongoDB Atlas. Both platforms now default to
`https://microplanner-api.vercel.app`, independently of the laptop/USB connection.

Download signed Android APKs from [GitHub Releases](https://github.com/macorisd/microplanner/releases).
See [cloud hosting and Android releases](docs/cloud-and-releases.md) for installation,
signing, the development-app transition, deployment, backups and release recovery.

## Run locally

Requirements: Flutter 3.38.6 / Dart 3.10.7, Node.js 24, a configured
Google OAuth project, and an Atlas replica set (Atlas Free works).

1. Keep `server.env` in the repository root, using `server.env.example` as a
   reference. It is ignored by Git and must never be packaged with Flutter.
2. Open a terminal in `server/`:

   ```powershell
   npm ci
   npm run check:atlas
   npm run dev
   ```

3. Leave that terminal running. From the repository root, open another:

   ```powershell
   flutter pub get
   flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000
   ```

For Android, use a debug build while testing the local HTTP API:

```powershell
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Local development requires an explicit `API_BASE_URL` override. The standard
emulator reaches the host at `http://10.0.2.2:3000`; Windows uses `http://127.0.0.1:3000`.

For a physical phone over USB, enable USB debugging, connect the phone and
authorize the computer on the phone. Use `flutter devices` to find its ID.
With `adb` from the Android SDK's `platform-tools` on your PATH, run:

```powershell
adb -s <android-device-id> reverse tcp:3000 tcp:3000
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Keep the USB cable connected. Restore the reverse mapping if the phone disconnects
or restarts. The API can keep listening on `127.0.0.1`; no LAN listener is needed.
This is a development connection, not a way to distribute the app to friends.

For a physical phone over Wi-Fi, put it on the same network as the computer,
set `HOST=0.0.0.0` in `server.env`, restart the API and set its LAN address:

```powershell
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://192.168.1.20:3000
```

Replace that IP with the actual computer address. Allow the API's port through
the firewall on your private network if needed. Atlas must authorize the public
IP of the **API computer**, not the phone. API URLs and OAuth Client IDs are public
configuration; database credentials and OAuth secrets belong only on the server.

## Google configuration

The public Client IDs for the configured project are already set in the app and
API. Android initializes the official Google Sign-In plugin with the **Web Client
ID** as `serverClientId`; register `com.microplanner.microplanner` and the SHA-1 of
the signing certificate as an Android client in the same Google project.

Windows opens the system browser and uses a Desktop OAuth client, PKCE S256,
state and a random-port loopback callback. The API exchanges the authorization
code and verifies the Google ID token, including its nonce. This project's Google
Desktop client requires `GOOGLE_WINDOWS_CLIENT_SECRET` in `server.env`; copy it
from Google Auth Platform → Clients → the Desktop client. Never put it in Dart
defines or in a Flutter asset.

The API accepts only the configured Google audiences and validates the token's
signature, issuer, expiry and verified email. Google `sub` is the stable account
identifier. Local development and production may override Client IDs using:

- API: `GOOGLE_WINDOWS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`.
- Flutter Android: `--dart-define=GOOGLE_WEB_CLIENT_ID=...`.

When distributing Android with a different signing key or Play App Signing,
register the SHA-1 of the delivered app certificate. Release builds now require
the persistent release keystore; debug signing is never a release fallback.
The hosted HTTPS API is the default. Android release builds do
not permit unencrypted HTTP; the exception exists only in the debug manifest.

## MongoDB and local data

MongoDB is accessed **only by the API** using the `readWrite` role restricted to
the configured database. Boards, subjects and tasks have an `ownerId` generated
from the authenticated session; clients cannot set it. Workspace snapshots save
in a MongoDB transaction with revision checks and durable idempotency receipts.
Conflicting edits are rebased only when they do not overwrite a remotely changed
field; overlapping changes are retained for review. Receipt records are retained
without an automatic expiry so an interrupted request remains safe to retry even
after many later saves.

The UI loads on sign-in, on app resume and on explicit refresh. Changes are
visible on another device after reload; this version does not push live updates.
New writes require a connection to the API. Accepted actions are queued in an
encrypted, account-scoped journal and resume only for the same account after a
restart or sign-in. An unconfirmed network outcome remains pending rather than
being treated as a failure. Definitive failures appear in the cloud notice, with
safe retry or draft review where applicable. Confirmed remote data are cached,
encrypted with a distinct Hive key per user. Keys and session tokens use platform
secure storage. Logout immediately clears visible state; when offline, the API
session revocation is retained securely for retry. Unexpired local sessions may
read their own cache while offline; expired or server-rejected sessions return
to sign-in.

If old Hive data exist, the app offers an import. The confirmation names the
destination Google account. Import preserves existing cloud data, remaps IDs and
commits the data and migration receipt atomically. A receipt prevents retrying
into duplicates or assigning the same local source to another account. Original
Hive boxes are retained as a backup. “Not now” dismisses the offer for that
account on this device; it does not erase the originals.

If Node reports `querySrv` / `queryTxt` with `ECONNREFUSED`, the network's DNS
resolver may refuse Atlas discovery queries. Set this optional variable and
restart the API (this changes DNS for the Node process only):

```dotenv
MONGODB_DNS_SERVERS=1.1.1.1,8.8.8.8
```

## Verification

```powershell
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release
```

In `server/`:

```powershell
npm ci
npm run build
npm test
npm run check:atlas
```

To verify Atlas write permissions and transaction commit/rollback, run
`npm run check:atlas -- --write`. It creates and removes a fresh temporary
verification collection and does not modify planner records.

API tests start an isolated local MongoDB replica set and test account isolation,
session revocation, malformed Google identities, PKCE/nonce, concurrent edits,
idempotent retries and migration. They do not use Atlas credentials. Google login
with real accounts must additionally be checked on the configured devices.

`/health/live` checks the API process; `/health/ready` pings MongoDB. The API does
not log request bodies, tokens or connection strings. It uses hashed, expiring
and revocable session tokens; authentication endpoints are rate limited.

## Versioning

Before 1.0.0, new functionality is minor and bug fixes are patch; no major bumps
are made solely for scope. The move to 1.0.0 is an explicit maturity decision.
After that, ordinary major/minor/patch rules apply. Approved changes follow the
single plan in `plans/` and are delivered by pull request.
