import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/transactions/product_selection_controller.dart';
import 'package:tindahan_ni_embi/models/product.dart';

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
