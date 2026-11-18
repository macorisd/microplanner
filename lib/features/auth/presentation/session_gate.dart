import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/startup_loading_screen.dart';
import '../../tasks/presentation/account_dashboard.dart';
import '../data/auth_service.dart';
import 'login_screen.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isInitializing) return const StartupLoadingScreen();
    if (auth.recoveringDeletion) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account deletion',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    auth.isLoading
                        ? 'Checking account deletion…'
                        : auth.error ??
                              'Check the deletion status to continue.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: auth.isLoading ? null : auth.retryDeletion,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (auth.isAuthenticated) {
      return AccountDashboard(key: ValueKey(auth.currentUser!.id));
    }
    return const MotionEntrance(key: ValueKey('sign-in'), child: LoginScreen());
  }
}
