String standardNumber(num value, {int maxDecimals = 3}) {
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
