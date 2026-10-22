import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/tasks/presentation/account_dashboard.dart';

class MicroPlannerApp extends StatelessWidget {
  const MicroPlannerApp({super.key});
  @override
  Widget build(BuildContext context) => Consumer<AuthService>(
    builder: (context, auth, _) => MaterialApp(
      // Recreate the navigator on account changes so an old edit dialog cannot survive logout.
      key: ValueKey(auth.currentUser?.id ?? 'signed-out'),
      title: 'MicroPlanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      locale: const Locale('en', 'GB'),
      home: auth.isAuthenticated
          ? const AccountDashboard()
          : const LoginScreen(),
    ),
  );
}
