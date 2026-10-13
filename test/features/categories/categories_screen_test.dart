import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/categories/presentation/categories_screen.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';

void main() {
  testWidgets('category screen shows active categories and clear actions', (
    tester,
  ) async {
    final repository = _FakeCategoryRepository([
      Category(
        id: 1,
        name: 'Mga Ilimnon',
        isArchived: false,
        createdAt: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CategoriesScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Mga Ilimnon'), findsOneWidget);
    expect(find.text('Add Category'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('category creation form fits compact phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: CategoriesScreen(repository: _FakeCategoryRepository([])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Category').last);
    await tester.pumpAndSettle();
    expect(find.text('Category name'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _FakeCategoryRepository implements CategoryRepository {
  _FakeCategoryRepository(this.categories);
  final List<Category> categories;

  @override
  Future<List<Category>> getActive() async => categories;

  @override
  Future<void> archive(int id) async {}

  @override
  Future<Category> create(String name) => throw UnimplementedError();

  @override
  Future<Category> update({required int id, required String name}) =>
      throw UnimplementedError();
}
