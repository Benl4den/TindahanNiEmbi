class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isArchived,
  });
  final int id;
  final String name;
  final bool isArchived;
  factory ExpenseCategory.fromMap(Map<String, Object?> map) => ExpenseCategory(
    id: map['id']! as int,
    name: map['name']! as String,
    isArchived: map['is_archived'] == 1,
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.reference,
    required this.categoryId,
    required this.categoryName,
    required this.amountCentavos,
    required this.description,
    required this.expenseDateTime,
    required this.createdAt,
    required this.status,
    this.notes,
    this.referenceNo,
    this.correctedByReference,
    this.correctionOfReference,
    this.reason,
    this.changedAt,
  });
  final int id, categoryId, amountCentavos;
  final String reference, categoryName, description, status;
  final String? notes,
      referenceNo,
      correctedByReference,
      correctionOfReference,
      reason;
  final DateTime expenseDateTime, createdAt;
  final DateTime? changedAt;
  factory Expense.fromMap(Map<String, Object?> m) => Expense(
    id: m['id']! as int,
    reference: m['expense_ref']! as String,
    categoryId: m['category_id']! as int,
    categoryName: m['category_name_snapshot']! as String,
    amountCentavos: m['amount_centavos']! as int,
    description: m['description']! as String,
    notes: m['notes'] as String?,
    referenceNo: m['reference_no'] as String?,
    status: m['status']! as String,
    expenseDateTime: DateTime.parse(m['expense_datetime']! as String),
    createdAt: DateTime.parse(m['created_at']! as String),
    correctedByReference: m['corrected_by_ref'] as String?,
    correctionOfReference: m['correction_of_ref'] as String?,
    reason: m['change_reason'] as String?,
    changedAt: m['changed_at'] == null
        ? null
        : DateTime.parse(m['changed_at']! as String),
  );
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.categoryId,
    required this.amountCentavos,
    required this.description,
    required this.expenseDateTime,
    this.notes,
    this.referenceNo,
  });
  final int categoryId, amountCentavos;
  final String description;
  final DateTime expenseDateTime;
  final String? notes, referenceNo;
}
