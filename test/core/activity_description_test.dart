import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/formatters/activity_description.dart';

void main() {
  test(
    'legacy centavo amounts display as pesos without changing other numbers',
    () {
      expect(
        formatActivityDescription(
          'EXP-000001 added. Electricity — 250000 centavos',
        ),
        'EXP-000001 added. Electricity — ₱2,500.00',
      );
      expect(
        formatActivityDescription('UTANG UTG-000015 — ₱120.00'),
        'UTANG UTG-000015 — ₱120.00',
      );
      expect(formatActivityDescription('-500 centavos'), '-₱5.00');
    },
  );
}
