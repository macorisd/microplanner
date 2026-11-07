# Visual design

Applies to visible UI on Windows and Android. Source: user-approved plans
[0.3.0](../plans/plan-20261025T115132337Z-version0.3.0.md),
[0.4.0](../plans/plan-20261025T191235062Z-version0.4.0.md),
[0.5.0](../plans/plan-20261027T085951733Z-version0.5.0.md),
[0.10.0](../plans/plan-20261030T185610007Z-version0.10.0.md), and subsequent explicit
user refinements (initial consolidation 2026-11-02; audited against
[PR #13](https://github.com/macorisd/microplanner/pull/13) through
[PR #19](https://github.com/macorisd/microplanner/pull/19) on 2026-11-05).

## Palette and components

- Keep the existing colors. Material 3/Material You informs shapes, controls and
  motion; system wallpaper colors must not replace the approved palette.
- Reuse [AppColors](../../lib/core/theme/app_colors.dart) and
  [AppTheme](../../lib/core/theme/app_theme.dart). Reference colors: background
  `#F5F5F7`, cards `#FFFFFF`, primary `#6FA89F`; Completed `#8DD4A0`, Late
  `#F5D68A`, Upcoming `#8BB8E8`. Do not invent a parallel theme for a new screen.
- Use the shared spacing scale (4/8/16/24/32 logical pixels) and radius tokens
  (8/12/16/20/24). Match neighboring controls in size, alignment and emphasis.
  Keep the soft, minimal, rounded style and readable contrast in every state.
- New settings, account views and controls must follow the same visual language
  as the existing task forms/sidebar. A new feature is not a separate redesign.
- Cancel actions are red consistently. Destructive actions and confirmations must
  remain distinguishable; subdued controls must still be readable.
- Use Subject's rounded downward chevron for selectors throughout the app;
  direction disclosures rotate the same shape. Deadline and Time use its same
  secondary text color, and both show a trailing chevron on Windows and Android.
  Source: user refinement, 2026-11-04.

## Forms and cards

- Form action standardization, user decision 2026-11-06, applies on Windows and
  Android and to future forms. Creation forms use "Cancel" and "Create X";
  editing forms use "Cancel" and "Save changes"; deletion confirmations use
  "Cancel" and "Delete". All form buttons use rounded rectangles with radius 12,
  replacing the previously approved capsules, including date/time actions.
  Keep destructive actions
  distinguishable and retain the existing red Cancel text.
- These forms always have a white footer outside the scrolling content, including
  short forms and small screens. Windows uses balanced footer padding of 12
  (8 in compact windows); Android uses 16 consistently, matching Edit Board.
  Increase footer height when needed. Measure the visible button
  surface: the bottom gap below the rightmost proceed button must equal its right
  gap to the dialog edge, not merely the padding of an invisible touch box.
  Keep actions visible above the keyboard. Cancel's
  pressed/hover/focus surface must match the proceed button's rounded shape,
  height and vertical alignment; without a proceed action, use a standard-sized
  rounded button. Keep Cancel compact, with less horizontal padding than the
  proceed action and a consistent 8-pixel gap between button surfaces. Standard
  visual minimum height is 40 logical pixels, growing with enlarged text; touch
  controls retain at least a 48-pixel target. Apply coherent spacing across the
  app and prioritize balanced, aligned layouts over preserving an old footer
  height. Source: user explicitly replaced capsules and required equal visible
  bottom/right margins on 2026-11-06.
- Use each platform's shared footer margins in every form and picker. Android's
  Edit Board is the approved reference; remove the Edit Task-only exception and
  inconsistent picker margins. Source: user consistency correction, 2026-11-06.
- Judge spacing across the complete form, from the final visible control to the
  action surfaces, including reserved validation/save-error rows and nested
  padding. Do not stack blank status rows, spacers or expanded areas into a large
  empty band. Keep a modest separation, typically no more than 48 logical pixels
  at normal text size including one necessary message slot; enlarged text may
  grow as needed. Reserve only the message space actually needed and keep errors
  readable without resizing the form or moving its controls. Review healthy and
  error states across all affected forms and both platforms; checking a footer's
  padding or a few representative screenshots alone is insufficient. Source:
  user screenshot review and requested general lesson, 2026-11-06.
- Preserve all current date/time picker modes and expanded description. Date/time
  actions use the shared shape, compact Cancel and balanced margins, matching
  Apply's height/alignment when present. Manual entry also follows the compact
  content-to-action spacing rule above, with only necessary validation space.
  Preserve calendar/dial geometry, footer placement, acceptance and behavior.
  Expanded description stays unchanged. Reduce
  the excess footer margin in Choose an icon. Apply a default list gets a standard
  right-aligned Cancel button in its footer instead of a full-width list option.
  Source: user exceptions, 2026-11-06.
- Recovery drafts follow their original create/edit operation and use the same
  labels, rounded actions and fixed footer as the corresponding form. Save list
  changes uses "Cancel" / "Save changes"; discarding a saved draft uses "Cancel"
  / red "Discard"; importing local data uses "Cancel" / "Import". Actions needing
  attention retains per-operation "Review draft", "Retry" and "Discard" buttons
  beside each operation, with "Close" in the fixed footer and local-storage repair
  only when relevant. Limit messages use a single right-aligned "OK" button.
  All these dialogs share the balanced fixed-footer margins. Source: user approved
  the exceptional-dialog proposal, 2026-11-06.
- Task creation and editing forms place Task type immediately after Subject and
  before Deadline and Time on Windows and Android. Source: user refinement,
  2026-11-05.
- Validation and save-error messages must not change form/dialog height or move
  its controls. Reserve stable message space in shared fields and status areas;
  preserve complete messages through scrolling and accessibility on narrow screens.
  Source: user correction, 2026-11-04.
- Board forms keep compact vertical spacing: no extra gap after the name's
  reserved message row, no divider between Subjects and Task types, and a compact
  stable save-error slot in Edit Board's scrolling content. New Board shares its
  fixed name message row with save failures instead of reserving a second status area.
  Source: user spacing review, 2026-11-04.
- Align adjacent icons and punctuation with the text input's filled surface,
  excluding its reserved validation area. Date/time mode switches, Cancel and
  Apply share a vertically centered footer row aligned to the right edge; wrap
  only when space requires it.
  Source: user screenshot review, 2026-11-04.
- Edit Board keeps Cancel and Save changes in a white footer outside its
  scrolling content, visible at every scroll position and above the keyboard.
  Center the buttons vertically with the balanced shared footer padding; keep the
  stable save-error row in the scrolling content and reveal it when an error occurs.
  Subject forms omit extra spacing after Name's reserved validation row before
  Color. Source: user refinement, 2026-11-05.
- Expanded description is a dialog with the **same size and shape** as its task
  form, a back button, the noneditable task title and description field. Keep
  unsaved content. Its expand control is compact, uses matching colors and aligns
  with adjacent fields such as Subject; it is not an oversized separate action.
- Description scrollbars must remain clear of the entered text and its selection,
  including in the expanded editor; reserve space instead of painting the thumb
  over text. Source: [PR #14](https://github.com/macorisd/microplanner/pull/14).
- Keep task cards compact on Windows and Android. Android uses an 8 logical-pixel
  inset between the column's inner edge and its cards, plus an 8-pixel vertical
  gap between cards. Windows uses 10 pixels for both outer margins. Both platforms
  use 12 logical-pixel padding inside each card around the title, date and
  priority controls. Keep bottom spacing comparable to side spacing, no blank
  subject row and no extra title/date gap when Subject is absent. Align the
  checkbox with the date's left edge. Priority has breathing room after the title
  and aligns vertically with the delete icon. Source: user preference and
  Windows-only refinement, 2026-11-07.
- Subject chips hug their text, including on Windows. Show the subject color in
  the task form selector. Hover/focus effects must not create oversized checkbox
  circles or leave highlights on multiple sidebar boards.
- Android column headers keep their colors even when empty; Windows empty
  headers remain gray. Adding header actions must not make Completed taller.
  Use **Completed** consistently on both platforms.
- Loading/sync notices float above content as rounded cards without shifting the
  board. Reuse the animated logo rather than a generic spinner; do not also show
  a spinner next to Refresh. Initial synchronization belongs to startup instead.
- While a newly accepted task is pending synchronization, its card and transition
  keep showing the selected subject, task type, deadline, time and priority.
  Synchronization feedback must not replace or hide task metadata.

## Platform appearance and motion

- Android uses portrait orientation only, including startup, editors and pickers;
  rotating the phone must not switch microplanner to landscape. Source: explicit
  user preference, 2026-11-04.
- Android launcher artwork extends the original logo colors to a square; let the
  launcher apply its own mask. No added white border or baked-in extra curvature.
  Sidebar logo keeps the Windows artwork's proportions and curvature. Android
  status/navigation bars follow the current app background, with legible icons.
- Android carousel pages remain flat and layered in depth, without tilted faces:
  Completed | Late | Upcoming. Only predecessors remain behind the active page;
  do not suggest another page beyond Completed. Align the manual selector's left
  edge with the settled column. Preserve current colors and scroll position.
- Motion should be smooth, light and meaningful. Respect reduced motion, avoid
  idle tickers and broad rebuilds, and measure performance-sensitive work rather
  than claiming smoothness from an automated widget test alone.
- Expanding/collapsing sidebar Boards uses a brief coordinated size, fade and
  slight vertical slide, with the disclosure rotating in sync. Reverse smoothly
  on repeated input; collapsed controls must not receive input or keep animating.
- During a board's creation or save, a small neutral light travels around its
  rounded sidebar row and open heading until synchronization resolves. Keep a
  soft luminous tail and visible contrast, without sweeping bands or shading
  across the interior. Preserve board colors and content; omit task-style color
  washes and destination holds. Reduced motion keeps the light stationary.
  On Windows and Android, draw the moving light over the card's perimeter using
  the complete surface bounds, aligned evenly at the top and bottom, including
  display scaling. Android shares the approved Windows placement.
  Source: user requested a different, minimal but noticeable approach after
  rejecting the interior sheen, 2026-11-05.
- Windows keeps the animated startup logo. Android starts with a centered static
  logo and a smooth reveal toward the saved column's logo color. Do not restore
  the Android shuffling startup animation that visibly froze during initialization.

Task transition timings and failure behavior are in
[Interaction and data](interaction-and-data.md); verify real layouts using
[Verification](verification.md).

The [0.11.0 plan](../plans/plan-20261102T143728008Z-version0.11.0.md) extends this
language to account and customization views: reuse the task form's 480-pixel
maximum width, responsive padding and rounded surface. Keep the profile photo
round even in a stretched column. Customization rows must fit narrow screens,
retain readable names and expose reorder/edit/remove actions without crowding.

User refinement, 2026-11-03: sidebar board rows follow the column headers:
use the exact chosen color for labels, icons and actions, with a very pale tint
of it as the background. Selection and hover add an outline without changing
row dimensions. On Windows, names use the full available width until hover or
keyboard focus reveals actions; reserve row height, not hidden action width.
Android shows compact Edit/Delete glyphs aligned right with usable touch targets.
These controls are for boards; task cards still edit on tap/click without an edit
button. Dragged rows keep their own opaque rounded surface; no detached background
ink, white rectangles or tooltips. This supersedes the earlier exact-color fill
and white/black label contrast choice.


Further user refinement, 2026-11-03: every sidebar board name is bold, including
unselected boards. The open board title shows its saved icon and exact color on
both platforms, on a matching rounded very pale surface like its sidebar row;
keep the task area on the original neutral background without a board-color wash.
On Android, group board Edit/Delete glyphs more closely and
place Delete slightly nearer the right edge, with separate usable touch targets.

Navigation refinement, 2026-11-04: Boards has a leading dashboard icon aligned
with Weekly Plan's icon and label, retaining its collapse and add controls on the
right. Clicking/tapping the open board title opens Edit Board. Hover or keyboard
focus expands its tinted title surface slightly to the right to reveal Delete;
use the same confirmation and last-board protection as the sidebar. Preserve
the title's left edge and height, truncate long titles within the available width,
and respect reduced motion.


Palette refinement, 2026-11-03: board/subject selectors contain exactly 21 distinct
colors. Retire bright yellow #FFF176 and light grays #B0BEC5/#CFD8DC; add ochre
#AD7C32, raspberry #A86178, pine #568578 and slate blue #687F9C. Existing uses of
the retired colors are replaced with ochre, slate blue and pine respectively,
through normal account-scoped synchronization (user explicitly chose replacement).
Keep all other saved colors and column header colors. New tones need readable
contrast on their matching pale surfaces. In Android's app bar, the visible gap
from the left edge to the menu glyph matches the gap from that glyph to the
rounded board title surface.


Palette order refinement, 2026-11-03: arrange the same 21 board/subject presets
as a continuous rainbow from reds through orange/yellow, green, blue, violet and
pink, with muted brown/blue-gray neutrals last. Selectors use consistent 40-pixel
circles and 8-pixel gaps, wrapping naturally
to the available width. The Windows Edit Board refinement below constrains its
color section to seven columns; other color selectors retain natural wrapping.
The Windows board title uses the compact Android text/icon/surface proportions.
Reordering presets never changes saved colors or assignments.


Icon controls, 2026-11-03: board forms show a "Board icon" heading above an
icon-only selector tinted with the current board color. Type editors show an
"Icon" heading like the subject editor's "Color" heading, with the selected icon
as its compact button. Use matching rounded surfaces and accessible tooltips.
Windows subject/type rows center 20-pixel markers vertically with names and use
an 8-pixel gap, matching Android's compact separation.
Subject/type list Remove glyphs use 18 pixels on both platforms, centered with
the row and adjacent drag handle; preserve the existing button hit area.
Source: user refinement, 2026-11-05.
Newly created boards default to the final blue-gray preset (#90A4AE), preserving
all existing board colors and legacy deserialization defaults.

Desktop layout refinement, 2026-11-03: Edit Board places Board color on the left
(three rows of seven 40-pixel swatches) and Board icon on the right within the
normal form width. The Windows board icon sits centered in a light-gray rounded
panel aligned with the color grid's top and bottom. Keep the original compact
button with its colored border and pastel fill inside; only that inner button
opens the icon picker. The gray container is passive. Keep both headings aligned, including wrapped labels. Narrow
Windows layouts stack the sections and retain the centered gray selector.
Source: user refinement, 2026-11-05. Task type forms place Icon left and Name right on Windows and
Android, aligned with the input surface rather than its validation row. On
Android the icon button is square, with both sides matching the Name surface's
full height, including enlarged text. Stack
only when the available width cannot fit both controls. This supersedes Android's
previous vertical layout. Source: user refinement, 2026-11-05.
The desktop Choose an icon grid uses eight compact cells per row (five on
unusually narrow dialogs); Android retains five. Hidden desktop board actions
must not shorten names; revealing them truncates names without changing row height.
