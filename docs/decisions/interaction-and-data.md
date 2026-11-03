# Interaction and data

Applies to navigation, forms and cloud state. Sources: approved plans
[0.5.0](../plans/plan-20261027T085951733Z-version0.5.0.md),
[0.6.0](../plans/plan-20261028T185419457Z-version0.6.0.md),
[0.9.0](../plans/plan-20261030T112258066Z-version0.9.0.md),
[0.10.0](../plans/plan-20261030T185610007Z-version0.10.0.md), and explicit user
refinements through validated 0.10.2. Later instructions below supersede older
plan choices (for example, restoring each board's column instead of Upcoming).

## Navigation and focus

- Remember the last board **per account and device**, and each board's last column.
  Restore on startup and board changes; retain the column on refresh. Upcoming is
  the fallback without history. Persist drag selections too, including immediately
  leaving Android, removing the app from recents and reopening it.
- Android supports precise snapping by swipe and a three-icon selector left of
  New Task (complete, warning, clock); both animate the same finite carousel.
  From Upcoming swipe right toward Late, then Completed; no loop. A sufficiently
  wide invisible left edge opens the sidebar **by inward drag only**, without
  requiring a system Back gesture. Keep the menu button and Android Back usable.
- Tap/click a task to edit on **both** platforms; no edit icon on task cards.
  Checkbox/delete and other nested actions must not also open the editor.
- Editing must not select/focus the title or open the Android keyboard by default.
  Opening date/time/selectors or expanded description clears stale text focus.
  Closing them must not restore focus or reopen the keyboard unexpectedly.
- Back from expanded description returns to Edit Task with its draft intact.
  Android Back first dismisses the keyboard when appropriate; a later Back follows
  the current dialog/navigation level. Test Back, Escape and dismissal paths.
- On Windows, Enter submits when Save is enabled unless editing description.
  Description Enter inserts a newline; Ctrl+Enter submits. This must still work
  after returning from a date/time picker. Save is disabled without changes.

## Actions, persistence and errors

- Accept create/edit/delete actions once, then close the form/confirmation
  immediately and show the floating sync notice. Permit navigation and independent
  actions. Prevent duplicate submissions and conflicting writes to a pending item.
  This supersedes the earlier rule of keeping a saving form locked open.
- Journal accepted pending actions securely per account/device; resume only with
  that account. Preserve failed drafts for review/safe retry. A timeout with an
  unknown outcome is not a confirmed failure; use idempotency and revision checks.
- Disable controls on a task only while its real operation is unresolved. Once it
  has arrived in the destination, controls work immediately even during its color
  fade; another move/delete starts smoothly from the current visual state.
- Offline mode shows the last account-scoped cache and prevents new edits. Startup
  sync happens while the logo is visible; do not flash a sync notice on first
  entering the board. Do not expose another account's data on sign-out/switch.
- Validate text and extreme values consistently in UI and API, using shared
  limits. Board names have a 50-character maximum. Preserve drafts on errors and
  keep valid actions enabled; refresh/resume must never consume a user's click.
- Clear Completed Tasks deletes only completed tasks on the current board, after
  confirming the count and board name. Its discreet bin is left of the counter;
  on Windows show it only while hovering that green header.

## Task transition contract

- Destination colors: Completed green, Late yellow, Upcoming blue; deletion red.
  All paths, including deadline edits, refresh/startup reclassification and bulk
  changes, need origin/destination detail without moving the user's viewport.
- For column moves, color the origin for at least **1 second**, then keep its
  animated colored haze until the write is confirmed and sync is finished. Only
  then transfer. The destination holds full color **1.5 seconds** and fades to its
  normal surface over **1 second** (2.5 seconds total), even on a fast response.
- Creation/deletion have a **2.5-second minimum from the original action** in
  their single column, also awaiting confirmed synchronization when necessary.
  No additional destination timer for these actions. Creation appears pending
  immediately; deletion remains visually pending until it can disappear safely.
- Completion strikes animate left to right; uncompletion reverses them. Source
  completion strike is black; destination uses its normal muted appearance without
  a sudden end-of-animation color change. Keep the colored haze alive on slow sync.
- Independent transitions can overlap. Confirmed failures restore original state
  with inverse motion; late responses, old timers, account switches or new actions
  must not overwrite newer state. Check chains during the destination fade.

## Board customization and account pages

Source: [approved 0.11.0 plan](../plans/plan-20261102T143728008Z-version0.11.0.md).

- Weekly Plan is a Coming Soon destination before collapsible Boards. Profile
  contains only Google photo/name/email, Settings and Sign out. Settings contains
  only Customization > Boards > Default lists of task types; no extra placeholders.
- Back and Escape unwind Settings one level at a time, then Profile, then the
  previous board. Sidebar navigation must not leave stale back-history entries.
- Boards and task types share the icon catalog; boards and subjects share the
  existing subject palette. A selected board color adds only a very pale board
  background; it does not replace the application or column colors.
- Subjects and types are ordered, editable board-local lists, limited to 25 each.
  Names are trimmed, nonempty and at most 50 characters. Preserve longer existing
  names and over-limit legacy subject lists; unrelated edits never truncate them.
- Applying a default list makes an independent copy. Match existing type names
  ignoring case/outer whitespace only when unambiguous; confirm the number of
  assignments that will be cleared. Removing/reordering categories must not
  silently lose or reassign task associations.
- The five editable initial lists are Academic tasks, Software development, Work,
  Personal life and Creative projects. Editing/deleting a default never changes
  boards that previously copied it. Preserve the unassigned No type choice.
