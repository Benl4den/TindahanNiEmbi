import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/widgets/day_history.dart';

void main() {
  testWidgets(
    'nested details survive date collapse and insertion of a newer day',
    (tester) async {
      final days = ValueNotifier([DateTime(2026, 9, 9), DateTime(2026, 9, 8)]);
      addTearDown(days.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<List<DateTime>>(
                valueListenable: days,
                builder: (_, items, _) => DayHistory<DateTime>(
                  storageKey: 'nested',
                  items: items,
                  date: (day) => day,
                  itemBuilder: (day) => ExpansionTile(
                    key: PageStorageKey('entry-${day.day}'),
                    title: Text('Entry ${day.day}'),
                    children: [Text('Details ${day.day}')],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final dayTile = find
          .descendant(
            of: find.byKey(PageStorageKey('nested-${DateTime(2026, 9, 9)}')),
            matching: find.byType(ListTile),
          )
          .first;
      await tester.tap(dayTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entry 9'));
      await tester.pumpAndSettle();
      expect(find.text('Details 9'), findsOneWidget);
      await tester.tap(dayTile);
      await tester.pumpAndSettle();
      expect(find.text('Details 9'), findsNothing);
      await tester.tap(dayTile);
      await tester.pumpAndSettle();
      expect(find.text('Details 9'), findsOneWidget);
      days.value = [DateTime(2026, 9, 10), ...days.value];
      await tester.pumpAndSettle();
      expect(find.text('Details 9'), findsOneWidget);
      expect(find.text('Entry 10'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
