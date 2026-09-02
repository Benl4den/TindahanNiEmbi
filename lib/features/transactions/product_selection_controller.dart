import '../../models/product.dart';

class ProductSelectionController {
  ProductSelectionController(List<Product> products)
    : products = List.unmodifiable(products);
  final List<Product> products;
  final Map<int, int> _quantities = {};
  int quantityFor(Product p) => _quantities[p.id] ?? 0;
  void increase(Product p) {
    final q = quantityFor(p);
    if (p.currentQuantity > 0 && q < p.currentQuantity) {
      _quantities[p.id] = q + 1;
    }
  }

  void decrease(Product p) {
    final q = quantityFor(p);
    if (q <= 1) {
      _quantities.remove(p.id);
    } else {
      _quantities[p.id] = q - 1;
    }
  }

  void remove(Product p) => _quantities.remove(p.id);

  int get totalCentavos => products.fold(
    0,
    (sum, p) => sum + p.sellingPriceCentavos * quantityFor(p),
  );
  List<Product> get selectedProducts =>
      products.where((p) => quantityFor(p) > 0).toList(growable: false);
  void clear() => _quantities.clear();
}
