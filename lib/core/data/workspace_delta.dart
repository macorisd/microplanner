import 'workspace_limits.dart';
import 'workspace_snapshot.dart';

/// A replayable, entity-scoped change. Untouched fields from newer cloud data
/// survive; an overlapping edit or a changed deletion target is a conflict.
class WorkspaceDelta {
  static const kinds = ['boards', 'subjects', 'tasks'];
  final List<WorkspaceDeltaItem> items;
  const WorkspaceDelta(this.items);

  factory WorkspaceDelta.between(
    WorkspaceSnapshot before,
    WorkspaceSnapshot after,
  ) {
    final oldData = before.data;
    final newData = after.data;
    final changes = <WorkspaceDeltaItem>[];
    for (final kind in kinds) {
      final oldRows = _rows(oldData[kind]);
      final newRows = _rows(newData[kind]);
      final oldById = {for (final row in oldRows) row['id'] as String: row};
      final newById = {for (final row in newRows) row['id'] as String: row};
      for (final id in {...oldById.keys, ...newById.keys}) {
        final old = oldById[id];
        final next = newById[id];
        if (old == null || next == null || !_equal(old, next)) {
          changes.add(WorkspaceDeltaItem(kind, id, old, next));
        }
      }
    }
    return WorkspaceDelta(List.unmodifiable(changes));
  }

  factory WorkspaceDelta.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List || raw.length > 13300) {
      throw const FormatException('Invalid operation items');
    }
    final items = <WorkspaceDeltaItem>[];
    final seen = <String>{};
    for (final value in raw) {
      final item = WorkspaceDeltaItem.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (!kinds.contains(item.kind) ||
          item.id.isEmpty ||
          item.id.length > 150 ||
          (item.before == null && item.after == null) ||
          (item.before != null && item.before!['id'] != item.id) ||
          (item.after != null && item.after!['id'] != item.id) ||
          !seen.add('${item.kind}:${item.id}')) {
        throw const FormatException('Invalid operation item');
      }
      items.add(item);
    }
    return WorkspaceDelta(List.unmodifiable(items));
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
  };

  /// Returns null when rebasing would overwrite an independently changed field.
  WorkspaceSnapshot? apply(WorkspaceSnapshot current) {
    final result = current.toJson();
    final lists = {for (final kind in kinds) kind: _rows(result[kind])};
    final indexes = {
      for (final kind in kinds)
        kind: {for (final row in lists[kind]!) row['id'] as String: row},
    };
    final order = {
      for (final kind in kinds)
        kind: [for (final row in lists[kind]!) row['id'] as String],
    };
    for (final item in items) {
      final index = indexes[item.kind];
      if (index == null) return null;
      final currentRow = index[item.id];
      final old = item.before;
      final next = item.after;
      if (old == null && next != null) {
        if (currentRow == null) {
          index[item.id] = Map.of(next);
          order[item.kind]!.add(item.id);
        } else if (!_equal(currentRow, next)) {
          return null;
        }
      } else if (old != null && next == null) {
        if (currentRow != null) {
          if (!_equal(currentRow, old)) return null;
          index.remove(item.id);
        }
      } else if (old != null && next != null) {
        if (currentRow == null) return null;
        final updated = Map<String, dynamic>.of(currentRow);
        for (final key in {...old.keys, ...next.keys}) {
          if (old[key] == next[key]) continue;
          if (updated[key] != old[key] && updated[key] != next[key]) {
            return null;
          }
          if (next.containsKey(key)) {
            updated[key] = next[key];
          } else {
            updated.remove(key);
          }
        }
        index[item.id] = updated;
      } else {
        return null;
      }
    }
    for (final kind in kinds) {
      final rows = indexes[kind]!;
      result[kind] = [
        for (final id in order[kind]!)
          if (rows.containsKey(id)) rows[id]!,
      ];
    }
    try {
      final snapshot = WorkspaceSnapshot.fromJson(result);
      return WorkspaceLimits.validate(snapshot) == null ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _rows(Object? value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  static bool _equal(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a.length == b.length &&
      a.keys.every((key) => b.containsKey(key) && a[key] == b[key]);
}

class WorkspaceDeltaItem {
  final String kind;
  final String id;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  const WorkspaceDeltaItem(this.kind, this.id, this.before, this.after);
  factory WorkspaceDeltaItem.fromJson(Map<String, dynamic> json) =>
      WorkspaceDeltaItem(
        json['kind'] as String,
        json['id'] as String,
        json['before'] == null
            ? null
            : Map<String, dynamic>.from(json['before'] as Map),
        json['after'] == null
            ? null
            : Map<String, dynamic>.from(json['after'] as Map),
      );
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'before': before,
    'after': after,
  };
}
