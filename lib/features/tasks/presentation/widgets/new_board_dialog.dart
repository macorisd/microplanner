import 'package:flutter/material.dart';
import 'save_status.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/pending_action.dart';

class NewBoardDialog extends StatefulWidget {
  final Future<bool> Function(String? name) onSave;
  const NewBoardDialog({super.key, required this.onSave});
  @override
  State<NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<NewBoardDialog>
    with PendingActionState<NewBoardDialog> {
  final _controller = TextEditingController();
  bool get _saving => actionBlocked;
  String? _nameError(String? value) =>
      (value?.trim().isEmpty ?? true) ? null : WorkspaceLimits.nameError(value);
  @override
  void initState() {
    super.initState();
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
    child: AlertDialog(
      scrollable: true,
      title: const Text('New Board'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LimitedTextField(
            limit: WorkspaceLimits.name,
            validator: _nameError,
            enabled: !_saving,
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Board name',
              hintText: 'Enter board name',
            ),
            onSubmitted: (_) {
              if (_controller.text.trim().isNotEmpty) _save();
            },
          ),
          SaveStatus(error: submissionError),
        ],
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
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
