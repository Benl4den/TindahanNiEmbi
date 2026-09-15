import 'package:sqflite/sqflite.dart';

/// Popularity across unlike units: count each posted sale once per product.
Future<List<Map<String, Object?>>> productSalesRanking(
  Database db, {
  String? start,
  String? end,
  int limit = -1,
}) => db.rawQuery(
  '''
  SELECT p.id product_id,p.name, SUM(sold.quantity) quantity,
    SUM(sold.amount) sales_amount,COUNT(DISTINCT sold.transaction_key) sale_count,
    p.photo_path,p.base_unit_code,p.base_unit_label
  FROM (
    SELECT i.product_id,COALESCE(i.total_base_quantity,i.quantity) quantity,
      i.line_total_centavos amount,'C'||s.id transaction_key,s.occurred_at
    FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
    WHERE s.status='POSTED' AND (? IS NULL OR s.occurred_at>=?) AND (? IS NULL OR s.occurred_at<?)
    UNION ALL
    SELECT i.product_id,COALESCE(i.total_base_quantity,i.quantity),
      i.line_total_centavos,'U'||u.id,u.occurred_at
    FROM utang_transaction_items i JOIN utang_transactions u ON u.id=i.utang_transaction_id
    WHERE u.status='POSTED' AND (? IS NULL OR u.occurred_at>=?) AND (? IS NULL OR u.occurred_at<?)
  ) sold JOIN products p ON p.id=sold.product_id
  GROUP BY p.id
  ORDER BY sale_count DESC,MAX(sold.occurred_at) DESC,p.id ASC LIMIT ?
''',
  [start, start, end, end, start, start, end, end, limit],
);
