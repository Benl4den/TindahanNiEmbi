import 'package:sqflite/sqflite.dart';

class ConsignmentAllocation {
  /// Allocates supplier-owned units oldest receipt first (FIFO). This snapshots
  /// batch cost so later price changes cannot rewrite payable or margin history.
  static Future<void> postSale(
    DatabaseExecutor tx, {
    required int productId,
    required int quantity,
    required int sellingPriceCentavos,
    int? totalSaleCentavos,
    int? cashSaleItemId,
    int? utangItemId,
    required String occurredAt,
  }) async {
    var remaining = quantity;
    var remainingRevenue = totalSaleCentavos ?? sellingPriceCentavos * quantity;
    final batches = await tx.rawQuery(
      '''SELECT b.*, c.name consignor_name FROM consignment_batches b
      JOIN consignors c ON c.id=b.consignor_id
      WHERE b.product_id=? AND b.units_received-b.units_allocated-b.units_returned>0
      ORDER BY b.received_at,b.id''',
      [productId],
    );
    for (final batch in batches) {
      if (remaining == 0) break;
      final available =
          (batch['units_received']! as int) -
          (batch['units_allocated']! as int) -
          (batch['units_returned']! as int);
      final take = remaining < available ? remaining : available;
      final cost = batch['unit_cost_centavos']! as int;
      final revenue = take == remaining
          ? remainingRevenue
          : (remainingRevenue * take) ~/ remaining;
      final actualMargin = revenue - take * cost;
      final allocationId = await tx.insert('consignment_allocations', {
        'batch_id': batch['id'],
        'cash_sale_item_id': cashSaleItemId,
        'utang_item_id': utangItemId,
        'quantity': take,
        'unit_cost_centavos': cost,
        'selling_price_centavos': sellingPriceCentavos,
        'payable_centavos': take * cost,
        'margin_centavos': take * (sellingPriceCentavos - cost),
        'sale_revenue_centavos': revenue,
        'actual_margin_centavos': actualMargin,
        'occurred_at': occurredAt,
      });
      await tx.update(
        'consignment_batches',
        {'units_allocated': (batch['units_allocated']! as int) + take},
        where: 'id=?',
        whereArgs: [batch['id']],
      );
      await tx.insert('consignor_ledger_entries', {
        'consignor_id': batch['consignor_id'],
        'entry_type': 'SALE',
        'amount_change_centavos': take * cost,
        'allocation_id': allocationId,
        'description': '$take consigned unit(s) sold',
        'occurred_at': occurredAt,
        'created_at': occurredAt,
      });
      remaining -= take;
      remainingRevenue -= revenue;
    }
  }
}
