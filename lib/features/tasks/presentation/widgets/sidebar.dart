import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/widgets/board_sync_glow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../../core/widgets/bounded_reorderable_list.dart';
import '../../../../core/widgets/disclosure_icon.dart';
import '../../../auth/data/auth_service.dart';
import '../../../boards/data/models/board.dart';
import '../../../boards/providers/boards_provider.dart';
import 'new_board_dialog.dart';
import 'board_actions.dart';
import '../../../boards/data/board_catalog.dart';

/// Resizable sidebar navigation widget
/// Contains navigation, boards and the current account.
class Sidebar extends StatefulWidget {
  final bool inDrawer;

  const Sidebar({super.key, this.inDrawer = false});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  double _sidebarWidth = AppTheme.sidebarWidth;
  static const double _minWidth = AppTheme.sidebarWidth;
  static const double _maxWidth = AppTheme.sidebarWidth * 2;
  bool _isResizeHovered = false;

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: widget.inDrawer ? constraints.maxWidth : _sidebarWidth,
            decoration: const BoxDecoration(color: AppColors.sidebarBackground),
            child: Column(
              children: [
                // Header with logo
                Container(
                  padding: EdgeInsets.all(touch ? 16 : AppTheme.spacingLarge),
                  child: Row(
                    children: [
                      Container(
                        width: touch ? 32 : 40,
                        height: touch ? 32 : 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(touch ? 9.6 : 12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/microplanner_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMedium),
                      Expanded(
                        child: Text(
                          'microplanner',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: AppTheme.spacingSmall),

                _SidebarItem(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'Weekly Plan',
                  isActive:
                      context.select<BoardsProvider, DashboardPage>(
                        (boards) => boards.page,
                      ) ==
                      DashboardPage.weeklyPlan,
                  onTap: () {
                    context.read<BoardsProvider>().navigate(
                      DashboardPage.weeklyPlan,
                    );
                    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                      Scaffold.of(context).closeDrawer();
                    }
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(child: const _BoardsSection()),
                ),

                // User info
                Consumer<AuthService>(
                  builder: (context, authService, _) {
                    final user = authService.currentUser;
                    if (user == null) return const SizedBox.shrink();

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        onTap: () {
                          context.read<BoardsProvider>().navigate(
                            DashboardPage.profile,
                          );
                          if (Scaffold.maybeOf(context)?.isDrawerOpen ??
                              false) {
                            Scaffold.of(context).closeDrawer();
                          }
                        },
                        child: Container(
                          margin: EdgeInsets.all(
                            touch ? 12 : AppTheme.spacingMedium,
                          ),
                          padding: EdgeInsets.all(
                            touch ? 12 : AppTheme.spacingMedium,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                          ),
                          child: Row(
                            children: [
                              _ProfileAvatar(
                                key: ValueKey(user.id),
                                user: user,
                              ),
                              const SizedBox(width: AppTheme.spacingSmall),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      user.email,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                SizedBox(height: touch ? 8 : AppTheme.spacingMedium),
              ],
            ),
          ),
          // Resize handle
          if (!widget.inDrawer)
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _isResizeHovered = true),
              onExit: (_) => setState(() => _isResizeHovered = false),
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
                      _minWidth,
                      _maxWidth,
                    );
                  });
                },
                child: Container(
                  width: 4,
                  color: _isResizeHovered
                      ? AppColors.primary
                      : AppColors.divider,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Expanded-by-default board navigation with accessible editing controls.
class _BoardsSection extends StatefulWidget {
  const _BoardsSection();
  @override
  State<_BoardsSection> createState() => _BoardsSectionState();
}

class _BoardsSectionState extends State<_BoardsSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final _motion = AnimationController(
    vsync: this,
    duration: AppMotion.entrance,
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _motion,
    curve: AppMotion.curve,
    reverseCurve: Curves.easeInOutCubic,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = _expanded ? 1 : 0;
    } else if (_expanded) {
      _motion.forward();
    } else {
      _motion.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = _expanded ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                expanded: _expanded,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                      vertical: AppTheme.spacingMedium,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.dashboard_outlined,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppTheme.spacingMedium),
                        Expanded(
                          child: Text(
                            'Boards',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        RotationTransition(
                          turns: Tween<double>(
                            begin: -.25,
                            end: 0,
                          ).animate(_curve),
                          child: const DisclosureIcon(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _BoardActionButton(
              icon: Icons.add_rounded,
              tooltip: 'New board',
              color: AppColors.primary,
              onTap: () {
                final boards = context.read<BoardsProvider>();
                showMotionDialog(
                  context: context,
                  builder: (_) => NewBoardDialog(
                    onSave: (name) => boards.addBoard(name: name),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      AnimatedBuilder(
        animation: _motion,
        builder: (context, child) => !_expanded && _motion.isDismissed
            ? const SizedBox.shrink()
            : ClipRect(
                child: SizeTransition(
                  sizeFactor: _curve,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: _curve,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -.035),
                        end: Offset.zero,
                      ).animate(_curve),
                      child: IgnorePointer(
                        ignoring: !_expanded,
                        child: ExcludeFocus(
                          excluding: !_expanded,
                          child: ExcludeSemantics(
                            excluding: !_expanded,
                            child: child!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        child: Consumer<BoardsProvider>(
          builder: (context, provider, _) => BoundedReorderableList(
            proxyColor: AppColors.sidebarBackground,
            onReorder: provider.reorderBoards,
            itemCount: provider.boards.length,
            itemBuilder: (context, index) {
              final board = provider.boards[index];
              final card = _BoardCard(
                board: board,
                isActive:
                    provider.currentBoardId == board.id &&
                    provider.page == DashboardPage.board,
                canDelete: provider.boards.length > 1,
              );
              return usesTouchControls(context)
                  ? ReorderableDelayedDragStartListener(
                      key: ValueKey(board.id),
                      index: index,
                      child: card,
                    )
                  : ReorderableDragStartListener(
                      key: ValueKey(board.id),
                      index: index,
                      child: card,
                    );
            },
          ),
        ),
      ),
    ],
  );
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({
    required this.board,
    required this.isActive,
    required this.canDelete,
  });
  final Board board;
  final bool isActive;
  final bool canDelete;
  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _hovered = false;
  bool _focused = false;
  void _edit() => editBoard(context, widget.board);
  void _delete() => confirmBoardDeletion(context, widget.board);

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final pending = context.select<WorkspaceController, bool>(
      (workspace) => workspace.pendingBoardIds.contains(widget.board.id),
    );
    final show = touch || _hovered || _focused;
    final color = Color(widget.board.color);
    final foreground = color;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingXSmall,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              hoverColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              onTap: () {
                context.read<BoardsProvider>().selectBoard(widget.board.id);
                if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                  Scaffold.of(context).closeDrawer();
                }
              },
              child: _BoardSurface(
                pending: pending,
                decoration: BoxDecoration(
                  color: boardRowBackground(color),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color: _focused || widget.isActive
                        ? foreground.withValues(alpha: .7)
                        : _hovered
                        ? foreground.withValues(alpha: .25)
                        : Colors.transparent,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTheme.spacingMedium,
                    touch ? 4 : 8,
                    touch ? AppTheme.spacingSmall : AppTheme.spacingMedium,
                    touch ? 4 : 8,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: touch ? 48 : 24),
                    child: Row(
                      children: [
                        Icon(
                          boardIcons[widget.board.icon] ??
                              Icons.dashboard_rounded,
                          size: 20,
                          color: foreground,
                        ),
                        const SizedBox(width: AppTheme.spacingSmall),
                        Expanded(
                          child: Text(
                            widget.board.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Visibility(
                          visible: show,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BoardActionButton(
                                compact: touch,
                                alignment: touch
                                    ? Alignment.centerRight
                                    : Alignment.center,
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit board',
                                color: foreground,
                                onTap: pending ? null : _edit,
                              ),
                              Visibility(
                                visible: widget.canDelete,
                                maintainState: true,
                                maintainAnimation: true,
                                maintainSize: true,
                                child: _BoardActionButton(
                                  compact: touch,
                                  icon: Icons.delete_outline_rounded,
                                  tooltip: 'Delete board',
                                  color: foreground,
                                  onTap: pending ? null : _delete,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The outline and its travelling light share the complete card surface.
class _BoardSurface extends StatelessWidget {
  const _BoardSurface({
    required this.pending,
    required this.decoration,
    required this.child,
  });
  final bool pending;
  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) => BoardSyncGlow(
    active: pending,
    foreground: true,
    child: Ink(decoration: decoration, child: child),
  );
}

/// Individual sidebar navigation item
class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isHovered;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingXSmall,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            onTap: widget.onTap,
            child: Ink(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingMedium,
              ),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? AppColors.sidebarItemActive
                    : _isHovered
                    ? AppColors.sidebarItemHover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 22,
                    color: isHighlighted
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isHighlighted
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Action button for board cards with hover effect
class _BoardActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  final bool compact;
  final Alignment alignment;

  const _BoardActionButton({
    required this.icon,
    this.onTap,
    this.color,
    this.tooltip,
    this.compact = false,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // A disabled nested button must consume its tap instead of selecting the row.
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? () {} : null,
      child: PressFeedback(
        child: SizedBox(
          width: compact
              ? 44
              : usesTouchControls(context)
              ? 48
              : 24,
          height: usesTouchControls(context) ? 48 : 24,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 4)
                : EdgeInsets.zero,
            alignment: alignment,
            hoverColor: AppColors.surfaceVariant,
            icon: Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final AppUser user;
  const _ProfileAvatar({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    final url = user.photoUrl?.trim();
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primaryLight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              user.displayName.isEmpty
                  ? 'U'
                  : user.displayName[0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (url != null && url.isNotEmpty)
            ClipOval(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, synchronous) =>
                    AnimatedOpacity(
                      duration: AppMotion.duration(context, AppMotion.normal),
                      opacity: frame == null ? 0 : 1,
                      child: child,
                    ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
