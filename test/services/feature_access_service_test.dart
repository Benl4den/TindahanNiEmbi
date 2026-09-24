import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

class _EntitlementSource extends AppPlanSource {
  AppPlan _plan = AppPlan.free;

  @override
  AppPlan get plan => _plan;

  @override
  Future<AppPlan> load() async => _plan;

  void update(AppPlan value) {
    _plan = value;
    notifyListeners();
  }
}

void main() {
  sqfliteFfiInit();

  test(
    'debug plan persists separately and changes only approved access',
    () async {
      final directory = await Directory.systemTemp.createTemp('plan_test_');
      final file = File('${directory.path}/test_plan.txt');
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(() async {
        await app.close();
        await directory.delete(recursive: true);
      });
      final db = await app.database;
      final before = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM products'),
      );
      final controller = AppPlanController(
        DevelopmentPlanSource(enabled: true, preferenceFile: () async => file),
      );
      final access = FeatureAccessService(db, planController: controller);
      var changes = 0;
      controller.addListener(() => changes++);

      expect(await access.currentPlan(), AppPlan.free);
      expect(await access.allows(ProFeature.managedBrandAnalytics), isFalse);
      expect(await access.allows(ProFeature.fiveSixLoanManagement), isFalse);
      expect(await access.allows(ProFeature.productInsights), isFalse);
      expect(await access.canAccess(AppFeature.inventoryAnalytics), isTrue);
      expect(await access.canAccess(AppFeature.consignment), isTrue);

      await access.setLocalPlanForTesting(AppPlan.pro);
      expect(await access.currentPlan(), AppPlan.pro);
      expect(await access.allows(ProFeature.managedBrandAnalytics), isTrue);
      expect(await access.allows(ProFeature.fiveSixLoanManagement), isTrue);
      expect(await access.allows(ProFeature.productInsights), isTrue);
      expect(changes, greaterThanOrEqualTo(2));

      final restarted = AppPlanController(
        DevelopmentPlanSource(enabled: true, preferenceFile: () async => file),
      );
      expect(await restarted.load(), AppPlan.pro);
      await restarted.setDevelopmentPlan(AppPlan.free);
      expect(
        await AppPlanController(
          DevelopmentPlanSource(
            enabled: true,
            preferenceFile: () async => file,
          ),
        ).load(),
        AppPlan.free,
      );
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products'),
        ),
        before,
      );
      expect(
        await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: ['plan_tier'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'release policy ignores test preferences and cannot change them',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await app.database;
      final controller = AppPlanController(OpenAccessPlanSource());
      final access = FeatureAccessService(db, planController: controller);
      expect(await access.currentPlan(), AppPlan.pro);
      expect(await access.allows(ProFeature.fiveSixLoanManagement), isTrue);
      expect(await access.allows(ProFeature.managedBrandAnalytics), isTrue);
      await expectLater(
        access.setLocalPlanForTesting(AppPlan.free),
        throwsStateError,
      );
      expect(controller.source, isA<OpenAccessPlanSource>());
      expect(showDeveloperPlanTools(debugBuild: false, owner: true), isFalse);
      expect(showDeveloperPlanTools(debugBuild: true, owner: false), isFalse);
      expect(showDeveloperPlanTools(debugBuild: true, owner: true), isTrue);
    },
  );

  test('an entitlement source can replace the debug source without UI rules changing', () async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await app.database;
    final source = _EntitlementSource();
    final controller = AppPlanController(source);
    final access = FeatureAccessService(db, planController: controller);
    var updates = 0;
    controller.addListener(() => updates++);

    expect(await access.currentPlan(), AppPlan.free);
    expect(await access.allows(ProFeature.managedBrandAnalytics), isFalse);
    source.update(AppPlan.pro);
    expect(controller.plan, AppPlan.pro);
    expect(access.allowsCurrent(ProFeature.managedBrandAnalytics), isTrue);
    expect(await access.allows(ProFeature.fiveSixLoanManagement), isTrue);
    expect(updates, 1);
    await expectLater(
      controller.setDevelopmentPlan(AppPlan.free),
      throwsStateError,
    );
  });
}
