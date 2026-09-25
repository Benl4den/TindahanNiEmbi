import 'package:sqflite/sqflite.dart';

/// Popularity across unlike units: count each included sale once per product.
Future<List<Map<String, Object?>>> productSalesRanking(
  DatabaseExecutor db, {
  String? start,
  String? end,
  int limit = -1,
  bool includeReversed = false,
  bool useSaleSnapshots = false,
}) => db.rawQuery(
  '''
  WITH sold AS (
    SELECT i.product_id,COALESCE(i.total_base_quantity,i.quantity) quantity,
      i.line_total_centavos amount,'C'||s.id transaction_key,s.occurred_at,
      i.product_name_snapshot snapshot_name,i.base_unit_snapshot snapshot_unit
    FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
    WHERE s.status ${includeReversed ? "IN ('POSTED','REVERSED')" : "='POSTED'"} AND (? IS NULL OR s.occurred_at>=?) AND (? IS NULL OR s.occurred_at<?)
    UNION ALL
    SELECT i.product_id,COALESCE(i.total_base_quantity,i.quantity),
      i.line_total_centavos,'U'||u.id,u.occurred_at,
      i.product_name_snapshot,i.base_unit_snapshot
    FROM utang_transaction_items i JOIN utang_transactions u ON u.id=i.utang_transaction_id
    WHERE u.status ${includeReversed ? "IN ('POSTED','REVERSED')" : "='POSTED'"} AND (? IS NULL OR u.occurred_at>=?) AND (? IS NULL OR u.occurred_at<?)
  ), ranked AS (
    SELECT sold.*,ROW_NUMBER() OVER (
      PARTITION BY product_id ORDER BY occurred_at DESC,transaction_key DESC
    ) snapshot_rank FROM sold
  )
  SELECT p.id product_id,${useSaleSnapshots ? 'COALESCE(MAX(CASE WHEN sold.snapshot_rank=1 THEN sold.snapshot_name END),p.name)' : 'p.name'} name, SUM(sold.quantity) quantity,
    SUM(sold.amount) sales_amount,COUNT(DISTINCT sold.transaction_key) sale_count,
    p.photo_path,p.base_unit_code,${useSaleSnapshots ? 'COALESCE(MAX(CASE WHEN sold.snapshot_rank=1 THEN sold.snapshot_unit END),p.base_unit_label)' : 'p.base_unit_label'} base_unit_label
  FROM ranked sold JOIN products p ON p.id=sold.product_id
  GROUP BY p.id
  ORDER BY sale_count DESC,MAX(sold.occurred_at) DESC,p.id ASC LIMIT ?
''',
  [start, start, end, end, start, start, end, end, limit],
);
