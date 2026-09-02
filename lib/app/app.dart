import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../database/app_database.dart';
import '../features/security/presentation/auth_gate.dart';
import '../features/shell/presentation/app_shell.dart';
import '../services/auth_service.dart';

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
    startup = db.database;
  }

  void retryStartup() => setState(() => startup = db.database);
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
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Could not start TindahanNiEmbi',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your store data was not deleted. Please try again. If this continues, contact support and mention “database startup”.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: retryStartup,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!s.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
