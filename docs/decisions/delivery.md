# Repository and delivery

Applies when editing shared content or publishing. Source: the user's naming,
pre-1.0 versioning, PR-format, branch-cleanup and publication instructions,
consolidated 2026-11-02. Detailed setup lives in
[Development](../development.md) and [Cloud and releases](../cloud-and-releases.md).

- Always write **microplanner** in lowercase in UI, docs, PRs and conversation.
  Repository text (including UI, comments, documentation, commits and PRs) is
  English. Conversations with this user can remain Spanish.
- Use descriptive branches such as `feature/google-auth-mongodb` or
  `fix/session-restore`. Branch names, PR titles/bodies and hidden release metadata
  must not mention the development methodology or its tools.
- Before 1.0.0, features increment minor and fixes patch. No major release until
  the user explicitly decides the app is ready. Synchronize product version
  manifests and increasing Android build numbers when releasing app changes.
  Corrections and refinements of existing controls (keyboard, focus, visual
  consistency or removing redundant confirmation steps) are patches. Scope,
  implementation effort and the number of fixes do not make them minor; minor
  requires a new product capability. Respect the user's explicit classification.
  Source: user clarification, 2026-11-04.
- PR bodies contain only `## Changes`, then nonempty `### Major`, `### Minor`,
  `### Patch` subsections in that order. One concise, user-facing bullet per
  requested change, classified individually. Omit absent categories and retain
  required hidden release metadata. Keep test logs elsewhere.
- Plans live in `docs/plans/`; standing decisions live in `docs/decisions/`.
  Preserve plan IDs, approvals and historical answers. Record important new design
  choices in the plan before implementing; ask the user when an unresolved choice
  materially affects them. Do not ask again about an existing accepted decision.
- Preserve unrelated work and active worktrees. Before publication (or during
  build waits), remove branches from merged PRs only after verifying merge status,
  no unpublished work, and no active worktree. Keep main and unmerged/uncertain
  branches. Never merge the user's PR just because implementation is complete.
- Starting with PR 17, successful Android release publication removes the merged
  PR's remote source branch only after checks, APK publication and README update
  have succeeded. Verify the release/merged PR association and unchanged head;
  preserve protected branches, reused branches with open PRs and newer commits.
  Failed or canceled publication retains its branch for recovery. This does not
  remove a local checkout. Source: explicit user request, 2026-11-04.
- Keep credentials in ignored local/server configuration. Never print, commit or
  package database/OAuth/session secrets or signing keys. The API owns MongoDB
  access, validates identity and isolates every account; clients never get DB
  credentials. Preserve per-account cache and secure pending operations.
- The normal API is hosted on Vercel with Atlas. Local API/USB port forwarding
  are explicit development overrides; do not make normal builds depend on them.
- Application checks run once per PR update, plus pushes to main. Versioned merges
  create immutable tags; Android publication verifies and publishes signed APKs
  as prereleases, then updates managed README download/history links. Keep those
  markers intact; never move published tags or replace a different APK asset.
- Leave verified Windows/Android builds installed for the user. After publishing,
  **do not keep the chat open only to wait for GitHub's APK build**. Deliver the
  PR/action link and say generation continues. Inspect later if the user asks or
  reports a failure; do not add a background polling loop.
- Before pushing a pull request branch or updating an open pull request with a
  runnable-app change, install that PR version on both Windows and the physical
  Android device, preserving the user's account, session and data. The user
  tests these normal installations before approving the merge; neither platform
  may be left on an older build.

README remains user-oriented: icon banner, a brief natural explanation, Windows/
Android installation, a version table with change lists, and minimal developer
setup in a final collapsible section. Banner tagline:
**A minimalist space for everything you need to do.**
