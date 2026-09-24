import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

enum ProductInsightsRange {
  last7Days('Last 7 Days'),
  last30Days('Last 30 Days'),
  last3Months('Last 3 Months'),
  thisYear('This Year'),
  allTime('All Time');

  const ProductInsightsRange(this.label);
  final String label;

  DateTime? start(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      last7Days => today.subtract(const Duration(days: 6)),
      last30Days => today.subtract(const Duration(days: 29)),
      last3Months => DateTime(now.year, now.month - 2),
      thisYear => DateTime(now.year),
      allTime => null,
    };
  }
}

class ProductInsights {
  const ProductInsights({
    required this.soldBaseQuantity,
    required this.totalSalesCentavos,
    required this.grossProfitCentavos,
    required this.averageDailyBaseQuantity,
    required this.estimatedDaysOfStock,
    required this.restockFrequency,
    required this.recentRestockUnitCostsCentavos,
    required this.saleCount,
    required this.periodDays,
    required this.profitEstimated,
  });

  final int soldBaseQuantity;
  final int totalSalesCentavos;

  /// Null means some sold items lack a recorded historical cost.
  final int? grossProfitCentavos;
  final double averageDailyBaseQuantity;
  final double? estimatedDaysOfStock;
  final int restockFrequency;
  final List<int> recentRestockUnitCostsCentavos;
  final int saleCount;
  final int periodDays;
  final bool profitEstimated;

  double? get profitMargin => totalSalesCentavos == 0
      ? 0
      : grossProfitCentavos == null
      ? null
      : grossProfitCentavos! * 100 / totalSalesCentavos;

  String get performance {
    if (saleCount == 0) return 'No recent sales';
    final salesPerDay = saleCount / periodDays;
    if (salesPerDay >= 0.5) return 'Selling well';
    if (salesPerDay >= 0.1) return 'Steady';
    return 'Slow moving';
  }
}

/// Read-only insights from posted sale items and inventory movements. Never
/// estimates historical profit from today's editable product cost.
class ProductInsightsRepository {
  const ProductInsightsRepository(this.db);
  final Database db;

  Future<ProductInsights> load(
    Product product,
    ProductInsightsRange range, {
    DateTime? now,
  }) async {
    final endLocal = now ?? DateTime.now();
    final startLocal = range.start(endLocal);
    final start = startLocal?.toUtc().toIso8601String();
    final end = endLocal.toUtc().toIso8601String();
    final sales = <Map<String, Object?>>[];
    for (final (
          prefix,
          table,
          parent,
          foreignKey,
          allocationKey,
          attributionKey,
        )
        in [
          (
            'C',
            'cash_sale_items',
            'cash_sales',
            'cash_sale_id',
            'cash_sale_item_id',
            'cash_sale_item_id',
          ),
          (
            'U',
            'utang_transaction_items',
            'utang_transactions',
            'utang_transaction_id',
            'utang_item_id',
            'utang_item_id',
          ),
        ]) {
      sales.addAll(
        await db.rawQuery(
          '''SELECT i.line_total_centavos revenue,
          COALESCE(i.total_base_quantity,i.quantity) base_quantity,
          s.occurred_at,'$prefix' || s.id transaction_key,
          (SELECT SUM(COALESCE(a.actual_payable_centavos,a.payable_centavos))
             FROM consignment_allocations a WHERE a.$allocationKey=i.id) allocated_cost,
          (SELECT a.cost_centavos FROM brand_sale_attributions a
             WHERE a.$attributionKey=i.id ORDER BY a.id LIMIT 1) attributed_cost,
          (SELECT a.is_estimate FROM brand_sale_attributions a
             WHERE a.$attributionKey=i.id ORDER BY a.id LIMIT 1) attributed_estimate
          FROM $table i JOIN $parent s ON s.id=i.$foreignKey
          WHERE i.product_id=? AND s.status='POSTED'
            AND (? IS NULL OR s.occurred_at>=?) AND s.occurred_at<?
          ORDER BY s.occurred_at,i.id''',
          [product.id, start, start, end],
        ),
      );
    }

    final purchases = await db.rawQuery(
      '''SELECT t.id transaction_id,t.type,t.occurred_at,m.quantity_change,
        m.unit_cost_centavos,COALESCE(m.entered_quantity,m.quantity_change) entered_quantity
        FROM inventory_movements m
        JOIN inventory_transactions t ON t.id=m.inventory_transaction_id
        WHERE m.product_id=? AND t.type IN('INITIAL_STOCK','STOCK_IN')
          AND m.quantity_change>0 AND t.occurred_at<?
        ORDER BY t.occurred_at,m.id''',
      [product.id, end],
    );

    var sold = 0, revenue = 0, knownCost = 0;
    final saleKeys = <String>{};
    var missingCost = false;
    var profitEstimated = false;
    DateTime? firstSale;
    for (final sale in sales) {
      final quantity = sale['base_quantity']! as int;
      sold += quantity;
      revenue += sale['revenue']! as int;
      saleKeys.add(sale['transaction_key']! as String);
      final occurred = DateTime.parse(sale['occurred_at']! as String);
      if (firstSale == null || occurred.isBefore(firstSale)) {
        firstSale = occurred;
      }
      final snapshotCost =
          (sale['allocated_cost'] ?? sale['attributed_cost']) as int?;
      if (snapshotCost != null) {
        knownCost += snapshotCost;
        if (sale['allocated_cost'] == null &&
            sale['attributed_estimate'] == 1) {
          profitEstimated = true;
        }
        continue;
      }
      Map<String, Object?>? lastPurchase;
      for (final purchase in purchases) {
        if ((purchase['unit_cost_centavos'] as int?) == null) continue;
        if (DateTime.parse(purchase['occurred_at']! as String)
            .isAfter(occurred)) {
          break;
        }
        lastPurchase = purchase;
      }
      if (lastPurchase == null) {
        missingCost = true;
      } else {
        profitEstimated = true;
        final packageCost = lastPurchase['unit_cost_centavos']! as int;
        final entered = lastPurchase['entered_quantity']! as int;
        final base = lastPurchase['quantity_change']! as int;
        knownCost += (quantity * packageCost * entered + base ~/ 2) ~/ base;
      }
    }

    final periodStart = startLocal ?? firstSale?.toLocal() ?? endLocal;
    final days =
        endLocal
            .difference(
              DateTime(periodStart.year, periodStart.month, periodStart.day),
            )
            .inDays +
        1;
    final periodDays = days < 1 ? 1 : days;
    final average = sold / periodDays;
    final restocks = purchases.where((row) {
      if (row['type'] != 'STOCK_IN') return false;
      return start == null ||
          (row['occurred_at']! as String).compareTo(start) >= 0;
    }).toList();
    final restockIds = restocks
        .map((row) => row['transaction_id']! as int)
        .toSet();
    final costs = restocks
        .where((row) => row['unit_cost_centavos'] != null)
        .map((row) {
          final cost = row['unit_cost_centavos']! as int;
          final entered = row['entered_quantity']! as int;
          final base = row['quantity_change']! as int;
          final currentPackageBase = product.defaultPurchaseBaseQuantity ?? 1;
          return (cost * entered * currentPackageBase + base ~/ 2) ~/ base;
        })
        .toList();

    return ProductInsights(
      soldBaseQuantity: sold,
      totalSalesCentavos: revenue,
      grossProfitCentavos: missingCost ? null : revenue - knownCost,
      averageDailyBaseQuantity: average,
      estimatedDaysOfStock: average <= 0
          ? null
          : product.currentQuantity / average,
      restockFrequency: restockIds.length,
      recentRestockUnitCostsCentavos: costs.length <= 3
          ? costs
          : costs.sublist(costs.length - 3),
      saleCount: saleKeys.length,
      periodDays: periodDays,
      profitEstimated: profitEstimated,
    );
  }
}
