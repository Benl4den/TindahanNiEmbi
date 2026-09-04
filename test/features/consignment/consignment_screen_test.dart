import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/features/consignment/presentation/consignment_screen.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/models/consignment.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/consignment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/product_photo_service.dart';

class _Repo extends ConsignmentRepository {
  _Repo(super.db);
  final parties = <Consignor>[];
  int payable = 0, receipts = 0;
  bool failCreate = false;
  @override
  Future<ConsignmentSummary> summary() async => ConsignmentSummary(
    payableCentavos: payable,
    remainingUnits: receipts * 24,
    inventoryValueCentavos: 0,
    marginCentavos: 0,
  );
  @override
  Future<List<Map<String, Object?>>> productCards() async => [];
  @override
  Future<List<Map<String, Object?>>> companyCards() async => [
    for (final p in parties)
      {
        'id': p.id,
        'name': p.name,
        'contact_details': p.contactDetails,
        'product_count': receipts == 0 ? 0 : 1,
        'payable_centavos': payable,
      },
  ];
  @override
  Future<ConsignmentSummary> summaryForConsignor(int consignorId) => summary();
  @override
  Future<List<Map<String, Object?>>> productCardsForConsignor(
    int consignorId,
  ) async => [];
  @override
  Future<List<Consignor>> consignors({bool activeOnly = true}) async => parties;
  @override
  Future<Map<int, int>> payableByConsignor() async => {
    for (final p in parties) p.id: payable,
  };
  @override
  Future<int> createConsignor(String n, {String? contactDetails}) async {
    if (failCreate) {
      throw const InvalidConsignmentOperation('Could not save consignor.');
    }
    parties.add(Consignor(id: parties.length + 1, name: n, isArchived: false));
    return parties.length;
  }

  @override
  Future<int> receive(ConsignmentReceiptDraft d) async {
    receipts++;
    return receipts;
  }

  @override
  Future<int> remit({
    required int consignorId,
    required int amountCentavos,
    String? notes,
  }) async {
    payable -= amountCentavos;
    return 1;
  }
}

class _Products implements ProductRepository {
  final p = Product(
    id: 1,
    categoryId: 1,
    name: 'Juice',
    photoPath: '/x',
    purchasePriceCentavos: 1,
    sellingPriceCentavos: 2,
    currentQuantity: 0,
    minimumStockLevel: 1,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<List<Product>> searchActive([String q = '']) async => [p];
  @override
  Future<Product> create(ProductDraft d) async => p;
  @override
  Future<Product> update(Product p) async => p;
  @override
  Future<void> archive(int id) async {}
}

class _Categories implements CategoryRepository {
  @override
  Future<List<Category>> getActive() async => [];
  @override
  Future<void> archive(int id) async {}
  @override
  Future<Category> create(String n) => throw UnimplementedError();
  @override
  Future<Category> update({required int id, required String name}) =>
      throw UnimplementedError();
}

class _Photo implements ProductPhotoService {
  @override
  Future<String?> capture() async => '/x';
  @override
  Future<void> delete(String p) async {}
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late _Repo repo;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repo = _Repo(db);
  });
  tearDown(() => db.close());
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        home: ConsignmentScreen(
          repository: repo,
          products: _Products(),
          categories: _Categories(),
          photoService: _Photo(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'Add Consignor persists, closes, refreshes, and enables receipt',
    (t) async {
      await pump(t);
      await t.tap(find.text('Add Consignor'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Company / Name'),
        'ABC',
      );
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.parties.single.name, 'ABC');
      await t.tap(find.text('Receive Consignment'));
      await t.pumpAndSettle();
      expect(find.text('Select Existing Product'), findsOneWidget);
    },
  );
  testWidgets(
    'company list is first and summary appears only after selection',
    (t) async {
      repo.parties.add(const Consignor(id: 1, name: 'ABC', isArchived: false));
      repo.payable = 420000;
      await pump(t);
      expect(find.byKey(const Key('consignor-company-list')), findsOneWidget);
      expect(find.text('Outstanding Supplier Payable'), findsNothing);
      await t.tap(find.text('ABC'));
      await t.pumpAndSettle();
      expect(find.text('Outstanding Supplier Payable'), findsOneWidget);
      expect(find.text('₱4200.00'), findsWidgets);
    },
  );
  testWidgets('receipt and remittance open, validate, persist and refresh', (
    t,
  ) async {
    repo.parties.add(const Consignor(id: 1, name: 'ABC', isArchived: false));
    await pump(t);
    await t.tap(find.text('Receive Consignment'));
    await t.pumpAndSettle();
    await t.tap(find.text('Select Existing Product'));
    await t.pumpAndSettle();
    for (final x in [
      ('Packages received', '1'),
      ('Base units per package', '24'),
      ('Cost per unit', '1'),
      ('Selling price per unit', '2'),
    ]) {
      expect(find.text(x.$1), findsOneWidget, reason: x.$1);
      await t.enterText(find.widgetWithText(TextField, x.$1), x.$2);
    }
    await t.pump();
    expect(find.textContaining('= 24 base units received'), findsOneWidget);
    await t.tap(find.text('Receive').last);
    await t.pumpAndSettle();
    expect(repo.receipts, 1);
    repo.payable = 300;
    await t.tap(find.text('ABC'));
    await t.pumpAndSettle();
    await t.tap(find.text('Record Remittance'));
    await t.pumpAndSettle();
    expect(find.text('Outstanding Payable: ₱3.00'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Remittance Amount'), '4');
    await t.tap(find.text('Record Remittance').last);
    await t.pump();
    expect(find.textContaining('cannot exceed'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Remittance Amount'), '2');
    await t.tap(find.text('Record Remittance').last);
    await t.pumpAndSettle();
    expect(repo.payable, 100);
  });
  testWidgets('repository failure stays visible in Add Consignor modal', (
    t,
  ) async {
    repo.failCreate = true;
    await pump(t);
    await t.tap(find.text('Add Consignor'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Company / Name'), 'ABC');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Could not save consignor.'), findsOneWidget);
    expect(find.text('Add Consignor'), findsWidgets);
  });
}
