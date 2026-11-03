# Project decisions

This is the shared contract for microplanner across chats. Read this index at the
start of every task, then read the relevant topics **before** planning, coding or
testing. A local chat log is not a substitute. These are accepted requirements,
not a claim that every current screen already complies.

| Document | Read when changing or checking |
| --- | --- |
| [Visual design](visual-design.md) | Any visible component, layout, icon, color, form or animation. |
| [Interaction and data](interaction-and-data.md) | Navigation, focus, keyboard, forms, task actions, persistence or synchronization. |
| [Verification](verification.md) | Tests, builds, UI changes or installing and checking either platform. |
| [Delivery](delivery.md) | Repository content, branches, PRs, versions, releases or credentials. |

For UI work, read the first three topics; delivery rules apply when publishing.
A server-only fix can skip visual layout rules. Read the active plan in
[docs/plans](../plans/); older plans are evidence, not the current rulebook.

## Keep this useful

- Update the relevant topic in the same task when the user asks to remember a
  practice, changes a standing decision, or approves a durable design decision.
  Record its scope and source; add a topic only when an existing one cannot fit.
- Keep only current rules here. Replace superseded rules; leave historical
  questions, answers and delivery notes in their original plans. Do not copy
  implementation details, test logs or secrets into these documents.
- An explicit current user instruction takes precedence. A temporary exception
  applies only to its stated scope. Clarify an unresolved important conflict;
  do not silently discard a standing convention or ask again about settled ones.
- Newly observed behavior is not automatically an approved design. Before a PR,
  check the relevant rules, record actual verification and update affected links.
- Local `.agents/skills/.local/md-method/context.md` is an operational journal;
  this directory is the versioned source of standing project decisions.

Initial consolidation: 2026-11-02, from the user's instructions and approved plans
through 0.10.0, plus the validated 0.10.2 refinements. The approved
[0.11.0 customization decisions](../plans/plan-20261102T143728008Z-version0.11.0.md)
are included in the relevant topics. Verification evidence belongs in the plan.
After updating an older worktree, align its ignored local `plansPath` with
`docs/plans`; do not recreate a root-level plans directory or modify another
active worktree's private configuration.
