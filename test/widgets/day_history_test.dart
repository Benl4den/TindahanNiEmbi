import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/widgets/day_history.dart';

void main() {
  testWidgets('groups transactions by local day and expands details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayHistory<DateTime>(
              storageKey: 'test',
              items: [
                DateTime(2026, 9, 9, 10),
                DateTime(2026, 9, 9, 11),
                DateTime(2026, 9, 8),
              ],
              date: (date) => date,
              itemBuilder: (date) => Text('Transaction ${date.hour}'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(find.text('Transaction 10'), findsNothing);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Transaction 10'), findsOneWidget);
    expect(find.text('Transaction 11'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
