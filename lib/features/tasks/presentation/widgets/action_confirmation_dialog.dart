import 'package:flutter/material.dart';
import '../../../../core/widgets/pending_action.dart';
import 'save_status.dart';

class ActionConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<bool> Function() onConfirm;
  final String actionLabel;
  final String pendingLabel;
  final bool destructive;
  final ButtonStyle? confirmStyle;
  const ActionConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    required this.actionLabel,
    required this.pendingLabel,
    this.destructive = false,
    this.confirmStyle,
  });
  @override
  State<ActionConfirmationDialog> createState() =>
      _ActionConfirmationDialogState();
}

class _ActionConfirmationDialogState extends State<ActionConfirmationDialog>
    with PendingActionState<ActionConfirmationDialog> {
  Future<void> _delete() async {
    if (actionBlocked) return;
    if (await submitOnce(widget.onConfirm) && mounted) closeForm();
  }

  @override
  Widget build(BuildContext context) => PendingForm(
    pending: actionBlocked,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          SaveStatus(error: submissionError),
        ],
      ),
      actions: [
        TextButton(
          onPressed: actionBlocked ? null : closeForm,
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: actionBlocked ? null : _delete,
          autofocus: true,
          style:
              widget.confirmStyle ??
              (widget.destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    )
                  : null),
          child: Text(isSubmitting ? widget.pendingLabel : widget.actionLabel),
        ),
      ],
    ),
  );
}
