import 'package:flutter/material.dart';
import 'save_status.dart';

class NewBoardDialog extends StatefulWidget {
  final Future<bool> Function(String? name) onSave;
  const NewBoardDialog({super.key, required this.onSave});
  @override
  State<NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<NewBoardDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final name = _controller.text.trim();
    final saved = await widget.onSave(name.isEmpty ? null : name);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('New Board'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
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
        const SaveStatus(),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Create'),
      ),
    ],
  );
}
