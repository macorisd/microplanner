# Interaction and data

Applies to navigation, forms and cloud state. Sources: approved plans
[0.5.0](../plans/plan-20261027T085951733Z-version0.5.0.md),
[0.6.0](../plans/plan-20261028T185419457Z-version0.6.0.md),
[0.9.0](../plans/plan-20261030T112258066Z-version0.9.0.md),
[0.10.0](../plans/plan-20261030T185610007Z-version0.10.0.md), and explicit user
refinements audited through [PR #19](https://github.com/macorisd/microplanner/pull/19)
on 2026-11-05. Later instructions below supersede older
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
- After a newly created task is durably accepted, reveal its destination column
  on Android and animate its task column vertically to the new card on Windows
  and Android. Aim for the viewport center using a short visible scroll rather
  than an instant jump. Do not scroll when the list has no excess extent; near
  the beginning or end, stop at the reachable minimum or maximum scroll offset
  instead of forcing the card to the center. This applies only to task creation,
  not editing an existing task, refresh, restore or other list changes. Keep the
  creation color feedback visible during synchronization and honor reduced
  motion. Source: explicit user requirement, 2026-11-09.
- Tapping/clicking the open board heading opens its existing Edit Board dialog;
  the heading's hover/focus Delete action opens the same confirmation as sidebar
  deletion and must not also open the editor. Source: user refinement, 2026-11-04.
- Sidebar Edit/Delete actions must not also select their board. Keep name/row
  selection separate from nested actions, including disabled targets. Source:
  [PR #15](https://github.com/macorisd/microplanner/pull/15) and the PR #19 correction.
- Editing must not select/focus the title or open the Android keyboard by default.
  Opening date/time/selectors or expanded description clears stale text focus.
  Closing them must not restore focus or reopen the keyboard unexpectedly.
- Android text fields request sentence capitalization (including names and
  descriptions) without rewriting entered text; date/numeric keyboards keep their
  appropriate input modes. Apply this through the shared text-field component.
- Every creation form with a name (tasks, boards, subjects, task types and default
  lists, including reviewed failed creation drafts) focuses Name on opening.
  A pristine empty field shows no error; leaving it empty after focus or clearing
  its contents shows "Please enter a name." and keeps Save/Create disabled.
  Edit forms do not focus Name automatically. Source: user refinement, 2026-11-05.
- Save in an edit form is enabled only for a valid change; reverting all changes
  disables it again. Invalid or unchanged saves must not enqueue redundant writes.
  Source: [PR #15](https://github.com/macorisd/microplanner/pull/15).
- Repeated taps/keys must not open duplicate instances of the same dialog or
  picker, including nested editors, or close/submit a route twice. Keep distinct
  nested routes usable. Source: PR #15's approved interaction refinements.
- Back from expanded description returns to Edit Task with its draft intact.
  Android Back first dismisses the keyboard when appropriate; a later Back follows
  the current dialog/navigation level. Test Back, Escape and dismissal paths.
- Enter (including numeric-keypad Enter) activates the enabled save/create action
  in every editable form, including board, subject, task type and default-list
  editors, even with focus outside its text fields or after a picker returns.
  Preserve description newlines; Ctrl+Enter submits descriptions on Windows.
  Disabled, unchanged, invalid or pending forms never submit; nested dialogs
  handle their own keys without submitting an underlying form.
- Sign-in has no in-app Cancel button. A failed attempt returns to the sign-in
  screen with "Sign in with Google" available again. Preserve the existing
  account/session safety and the provider's own dismissal behavior. Source:
  explicit user refinement, 2026-11-06.
- Selecting a calendar day immediately accepts it and returns to the task draft;
  selecting clock minutes does the same for time. Hour selection advances to
  minutes; dial dragging accepts only on release. Omit OK in both selectors.
  Keep validated manual entry with Apply/Enter, date bounds, precise minutes,
  12/24-hour handling, Cancel and Back/Escape. Picker completion never saves the
  task or restores stale text focus. Source: user correction, 2026-11-04.
- Date pickers use fixed internal bounds from 1900-01-01 through 2999-12-31.
  Opening an older legacy deadline clamps only the picker's initial selection;
  cancellation and unrelated edits preserve saved data. Do not expose numeric
  bounds in validation messages. For dates below the range, use "A bit odd to
  plan something before you were born, isn't it?" For dates above it, use "Trust
  me, you won't have to worry about this task by then." Show either message only
  after complete date entry, as specified below. Source: user refinement in
  [PR #17](https://github.com/macorisd/microplanner/pull/17), 2026-11-04.
- Manual dates accept ASCII digits only and insert slashes after the day and
  month (`dd/MM/yyyy`). Until all eight digits are present, show no validation
  message and keep Apply/Enter disabled. Time inputs also ignore everything
  except ASCII digits. Source: user refinement, 2026-11-04.
- Clock selection visibly animates the needle to the chosen hour/minute before
  advancing or accepting. Keep this brief, preserve precise minute selection,
  cancellation and duplicate-input guards, and honor reduced motion.
  Source: user refinement, 2026-11-04.

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
- While a board creation/save is unresolved, disable that board's Edit/Delete
  controls in the sidebar and open heading. Other boards and navigation remain
  available; confirmation or a definite failure releases the pending state.
  Include saves that change only subjects or task types. Newly accepted boards
  appear in the sidebar immediately. Source: user refinement, 2026-11-05.
  Disabled Edit/Delete targets consume clicks without selecting/opening the board;
  its name area still selects it. Source: user correction, 2026-11-05.
- Offline mode shows the last account-scoped cache and prevents new edits. Startup
  sync happens while the logo is visible; do not flash a sync notice on first
  entering the board. Do not expose another account's data on sign-out/switch.
- Validate text and extreme values consistently in UI and API, using shared
  limits. Board names have a 50-character maximum. Preserve drafts on errors and
  keep valid actions enabled; refresh/resume must never consume a user's click.
- "Delete Completed tasks" replaces the former "Clear Completed Tasks" label.
  Its confirmation uses "Cancel" and "Delete" with the shared rounded/fixed-footer
  conventions. Source: user refinement, 2026-11-06.
  It deletes only completed tasks on the current board, after
  confirming the count and board name. Its discreet bin is left of the counter;
  on Windows show it only while hovering that green header.

## Task transition contract

- Destination colors: Completed green, Late yellow, Upcoming blue; deletion red.
  Column moves from any path, including deadline edits, refresh/startup
  reclassification and bulk changes, need origin/destination detail without
  moving the user's viewport.
- For column moves, color the origin for at least **1 second**, then keep its
  animated colored haze until the write is confirmed and sync is finished. Only
  then transfer. The destination holds full color **1.5 seconds** and fades to its
  normal surface over **1 second** (2.5 seconds total), even on a fast response.
- Creation, deletion and edits that stay in the same board/column show feedback
  only while their own real operation is unresolved. End it on confirmation or
  definite failure, without a minimum duration or a destination hold/fade;
  unrelated pending writes must not prolong it. Creation appears pending
  immediately; deletion remains present until confirmed, and failure restores
  the confirmed state. Source: [PR #14](https://github.com/macorisd/microplanner/pull/14)
  (0.10.3), which supersedes PR #13's earlier standalone minimum duration.
- Completion strikes animate left to right; uncompletion reverses them. Source
  completion strike is black; destination uses its normal muted appearance without
  a sudden end-of-animation color change. Keep the colored haze alive on slow sync.
- Independent transitions can overlap. Failed column moves restore original state
  with inverse motion; standalone actions end their pending feedback as above.
  Late responses, old timers, account switches or new actions must not overwrite
  newer state. Check chains during the destination fade.

## Board customization and account pages

Source: [approved 0.11.0 plan](../plans/plan-20261102T143728008Z-version0.11.0.md).

- Weekly Plan is a Coming Soon destination before collapsible Boards. Profile
  contains only Google photo/name/email, Settings and Sign out. Settings contains
  Customization > Boards > Default lists of task types and its sibling
  Notifications destination; no extra placeholders.
- Back and Escape unwind Settings one level at a time, then Profile, then the
  previous board. Sidebar navigation must not leave stale back-history entries.
- Boards and task types share the icon catalog; boards and subjects share the
  existing subject palette. Board colors identify sidebar rows and the open
  board heading; keep the task area neutral and preserve column colors.
- Subjects and types are ordered, editable board-local lists, limited to 25 each.
  Names are trimmed, nonempty and at most 50 characters. Preserve longer existing
  names and over-limit legacy subject lists; unrelated edits never truncate them.
- New boards start with no subjects and the six types Homework, Test,
  Presentation, Project, Reading and Other. No type remains an unassigned choice,
  not a removable entry. Explain the 25-item limit when an addition is attempted
  beyond it, rather than showing a permanent warning. Source: the approved
  0.11.0 plan, B02, and [PR #15](https://github.com/macorisd/microplanner/pull/15).
- Preserve board order through subsequent queued edits, refresh and cache restore;
  reordering retains board IDs. Show the accepted order immediately after a drop,
  throughout synchronization and on confirmation, without reverting to the old
  order while waiting. A definite failure restores the confirmed order.
  After any board reorder is accepted, disable every board drag until that order
  write resolves. A second reorder must not enqueue, alter the visible order or
  wait behind the first; confirmation or definite failure unlocks dragging.
  This does not disable board Edit/Delete controls or navigation.
  While any board creation/editor save shows pending synchronization, disable
  reordering all sidebar boards; keep board navigation available. Re-enable
  dragging when those saves resolve, including definite failure. This includes
  category-only saves, but task writes alone do not block board reordering.
  Source: user correction, 2026-11-06.
  Windows board rows can be dragged immediately;
  Android rows require a long press, while ordinary swipes scroll without
  reordering. Source: PR #15's ordering and touch refinements.
- Dragged boards, subjects and task types stay visually inside their own visible
  list region, including inside a scrolled form. They cannot cover form headings,
  other category sections or footer actions. Keep first/last drop positions
  reachable, preserve IDs and show complete rounded rows throughout the drag.
- Board names are unique within an account. Subject and task type names are unique
  within their board; task types are also unique within each default list.
  Compare names ignoring case and outer whitespace, irrespective of color/icon.
  Enforce creation and renaming in forms, queued/rebased writes and the API.
  Preserve existing duplicates and assignments on unrelated edits; allow users
  to resolve them without silently deleting or renaming their data.
  Source: explicit user decision, 2026-11-05.
- Subjects/task types are reordered by dragging their handles; omit redundant
  three-dot Move up/Move down menus, including in default-list editors.
- The Board's configured Subject order is authoritative in every task form.
  Create Task, Edit Task and recovered task drafts show the same Subject order
  as Edit Board and the task card.
- Subject/type drag handles have a full 48-pixel square hit area. On Android,
  dragging the handle starts immediately; the name area requires a long press,
  as with sidebar boards. Neither gesture shows an Edit/name tooltip or opens
  the editor. Normal name taps still edit; Windows handle behavior and desktop
  hover tooltips remain unchanged. Source: user refinement, 2026-11-05.
- Applying a default list makes an independent copy. Match existing type names
  ignoring case/outer whitespace only when unambiguous; confirm the number of
  assignments that will be cleared. Removing/reordering categories must not
  silently lose or reassign task associations.
- Removing/replacing subjects or types preserves the tasks themselves. Before
  saving destructive category changes, confirm how many task assignments will
  be cleared; canceling leaves saved categories and associations intact. Source:
  the approved 0.11.0 plan, B02/Q04, and PR #15.
- The five editable initial lists are Academic tasks, Software development, Work,
  Personal life and Creative projects. Editing/deleting a default never changes
  boards that previously copied it. Preserve the unassigned No type choice.

## Deadline notifications

Source: approved [0.12.0 plan](../plans/plan-20261113T095259660Z-version0.12.0.md),
2026-11-13. Reminders cover incomplete tasks on every board. The synchronized
default is 24 hours before, with an optional deadline reminder initially off.
Tasks inherit the current default, disable both reminders, or override the
advance (1-10,080 whole minutes). Completing/deleting/editing cancels obsolete
events; unresolved relevant writes suppress them until the outcome is known.
No periodic overdue reminders. Catch up once while the deadline is still ahead;
batch simultaneous catch-up and avoid duplicates after refresh/restart.

Activation is opt-in per account/device, initially off. Quiet hours and content
privacy are device/account preferences; quiet hours are initially off with a
22:00-08:00 suggestion. Delay advance reminders to the next allowed time only
before their deadline; skip deadline events in quiet hours. Generic content hides
task details. Sound/vibration/banners and Do Not Disturb belong to system settings.
Show permission/timing/setup/partial-coverage state and offer a sample notification.
Page controls persist immediately; custom-duration editors use ordinary save rules.
Notification deadline text uses "today" and "tomorrow" for those local calendar
days, retaining the time; other dates retain the abbreviated weekday/day/month.
Resolve relative dates for the notification's delivery time, including scheduled
events while the app is closed. Source: user refinement, 2026-11-13.
On Android, guide activation to precise reminder access when it is missing.
Explicitly state that inexact alarms can be delayed up to an hour and can miss a
short deadline. Closing/removing the app from recents must not require Flutter to
stay running; verify a future OS alarm with the process closed, not only an
immediate notification or activation of an already displayed one.

Use local OS scheduling with last synchronized data, including closed-app/offline
delivery where the OS allows it. Cross-device edits apply on the next sync;
each enabled device can notify. Preserve UTC deadline instants. Show scheduling
capacity/session coverage honestly. Cancel old-account schedules on sign-out and
reject stale callbacks. Clicking reveals the current task after login/data restore
without changing it, losing an unsaved draft or bypassing account isolation.

The user authorizes changing Windows distribution if necessary after evaluating
compatibility, installation and maintenance. Prefer preserving the normal bundle
when native integration works; closing the app must still exit the process.
