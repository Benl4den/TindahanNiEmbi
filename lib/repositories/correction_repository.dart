import 'package:sqflite/sqflite.dart';

import '../models/utang_draft.dart';
import 'cash_sale_repository.dart';
import 'payment_repository.dart';
import 'reversal_repository.dart';
import 'utang_repository.dart';

class CorrectionException implements Exception {
  const CorrectionException(this.message);
  final String message;
}

class CorrectionResult {
  const CorrectionResult(
    this.correctionId,
    this.replacementId,
    this.replacementReference,
  );
  final int correctionId, replacementId;
  final String replacementReference;
}

class CorrectionRepository {
  const CorrectionRepository(this.db, {this.actorRole = 'OWNER'});
  final Database db;
  final String actorRole;

  void _authorize(bool ownerPinAuthorized, String reason) {
    if (actorRole != 'OWNER' || !ownerPinAuthorized) {
      throw const CorrectionException('Owner PIN authorization is required.');
    }
    if (reason.trim().isEmpty) {
      throw const CorrectionException('Correction reason is required.');
    }
  }

  Future<CorrectionResult> correctCashSale({
    required int originalId,
    required List<UtangItemDraft> correctedItems,
    required String reason,
    required bool ownerPinAuthorized,
  }) async {
    _authorize(ownerPinAuthorized, reason);
    return db.transaction((tx) async {
      final reversal = await ReversalRepository(
        db,
        actorRole: actorRole,
      ).reverseCashSaleWith(tx, originalId, reason, ownerPinAuthorized: true);
      final replacement = await CashSaleRepository(
        db,
        actorRole: actorRole,
      ).saveWithExecutor(tx, correctedItems);
      final correction = await _link(
        tx,
        'CASH_SALE',
        originalId,
        replacement.id,
        reversal,
        reason,
        replacement.reference,
      );
      return CorrectionResult(
        correction,
        replacement.id,
        replacement.reference,
      );
    });
  }

  Future<CorrectionResult> correctUtang({
    required int originalId,
    required UtangDraft corrected,
    required String reason,
    required bool ownerPinAuthorized,
  }) async {
    _authorize(ownerPinAuthorized, reason);
    return db.transaction((tx) async {
      final reversal = await ReversalRepository(
        db,
        actorRole: actorRole,
      ).reverseUtangWith(tx, originalId, reason, ownerPinAuthorized: true);
      final replacementId = await UtangRepository(
        db,
        actorRole: actorRole,
      ).saveWithExecutor(tx, corrected);
      final reference = 'UTG-${replacementId.toString().padLeft(6, '0')}';
      final correction = await _link(
        tx,
        'UTANG',
        originalId,
        replacementId,
        reversal,
        reason,
        reference,
      );
      return CorrectionResult(correction, replacementId, reference);
    });
  }

  Future<CorrectionResult> correctPayment({
    required int originalId,
    required int correctedAmountCentavos,
    String? notes,
    required String reason,
    required bool ownerPinAuthorized,
  }) async {
    _authorize(ownerPinAuthorized, reason);
    if (correctedAmountCentavos <= 0) {
      throw const CorrectionException(
        'Corrected payment must be greater than zero.',
      );
    }
    return db.transaction((tx) async {
      final original = await tx.query(
        'utang_payments',
        where: "id=? AND status='POSTED'",
        whereArgs: [originalId],
        limit: 1,
      );
      if (original.isEmpty) {
        throw const CorrectionException(
          'Payment is unavailable or already reversed.',
        );
      }
      final reversal = await ReversalRepository(
        db,
        actorRole: actorRole,
      ).reversePaymentWith(tx, originalId, reason, ownerPinAuthorized: true);
      final replacementId = await PaymentRepository(db, actorRole: actorRole)
          .recordWithExecutor(
            tx,
            customerId: original.single['customer_id']! as int,
            amountCentavos: correctedAmountCentavos,
            notes: notes,
          );
      final reference = 'PAY-${replacementId.toString().padLeft(6, '0')}';
      final correction = await _link(
        tx,
        'PAYMENT',
        originalId,
        replacementId,
        reversal,
        reason,
        reference,
      );
      return CorrectionResult(correction, replacementId, reference);
    });
  }

  Future<int> _link(
    DatabaseExecutor tx,
    String type,
    int original,
    int replacement,
    int reversal,
    String reason,
    String replacementReference,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await tx.insert('transaction_corrections', {
      'reference': 'COR-${DateTime.now().microsecondsSinceEpoch}',
      'transaction_reversal_id': reversal,
      'entity_type': type,
      'original_entity_id': original,
      'replacement_entity_id': replacement,
      'reason': reason.trim(),
      'occurred_at': now,
      'created_at': now,
    });
    await tx.insert('activity_logs', {
      'event_type': 'TRANSACTION_CORRECTED',
      'description':
          '$type #$original corrected to $replacementReference. Reason: ${reason.trim()}',
      'actor_role': actorRole,
      'related_entity_type': type,
      'related_entity_id': original,
      'created_at': now,
    });
    return id;
  }

  Future<Map<String, Object?>?> relationship(String type, int id) async {
    final rows = await db.rawQuery(
      '''SELECT c.*,r.reference reversal_reference,r.occurred_at reversal_at
      FROM transaction_corrections c JOIN transaction_reversals r ON r.id=c.transaction_reversal_id
      WHERE c.entity_type=? AND (c.original_entity_id=? OR c.replacement_entity_id=?) LIMIT 1''',
      [type, id, id],
    );
    return rows.isEmpty ? null : rows.single;
  }
}
