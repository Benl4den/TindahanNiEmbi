import 'package:sqflite/sqflite.dart';

import '../models/expense.dart';
import '../services/app_refresh_controller.dart';

class ExpenseException implements Exception {
  const ExpenseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExpenseSummary {
  const ExpenseSummary(this.total, this.count, this.largest, this.topCategory);
  final int total, count, largest;
  final String? topCategory;
}

class ExpenseRepository {
  const ExpenseRepository(this.db, {this.actorRole = 'OWNER'});
  final Database db;
  final String actorRole;

  Future<List<ExpenseCategory>> categories({bool activeOnly = true}) async =>
      (await db.query(
        'expense_categories',
        where: activeOnly ? 'is_archived=0' : null,
        orderBy: 'name COLLATE NOCASE',
      )).map(ExpenseCategory.fromMap).toList();

  Future<int> addCategory(String name) async {
    _owner();
    final value = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) {
      throw const ExpenseException('Category name is required.');
    }
    try {
      final id = await db.insert('expense_categories', {
        'name': value,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      AppRefreshController.instance.dataChanged();
      return id;
    } on DatabaseException {
      throw const ExpenseException('That expense category already exists.');
    }
  }

  Future<void> archiveCategory(int id) async {
    _owner();
    await db.update(
      'expense_categories',
      {
        'is_archived': 1,
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND is_archived=0',
      whereArgs: [id],
    );
    AppRefreshController.instance.dataChanged();
  }

  Future<Expense> add(ExpenseDraft draft) => AppRefreshController.instance
      .after(db.transaction((tx) => _add(tx, draft)));

  Future<Expense> _add(DatabaseExecutor tx, ExpenseDraft draft) async {
    _owner();
    _validate(draft);
    final category = await tx.query(
      'expense_categories',
      where: 'id=? AND is_archived=0',
      whereArgs: [draft.categoryId],
      limit: 1,
    );
    if (category.isEmpty) {
      throw const ExpenseException('Please select an active expense category.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final next = await tx.rawQuery(
      'SELECT COALESCE(MAX(id),0)+1 id FROM expenses',
    );
    final id = next.single['id']! as int;
    final reference = 'EXP-${id.toString().padLeft(6, '0')}';
    await tx.insert('expenses', {
      'id': id,
      'expense_ref': reference,
      'category_id': draft.categoryId,
      'category_name_snapshot': category.single['name'],
      'amount_centavos': draft.amountCentavos,
      'description': draft.description.trim().replaceAll(RegExp(r'\s+'), ' '),
      'notes': _optional(draft.notes),
      'reference_no': _optional(draft.referenceNo),
      'expense_datetime': draft.expenseDateTime.toUtc().toIso8601String(),
      'created_at': now,
      'created_by_role': actorRole,
    });
    await tx.insert('activity_logs', {
      'event_type': 'EXPENSE_ADDED',
      'description':
          '$reference added. ${category.single['name']} — ${draft.amountCentavos} centavos',
      'actor_role': actorRole,
      'related_entity_type': 'EXPENSE',
      'related_entity_id': id,
      'created_at': now,
    });
    return (await _query(tx, where: 'e.id=?', args: [id])).single;
  }

  Future<List<Expense>> list({
    String query = '',
    int? categoryId,
    DateTime? from,
    DateTime? to,
  }) async {
    final clauses = <String>[], args = <Object?>[];
    if (query.trim().isNotEmpty) {
      clauses.add(
        '(e.description LIKE ? OR e.expense_ref LIKE ? OR e.category_name_snapshot LIKE ?)',
      );
      final q = '%${query.trim()}%';
      args.addAll([q, q, q]);
    }
    if (categoryId != null) {
      clauses.add('e.category_id=?');
      args.add(categoryId);
    }
    if (from != null) {
      clauses.add('e.expense_datetime>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      clauses.add('e.expense_datetime<?');
      args.add(to.toUtc().toIso8601String());
    }
    return _query(
      db,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      args: args,
    );
  }

  Future<Expense> get(int id) async =>
      (await _query(db, where: 'e.id=?', args: [id])).single;

  Future<ExpenseSummary> summary(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount_centavos),0) total,
      COUNT(*) count,COALESCE(MAX(amount_centavos),0) largest FROM expenses
      WHERE status='POSTED' AND expense_datetime>=? AND expense_datetime<?''',
      [start.toUtc().toIso8601String(), end.toUtc().toIso8601String()],
    );
    final top = await db.rawQuery(
      '''SELECT category_name_snapshot name,COUNT(*) count
      FROM expenses WHERE status='POSTED' AND expense_datetime>=? AND expense_datetime<?
      GROUP BY category_name_snapshot ORDER BY count DESC,name COLLATE NOCASE LIMIT 1''',
      [start.toUtc().toIso8601String(), end.toUtc().toIso8601String()],
    );
    final x = rows.single;
    return ExpenseSummary(
      x['total']! as int,
      x['count']! as int,
      x['largest']! as int,
      top.isEmpty ? null : top.single['name']! as String,
    );
  }

  Future<Expense> correct(
    int id,
    ExpenseDraft corrected, {
    required String reason,
    required bool ownerPinAuthorized,
  }) async {
    _authorize(reason, ownerPinAuthorized);
    return AppRefreshController.instance.after(
      db.transaction((tx) async {
        final original = await _posted(tx, id);
        final reversalId = await _reverse(tx, original, reason, 'CORRECTED');
        final replacement = await _add(tx, corrected);
        final now = DateTime.now().toUtc().toIso8601String();
        await tx.insert('expense_corrections', {
          'original_expense_id': id,
          'replacement_expense_id': replacement.id,
          'expense_reversal_id': reversalId,
          'reason': reason.trim(),
          'occurred_at': now,
        });
        await tx.insert('activity_logs', {
          'event_type': 'EXPENSE_CORRECTED',
          'description':
              '${original.reference} corrected to ${replacement.reference}. Reason: ${reason.trim()}',
          'actor_role': actorRole,
          'related_entity_type': 'EXPENSE',
          'related_entity_id': id,
          'created_at': now,
        });
        return replacement;
      }),
    );
  }

  Future<void> reverse(
    int id, {
    required String reason,
    required bool ownerPinAuthorized,
  }) async {
    _authorize(reason, ownerPinAuthorized);
    await db.transaction((tx) async {
      final original = await _posted(tx, id);
      await _reverse(tx, original, reason, 'REVERSED');
      await tx.insert('activity_logs', {
        'event_type': 'EXPENSE_REVERSED',
        'description':
            '${original.reference} reversed. Reason: ${reason.trim()}',
        'actor_role': actorRole,
        'related_entity_type': 'EXPENSE',
        'related_entity_id': id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    AppRefreshController.instance.dataChanged();
  }

  Future<int> _reverse(
    DatabaseExecutor tx,
    Expense original,
    String reason,
    String status,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final reversal = await tx.insert('expense_reversals', {
      'expense_id': original.id,
      'reason': reason.trim(),
      'occurred_at': now,
      'actor_role': actorRole,
    });
    final changed = await tx.update(
      'expenses',
      {'status': status},
      where: "id=? AND status='POSTED'",
      whereArgs: [original.id],
    );
    if (changed != 1) {
      throw const ExpenseException(
        'This expense was already corrected or reversed.',
      );
    }
    return reversal;
  }

  Future<Expense> _posted(DatabaseExecutor tx, int id) async {
    final rows = await _query(
      tx,
      where: "e.id=? AND e.status='POSTED'",
      args: [id],
    );
    if (rows.isEmpty) {
      throw const ExpenseException(
        'This expense was already corrected or reversed.',
      );
    }
    return rows.single;
  }

  Future<List<Expense>> _query(
    DatabaseExecutor executor, {
    String? where,
    List<Object?> args = const [],
  }) async => (await executor.rawQuery(
    '''SELECT e.*,
      replacement.expense_ref corrected_by_ref,original.expense_ref correction_of_ref,
      COALESCE(c1.reason,c2.reason,r.reason) change_reason,
      COALESCE(c1.occurred_at,c2.occurred_at,r.occurred_at) changed_at
      FROM expenses e
      LEFT JOIN expense_corrections c1 ON c1.original_expense_id=e.id
      LEFT JOIN expenses replacement ON replacement.id=c1.replacement_expense_id
      LEFT JOIN expense_corrections c2 ON c2.replacement_expense_id=e.id
      LEFT JOIN expenses original ON original.id=c2.original_expense_id
      LEFT JOIN expense_reversals r ON r.expense_id=e.id
      ${where == null ? '' : 'WHERE $where'} ORDER BY e.expense_datetime DESC,e.id DESC''',
    args,
  )).map(Expense.fromMap).toList();

  void _owner() {
    if (actorRole != 'OWNER') {
      throw const ExpenseException('Owner permission is required.');
    }
  }

  void _authorize(String reason, bool pin) {
    _owner();
    if (!pin) {
      throw const ExpenseException('Owner PIN authorization is required.');
    }
    if (reason.trim().isEmpty) {
      throw const ExpenseException('A reason is required.');
    }
  }

  void _validate(ExpenseDraft d) {
    if (d.amountCentavos <= 0) {
      throw const ExpenseException('Amount must be greater than zero.');
    }
    if (d.description.trim().isEmpty) {
      throw const ExpenseException('Description is required.');
    }
  }

  String? _optional(String? value) =>
      value?.trim().isEmpty ?? true ? null : value!.trim();
}
