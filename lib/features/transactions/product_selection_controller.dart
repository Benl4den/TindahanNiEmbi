import '../../models/product.dart';
import '../../models/product_unit.dart';
import '../../models/utang_draft.dart';

class SaleCartLine {
  const SaleCartLine({
    required this.product,
    required this.option,
    required this.quantityValue,
    required this.quantityScale,
  });
  final Product product;
  final SellingOption option;
  final int quantityValue, quantityScale;
  String get key => '${product.id}:${option.id}';
  int get baseQuantity => quantityValue * option.baseQuantity ~/ quantityScale;
  int get lineTotalCentavos =>
      (option.priceCentavos * quantityValue + quantityScale ~/ 2) ~/
      quantityScale;
  String get quantityText => quantityScale == 1
      ? '$quantityValue'
      : _decimal(quantityValue, quantityScale);
  UtangItemDraft toDraft() => UtangItemDraft(
    productId: product.id,
    quantity: quantityScale == 1 ? quantityValue : 1,
    sellingOptionId: option.id > 0 ? option.id : null,
    sellingOptionName: option.name,
    quantityValue: quantityValue,
    quantityScale: quantityScale,
    baseQuantityPerUnit: option.baseQuantity,
    baseUnitLabel: product.baseUnitLabel,
    unitPriceCentavos: option.priceCentavos,
  );
  SaleCartLine copyWithQuantity(int value) => SaleCartLine(
    product: product,
    option: option,
    quantityValue: value,
    quantityScale: quantityScale,
  );
  static String _decimal(int value, int scale) {
    final whole = value ~/ scale, remainder = value % scale;
    if (remainder == 0) return '$whole';
    return '$whole.${remainder.toString().padLeft(scale.toString().length - 1, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
}

class ProductSelectionController {
  ProductSelectionController(List<Product> products)
    : products = List.unmodifiable(products);
  final List<Product> products;
  final Map<String, SaleCartLine> _lines = {};
  List<SaleCartLine> get lines => List.unmodifiable(_lines.values);
  int quantityFor(Product p) => lines
      .where((x) => x.product.id == p.id)
      .fold(0, (n, x) => n + (x.quantityScale == 1 ? x.quantityValue : 1));
  void add(
    Product product,
    SellingOption option, {
    int quantityValue = 1,
    int quantityScale = 1,
  }) {
    if (quantityValue <= 0 ||
        quantityScale <= 0 ||
        quantityValue * option.baseQuantity % quantityScale != 0) {
      throw ArgumentError('Invalid quantity.');
    }
    final line = SaleCartLine(
      product: product,
      option: option,
      quantityValue: quantityValue,
      quantityScale: quantityScale,
    );
    final next = (_lines[line.key]?.quantityValue ?? 0) + quantityValue;
    if (next * option.baseQuantity ~/ quantityScale > product.currentQuantity) {
      throw StateError('Not enough stock.');
    }
    _lines[line.key] = line.copyWithQuantity(next);
  }

  void increase(Product p) {
    if (quantityFor(p) >= p.currentQuantity) return;
    add(
      p,
      SellingOption(
        id: -p.id,
        productId: p.id,
        name: 'Piece',
        baseQuantity: 1,
        priceCentavos: p.sellingPriceCentavos,
        isDefault: true,
      ),
    );
  }

  void increaseLine(SaleCartLine line) => add(
    line.product,
    line.option,
    quantityValue: line.quantityScale,
    quantityScale: line.quantityScale,
  );
  void decrease(Product p) {
    final found = lines.where((x) => x.product.id == p.id).firstOrNull;
    if (found != null) decreaseLine(found);
  }

  void decreaseLine(SaleCartLine line) {
    final next = line.quantityValue - line.quantityScale;
    if (next <= 0) {
      _lines.remove(line.key);
    } else {
      _lines[line.key] = line.copyWithQuantity(next);
    }
  }

  void remove(Product p) => _lines.removeWhere((_, x) => x.product.id == p.id);
  void removeLine(SaleCartLine line) => _lines.remove(line.key);
  int get totalCentavos => lines.fold(0, (n, x) => n + x.lineTotalCentavos);
  List<Product> get selectedProducts =>
      lines.map((x) => x.product).toList(growable: false);
  List<UtangItemDraft> get drafts =>
      lines.map((x) => x.toDraft()).toList(growable: false);
  void clear() => _lines.clear();
}

({int value, int scale}) parseSaleQuantity(
  String input, {
  required bool measured,
}) {
  final text = input.trim();
  if (!measured) {
    final value = int.tryParse(text);
    if (value == null || value <= 0) {
      throw const FormatException('Enter a whole quantity greater than zero.');
    }
    return (value: value, scale: 1);
  }
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(text)) {
    throw const FormatException('Enter up to three decimal places.');
  }
  final parts = text.split('.'), fraction = parts.length == 1 ? '' : parts[1];
  final scale = fraction.isEmpty
      ? 1
      : switch (fraction.length) {
          1 => 10,
          2 => 100,
          _ => 1000,
        };
  final value =
      int.parse(parts[0]) * scale +
      (fraction.isEmpty ? 0 : int.parse(fraction));
  if (value <= 0) {
    throw const FormatException('Quantity must be greater than zero.');
  }
  return (value: value, scale: scale);
}
