import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/backup/presentation/backup_screen.dart';
import 'package:tindahan_ni_embi/services/backup_service.dart';

class _PhotoBackupService extends BackupService {
  _PhotoBackupService() : super(AppDatabase());

  @override
  Future<BackupHealth> health() async => const BackupHealth(
    status: 'Recent',
    valid: true,
    storePhotoIncluded: true,
  );
}

void main() {
  testWidgets('backup photo status fits phone and tablet layouts', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _PhotoBackupService();

    for (final width in [280.0, 1200.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(service: service, onRestored: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tindahan photo: Included'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
