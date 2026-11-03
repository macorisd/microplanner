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

User refinement, 2026-11-03: sidebar board rows use the **exact selected color as
their background**, with matching icons/actions and readable text. Prefer white
when it provides sufficient contrast; otherwise use black. The user explicitly
chose keeping the exact pastel color over darkening it to favor white text.
Remove the former dark/near-black backing for pale colors. Selection and hover
use a border/emphasis, preserving the chosen fill. Dragged rows keep their own
opaque rounded surface; no detached background ink, white rectangles or tooltips.
