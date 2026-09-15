import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/widgets/app_search_field.dart';
import 'package:tindahan_ni_embi/widgets/app_state_view.dart';
import 'package:tindahan_ni_embi/widgets/product_image.dart';
import 'package:tindahan_ni_embi/widgets/status_badge.dart';
import 'package:tindahan_ni_embi/widgets/store_summary_card.dart';
import 'package:tindahan_ni_embi/widgets/balanced_card_grid.dart';

void main() {
  testWidgets(
    'card groups use three aligned columns and match natural heights',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 850,
              child: BalancedCardGrid(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      key: ValueKey('card-$i'),
                      color: Colors.green,
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (_, box) => Text(
                          i == 1
                              ? 'A longer card description that needs additional lines and grows safely.'
                              : 'Short card',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final rects = [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byKey(ValueKey('card-$i'))),
      ];
      expect(rects[0].top, rects[1].top);
      expect(rects[1].top, rects[2].top);
      expect(rects[0].height, rects[1].height);
      expect(rects[1].height, rects[2].height);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reference summary cards fit large values and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const SingleChildScrollView(
              child: SizedBox(
                width: 290,
                child: Column(
                  children: [
                    StoreSummaryCard(
                      title: 'Currently Owed to Suppliers',
                      value: '₱4,195,615.05',
                      icon: Icons.handshake_outlined,
                      accent: Color(0xFFBAA0E5),
                    ),
                    StoreSummaryHero(
                      title: 'Total Sales',
                      value: '₱4,195,615.05',
                      caption: 'Cash, GCash and UTANG sales',
                      icon: Icons.bar_chart,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('loading feedback fits short panels and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const SizedBox(
              width: 220,
              height: 70,
              child: AppLoadingView(label: 'Loading your transaction history…'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Loading your transaction history…'), findsOneWidget);
  });
  testWidgets('shared controls remain readable at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(label: Text('All Products'), selected: true),
                      ChoiceChip(label: Text('Low Stock'), selected: false),
                      StatusBadge(
                        label: 'Out of Stock',
                        status: AppStatus.critical,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 220,
                    height: 160,
                    child: ProductImage(path: '/missing-product-image'),
                  ),
                  SizedBox(height: 16),
                  AppStateView.empty(
                    title: 'No products found',
                    message: 'Try another search.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('All Products'), findsOneWidget);
    expect(find.text('Low Stock'), findsOneWidget);
    expect(find.bySemanticsLabel('Out of Stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search debounces queries and clears immediately', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppSearchField(
            hintText: 'Search products...',
            onChanged: values.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'co');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 249));
    expect(values, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(values, ['coffee']);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(values, ['coffee', '']);
    expect(find.text('coffee'), findsNothing);
  });

  test('chip theme defines readable selected and unselected labels', () {
    final chips = AppTheme.light.chipTheme;
    expect(chips.labelStyle?.color, AppTheme.text);
    expect(chips.secondaryLabelStyle?.color, AppTheme.primary);
    expect(chips.selectedColor, isNotNull);
    expect(chips.checkmarkColor, AppTheme.primary);
  });
}
