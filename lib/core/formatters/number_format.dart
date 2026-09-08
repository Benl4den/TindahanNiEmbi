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
