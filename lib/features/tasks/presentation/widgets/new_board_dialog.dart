import 'form_dialog.dart';
import 'task_form_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/pending_action.dart';

class NewBoardDialog extends StatefulWidget {
  final Future<bool> Function(String? name) onSave;
  final String initialName;
  final bool creating;
  final String? originalBoardId;
  const NewBoardDialog({
    super.key,
    required this.onSave,
    this.initialName = '',
    this.creating = true,
    this.originalBoardId,
  });
  @override
  State<NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<NewBoardDialog>
    with PendingActionState<NewBoardDialog> {
  final _controller = TextEditingController();
  bool get _saving => actionBlocked;
  String? _nameError(String? value) => WorkspaceLimits.namedItemError(
    value,
    limit: WorkspaceLimits.boardName,
    originalName: widget.creating ? null : widget.initialName,
    otherNames:
        (context.read<WorkspaceController>().outbox?.projected ??
                context.read<WorkspaceController>().snapshot)
            .boards
            .where((board) => board.id != widget.originalBoardId)
            .map((board) => board.name),
    kind: 'board',
  );
  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialName;
    _controller.addListener(_textChanged);
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving || _nameError(_controller.text) != null) return;
    final name = _controller.text.trim();
    final saved = await submitOnce(
      () => widget.onSave(name.isEmpty ? null : name),
    );
    if (!mounted) return;
    if (saved) {
      closeForm();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PendingForm(
    pending: _saving,
    child: TaskFormKeyboard(
      canSubmit: !_saving && _nameError(_controller.text) == null,
      onSubmit: _save,
      child: FormDialog(
        title: Text(widget.creating ? 'New Board' : 'Edit Board'),
        content: LimitedTextField(
          limit: WorkspaceLimits.boardName,
          validator: _nameError,
          enabled: !_saving,
          controller: _controller,
          autofocus: widget.creating,
          validateOnBlur: true,
          errorText:
              context.watch<WorkspaceController>().error ?? submissionError,
          decoration: const InputDecoration(
            labelText: 'Board name',
            hintText: 'Enter board name',
          ),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : closeForm,
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || _nameError(_controller.text) != null
                ? null
                : _save,
            child: Text(widget.creating ? 'Create board' : 'Save changes'),
          ),
        ],
      ),
    ),
  );
}
