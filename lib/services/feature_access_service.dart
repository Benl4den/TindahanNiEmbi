import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum AppPlan { free, pro }

/// Explicit Pro boundaries; all unlisted future features remain open.
enum ProFeature {
  managedBrandAnalytics,
  consignment,
  fiveSixLoanManagement,
  productInsights,
  inventoryInsights,
}

/// Identifiers for later plan decisions. Unapproved boundaries stay open.
enum AppFeature {
  inventoryAnalytics,
  productAnalytics,
  productInsights,
  inventoryInsights,
  advancedReports,
  managedBrandsAnalytics,
  consignment,
  selecta,
  loanManagement,
}

/// A replaceable source of plan state. Screens listen to [AppPlanController],
/// never to a development preference or a future billing SDK directly.
abstract class AppPlanSource extends ChangeNotifier {
  AppPlan get plan;
  Future<AppPlan> load();
}

/// Permanent debug-only test source, including after billing is introduced.
/// Its override is outside store backups and is never read in release builds.
class DevelopmentPlanSource extends AppPlanSource {
  DevelopmentPlanSource({
    bool? enabled,
    Future<File> Function()? preferenceFile,
  }) : _enabledForTesting = enabled,
       _preferenceFile = preferenceFile ?? _defaultPreferenceFile;

  final bool? _enabledForTesting;
  bool get enabled => kDebugMode && (_enabledForTesting ?? true);
  final Future<File> Function() _preferenceFile;
  AppPlan _plan = AppPlan.free;
  Future<AppPlan>? _loading;

  @override
  AppPlan get plan => enabled ? _plan : AppPlan.pro;

  static Future<File> _defaultPreferenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/development_test_plan.txt');
  }

  @override
  Future<AppPlan> load() async {
    if (!enabled) return AppPlan.pro;
    try {
      await (_loading ??= _read());
      return _plan;
    } catch (_) {
      // If development storage is unavailable, keep the safe Free default.
      // A later load may retry without blocking the rest of the app.
      _loading = null;
      _plan = AppPlan.free;
      notifyListeners();
      return _plan;
    }
  }

  Future<AppPlan> _read() async {
    final file = await _preferenceFile();
    if (await file.exists()) {
      _plan = (await file.readAsString()).trim() == 'PRO'
          ? AppPlan.pro
          : AppPlan.free;
    }
    notifyListeners();
    return _plan;
  }

  Future<void> setPlan(AppPlan plan) async {
    if (!enabled) {
      throw StateError(
        'Development plan switching is unavailable in release builds.',
      );
    }
    await load();
    final file = await _preferenceFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      plan == AppPlan.pro ? 'PRO' : 'FREE',
      flush: true,
    );
    await temporary.rename(file.path);
    _plan = plan;
    notifyListeners();
  }
}

/// Temporary production source while billing is not implemented. Replacing
/// this with an entitlement source will not change feature screens or rules.
class OpenAccessPlanSource extends AppPlanSource {
  @override
  AppPlan get plan => AppPlan.pro;

  @override
  Future<AppPlan> load() async => AppPlan.pro;
}

/// The single plan state consumed by feature access and listening UI.
class AppPlanController extends ChangeNotifier {
  AppPlanController(this.source) {
    source.addListener(_sourceChanged);
  }

  static final instance = AppPlanController(
    kDebugMode ? DevelopmentPlanSource() : OpenAccessPlanSource(),
  );

  final AppPlanSource source;
  AppPlan get plan => source.plan;
  Future<AppPlan> load() => source.load();

  Future<void> setDevelopmentPlan(AppPlan plan) async {
    if (!kDebugMode || source is! DevelopmentPlanSource) {
      throw StateError('Development plan switching is unavailable.');
    }
    await (source as DevelopmentPlanSource).setPlan(plan);
  }

  void _sourceChanged() => notifyListeners();

  @override
  void dispose() {
    source.removeListener(_sourceChanged);
    super.dispose();
  }
}

bool showDeveloperPlanTools({required bool debugBuild, required bool owner}) =>
    debugBuild && owner;

/// Release remains open until a real entitlement provider is approved; the
/// development preference is never production authority.
class FeatureAccessService {
  FeatureAccessService(this.db, {AppPlanController? planController})
    : planController = planController ?? AppPlanController.instance;

  final Database db;
  final AppPlanController planController;

  Future<AppPlan> currentPlan() => planController.load();

  /// Read only after [currentPlan] has finished loading. Used by listening UI.
  bool allowsCurrent(ProFeature feature) => planController.plan == AppPlan.pro;

  Future<bool> canAccess(AppFeature feature) async {
    return switch (feature) {
      AppFeature.managedBrandsAnalytics ||
      AppFeature.consignment ||
      AppFeature.loanManagement ||
      AppFeature.productInsights => await currentPlan() == AppPlan.pro,
      AppFeature.inventoryInsights => await currentPlan() == AppPlan.pro,
      _ => true,
    };
  }

  Future<bool> allows(ProFeature feature) => canAccess(switch (feature) {
    ProFeature.managedBrandAnalytics => AppFeature.managedBrandsAnalytics,
    ProFeature.consignment => AppFeature.consignment,
    ProFeature.fiveSixLoanManagement => AppFeature.loanManagement,
    ProFeature.productInsights => AppFeature.productInsights,
    ProFeature.inventoryInsights => AppFeature.inventoryInsights,
  });

  Future<void> setLocalPlanForTesting(AppPlan plan) =>
      planController.setDevelopmentPlan(plan);
}
