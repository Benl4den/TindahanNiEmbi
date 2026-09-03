import 'package:flutter/material.dart';

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
