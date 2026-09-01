class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    this.nickname,
    this.mobileNumber,
    this.address,
    this.notes,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.balanceCentavos = 0,
  });
  final int id;
  final String fullName;
  final String? nickname;
  final String? mobileNumber;
  final String? address;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int balanceCentavos;

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
    id: map['id']! as int,
    fullName: map['full_name']! as String,
    nickname: map['nickname'] as String?,
    mobileNumber: map['mobile_number'] as String?,
    address: map['address'] as String?,
    notes: map['notes'] as String?,
    isArchived: map['is_archived'] == 1,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
    balanceCentavos: (map['balance_centavos'] as int?) ?? 0,
  );
}

class CustomerDraft {
  const CustomerDraft({
    required this.fullName,
    this.nickname,
    this.mobileNumber,
    this.address,
    this.notes,
  });
  final String fullName;
  final String? nickname;
  final String? mobileNumber;
  final String? address;
  final String? notes;
}

class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.id,
    required this.type,
    required this.amountCentavos,
    required this.occurredAt,
    this.description,
    this.utangTransactionId,
    this.paymentId,
    this.itemCount,
  });
  final int id;
  final String type;
  final int amountCentavos;
  final DateTime occurredAt;
  final String? description;
  final int? utangTransactionId, paymentId, itemCount;
  factory CustomerLedgerEntry.fromMap(Map<String, Object?> map) =>
      CustomerLedgerEntry(
        id: map['id']! as int,
        type: map['entry_type']! as String,
        amountCentavos: map['amount_change_centavos']! as int,
        occurredAt: DateTime.parse(map['occurred_at']! as String),
        description: map['description'] as String?,
        utangTransactionId: map['utang_transaction_id'] as int?,
        paymentId: map['payment_id'] as int?,
        itemCount: map['item_count'] as int?,
      );
}

class CustomerDetails {
  const CustomerDetails({required this.customer, required this.ledger});
  final Customer customer;
  final List<CustomerLedgerEntry> ledger;
  Iterable<CustomerLedgerEntry> get utangHistory =>
      ledger.where((e) => e.type == 'UTANG' || e.type == 'UTANG_REVERSAL');
  Iterable<CustomerLedgerEntry> get paymentHistory =>
      ledger.where((e) => e.type == 'PAYMENT' || e.type == 'PAYMENT_REVERSAL');
}
