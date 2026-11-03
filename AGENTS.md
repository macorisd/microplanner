# Repository conventions

## Shared project decisions

Use the active `md-method` skill for every requested change. Read
[docs/decisions/README.md](docs/decisions/README.md) at the start of every
task, then the topic documents relevant to its scope before planning, changing
or verifying anything. UI work requires the visual, interaction and verification
topics, including real Windows computer use and physical Android ADB checks.
Update these versioned decisions in the same task when the user changes or asks
to save a standing convention. The local context log is not the shared rulebook.
Plans live in `docs/plans/`; preserve their history and approval metadata.

## General rules

- Use the `md-method` skill for every requested change to microplanner.
- Continue authorized work until the requested result is complete. Do not stop
  simply because the task is large, time has passed, or an intermediate step
  is done. Pause only for a real blocker, an explicit user request, or a
  required decision or approval; explain the reason and resume when resolved.
- Always spell the product name `microplanner` in lowercase in UI text,
  documentation, pull requests, and conversation. Use ordinary language naming
  conventions for identifiers that do not contain the product name.
- Write repository content in English, including documentation, comments,
  user-facing text, commit messages, and pull request titles and bodies.
- Use descriptive branch names such as `feature/google-auth-mongodb` or
  `fix/session-restore`. Branch names and pull request text, including hidden
  release metadata, must not mention the development methodology or its tools.
- Before version `1.0.0`, new features increment the minor version and bug fixes
  increment the patch version. Do not introduce a major version before the user
  explicitly decides the application is ready for `1.0.0`.
- Keep credentials in ignored local configuration. Never commit, print, or
  package database credentials, OAuth secrets, or session tokens.
- Preserve user data when rebuilding or updating the application.
- PR descriptions contain only `## Changes`, with subsections for the change
  types present in the PR: `### Major`, `### Minor` and `### Patch`, in that
  order. Omit sections without changes. Use one concise, user-facing bullet per
  requested change; retain required hidden release metadata.
- Delete residual branches belonging to merged PRs when convenient during
  tests/builds, after verifying they contain no unpublished work. Preserve main,
  active worktrees and unmerged branches.

## Windows build workflow

- Build local Windows releases from the repository root with
  `flutter build windows --release`.
- Always leave the complete runnable bundle in
  `build/windows/x64/runner/Release/`, with `microplanner.exe`, its DLLs and its
  `data/` directory together. The Windows taskbar shortcut targets this executable.
- Use this canonical executable when opening the rebuilt application. Any
  additional build copies must not replace it as the user's normal launch target.
- Check for running instances before updating the bundle. The user explicitly
  authorizes terminating microplanner from the terminal when a rebuild requires
  it to close. Scope termination to verified microplanner processes; preserve
  application data and reopen the canonical executable after the update.
- After a successful update, reopen the canonical executable if the application
  was running before the update. Preserve local data and sign-in state.

## Android device verification

- When a change needs verification on a physical Android phone, tell the user
  during the work as soon as that need is apparent, before delivering or
  publishing the change. Use ADB to perform the verification yourself whenever
  the device is available; do not ask the user to perform tests that can be
  done through ADB. Request the user's help only when their intervention is
  actually needed, and respect their decision if they prefer not to test.

## GitHub publication handoff

- After publishing changes and starting Android APK generation, do not keep the
  chat turn open just to wait for that build. Once implementation and requested
  local/device verification are complete, finish the response and state that
  APK generation continues in GitHub Actions. Provide its link when available.
- Inspect that background publication later when the user asks or reports a
  failure; do not add an automatic waiting or polling loop to the delivery.

## Visual regression data

- The user authorizes a cloud board named `Prueba Desarrollo`, placed last, for
  testing tasks with varied titles, subjects, types, priorities and states.
- Reuse this board for future UI checks. Keep its test records separate from
  the user's other boards and preserve the user's own data and board order.
