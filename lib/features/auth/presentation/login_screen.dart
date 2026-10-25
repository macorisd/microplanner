import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../data/auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_note_rounded,
                    size: 96,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'microplanner',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('Your academic tasks, on your devices.'),
                  const SizedBox(height: 40),
                  PressFeedback(
                    child: FilledButton.icon(
                      onPressed: auth.isLoading ? null : auth.signInWithGoogle,
                      icon: auth.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: MotionSwap(
                        child: Text(
                          key: ValueKey(auth.isLoading),
                          auth.isLoading
                              ? 'Connecting…'
                              : 'Sign in with Google',
                        ),
                      ),
                    ),
                  ),
                  if (auth.canCancelSignIn)
                    TextButton(
                      onPressed: auth.cancelSignIn,
                      child: const Text('Cancel'),
                    ),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        auth.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
