import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/tasks/presentation/dashboard_screen.dart';

/// Root widget for MicroPlanner
class MicroPlannerApp extends StatelessWidget {
  const MicroPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MicroPlanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: AppConfig.enableAuthentication
          ? Consumer<AuthService>(
              builder: (context, authService, _) {
                // Show login or dashboard based on auth state
                if (authService.isAuthenticated) {
                  return const DashboardScreen();
                }
                return const LoginScreen();
              },
            )
          : const DashboardScreen(), // Skip authentication, go directly to dashboard
    );
  }
}
