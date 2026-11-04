import '../../../../core/widgets/form_message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';

class SaveStatus extends StatelessWidget {
  final String? error;
  const SaveStatus({super.key, this.error});
  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final message = workspace.error ?? error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormMessage(message: message, lines: 2),
    );
  }
}
