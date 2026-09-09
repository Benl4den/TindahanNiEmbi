import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/widgets/overview_banner.dart';

void main() {
  testWidgets('inventory footer keeps space for the page body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: SizedBox.expand(key: Key('inventory-body')),
          bottomNavigationBar: OverviewBanner(
            title: 'Owned Inventory Value',
            value: '₱16,413.82',
            caption: 'Stock at purchase cost • Consignment excluded',
            icon: Icons.inventory_2_outlined,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(OverviewBanner)).height, lessThan(200));
    expect(
      tester.getSize(find.byKey(const Key('inventory-body'))).height,
      greaterThan(300),
    );
    expect(tester.takeException(), isNull);
  });
}
