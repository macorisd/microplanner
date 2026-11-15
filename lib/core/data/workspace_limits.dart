import 'dart:convert';
import 'workspace_snapshot.dart';

/// Keep these limits aligned with server/src/domain.ts.
class WorkspaceLimits {
  WorkspaceLimits._();
  static const name = 300;
  static const boardName = 50;
  static const categoryName = 50;
  static const categoriesPerBoard = 25;
  static const description = 20000;
  static const boards = 300;
  static const subjects = 3000;
  static const tasks = 10000;
  static const bytes = 4000000;
  static final _id = RegExp(r'^[\w-]{1,150}$');

  static String? nameError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter a name.';
    if (text.length > name) return 'Use at most $name characters.';
    return null;
  }

  static String? boardNameError(String? value) {
    final error = nameError(value);
    if (error != null) return error;
    return value!.trim().length > boardName
        ? 'Use at most $boardName characters.'
        : null;
  }

  static String nameKey(String value) => value.trim().toLowerCase();

  static String? namedItemError(
    String? value, {
    int limit = categoryName,
    String? originalName,
    Iterable<String> otherNames = const [],
    String kind = 'item',
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter a name.';
    if (text.length > limit && text != originalName?.trim()) {
      return 'Use at most $limit characters.';
    }
    if (nameKey(text) !=
            (originalName == null ? null : nameKey(originalName)) &&
        otherNames.any((name) => nameKey(name) == nameKey(text))) {
      return 'A $kind with this name already exists.';
    }
    return null;
  }

  /// Preserve legacy collisions only for the same entries and normalized names.
  static String? _duplicateError(
    Iterable<(String, String, String)> rows,
    Iterable<(String, String, String)> previous,
    String kind,
  ) {
    Map<(String, String), int> counts(
      Iterable<(String, String, String)> values,
    ) {
      final result = <(String, String), int>{};
      for (final (scope, _, name) in values) {
        final key = (scope, nameKey(name));
        result[key] = (result[key] ?? 0) + 1;
      }
      return result;
    }

    final old = counts(previous);
    final oldEntries = previous
        .map((row) => (row.$1, row.$2, nameKey(row.$3)))
        .toSet();
    final introduced = rows
        .where((row) => !oldEntries.contains((row.$1, row.$2, nameKey(row.$3))))
        .map((row) => (row.$1, nameKey(row.$3)))
        .toSet();
    for (final entry in counts(rows).entries) {
      if (entry.value > 1 &&
          (entry.value > (old[entry.key] ?? 0) ||
              introduced.contains(entry.key))) {
        return 'A $kind with this name already exists.';
      }
    }
    return null;
  }

  static String? descriptionError(String? value) =>
      (value?.length ?? 0) > description
      ? 'Use at most $description characters.'
      : null;

  static bool validDate(DateTime date) =>
      date.year >= 1 &&
      date.year <= 9999 &&
      date.toUtc().year >= 1 &&
      date.toUtc().year <= 9999;

  static String? validate(
    WorkspaceSnapshot data, {
    WorkspaceSnapshot? previous,
  }) {
    if (data.revision < 0 || data.revision >= 9007199254740991) {
      return 'Invalid workspace revision. Refresh and try again.';
    }
    if (data.boards.isEmpty) return 'Keep at least one board.';
    if (data.boards.length > boards) {
      return 'You can keep up to $boards boards.';
    }
    if (data.subjects.length > subjects) {
      return 'You can keep up to $subjects subjects.';
    }
    if (data.tasks.length > tasks) return 'You can keep up to $tasks tasks.';
    final advance = data.notificationPreferences?.advanceMinutes;
    if (advance != null && (advance < 1 || advance > 10080)) {
      return 'Choose a reminder from 1 minute to 7 days.';
    }
    final duplicate =
        _duplicateError(
          data.boards.map((item) => ('', item.id, item.name)),
          previous?.boards.map((item) => ('', item.id, item.name)) ?? const [],
          'board',
        ) ??
        _duplicateError(
          data.subjects.map((item) => (item.boardId, item.id, item.name)),
          previous?.subjects.map(
                (item) => (item.boardId, item.id, item.name),
              ) ??
              const [],
          'subject',
        ) ??
        _duplicateError(
          data.boardTypes.map((item) => (item.boardId, item.id, item.name)),
          previous?.boardTypes.map(
                (item) => (item.boardId, item.id, item.name),
              ) ??
              const [],
          'task type',
        ) ??
        _duplicateError(
          data.typeLists.expand(
            (list) => list.types.map(
              (item) => (list.id, nameKey(item.name), item.name),
            ),
          ),
          previous?.typeLists.expand(
                (list) => list.types.map(
                  (item) => (list.id, nameKey(item.name), item.name),
                ),
              ) ??
              const [],
          'task type',
        );
    if (duplicate != null) return duplicate;
    final boardIds = <String>{};
    final subjectBoards = <String, String>{};
    final typeBoards = <String, String>{};
    final taskIds = <String>{};
    for (final board in data.boards) {
      if (!_id.hasMatch(board.id) ||
          !boardIds.add(board.id) ||
          board.sortOrder < 0 ||
          board.sortOrder > 9007199254740991 ||
          !validDate(board.createdAt) ||
          (data.schemaVersion == 2 &&
              (board.color < 0 ||
                  board.color > 0xffffffff ||
                  !_validIcon(board.icon)))) {
        return 'Invalid board data. Refresh and try again.';
      }
      // Unchanged legacy names never block unrelated saves or get truncated.
      final unchanged =
          previous?.boards.any(
            (old) => old.id == board.id && old.name == board.name,
          ) ??
          false;
      final error = unchanged
          ? nameError(board.name)
          : boardNameError(board.name);
      if (error != null) return 'Board name: $error';
    }
    for (final subject in data.subjects) {
      if (!_id.hasMatch(subject.id) ||
          subjectBoards.containsKey(subject.id) ||
          !boardIds.contains(subject.boardId) ||
          subject.color < 0 ||
          subject.color > 0xffffffff) {
        return 'Invalid subject data. Refresh and try again.';
      }
      subjectBoards[subject.id] = subject.boardId;
      final error = nameError(subject.name);
      if (error != null) return 'Subject name: $error';
      if (data.schemaVersion == 2 &&
          subject.name.trim().length > categoryName &&
          !(previous?.subjects.any(
                (old) => old.id == subject.id && old.name == subject.name,
              ) ??
              false)) {
        return 'Subject name: Use at most $categoryName characters.';
      }
    }
    if (data.schemaVersion == 2) {
      final counts = <String, int>{};
      final previousCounts = <String, int>{};
      for (final subject in data.subjects) {
        counts[subject.boardId] = (counts[subject.boardId] ?? 0) + 1;
      }
      for (final subject in previous?.subjects ?? const []) {
        previousCounts[subject.boardId] =
            (previousCounts[subject.boardId] ?? 0) + 1;
      }
      for (final entry in counts.entries) {
        final old = previousCounts[entry.key] ?? 0;
        if (entry.value > categoriesPerBoard && entry.value > old) {
          return 'You can keep up to $categoriesPerBoard subjects per board.';
        }
      }
      final typeCounts = <String, int>{};
      for (final type in data.boardTypes) {
        if (!_id.hasMatch(type.id) ||
            typeBoards.containsKey(type.id) ||
            !boardIds.contains(type.boardId) ||
            !_validIcon(type.icon) ||
            type.sortOrder < 0 ||
            nameError(type.name) != null ||
            type.name.trim().length > categoryName) {
          return 'Invalid task type data.';
        }
        typeBoards[type.id] = type.boardId;
        typeCounts[type.boardId] = (typeCounts[type.boardId] ?? 0) + 1;
      }
      if (typeCounts.values.any((count) => count > categoriesPerBoard)) {
        return 'You can keep up to $categoriesPerBoard task types per board.';
      }
      final listIds = <String>{};
      if (data.typeLists.length > 300) return 'Too many default lists.';
      for (final list in data.typeLists) {
        if (!_id.hasMatch(list.id) ||
            !listIds.add(list.id) ||
            nameError(list.name) != null ||
            list.name.trim().length > categoryName ||
            list.types.length > categoriesPerBoard ||
            list.types.any(
              (type) =>
                  nameError(type.name) != null ||
                  type.name.trim().length > categoryName ||
                  !_validIcon(type.icon),
            )) {
          return 'Invalid default task type list.';
        }
      }
    }
    for (final task in data.tasks) {
      if (!_id.hasMatch(task.id) ||
          !taskIds.add(task.id) ||
          !boardIds.contains(task.boardId) ||
          (task.subjectId != null &&
              subjectBoards[task.subjectId] != task.boardId) ||
          (data.schemaVersion == 2 &&
              task.typeId != null &&
              typeBoards[task.typeId] != task.boardId) ||
          task.typeIndex < 0 ||
          task.typeIndex > 6 ||
          task.priorityIndex < 0 ||
          task.priorityIndex > 2 ||
          (task.reminderMinutes != null && (task.reminderMinutes! < 0 || task.reminderMinutes! > 10080)) ||
          !validDate(task.deadline) ||
          !validDate(task.createdAt)) {
        return 'Invalid task data. Refresh and try again.';
      }
      final error = nameError(task.name) ?? descriptionError(task.description);
      if (error != null) return 'Task: $error';
    }
    if (utf8
            .encode(jsonEncode({...data.data, 'revision': data.revision + 1}))
            .length >
        bytes) {
      return 'The workspace is too large. Reduce its size before saving.';
    }
    return null;
  }

  static bool _validIcon(String value) =>
      value.length <= 50 && RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value);
}
