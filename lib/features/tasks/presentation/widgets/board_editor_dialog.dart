import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/data/workspace_controller.dart';
import '../../../../core/data/workspace_delta.dart';
import '../../../../core/data/workspace_snapshot.dart';
import '../../../boards/data/board_catalog.dart';
import '../../../boards/data/models/board.dart';
import '../../../boards/data/models/board_task_type.dart';
import '../../../boards/data/models/subject.dart';
import '../../../boards/data/type_list_replacement.dart';
import 'category_editor.dart';
import '../../../../core/widgets/pending_action.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/limited_text_field.dart';
import 'editor_panel.dart';

class BoardEditorDialog extends StatefulWidget {
  const BoardEditorDialog({super.key, required this.board});
  final Board board;
  @override
  State<BoardEditorDialog> createState() => _BoardEditorDialogState();
}

class _BoardEditorDialogState extends State<BoardEditorDialog>
    with PendingActionState<BoardEditorDialog> {
  late final WorkspaceSnapshot _base;
  late final Board _originalBoard;
  late final String? _owner;
  late final String? _token;
  late final TextEditingController _name;
  late String _icon;
  late int _color;
  late List<CategoryDraft> _subjects;
  late List<CategoryDraft> _types;
  late final List<CategoryDraft> _initialSubjects;
  late final List<CategoryDraft> _initialTypes;
  bool _saving = false;
  String? _error;

  bool get _hasChanges =>
      _name.text.trim() != _originalBoard.name ||
      _icon != _originalBoard.icon ||
      _color != _originalBoard.color ||
      !sameCategories(_subjects, _initialSubjects) ||
      !sameCategories(_types, _initialTypes);
  bool get _canSave =>
      !_saving &&
      _hasChanges &&
      _name.text.trim().isNotEmpty &&
      (_name.text.trim().length <= WorkspaceLimits.boardName ||
          _name.text.trim() == _originalBoard.name);

  @override
  void initState() {
    super.initState();
    final workspace = context.read<WorkspaceController>();
    _base = (workspace.outbox?.projected ?? workspace.snapshot)
        .clone()
        .upgraded();
    _originalBoard =
        _base.boards
            .where((board) => board.id == widget.board.id)
            .firstOrNull ??
        widget.board;
    _owner = workspace.ownerId;
    _token = workspace.auth.token;
    _name = TextEditingController(text: _originalBoard.name)
      ..addListener(() => setState(() => _error = null));
    _icon = _originalBoard.icon;
    _color = _originalBoard.color;
    final subjects =
        _base.subjects.where((item) => item.boardId == widget.board.id).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _subjects = [
      for (final item in subjects)
        CategoryDraft(id: item.id, name: item.name, color: item.color),
    ];
    final types =
        _base.boardTypes
            .where((item) => item.boardId == widget.board.id)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _types = [
      for (final item in types)
        CategoryDraft(id: item.id, name: item.name, icon: item.icon),
    ];
    _initialSubjects = List.of(_subjects);
    _initialTypes = List.of(_types);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _applyList() async {
    final workspace = context.read<WorkspaceController>();
    final lists = (workspace.outbox?.projected ?? workspace.snapshot).typeLists;
    final selected = await pickOnce(
      () => showMotionDialog<TaskTypeList>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Apply a default list'),
          children: [
            if (lists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No default lists yet.'),
              ),
            for (final list in lists)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, list),
                child: Text(list.name),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final result = replaceTypeList(
      existing: [
        for (final type in _types)
          BoardTypeEntry(id: type.id, name: type.name, icon: type.icon),
      ],
      replacement: selected.types,
      newId: () => const Uuid().v4(),
    );
    setState(
      () => _types = [
        for (final type in result.types)
          CategoryDraft(id: type.id, name: type.name, icon: type.icon),
      ],
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final name = _name.text.trim();
    if (name.isEmpty || (name.length > 50 && name != _originalBoard.name)) {
      setState(
        () => _error = name.isEmpty
            ? 'Enter a board name.'
            : 'Use at most 50 characters.',
      );
      return;
    }
    final beforeSubjects = _base.subjects
        .where((item) => item.boardId == widget.board.id)
        .map((item) => item.id)
        .toSet();
    final beforeTypes = _base.boardTypes
        .where((item) => item.boardId == widget.board.id)
        .map((item) => item.id)
        .toSet();
    final removedSubjects = beforeSubjects.difference(
      _subjects.map((item) => item.id).toSet(),
    );
    final removedTypes = beforeTypes.difference(
      _types.map((item) => item.id).toSet(),
    );
    final subjectCount = _base.tasks
        .where(
          (task) =>
              task.subjectId != null &&
              removedSubjects.contains(task.subjectId),
        )
        .length;
    final typeCount = _base.tasks
        .where(
          (task) => task.typeId != null && removedTypes.contains(task.typeId),
        )
        .length;
    if (removedSubjects.isNotEmpty || removedTypes.isNotEmpty) {
      final confirm = await pickOnce(
        () => showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save list changes?'),
            content: Text(
              'Removing these entries will clear the subject from $subjectCount ${subjectCount == 1 ? 'task' : 'tasks'} and the task type from $typeCount ${typeCount == 1 ? 'task' : 'tasks'}.',
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
      );
      if (confirm != true || !mounted) return;
    }
    final workspace = context.read<WorkspaceController>();
    if (workspace.ownerId != _owner ||
        workspace.auth.token != _token ||
        !workspace.canWrite) {
      setState(
        () => _error =
            'Your account or connection changed. Refresh and try again.',
      );
      return;
    }
    final after = _base.copyWith(
      boards: [
        for (final board in _base.boards)
          if (board.id == widget.board.id)
            board.copyWith(name: name, icon: _icon, color: _color)
          else
            board,
      ],
      subjects: [
        ..._base.subjects.where((item) => item.boardId != widget.board.id),
        for (var i = 0; i < _subjects.length; i++)
          Subject(
            id: _subjects[i].id,
            name: _subjects[i].name,
            boardId: widget.board.id,
            color: _subjects[i].color,
            sortOrder: i,
          ),
      ],
      boardTypes: [
        ..._base.boardTypes.where((item) => item.boardId != widget.board.id),
        for (var i = 0; i < _types.length; i++)
          BoardTaskType(
            id: _types[i].id,
            name: _types[i].name,
            boardId: widget.board.id,
            icon: _types[i].icon,
            sortOrder: i,
          ),
      ],
      tasks: [
        for (final task in _base.tasks)
          task.copyWith(
            subjectId: removedSubjects.contains(task.subjectId)
                ? null
                : task.subjectId,
            typeId: removedTypes.contains(task.typeId) ? null : task.typeId,
          ),
      ],
    );
    final delta = WorkspaceDelta.between(_base, after);
    if (delta.items.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await submitOnce(() => workspace.applyDelta(delta));
    if (!mounted) return;
    if (saved) {
      closeForm();
    } else {
      setState(() {
        _saving = false;
        _error =
            submissionError ??
            workspace.error ??
            'Could not save changes. Refresh and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PendingForm(
    pending: _saving,
    child: EditorPanel(
      dialog: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorHeading(
            title: 'Edit Board',
            icon: Icons.dashboard_outlined,
            onClose: _saving ? null : closeForm,
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          LimitedTextField(
            controller: _name,
            limit: WorkspaceLimits.boardName,
            enabled: !_saving,
            validator: (_) => null,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Board name'),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          IconChoice(
            label: 'Board icon',
            labelStyle: Theme.of(context).textTheme.titleMedium,
            color: Color(_color),
            icon: boardIcons[_icon] ?? Icons.dashboard_rounded,
            onPressed: _saving
                ? null
                : () async {
                    final icon = await pickOnce(
                      () => chooseBoardIcon(context, _icon),
                    );
                    if (icon != null && mounted) setState(() => _icon = icon);
                  },
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Text('Board color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.spacingSmall),
          ColorChoices(
            color: _color,
            onChanged: (value) => setState(() => _color = value),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          EditableCategoryList(
            title: 'Subjects',
            label: 'subject',
            useIcon: false,
            items: _subjects,
            onChanged: (value) => setState(() => _subjects = value),
          ),
          const Divider(height: AppTheme.spacingLarge),
          EditableCategoryList(
            title: 'Task types',
            label: 'task type',
            useIcon: true,
            items: _types,
            onChanged: (value) => setState(() => _types = value),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _applyList,
              icon: const Icon(Icons.library_add_outlined, size: 20),
              label: const Text('Apply default list'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: AppTheme.spacingMedium),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: _saving ? null : closeForm,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _canSave ? _save : null,
                child: const Text('Save changes'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
