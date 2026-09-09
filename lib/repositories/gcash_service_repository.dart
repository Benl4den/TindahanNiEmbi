import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/formatters/number_format.dart';

import '../services/app_refresh_controller.dart';
import 'payment_accounting_repository.dart';

class GCashServiceException implements Exception {
  const GCashServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GCashServiceTransaction {
  const GCashServiceTransaction({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.principalCentavos,
    required this.feeCentavos,
    required this.customerTotalCentavos,
    required this.physicalCashChangeCentavos,
    required this.gcashChangeCentavos,
    required this.createdAt,
    this.gcashReference,
    this.notes,
  });
  final int id, principalCentavos, feeCentavos, customerTotalCentavos;
  final int physicalCashChangeCentavos, gcashChangeCentavos;
  final String reference, type, status;
  final DateTime createdAt;
  final String? gcashReference, notes;
  factory GCashServiceTransaction.fromMap(Map<String, Object?> row) =>
      GCashServiceTransaction(
        id: row['id']! as int,
        reference: row['reference']! as String,
        type: row['service_type']! as String,
        status: (row['effective_status'] ?? row['status'])! as String,
        principalCentavos: row['principal_centavos']! as int,
        feeCentavos: row['fee_centavos']! as int,
        customerTotalCentavos: row['customer_total_centavos']! as int,
        physicalCashChangeCentavos:
            row['physical_cash_change_centavos']! as int,
        gcashChangeCentavos: row['gcash_change_centavos']! as int,
        createdAt: DateTime.parse(row['created_at']! as String),
        gcashReference: row['gcash_reference'] as String?,
        notes: row['notes'] as String?,
      );
}

class GCashServiceSummary {
  const GCashServiceSummary({
    required this.cashInCount,
    required this.cashOutCount,
    required this.cashInPrincipal,
    required this.cashOutPrincipal,
    required this.cashInFees,
    required this.cashOutFees,
    required this.physicalCashChange,
    required this.gcashChange,
  });
  final int cashInCount, cashOutCount, cashInPrincipal, cashOutPrincipal;
  final int cashInFees, cashOutFees, physicalCashChange, gcashChange;
  int get totalFeeIncome => cashInFees + cashOutFees;
}

class GCashServiceRepository {
  const GCashServiceRepository(this.db, {this.actorRole = 'OWNER'});
  final Database db;
  final String actorRole;
  static String newRequestId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<int> totalFeeIncome() async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END),0) FROM gcash_service_transactions",
        ),
      ) ??
      0;

  Future<int> availableGCashBalance() async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COALESCE(SUM(amount_change_centavos),0) FROM gcash_ledger_entries',
        ),
      ) ??
      0;

  Future<GCashServiceTransaction> record({
    required String type,
    required int principalCentavos,
    required int feeCentavos,
    String? gcashReference,
    String? notes,
    bool physicalCashAvailabilityAcknowledged = false,
    String? requestId,
  }) => AppRefreshController.instance.after(
    db.transaction((tx) async {
      final reference = 'GCS-${requestId ?? newRequestId()}';
      final existing = await tx.query(
        'gcash_service_transactions',
        where: 'reference=?',
        whereArgs: [reference],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['service_type'] != type ||
            row['principal_centavos'] != principalCentavos ||
            row['fee_centavos'] != feeCentavos ||
            row['gcash_reference'] !=
                PaymentAccountingRepository.normalizeReference(
                  gcashReference,
                ) ||
            row['notes'] !=
                PaymentAccountingRepository.normalizeReference(notes)) {
          throw const GCashServiceException(
            'This request was already saved with different details. Close and start a new service.',
          );
        }
        return GCashServiceTransaction.fromMap(row);
      }
      if (!const {'CASH_IN', 'CASH_OUT'}.contains(type) ||
          principalCentavos <= 0 ||
          feeCentavos < 0) {
        throw const GCashServiceException(
          'Enter a valid principal and service fee.',
        );
      }
      final total = principalCentavos + feeCentavos;
      if (principalCentavos > 100000000000 ||
          feeCentavos > 100000000000 ||
          total < principalCentavos) {
        throw const GCashServiceException('The amount is too large.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      // Fees are paid in physical cash for both service types.  GCash always
      // moves only the customer's requested principal.
      final gcashChange = type == 'CASH_IN'
          ? -principalCentavos
          : principalCentavos;
      if (type == 'CASH_IN') {
        final balance =
            Sqflite.firstIntValue(
              await tx.rawQuery(
                'SELECT COALESCE(SUM(amount_change_centavos),0) FROM gcash_ledger_entries',
              ),
            ) ??
            0;
        if (balance < principalCentavos) {
          throw GCashServiceException(
            'Insufficient GCash. Available: ${standardMoney(balance)}. '
            'Required: ${standardMoney(principalCentavos)}. '
            'Short: ${standardMoney(principalCentavos - balance)}.',
          );
        }
      } else if (!physicalCashAvailabilityAcknowledged) {
        // V18 has transaction-based cash movement but no opening-drawer balance.
        throw const GCashServiceException(
          'Confirm the available physical cash before Cash-Out.',
        );
      }
      final physicalChange = type == 'CASH_IN'
          ? total
          : -principalCentavos + feeCentavos;
      if (type == 'CASH_OUT' && feeCentavos >= principalCentavos) {
        throw const GCashServiceException(
          'Cash-Out fee must be less than the principal.',
        );
      }
      final id = await tx.insert('gcash_service_transactions', {
        'reference': reference,
        'service_type': type,
        'status': 'POSTED',
        'principal_centavos': principalCentavos,
        'fee_centavos': feeCentavos,
        'customer_total_centavos': total,
        'physical_cash_change_centavos': physicalChange,
        'gcash_change_centavos': gcashChange,
        'gcash_reference': PaymentAccountingRepository.normalizeReference(
          gcashReference,
        ),
        'notes': PaymentAccountingRepository.normalizeReference(notes),
        'created_by_role_snapshot': actorRole,
        'created_at': now,
      });
      await PaymentAccountingRepository.postGCashService(
        tx,
        serviceId: id,
        serviceType: type,
        amountChangeCentavos: gcashChange,
        gcashReference: gcashReference,
        actorRole: actorRole,
        notes: notes,
        occurredAt: now,
      );
      await tx.insert('activity_logs', {
        'event_type': 'GCASH_$type',
        'description':
            'GCash ${type == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'} $principalCentavos centavos.',
        'actor_role': actorRole,
        'related_entity_type': 'GCASH_SERVICE',
        'related_entity_id': id,
        'created_at': now,
      });
      return GCashServiceTransaction.fromMap(
        (await tx.query(
          'gcash_service_transactions',
          where: 'id=?',
          whereArgs: [id],
        )).single,
      );
    }),
  );

  Future<GCashServiceTransaction> reverse(
    int id, {
    required String reason,
    required bool ownerPinAuthorized,
  }) => AppRefreshController.instance.after(
    db.transaction((tx) async {
      if (actorRole != 'OWNER' ||
          !ownerPinAuthorized ||
          reason.trim().isEmpty) {
        throw const GCashServiceException(
          'Owner PIN authorization and a reason are required.',
        );
      }
      final original = await tx.query(
        'gcash_service_transactions',
        where: "id=? AND status='POSTED' AND NOT EXISTS(SELECT 1 FROM gcash_service_transactions r WHERE r.reversal_of_service_id=gcash_service_transactions.id)",
        whereArgs: [id],
      );
      if (original.isEmpty) {
        throw const GCashServiceException(
          'This service is unavailable or already reversed.',
        );
      }
      final row = original.single,
          now = DateTime.now().toUtc().toIso8601String();
      final reversalId = await tx.insert('gcash_service_transactions', {
        'reference': 'GCS-R-${DateTime.now().microsecondsSinceEpoch}',
        'service_type': row['service_type'],
        'status': 'REVERSAL',
        'principal_centavos': row['principal_centavos'],
        'fee_centavos': row['fee_centavos'],
        'customer_total_centavos': row['customer_total_centavos'],
        'physical_cash_change_centavos':
            -(row['physical_cash_change_centavos']! as int),
        'gcash_change_centavos': -(row['gcash_change_centavos']! as int),
        'gcash_reference': row['gcash_reference'],
        'notes': reason.trim(),
        'created_by_role_snapshot': actorRole,
        'reversal_of_service_id': id,
        'created_at': now,
      });
      await PaymentAccountingRepository.postGCashService(
        tx,
        serviceId: reversalId,
        isReversal: true,
        serviceType: row['service_type']! as String,
        amountChangeCentavos: -(row['gcash_change_centavos']! as int),
        gcashReference: row['gcash_reference'] as String?,
        actorRole: actorRole,
        notes: 'Reversal: ${reason.trim()}',
        occurredAt: now,
      );
      await tx.insert('activity_logs', {
        'event_type': 'GCASH_SERVICE_REVERSAL',
        'description':
            'GCash service ${row['reference']} reversed — ${reason.trim()}',
        'actor_role': actorRole,
        'related_entity_type': 'GCASH_SERVICE',
        'related_entity_id': reversalId,
        'created_at': now,
      });
      return GCashServiceTransaction.fromMap(
        (await tx.query(
          'gcash_service_transactions',
          where: 'id=?',
          whereArgs: [reversalId],
        )).single,
      );
    }),
  );

  Future<List<GCashServiceTransaction>> recent({int limit = 50}) async =>
      (await db.rawQuery(
        "SELECT s.*, CASE WHEN EXISTS(SELECT 1 FROM gcash_service_transactions r WHERE r.reversal_of_service_id=s.id) THEN 'REVERSED' ELSE s.status END effective_status FROM gcash_service_transactions s ORDER BY s.created_at DESC,s.id DESC LIMIT ?",
        [limit],
      )).map(GCashServiceTransaction.fromMap).toList(growable: false);

  Future<GCashServiceSummary> summary(DateTime day) async {
    final start = DateTime(
      day.year,
      day.month,
      day.day,
    ).toUtc().toIso8601String();
    final end = DateTime(
      day.year,
      day.month,
      day.day + 1,
    ).toUtc().toIso8601String();
    final row = (await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' AND status='POSTED' THEN 1 ELSE 0 END),0) ci_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' AND status='POSTED' THEN 1 ELSE 0 END),0) co_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN CASE WHEN status='REVERSAL' THEN -principal_centavos ELSE principal_centavos END ELSE 0 END),0) ci_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN CASE WHEN status='REVERSAL' THEN -principal_centavos ELSE principal_centavos END ELSE 0 END),0) co_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) ci_fee,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) co_fee,
      COALESCE(SUM(physical_cash_change_centavos),0) cash_change,
      COALESCE(SUM(gcash_change_centavos),0) gcash_change
      FROM gcash_service_transactions WHERE created_at>=? AND created_at<?''',
      [start, end],
    )).single;
    return GCashServiceSummary(
      cashInCount: row['ci_count']! as int,
      cashOutCount: row['co_count']! as int,
      cashInPrincipal: row['ci_principal']! as int,
      cashOutPrincipal: row['co_principal']! as int,
      cashInFees: row['ci_fee']! as int,
      cashOutFees: row['co_fee']! as int,
      physicalCashChange: row['cash_change']! as int,
      gcashChange: row['gcash_change']! as int,
    );
  }
}
