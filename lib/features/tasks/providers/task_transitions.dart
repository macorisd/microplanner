import 'dart:async';
import '../../../core/data/workspace_operation.dart';
import '../../../core/data/workspace_snapshot.dart';
import '../data/models/task.dart';

enum TaskColumnKind { completed, late, upcoming }

enum TaskTransitionPhase { source, destination, rollback, creating }

class TaskTransition {
  final String id;
  final String? operationId;
  final Task? before;
  Task? after;
  final TaskColumnKind? from;
  TaskColumnKind? to;
  final DateTime started;
  TaskTransitionPhase phase;
  DateTime phaseAt;
  bool confirmed;
  bool failed = false;

  TaskTransition({
    required this.id,
    required this.operationId,
    required this.before,
    required this.after,
    required this.from,
    required this.to,
    required this.started,
    required this.phase,
    this.confirmed = false,
  }) : phaseAt = started;
}

/// Tracks transitions independently of rendered rows, scroll position and page.
class TaskTransitions {
  static const baseDuration = Duration(milliseconds: 500);
  static const settleDuration = Duration(milliseconds: 380);
  final DateTime Function() now;
  final void Function() changed;
  final Map<String, TaskTransition> _items = {};
  Map<String, Task> _previous = {};
  DateTime? _previousAt;
  String? _owner;
  Timer? _timer;
  int revision = 0;

  TaskTransitions({required this.now, required this.changed});
  TaskTransition? operator [](String id) => _items[id];
  bool locked(String id) => _items.containsKey(id);

  void seed(String owner, List<Task> tasks, DateTime seenAt) {
    _timer?.cancel();
    _items.clear();
    _owner = owner;
    _previous = {for (final task in tasks) task.id: task};
    _previousAt = seenAt;
    revision++;
  }

  static TaskColumnKind column(Task task, DateTime at) => task.isCompleted
      ? TaskColumnKind.completed
      : at.isAfter(task.deadline)
      ? TaskColumnKind.late
      : TaskColumnKind.upcoming;

  static Task? _read(Map<String, dynamic>? row) {
    if (row == null) return null;
    try {
      return WorkspaceSnapshot.fromJson({
        'boards': [],
        'subjects': [],
        'tasks': [row],
      }).tasks.single;
    } catch (_) {
      return null;
    }
  }

  void update(
    String? owner,
    List<Task> tasks,
    List<WorkspaceOperation> operations,
  ) {
    final time = now();
    if (_owner != owner) {
      _timer?.cancel();
      _items.clear();
      _previous = {};
      _previousAt = null;
      _owner = owner;
      revision++;
    }
    final current = {for (final task in tasks) task.id: task};
    final byOperation = {
      for (final operation in operations) operation.id: operation,
    };
    final taskOperations = <String>{};
    for (final operation in operations) {
      for (final item in operation.delta.items.where(
        (item) => item.kind == 'tasks',
      )) {
        taskOperations.add(item.id);
        if (operation.failure != null || _items.containsKey(item.id)) continue;
        final before = _previous[item.id] ?? _read(item.before);
        final after = _read(item.after);
        final from = before == null ? null : column(before, time);
        final to = after == null ? null : column(after, time);
        if (before != null &&
            after != null &&
            from == to &&
            before.boardId == after.boardId) {
          continue;
        }
        _items[item.id] = TaskTransition(
          id: item.id,
          operationId: operation.id,
          before: before,
          after: after,
          from: from,
          to: to,
          started: time,
          phase: before == null
              ? TaskTransitionPhase.creating
              : TaskTransitionPhase.source,
        );
        revision++;
      }
    }
    for (final transition in _items.values.toList()) {
      if (transition.operationId == null) continue;
      final operation = byOperation[transition.operationId];
      if (operation?.failure != null && !transition.failed) {
        transition.failed = true;
        revision++;
      } else if (operation == null &&
          !transition.confirmed &&
          !transition.failed &&
          transition.phase != TaskTransitionPhase.rollback) {
        transition.confirmed = true;
        // A receipt retry can return a newer workspace than the original
        // response; present the authoritative state, not a stale target.
        transition.after = current[transition.id];
        transition.to = transition.after == null
            ? null
            : column(transition.after!, time);
        revision++;
      }
    }
    // Changes from a refresh or elapsed deadline have no request to await.
    if (_previousAt != null) {
      for (final entry in _previous.entries) {
        final old = entry.value;
        final next = current[entry.key];
        if (_items.containsKey(entry.key) ||
            taskOperations.contains(entry.key)) {
          continue;
        }
        final from = column(old, _previousAt!);
        final to = next == null ? null : column(next, time);
        if (next == null || from != to || old.boardId != next.boardId) {
          _items[entry.key] = TaskTransition(
            id: entry.key,
            operationId: null,
            before: old,
            after: next,
            from: from,
            to: to,
            started: time,
            phase: TaskTransitionPhase.source,
            confirmed: true,
          );
          revision++;
        }
      }
    }
    _previous = current;
    _previousAt = time;
    _advance(time);
  }

  void _advance(DateTime time) {
    for (final entry in _items.entries.toList()) {
      final t = entry.value;
      final elapsed = time.difference(t.phaseAt);
      if (t.phase == TaskTransitionPhase.rollback &&
          elapsed >= settleDuration) {
        _items.remove(entry.key);
        revision++;
      } else if ((t.phase == TaskTransitionPhase.source ||
              t.phase == TaskTransitionPhase.creating) &&
          (t.confirmed || t.failed) &&
          time.difference(t.started) >= baseDuration) {
        if (t.failed) {
          t.phase = TaskTransitionPhase.rollback;
          t.phaseAt = time;
          revision++;
        } else if (t.after == null) {
          _items.remove(entry.key);
          revision++;
        } else {
          t.phase = TaskTransitionPhase.destination;
          t.phaseAt = time;
          revision++;
        }
      } else if (t.phase == TaskTransitionPhase.destination &&
          elapsed >= settleDuration) {
        _items.remove(entry.key);
        revision++;
      }
    }
    _timer?.cancel();
    Duration? next;
    for (final t in _items.values) {
      DateTime? deadline;
      if (t.phase == TaskTransitionPhase.rollback ||
          t.phase == TaskTransitionPhase.destination) {
        deadline = t.phaseAt.add(settleDuration);
      } else if (t.confirmed || t.failed) {
        deadline = t.started.add(baseDuration);
      }
      if (deadline == null) continue;
      final remaining = deadline.difference(time);
      final delay = remaining.isNegative ? Duration.zero : remaining;
      if (next == null || delay < next) next = delay;
    }
    if (next != null) {
      _timer = Timer(next + const Duration(milliseconds: 1), () {
        _advance(now());
        changed();
      });
    }
  }

  List<Task> present(List<Task> current) {
    final result = {for (final task in current) task.id: task};
    for (final transition in _items.values) {
      if (transition.phase == TaskTransitionPhase.source ||
          transition.phase == TaskTransitionPhase.rollback) {
        if (transition.before != null) {
          result[transition.id] = transition.before!;
        } else if (transition.after != null) {
          result[transition.id] = transition.after!;
        } else {
          result.remove(transition.id);
        }
      } else if (transition.phase == TaskTransitionPhase.creating &&
          transition.after != null) {
        result[transition.id] = transition.after!;
      }
    }
    return result.values.toList();
  }

  TaskColumnKind displayedColumn(Task task, DateTime time) {
    final t = _items[task.id];
    if ((t?.phase == TaskTransitionPhase.source ||
            t?.phase == TaskTransitionPhase.rollback) &&
        t?.from != null) {
      return t!.from!;
    }
    return column(task, time);
  }

  void dispose() {
    _timer?.cancel();
  }
}
