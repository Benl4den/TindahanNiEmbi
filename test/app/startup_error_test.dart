import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tindahan_ni_embi/app/app.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';

class _FailingDatabase extends AppDatabase {
  @override
  Future<Database> get database =>
      Future<Database>.error(StateError('open failed'));

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'database startup failure replaces spinner with retryable error',
    (tester) async {
      await tester.pumpWidget(TindahanNiEmbiApp(database: _FailingDatabase()));
      await tester.pump();
      expect(find.text('Could not start TindahanNiEmbi'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byType(TindahanNiEmbiApp), findsOneWidget);
    },
  );
}
