import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/workspace_controller.dart';

/// Guards both pointer and keyboard submissions before the first async gap.
mixin PendingActionState<T extends StatefulWidget> on State<T> {
  bool isSubmitting = false;
  String? submissionError;
  bool _closing = false;
  bool _pickerOpen = false;
  bool get actionBlocked => isSubmitting || _closing;
  Future<R?> pickOnce<R>(Future<R?> Function() open) async {
    if (actionBlocked || _pickerOpen) return null;
    _pickerOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      return await open();
    } finally {
      _pickerOpen = false;
    }
  }

  void closeForm() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.pop(context);
  }

  Future<bool> submitOnce(
    Future<bool> Function() action, {
    bool lockAfterSuccess = true,
  }) async {
    if (actionBlocked) return false;
    setState(() {
      isSubmitting = true;
      submissionError = null;
    });
    var saved = false;
    try {
      final workspace = context.read<WorkspaceController?>();
      final queue = workspace?.outbox;
      final before = queue?.operations.length;
      final failedBefore = queue?.operations
          .where((item) => item.failure != null)
          .length;
      final future = action();
      // Only dismiss after an intent has actually been accepted into the
      // account-scoped queue. Validation failures keep the form open.
      if (queue != null &&
          identical(queue, workspace?.outbox) &&
          (queue.operations.length > before! ||
              queue.operations.where((item) => item.failure != null).length <
                  failedBefore!)) {
        saved = true;
        // The route is about to close; do not show its old inline spinner
        // during the exit animation. The cloud notice owns progress now.
        isSubmitting = false;
        future.catchError((Object _) => false);
        return true;
      }
      saved = await future;
      if (!saved && mounted) {
        submissionError =
            'The action could not be completed. Please try again.';
      }
      return saved;
    } catch (_) {
      if (mounted) {
        submissionError =
            'The action could not be completed. Please try again.';
      }
      return false;
    } finally {
      if (mounted && (!saved || !lockAfterSuccess)) {
        setState(() => isSubmitting = false);
      }
    }
  }
}

/// Keep the submitted values and route stable until the result is known.
class PendingForm extends StatelessWidget {
  final bool pending;
  final Widget child;
  const PendingForm({super.key, required this.pending, required this.child});
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !pending,
    child: ExcludeFocus(
      excluding: pending,
      child: AbsorbPointer(absorbing: pending, child: child),
    ),
  );
}
