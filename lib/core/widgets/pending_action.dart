import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/workspace_controller.dart';

/// Guards both pointer and keyboard submissions before the first async gap.
mixin PendingActionState<T extends StatefulWidget> on State<T> {
  bool isSubmitting = false;
  String? submissionError;
  bool _closing = false;
  bool _accepting = false;
  bool _pickerOpen = false;
  bool get actionBlocked => isSubmitting || _accepting || _closing;
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
      final before = {
        for (final item in queue?.operations ?? [])
          item.id: item.failure != null,
      };
      final future = action();
      final accepted = queue?.operations
          .where(
            (item) =>
                !before.containsKey(item.id) ||
                (before[item.id] == true && item.failure == null),
          )
          .firstOrNull;
      if (queue != null &&
          accepted != null &&
          identical(queue, workspace?.outbox)) {
        // The cloud notice owns progress; briefly keep input locked while the
        // encrypted local write completes, before the route can be dismissed.
        future.catchError((Object _) => false);
        setState(() {
          isSubmitting = false;
          _accepting = true;
        });
        final stored = await queue.durable(accepted.id);
        _accepting = false;
        if (!stored || !identical(queue, workspace?.outbox)) {
          if (mounted) {
            submissionError =
                'The action could not be stored on this device. Your draft is still here.';
          }
          return false;
        }
        saved = true;
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
        setState(() {
          isSubmitting = false;
          _accepting = false;
        });
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
