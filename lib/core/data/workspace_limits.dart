import 'dart:convert';
import 'workspace_snapshot.dart';

/// Keep these limits aligned with server/src/domain.ts.
class WorkspaceLimits {
  WorkspaceLimits._();
  static const name = 300;
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

  static String? descriptionError(String? value) =>
      (value?.length ?? 0) > description
      ? 'Use at most $description characters.'
      : null;

  static bool validDate(DateTime date) =>
      date.year >= 1 &&
      date.year <= 9999 &&
      date.toUtc().year >= 1 &&
      date.toUtc().year <= 9999;

  static String? validate(WorkspaceSnapshot data) {
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
    final boardIds = <String>{};
    final subjectBoards = <String, String>{};
    final taskIds = <String>{};
    for (final board in data.boards) {
      if (!_id.hasMatch(board.id) ||
          !boardIds.add(board.id) ||
          board.sortOrder < 0 ||
          board.sortOrder > 9007199254740991 ||
          !validDate(board.createdAt)) {
        return 'Invalid board data. Refresh and try again.';
      }
      final error = nameError(board.name);
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
    }
    for (final task in data.tasks) {
      if (!_id.hasMatch(task.id) ||
          !taskIds.add(task.id) ||
          !boardIds.contains(task.boardId) ||
          (task.subjectId != null &&
              subjectBoards[task.subjectId] != task.boardId) ||
          task.typeIndex < 0 ||
          task.typeIndex > 6 ||
          task.priorityIndex < 0 ||
          task.priorityIndex > 2 ||
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
}
