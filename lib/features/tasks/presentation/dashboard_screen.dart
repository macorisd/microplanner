import 'dart:async';

import 'widgets/action_confirmation_dialog.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/notifications/notification_controller.dart';
import '../../../core/widgets/board_sync_glow.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/input_mode.dart';
import '../../boards/providers/boards_provider.dart';
import '../../boards/data/board_catalog.dart';
import '../../boards/data/models/board.dart';
import 'widgets/board_actions.dart';
import '../data/models/task.dart';
import '../providers/tasks_provider.dart';
import 'widgets/add_task_dialog.dart';
import 'widgets/android_board_carousel.dart';
import 'widgets/edit_task_dialog.dart';
import 'widgets/sidebar.dart';
import 'widgets/account_pages.dart';
import 'widgets/task_column.dart';
import 'widgets/editor_panel.dart';
import 'package:flutter/services.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _taskArea = GlobalKey<_TaskAreaState>();
  BoardsProvider? _navigation;
  LocalHistoryEntry? _history;
  bool _disposing = false;
  NotificationController? _notifications;
  bool _notificationScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifications = context.read<NotificationController?>();
    if (!identical(notifications, _notifications)) {
      _notifications?.removeListener(_notificationChanged);
      _notifications = notifications;
      notifications?.addListener(_notificationChanged);
    }
    _notificationChanged();
    final boards = context.read<BoardsProvider>();
    if (identical(_navigation, boards)) return;
    _navigation?.removeListener(_syncHistory);
    _navigation = boards..addListener(_syncHistory);
    _syncHistory();
  }

  void _syncHistory() {
    if (_navigation!.page == DashboardPage.board) {
      _history?.remove();
      _history = null;
    } else if (_history == null) {
      _history = LocalHistoryEntry(
        onRemove: () {
          _history = null;
          if (!_disposing) _navigation?.navigate(DashboardPage.board);
        },
      );
      ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    }
  }

  void _back() => _navigation?.navigate(DashboardPage.board);

  void _notificationChanged() {
    if (_notifications?.target == null || _notificationScheduled || !mounted) {
      return;
    }
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final target = _notifications?.target;
      if (target == null) return;
      final workspace = context.read<WorkspaceController>();
      if (workspace.isLoading || !workspace.hasData) return;
      _notifications!.consumeTarget();
      if (target.owner != workspace.ownerId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This reminder belongs to another account.'),
          ),
        );
        return;
      }
      final task = workspace.snapshot.tasks
          .where((t) => t.id == target.task && t.boardId == target.board)
          .firstOrNull;
      if (task == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This task is no longer available.')),
        );
        return;
      }
      context.read<BoardsProvider>().selectBoard(task.boardId!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _taskArea.currentState?.revealCreatedTask((
          id: task.id,
          boardId: task.boardId!,
          columnIndex: task.isCompleted
              ? 0
              : task.isLate
              ? 1
              : 2,
        ));
      });
    });
  }

  @override
  void dispose() {
    _disposing = true;
    _notifications?.removeListener(_notificationChanged);
    _navigation?.removeListener(_syncHistory);
    _history?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final android = Theme.of(context).platform == TargetPlatform.android;
    final backInset = MediaQuery.systemGestureInsetsOf(context).left;
    final compact = android || MediaQuery.sizeOf(context).width < 850;
    final short = MediaQuery.sizeOf(context).height < 360;
    final workspace = context.watch<WorkspaceController>();
    final page = context.select<BoardsProvider, DashboardPage>(
      (boards) => boards.page,
    );
    final board = context.select<BoardsProvider, Board?>(
      (boards) => boards.currentBoard,
    );
    final boardName = board?.name ?? 'My Tasks';
    final pageName = switch (page) {
      DashboardPage.board => boardName,
      DashboardPage.weeklyPlan => 'Weekly Plan',
      DashboardPage.profile => 'Profile',
      DashboardPage.settings => 'Settings',
    };
    final refresh = IconButton(
      tooltip: 'Refresh cloud data',
      onPressed: workspace.isLoading || workspace.isSaving
          ? null
          : workspace.refresh,
      icon: const Icon(Icons.refresh),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: Scaffold(
        appBar: compact
            ? AppBar(
                toolbarHeight: short ? 48 : null,
                titleSpacing: android ? 0 : null,
                title: MotionSwap(
                  alignment: Alignment.centerLeft,
                  child: page == DashboardPage.board
                      ? _BoardHeading(key: ValueKey(board?.id), board: board)
                      : Text(
                          pageName,
                          key: ValueKey(pageName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                actions: [if (page == DashboardPage.board) refresh],
              )
            : null,
        drawer: compact
            ? const Drawer(child: SafeArea(child: Sidebar(inDrawer: true)))
            : null,
        // Some Android skins report zero for the Back inset. Keep a small fallback
        // so an inward drag just beyond that OS-owned strip can reach the drawer.
        // This does not exclude or override the system Back gesture.
        drawerEdgeDragWidth: android
            ? 36 + (backInset < 20 ? 20 : backInset)
            : null,
        body: Row(
          children: [
            if (!compact) const Sidebar(),
            Expanded(
              child: Container(
                color: AppColors.background,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact && page == DashboardPage.board)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingLarge,
                          vertical: AppTheme.spacingMedium,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: MotionSwap(
                                alignment: Alignment.centerLeft,
                                child: _BoardHeading(
                                  key: ValueKey(board?.id),
                                  board: board,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                            refresh,
                          ],
                        ),
                      ),
                    Expanded(
                      child: MotionEntrance(
                        key: ValueKey(page),
                        fade: page != DashboardPage.board,
                        child: switch (page) {
                          DashboardPage.board => _TaskArea(
                            key: _taskArea,
                            onAdd: () => _add(context),
                          ),
                          DashboardPage.weeklyPlan => EditorPanel(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                EditorHeading(
                                  title: 'Weekly Plan',
                                  icon: Icons.calendar_view_week_outlined,
                                  onBack: _back,
                                ),
                                const SizedBox(height: AppTheme.spacingLarge),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingLarge,
                                  ),
                                  child: Text('Coming Soon'),
                                ),
                              ],
                            ),
                          ),
                          DashboardPage.profile => ProfilePage(
                            onBack: _back,
                            onSettings: () => context
                                .read<BoardsProvider>()
                                .navigate(DashboardPage.settings),
                          ),
                          DashboardPage.settings => SettingsPage(
                            onBack: () => context
                                .read<BoardsProvider>()
                                .navigate(DashboardPage.profile),
                          ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: android || page != DashboardPage.board
            ? null
            : PressFeedback(
                child: short
                    ? FloatingActionButton.small(
                        tooltip: 'New Task',
                        onPressed: workspace.canWrite
                            ? () => _add(context)
                            : null,
                        child: const Icon(Icons.add_rounded),
                      )
                    : FloatingActionButton.extended(
                        onPressed: workspace.canWrite
                            ? () => _add(context)
                            : null,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Task'),
                      ),
              ),
      ),
    );
  }

  static List<Widget> _taskColumns(
    BuildContext context, {
    ValueListenable<TaskRevealRequest?>? revealRequests,
  }) {
    Widget column(
      String title,
      List<Task> Function(TasksProvider) select,
      Color color,
      Color background,
      IconData icon, {
      bool completed = false,
    }) => Selector<TasksProvider, (String?, String?, List<Task>)>(
      selector: (_, provider) => (
        provider.workspace.ownerId,
        provider.boards.currentBoardId,
        select(provider),
      ),
      shouldRebuild: (previous, next) =>
          previous.$1 != next.$1 ||
          previous.$2 != next.$2 ||
          !identical(previous.$3, next.$3),
      builder: (context, view, _) {
        final provider = context.read<TasksProvider>();
        return TaskColumn(
          key: ValueKey('${view.$1}:${view.$2}:$title'),
          title: title,
          tasks: view.$3,
          headerColor: color,
          headerBackgroundColor: background,
          icon: icon,
          onToggleComplete: (task) => provider.toggleTaskCompletion(task.id),
          onDeleteTask: (task) => _delete(context, task),
          onEditTask: (task) => _edit(context, task),
          onClearCompleted: completed ? () => _clearCompleted(context) : null,
          revealRequests: revealRequests,
        );
      },
    );
    return [
      column(
        'Completed',
        (provider) => provider.completedTasks,
        AppColors.completeHeader,
        AppColors.completeHeaderLight,
        Icons.check_circle_rounded,
        completed: true,
      ),
      column(
        'Late',
        (provider) => provider.lateTasks,
        AppColors.lateHeader,
        AppColors.lateHeaderLight,
        Icons.warning_rounded,
      ),
      column(
        'Upcoming',
        (provider) => provider.upcomingTasks,
        AppColors.upcomingHeader,
        AppColors.upcomingHeaderLight,
        Icons.schedule_rounded,
      ),
    ];
  }

  void _add(BuildContext context) {
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => AddTaskDialog(
        onSave: provider.addTask,
        onSaveWithType: provider.addTask,
        onCreated: () {
          final created = provider.latestCreatedTask;
          if (created != null) {
            _taskArea.currentState?.revealCreatedTask(created);
          }
        },
      ),
    );
  }

  static void _edit(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => EditTaskDialog(
        task: task,
        onSave: (updated) => provider.updateTask(updated, original: task),
      ),
    );
  }

  static void _delete(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => ActionConfirmationDialog(
        actionLabel: 'Delete',
        pendingLabel: 'Deleting…',
        destructive: true,
        title: 'Delete Task',
        message: 'Are you sure you want to delete "${task.name}"?',
        onConfirm: () => provider.deleteTask(task.id),
      ),
    );
  }

  static Future<void> _clearCompleted(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final provider = context.read<TasksProvider>();
    final board = context.read<BoardsProvider>().currentBoard;
    if (!workspace.canWrite ||
        board == null ||
        provider.completedTasks.isEmpty) {
      return;
    }
    final owner = workspace.ownerId;
    final token = workspace.auth.token;
    final intended = provider.completedTasks.map((task) => task.id).toSet();
    final count = intended.length;
    await showMotionDialog(
      context: context,
      builder: (_) => ActionConfirmationDialog(
        title: 'Delete Completed tasks',
        message:
            'Delete $count completed ${count == 1 ? 'task' : 'tasks'} from "${board.name}"?',
        actionLabel: 'Delete',
        pendingLabel: 'Clearing…',
        destructive: true,
        onConfirm: () {
          if (workspace.ownerId != owner || workspace.auth.token != token) {
            return Future.value(false);
          }
          return provider.clearCompletedTasks(
            boardId: board.id,
            taskIds: intended,
          );
        },
      ),
    );
  }
}

class _BoardHeading extends StatefulWidget {
  const _BoardHeading({super.key, required this.board, this.style});

  final Board? board;
  final TextStyle? style;

  @override
  State<_BoardHeading> createState() => _BoardHeadingState();
}

class _BoardHeadingState extends State<_BoardHeading> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final pending = context.select<WorkspaceController, bool>(
      (workspace) => workspace.pendingBoardIds.contains(board?.id),
    );
    final canDelete = context.select<BoardsProvider, bool>(
      (boards) => boards.boards.length > 1,
    );
    final foreground = Color(board?.color ?? 0xff7986cb);
    final textStyle = (widget.style ?? Theme.of(context).textTheme.titleLarge)
        ?.copyWith(color: foreground, fontWeight: FontWeight.w700);
    final touch = usesTouchControls(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (value) => setState(() => _focused = value),
          child: _HeadingSize(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: boardRowBackground(foreground),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: BoardSyncGlow(
                active: pending,
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    key: const ValueKey('board-heading'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: 'Edit board',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                            onTap: board == null || pending
                                ? null
                                : () => editBoard(context, board),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: touch ? 36 : 24,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      boardIcons[board?.icon] ??
                                          Icons.dashboard_rounded,
                                      color: foreground,
                                      size: (textStyle?.fontSize ?? 22)
                                          .clamp(24, 36)
                                          .toDouble(),
                                    ),
                                    const SizedBox(
                                      width: AppTheme.spacingSmall,
                                    ),
                                    Flexible(
                                      child: Text(
                                        board?.name ?? 'My Tasks',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (board != null && canDelete && (_hovered || _focused))
                        SizedBox(
                          width: touch ? 48 : 36,
                          height: touch ? 48 : 36,
                          child: IconButton(
                            tooltip: 'Delete board',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: foreground,
                            ),
                            onPressed: pending
                                ? null
                                : () => confirmBoardDeletion(context, board),
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
    );
  }
}

/// Reduced motion bypasses size interpolation, including live preference changes.
class _HeadingSize extends StatelessWidget {
  const _HeadingSize({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          alignment: Alignment.centerLeft,
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          child: child,
        );
}

/// Cloud status changes do not rebuild or re-sort the task workspace.
class _TaskArea extends StatefulWidget {
  final VoidCallback onAdd;

  const _TaskArea({super.key, required this.onAdd});
  @override
  State<_TaskArea> createState() => _TaskAreaState();
}

class _TaskAreaState extends State<_TaskArea> {
  final _horizontal = ScrollController();
  final _creationReveals = ValueNotifier<TaskRevealRequest?>(null);
  final _carousel = AndroidBoardCarouselController();
  final _touchColumns = _TouchColumnsController();
  Timer? _revealTimer;
  Timer? _scrollRevealTimer;
  int _revealRevision = 0;

  void revealCreatedTask(TaskCreationTarget target) {
    _revealTimer?.cancel();
    _scrollRevealTimer?.cancel();
    _revealTimer = Timer(AppMotion.duration(context, AppMotion.normal), () {
      if (!mounted) return;
      final tasks = context.read<TasksProvider>();
      final boards = context.read<BoardsProvider>();
      if (boards.currentBoardId != target.boardId ||
          !tasks.tasks.any((task) => task.id == target.id)) {
        return;
      }
      final column = target.columnIndex.clamp(0, 2).toInt();
      final distance = (column - boards.currentColumnIndex).abs();
      boards.selectColumn(column);
      Duration navigation = Duration.zero;
      if (Theme.of(context).platform == TargetPlatform.android) {
        _carousel.selectColumn(column);
        if (distance > 0) {
          navigation = Duration(milliseconds: 260 + distance * 100);
        }
      } else if (MediaQuery.sizeOf(context).width < 850 &&
          usesTouchControls(context)) {
        _touchColumns.selectColumn(column);
        if (distance > 0) navigation = AppMotion.normal;
      }
      void reveal() {
        if (!mounted) return;
        _creationReveals.value = TaskRevealRequest(
          taskId: target.id,
          revision: ++_revealRevision,
        );
      }

      if (navigation == Duration.zero) {
        reveal();
      } else {
        _scrollRevealTimer = Timer(navigation, reveal);
      }
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scrollRevealTimer?.cancel();
    _creationReveals.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = _DashboardScreenState._taskColumns(
        context,
        revealRequests: _creationReveals,
      );
      if (Theme.of(context).platform == TargetPlatform.android) {
        final identity = context.select<BoardsProvider, (String?, String?)>(
          (boards) => (boards.workspace.ownerId, boards.currentBoardId),
        );
        final boards = context.read<BoardsProvider>();
        return AndroidBoardCarousel(
          key: ValueKey(identity),
          columns: columns,
          initialColumn: boards.currentColumnIndex,
          controller: _carousel,
          onColumnChanged: (column) {
            // A cancelled gesture from an outgoing surface belongs to its owner.
            if (boards.workspace.ownerId == identity.$1 &&
                boards.currentBoardId == identity.$2) {
              boards.selectColumn(column);
            }
          },
          onAdd: widget.onAdd,
        );
      }
      if (MediaQuery.sizeOf(context).width < 850 &&
          usesTouchControls(context)) {
        return _TouchColumns(
          columns: columns,
          initialColumn: context.read<BoardsProvider>().currentColumnIndex,
          controller: _touchColumns,
        );
      }
      final width = constraints.maxWidth < 900 ? 900.0 : constraints.maxWidth;
      final overflow = width > constraints.maxWidth;
      return ScrollbarTheme(
        data: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(AppColors.textTertiary),
        ),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: overflow,
          trackVisibility: overflow,
          notificationPredicate: (notice) => notice.depth == 0,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  constraints.maxHeight < 300 ? 12 : 80,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: columns[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Wide touch columns snap into place while revealing the next page.
class _TouchColumnsController {
  _TouchColumnsState? _state;

  void selectColumn(int index) => _state?._select(index);
}

class _TouchColumns extends StatefulWidget {
  final List<Widget> columns;
  final int initialColumn;
  final _TouchColumnsController? controller;

  const _TouchColumns({
    required this.columns,
    required this.initialColumn,
    this.controller,
  });

  @override
  State<_TouchColumns> createState() => _TouchColumnsState();
}

class _TouchColumnsState extends State<_TouchColumns> {
  late final _controller = PageController(
    viewportFraction: 0.92,
    initialPage: widget.initialColumn.clamp(0, 2).toInt(),
  );

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(covariant _TouchColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (identical(oldWidget.controller?._state, this)) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  void _select(int index) {
    if (!_controller.hasClients) return;
    final destination = index.clamp(0, 2).toInt();
    _controller.animateToPage(
      destination,
      duration: AppMotion.duration(context, AppMotion.normal),
      curve: AppMotion.curve,
    );
  }

  @override
  void dispose() {
    if (identical(widget.controller?._state, this)) {
      widget.controller?._state = null;
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView(
    controller: _controller,
    children: [
      for (final column in widget.columns)
        Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 80), child: column),
    ],
  );
}
