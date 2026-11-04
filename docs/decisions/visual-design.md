# Visual design

Applies to visible UI on Windows and Android. Source: user-approved plans
[0.3.0](../plans/plan-20261025T115132337Z-version0.3.0.md),
[0.4.0](../plans/plan-20261025T191235062Z-version0.4.0.md),
[0.5.0](../plans/plan-20261027T085951733Z-version0.5.0.md),
[0.10.0](../plans/plan-20261030T185610007Z-version0.10.0.md), and subsequent explicit
user refinements validated through 0.10.2 (consolidated 2026-11-02).

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

## Forms and cards

- Validation and save-error messages must not change form/dialog height or move
  its controls. Reserve stable message space in shared fields and status areas;
  preserve complete messages through scrolling and accessibility on narrow screens.
  Source: user correction, 2026-11-04.
- Align adjacent icons and punctuation with the text input's filled surface,
  excluding its reserved validation area. Date/time mode switches, Cancel and
  Apply share a vertically centered footer row aligned to the right edge; wrap
  only when space requires it.
  Source: user screenshot review, 2026-11-04.
- Expanded description is a dialog with the **same size and shape** as its task
  form, a back button, the noneditable task title and description field. Keep
  unsaved content. Its expand control is compact, uses matching colors and aligns
  with adjacent fields such as Subject; it is not an oversized separate action.
- Preserve compact task cards on Android: bottom spacing comparable to side
  spacing, no blank subject row or extra title/date gap when Subject is absent.
  Align the checkbox with the date's left edge. Priority has breathing room after
  the title and aligns vertically with the delete icon.
- Subject chips hug their text, including on Windows. Show the subject color in
  the task form selector. Hover/focus effects must not create oversized checkbox
  circles or leave highlights on multiple sidebar boards.
- Android column headers keep their colors even when empty; Windows empty
  headers remain gray. Adding header actions must not make Completed taller.
  Use **Completed** consistently on both platforms.
- Loading/sync notices float above content as rounded cards without shifting the
  board. Reuse the animated logo rather than a generic spinner; do not also show
  a spinner next to Refresh. Initial synchronization belongs to startup instead.

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
Newly created boards default to the final blue-gray preset (#90A4AE), preserving
all existing board colors and legacy deserialization defaults.

Desktop layout refinement, 2026-11-03: Edit Board places Board color on the left
(three rows of seven 40-pixel swatches) and Board icon on the right within the
normal form width. Edit task type places Icon left and Name right. Stack these
sections on narrow Windows layouts; keep Android's current vertical layout.
The desktop Choose an icon grid uses eight compact cells per row (five on
unusually narrow dialogs); Android retains five. Hidden desktop board actions
must not shorten names; revealing them truncates names without changing row height.
