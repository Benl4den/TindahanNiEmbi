import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/formatters/number_format.dart';

void main() {
  test('money uses one decimal separator and thousands separators', () {
    expect(standardMoney(8000), '₱80.00');
    expect(standardMoney(40000), '₱400.00');
    expect(standardMoney(1850000), '₱18,500.00');
    expect(standardMoney(-125050), '-₱1,250.50');
  });

  test('money input requires at most two decimal places', () {
    expect(parseMoneyCentavos('12.34'), 1234);
    expect(parseMoneyCentavos('1,234.50'), 123450);
    expect(parseMoneyCentavos('12.345'), isNull);
  });
}
