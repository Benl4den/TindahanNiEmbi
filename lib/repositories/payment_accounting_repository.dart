import 'package:sqflite/sqflite.dart';

import '../models/payment_method.dart';
import '../services/app_refresh_controller.dart';

class GCashLedgerEntry {
  const GCashLedgerEntry({
    required this.id,
    required this.reference,
    required this.type,
    required this.amountChangeCentavos,
    required this.occurredAt,
    this.gcashReference,
    this.notes,
  });
  final int id, amountChangeCentavos;
  final String reference, type;
  final String? gcashReference, notes;
  final DateTime occurredAt;

  factory GCashLedgerEntry.fromMap(Map<String, Object?> map) =>
      GCashLedgerEntry(
        id: map['id']! as int,
        reference: map['reference']! as String,
        type: map['entry_type']! as String,
        amountChangeCentavos: map['amount_change_centavos']! as int,
        occurredAt: DateTime.parse(map['occurred_at']! as String),
        gcashReference: map['gcash_reference'] as String?,
        notes: map['notes'] as String?,
      );
}

class GCashSummary {
  const GCashSummary({
    required this.balance,
    required this.todayIn,
    required this.todayOut,
  });
  final int balance, todayIn, todayOut;
  int get todayNet => todayIn - todayOut;
}

class PaymentAccountingException implements Exception {
  const PaymentAccountingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PaymentAccountingRepository {
  const PaymentAccountingRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;
  Future<bool> hasOpeningBalance() async => (await db.query(
    'gcash_ledger_entries',
    columns: ['id'],
    where: "entry_type='OPENING_BALANCE'",
    limit: 1,
  )).isNotEmpty;

  static String? normalizeReference(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Future<void> postSale(
    DatabaseExecutor tx, {
    required int saleId,
    required int amountCentavos,
    required PaymentMethod method,
    String? gcashReference,
    String? actorRole,
    required String occurredAt,
  }) async {
    final reference = normalizeReference(gcashReference);
    await tx.insert('sale_payments', {
      'cash_sale_id': saleId,
      'payment_method': method.dbValue,
      'amount_centavos': amountCentavos,
      'gcash_reference': method == PaymentMethod.gcash ? reference : null,
      'created_at': occurredAt,
    });
    if (method == PaymentMethod.gcash) {
      await _postLedger(
        tx,
        type: 'SALE',
        amountChangeCentavos: amountCentavos,
        cashSaleId: saleId,
        gcashReference: reference,
        actorRole: actorRole,
        occurredAt: occurredAt,
      );
    }
  }

  static Future<void> postUtangPayment(
    DatabaseExecutor tx, {
    required int paymentId,
    required int amountCentavos,
    required PaymentMethod method,
    String? gcashReference,
    String? actorRole,
    required String occurredAt,
  }) async {
    if (method != PaymentMethod.gcash) return;
    await _postLedger(
      tx,
      type: 'UTANG_PAYMENT',
      amountChangeCentavos: amountCentavos,
      utangPaymentId: paymentId,
      gcashReference: normalizeReference(gcashReference),
      actorRole: actorRole,
      occurredAt: occurredAt,
    );
  }

  static Future<void> postExpense(
    DatabaseExecutor tx, {
    required int expenseId,
    required int amountCentavos,
    required PaymentMethod method,
    String? gcashReference,
    String? actorRole,
    required String occurredAt,
  }) async {
    final reference = normalizeReference(gcashReference);
    await tx.insert('expense_payments', {
      'expense_id': expenseId,
      'payment_method': method.dbValue,
      'amount_centavos': amountCentavos,
      'gcash_reference': method == PaymentMethod.gcash ? reference : null,
      'created_at': occurredAt,
    });
    if (method == PaymentMethod.gcash) {
      await _postLedger(
        tx,
        type: 'EXPENSE',
        amountChangeCentavos: -amountCentavos,
        expenseId: expenseId,
        gcashReference: reference,
        actorRole: actorRole,
        occurredAt: occurredAt,
      );
    }
  }

  static Future<void> postConsignorRemittance(
    DatabaseExecutor tx, {
    required int remittanceId,
    required int amountCentavos,
    required PaymentMethod method,
    String? gcashReference,
    String? actorRole,
    required String occurredAt,
  }) async {
    if (method != PaymentMethod.gcash) return;
    await _postLedger(
      tx,
      type: 'CONSIGNOR_REMITTANCE',
      amountChangeCentavos: -amountCentavos,
      consignorRemittanceId: remittanceId,
      gcashReference: normalizeReference(gcashReference),
      actorRole: actorRole,
      occurredAt: occurredAt,
    );
  }

  static Future<int> postGCashService(
    DatabaseExecutor tx, {
    required int serviceId,
    required String serviceType,
    bool isReversal = false,
    required int amountChangeCentavos,
    String? gcashReference,
    String? actorRole,
    String? notes,
    required String occurredAt,
  }) => _postLedger(
    tx,
    type: isReversal
        ? 'SERVICE_REVERSAL'
        : serviceType == 'CASH_IN'
        ? 'CASH_IN_SERVICE'
        : 'CASH_OUT_SERVICE',
    amountChangeCentavos: amountChangeCentavos,
    gcashServiceTransactionId: serviceId,
    gcashReference: normalizeReference(gcashReference),
    actorRole: actorRole,
    notes: notes,
    occurredAt: occurredAt,
  );

  static Future<void> reverseSource(
    DatabaseExecutor tx, {
    int? cashSaleId,
    int? utangPaymentId,
    int? expenseId,
    int? transactionReversalId,
    int? expenseReversalId,
    String? actorRole,
    required String occurredAt,
    required String reason,
  }) async {
    final where = cashSaleId != null
        ? 'cash_sale_id=?'
        : utangPaymentId != null
        ? 'utang_payment_id=?'
        : expenseId != null
        ? 'expense_id=?'
        : null;
    final sourceId = cashSaleId ?? utangPaymentId ?? expenseId;
    if (where == null || sourceId == null) return;
    final rows = await tx.query(
      'gcash_ledger_entries',
      where: where,
      whereArgs: [sourceId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final original = rows.single;
    await _postLedger(
      tx,
      type: 'REVERSAL',
      amountChangeCentavos: -(original['amount_change_centavos']! as int),
      transactionReversalId: transactionReversalId,
      expenseReversalId: expenseReversalId,
      reversalOfEntryId: original['id']! as int,
      actorRole: actorRole,
      notes: reason.trim(),
      occurredAt: occurredAt,
    );
  }

  Future<int> addManual({
    required String type,
    required int amountCentavos,
    required String reason,
    String? gcashReference,
    bool ownerPinAuthorized = false,
  }) async {
    if (actorRole != 'OWNER' || !ownerPinAuthorized) {
      throw const PaymentAccountingException(
        'Owner PIN authorization is required.',
      );
    }
    if (!const {
      'OPENING_BALANCE',
      'ADJUSTMENT_IN',
      'ADJUSTMENT_OUT',
    }.contains(type)) {
      throw const PaymentAccountingException('Invalid adjustment type.');
    }
    if (amountCentavos <= 0 || reason.trim().isEmpty) {
      throw const PaymentAccountingException(
        'A positive amount and reason are required.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final change = type == 'ADJUSTMENT_OUT' ? -amountCentavos : amountCentavos;
    return AppRefreshController.instance.after(
      db.transaction((tx) async {
        if (type == 'OPENING_BALANCE' &&
            (await tx.query(
              'gcash_ledger_entries',
              columns: ['id'],
              where: "entry_type='OPENING_BALANCE'",
              limit: 1,
            )).isNotEmpty) {
          throw const PaymentAccountingException(
            'Opening balance is already recorded. Use Adjustment In or Out instead.',
          );
        }
        final id = await _postLedger(
          tx,
          type: type,
          amountChangeCentavos: change,
          gcashReference: normalizeReference(gcashReference),
          actorRole: actorRole,
          notes: reason.trim(),
          occurredAt: now,
        );
        await tx.insert('activity_logs', {
          'event_type': 'GCASH_$type',
          'description': 'GCash $type recorded. Reason: ${reason.trim()}',
          'actor_role': actorRole,
          'related_entity_type': 'GCASH_LEDGER',
          'related_entity_id': id,
          'created_at': now,
        });
        return id;
      }),
    );
  }

  Future<GCashSummary> summary([DateTime? selectedDay]) async {
    final day = selectedDay ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final row = (await db.rawQuery(
      '''SELECT COALESCE(SUM(amount_change_centavos),0) balance,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos>0 THEN amount_change_centavos ELSE 0 END),0) today_in,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos<0 THEN -amount_change_centavos ELSE 0 END),0) today_out
      FROM gcash_ledger_entries''',
      [
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
      ],
    )).single;
    return GCashSummary(
      balance: row['balance']! as int,
      todayIn: row['today_in']! as int,
      todayOut: row['today_out']! as int,
    );
  }

  Future<List<GCashLedgerEntry>> history({int limit = 100}) async =>
      (await db.query(
        'gcash_ledger_entries',
        orderBy: 'occurred_at DESC,id DESC',
        limit: limit,
      )).map(GCashLedgerEntry.fromMap).toList(growable: false);

  static Future<int> _postLedger(
    DatabaseExecutor tx, {
    required String type,
    required int amountChangeCentavos,
    int? cashSaleId,
    int? utangPaymentId,
    int? expenseId,
    int? consignorRemittanceId,
    int? transactionReversalId,
    int? expenseReversalId,
    int? gcashServiceTransactionId,
    int? reversalOfEntryId,
    String? gcashReference,
    String? notes,
    String? actorRole,
    required String occurredAt,
  }) async {
    if (amountChangeCentavos == 0) {
      throw const PaymentAccountingException('Ledger amount cannot be zero.');
    }
    final id = await tx.insert('gcash_ledger_entries', {
      'reference': 'GCL-${DateTime.now().microsecondsSinceEpoch}',
      'entry_type': type,
      'amount_change_centavos': amountChangeCentavos,
      'cash_sale_id': cashSaleId,
      'utang_payment_id': utangPaymentId,
      'expense_id': expenseId,
      'consignor_remittance_id': consignorRemittanceId,
      'transaction_reversal_id': transactionReversalId,
      'expense_reversal_id': expenseReversalId,
      'gcash_service_transaction_id': gcashServiceTransactionId,
      'reversal_of_entry_id': reversalOfEntryId,
      'gcash_reference': gcashReference,
      'notes': notes,
      'actor_role': actorRole,
      'occurred_at': occurredAt,
      'created_at': occurredAt,
    });
    return id;
  }
}
