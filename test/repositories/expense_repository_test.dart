import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/expense.dart';
import 'package:tindahan_ni_embi/repositories/expense_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/services/data_integrity_service.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late ExpenseRepository repository;
  late int category;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    repository = ExpenseRepository(db);
    category = (await repository.categories()).first.id;
  });
  tearDown(() => app.close());
  ExpenseDraft draft(int cents, {int? categoryId, DateTime? when}) =>
      ExpenseDraft(
        categoryId: categoryId ?? category,
        amountCentavos: cents,
        description: 'Electric bill',
        expenseDateTime: when ?? DateTime.now(),
        notes: 'September',
        referenceNo: 'BILL-1',
      );

  test(
    'adds centavo-precise expense with unique reference and snapshot',
    () async {
      final first = await repository.add(draft(205001));
      final second = await repository.add(draft(1));
      expect(first.reference, 'EXP-000001');
      expect(second.reference, 'EXP-000002');
      expect(first.amountCentavos, 205001);
      expect(first.categoryName, isNotEmpty);
      await expectLater(
        repository.add(
          ExpenseDraft(
            categoryId: category,
            amountCentavos: 0,
            description: 'Bad',
            expenseDateTime: DateTime.now(),
          ),
        ),
        throwsA(isA<ExpenseException>()),
      );
      await expectLater(
        db.update(
          'expenses',
          {'amount_centavos': 2},
          where: 'id=?',
          whereArgs: [first.id],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.delete('expenses', where: 'id=?', whereArgs: [first.id]),
        throwsA(anything),
      );
    },
  );

  test(
    'archived category remains visible historically but rejects new expense',
    () async {
      final expense = await repository.add(draft(100));
      await repository.archiveCategory(category);
      expect(
        (await repository.get(expense.id)).categoryName,
        expense.categoryName,
      );
      expect(
        (await repository.categories()).any((x) => x.id == category),
        isFalse,
      );
      await expectLater(
        repository.add(draft(200)),
        throwsA(isA<ExpenseException>()),
      );
    },
  );

  test(
    'correction preserves original, links replacement, and uses net totals',
    () async {
      final original = await repository.add(draft(250000));
      final replacement = await repository.correct(
        original.id,
        draft(205000),
        reason: 'Wrong amount',
        ownerPinAuthorized: true,
      );
      final old = await repository.get(original.id);
      expect(old.status, 'CORRECTED');
      expect(old.correctedByReference, replacement.reference);
      expect(
        (await repository.get(replacement.id)).correctionOfReference,
        original.reference,
      );
      final daily = await OperationsRepository(db).daily(DateTime.now());
      expect(daily.operatingExpenses, 205000);
      expect(daily.netRecordedCash, -205000);
      await expectLater(
        repository.reverse(
          original.id,
          reason: 'Again',
          ownerPinAuthorized: true,
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'reverse preserves original, creates no replacement, and excludes totals',
    () async {
      final original = await repository.add(draft(70000));
      await repository.reverse(
        original.id,
        reason: 'Duplicate',
        ownerPinAuthorized: true,
      );
      expect((await repository.get(original.id)).status, 'REVERSED');
      expect(await db.query('expenses'), hasLength(1));
      expect(
        (await OperationsRepository(db).daily(DateTime.now()))
            .operatingExpenses,
        0,
      );
      await expectLater(
        repository.reverse(
          original.id,
          reason: 'Again',
          ownerPinAuthorized: true,
        ),
        throwsA(anything),
      );
    },
  );

  test('security and reason are enforced before writes', () async {
    final expense = await repository.add(draft(100));
    await expectLater(
      repository.correct(
        expense.id,
        draft(200),
        reason: '',
        ownerPinAuthorized: true,
      ),
      throwsA(isA<ExpenseException>()),
    );
    await expectLater(
      repository.reverse(
        expense.id,
        reason: 'Wrong',
        ownerPinAuthorized: false,
      ),
      throwsA(isA<ExpenseException>()),
    );
    await expectLater(
      ExpenseRepository(db, actorRole: 'STAFF').add(draft(100)),
      throwsA(isA<ExpenseException>()),
    );
    expect(await db.query('expense_reversals'), isEmpty);
  });

  test('reports filter by category and integrity is healthy', () async {
    final other = await repository.addCategory('Custom');
    await repository.add(draft(100));
    await repository.add(draft(300, categoryId: other));
    final reports = ReportsRepository(db);
    expect((await reports.expenseSummary())['total'], 400);
    expect((await reports.expenseSummary(categoryId: other))['total'], 300);
    expect(await reports.expensesByCategory(), hasLength(2));
    final integrity = await DataIntegrityService(db).check();
    expect(
      integrity.sections.singleWhere((x) => x.name == 'Expenses').healthy,
      isTrue,
    );
  });
}
