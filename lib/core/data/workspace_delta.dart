import 'workspace_limits.dart';
import 'workspace_snapshot.dart';

/// A replayable, entity-scoped change. Untouched fields from newer cloud data
/// survive; an overlapping edit or a changed deletion target is a conflict.
class WorkspaceDelta {
  static const kinds = [
    'boards',
    'subjects',
    'tasks',
    'boardTypes',
    'typeLists',
  ];
  final List<WorkspaceDeltaItem> items;
  const WorkspaceDelta(this.items);

  bool get reordersBoards => items.any(
    (item) =>
        item.kind == 'boards' &&
        item.before != null &&
        item.after != null &&
        item.before!['sortOrder'] != item.after!['sortOrder'],
  );

  /// Board editor saves can change only a board-local category list.
  Set<String> get savingBoardIds => {
    for (final item in items)
      if (item.kind == 'boards' &&
          item.after != null &&
          (item.before == null ||
              [
                'name',
                'icon',
                'color',
              ].any((key) => item.before![key] != item.after![key])))
        item.id
      else if (item.kind == 'subjects' || item.kind == 'boardTypes') ...{
        if (item.before?['boardId'] case final String id) id,
        if (item.after?['boardId'] case final String id) id,
      },
  };

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
    if (raw is! List || raw.length > 21100) {
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
          final added = Map<String, dynamic>.of(next);
          if (current.schemaVersion == 2 &&
              item.kind == 'tasks' &&
              !added.containsKey('typeId')) {
            final board = added['boardId'] as String;
            final legacyIndex = added['typeIndex'] as int;
            added['typeId'] = legacyIndex == 0
                ? null
                : WorkspaceSnapshot.legacyTypeId(board, legacyIndex);
          }
          if (current.schemaVersion == 2 &&
              item.kind == 'boards' &&
              !added.containsKey('icon')) {
            added['icon'] = 'board';
            added['color'] = 0xff7986cb;
            for (final type in WorkspaceSnapshot.defaultBoardTypes(item.id)) {
              if (indexes['boardTypes']!.containsKey(type.id)) return null;
              indexes['boardTypes']![type.id] = type.toJson();
              order['boardTypes']!.add(type.id);
            }
          }
          index[item.id] = added;
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
        if (current.schemaVersion == 2 &&
            item.kind == 'tasks' &&
            !old.containsKey('typeId') &&
            !next.containsKey('typeId') &&
            (old['typeIndex'] != next['typeIndex'] ||
                old['boardId'] != next['boardId'])) {
          String? mapped(Map<String, dynamic> row) {
            final legacyIndex = row['typeIndex'] as int;
            return legacyIndex == 0
                ? null
                : WorkspaceSnapshot.legacyTypeId(
                    row['boardId'] as String,
                    legacyIndex,
                  );
          }

          final previousType = mapped(old);
          final nextType = mapped(next);
          if (updated['typeId'] != previousType &&
              updated['typeId'] != nextType) {
            return null;
          }
          updated['typeId'] = nextType;
        }
        for (final key in {...old.keys, ...next.keys}) {
          if (_valueEqual(old[key], next[key])) continue;
          if (!_valueEqual(updated[key], old[key]) &&
              !_valueEqual(updated[key], next[key])) {
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
      return WorkspaceLimits.validate(snapshot, previous: current) == null
          ? snapshot
          : null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  static bool _equal(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _valueEqual(a, b);
  static bool _valueEqual(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(
            a.length,
            (i) => i,
          ).every((i) => _valueEqual(a[i], b[i]));
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _valueEqual(a[key], b[key]),
          );
    }
    return a == b;
  }
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
