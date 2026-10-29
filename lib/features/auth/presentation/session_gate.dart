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
    if (auth.isAuthenticated) {
      return MotionEntrance(
        key: ValueKey(auth.currentUser!.id),
        child: const AccountDashboard(),
      );
    }
    return const MotionEntrance(key: ValueKey('sign-in'), child: LoginScreen());
  }
}
