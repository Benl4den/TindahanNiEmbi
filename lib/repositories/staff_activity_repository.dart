import 'package:sqflite/sqflite.dart';

class StaffActivitySummary {
  StaffActivitySummary({required this.name});
  final String name;
  int cashSales = 0;
  int cashSalesAmount = 0;
  int utangSales = 0;
  int utangSalesAmount = 0;
  int payments = 0;
  int paymentsAmount = 0;
  int cashIn = 0;
  int cashOut = 0;
  int serviceFees = 0;
  int expenses = 0;
  int expensesAmount = 0;
  int adjustments = 0;
}

class StaffActivityRepository {
  const StaffActivityRepository(this.db);
  final Database db;

  Future<List<StaffActivitySummary>> forDay(
    DateTime day, {
    bool includeWalletServices = true,
  }) async {
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
    final names = await db.rawQuery('''
      SELECT DISTINCT actor_name name FROM activity_logs
      WHERE actor_role='STAFF' AND actor_name IS NOT NULL AND trim(actor_name)<>''
      UNION
      SELECT name FROM staff_accounts
      UNION
      SELECT 'Staff (not recorded)' name
      WHERE EXISTS(SELECT 1 FROM activity_logs WHERE actor_role='STAFF' AND (actor_name IS NULL OR trim(actor_name)=''))
      ORDER BY name COLLATE NOCASE
    ''');
    final summaries = <String, StaffActivitySummary>{
      for (final row in names)
        row['name']! as String: StaffActivitySummary(
          name: row['name']! as String,
        ),
    };
    for (final summary in summaries.values) {
      final cash = await _metric(
        summary.name,
        start,
        end,
        'CASH_SALE',
        'cash_sales',
        's.total_centavos',
        "s.status='POSTED'",
      );
      summary.cashSales = cash.$1;
      summary.cashSalesAmount = cash.$2;
      final utang = await _metric(
        summary.name,
        start,
        end,
        'UTANG',
        'utang_transactions',
        's.total_centavos',
        "s.status='POSTED'",
      );
      summary.utangSales = utang.$1;
      summary.utangSalesAmount = utang.$2;
      final payments = await _metric(
        summary.name,
        start,
        end,
        'PAYMENT',
        'utang_payments',
        's.amount_centavos',
        "s.status='POSTED'",
      );
      summary.payments = payments.$1;
      summary.paymentsAmount = payments.$2;
      final expenses = await _metric(
        summary.name,
        start,
        end,
        'EXPENSE',
        'expenses',
        's.amount_centavos',
        "s.status='POSTED'",
      );
      summary.expenses = expenses.$1;
      summary.expensesAmount = expenses.$2;
      if (!includeWalletServices) continue;
      final actorWhere = _actorWhere(summary.name);
      final actorArgs = _actorArgs(summary.name);
      final services = await db.rawQuery(
        '''
        SELECT s.service_type,COUNT(DISTINCT s.id) count,COALESCE(SUM(s.fee_centavos),0) fees
        FROM activity_logs l JOIN gcash_service_transactions s ON s.id=l.related_entity_id
        WHERE l.related_entity_type='GCASH_SERVICE' AND $actorWhere
          AND l.created_at>=? AND l.created_at<? AND s.status='POSTED'
          AND NOT EXISTS(SELECT 1 FROM gcash_service_transactions r WHERE r.reversal_of_service_id=s.id)
        GROUP BY s.service_type
      ''',
        [...actorArgs, start, end],
      );
      for (final row in services) {
        if (row['service_type'] == 'CASH_IN') {
          summary.cashIn = row['count']! as int;
        }
        if (row['service_type'] == 'CASH_OUT') {
          summary.cashOut = row['count']! as int;
        }
        summary.serviceFees += row['fees']! as int;
      }
      final adjustments = await db.rawQuery(
        '''
        SELECT COUNT(*) count FROM activity_logs l
        WHERE $actorWhere AND created_at>=? AND created_at<?
          AND event_type IN('GCASH_ADJUSTMENT_IN','GCASH_ADJUSTMENT_OUT')
      ''',
        [...actorArgs, start, end],
      );
      summary.adjustments = adjustments.single['count']! as int;
    }
    return summaries.values.toList(growable: false);
  }

  Future<(int, int)> _metric(
    String name,
    String start,
    String end,
    String entityType,
    String table,
    String amountColumn,
    String status,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT s.id) count,COALESCE(SUM($amountColumn),0) amount
      FROM activity_logs l JOIN $table s ON s.id=l.related_entity_id
      WHERE l.related_entity_type=? AND ${_actorWhere(name)} AND l.created_at>=? AND l.created_at<? AND $status
    ''',
      [entityType, ..._actorArgs(name), start, end],
    );
    return (rows.single['count']! as int, rows.single['amount']! as int);
  }

  String _actorWhere(String name) => name == 'Staff (not recorded)'
      ? "l.actor_role='STAFF' AND (l.actor_name IS NULL OR trim(l.actor_name)='')"
      : 'l.actor_name=?';

  List<Object?> _actorArgs(String name) =>
      name == 'Staff (not recorded)' ? const [] : [name];
}
