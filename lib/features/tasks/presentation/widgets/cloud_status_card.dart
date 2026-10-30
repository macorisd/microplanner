import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/animated_app_logo.dart';
import 'failed_actions_dialog.dart';

/// A single cloud notice layered over the workspace instead of taking its space.
class CloudStatusCard extends StatefulWidget {
  final WorkspaceController workspace;
  const CloudStatusCard({super.key, required this.workspace});

  @override
  State<CloudStatusCard> createState() => _CloudStatusCardState();
}

class _CloudStatusCardState extends State<CloudStatusCard> {
  Timer? _delay;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_changed);
    _update();
  }

  void _changed() {
    if (mounted) setState(_update);
  }

  void _update() {
    final workspace = widget.workspace;
    final busy = workspace.isLoading || workspace.isSaving;
    if (busy == _busy) return;
    _busy = busy;
    _delay?.cancel();
    _ready =
        busy &&
        (workspace.isSaving || !workspace.isOnline || workspace.error != null);
    if (busy && !_ready) {
      _delay = Timer(const Duration(milliseconds: 160), () {
        if (mounted && _busy) setState(() => _ready = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant CloudStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_changed);
      widget.workspace.addListener(_changed);
      _busy = false;
      _update();
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_changed);
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final busy = workspace.isLoading || workspace.isSaving;
    final hasFailures = workspace.outbox?.hasFailures ?? false;
    final failed =
        !busy &&
        (workspace.error != null || !workspace.isOnline || hasFailures);
    final visible = (busy && (_ready || hasFailures)) || failed;
    final title = workspace.isSaving
        ? 'Saving your changes'
        : busy
        ? 'Loading your data'
        : hasFailures
        ? 'Actions need attention'
        : 'Connection needs attention';
    final detail = busy
        ? (workspace.isSaving
              ? 'Keeping your workspace up to date.'
              : 'Checking your latest cloud copy.')
        : workspace.error ??
              (hasFailures
                  ? 'Review your saved actions.'
                  : 'Read-only local copy. Connect to edit.');
    return IgnorePointer(
      // Progress is informational; let gestures reach the workspace beneath it.
      ignoring: !visible || (busy && !hasFailures),
      child: MotionSwap(
        alignment: Alignment.topCenter,
        slideOffset: const Offset(0, -0.12),
        child: !visible
            ? const SizedBox.shrink(key: ValueKey('cloud-idle'))
            : Semantics(
                key: ValueKey(busy ? 'cloud-busy' : 'cloud-error'),
                liveRegion: true,
                child: Material(
                  color: AppColors.surface,
                  elevation: 8,
                  shadowColor: AppColors.textPrimary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: failed
                          ? Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.2)
                          : AppColors.divider,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: busy ? 56 : 38,
                          height: busy ? 40 : 38,
                          child: busy
                              ? const AnimatedAppLogo()
                              : Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.cloud_off_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      size: 22,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                detail,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (hasFailures && workspace.ownerId != null)
                          TextButton(
                            onPressed: () => showMotionDialog(
                              context: context,
                              builder: (_) => FailedActionsDialog(
                                owner: workspace.ownerId!,
                              ),
                            ),
                            child: const Text('Review'),
                          )
                        else if (failed)
                          PressFeedback(
                            child: TextButton(
                              onPressed: workspace.outbox?.storageError != null
                                  ? workspace.repairStorage
                                  : workspace.refresh,
                              child: const Text('Retry'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
