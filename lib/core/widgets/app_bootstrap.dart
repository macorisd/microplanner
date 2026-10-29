import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/system_bars.dart';
import 'startup_loading_screen.dart';

/// Draw the logo before starting any platform storage or session initialization.
class AppBootstrap extends StatefulWidget {
  final Future<Widget> Function() initialize;
  const AppBootstrap({super.key, required this.initialize});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Widget? _application;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final application = await widget.initialize();
      if (mounted) setState(() => _application = application);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _application ??
      MaterialApp(
        title: 'microplanner',
        debugShowCheckedModeBanner: false,
        // Loading does not need fonts or any other asynchronously loaded assets.
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppTheme.lightColorScheme,
          scaffoldBackgroundColor: AppColors.background,
        ),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: appSystemBars,
          child: child!,
        ),
        home: !_failed
            ? const StartupLoadingScreen()
            : Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Could not start microplanner. Please try again.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy ? null : _initialize,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
}
