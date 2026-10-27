import 'package:flutter/material.dart';

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
      saved = await action();
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
