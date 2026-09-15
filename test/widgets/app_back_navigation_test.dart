import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/widgets/app_back_navigation.dart';
import 'package:tindahan_ni_embi/features/cash_sales/presentation/cash_sale_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';

Future<void> openForm(
  WidgetTester tester,
  TextEditingController controller, {
  bool busy = false,
  bool modal = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final form = PageBackGuard(
                controllers: [controller],
                busy: busy,
                child: Scaffold(body: TextField(controller: controller)),
              );
              if (modal) {
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(child: form),
                );
              } else {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => form),
                );
              }
            },
            child: const Text('Open Form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Form'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Back closes Review Sale and confirms leaving a current cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SectionBackController();
    final now = DateTime(2026);
    var exits = 0, saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop && !await controller.handleBack()) exits++;
          },
          child: Scaffold(
            body: SectionBackScope(
              controller: controller,
              child: CashSaleScreen(
                embedded: true,
                saveSale: (_) async => ++saves,
                products: [
                  Product(
                    id: 1,
                    categoryId: 1,
                    name: 'Coffee',
                    photoPath: '/missing',
                    purchasePriceCentavos: 500,
                    sellingPriceCentavos: 1000,
                    currentQuantity: 10,
                    minimumStockLevel: 1,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review & Complete Sale'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Review Sale'), findsNothing);
    expect(find.text('1 products in cart'), findsOneWidget);
    expect(exits, 0);
    expect(saves, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave TindaSari PH?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(exits, 0);
    expect(find.text('1 products in cart'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave App'));
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Back closes an untouched form without confirmation', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Original');
    addTearDown(controller.dispose);
    await openForm(tester, controller);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Form'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  for (final modal in [false, true]) {
    testWidgets('Back protects edited ${modal ? 'modal' : 'page'} fields', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Original');
      addTearDown(controller.dispose);
      await openForm(tester, controller, modal: modal);
      await tester.enterText(find.byType(TextField), 'Changed');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Changed');
      expect(find.byType(TextField), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Back cannot leave while a save is processing', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await openForm(tester, controller, busy: true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('Back dismisses keyboard before leaving an untouched form', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetViewInsets);
    await openForm(tester, controller);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('embedded section Back handlers unregister when removed', (
    tester,
  ) async {
    final controller = SectionBackController();
    var handled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SectionBackScope(
          controller: controller,
          child: SectionBackHandler(
            onBack: () async {
              handled++;
              return true;
            },
            child: const SizedBox(),
          ),
        ),
      ),
    );
    expect(await controller.handleBack(), isTrue);
    expect(handled, 1);
    await tester.pumpWidget(const SizedBox());
    expect(await controller.handleBack(), isFalse);
    expect(handled, 1);
  });
}
