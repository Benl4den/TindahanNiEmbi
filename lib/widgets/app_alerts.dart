import 'package:flutter/material.dart';

String transactionFailureMessage(Object error) {
  final raw = error.toString().replaceFirst(
    RegExp(r'^[A-Za-z]+Exception:\s*'),
    '',
  );
  if (raw.contains('Not enough') || raw.contains('INSUFFICIENT_STOCK')) {
    return 'There is not enough stock for the selected quantity. $raw';
  }
  if (raw.contains('selling option')) return raw;
  if (raw.contains('STALE_PRODUCT_QUANTITY')) {
    return 'Inventory changed while the sale was being saved. Refresh and try once more.';
  }
  return 'The transaction could not be saved. Your cart is safe. Details: $raw';
}

Future<void> showFriendlyError(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    icon: Icon(Icons.error_outline, color: Theme.of(dialog).colorScheme.error),
    title: Text(title),
    content: Text(message),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('OK'),
      ),
    ],
  ),
);

Future<void> showStockAlert(
  BuildContext context,
  String productName,
  int available,
) => showFriendlyError(
  context,
  title: available <= 0 ? 'Out of Stock' : 'Not Enough Stock',
  message: available <= 0
      ? '$productName is currently out of stock. Restock it before adding it to a sale.'
      : 'Only $available units of $productName are available.',
);
