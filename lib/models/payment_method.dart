import '../core/formatters/display_labels.dart';

enum PaymentMethod {
  cash('CASH'),
  gcash('GCASH');

  const PaymentMethod(this.dbValue);
  final String dbValue;
  String get label => DisplayLabels.paymentMethod(dbValue);

  static PaymentMethod fromDatabase(Object? value) =>
      value == 'GCASH' ? PaymentMethod.gcash : PaymentMethod.cash;
}
