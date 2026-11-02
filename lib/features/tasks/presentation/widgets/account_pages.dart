import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/data/workspace_controller.dart';
import '../../../../core/data/workspace_delta.dart';
import '../../../auth/data/auth_service.dart';
import '../../../boards/data/models/board_task_type.dart';
import '../../../boards/data/type_list_replacement.dart';
import 'category_editor.dart';
import '../../../../core/widgets/pending_action.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.onSettings});
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Profile',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 36,
                foregroundImage: user.photoUrl == null
                    ? null
                    : NetworkImage(user.photoUrl!),
                child: Text(
                  user.displayName.isEmpty
                      ? '?'
                      : user.displayName[0].toUpperCase(),
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
              const SizedBox(height: 32),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onSettings,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: auth.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
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

  Future<void> _edit([TaskTypeList? original]) async {
    final workspace = context.read<WorkspaceController>();
    if (!workspace.canWrite) return;
    final owner = workspace.ownerId;
    final token = workspace.auth.token;
    final base = (workspace.outbox?.projected ?? workspace.snapshot).clone();
    await showDialog<void>(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () {
                      if (_page == 0) {
                        widget.onBack();
                      } else {
                        setState(() => _page--);
                      }
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_page == 0)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.brush_outlined),
                    title: const Text('Customization'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _page = 1),
                  ),
                ),
              if (_page == 1)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Boards'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _page = 2),
                  ),
                ),
              if (_page == 2)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.list_alt_rounded),
                    title: const Text('Default lists of task types'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _page = 3),
                  ),
                ),
              if (_page == 3) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: workspace.canWrite ? () => _edit() : null,
                    icon: const Icon(Icons.add),
                    label: const Text('New list'),
                  ),
                ),
                if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No default lists yet.'),
                  ),
                for (final list in lists)
                  Card(
                    child: ListTile(
                      title: Text(list.name),
                      subtitle: Text(
                        '${list.types.length} ${list.types.length == 1 ? 'type' : 'types'}',
                      ),
                      onTap: workspace.canWrite ? () => _edit(list) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit list',
                            onPressed: workspace.canWrite
                                ? () => _edit(list)
                                : null,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete list',
                            onPressed: workspace.canWrite
                                ? () => _delete(list)
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
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
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.original?.name ?? '');
    _types = [
      for (final type in widget.original?.types ?? const <TypeListEntry>[])
        CategoryDraft(id: const Uuid().v4(), name: type.name, icon: type.icon),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PendingForm(
    pending: _saving,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.original == null
                    ? 'New default list'
                    : 'Edit default list',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'List name',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              EditableCategoryList(
                title: 'Task types',
                label: 'task type',
                useIcon: true,
                isTemplate: true,
                items: _types,
                onChanged: (value) => setState(() => _types = value),
              ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final name = _name.text.trim();
                            if (name.isEmpty || name.length > 50) {
                              setState(
                                () => _error = name.isEmpty
                                    ? 'Enter a name.'
                                    : 'Use at most 50 characters.',
                              );
                              return;
                            }
                            final result = TaskTypeList(
                              id: widget.original?.id ?? const Uuid().v4(),
                              name: name,
                              types: [
                                for (final type in _types)
                                  TypeListEntry(
                                    name: type.name,
                                    icon: type.icon,
                                  ),
                              ],
                            );
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            final saved = await submitOnce(
                              () => widget.onSave(result),
                            );
                            if (!mounted) return;
                            if (saved) {
                              closeForm();
                            } else {
                              setState(() {
                                _saving = false;
                                _error =
                                    submissionError ??
                                    'Could not save the list. Refresh and try again.';
                              });
                            }
                          },
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
