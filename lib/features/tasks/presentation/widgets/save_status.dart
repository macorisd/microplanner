import '../../../../core/theme/app_motion.dart';
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
    return AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.normal),
      alignment: Alignment.topLeft,
      child: MotionSwap(
        child: message == null
            ? const SizedBox.shrink(key: ValueKey('clear'))
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
      ),
    );
  }
}
