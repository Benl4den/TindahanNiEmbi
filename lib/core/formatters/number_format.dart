import '../../models/product.dart';

String standardNumber(num value, {int maxDecimals = 3}) {
  if (maxDecimals <= 0) {
    final grouped = value.abs().round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${value < 0 ? '-' : ''}$grouped';
  }
  final fixed = value.abs().toStringAsFixed(maxDecimals).split('.');
  final grouped = fixed.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final decimal = fixed.last.replaceFirst(RegExp(r'0+$'), '');
  return '${value < 0 ? '-' : ''}$grouped${decimal.isEmpty ? '' : '.$decimal'}';
}

String numericInput(String value) => value.replaceAll(',', '').trim();

/// Exact money input: accepts correctly grouped pesos and at most two decimals.
int? parseMoneyCentavos(String input) {
  final value = input.trim();
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.replaceAll(',', '').split('.');
  final pesos = int.tryParse(parts[0]);
  // Conservative bound keeps totals exact on all supported platforms.
  if (pesos == null || pesos > 1000000000) return null;
  return pesos * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String standardMoney(int centavos) {
  final value = centavos.abs();
  final pesos = standardNumber(value ~/ 100, maxDecimals: 0);
  return '${centavos < 0 ? '-' : ''}₱$pesos.${(value % 100).toString().padLeft(2, '0')}';
}

String productQuantityText(Product product, int quantity) {
  return baseQuantityText(
    quantity,
    baseUnitCode: product.baseUnitCode,
    baseUnitLabel: product.baseUnitLabel,
  );
}

String baseQuantityText(
  int quantity, {
  required String baseUnitCode,
  required String baseUnitLabel,
}) {
  if (baseUnitCode == 'GRAM') {
    return '${standardNumber(quantity / 1000)} kg';
  }
  if (baseUnitCode == 'MILLILITER') {
    return '${standardNumber(quantity / 1000)} L';
  }
  return '${standardNumber(quantity)} $baseUnitLabel${quantity == 1 ? '' : 's'}';
}
