import 'package:flutter/foundation.dart';

/// Lightweight app-wide invalidation signal for committed store-data changes.
class AppRefreshController extends ChangeNotifier {
  AppRefreshController._();
  static final instance = AppRefreshController._();
  int _revision = 0;
  int get revision => _revision;
  void dataChanged() {
    _revision++;
    notifyListeners();
  }

  Future<T> after<T>(Future<T> operation) async {
    final result = await operation;
    dataChanged();
    return result;
  }
}
