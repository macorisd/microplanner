import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_service.dart';
import '../../../boards/data/models/board.dart';
import '../../../boards/providers/boards_provider.dart';
import 'subject_dialog.dart';

/// Resizable sidebar navigation widget
/// Contains Boards section with subjects management and Sign Out
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _sidebarWidth,
          decoration: const BoxDecoration(
            color: AppColors.sidebarBackground,
          ),
          child: Column(
            children: [
              // Header with logo
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingLarge),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_note_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMedium),
                    Expanded(
                      child: Text(
                        'MicroPlanner',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
                      if (boardsProvider.showSubjectsView) {
                        return const _SubjectsView();
                      }
                      return const _BoardsSection();
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
                      margin: const EdgeInsets.all(AppTheme.spacingMedium),
                      padding: const EdgeInsets.all(AppTheme.spacingMedium),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryLight,
                            child: Text(
                              user.displayName.isNotEmpty
                                  ? user.displayName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingSmall),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  style: Theme.of(context).textTheme.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  user.email,
                                  style: Theme.of(context).textTheme.labelSmall,
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
              const SizedBox(height: AppTheme.spacingMedium),
            ],
          ),
        ),
        // Resize handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _isResizeHovered = true),
          onExit: (_) => setState(() => _isResizeHovered = false),
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _sidebarWidth = (_sidebarWidth + details.delta.dx)
                    .clamp(_minWidth, _maxWidth);
              });
            },
            child: Container(
              width: 4,
              color: _isResizeHovered ? AppColors.primary : AppColors.divider,
            ),
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLarge,
            vertical: AppTheme.spacingSmall,
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
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showAddBoardDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Board list
        Consumer<BoardsProvider>(
          builder: (context, provider, _) {
            return Column(
              children: provider.boards.map((board) {
                return _BoardCard(
                  board: board,
                  isActive: provider.currentBoardId == board.id,
                  canDelete: provider.boards.length > 1,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  void _showAddBoardDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Board'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Board name',
            hintText: 'Enter board name',
          ),
          onSubmitted: (_) {
            if (controller.text.trim().isNotEmpty) {
              context.read<BoardsProvider>().addBoard(name: controller.text.trim());
              Navigator.of(dialogContext).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              context.read<BoardsProvider>().addBoard(name: name.isEmpty ? null : name);
              Navigator.of(dialogContext).pop();
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Board'),
        content: Text('Are you sure you want to delete "${widget.board.name}"? This will also delete all subjects in this board.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<BoardsProvider>().deleteBoard(widget.board.id);
              Navigator.of(dialogContext).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          onTap: _isEditing ? null : () {
            context.read<BoardsProvider>().selectBoard(widget.board.id);
          },
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
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
                    _isEditing
                        ? Flexible(
                            fit: FlexFit.loose,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 100,
                              ),
                              width: _nameController.text.length * 10.0 + 40,
                              child: TextField(
                                controller: _nameController,
                                autofocus: true,
                                style: Theme.of(context).textTheme.bodyMedium,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onSubmitted: (_) => _finishEditing(),
                                onEditingComplete: _finishEditing,
                              ),
                            ),
                          )
                        : Expanded(
                            child: Text(
                              widget.board.name,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    // Action buttons - always present but invisible when not hovered
                    if (!_isEditing)
                      Opacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _BoardActionButton(
                              icon: Icons.edit_outlined,
                              onTap: _isHovered ? _startEditing : null,
                            ),
                            if (widget.canDelete)
                              _BoardActionButton(
                                icon: Icons.delete_outline_rounded,
                                onTap: _isHovered ? _confirmDelete : null,
                              ),
                          ],
                        ),
                      ),
                    if (_isEditing) ...[
                      _BoardActionButton(
                        icon: Icons.check_rounded,
                        onTap: _finishEditing,
                        color: AppColors.success,
                      ),
                      _BoardActionButton(
                        icon: Icons.close_rounded,
                        onTap: _cancelEditing,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTheme.spacingXSmall),
                // Subjects button with oval hover effect
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isSubjectsHovered = true),
                  onExit: (_) => setState(() => _isSubjectsHovered = false),
                  child: GestureDetector(
                    onTap: () {
                      context.read<BoardsProvider>().showSubjectsForBoard(widget.board.id);
                    },
                    child: Container(
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
                          const Icon(
                            Icons.subject_rounded,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Subjects',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.textTertiary,
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLarge,
                vertical: AppTheme.spacingSmall,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => provider.hideSubjectsView(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subjects',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (provider.subjectsBoardName != null)
                          Text(
                            provider.subjectsBoardName!,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                          ),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _showAddSubjectDialog(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
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
    showDialog(
      context: context,
      builder: (dialogContext) => SubjectDialog(
        title: 'New Subject',
        initialName: '',
        initialColor: AppColors.subjectColors.first.value,
        onSave: (name, color) {
          boardsProvider.addSubject(name: name, color: color);
        },
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
        child: Container(
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
              if (_isHovered) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showEditDialog(context),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      context.read<BoardsProvider>().deleteSubject(widget.subject.id);
                    },
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final boardsProvider = context.read<BoardsProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => SubjectDialog(
        title: 'Edit Subject',
        initialName: widget.subject.name,
        initialColor: widget.subject.color,
        onSave: (name, color) {
          final updated = widget.subject.copyWith(name: name, color: color);
          boardsProvider.updateSubject(updated);
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
                        fontWeight:
                            widget.isActive ? FontWeight.w600 : FontWeight.w500,
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
class _BoardActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  const _BoardActionButton({
    required this.icon,
    this.onTap,
    this.color,
  });

  @override
  State<_BoardActionButton> createState() => _BoardActionButtonState();
}

class _BoardActionButtonState extends State<_BoardActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.surfaceVariant : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: widget.color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
