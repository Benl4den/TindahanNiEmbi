import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/features/consignment/presentation/consignment_screen.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/models/consignment.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/consignment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/product_photo_service.dart';

class _Repo extends ConsignmentRepository {
  _Repo(super.db);
  final parties = <Consignor>[];
  int payable = 0, receipts = 0;
  int? lastReceiptConsignorId;
  final companyBalances = <int, int>{};
  bool failCreate = false;
  ConsignmentReceiptDraft? lastReceipt;
  @override
  Future<ProductUnitConfiguration> deliveryConfiguration(int productId) async =>
      const ProductUnitConfiguration(
        baseUnit: BaseUnit.piece,
        purchasePackages: [
          PurchasePackageDraft(name: 'Box', baseQuantity: 24, isDefault: true),
          PurchasePackageDraft(name: 'Pack', baseQuantity: 6),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: 'Piece',
            baseQuantity: 1,
            priceCentavos: 200,
            isDefault: true,
          ),
        ],
      );
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
    for (final p in parties) p.id: companyBalances[p.id] ?? payable,
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
    lastReceipt = d;
    lastReceiptConsignorId = d.consignorId;
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
      expect(find.text('Receive Consignment'), findsNothing);
      expect(find.text('Add Product'), findsNothing);
      await t.tap(find.text('ABC'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add Product'));
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
    await t.tap(find.text('ABC'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Product'));
    await t.pumpAndSettle();
    await t.tap(find.text('Select Existing Product'));
    await t.pumpAndSettle();
    for (final x in [
      ('Packages received', '1'),
      ('Supplier cost per Piece', '1'),
      ('Selling price per Piece', '2'),
    ]) {
      expect(find.text(x.$1), findsOneWidget, reason: x.$1);
      await t.enterText(find.widgetWithText(TextField, x.$1), x.$2);
    }
    await t.pump();
    expect(find.textContaining('= 24 pieces received'), findsOneWidget);
    await t.tap(find.text('Receive').last);
    await t.pumpAndSettle();
    expect(repo.receipts, 1);
    expect(repo.lastReceipt!.unitsPerBox, 24);
    repo.payable = 300;
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

  testWidgets('empty company cannot receive another company products', (
    t,
  ) async {
    repo.parties.add(const Consignor(id: 1, name: 'ABC', isArchived: false));
    await pump(t);
    await t.tap(find.text('ABC'));
    await t.pumpAndSettle();
    await t.tap(find.text('Receive Delivery'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Add a product inside this company'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.receipts, 0);
  });

  for (final direct in [false, true]) {
    testWidgets('saved alternative package and direct quantity ($direct)', (
      t,
    ) async {
      repo.parties.add(const Consignor(id: 1, name: 'ABC', isArchived: false));
      await pump(t);
      await t.tap(find.text('ABC'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add Product'));
      await t.pumpAndSettle();
      await t.tap(find.text('Select Existing Product'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<PurchasePackageDraft>));
      await t.pumpAndSettle();
      await t.tap(find.text('Pack • 6 pieces').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(
              find.widgetWithText(TextField, 'piece per package'),
            )
            .readOnly,
        isTrue,
      );
      if (direct) {
        await t.tap(find.text('Direct Units'));
        await t.pumpAndSettle();
      }
      await t.enterText(
        find.widgetWithText(
          TextField,
          direct ? 'Quantity received (piece)' : 'Packages received',
        ),
        '2',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Supplier cost per Piece'),
        '1',
      );
      await t.pump();
      expect(
        find.textContaining(
          direct ? '2 pieces received' : '= 12 pieces received',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Receive').last);
      await t.pumpAndSettle();
      expect(repo.lastReceipt!.totalUnits, direct ? 2 : 12);
      expect(repo.lastReceipt!.sellingPriceCentavos, 200);
    });
  }

  testWidgets('another company payable does not enable remittance', (t) async {
    repo.parties.addAll([
      const Consignor(id: 1, name: 'ABC', isArchived: false),
      const Consignor(id: 2, name: 'XYZ', isArchived: false),
    ]);
    repo.companyBalances.addAll({1: 0, 2: 10000});
    await pump(t);
    await t.tap(find.text('ABC'));
    await t.pumpAndSettle();
    await t.tap(find.text('Record Remittance'));
    await t.pumpAndSettle();
    expect(
      find.text('There is no outstanding supplier payable to remit.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });
}
