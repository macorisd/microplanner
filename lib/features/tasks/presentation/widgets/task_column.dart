import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/input_mode.dart';
import '../../data/models/task.dart';
import 'task_card.dart';

/// A column in the task dashboard displaying tasks of a specific status
class TaskColumn extends StatelessWidget {
  final String title;
  final List<Task> tasks;
  final Color headerColor;
  final Color headerBackgroundColor;
  final IconData icon;
  final FutureOr<void> Function(Task task) onToggleComplete;
  final void Function(Task task)? onDeleteTask;
  final void Function(Task task)? onEditTask;
  final Future<void> Function()? onClearCompleted;

  const TaskColumn({
    super.key,
    required this.title,
    required this.tasks,
    required this.headerColor,
    required this.headerBackgroundColor,
    required this.icon,
    required this.onToggleComplete,
    this.onDeleteTask,
    this.onEditTask,
    this.onClearCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final muted =
        tasks.isEmpty && Theme.of(context).platform != TargetPlatform.android;
    final effectiveHeaderColor = muted ? AppColors.textTertiary : headerColor;
    final effectiveHeaderBgColor = muted
        ? AppColors.surfaceVariant
        : headerBackgroundColor;
    final headerPadding = !touch && MediaQuery.sizeOf(context).height < 360
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : EdgeInsets.all(touch ? 12 : AppTheme.spacingMedium);

    return MotionEntrance(
      fade: false,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _TaskColumnHeader(
                title: title,
                icon: icon,
                tasks: tasks,
                color: effectiveHeaderColor,
                background: effectiveHeaderBgColor,
                padding: headerPadding,
                onClear: onClearCompleted,
              ),

              // Task list
              Expanded(child: _TaskList(column: this)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskColumnHeader extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Task> tasks;
  final Color color;
  final Color background;
  final EdgeInsets padding;
  final Future<void> Function()? onClear;
  const _TaskColumnHeader({
    required this.title,
    required this.icon,
    required this.tasks,
    required this.color,
    required this.background,
    required this.padding,
    required this.onClear,
  });
  @override
  State<_TaskColumnHeader> createState() => _TaskColumnHeaderState();
}

class _TaskColumnHeaderState extends State<_TaskColumnHeader> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final contentPadding = EdgeInsets.symmetric(vertical: widget.padding.top);
    final showClear =
        Theme.of(context).platform != TargetPlatform.windows || _hovered;
    final trackHover =
        widget.onClear != null &&
        Theme.of(context).platform == TargetPlatform.windows;
    return MouseRegion(
      onEnter: trackHover ? (_) => setState(() => _hovered = true) : null,
      onExit: trackHover ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.normal),
        padding: EdgeInsets.symmetric(horizontal: widget.padding.left),
        decoration: BoxDecoration(
          color: widget.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusXLarge),
            topRight: Radius.circular(AppTheme.radiusXLarge),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: contentPadding,
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.color, size: 22),
                    const SizedBox(width: AppTheme.spacingSmall),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: widget.color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.onClear != null)
              Visibility(
                visible: showClear,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: _ClearCompletedButton(
                  hasTasks: widget.tasks.isNotEmpty,
                  onClear: widget.onClear!,
                ),
              ),
            Padding(
              padding: contentPadding,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSmall,
                  vertical: AppTheme.spacingXSmall,
                ),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: MotionSwap(
                  child: Text(
                    '${widget.tasks.length}',
                    key: ValueKey(widget.tasks.length),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearCompletedButton extends StatefulWidget {
  final bool hasTasks;
  final Future<void> Function() onClear;
  const _ClearCompletedButton({required this.hasTasks, required this.onClear});
  @override
  State<_ClearCompletedButton> createState() => _ClearCompletedButtonState();
}

class _ClearCompletedButtonState extends State<_ClearCompletedButton> {
  bool _opening = false;
  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onClear();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final writable = context.select<WorkspaceController, bool>(
      (workspace) => workspace.canWrite,
    );
    return SizedBox.square(
      dimension: usesTouchControls(context) ? 48 : 30,
      child: IconButton(
        tooltip: 'Clear Completed Tasks',
        onPressed: widget.hasTasks && writable && !_opening ? _open : null,
        padding: EdgeInsets.zero,
        color: AppColors.textSecondary,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
      ),
    );
  }
}

/// Empty state shown when a column has no tasks
class _EmptyState extends StatelessWidget {
  final String title;

  const _EmptyState({required this.title});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String message;

    switch (title.toLowerCase()) {
      case 'complete':
      case 'completed':
        icon = Icons.check_circle_outline_rounded;
        message = 'No completed tasks yet';
        break;
      case 'late':
        icon = Icons.celebration_rounded;
        message = 'No overdue tasks!';
        break;
      case 'upcoming':
        icon = Icons.event_available_rounded;
        message = 'No upcoming tasks';
        break;
      default:
        icon = Icons.inbox_rounded;
        message = 'No tasks';
    }

    if (MediaQuery.sizeOf(context).height < 360) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(icon, size: 24, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatefulWidget {
  final TaskColumn column;
  const _TaskList({required this.column});
  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList>
    with SingleTickerProviderStateMixin {
  var _listKey = GlobalKey<AnimatedListState>();
  final _viewportKey = GlobalKey();
  final _scroll = ScrollController();
  final _anchors = <String, GlobalKey>{};
  late final Ticker _anchorTicker;
  GlobalKey? _anchor;
  double? _anchorTop;
  late List<Task> _items;

  @override
  void initState() {
    super.initState();
    _anchorTicker = createTicker(_preserveAnchor);
    _items = List.of(widget.column.tasks);
  }

  @override
  void didUpdateWidget(covariant _TaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.column.tasks;
    if (_items.length == next.length &&
        List.generate(
          next.length,
          (i) => _items[i].id == next[i].id,
        ).every((same) => same)) {
      _items = List.of(next);
      return;
    }
    final state = _listKey.currentState;
    if (state == null) {
      _items = List.of(next);
      _listKey = GlobalKey<AnimatedListState>();
      return;
    }
    final ids = next.map((task) => task.id).toSet();
    _captureAnchor(ids);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final current = _items.map((task) => task.id).toSet();
        _anchors.removeWhere(
          (id, key) => !current.contains(id) && key.currentContext == null,
        );
      }
    });
    if (_items.where((task) => !ids.contains(task.id)).take(21).length > 20) {
      // Bulk removal should not create an animation/controller for every row.
      _items = List.of(next);
      _listKey = GlobalKey<AnimatedListState>();
      return;
    }
    for (var i = _items.length - 1; i >= 0; i--) {
      if (!ids.contains(_items[i].id)) _remove(state, i);
    }
    for (var i = 0; i < next.length; i++) {
      if (i < _items.length && _items[i].id == next[i].id) {
        _items[i] = next[i];
        continue;
      }
      final oldIndex = _items.indexWhere((task) => task.id == next[i].id);
      if (oldIndex == i) {
        _items[i] = next[i];
      } else {
        if (oldIndex >= 0) _remove(state, oldIndex);
        _items.insert(i, next[i]);
        state.insertItem(
          i,
          duration: AppMotion.duration(context, AppMotion.normal),
        );
      }
    }
  }

  void _captureAnchor(Set<String> remaining) {
    if (!_scroll.hasClients || _scroll.position.isScrollingNotifier.value) {
      return;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    GlobalKey? selected;
    double? selectedTop;
    for (final item in _items) {
      if (!remaining.contains(item.id)) continue;
      final key = _anchors[item.id];
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top || y >= bottom) continue;
      if (selectedTop == null || y < selectedTop) {
        selected = key;
        selectedTop = y;
      }
    }
    if (selected == null) return;
    _anchor = selected;
    _anchorTop = selectedTop;
    _anchorTicker.stop();
    _anchorTicker.start();
  }

  void _preserveAnchor(Duration elapsed) {
    if (elapsed > const Duration(milliseconds: 350)) {
      _anchorTicker.stop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _scroll.position.isScrollingNotifier.value) {
        _anchorTicker.stop();
        return;
      }
      final box = _anchor?.currentContext?.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          _anchorTop == null) {
        return;
      }
      final delta = box.localToGlobal(Offset.zero).dy - _anchorTop!;
      if (delta.abs() > 0.5) {
        final position = _scroll.position;
        _scroll.jumpTo(
          (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _anchorTicker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _remove(AnimatedListState state, int index) {
    final removed = _items.removeAt(index);
    state.removeItem(
      index,
      (_, animation) => IgnorePointer(
        child: ExcludeSemantics(
          child: _transition(removed, animation, removed: true),
        ),
      ),
      duration: AppMotion.duration(context, AppMotion.fast),
    );
  }

  Widget _transition(
    Task task,
    Animation<double> animation, {
    bool removed = false,
  }) {
    final column = widget.column;
    return SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: AppMotion.curve)),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: KeyedSubtree(
          key: removed ? null : _anchors.putIfAbsent(task.id, GlobalKey.new),
          child: TaskCard(
            key: ValueKey(task.id),
            task: task,
            hoverBorderColor: column.headerColor,
            onToggleComplete: removed
                ? () {}
                : () => column.onToggleComplete(task),
            onEdit: column.onEditTask != null
                ? (removed ? () {} : () => column.onEditTask!(task))
                : null,
            onDelete: column.onDeleteTask != null
                ? (removed ? () {} : () => column.onDeleteTask!(task))
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: _viewportKey,
    children: [
      Positioned.fill(
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(false),
            trackVisibility: WidgetStateProperty.all(false),
          ),
          child: AnimatedList(
            key: _listKey,
            controller: _scroll,
            initialItemCount: _items.length,
            padding: EdgeInsets.fromLTRB(
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              MediaQuery.sizeOf(context).height < 360
                  ? 64
                  : (usesTouchControls(context) ? 8 : AppTheme.spacingMedium),
            ),
            itemBuilder: (_, index, animation) =>
                _transition(_items[index], animation),
          ),
        ),
      ),
      if (_items.isEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: MotionEntrance(
              child: _EmptyState(title: widget.column.title),
            ),
          ),
        ),
    ],
  );
}
