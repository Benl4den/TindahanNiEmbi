import 'package:flutter/material.dart';

import '../../../models/product_unit.dart';
import 'units_packaging_editor.dart';

class SmartPackagingEditor extends StatefulWidget {
  const SmartPackagingEditor({
    super.key,
    required this.categoryName,
    required this.purchasePriceCentavos,
    required this.sellingPriceCentavos,
    required this.onChanged,
    required this.onPricesChanged,
    this.initial,
    this.startingPackageCount,
  });

  final String categoryName;
  final int purchasePriceCentavos;
  final int sellingPriceCentavos;
  final ProductUnitConfiguration? initial;
  final TextEditingController? startingPackageCount;
  final ValueChanged<ProductUnitConfiguration> onChanged;
  final void Function(int purchase, int selling) onPricesChanged;

  @override
  State<SmartPackagingEditor> createState() => _SmartPackagingEditorState();
}

class _SmartPackagingEditorState extends State<SmartPackagingEditor> {
  late final String kind;
  late final TextEditingController size, purchase, largePrice, smallPrice;
  TextEditingController? secondSmallPrice;
  bool changing = false;

  @override
  void initState() {
    super.initState();
    kind = _kind(widget.categoryName);
    final preset =
        widget.initial ??
        ProductUnitPreset.forCategory(
          widget.categoryName,
          widget.sellingPriceCentavos,
        );
    final package = preset.purchasePackages.first;
    final small = preset.sellingOptions.first;
    final large = preset.sellingOptions.length > 1
        ? preset.sellingOptions.last
        : null;
    size = TextEditingController(text: _displaySize(package.baseQuantity));
    purchase = TextEditingController(
      text: _money(widget.purchasePriceCentavos),
    );
    smallPrice = TextEditingController(text: _money(small.priceCentavos));
    largePrice = TextEditingController(
      text: _money(
        large?.priceCentavos ??
            _suggestLarge(small.priceCentavos, package.baseQuantity),
      ),
    );
    if (kind == 'oil') {
      final half = preset.sellingOptions
          .where((x) => x.baseQuantity == 125)
          .firstOrNull;
      final lapad = preset.sellingOptions
          .where((x) => x.baseQuantity == 250)
          .firstOrNull;
      smallPrice.text = _money(lapad?.priceCentavos ?? 0);
      secondSmallPrice = TextEditingController(
        text: _money(half?.priceCentavos ?? 0),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    size.dispose();
    purchase.dispose();
    largePrice.dispose();
    smallPrice.dispose();
    secondSmallPrice?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kind == 'other') {
      return UnitsPackagingEditor(
        categoryName: widget.categoryName,
        defaultSellingPriceCentavos: widget.sellingPriceCentavos,
        initial: widget.initial,
        onChanged: widget.onChanged,
      );
    }
    final labels = switch (kind) {
      'rice' => (
        'Weight per Sack',
        'kg',
        'Purchase Price per Sack',
        'Selling Price per Sack',
        'Selling Price per kg',
      ),
      'oil' => (
        'Volume per Gallon',
        'L',
        'Purchase Price per Gallon',
        'Selling Price per Gallon',
        'Selling Price per Lapad',
      ),
      'drinks' => (
        'Bottles per Case',
        'bottles',
        'Purchase Price per Case',
        'Selling Price per Case',
        'Selling Price per Bottle',
      ),
      _ => (
        'Sticks per Pack',
        'sticks',
        'Purchase Price per Pack',
        'Selling Price per Pack',
        'Selling Price per Stick',
      ),
    };
    final startingLabel = switch (kind) {
      'rice' => 'Number of Sacks Purchased',
      'oil' => 'Number of Gallons Purchased',
      'drinks' => 'Number of Cases Purchased',
      _ => 'Number of Packs Purchased',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stock, Package & Pricing',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter familiar store quantities. Internal unit conversions are handled automatically.',
            ),
            const SizedBox(height: 18),
            if (widget.startingPackageCount != null) ...[
              _field(
                widget.startingPackageCount!,
                startingLabel,
                money: false,
                onChanged: (_) {},
              ),
              const SizedBox(height: 14),
            ],
            _field(
              size,
              labels.$1,
              suffix: labels.$2,
              money: false,
              onChanged: (_) => _sizeChanged(),
            ),
            const SizedBox(height: 14),
            _field(purchase, labels.$3, onChanged: (_) => _emit()),
            const SizedBox(height: 14),
            _field(largePrice, labels.$4, onChanged: (_) => _largeChanged()),
            const SizedBox(height: 14),
            _field(smallPrice, labels.$5, onChanged: (_) => _smallChanged()),
            if (kind == 'oil') ...[
              const SizedBox(height: 14),
              _field(
                secondSmallPrice!,
                'Selling Price per Half Lapad',
                onChanged: (_) => _emit(),
              ),
              const SizedBox(height: 6),
              const Text(
                'Lapad prices are suggestions. You may set practical retail prices.',
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced Units & Packaging'),
              subtitle: const Text('For unusual or additional package sizes'),
              children: [
                UnitsPackagingEditor(
                  categoryName: widget.categoryName,
                  defaultSellingPriceCentavos: _cents(smallPrice.text) ?? 0,
                  initial: _configuration(),
                  onChanged: widget.onChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? suffix,
    bool money = true,
    required ValueChanged<String> onChanged,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: money ? '₱ ' : null,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    ),
    validator: (text) {
      if (controller == widget.startingPackageCount) {
        final count = int.tryParse(text?.trim() ?? '');
        return count == null || count < 0
            ? 'Enter a valid whole number.'
            : null;
      }
      final n = double.tryParse(text?.trim() ?? '');
      return n == null || !n.isFinite || (money ? n < 0 : n <= 0)
          ? money
                ? 'Enter a valid non-negative price.'
                : 'Enter a number greater than 0.'
          : null;
    },
    onChanged: onChanged,
  );

  void _largeChanged() {
    if (changing) return;
    final large = _cents(largePrice.text), base = _baseQuantity();
    if (large != null && base > 0) {
      changing = true;
      if (kind == 'rice') {
        smallPrice.text = _money((large * 1000 / base).round());
      }
      if (kind == 'oil') {
        smallPrice.text = _money((large * 250 / base).round());
        secondSmallPrice!.text = _money((large * 125 / base).round());
      }
      if (kind == 'drinks' || kind == 'cigarettes') {
        smallPrice.text = _money((large / base).round());
      }
      changing = false;
    }
    _emit();
  }

  void _smallChanged() {
    if (!changing && kind == 'rice') {
      final small = _cents(smallPrice.text), base = _baseQuantity();
      if (small != null && base > 0) {
        changing = true;
        largePrice.text = _money((small * base / 1000).round());
        changing = false;
      }
    }
    _emit();
  }

  void _sizeChanged() {
    _largeChanged();
  }

  void _emit() {
    final config = _configuration();
    widget.onChanged(config);
    widget.onPricesChanged(
      _cents(purchase.text) ?? 0,
      _cents(smallPrice.text) ?? 0,
    );
  }

  ProductUnitConfiguration _configuration() {
    final base = _baseQuantity().clamp(1, 1 << 31);
    final large = _cents(largePrice.text) ?? 0;
    final small = _cents(smallPrice.text) ?? 0;
    if (kind == 'rice') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.gram,
        purchasePackages: [
          PurchasePackageDraft(
            name: '${_clean(size.text)} kg Sack',
            baseQuantity: base,
            isDefault: true,
          ),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: '1 kg',
            baseQuantity: 1000,
            priceCentavos: small,
            isDefault: true,
          ),
          SellingOptionDraft(
            name: '${_clean(size.text)} kg Sack',
            baseQuantity: base,
            priceCentavos: large,
          ),
        ],
      );
    }
    if (kind == 'oil') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.milliliter,
        purchasePackages: [
          PurchasePackageDraft(
            name: 'Gallon',
            baseQuantity: base,
            isDefault: true,
          ),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: 'Lapad',
            baseQuantity: 250,
            priceCentavos: small,
            isDefault: true,
          ),
          SellingOptionDraft(
            name: 'Half Lapad',
            baseQuantity: 125,
            priceCentavos: _cents(secondSmallPrice!.text) ?? 0,
          ),
          SellingOptionDraft(
            name: 'Gallon',
            baseQuantity: base,
            priceCentavos: large,
          ),
        ],
      );
    }
    final isDrink = kind == 'drinks';
    return ProductUnitConfiguration(
      baseUnit: isDrink ? BaseUnit.bottle : BaseUnit.stick,
      purchasePackages: [
        PurchasePackageDraft(
          name: isDrink ? 'Case' : 'Pack',
          baseQuantity: base,
          isDefault: true,
        ),
      ],
      sellingOptions: [
        SellingOptionDraft(
          name: isDrink ? 'Bottle' : 'Stick',
          baseQuantity: 1,
          priceCentavos: small,
          isDefault: true,
        ),
        SellingOptionDraft(
          name: isDrink ? 'Case' : 'Pack',
          baseQuantity: base,
          priceCentavos: large,
        ),
      ],
    );
  }

  int _baseQuantity() {
    final n = double.tryParse(size.text.trim()) ?? 0;
    return kind == 'rice' || kind == 'oil' ? (n * 1000).round() : n.round();
  }

  String _displaySize(int base) =>
      kind == 'rice' || kind == 'oil' ? _clean('${base / 1000}') : '$base';
  int _suggestLarge(int small, int base) =>
      kind == 'rice' ? (small * base / 1000).round() : small * base;
  int? _cents(String text) {
    final n = double.tryParse(text.trim());
    return n == null || !n.isFinite || n < 0 ? null : (n * 100).round();
  }

  String _money(int cents) => (cents / 100).toStringAsFixed(2);
  String _clean(String text) => text.replaceFirst(RegExp(r'\.0+$'), '');
  String _kind(String name) {
    final n = name.trim().toLowerCase().replaceAll(RegExp(r'[- ]+'), ' ');
    if (n == 'rice') return 'rice';
    if (n == 'cooking oil') return 'oil';
    if (n == 'soft drinks' || n == 'softdrinks') return 'drinks';
    if (n == 'cigarettes' || n == 'cigarettes & tobacco') return 'cigarettes';
    return 'other';
  }
}
