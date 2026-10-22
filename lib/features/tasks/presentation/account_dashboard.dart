import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/workspace_controller.dart';
import '../../auth/data/auth_service.dart';
import 'dashboard_screen.dart';

class AccountDashboard extends StatefulWidget {
  const AccountDashboard({super.key});
  @override
  State<AccountDashboard> createState() => _AccountDashboardState();
}

class _AccountDashboardState extends State<AccountDashboard>
    with WidgetsBindingObserver {
  Timer? _expiry;
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
    if (state == AppLifecycleState.resumed) {
      final auth = context.read<AuthService>();
      if (!auth.sessionValid) {
        auth.signOut();
      } else {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import local data?'),
        content: Text(
          'Add the boards, subjects and tasks previously saved on this device to ${auth.currentUser?.email}? '
          'Your existing cloud data and the original local copy will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (workspace.error != null || !workspace.isOnline)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workspace.error ??
                              (workspace.isLoading
                                  ? 'Loading your data…'
                                  : 'Read-only local copy. Connect to edit.'),
                        ),
                      ),
                      TextButton(
                        onPressed: workspace.isLoading || workspace.isSaving
                            ? null
                            : workspace.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (workspace.canImport)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const Text(
                        'Local data from before sign-in are available.',
                      ),
                      TextButton(
                        onPressed: _confirmImport,
                        child: const Text('Import…'),
                      ),
                      TextButton(
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
      ),
    );
  }
}
