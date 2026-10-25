import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../auth/data/auth_service.dart';
import '../../../boards/data/models/board.dart';
import '../../../boards/providers/boards_provider.dart';
import 'subject_dialog.dart';
import 'save_status.dart';

/// Resizable sidebar navigation widget
/// Contains Boards section with subjects management and Sign Out
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

                // Boards section
                Expanded(
                  child: SingleChildScrollView(
                    child: Consumer<BoardsProvider>(
                      builder: (context, boardsProvider, _) {
                        return MotionSwap(
                          alignment: Alignment.topLeft,
                          child: KeyedSubtree(
                            key: ValueKey(
                              boardsProvider.showSubjectsView
                                  ? 'subjects:${boardsProvider.subjectsBoardName}'
                                  : 'boards',
                            ),
                            child: boardsProvider.showSubjectsView
                                ? const _SubjectsView()
                                : const _BoardsSection(),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // User info
                Consumer<AuthService>(
                  builder: (context, authService, _) {
                    final user = authService.currentUser;
                    if (user == null) return const SizedBox.shrink();

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
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
                            _ProfileAvatar(key: ValueKey(user.id), user: user),
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
                    );
                  },
                ),

                // Sign out button
                _SidebarItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  isActive: false,
                  onTap: () {
                    context.read<AuthService>().signOut();
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

/// Boards section with header and list
class _BoardsSection extends StatelessWidget {
  const _BoardsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLarge,
            vertical: usesTouchControls(context) ? 0 : AppTheme.spacingSmall,
          ),
          child: Row(
            children: [
              Text(
                'Boards',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _BoardActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New board',
                color: AppColors.primary,
                onTap: () => _showAddBoardDialog(context),
              ),
            ],
          ),
        ),
        // Board list - Reorderable with smooth animations
        Consumer<BoardsProvider>(
          builder: (context, provider, _) {
            return ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final animValue = Curves.easeInOut.transform(
                      animation.value,
                    );
                    final elevation = lerpDouble(0, 8, animValue)!;
                    final scale = lerpDouble(1.0, 1.03, animValue)!;
                    return Transform.scale(
                      scale: scale,
                      child: Material(
                        elevation: elevation,
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                provider.reorderBoards(oldIndex, newIndex);
              },
              itemCount: provider.boards.length,
              itemBuilder: (context, index) {
                final board = provider.boards[index];
                final card = _BoardCard(
                  board: board,
                  isActive: provider.currentBoardId == board.id,
                  canDelete: provider.boards.length > 1,
                );
                if (usesTouchControls(context)) {
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(board.id),
                    index: index,
                    child: card,
                  );
                }
                return ReorderableDragStartListener(
                  key: ValueKey(board.id),
                  index: index,
                  child: card,
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _showAddBoardDialog(BuildContext context) {
    final controller = TextEditingController();
    showMotionDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Board'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Board name',
                hintText: 'Enter board name',
              ),
              onSubmitted: (_) async {
                if (controller.text.trim().isNotEmpty) {
                  final saved = await context.read<BoardsProvider>().addBoard(
                    name: controller.text.trim(),
                  );
                  if (saved && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                }
              },
            ),
            const SaveStatus(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              final saved = await context.read<BoardsProvider>().addBoard(
                name: name.isEmpty ? null : name,
              );
              if (saved && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Individual board card in sidebar
class _BoardCard extends StatefulWidget {
  final Board board;
  final bool isActive;
  final bool canDelete;

  const _BoardCard({
    required this.board,
    required this.isActive,
    required this.canDelete,
  });

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _isHovered = false;
  bool _isSubjectsHovered = false;
  bool _isEditing = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.board.name);
    _nameController.addListener(() {
      // Rebuild to update width based on text length
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _nameController.text = widget.board.name;
    });
  }

  void _finishEditing() {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty && newName != widget.board.name) {
      final updated = widget.board.copyWith(name: newName);
      context.read<BoardsProvider>().updateBoard(updated);
    }
    setState(() => _isEditing = false);
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _nameController.text = widget.board.name;
    });
  }

  void _confirmDelete() {
    showMotionDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Board'),
        content: Text(
          'Are you sure you want to delete "${widget.board.name}"? This will also delete all subjects and tasks in this board.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final saved = await context.read<BoardsProvider>().deleteBoard(
                widget.board.id,
              );
              if (saved && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            autofocus: true,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final showActions = touch || _isHovered;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingXSmall,
      ),
      child: TapRegion(
        onTapOutside: (_) {
          if (_isEditing) _cancelEditing();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: _isEditing
                ? null
                : () {
                    context.read<BoardsProvider>().selectBoard(widget.board.id);
                    final scaffold = Scaffold.maybeOf(context);
                    if (scaffold?.isDrawerOpen ?? false) {
                      scaffold!.closeDrawer();
                    }
                  },
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.normal),
              curve: AppMotion.curve,
              padding: EdgeInsets.symmetric(
                horizontal: touch ? 12 : AppTheme.spacingMedium,
                vertical: touch ? 4 : AppTheme.spacingMedium,
              ),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? AppColors.sidebarItemActive
                    : _isHovered
                    ? AppColors.sidebarItemHover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: widget.isActive
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.dashboard_rounded,
                        size: 18,
                        color: widget.isActive
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppTheme.spacingSmall),
                      Expanded(
                        child: MotionSwap(
                          alignment: Alignment.centerLeft,
                          child: _isEditing
                              ? TextField(
                                  key: const ValueKey('editing'),
                                  controller: _nameController,
                                  autofocus: true,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                  ),
                                  onSubmitted: (_) => _finishEditing(),
                                )
                              : Text(
                                  widget.board.name,
                                  key: const ValueKey('name'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: widget.isActive
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                        fontWeight: widget.isActive
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ),
                      // Action buttons - always present but invisible when not hovered
                      if (!_isEditing)
                        AnimatedOpacity(
                          duration: AppMotion.duration(context, AppMotion.fast),
                          opacity: showActions ? 1.0 : 0.0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BoardActionButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Rename board',
                                onTap: showActions ? _startEditing : null,
                              ),
                              if (widget.canDelete)
                                _BoardActionButton(
                                  icon: Icons.delete_outline_rounded,
                                  tooltip: 'Delete board',
                                  onTap: showActions ? _confirmDelete : null,
                                ),
                            ],
                          ),
                        ),
                      if (_isEditing) ...[
                        _BoardActionButton(
                          icon: Icons.check_rounded,
                          tooltip: 'Save board name',
                          onTap: _finishEditing,
                          color: AppColors.success,
                        ),
                        _BoardActionButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Cancel renaming',
                          onTap: _cancelEditing,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: touch ? 0 : AppTheme.spacingXSmall),
                  // Subjects button with oval hover effect
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _isSubjectsHovered = true),
                    onExit: (_) => setState(() => _isSubjectsHovered = false),
                    child: GestureDetector(
                      onTap: () {
                        context.read<BoardsProvider>().showSubjectsForBoard(
                          widget.board.id,
                        );
                      },
                      child: AnimatedContainer(
                        duration: AppMotion.duration(context, AppMotion.fast),
                        constraints: BoxConstraints(
                          minHeight: usesTouchControls(context) ? 48 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingSmall,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isSubjectsHovered
                                ? AppColors.textTertiary
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.subject_rounded,
                              size: touch ? 16 : 14,
                              color: touch
                                  ? AppColors.textSecondary
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Subjects',
                              style:
                                  (touch
                                          ? Theme.of(
                                              context,
                                            ).textTheme.labelMedium
                                          : Theme.of(
                                              context,
                                            ).textTheme.labelSmall)
                                      ?.copyWith(
                                        color: touch
                                            ? AppColors.textSecondary
                                            : AppColors.textTertiary,
                                      ),
                            ),
                          ],
                        ),
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

/// Subject management view
class _SubjectsView extends StatelessWidget {
  const _SubjectsView();

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardsProvider>(
      builder: (context, provider, _) {
        final subjects = provider.currentBoardSubjects;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with back button
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLarge,
                vertical: usesTouchControls(context)
                    ? 0
                    : AppTheme.spacingSmall,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BoardActionButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to boards',
                    onTap: provider.hideSubjectsView,
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subjects',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (provider.subjectsBoardName != null)
                          Text(
                            provider.subjectsBoardName!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                      ],
                    ),
                  ),
                  _BoardActionButton(
                    icon: Icons.add_rounded,
                    tooltip: 'New subject',
                    color: AppColors.primary,
                    onTap: () => _showAddSubjectDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingXSmall),
            // Subject list
            if (subjects.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLarge),
                child: Text(
                  'No subjects yet.\nTap + to add one.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...subjects.map((subject) => _SubjectItem(subject: subject)),
          ],
        );
      },
    );
  }

  void _showAddSubjectDialog(BuildContext context) {
    final boardsProvider = context.read<BoardsProvider>();
    showMotionDialog(
      context: context,
      builder: (dialogContext) => SubjectDialog(
        title: 'New Subject',
        initialName: '',
        initialColor: AppColors.subjectColors.first.toARGB32(),
        onSave: (name, color) =>
            boardsProvider.addSubject(name: name, color: color),
      ),
    );
  }
}

/// Individual subject item
class _SubjectItem extends StatefulWidget {
  final dynamic subject;

  const _SubjectItem({required this.subject});

  @override
  State<_SubjectItem> createState() => _SubjectItemState();
}

class _SubjectItemState extends State<_SubjectItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingXSmall,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMedium,
            vertical: AppTheme.spacingSmall,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.sidebarItemHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(widget.subject.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              Expanded(
                child: Text(
                  widget.subject.name,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (usesTouchControls(context) || _isHovered) ...[
                _BoardActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit subject',
                  onTap: () => _showEditDialog(context),
                ),
                _BoardActionButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete subject',
                  onTap: _confirmDeleteSubject,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSubject() {
    showMotionDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Subject'),
        content: Text(
          'Are you sure you want to delete "${widget.subject.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final saved = await context.read<BoardsProvider>().deleteSubject(
                widget.subject.id,
              );
              if (saved && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            autofocus: true,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final boardsProvider = context.read<BoardsProvider>();
    showMotionDialog(
      context: context,
      builder: (dialogContext) => SubjectDialog(
        title: 'Edit Subject',
        initialName: widget.subject.name,
        initialColor: widget.subject.color,
        onSave: (name, color) {
          final updated = widget.subject.copyWith(name: name, color: color);
          return boardsProvider.updateSubject(updated);
        },
      ),
    );
  }
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
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
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
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isHighlighted
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
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

  const _BoardActionButton({
    required this.icon,
    this.onTap,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      child: SizedBox.square(
        dimension: usesTouchControls(context) ? 48 : 24,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          padding: EdgeInsets.zero,
          hoverColor: AppColors.surfaceVariant,
          icon: Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
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
