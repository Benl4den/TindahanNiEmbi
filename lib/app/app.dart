import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../database/app_database.dart';
import '../features/security/presentation/auth_gate.dart';
import '../features/shell/presentation/app_shell.dart';
import '../services/auth_service.dart';
import '../repositories/category_repository.dart';
import '../widgets/app_state_view.dart';

class TindahanNiEmbiApp extends StatefulWidget {
  const TindahanNiEmbiApp({super.key, this.database});
  final AppDatabase? database;
  @override
  State<TindahanNiEmbiApp> createState() => _State();
}

class _State extends State<TindahanNiEmbiApp> {
  late final AppDatabase db;
  late Future<Database> startup;

  @override
  void initState() {
    super.initState();
    db = widget.database ?? AppDatabase();
    startup = _bootstrap();
  }

  Future<Database> _bootstrap() async {
    final database = await db.database;
    await SqliteCategoryRepository(database).ensureDefaultCategories();
    return database;
  }

  void retryStartup() => setState(() => startup = _bootstrap());
  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: FutureBuilder(
      future: startup,
      builder: (_, s) {
        if (s.hasError) {
          return Scaffold(
            body: AppStateView.error(
              title: 'Could not start TindahanNiEmbi',
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
          auth: AuthService(s.data!),
          builder: (role, lock) => AppShell(
            database: s.data!,
            appDatabase: db,
            role: role,
            lock: lock,
          ),
        );
      },
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
          child: const Icon(Icons.storefront, color: Colors.white, size: 40),
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
