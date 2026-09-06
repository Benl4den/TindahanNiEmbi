import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';

import '../../../models/consignment.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/product_unit.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../../widgets/product_image.dart';
import '../../../widgets/summary_card.dart';

class ConsignmentScreen extends StatefulWidget {
  const ConsignmentScreen({
    super.key,
    required this.repository,
    required this.products,
    required this.categories,
    required this.photoService,
    this.initialConsignorId,
    this.initialReceiveProductId,
  });
  final ConsignmentRepository repository;
  final ProductRepository products;
  final CategoryRepository categories;
  final ProductPhotoService photoService;
  final int? initialConsignorId;
  final int? initialReceiveProductId;
  @override
  State<ConsignmentScreen> createState() => _ConsignmentScreenState();
}

class _AddConsignorDialog extends StatefulWidget {
  const _AddConsignorDialog({
    required this.repository,
    required this.categories,
  });
  final ConsignmentRepository repository;
  final List<Category> categories;
  @override
  State<_AddConsignorDialog> createState() => _AddConsignorDialogState();
}

class _AddConsignorDialogState extends State<_AddConsignorDialog> {
  final name = TextEditingController(), contact = TextEditingController();
  int? categoryId;
  String? error;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Company or consignor name is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.createConsignor(
        name.text,
        contactDetails: contact.text,
        defaultCategoryId: categoryId,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is InvalidConsignmentOperation
              ? e.message
              : 'Could not save the consignor. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Consignor'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Company / Name',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contact,
            decoration: const InputDecoration(
              labelText: 'Contact details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: categoryId,
            decoration: const InputDecoration(
              labelText: 'Default product category (optional)',
              border: OutlineInputBorder(),
            ),
            items: widget.categories
                .map((x) => DropdownMenuItem(value: x.id, child: Text(x.name)))
                .toList(),
            onChanged: (value) => setState(() => categoryId = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: name.text.trim().isEmpty || saving ? null : save,
        child: saving
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

class _RemittanceDialog extends StatefulWidget {
  const _RemittanceDialog({
    required this.repository,
    required this.parties,
    required this.balances,
  });
  final ConsignmentRepository repository;
  final List<Consignor> parties;
  final Map<int, int> balances;
  @override
  State<_RemittanceDialog> createState() => _RemittanceDialogState();
}

class _RemittanceDialogState extends State<_RemittanceDialog> {
  late int party;
  final amount = TextEditingController(), notes = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    party = widget.parties
        .firstWhere((p) => (widget.balances[p.id] ?? 0) > 0)
        .id;
  }

  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  String money(int n) => '₱${(n / 100).toStringAsFixed(2)}';
  Future<void> save() async {
    final cents = ((double.tryParse(amount.text.trim()) ?? 0) * 100).round(),
        balance = widget.balances[party] ?? 0;
    if (cents <= 0) {
      setState(() => error = 'Enter a remittance amount greater than zero.');
      return;
    }
    if (cents > balance) {
      setState(() => error = 'Amount cannot exceed ${money(balance)}.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.remit(
        consignorId: party,
        amountCentavos: cents,
        notes: notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is InvalidConsignmentOperation
              ? e.message
              : 'Could not record the remittance. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.balances[party] ?? 0;
    return AlertDialog(
      title: const Text('Record Remittance'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: party,
              decoration: const InputDecoration(
                labelText: 'Consignor',
                border: OutlineInputBorder(),
              ),
              items: widget.parties
                  .where((p) => (widget.balances[p.id] ?? 0) > 0)
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (v) => setState(() {
                      party = v!;
                      error = null;
                    }),
            ),
            const SizedBox(height: 14),
            Text(
              'Outstanding Payable: ${money(balance)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Remittance Amount',
                prefixText: '₱ ',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record Remittance'),
        ),
      ],
    );
  }
}

class _NewCompanyProductFlow extends StatefulWidget {
  const _NewCompanyProductFlow({
    required this.repository,
    required this.products,
    required this.categories,
    required this.photoService,
    required this.consignor,
    this.initialCategoryId,
  });
  final ConsignmentRepository repository;
  final ProductRepository products;
  final List<Category> categories;
  final ProductPhotoService photoService;
  final Consignor consignor;
  final int? initialCategoryId;

  @override
  State<_NewCompanyProductFlow> createState() => _NewCompanyProductFlowState();
}

class _NewCompanyProductFlowState extends State<_NewCompanyProductFlow> {
  final name = TextEditingController(),
      count = TextEditingController(),
      cost = TextEditingController(),
      price = TextEditingController(),
      minimum = TextEditingController(text: '1');
  late int? categoryId;
  String photoPath = '';
  bool saving = false, choosingPhoto = false, changeCategory = false;
  String? error;

  @override
  void initState() {
    super.initState();
    categoryId =
        widget.initialCategoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
  }

  @override
  void dispose() {
    name.dispose();
    count.dispose();
    cost.dispose();
    price.dispose();
    minimum.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto({required bool gallery}) async {
    setState(() => choosingPhoto = true);
    try {
      final selected =
          gallery && widget.photoService is ProductGalleryPhotoService
          ? await (widget.photoService as ProductGalleryPhotoService)
                .chooseFromGallery()
          : await widget.photoService.capture();
      if (mounted && selected != null) setState(() => photoPath = selected);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not add the photo. Please try again.');
      }
    } finally {
      if (mounted) setState(() => choosingPhoto = false);
    }
  }

  Future<void> _save() async {
    final productName = name.text.trim();
    final quantity = int.tryParse(numericInput(count.text)) ?? 0;
    final supplierCost =
        ((double.tryParse(numericInput(cost.text)) ?? -1) * 100).round();
    final sellingPrice =
        ((double.tryParse(numericInput(price.text)) ?? -1) * 100).round();
    final lowStock = int.tryParse(numericInput(minimum.text)) ?? -1;
    if (productName.isEmpty || categoryId == null || photoPath.isEmpty) {
      setState(() => error = 'Add the product name, category, and photo.');
      return;
    }
    if (quantity <= 0 ||
        supplierCost < 0 ||
        sellingPrice <= 0 ||
        lowStock < 0) {
      setState(
        () => error = 'Enter a valid quantity, supplier cost, selling price, and low-stock level.',
      );
      return;
    }
    final duplicate = (await widget.products.searchActive(productName)).any(
      (product) =>
          product.name.trim().toLowerCase() == productName.toLowerCase(),
    );
    if (duplicate) {
      if (mounted) {
        setState(
          () => error = 'A product with this name already exists. Use Select Existing Product instead.',
        );
      }
      return;
    }
    final units = ProductUnitConfiguration(
      baseUnit: BaseUnit.piece,
      purchasePackages: const [
        PurchasePackageDraft(name: 'Piece', baseQuantity: 1, isDefault: true),
      ],
      sellingOptions: [
        SellingOptionDraft(
          name: 'Piece',
          baseQuantity: 1,
          priceCentavos: sellingPrice,
          isDefault: true,
        ),
      ],
    );
    final value = ProductDraft(
      categoryId: categoryId!,
      name: productName,
      photoPath: photoPath,
      purchasePriceCentavos: supplierCost,
      sellingPriceCentavos: sellingPrice,
      startingQuantity: 0,
      minimumStockLevel: lowStock,
      unitConfiguration: units,
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.receiveNewProduct(
        product: value,
        consignorId: widget.consignor.id,
        boxes: quantity,
        unitsPerBox: 1,
        unitCostCentavos: supplierCost,
        supplierCostBasisQuantity: 1,
        packageName: 'Direct piece',
        baseUnitLabel: 'piece',
        priceUnitName: 'Piece',
        sellingPriceCentavos: sellingPrice,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is InvalidConsignmentOperation
              ? e.message
              : 'Could not save the product and delivery.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(numericInput(count.text)) ?? 0;
    final supplier = double.tryParse(numericInput(cost.text)) ?? 0;
    final selling = double.tryParse(numericInput(price.text)) ?? 0;
    final selectedCategory = widget.categories
        .where((category) => category.id == categoryId)
        .map((category) => category.name)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Consignment Product')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.consignor.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Count the delivered pieces. The product and first delivery save together.',
                ),
                const SizedBox(height: 20),
                SizedBox(height: 150, child: ProductImage(path: photoPath)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: choosingPhoto
                            ? null
                            : () => _choosePhoto(gallery: false),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Take Photo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: choosingPhoto
                            ? null
                            : () => _choosePhoto(gallery: true),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Upload Image'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Product Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                if (!changeCategory && selectedCategory != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Category'),
                    subtitle: Text(selectedCategory),
                    trailing: TextButton(
                      onPressed: () => setState(() => changeCategory = true),
                      child: const Text('Change'),
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => categoryId = value),
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantity Received (pieces)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Supplier Price per Piece',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Selling Price per Piece',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Low-Stock Level',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '$quantity pieces • Supplier total: ₱${(quantity * supplier).toStringAsFixed(2)} • Expected profit: ₱${(quantity * (selling - supplier)).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving…' : 'Add & Receive Product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsignmentScreenState extends State<ConsignmentScreen> {
  int? selectedConsignorId;
  int? _pendingReceiveProductId;
  int _companyTab = 0;
  late Future<
    ({
      ConsignmentSummary? summary,
      List<Map<String, Object?>> cards,
      List<Map<String, Object?>> companies,
    })
  >
  _data;

  @override
  void initState() {
    super.initState();
    selectedConsignorId = widget.initialConsignorId;
    _pendingReceiveProductId = widget.initialReceiveProductId;
    _reload();
    _scheduleInitialReceive();
  }

  @override
  void didUpdateWidget(covariant ConsignmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialConsignorId != oldWidget.initialConsignorId ||
        widget.initialReceiveProductId != oldWidget.initialReceiveProductId) {
      selectedConsignorId = widget.initialConsignorId ?? selectedConsignorId;
      _pendingReceiveProductId = widget.initialReceiveProductId;
      _reload();
      _scheduleInitialReceive();
    }
  }

  void _scheduleInitialReceive() {
    if (_pendingReceiveProductId == null || selectedConsignorId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _pendingReceiveProductId == null) return;
      final productId = _pendingReceiveProductId;
      _pendingReceiveProductId = null;
      await _receive(initialProductId: productId);
    });
  }

  void _reload() {
    _data = _load();
  }

  Future<
    ({
      ConsignmentSummary? summary,
      List<Map<String, Object?>> cards,
      List<Map<String, Object?>> companies,
    })
  >
  _load() async {
    final companies = await widget.repository.companyCards();
    final id = selectedConsignorId;
    if (id == null) {
      return (
        summary: null,
        cards: <Map<String, Object?>>[],
        companies: companies,
      );
    }
    return (
      summary: await widget.repository.summaryForConsignor(id),
      cards: await widget.repository.productCardsForConsignor(id),
      companies: companies,
    );
  }

  String money(int value) => '₱${(value / 100).toStringAsFixed(2)}';
  Future<void> _addConsignor() async {
    final categories = await widget.categories.getActive();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddConsignorDialog(
        repository: widget.repository,
        categories: categories,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _receive({
    bool addProduct = false,
    int? initialProductId,
  }) async {
    final companyId = selectedConsignorId;
    if (companyId == null) return;
    final parties = (await widget.repository.consignors())
        .where((p) => p.id == companyId)
        .toList();
    var products = await widget.products.searchActive();
    if (!addProduct) {
      final companyProducts = await widget.repository.productCardsForConsignor(
        companyId,
      );
      final ids = companyProducts.map((p) => p['product_id']).toSet();
      products = products.where((p) => ids.contains(p.id)).toList();
    }
    if (!mounted) return;
    if (parties.isEmpty) {
      _message('Add a consignor before receiving consignment.');
      return;
    }
    if (!addProduct && products.isEmpty) {
      _message(
        'Add a product inside this company before receiving another delivery.',
      );
      return;
    }
    final createNew = !addProduct
        ? false
        : await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Add Product to Company'),
              content: const Text(
                'Choose how to identify the delivered product.',
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Select Existing Product'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Create New Product'),
                ),
              ],
            ),
          );
    if (createNew == null) return;
    if (!createNew && products.isEmpty) {
      _message('No products are available. Choose Create New Product.');
      return;
    }
    if (createNew) {
      final categories = await widget.categories.getActive();
      if (!mounted) return;
      final completed = await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 900),
            child: _NewCompanyProductFlow(
              repository: widget.repository,
              products: widget.products,
              photoService: widget.photoService,
              categories: categories,
              consignor: parties.single,
              initialCategoryId: parties.single.defaultCategoryId,
            ),
          ),
        ),
      );
      if (completed == true && mounted) setState(_reload);
      return;
    }
    if (!mounted) return;
    final party = parties.single.id;
    var product =
        initialProductId != null &&
            products.any((p) => p.id == initialProductId)
        ? initialProductId
        : products.first.id;
    final configurations = <int, ProductUnitConfiguration>{};
    try {
      for (final item in products) {
        configurations[item.id] = await widget.repository.deliveryConfiguration(
          item.id,
        );
      }
    } catch (e) {
      if (mounted) _message(_friendly(e));
      return;
    }
    if (!mounted) return;
    ProductUnitConfiguration configuration() => configurations[product]!;
    SellingOptionDraft sellingOption() =>
        configuration().sellingOptions.singleWhere((o) => o.isDefault);
    String unitLabel() => configuration().baseUnit.label;
    String quantityLabel(int amount) => switch (configuration().baseUnit) {
      BaseUnit.gram => '${standardNumber(amount / 1000)} kg',
      BaseUnit.milliliter => '${standardNumber(amount / 1000)} L',
      _ => '${standardNumber(amount)} ${unitLabel()}${amount == 1 ? '' : 's'}',
    };
    final boxes = TextEditingController(),
        units = TextEditingController(),
        cost = TextEditingController(),
        sell = TextEditingController(),
        notes = TextEditingController();
    units.text = '1';
    sell.text = (sellingOption().priceCentavos / 100).toStringAsFixed(2);
    String? error;
    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Receive Consignment'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      parties.single.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!createNew)
                    DropdownButtonFormField<int>(
                      initialValue: product,
                      decoration: const InputDecoration(
                        labelText: 'Existing Product',
                      ),
                      items: products
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() {
                        product = v!;
                        units.text = '1';
                        sell.text = (sellingOption().priceCentavos / 100)
                            .toStringAsFixed(2);
                        cost.clear();
                        boxes.clear();
                      }),
                    ),
                  const SizedBox(height: 12),
                  ...[
                    (boxes, 'Quantity received (${unitLabel()})'),
                    (cost, 'Supplier cost per ${sellingOption().name}'),
                    (sell, 'Selling price per ${sellingOption().name}'),
                    (notes, 'Notes (optional)'),
                  ].map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: f.$1,
                        readOnly: f.$1 == units,
                        onChanged: (_) => set(() {}),
                        keyboardType: f.$1 == notes
                            ? TextInputType.text
                            : TextInputType.number,
                        decoration: InputDecoration(
                          labelText: f.$2,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final boxCount =
                          int.tryParse(numericInput(boxes.text)) ?? 0;
                      final perBox = int.tryParse(units.text) ?? 0;
                      final unitCost = double.tryParse(cost.text) ?? 0;
                      final total = boxCount * perBox;
                      final costBasis = sellingOption().baseQuantity;
                      final totalCost =
                          (total * (unitCost * 100)).round() / costBasis / 100;
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${quantityLabel(total)} received\nSupplier cost: ₱${unitCost.toStringAsFixed(2)} per ${sellingOption().name}\nTotal Consigned Value: ₱${totalCost.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      );
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Selling price updates the current Sales price. Previous transactions keep their original prices.',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final receipt = ConsignmentReceiptDraft(
                        consignorId: party,
                        productId: product,
                        boxes: int.tryParse(numericInput(boxes.text)) ?? 0,
                        unitsPerBox: int.tryParse(units.text) ?? 0,
                        unitCostCentavos:
                            ((double.tryParse(cost.text) ?? -1) * 100).round(),
                        sellingPriceCentavos:
                            ((double.tryParse(sell.text) ?? -1) * 100).round(),
                        supplierCostBasisQuantity: sellingOption().baseQuantity,
                        packageName: 'Direct ${unitLabel()}',
                        baseUnitLabel: unitLabel(),
                        priceUnitName: sellingOption().name,
                        notes: notes.text,
                      );
                      if (receipt.boxes <= 0 ||
                          receipt.unitsPerBox <= 0 ||
                          receipt.unitCostCentavos < 0 ||
                          receipt.sellingPriceCentavos <= 0) {
                        set(
                          () => error = 'Enter valid quantities, cost, and a selling price greater than zero.',
                        );
                        return;
                      }
                      set(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await widget.repository.receive(receipt);
                        if (x.mounted) Navigator.pop(x, true);
                      } catch (e) {
                        if (x.mounted) {
                          set(() {
                            saving = false;
                            error = _friendly(e);
                          });
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Receive'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(_reload);
  }

  String _friendly(Object error) => error is InvalidConsignmentOperation
      ? error.message
      : 'Could not save. Please check the details and try again.';
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _remit() async {
    final companyId = selectedConsignorId;
    if (companyId == null) return;
    final parties = (await widget.repository.consignors())
        .where((p) => p.id == companyId)
        .toList();
    if (!mounted) return;
    if (parties.isEmpty) {
      _message('Add a consignor before recording a remittance.');
      return;
    }
    final balances = await widget.repository.payableByConsignor();
    if (!mounted) return;
    if ((balances[companyId] ?? 0) <= 0) {
      _message('There is no outstanding supplier payable to remit.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RemittanceDialog(
        repository: widget.repository,
        parties: parties,
        balances: balances,
      ),
    );
    if (ok == true && mounted) setState(_reload);
  }

  Future<void> _details(Map<String, Object?> product) async {
    final rows = await widget.repository.productHistory(
      product['product_id']! as int,
      consignorId: selectedConsignorId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  product['name']! as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                subtitle: Text(
                  '${product['consignor_name']} • Read-only history',
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final x = rows[i];
                    final payable = x['payable_centavos']! as int;
                    return ListTile(
                      title: Text(
                        '${x['event_type']} • ${x['quantity']} units',
                      ),
                      subtitle: Text(
                        '${DateTime.parse(x['occurred_at']! as String).toLocal()}\nCost ${money(x['unit_cost_centavos']! as int)} • Selling ${money(x['selling_price_centavos']! as int)}',
                      ),
                      trailing: payable == 0
                          ? null
                          : Text(
                              'Payable ${money(payable)}\nMargin ${money(x['margin_centavos']! as int)}',
                              textAlign: TextAlign.end,
                            ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _returnStock(product);
                        },
                        icon: const Icon(Icons.undo),
                        label: const Text('Return Unsold Stock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _archiveConsignor(String name) async {
    final id = selectedConsignorId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Archive Consignor?'),
        content: Text(
          '$name will no longer appear in normal Consignment selections. All receipts, products, remittances, payable entries, and historical records will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Archive Consignor'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.archiveConsignor(id);
      if (!mounted) return;
      setState(() {
        selectedConsignorId = null;
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Consignor archived. Historical records were preserved.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The consignor could not be archived. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editConsignor(Map<String, Object?> company) async {
    final categories = await widget.categories.getActive();
    if (!mounted) return;
    final name = TextEditingController(text: company['name']! as String);
    final contact = TextEditingController(
      text: company['contact_details'] as String? ?? '',
    );
    var categoryId = company['default_category_id'] as int?;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Edit Consignor'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Company / Name',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact details (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Default product category (optional)',
                  ),
                  items: categories
                      .map(
                        (x) =>
                            DropdownMenuItem(value: x.id, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (value) => categoryId = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.repository.updateConsignor(
                    company['id']! as int,
                    name: name.text,
                    contactDetails: contact.text,
                    defaultCategoryId: categoryId,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } on InvalidConsignmentOperation catch (e) {
                  setDialog(() => error = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    contact.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _returnStock(Map<String, Object?> product) async {
    final batches = await widget.repository.returnableBatches(
      product['product_id']! as int,
      consignorId: selectedConsignorId,
    );
    if (!mounted || batches.isEmpty) return;
    var batchId = batches.first['id']! as int;
    final quantity = TextEditingController(), notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Return Unsold Stock'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: batchId,
                  decoration: const InputDecoration(labelText: 'Receipt batch'),
                  items: batches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b['id']! as int,
                          child: Text(
                            '${b['consignor_name']} • ${b['available']} available',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => set(() => batchId = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Units to return',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Confirm Return'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.repository.returnUnits(
        batchId: batchId,
        quantity: int.tryParse(quantity.text) ?? 0,
        notes: notes.text,
      );
      if (mounted) setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: selectedConsignorId == null
          ? null
          : IconButton(
              tooltip: 'Company List',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                selectedConsignorId = null;
                _reload();
              }),
            ),
      title: const Text('Consignment'),
    ),
    body: FutureBuilder(
      future: _data,
      builder: (_, s) {
        if (s.hasError) {
          return Center(child: Text('Could not load Consignment: ${s.error}'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final summary = s.data!.summary,
            cards = s.data!.cards,
            companies = s.data!.companies;
        if (selectedConsignorId == null) {
          return ListView(
            key: const Key('consignor-company-list'),
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addConsignor,
                    icon: const Icon(Icons.business),
                    label: const Text('Add Consignor'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Companies / Consignors',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (companies.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text('No consignors yet. Add a consignor to begin.'),
                  ),
                ),
              ...companies.map(
                (x) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(18),
                    leading: const CircleAvatar(child: Icon(Icons.business)),
                    title: Text(
                      x['name']! as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Text(
                      '${x['product_count']} products • ${money(x['payable_centavos']! as int)} payable'
                      '${x['default_category_name'] == null ? '' : ' • ${x['default_category_name']}'}\n'
                      'Last receipt: ${_shortDate(x['last_receipt_at'])} • Last remittance: ${_shortDate(x['last_remittance_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() {
                      selectedConsignorId = x['id']! as int;
                      _companyTab = 0;
                      _reload();
                    }),
                  ),
                ),
              ),
            ],
          );
        }
        if (summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final company = companies.firstWhere(
          (x) => x['id'] == selectedConsignorId,
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              company['name']! as String,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (company['contact_details'] != null)
              Text(company['contact_details']! as String),
            if (company['default_category_name'] != null)
              Text('Default category: ${company['default_category_name']}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    selectedConsignorId = null;
                    _reload();
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Company List'),
                ),
                FilledButton.icon(
                  onPressed: () => _receive(addProduct: true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _receive(),
                  icon: const Icon(Icons.add_box),
                  label: const Text('Receive Delivery'),
                ),
                OutlinedButton.icon(
                  onPressed: _remit,
                  icon: const Icon(Icons.payments),
                  label: const Text('Record Remittance'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editConsignor(company),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Consignor'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: () =>
                      _archiveConsignor(company['name']! as String),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive Consignor'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SummaryCard(
                  label: 'Outstanding Supplier Payable',
                  value: money(summary.payableCentavos),
                ),
                SummaryCard(
                  label: 'Products with Remaining Stock',
                  value:
                      '${cards.where((p) => (p['remaining']! as int) > 0).length}',
                ),
                SummaryCard(
                  label: 'Consigned Inventory Value',
                  value: money(summary.inventoryValueCentavos),
                ),
                SummaryCard(
                  label: 'Store Margin Earned',
                  value: money(summary.marginCentavos),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Products')),
                ButtonSegment(value: 1, label: Text('Deliveries')),
                ButtonSegment(value: 2, label: Text('Payable')),
                ButtonSegment(value: 3, label: Text('Returns')),
                ButtonSegment(value: 4, label: Text('Archived')),
              ],
              selected: {_companyTab},
              onSelectionChanged: (value) =>
                  setState(() => _companyTab = value.single),
            ),
            const SizedBox(height: 12),
            if (_companyTab == 0 && cards.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('No consignment receipts yet.')),
              ),
            if (_companyTab == 0)
              ...cards.map(
                (x) => Card(
                  child: InkWell(
                    onTap: () => _details(x),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            x['name']! as String,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${x['consignor_name']}\nReceived: ${_quantity(x['received']! as int, x['base_unit_label'] as String?)}   Remaining: ${_quantity(x['remaining']! as int, x['base_unit_label'] as String?)}   Sold: ${_quantity(x['sold']! as int, x['base_unit_label'] as String?)}\nSelling: ${money(x['selling_price_centavos']! as int)}   Amount to Remit: ${money(x['payable_centavos']! as int)}',
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => _receive(
                                initialProductId: x['product_id']! as int,
                              ),
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Receive Again'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_companyTab == 1) _deliveriesTab(selectedConsignorId!),
            if (_companyTab == 2)
              _payableTab(selectedConsignorId!, summary.payableCentavos),
            if (_companyTab == 3) _returnsTab(cards),
            if (_companyTab == 4) _archivedProductsTab(selectedConsignorId!),
          ],
        );
      },
    ),
  );

  Widget _deliveriesTab(
    int consignorId,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: widget.repository.deliveriesForConsignor(consignorId),
    builder: (_, snapshot) {
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final rows = snapshot.data!;
      if (rows.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No deliveries yet.')),
        );
      }
      return Column(
        children: rows.map((row) {
          final package = row['package_name'] as String? ?? 'Package';
          final count = row['package_count'] ?? 1;
          final total = row['units_received']! as int;
          final unit = row['base_unit_label'] as String? ?? 'units';
          final direct = package.toLowerCase().startsWith('direct ');
          final totalLabel = _quantity(total, unit);
          return Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(row['name']! as String),
              subtitle: Text(
                '${direct ? 'Direct count: $totalLabel' : '$count × $package = $totalLabel'}\n${_shortDate(row['received_at'])}',
              ),
              isThreeLine: true,
              trailing: Text(
                'Cost ${money(row['supplier_cost_centavos']! as int)}\nper ${row['price_unit_name'] ?? unit}',
                textAlign: TextAlign.end,
              ),
            ),
          );
        }).toList(),
      );
    },
  );

  Widget _payableTab(
    int consignorId,
    int payable,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: widget.repository.remittancesForConsignor(consignorId),
    builder: (_, snapshot) {
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final rows = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Outstanding Supplier Payable'),
              trailing: Text(
                money(payable),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Remittance History',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No remittances recorded.'),
            ),
          ...rows.map(
            (row) => ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(money(row['amount_centavos']! as int)),
              subtitle: Text(
                '${_shortDate(row['remitted_at'])}${(row['notes'] as String?)?.trim().isNotEmpty == true ? ' • ${row['notes']}' : ''}',
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _returnsTab(List<Map<String, Object?>> cards) {
    final returnable = cards
        .where((x) => (x['remaining']! as int) > 0)
        .toList();
    if (returnable.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No stock is available to return.')),
      );
    }
    return Column(
      children: returnable
          .map(
            (x) => Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: Text(x['name']! as String),
                subtitle: Text(
                  '${_quantity(x['remaining']! as int, x['base_unit_label'] as String?)} available to return',
                ),
                trailing: OutlinedButton(
                  onPressed: () => _details(x),
                  child: const Text('View / Return'),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _archivedProductsTab(
    int consignorId,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: widget.repository.archivedProductCardsForConsignor(consignorId),
    builder: (_, snapshot) {
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final rows = snapshot.data!;
      if (rows.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No archived consignment products.')),
        );
      }
      return Column(
        children: rows
            .map(
              (x) => Card(
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(x['name']! as String),
                  subtitle: Text(
                    'Archived product\nReceived: ${_quantity(x['received']! as int, x['base_unit_label'] as String?)}   Remaining: ${_quantity(x['remaining']! as int, x['base_unit_label'] as String?)}   Sold: ${_quantity(x['sold']! as int, x['base_unit_label'] as String?)}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: () => _details(x),
                    child: const Text('View / Return'),
                  ),
                  onTap: () => _details(x),
                  isThreeLine: true,
                ),
              ),
            )
            .toList(),
      );
    },
  );

  String _shortDate(Object? value) => value == null
      ? 'None'
      : MaterialLocalizations.of(context)
            .formatShortDate(DateTime.parse(value as String).toLocal());

  String _quantity(int amount, String? unit) {
    if (unit == 'g') return '${standardNumber(amount / 1000)} kg';
    if (unit == 'mL') return '${standardNumber(amount / 1000)} L';
    final label = unit ?? 'unit';
    return '${standardNumber(amount)} $label${amount == 1 ? '' : 's'}';
  }
}
