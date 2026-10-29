import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'animated_app_logo.dart';

/// A quiet loading surface; recovery and sign-in controls live in their own states.
class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Semantics(
        label: 'Loading microplanner',
        liveRegion: true,
        image: true,
        child: ExcludeSemantics(
          child: AnimatedAppLogo(
            animate: Theme.of(context).platform != TargetPlatform.android,
          ),
        ),
      ),
    ),
  );
}
