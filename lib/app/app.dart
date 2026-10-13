import 'dart:async';
import 'dart:ui' as ui;

import '../widgets/brand_logo.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../database/app_database.dart';
import '../features/security/presentation/auth_gate.dart';
import '../features/shell/presentation/app_shell.dart';
import '../services/auth_service.dart';
import '../services/device_orientation_policy.dart';
import '../repositories/category_repository.dart';
import '../services/settings_service.dart';
import '../widgets/app_state_view.dart';

class TindahanNiEmbiApp extends StatefulWidget {
  const TindahanNiEmbiApp({super.key, this.database});
  final AppDatabase? database;
  @override
  State<TindahanNiEmbiApp> createState() => _State();
}

class _State extends State<TindahanNiEmbiApp> with WidgetsBindingObserver {
  late final AppDatabase db;
  late Future<Database> startup;
  AppThemePreference themePreference = AppThemePreference.system;
  int _sessionVersion = 0;
  ui.FlutterView? _view;
  bool? _lastCompactDisplay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    db = widget.database ?? AppDatabase();
    startup = _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.maybeOf(context);
    _syncOrientation();
  }

  @override
  void didChangeMetrics() => _syncOrientation();

  void _syncOrientation() {
    final display = _view?.display;
    if (display == null) return;
    final isCompact = isCompactDisplay(display.size, display.devicePixelRatio);
    if (_lastCompactDisplay == isCompact) return;
    _lastCompactDisplay = isCompact;
    unawaited(
      SystemChrome.setPreferredOrientations(
        preferredOrientationsForDisplay(display),
      ),
    );
  }

  Future<Database> _bootstrap() async {
    final database = await db.database;
    await SqliteCategoryRepository(database).ensureDefaultCategories();
    final savedPreference = await SettingsService(database).themePreference;
    // Rebuild MaterialApp itself; FutureBuilder only rebuilds its home subtree.
    if (mounted) setState(() => themePreference = savedPreference);
    return database;
  }

  Future<void> _setThemePreference(AppThemePreference preference) async {
    final database = await db.database;
    await SettingsService(database).setThemePreference(preference);
    if (mounted) setState(() => themePreference = preference);
  }

  void retryStartup() => setState(() => startup = _bootstrap());

  void _restartAfterRestore() => setState(() {
    _sessionVersion++;
    startup = _bootstrap();
  });
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: switch (themePreference) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    },
    themeAnimationDuration: Duration.zero,
    builder: (context, child) {
      if (child == null) return const SizedBox.shrink();
      final display = View.maybeOf(context)?.display;
      if (display == null ||
          !requiresTabletLandscapePrompt(
            display.size,
            display.devicePixelRatio,
            MediaQuery.sizeOf(context),
          )) {
        return child;
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          // Preserve the current route and form state until the tablet rotates.
          IgnorePointer(ignoring: true, child: child),
          const _TabletLandscapePrompt(),
        ],
      );
    },
    home: FutureBuilder(
      future: startup,
      builder: (_, s) {
        if (s.hasError) {
          return Scaffold(
            body: AppStateView.error(
              title: 'Could not start TindaSari PH',
              message: 'Your store data is safe. Please try again. If this continues, contact support and mention “database startup”.',
              actionLabel: 'Try Again',
              onAction: retryStartup,
            ),
          );
        }
        if (!s.hasData) {
          return const Scaffold(body: _StartupView());
        }
        return AuthGate(
          key: ValueKey('auth-session-$_sessionVersion'),
          auth: AuthService(s.data!),
          builder: (role, lock) => AppShell(
            database: s.data!,
            appDatabase: db,
            role: role,
            lock: lock,
            onThemePreferenceChanged: _setThemePreference,
            onDatabaseRestored: _restartAfterRestore,
          ),
        );
      },
    ),
  );
}

class _TabletLandscapePrompt extends StatelessWidget {
  const _TabletLandscapePrompt();

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.screen_rotation_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Rotate your tablet to landscape',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'TindaSari PH is available in landscape on tablets.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StartupView extends StatelessWidget {
  const _StartupView();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const BrandLogo(size: 72),
        ),
        const SizedBox(height: 20),
        Text(
          AppStrings.appName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Preparing your store…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        const SizedBox(width: 160, child: LinearProgressIndicator()),
      ],
    ),
  );
}
