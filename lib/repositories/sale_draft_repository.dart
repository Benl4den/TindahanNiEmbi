import 'package:sqflite/sqflite.dart';

import '../features/transactions/product_selection_controller.dart';
import '../models/product.dart';
import '../models/product_unit.dart';

class SaleDraftRepository {
  const SaleDraftRepository(this.db);
  final Database db;

  Future<List<SaleCartLine>> load(List<Product> products) async {
    final byId = {for (final product in products) product.id: product};
    final rows = await db.query('active_sale_draft_items', orderBy: 'id');
    return rows
        .map((row) {
          final product = byId[row['product_id'] as int];
          if (product == null || product.isArchived) return null;
          final optionId = row['selling_option_id'] as int?;
          return SaleCartLine(
            product: product,
            option: SellingOption(
              id: optionId ?? -product.id,
              productId: product.id,
              name: row['selling_option_name']! as String,
              baseQuantity: row['base_quantity_per_unit']! as int,
              priceCentavos: row['unit_price_centavos']! as int,
              isDefault: false,
            ),
            quantityValue: row['quantity_value']! as int,
            quantityScale: row['quantity_scale']! as int,
          );
        })
        .whereType<SaleCartLine>()
        .toList(growable: false);
  }

  Future<void> save(List<SaleCartLine> lines) => db.transaction((tx) async {
    if (lines.isEmpty) {
      await tx.delete('active_sale_draft', where: 'id=1');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.insert('active_sale_draft', {
      'id': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await tx.update('active_sale_draft', {'updated_at': now}, where: 'id=1');
    await tx.delete('active_sale_draft_items', where: 'draft_id=1');
    for (final line in lines) {
      await tx.insert('active_sale_draft_items', {
        'draft_id': 1,
        'product_id': line.product.id,
        'selling_option_id': line.option.id > 0 ? line.option.id : null,
        'selling_option_name': line.option.name,
        'quantity_value': line.quantityValue,
        'quantity_scale': line.quantityScale,
        'base_quantity_per_unit': line.option.baseQuantity,
        'unit_price_centavos': line.option.priceCentavos,
        'created_at': now,
      });
    }
  });

  Future<void> clear() => db.delete('active_sale_draft', where: 'id=1');
}
