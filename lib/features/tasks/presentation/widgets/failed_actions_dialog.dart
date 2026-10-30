import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/data/workspace_delta.dart';
import '../../../../core/data/workspace_operation.dart';
import '../../../../core/data/workspace_snapshot.dart';
import '../../data/models/task.dart';
import '../../providers/tasks_provider.dart';
import 'add_task_dialog.dart';
import 'edit_task_dialog.dart';
import 'new_board_dialog.dart';
import 'subject_dialog.dart';

/// The journal is the source of truth, so independent failures remain visible
/// until the user reviews or explicitly discards each one.
class FailedActionsDialog extends StatelessWidget {
  final String owner;
  const FailedActionsDialog({super.key, required this.owner});

  Task? _draft(WorkspaceOperation operation) {
    if (operation.delta.items.length != 1) return null;
    final items = operation.delta.items
        .where((item) => item.kind == 'tasks' && item.after != null)
        .toList();
    if (items.length != 1) return null;
    final item = items.single;
    if (item.before != null &&
        ![
          'name',
          'description',
          'deadline',
          'typeIndex',
          'priorityIndex',
          'subjectId',
        ].any((key) => item.before![key] != item.after![key])) {
      return null;
    }
    try {
      return WorkspaceSnapshot.fromJson({
        'boards': [],
        'subjects': [],
        'tasks': [items.single.after],
      }).tasks.single;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _row(
    WorkspaceSnapshot snapshot,
    String kind,
    String id,
  ) {
    final rows = snapshot.data[kind] as List;
    return rows
        .cast<Map<String, dynamic>>()
        .where((row) => row['id'] == id)
        .firstOrNull;
  }

  Map<String, dynamic> _mergeDraft(
    WorkspaceDeltaItem item,
    Map<String, dynamic>? current,
  ) {
    if (current == null || item.before == null) return Map.of(item.after!);
    final result = Map<String, dynamic>.of(current);
    for (final key in item.after!.keys) {
      if (item.before![key] != item.after![key]) result[key] = item.after![key];
    }
    return result;
  }

  void _editDraft(
    BuildContext context,
    WorkspaceController workspace,
    WorkspaceOperation operation,
  ) {
    final queue = workspace.outbox;
    final draft = _draft(operation);
    if (queue == null || draft == null || workspace.ownerId != owner) return;
    final current = queue.projected.tasks
        .where((item) => item.id == draft.id)
        .firstOrNull;
    final original = operation.delta.items.firstWhere(
      (item) => item.kind == 'tasks' && item.id == draft.id,
    );
    if (original.before != null && current == null) return;
    final reviewedDraft = current == null
        ? draft
        : WorkspaceSnapshot.fromJson({
            'boards': [],
            'subjects': [],
            'tasks': [
              _mergeDraft(original, _row(queue.projected, 'tasks', draft.id)),
            ],
          }).tasks.single;

    Future<bool> save(Task updated) {
      if (workspace.ownerId != owner ||
          !workspace.canWrite ||
          !identical(workspace.outbox, queue)) {
        return Future.value(false);
      }
      final before = queue.projected;
      final existing = before.tasks
          .where((task) => task.id == reviewedDraft.id)
          .firstOrNull;
      if ((original.before != null && existing == null) ||
          (original.before == null && existing != null)) {
        return Future.value(false);
      }
      final base = current == null
          ? before
          : before.copyWith(
              tasks: [
                ...before.tasks.where((task) => task.id != reviewedDraft.id),
                current,
              ],
            );
      final after = base.copyWith(
        tasks: [
          ...base.tasks.where((task) => task.id != reviewedDraft.id),
          updated,
        ],
      );
      return queue.replaceFailure(
        operation.id,
        WorkspaceDelta.between(base, after),
      );
    }

    showDialog<void>(
      context: context,
      builder: (_) => current == null
          ? AddTaskDialog(
              draft: reviewedDraft,
              onSave:
                  ({
                    required name,
                    required deadline,
                    required type,
                    required priority,
                    subjectId,
                    description,
                  }) => save(
                    reviewedDraft.copyWith(
                      name: name,
                      deadline: deadline,
                      type: type,
                      priority: priority,
                      subjectId: subjectId,
                      description: description,
                    ),
                  ),
            )
          : EditTaskDialog(task: current, draft: reviewedDraft, onSave: save),
    );
  }

  void _editNamedDraft(
    BuildContext context,
    WorkspaceController workspace,
    WorkspaceOperation operation,
    WorkspaceDeltaItem item,
  ) {
    final queue = workspace.outbox;
    if (queue == null || item.after == null || workspace.ownerId != owner) {
      return;
    }
    final current = _row(queue.projected, item.kind, item.id);
    if ((item.before == null && current != null) ||
        (item.before != null && current == null)) {
      return;
    }
    final draft = _mergeDraft(item, current);
    Future<bool> save(String? name, [int? color]) {
      if (!workspace.canWrite ||
          workspace.ownerId != owner ||
          !identical(queue, workspace.outbox)) {
        return Future.value(false);
      }
      final updated = Map<String, dynamic>.of(draft)..['name'] = name;
      if (color != null) updated['color'] = color;
      return queue.replaceFailure(
        operation.id,
        WorkspaceDelta([
          WorkspaceDeltaItem(item.kind, item.id, current, updated),
        ]),
      );
    }

    showDialog<void>(
      context: context,
      builder: (_) => item.kind == 'boards'
          ? NewBoardDialog(
              initialName: draft['name'] as String,
              onSave: (name) => save(name ?? draft['name'] as String),
            )
          : SubjectDialog(
              title: 'Review Subject',
              initialName: draft['name'] as String,
              initialColor: draft['color'] as int,
              allowUnchanged: true,
              onSave: (name, color) => save(name, color),
            ),
    );
  }

  Future<void> _discard(
    BuildContext context,
    WorkspaceController workspace,
    WorkspaceOperation operation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard saved draft?'),
        content: const Text(
          'This removes the saved action and its draft from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && workspace.ownerId == owner) {
      await workspace.outbox?.discardFailure(operation.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final taskTransitions = context.watch<TasksProvider?>()?.transitions;
    final queue = workspace.ownerId == owner ? workspace.outbox : null;
    final failed =
        queue?.operations.where((item) => item.failure != null).toList() ?? [];
    return AlertDialog(
      title: const Text('Actions needing attention'),
      content: SizedBox(
        width: 520,
        child: failed.isEmpty
            ? const Text('No actions need attention.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: failed.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final operation = failed[index];
                  final taskBusy = operation.delta.items.any(
                    (item) =>
                        item.kind == 'tasks' &&
                        ((taskTransitions?.locked(item.id) ?? false) ||
                            (queue?.pendingTaskIds.contains(item.id) ?? false)),
                  );
                  final item = operation.delta.items.firstOrNull;
                  final name =
                      (item?.after?['name'] ?? item?.before?['name'])
                          as String?;
                  final draft = _draft(operation);
                  final namedItem =
                      operation.delta.items.length == 1 &&
                          item?.after != null &&
                          (item?.kind == 'boards' || item?.kind == 'subjects')
                      ? item
                      : null;
                  final namedCurrent = namedItem == null
                      ? null
                      : _row(queue!.projected, namedItem.kind, namedItem.id);
                  final editableName =
                      namedItem != null &&
                      ((namedItem.before == null && namedCurrent == null) ||
                          (namedItem.before != null && namedCurrent != null));
                  final current = draft == null
                      ? null
                      : queue!.projected.tasks
                            .where((task) => task.id == draft.id)
                            .firstOrNull;
                  final taskItem = draft == null
                      ? null
                      : operation.delta.items.firstWhere(
                          (item) => item.kind == 'tasks' && item.id == draft.id,
                        );
                  final editable =
                      draft != null &&
                      ((taskItem!.before == null && current == null) ||
                          (taskItem.before != null && current != null));
                  final canRetry =
                      workspace.canWrite &&
                      !taskBusy &&
                      (operation.sourceId != null ||
                          operation.delta.apply(queue!.projected) != null);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ??
                            (operation.sourceId != null
                                ? 'Import local data'
                                : 'Workspace action'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(operation.failure!),
                      if (draft != null && (!editable || !workspace.canWrite))
                        SelectableText(
                          'Saved draft: ${draft.name}\n${draft.description ?? ''}',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (editable)
                            TextButton(
                              onPressed: workspace.canWrite && !taskBusy
                                  ? () => _editDraft(
                                      context,
                                      workspace,
                                      operation,
                                    )
                                  : null,
                              child: const Text('Review draft'),
                            ),
                          if (editableName)
                            TextButton(
                              onPressed: workspace.canWrite
                                  ? () => _editNamedDraft(
                                      context,
                                      workspace,
                                      operation,
                                      namedItem,
                                    )
                                  : null,
                              child: const Text('Review draft'),
                            ),
                          TextButton(
                            onPressed: canRetry
                                ? () {
                                    unawaited(queue!.retry(operation.id));
                                  }
                                : null,
                            child: const Text('Retry'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _discard(context, workspace, operation),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        if (queue?.storageError != null)
          TextButton(
            onPressed: workspace.repairStorage,
            child: const Text('Retry local storage'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
