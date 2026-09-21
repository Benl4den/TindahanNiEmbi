import '../core/formatters/display_labels.dart';

enum PaymentMethod {
  cash('CASH'),
  gcash('GCASH'),
  maya('MAYA');

  const PaymentMethod(this.dbValue);
  final String dbValue;
  String get legacyStorageValue =>
      this == PaymentMethod.maya ? 'CASH' : dbValue;
  String get label => DisplayLabels.paymentMethod(dbValue);

  static PaymentMethod fromDatabase(Object? value) => switch (value) {
    'GCASH' => PaymentMethod.gcash,
    'MAYA' => PaymentMethod.maya,
    _ => PaymentMethod.cash,
  };
}
