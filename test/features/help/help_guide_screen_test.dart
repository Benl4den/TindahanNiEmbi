import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/help/help_guide_screen.dart';

void main() {
  testWidgets('local Help & Guide search finds matching articles', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpGuideScreen()));

    expect(find.text('Sales'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'cash in');
    await tester.pump();

    expect(find.text('GCash Cash-In'), findsOneWidget);
    expect(find.text('Sales'), findsNothing);
  });
}
