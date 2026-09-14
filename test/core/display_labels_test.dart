import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/formatters/display_labels.dart';

void main() {
  test('stored transaction codes have readable labels', () {
    expect(DisplayLabels.status('POSTED'), 'Completed');
    expect(DisplayLabels.status('CORRECTED'), 'Fixed');
    expect(DisplayLabels.status('REVERSAL'), 'Cancelled');
    expect(DisplayLabels.paymentMethod('GCASH'), 'GCash');
    expect(DisplayLabels.movement('UTANG_REVERSAL'), 'UTANG Sale Cancelled');
    expect(DisplayLabels.movement('UNKNOWN_INTERNAL_CODE'), 'Stock Change');
  });
}
