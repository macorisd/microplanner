import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/theme/app_motion.dart';
import '../../auth/data/auth_service.dart';
import 'dashboard_screen.dart';
import 'widgets/cloud_status_card.dart';

class AccountDashboard extends StatefulWidget {
  const AccountDashboard({super.key});
  @override
  State<AccountDashboard> createState() => _AccountDashboardState();
}

class _AccountDashboardState extends State<AccountDashboard>
    with WidgetsBindingObserver {
  Timer? _expiry;
  bool _wasInBackground = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expiry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!context.read<AuthService>().sessionValid) {
        context.read<AuthService>().signOut();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasInBackground = true;
    }
    if (state == AppLifecycleState.resumed) {
      final auth = context.read<AuthService>();
      if (!auth.sessionValid) {
        auth.signOut();
      } else if (_wasInBackground) {
        _wasInBackground = false;
        context.read<WorkspaceController>().refresh();
      }
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _confirmImport() async {
    final workspace = context.read<WorkspaceController>();
    final auth = context.read<AuthService>();
    final owner = auth.currentUser?.id;
    final confirmed = await showMotionDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Import local data?'),
        content: Text(
          'Add the boards, subjects and tasks previously saved on this device to ${auth.currentUser?.email}? '
          'Your existing cloud data and the original local copy will be kept.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _importButtonStyle(dialogContext),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && auth.currentUser?.id == owner) {
      await workspace.importLegacy();
    }
  }

  ButtonStyle _importButtonStyle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colors.onPrimaryContainer,
      foregroundColor: colors.primaryContainer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (workspace.hasLegacyData)
                  Material(
                    color: colors.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            'Local data from before sign-in are available.',
                            style: TextStyle(color: colors.onPrimaryContainer),
                          ),
                          FilledButton(
                            style: _importButtonStyle(context),
                            onPressed: workspace.canImport
                                ? _confirmImport
                                : null,
                            child: const Text('Import…'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: colors.onPrimaryContainer,
                            ),
                            onPressed: workspace.dismissImport,
                            child: const Text('Not now'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: workspace.isLoading && !workspace.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : !workspace.hasData
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Connect to load your data for this account.',
                              ),
                              TextButton(
                                onPressed: workspace.refresh,
                                child: const Text('Retry'),
                              ),
                              TextButton(
                                onPressed: context.read<AuthService>().signOut,
                                child: const Text('Sign out'),
                              ),
                            ],
                          ),
                        )
                      : const DashboardScreen(),
                ),
              ],
            ),
            Positioned(
              top: MediaQuery.sizeOf(context).width < 850 ? 64 : 12,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: CloudStatusCard(workspace: workspace),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
