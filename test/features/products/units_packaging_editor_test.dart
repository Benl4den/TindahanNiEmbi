import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/products/presentation/units_packaging_editor.dart';

void main() {
  testWidgets('packaging fields stack with readable widths on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitsPackagingEditor(
              categoryName: 'Other',
              defaultSellingPriceCentavos: 1500,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      expect(tester.getSize(fields.at(i)).width, greaterThan(240));
      if (i > 0) {
        expect(
          tester.getTopLeft(fields.at(i)).dy,
          greaterThan(tester.getTopLeft(fields.at(i - 1)).dy),
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
