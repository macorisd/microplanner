import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/data/workspace_controller.dart';
import '../../../../core/data/workspace_delta.dart';
import '../../../auth/data/auth_service.dart';
import '../../../boards/data/models/board_task_type.dart';
import '../../../boards/data/type_list_replacement.dart';
import 'category_editor.dart';
import '../../../../core/widgets/pending_action.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/data/workspace_limits.dart';
import 'editor_panel.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.onSettings, this.onBack});
  final VoidCallback onSettings;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    return EditorPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorHeading(
            title: 'Profile',
            icon: Icons.person_outline_rounded,
            onBack: onBack,
          ),
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primaryLight,
              foregroundImage: user.photoUrl == null
                  ? null
                  : NetworkImage(user.photoUrl!),
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName[0].toUpperCase(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            user.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(user.email, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SettingsEntry(
            title: 'Settings',
            icon: Icons.settings_outlined,
            onTap: onSettings,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: auth.signOut,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _page = 0;
  final _history = <LocalHistoryEntry>[];
  LocalHistoryEntry? _rootHistory;
  bool _disposing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rootHistory != null) return;
    _rootHistory = LocalHistoryEntry(
      onRemove: () {
        _rootHistory = null;
        if (mounted && !_disposing) widget.onBack();
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(_rootHistory!);
  }

  void _open(int page) {
    FocusManager.instance.primaryFocus?.unfocus();
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      onRemove: () {
        _history.remove(entry);
        if (mounted && !_disposing) setState(() => _page = page - 1);
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(entry);
    _history.add(entry);
    setState(() => _page = page);
  }

  void _back() {
    if (_history.isNotEmpty) {
      _history.last.remove();
    } else {
      _rootHistory?.remove();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    for (final entry in _history.toList()) {
      entry.remove();
    }
    _rootHistory?.remove();
    super.dispose();
  }

  Future<void> _edit([TaskTypeList? original]) async {
    final workspace = context.read<WorkspaceController>();
    if (!workspace.canWrite) return;
    final owner = workspace.ownerId;
    final token = workspace.auth.token;
    final base = (workspace.outbox?.projected ?? workspace.snapshot).clone();
    await showMotionDialog<void>(
      context: context,
      builder: (_) => _TypeListDialog(
        original: original,
        onSave: (result) async {
          if (workspace.ownerId != owner ||
              workspace.auth.token != token ||
              !workspace.canWrite) {
            return false;
          }
          final after = base.copyWith(
            typeLists: [
              for (final list in base.typeLists)
                if (list.id == result.id) result else list,
              if (original == null) result,
            ],
          );
          final delta = WorkspaceDelta.between(base, after);
          if (delta.items.isEmpty) return true;
          return workspace.applyDelta(delta);
        },
      ),
    );
  }

  Future<void> _delete(TaskTypeList list) async {
    final workspace = context.read<WorkspaceController>();
    if (!workspace.canWrite) return;
    final owner = workspace.ownerId;
    final token = workspace.auth.token;
    final base = (workspace.outbox?.projected ?? workspace.snapshot).clone();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete default list?'),
        content: Text(
          'Delete "${list.name}"? Boards that used this list will keep their own types.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        workspace.ownerId != owner ||
        workspace.auth.token != token) {
      return;
    }
    final after = base.copyWith(
      typeLists: base.typeLists.where((item) => item.id != list.id).toList(),
    );
    final saved = await workspace.applyDelta(
      WorkspaceDelta.between(base, after),
    );
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(workspace.error ?? 'Could not delete the list.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final lists = (workspace.outbox?.projected ?? workspace.snapshot).typeLists;
    final title = [
      'Settings',
      'Customization',
      'Boards',
      'Default lists of task types',
    ][_page];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: EditorPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorHeading(
              title: title,
              icon: Icons.settings_outlined,
              onBack: _back,
            ),
            const SizedBox(height: AppTheme.spacingLarge),
            MotionSwap(
              alignment: Alignment.topCenter,
              child: Column(
                key: ValueKey(_page),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_page == 0)
                    SettingsEntry(
                      title: 'Customization',
                      icon: Icons.brush_outlined,
                      onTap: () => _open(1),
                    ),
                  if (_page == 1)
                    SettingsEntry(
                      title: 'Boards',
                      icon: Icons.dashboard_outlined,
                      onTap: () => _open(2),
                    ),
                  if (_page == 2)
                    SettingsEntry(
                      title: 'Default lists of task types',
                      icon: Icons.list_alt_rounded,
                      onTap: () => _open(3),
                    ),
                  if (_page == 3) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: workspace.canWrite ? () => _edit() : null,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('New list'),
                      ),
                    ),
                    if (lists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No default lists yet.'),
                      ),
                    for (final list in lists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SettingsEntry(
                          title: list.name,
                          icon: Icons.list_alt_rounded,
                          subtitle:
                              '${list.types.length} ${list.types.length == 1 ? 'type' : 'types'}',
                          onTap: workspace.canWrite ? () => _edit(list) : null,
                          trailing: IconButton(
                            tooltip: 'Delete list',
                            onPressed: workspace.canWrite
                                ? () => _delete(list)
                                : null,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeListDialog extends StatefulWidget {
  const _TypeListDialog({this.original, required this.onSave});
  final TaskTypeList? original;
  final Future<bool> Function(TaskTypeList) onSave;
  @override
  State<_TypeListDialog> createState() => _TypeListDialogState();
}

class _TypeListDialogState extends State<_TypeListDialog>
    with PendingActionState<_TypeListDialog> {
  late final TextEditingController _name;
  late List<CategoryDraft> _types;
  late final List<CategoryDraft> _initialTypes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.original?.name ?? '')
      ..addListener(_changed);
    _types = [
      for (final type in widget.original?.types ?? const <TypeListEntry>[])
        CategoryDraft(id: const Uuid().v4(), name: type.name, icon: type.icon),
    ];
    _initialTypes = List.of(_types);
  }

  void _changed() => setState(() => _error = null);
  bool get _hasChanges =>
      widget.original == null ||
      _name.text.trim() != widget.original!.name ||
      !sameCategories(_types, _initialTypes);
  bool get _canSave =>
      !actionBlocked &&
      _hasChanges &&
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= WorkspaceLimits.categoryName;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final result = TaskTypeList(
      id: widget.original?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      types: [
        for (final type in _types)
          TypeListEntry(name: type.name, icon: type.icon),
      ],
    );
    final saved = await submitOnce(() => widget.onSave(result));
    if (!mounted) return;
    if (saved) {
      closeForm();
    } else {
      setState(
        () => _error =
            submissionError ??
            'Could not save the list. Refresh and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PendingForm(
    pending: actionBlocked,
    child: EditorPanel(
      dialog: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorHeading(
            title: widget.original == null
                ? 'New default list'
                : 'Edit default list',
            icon: Icons.list_alt_rounded,
            onClose: actionBlocked ? null : closeForm,
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          LimitedTextField(
            controller: _name,
            limit: WorkspaceLimits.categoryName,
            validator: (_) => _error,
            enabled: !actionBlocked,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'List name',
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          EditableCategoryList(
            title: 'Task types',
            label: 'task type',
            useIcon: true,
            isTemplate: true,
            items: _types,
            onChanged: (value) => setState(() => _types = value),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: actionBlocked ? null : closeForm,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _canSave ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
