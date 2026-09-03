import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/widgets/app_search_field.dart';
import 'package:tindahan_ni_embi/widgets/app_state_view.dart';
import 'package:tindahan_ni_embi/widgets/product_image.dart';
import 'package:tindahan_ni_embi/widgets/status_badge.dart';

void main() {
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
