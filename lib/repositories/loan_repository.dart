import 'package:sqflite/sqflite.dart';

import '../core/formatters/number_format.dart';
import '../models/payment_method.dart';
import '../services/app_refresh_controller.dart';
import 'payment_accounting_repository.dart';

class LoanRepository {
  const LoanRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;
  Future<List<Map<String, Object?>>> loans({bool completed = false}) =>
      db.rawQuery(
        '''SELECT l.*,d.name lender_name,COALESCE((SELECT SUM(amount_centavos) FROM loan_payments p WHERE p.loan_id=l.id AND p.status='POSTED'),0) paid_centavos FROM loans l JOIN loan_lenders d ON d.id=l.lender_id WHERE l.status=? ORDER BY l.start_date DESC,l.id DESC''',
        [completed ? 'COMPLETED' : 'ACTIVE'],
      );
  Future<List<Map<String, Object?>>> paymentsFor(int loanId) => db.query(
    'loan_payments',
    where: 'loan_id=?',
    whereArgs: [loanId],
    orderBy: 'paid_at DESC,id DESC',
  );
  Future<int> createLender(String name, {String? contact}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Lender name is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('loan_lenders', {
      'name': n,
      'contact_number': contact?.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, Object?>>> lenders() => db.query(
    'loan_lenders',
    where: 'is_archived=0',
    orderBy: 'name COLLATE NOCASE',
  );
  Future<int> create({
    required int lenderId,
    required int borrowed,
    required int agreed,
    required String sourceKind,
    required DateTime start,
    required String frequency,
    int? scheduled,
    DateTime? firstCollection,
    PaymentMethod? receivedMethod,
    String? notes,
  }) async {
    if (borrowed <= 0 || agreed <= 0 || agreed < borrowed) {
      throw ArgumentError('Check the loan amounts.');
    }
    if (sourceKind != 'NEW' && sourceKind != 'EXISTING') {
      throw ArgumentError('Choose a valid loan source.');
    }
    if (sourceKind == 'NEW' && receivedMethod == null) {
      throw ArgumentError('Choose how the loan was received.');
    }
    if (scheduled != null && scheduled <= 0) {
      throw ArgumentError('Expected payment must be positive.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.transaction((tx) async {
      final i = await tx.insert('loans', {
        'lender_id': lenderId,
        'source_kind': sourceKind,
        'borrowed_amount_centavos': borrowed,
        'agreed_repayment_centavos': agreed,
        'start_date': start.toUtc().toIso8601String(),
        'first_collection_date': firstCollection?.toUtc().toIso8601String(),
        'collection_frequency': frequency,
        'scheduled_amount_centavos': scheduled,
        'received_payment_method': receivedMethod?.dbValue,
        'notes': notes?.trim(),
        'status': 'ACTIVE',
        'created_at': now,
        'created_by': actorRole,
      });
      await tx.update(
        'loans',
        {'reference': 'L56-${i.toString().padLeft(6, '0')}'},
        where: 'id=?',
        whereArgs: [i],
      );
      if (sourceKind == 'NEW' &&
          receivedMethod != null &&
          receivedMethod != PaymentMethod.cash) {
        await PaymentAccountingRepository.postLoanGCashMovement(
          tx,
          wallet: receivedMethod,
          amountChangeCentavos: borrowed,
          loanId: i,
          actorRole: actorRole,
          occurredAt: now,
          notes: '5/6 loan received',
        );
      }
      await tx.insert('activity_logs', {
        'event_type': 'LOAN_CREATED',
        'description': '5/6 loan L56-${i.toString().padLeft(6, '0')} created',
        'actor_role': actorRole,
        'related_entity_type': 'LOAN',
        'related_entity_id': i,
        'created_at': now,
      });
      return i;
    });
    AppRefreshController.instance.dataChanged();
    return id;
  }

  /// Corrects an incorrectly entered principal without changing repayments.
  /// Cash receipts are derived from this value, so a closed day cannot be
  /// rewritten. Wallet receipts need a separate compensating ledger flow.
  Future<void> correctBorrowedAmount({
    required int loanId,
    required int borrowed,
    required String reason,
    bool ownerPinAuthorized = false,
  }) async {
    if (actorRole != 'OWNER' || !ownerPinAuthorized) {
      throw StateError('Owner PIN authorization is required.');
    }
    if (reason.trim().isEmpty) throw ArgumentError('A reason is required.');
    if (borrowed <= 0) throw ArgumentError('Borrowed amount must be positive.');
    await db.transaction((tx) async {
      final rows = await tx.query(
        'loans',
        columns: [
          'reference',
          'source_kind',
          'received_payment_method',
          'borrowed_amount_centavos',
          'agreed_repayment_centavos',
          'created_at',
        ],
        where: 'id=?',
        whereArgs: [loanId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Loan not found.');
      final loan = rows.single;
      final oldBorrowed = loan['borrowed_amount_centavos']! as int;
      final agreed = loan['agreed_repayment_centavos']! as int;
      if (borrowed == oldBorrowed) {
        throw ArgumentError('Enter a different borrowed amount.');
      }
      if (borrowed > agreed) {
        throw ArgumentError('Borrowed amount cannot exceed total to repay.');
      }
      if (loan['source_kind'] == 'NEW') {
        if (loan['received_payment_method'] != 'CASH') {
          throw StateError(
            'Wallet-funded loan amounts cannot be edited here because the original wallet entry must be preserved.',
          );
        }
        final created = DateTime.parse(loan['created_at']! as String).toLocal();
        final day =
            '${created.year.toString().padLeft(4, '0')}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';
        final closed = await tx.query(
          'daily_closing_snapshots',
          columns: ['id'],
          where: 'closing_date=?',
          whereArgs: [day],
          limit: 1,
        );
        if (closed.isNotEmpty) {
          throw StateError(
            'This loan belongs to a closed day. Its original cash receipt cannot be changed.',
          );
        }
      }
      await tx.update(
        'loans',
        {'borrowed_amount_centavos': borrowed},
        where: 'id=? AND borrowed_amount_centavos=?',
        whereArgs: [loanId, oldBorrowed],
      );
      await tx.insert('activity_logs', {
        'event_type': 'LOAN_PRINCIPAL_CORRECTED',
        'description':
            '5/6 loan ${loan['reference'] ?? loanId} borrowed amount corrected from ${standardMoney(oldBorrowed)} to ${standardMoney(borrowed)}. Reason: ${reason.trim()}',
        'actor_role': actorRole,
        'related_entity_type': 'LOAN',
        'related_entity_id': loanId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    AppRefreshController.instance.dataChanged();
  }

  Future<void> pay({
    required int loanId,
    required int amount,
    required PaymentMethod method,
    String? note,
    String? reference,
  }) async {
    await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        '''SELECT l.agreed_repayment_centavos,COALESCE(SUM(p.amount_centavos),0) paid FROM loans l LEFT JOIN loan_payments p ON p.loan_id=l.id AND p.status='POSTED' WHERE l.id=? AND l.status='ACTIVE' GROUP BY l.id''',
        [loanId],
      );
      if (rows.isEmpty) throw StateError('Active loan not found.');
      final r = rows.single,
          remaining =
              (r['agreed_repayment_centavos']! as int) - (r['paid']! as int);
      if (amount <= 0 || amount > remaining) {
        throw ArgumentError('Payment must not exceed the remaining balance.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert('loan_payments', {
        'loan_id': loanId,
        'amount_centavos': amount,
        'payment_method': method.dbValue,
        'payment_reference': reference?.trim(),
        'notes': note?.trim(),
        'paid_at': now,
        'created_at': now,
        'status': 'POSTED',
      });
      await tx.update(
        'loan_payments',
        {'reference': 'L5P-${id.toString().padLeft(6, '0')}'},
        where: 'id=?',
        whereArgs: [id],
      );
      if (method != PaymentMethod.cash) {
        await PaymentAccountingRepository.postLoanGCashMovement(
          tx,
          wallet: method,
          amountChangeCentavos: -amount,
          loanPaymentId: id,
          gcashReference: reference,
          actorRole: actorRole,
          occurredAt: now,
          notes: '5/6 loan payment',
        );
      }
      if (amount == remaining) {
        await tx.update(
          'loans',
          {'status': 'COMPLETED'},
          where: 'id=?',
          whereArgs: [loanId],
        );
      }
      await tx.insert('activity_logs', {
        'event_type': 'LOAN_PAYMENT_POSTED',
        'description':
            '5/6 loan payment L5P-${id.toString().padLeft(6, '0')} recorded',
        'actor_role': actorRole,
        'related_entity_type': 'LOAN_PAYMENT',
        'related_entity_id': id,
        'created_at': now,
      });
    });
    AppRefreshController.instance.dataChanged();
  }

  Future<void> reversePayment({
    required int paymentId,
    required String reason,
    bool ownerPinAuthorized = false,
  }) async {
    if (actorRole != 'OWNER' || !ownerPinAuthorized) {
      throw StateError('Owner PIN authorization is required.');
    }
    if (reason.trim().isEmpty) throw ArgumentError('A reason is required.');
    await db.transaction((tx) async {
      final rows = await tx.query(
        'loan_payments',
        where: "id=? AND status='POSTED'",
        whereArgs: [paymentId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Payment is unavailable or already reversed.');
      }
      final payment = rows.single;
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'loan_payments',
        {
          'status': 'REVERSED',
          'reversed_at': now,
          'reversal_reason': reason.trim(),
          'reversed_by': actorRole,
        },
        where: 'id=?',
        whereArgs: [paymentId],
      );
      await tx.update(
        'loans',
        {'status': 'ACTIVE'},
        where: 'id=?',
        whereArgs: [payment['loan_id']],
      );
      if (payment['payment_method'] == 'GCASH' ||
          payment['payment_method'] == 'MAYA') {
        await PaymentAccountingRepository.reverseLoanGCashPayment(
          tx,
          wallet: payment['payment_method'] == 'MAYA'
              ? PaymentMethod.maya
              : PaymentMethod.gcash,
          paymentId: paymentId,
          actorRole: actorRole,
          occurredAt: now,
          reason: reason.trim(),
        );
      }
      await tx.insert('activity_logs', {
        'event_type': 'LOAN_PAYMENT_REVERSED',
        'description': '5/6 loan payment reversed — ${reason.trim()}',
        'actor_role': actorRole,
        'related_entity_type': 'LOAN_PAYMENT',
        'related_entity_id': paymentId,
        'created_at': now,
      });
    });
    AppRefreshController.instance.dataChanged();
  }
}
