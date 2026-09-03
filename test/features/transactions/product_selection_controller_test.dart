import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/transactions/product_selection_controller.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';

void main() {
  Product p(int id, int stock, int price) => Product(
    id: id,
    categoryId: 1,
    name: 'P$id',
    photoPath: '/x',
    purchasePriceCentavos: 1,
    sellingPriceCentavos: price,
    currentQuantity: stock,
    minimumStockLevel: 1,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  test('bounded quantities and integer totals', () {
    final a = p(1, 2, 900),
        b = p(2, 0, 2550),
        c = ProductSelectionController([a, b]);
    c.increase(a);
    c.increase(a);
    c.increase(a);
    c.increase(b);
    expect(c.quantityFor(a), 2);
    expect(c.quantityFor(b), 0);
    expect(c.totalCentavos, 1800);
    c.decrease(a);
    expect(c.totalCentavos, 900);
    c.decrease(a);
    c.decrease(a);
    expect(c.totalCentavos, 0);
  });
  test('same option merges and different options remain separate', () {
    final product = p(1, 100, 1500);
    final bottle = SellingOption(
      id: 1,
      productId: 1,
      name: 'Bottle',
      baseQuantity: 1,
      priceCentavos: 1500,
      isDefault: true,
    );
    final caseOption = SellingOption(
      id: 2,
      productId: 1,
      name: 'Case',
      baseQuantity: 24,
      priceCentavos: 34000,
      isDefault: false,
    );
    final cart = ProductSelectionController([product]);
    cart.add(product, bottle);
    cart.add(product, bottle, quantityValue: 2);
    cart.add(product, caseOption);
    expect(cart.lines, hasLength(2));
    expect(cart.lines.first.quantityValue, 3);
    expect(cart.lines.last.baseQuantity, 24);
  });

  test('decimal parser converts kg without floating point', () {
    final parsed = parseSaleQuantity('1.5', measured: true);
    expect(parsed.value, 15);
    expect(parsed.scale, 10);
  });
  test('multiple products are retained and clear resets the cart', () {
    final a = p(1, 3, 1000), b = p(2, 4, 500);
    final cart = ProductSelectionController([a, b]);
    cart.increase(a);
    cart.increase(b);
    cart.increase(b);
    expect(cart.selectedProducts.map((x) => x.id), [1, 2]);
    expect(cart.totalCentavos, 2000);
    cart.clear();
    expect(cart.selectedProducts, isEmpty);
    expect(cart.totalCentavos, 0);
  });
}
