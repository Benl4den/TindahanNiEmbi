import 'package:flutter/material.dart';

import '../../../models/product_unit.dart';

class UnitsPackagingEditor extends StatefulWidget {
  const UnitsPackagingEditor({
    super.key,
    required this.categoryName,
    required this.defaultSellingPriceCentavos,
    required this.onChanged,
    this.initial,
  });
  final String categoryName;
  final int defaultSellingPriceCentavos;
  final ProductUnitConfiguration? initial;
  final ValueChanged<ProductUnitConfiguration> onChanged;

  @override
  State<UnitsPackagingEditor> createState() => _UnitsPackagingEditorState();
}

class _UnitsPackagingEditorState extends State<UnitsPackagingEditor> {
  late ProductUnitConfiguration value;

  @override
  void initState() {
    super.initState();
    value =
        widget.initial ??
        ProductUnitPreset.forCategory(
          widget.categoryName,
          widget.defaultSellingPriceCentavos,
        );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onChanged(value),
    );
  }

  @override
  void didUpdateWidget(covariant UnitsPackagingEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryName != widget.categoryName &&
        widget.categoryName.isNotEmpty) {
      value = ProductUnitPreset.forCategory(
        widget.categoryName,
        widget.defaultSellingPriceCentavos,
      );
      widget.onChanged(value);
    }
  }

  void update(ProductUnitConfiguration next) {
    setState(() => value = next);
    widget.onChanged(next);
  }

  int? positive(String? text) {
    final number = int.tryParse(text?.trim() ?? '');
    return number != null && number > 0 ? null : 0;
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Units & Packaging',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set how you buy, store, and sell this product. Quantities are always kept in the base unit.',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<BaseUnit>(
            initialValue: value.baseUnit,
            decoration: const InputDecoration(
              labelText: 'Base inventory unit',
              border: OutlineInputBorder(),
            ),
            items: BaseUnit.values
                .map((x) => DropdownMenuItem(value: x, child: Text(x.label)))
                .toList(),
            onChanged: (unit) {
              if (unit != null) {
                update(
                  ProductUnitConfiguration(
                    baseUnit: unit,
                    purchasePackages: value.purchasePackages,
                    sellingOptions: value.sellingOptions,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 20),
          Text(
            'How do you buy this product?',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < value.purchasePackages.length; i++)
            _purchaseRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                update(
                  ProductUnitConfiguration(
                    baseUnit: value.baseUnit,
                    purchasePackages: [
                      ...value.purchasePackages,
                      const PurchasePackageDraft(
                        name: 'Custom package',
                        baseQuantity: 1,
                      ),
                    ],
                    sellingOptions: value.sellingOptions,
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add purchase package'),
            ),
          ),
          const Divider(height: 30),
          Text(
            'How do you sell this product?',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < value.sellingOptions.length; i++) _sellingRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                update(
                  ProductUnitConfiguration(
                    baseUnit: value.baseUnit,
                    purchasePackages: value.purchasePackages,
                    sellingOptions: [
                      ...value.sellingOptions,
                      SellingOptionDraft(
                        name: 'Custom size',
                        baseQuantity: 1,
                        priceCentavos: widget.defaultSellingPriceCentavos,
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add selling option'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _purchaseRow(int index) {
    final item = value.purchasePackages[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              key: ValueKey('purchase-name-$index-${item.name}'),
              initialValue: item.name,
              decoration: InputDecoration(
                labelText: index == 0
                    ? 'Default purchase package'
                    : 'Package name',
              ),
              validator: _label,
              onChanged: (text) => _replacePurchase(index, name: text),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: ValueKey('purchase-qty-$index-${item.baseQuantity}'),
              initialValue: '${item.baseQuantity}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${value.baseUnit.label}s per package',
              ),
              validator: _positiveMessage,
              onChanged: (text) =>
                  _replacePurchase(index, quantity: int.tryParse(text)),
            ),
          ),
          if (index > 0)
            IconButton(
              tooltip: 'Remove package',
              onPressed: () {
                final list = [...value.purchasePackages]..removeAt(index);
                update(
                  ProductUnitConfiguration(
                    baseUnit: value.baseUnit,
                    purchasePackages: list,
                    sellingOptions: value.sellingOptions,
                  ),
                );
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  Widget _sellingRow(int index) {
    final item = value.sellingOptions[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              key: ValueKey('sale-name-$index-${item.name}'),
              initialValue: item.name,
              decoration: InputDecoration(
                labelText: index == 0
                    ? 'Default selling option'
                    : 'Option name',
              ),
              validator: _label,
              onChanged: (text) => _replaceSale(index, name: text),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: ValueKey('sale-qty-$index-${item.baseQuantity}'),
              initialValue: '${item.baseQuantity}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${value.baseUnit.label}s used',
              ),
              validator: _positiveMessage,
              onChanged: (text) =>
                  _replaceSale(index, quantity: int.tryParse(text)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: ValueKey('sale-price-$index-${item.priceCentavos}'),
              initialValue: (item.priceCentavos / 100).toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Selling price',
                prefixText: '₱ ',
              ),
              validator: _moneyMessage,
              onChanged: (text) => _replaceSale(index, price: _centavos(text)),
            ),
          ),
          if (index > 0)
            IconButton(
              tooltip: 'Remove selling option',
              onPressed: () {
                final list = [...value.sellingOptions]..removeAt(index);
                update(
                  ProductUnitConfiguration(
                    baseUnit: value.baseUnit,
                    purchasePackages: value.purchasePackages,
                    sellingOptions: list,
                  ),
                );
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  String? _label(String? x) =>
      x == null || x.trim().isEmpty ? 'Enter a name.' : null;
  String? _positiveMessage(String? x) =>
      positive(x) == null ? null : 'Quantity must be greater than 0.';
  String? _moneyMessage(String? x) =>
      _centavos(x ?? '') == null ? 'Enter a valid non-negative price.' : null;
  int? _centavos(String x) {
    final n = double.tryParse(x.trim());
    return n == null || n < 0 ? null : (n * 100).round();
  }

  void _replacePurchase(int i, {String? name, int? quantity}) {
    final old = value.purchasePackages[i], list = [...value.purchasePackages];
    list[i] = PurchasePackageDraft(
      name: name ?? old.name,
      baseQuantity: quantity ?? old.baseQuantity,
      isDefault: i == 0,
    );
    value = ProductUnitConfiguration(
      baseUnit: value.baseUnit,
      purchasePackages: list,
      sellingOptions: value.sellingOptions,
    );
    widget.onChanged(value);
  }

  void _replaceSale(int i, {String? name, int? quantity, int? price}) {
    final old = value.sellingOptions[i], list = [...value.sellingOptions];
    list[i] = SellingOptionDraft(
      name: name ?? old.name,
      baseQuantity: quantity ?? old.baseQuantity,
      priceCentavos: price ?? old.priceCentavos,
      isDefault: i == 0,
    );
    value = ProductUnitConfiguration(
      baseUnit: value.baseUnit,
      purchasePackages: value.purchasePackages,
      sellingOptions: list,
    );
    widget.onChanged(value);
  }
}
