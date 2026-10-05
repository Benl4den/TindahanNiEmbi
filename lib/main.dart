import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'services/device_orientation_policy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final views = WidgetsBinding.instance.platformDispatcher.views;
  await SystemChrome.setPreferredOrientations(
    preferredOrientationsForDisplay(views.isEmpty ? null : views.first.display),
  );
  runApp(const TindahanNiEmbiApp());
}
