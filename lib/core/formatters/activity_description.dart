import 'number_format.dart';

/// Displays legacy log amounts in pesos without changing stored audit entries.
String formatActivityDescription(String description) =>
    description.replaceAllMapped(
      RegExp(r'(-?\d+) centavos\b', caseSensitive: false),
      (match) {
        final centavos = int.tryParse(match.group(1)!);
        return centavos == null ? match.group(0)! : standardMoney(centavos);
      },
    );
