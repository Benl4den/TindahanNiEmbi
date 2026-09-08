enum PaymentMethod {
  cash('CASH', 'Cash'),
  gcash('GCASH', 'GCash');

  const PaymentMethod(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static PaymentMethod fromDatabase(Object? value) =>
      value == 'GCASH' ? PaymentMethod.gcash : PaymentMethod.cash;
}
