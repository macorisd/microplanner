# Cloud hosting and Android releases

## Install and update Android

Open [Releases](https://github.com/macorisd/microplanner/releases), choose a
prerelease and download `microplanner-<version>-android.apk`. Allow installation
from your browser/file manager if Android requests it. Sign in with Google;
Windows and Android use the hosted API without the laptop API or USB.
The configured Google project's consent/testing restrictions still apply.

The adjacent `.apk.sha256` file contains the APK's SHA-256 checksum. On Windows,
run `Get-FileHash .\microplanner-0.2.0-android.apk -Algorithm SHA256` and compare it
with that file. Updates are manual downloads, with the same signing certificate
and a higher Android build number. There is no in-app updater.

The old USB test app used a debug certificate and cannot be updated in place
with the new release certificate. Before replacing it, refresh and confirm each
account's data on another device. Import any wanted local-only data and back up
anything still local. Only then deliberately uninstall the development app,
install the release APK and sign in again. Uninstalling deletes that installation's
cache and legacy Hive boxes; cloud data remain in Atlas. Never silently uninstall
an app to work around a signing mismatch.

## Vercel deployment

Project: <https://vercel.com/macoris-projects/microplanner-api>.
Production API: <https://microplanner-api.vercel.app>.
Use Root Directory `server`, Fastify, Node.js `24.x`, production branch `main`,
and automatic build/install/output settings. `src/index.ts` imports Fastify and
starts the server; `application.ts` contains the testable app factory.

Keep these variables in Vercel **Production only**:

| Variable | Contents |
|---|---|
| `MONGODB_URI` | Private Atlas connection string |
| `MONGODB_DB` | `microplanner` |
| `GOOGLE_WINDOWS_CLIENT_SECRET` | Existing Desktop OAuth client secret |

Public Google client IDs already have matching defaults in the API/app. Use
Standard Protection so the production domain is public and preview URLs remain
protected. Previews receive no production database credentials and cannot serve
account data. Never embed a protection-bypass token or server secret in the app.

Merges to `main` deploy automatically. To test a feature deliberately on the
production domain, promote its preview; Vercel rebuilds it with Production
variables. Redeploy after changing variables. Check `/health/live` (200 process),
`/health/ready` (200 authenticated DB ping), and `/workspace` without a session
(401). The root URL is not a health endpoint. On a bad release, use Vercel's
Instant Rollback to a previously working production build, inspect sanitized
logs, fix the source and redeploy. Rollback does not restore or erase MongoDB data.

Connections are reused per warm instance, with a maximum pool of five. Failed
initialization can retry. Hosted rate limits use hashed per-IP MongoDB counters
shared across instances: 300 requests/minute and 20 authentication attempts/minute.
The Vercel-supplied forwarding header is trusted only on Vercel. Personal responses
use `no-store`; raw database errors, request bodies and credentials are not logged.
Serialized workspaces, including merged imports, are capped at 4,000,000 UTF-8
bytes. Oversized writes roll back with HTTP 413, leaving headroom under Vercel's
4.5 MB payload limit.

Vercel Hobby permits personal, non-commercial use within free quotas. Exceeding
quotas can pause service; cold starts and service outages remain possible. Atlas
retains the existing restricted database user. The `0.0.0.0/0` entry permits
dynamic outbound IPs, still requiring authenticated TLS and private credentials.
No Marketplace replacement database or broader database role is required.

## Persistent Android signing

The release package remains `com.microplanner.microplanner`. Its certificate SHA-1:

```text
7D:77:B7:08:82:10:02:AD:DF:FA:CE:4D:26:E3:2E:F4:AB:6E:C4:EE
```

Register this package/certificate as a separate Android client in the existing
Google project, preserving the debug client. Android still uses the Web client ID
as `serverClientId`; the new Android client ID is not inserted into the app.

Local signing files live under `%USERPROFILE%\.microplanner\signing`, with a
protected local backup under `%USERPROFILE%\Documents\microplanner-signing-backup`.
Keep a further encrypted backup on another device or in a password manager.
Losing the signing identity prevents compatible updates to installed release APKs.
Do not regenerate the key between versions.

For local builds, the ignored `android/key.properties` contains `storeFile`
(absolute path with forward slashes), `storePassword`, `keyAlias`, and
`keyPassword`. Alternatively use `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. Release builds fail if these
are missing; debug builds do not require a release key.

Actions repository secrets use `ANDROID_KEYSTORE_BASE64` (base64 keystore),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
Store them directly as encrypted secrets. Never paste private values into chat,
PRs, release notes, logs or tracked files. Public fingerprints may be recorded.

## Publication sequence and recovery

1. A versioned PR merges. `Release version on merge` verifies it and creates an
   immutable annotated version tag at its actual merge commit.
2. `Publish Android APK` uses `workflow_run` on successful completion. This also
   works for the first implementation merge: the new workflow is then on `main`.
   It does not depend on a tag push from `GITHUB_TOKEN` triggering another workflow.
3. A read-only resolver verifies the originating workflow, associated merged PR,
   tag and main ancestry. The build checks out that exact merge SHA.
4. API, Flutter and release-safeguard tests pass before the key is restored. A
   pinned Flutter SDK builds the APK. Package/version/certificate/checksum are
   verified, and the temporary key is removed.
5. A separate write-permission job uploads APK/checksum to a draft, verifies both,
   then publishes a prerelease. Partial uploads remain drafts. Existing tags and
   different assets are never overwritten. An already published version is
   checksum-verified and skipped without rebuilding.

This runs for versioned merges, not every feature commit. PR checks use no
release secrets. A tag identifies source; a Release provides notes and downloads;
APK/checksum are assets. Actions artifacts are temporary hand-offs. Packages is
not needed for APK downloads. Public API URLs/client IDs are app configuration;
database and OAuth secrets stay on the server.

Rerun a failed publication. Alternatively, on `main`, run **Publish Android APK →
Run workflow** with an existing verified annotated tag. Never move a published
tag or replace its APK; publish a new version when the binary must change.
Keep `pubspec.yaml`, its increasing Android build number, and the server's
package/lockfile versions synchronized. Features are minor and fixes patch before
the explicit 1.0.0 maturity decision.

## Verification and icon generation

Run Flutter analysis/tests and Windows/Android release builds. In `server`, run
`npm run build` and `npm test`. Release safeguard tests run with
`python -m unittest discover -s scripts -p 'test_*.py'`. API tests use an isolated
replica set, including shared-instance limits, startup retry and oversized-import
rollback. Real Google login is additionally checked on Windows and Android.

Regenerate Android launcher PNGs/adaptive resources with Python/Pillow:
`python scripts/generate_android_icons.py`. They reuse
`assets/images/microplanner_logo.png`, matching Windows's existing ICO artwork,
with transparency and no added white background or decorative border. Android
may apply its launcher mask. Windows's icon remains unchanged.
