# Verification and installed builds

Read before tests, builds or UI delivery. Source: the user's repeated real-device
verification instructions, Windows taskbar/update preference, approved test board,
and 2026-11-02 cross-chat consolidation request. These are required development
practices, not optional examples.

## Evidence and data safety

- For UI work, inspect and interact with the actual Windows app using computer
  use and the physical Android app using ADB. Tests/build success alone does not
  establish visual quality. Read visual and interaction decisions first.
- Update the user's **normal installation**, retaining the real account, session
  and data. Use the cloud board **Prueba Desarrollo**, kept last, for varied test
  tasks. Preserve personal boards/tasks/order. Leave the updated normal app
  installed and available for the user's own checks before merge.
- Do not substitute another executable/package, a fictitious-account preview or
  a temporary app that is later removed, leaving the normal installation stale.
  Isolated fixtures are appropriate for automated tests, not this final UI check.
- Check for unsaved user drafts before restarting/installing. Ask the user to
  save/cancel those when necessary; never discard their draft to run a build.
- Report actual checks and limitations honestly. Ask for device connection/unlock
  early when needed, using an asynchronous interactive question while continuing
  independent work. Perform the available checks yourself; request manual testing
  only for a real tool limitation, personal preference or requested user validation.
- For form layout changes, inventory every affected form and measure the complete
  gap from its last visible content to its buttons, including hidden message
  reservations and accumulated padding. Check compact/large layouts, keyboard
  and error states, plus actual installations on both platforms. Passing margin
  assertions or inspecting isolated footers does not establish visual quality.

## Windows

- Build from the repository root: `flutter build windows --release`. Keep the
  complete bundle (EXE, DLLs, data) at `build/windows/x64/runner/Release/`; the
  taskbar shortcut targets `microplanner.exe` there. Open this exact executable.
- Before overwriting, verify microplanner process identity/path. The user permits
  terminating those processes from the terminal; preserve drafts/data first.
  Reopen the canonical executable after updating if it was running beforehand.
- Use the available Windows computer-use skill. Discover/select the actual
  microplanner window, take a fresh screenshot, act and inspect the result. If
  screenshots show another foreground app, reselect instead of clicking blindly.
  If native control fails, diagnose that specific connector and report the limit;
  do not silently replace real UI inspection with widget tests.
- Check normal size and the minimum window: half the current monitor width and
  height. Inspect hover, keyboard, dialogs, card spacing and overflow.

## Physical Android through ADB

- Use the existing Android SDK `platform-tools/adb.exe` (normally
  `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`). Run `adb devices -l`
  and explicitly target the discovered authorized Redmi with `-s <serial>`.
  Do not assume a stale serial or act on another device. USB debugging must be
  authorized and the phone unlocked; ask only when user intervention is needed.
- Build with the **existing persistent release signing identity**:
  `flutter build apk --release`. Keep ignored signing configuration private.
  Verify package/version/certificate with `scripts/android_release.py verify-apk`
  (see [release guide](../cloud-and-releases.md)). Package:
  `com.microplanner.microplanner`. Never regenerate its signing key for a test.
- Install in place with `adb -s <serial> install -r
  build/app/outputs/flutter-apk/app-release.apk`. Never uninstall, clear app data,
  or change application ID/signature as a shortcut; stop and resolve a mismatch.
- Launch the installed app, capture the real display with `adb shell screencap`
  and pull the PNG; inspect it with the image tool. Use `adb shell input tap`,
  `swipe` and `keyevent` for actions, with fresh screenshots after each meaningful
  state. Use original screenshot dimensions for coordinates. Keep screenshots and
  UI dumps in ignored local evidence, not in published files with account data.
- Do not route through Tango/WebUSB or reinstall screen-control tools: direct ADB
  is the working method. USB is for control; the normal app uses the hosted API.
- Verify changed flows plus keyboard open/closed, picker return, Android Back,
  dismissal, small layouts and independent pending actions when relevant.

## Automated checks and efficiency

- Test observable behavior and regressions, including failure, race/ordering and
  boundary cases. Avoid tests that merely mirror code or inflate coverage for
  trivial reversible changes. Widget tests use isolated fixtures; API tests use
  their isolated replica set, never the user's production records.
- Use `flutter analyze`, targeted/full `flutter test` as warranted; for API changes
  run `npm run build` and `npm test` in `server/`. Release-script changes use
  `python -m unittest discover -s scripts -p 'test_*.py'`. Match checks to scope;
  documentation-only work does not require rebuilding both apps.
- Start tests and the waiting build in parallel; cancel that build promptly if
  tests fail. Parallelize independent reads/checks but respect tool locks and
  shared outputs. Do not duplicate builds or repeat passing checks without cause.
- For motion changes, inspect a recording/real interaction and measure relevant
  performance; preserve reduced-motion behavior. Record evidence and limitations
  in the active plan or ignored local log, not in the PR's user-facing description.
