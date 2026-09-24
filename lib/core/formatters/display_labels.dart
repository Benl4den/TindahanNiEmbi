/// Translates stored codes only when displaying them to users.
abstract final class DisplayLabels {
  static String status(Object? code) => switch (code) {
    'POSTED' => 'Completed',
    'REVERSED' || 'REVERSAL' => 'Cancelled',
    'CORRECTED' => 'Fixed',
    _ => 'Not recorded',
  };

  static String paymentMethod(Object? code) => switch (code) {
    'CASH' => 'Cash',
    'GCASH' => 'GCash',
    'MAYA' => 'Maya',
    _ => 'Not recorded',
  };

  static String movement(Object? code) => switch (code) {
    'INITIAL_STOCK' => 'Starting Stock',
    'STOCK_IN' => 'Stock In',
    'STOCK_OUT' => 'Stock Out',
    'ADJUSTMENT_IN' => 'Stock Corrected (Added)',
    'ADJUSTMENT_OUT' => 'Stock Corrected (Removed)',
    'SALE' || 'CASH_SALE' => 'Sale',
    'UTANG' => 'UTANG Sale',
    'PAYMENT' => 'UTANG Payment',
    'SALE_REVERSAL' || 'CASH_SALE_REVERSAL' => 'Sale Cancelled',
    'UTANG_REVERSAL' => 'UTANG Sale Cancelled',
    'PAYMENT_REVERSAL' => 'Payment Cancelled',
    'REVERSAL' => 'Stock Returned by Cancellation',
    'RETURN' || 'CONSIGNMENT_RETURN' => 'Returned to Supplier',
    _ => 'Stock Change',
  };
}
