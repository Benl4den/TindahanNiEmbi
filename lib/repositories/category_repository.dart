import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../services/app_refresh_controller.dart';

class DuplicateCategoryNameException implements Exception {
  const DuplicateCategoryNameException();
}

class InvalidCategoryNameException implements Exception {
  const InvalidCategoryNameException();
}

class CategoryNotFoundException implements Exception {
  const CategoryNotFoundException();
}

abstract interface class CategoryRepository {
  Future<List<Category>> getActive();
  Future<Category> create(String name);
  Future<Category> update({required int id, required String name});
  Future<void> archive(int id);
}

class SqliteCategoryRepository implements CategoryRepository {
  const SqliteCategoryRepository(this._database);

  final Database _database;

  static const defaultPhilippineCategories = <String>[
    'Soft Drinks',
    'Water & Beverages',
    'Coffee & Powdered Drinks',
    'Rice',
    'Cooking Oil',
    'Canned Goods',
    'Instant Noodles',
    'Snacks & Chips',
    'Biscuits & Crackers',
    'Candy & Chocolates',
    'Bread & Bakery',
    'Eggs',
    'Condiments & Seasonings',
    'Sugar & Cooking Ingredients',
    'Milk & Creamer',
    'Cigarettes & Tobacco',
    'Beer & Alcoholic Drinks',
    'Frozen Foods',
    'Ice & Frozen Treats',
    'Shampoo & Hair Care',
    'Soap & Body Care',
    'Laundry Products',
    'Dishwashing & Cleaning',
    'Dental Care',
    'Personal Care',
    'Baby Products',
    'Household Supplies',
    'School & Office Supplies',
    'Medicine / OTC',
    'Mobile Load & Services',
    'Other',
  ];

  Future<void> ensureDefaultCategories() async {
    await _database.transaction((tx) async {
      final existing = await tx.query('categories', columns: ['name']);
      final names = existing
          .map((x) => _comparisonKey(x['name']! as String))
          .toSet();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final name in defaultPhilippineCategories) {
        if (!names.add(_comparisonKey(name))) continue;
        await tx.insert('categories', {
          'name': name,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  @override
  Future<List<Category>> getActive() async {
    final rows = await _database.query(
      'categories',
      where: 'is_archived = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Category.fromMap).toList(growable: false);
  }

  @override
  Future<Category> create(String name) async {
    final normalizedName = _normalize(name);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final id = await _database.insert('categories', {
        'name': normalizedName,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
      final category = (await _findById(id))!;
      AppRefreshController.instance.dataChanged();
      return category;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateCategoryNameException();
      }
      rethrow;
    }
  }

  @override
  Future<Category> update({required int id, required String name}) async {
    final normalizedName = _normalize(name);
    try {
      final changed = await _database.update(
        'categories',
        {
          'name': normalizedName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND is_archived = 0',
        whereArgs: [id],
      );
      if (changed == 0) throw const CategoryNotFoundException();
      final category = (await _findById(id))!;
      AppRefreshController.instance.dataChanged();
      return category;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateCategoryNameException();
      }
      rethrow;
    }
  }

  @override
  Future<void> archive(int id) async {
    final changed = await _database.update(
      'categories',
      {
        'is_archived': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
    );
    if (changed == 0) throw const CategoryNotFoundException();
    AppRefreshController.instance.dataChanged();
  }

  Future<Category?> _findById(int id) async {
    final rows = await _database.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Category.fromMap(rows.single);
  }

  String _normalize(String name) {
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) throw const InvalidCategoryNameException();
    return normalized;
  }

  String _comparisonKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
