import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/product_unit.dart';
import '../../../repositories/product_unit_repository.dart';

Future<bool> showPackageStockInDialog({
  required BuildContext context,
  required Product product,
  required ProductUnitRepository repository,
  int suggestedBaseQuantity = 0,
}) async {
  final packages = await repository.purchasePackages(product.id);
  if (!context.mounted) return false;
  if (packages.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No purchase package is configured.')),
    );
    return false;
  }
  var selected =
      packages.where((x) => x.isDefault).firstOrNull ?? packages.first;
  final suggested = suggestedBaseQuantity <= 0
      ? 1
      : (suggestedBaseQuantity / selected.baseQuantity).ceil().clamp(
          1,
          1 << 31,
        );
  final count = TextEditingController(text: '$suggested');
  final cost = TextEditingController();
  final notes = TextEditingController();
  String? error;
  var submitting = false;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (_, set) {
        final packagesCount = int.tryParse(numericInput(count.text)) ?? 0;
        final total = packagesCount * selected.baseQuantity;
        return AlertDialog(
          title: Text('Stock In — ${product.name}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PurchasePackage>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'Purchase package',
                      border: OutlineInputBorder(),
                    ),
                    items: packages
                        .map(
                          (x) =>
                              DropdownMenuItem(value: x, child: Text(x.name)),
                        )
                        .toList(),
                    onChanged: submitting
                        ? null
                        : (x) {
                            if (x != null) set(() => selected = x);
                          },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: count,
                    enabled: !submitting,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Number of ${selected.name} packages',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => set(() => error = null),
                    onTap: () => count.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: count.text.length,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: cost,
                    enabled: !submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Purchase cost per package (optional)',
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notes,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      packagesCount > 0
                          ? '$packagesCount × ${selected.name} = ${_friendly(total, product)} added'
                          : 'Enter how many packages were received.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final packageCount = int.tryParse(
                        numericInput(count.text),
                      );
                      final costText = cost.text.trim();
                      final pesos = costText.isEmpty
                          ? null
                          : double.tryParse(numericInput(costText));
                      if (packageCount == null ||
                          packageCount <= 0 ||
                          (costText.isNotEmpty &&
                              (pesos == null ||
                                  !pesos.isFinite ||
                                  pesos < 0))) {
                        set(
                          () => error = 'Enter a valid package count and cost.',
                        );
                        return;
                      }
                      set(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await repository.receive(
                          productId: product.id,
                          packageId: selected.id,
                          packageCount: packageCount,
                          packageCostCentavos: pesos == null
                              ? null
                              : (pesos * 100).round(),
                          notes: notes.text,
                        );
                        if (dialog.mounted) {
                          Navigator.pop(dialog, true);
                        }
                      } on InvalidProductUnit catch (e) {
                        if (dialog.mounted) {
                          set(() {
                            error = e.message;
                            submitting = false;
                          });
                        }
                      } catch (_) {
                        if (dialog.mounted) {
                          set(() {
                            error = 'Could not record Stock In.';
                            submitting = false;
                          });
                        }
                      }
                    },
              child: const Text('Stock In'),
            ),
          ],
        );
      },
    ),
  );
  return saved == true;
}

String _friendly(int quantity, Product product) {
  return productQuantityText(product, quantity);
}
