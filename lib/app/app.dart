import 'package:flutter/material.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../database/app_database.dart';
import '../features/security/presentation/auth_gate.dart';
import '../features/shell/presentation/app_shell.dart';
import '../services/auth_service.dart';

class TindahanNiEmbiApp extends StatefulWidget {
  const TindahanNiEmbiApp({super.key});
  @override
  State<TindahanNiEmbiApp> createState() => _State();
}

class _State extends State<TindahanNiEmbiApp> {
  final db = AppDatabase();
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
      future: db.database,
      builder: (_, s) {
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
