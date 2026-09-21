import 'package:sqflite/sqflite.dart';

enum AppPlan { free, pro }

enum ProFeature { managedBrandAnalytics, fiveSixLoanManagement }

/// One entitlement boundary for the whole app. Pro restrictions are disabled
/// during development until subscription billing is implemented.
class FeatureAccessService {
  const FeatureAccessService(this.db);
  final Database db;
  Future<AppPlan> currentPlan() async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: ['plan_tier'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'PRO'
        ? AppPlan.pro
        : AppPlan.free;
  }

  Future<bool> allows(ProFeature feature) async => true;
  Future<void> setLocalPlanForTesting(AppPlan plan) =>
      db.insert('app_settings', {
        'key': 'plan_tier',
        'value': plan == AppPlan.pro ? 'PRO' : 'FREE',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
}
