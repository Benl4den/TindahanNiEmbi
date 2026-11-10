import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../models/category.dart';
import '../../../models/consignment.dart';
import '../../../models/payment_method.dart';
import '../../../models/product.dart';
import '../../../models/product_unit.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../../widgets/app_back_navigation.dart';
import '../../../widgets/product_image.dart';

class AddConsignorDialog extends StatefulWidget {
  const AddConsignorDialog({
    super.key,
    required this.repository,
    required this.categories,
  });
  final ConsignmentRepository repository;
  final List<Category> categories;
  @override
  State<AddConsignorDialog> createState() => _AddConsignorDialogState();
}

class _AddConsignorDialogState extends State<AddConsignorDialog> {
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
  Widget build(BuildContext context) => PageBackGuard(
    controllers: [name, contact],
    changeToken: categoryId,
    busy: saving,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: MediaQuery.sizeOf(context).width < 600
        ? const EdgeInsets.all(16)
        : null,
    contentPadding: MediaQuery.sizeOf(context).width < 600
        ? const EdgeInsets.fromLTRB(16, 12, 16, 16)
        : null,
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
            isExpanded: true,
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
        onPressed: saving ? null : () => Navigator.maybePop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
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

class EditConsignorDialog extends StatefulWidget {
  const EditConsignorDialog({
    super.key,
    required this.repository,
    required this.categories,
    required this.company,
  });
  final ConsignmentRepository repository;
  final List<Category> categories;
  final Map<String, Object?> company;
  @override
  State<EditConsignorDialog> createState() => _EditConsignorDialogState();
}

class _EditConsignorDialogState extends State<EditConsignorDialog> {
  late final TextEditingController name;
  late final TextEditingController contact;
  int? categoryId;
  bool archivedCategory = false;
  bool saving = false;
  String? error;
  bool submitted = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.company['name'] as String? ?? '');
    contact = TextEditingController(
      text: widget.company['contact_details'] as String? ?? '',
    );
    final previous = widget.company['default_category_id'] as int?;
    archivedCategory =
        previous != null && !widget.categories.any((c) => c.id == previous);
    categoryId = archivedCategory ? null : previous;
  }

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => submitted = true);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.updateConsignor(
        widget.company['id']! as int,
        name: name.text,
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
  Widget build(BuildContext context) => PageBackGuard(
    controllers: [name, contact],
    changeToken: categoryId,
    busy: saving,
    child: AlertDialog(
      scrollable: true,
      insetPadding: MediaQuery.sizeOf(context).width < 600
          ? const EdgeInsets.all(16)
          : null,
      contentPadding: MediaQuery.sizeOf(context).width < 600
          ? const EdgeInsets.fromLTRB(16, 12, 16, 16)
          : null,
      title: const Text('Edit Consignor'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Company / Name',
                border: const OutlineInputBorder(),
                errorText: submitted && name.text.trim().isEmpty
                    ? 'Company or consignor name is required.'
                    : null,
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
              isExpanded: true,
              initialValue: categoryId,
              decoration: const InputDecoration(
                labelText: 'Default product category (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('No default category'),
                ),
                ...widget.categories.map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => categoryId = value),
            ),
            if (archivedCategory) ...[
              const SizedBox(height: 8),
              const Text(
                'The previous default category is archived. Saving without a new selection clears that default.',
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.maybePop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}

class RemittanceDialog extends StatefulWidget {
  const RemittanceDialog({
    super.key,
    required this.repository,
    required this.parties,
    required this.balances,
  });
  final ConsignmentRepository repository;
  final List<Consignor> parties;
  final Map<int, int> balances;
  @override
  State<RemittanceDialog> createState() => _RemittanceDialogState();
}

class _RemittanceDialogState extends State<RemittanceDialog> {
  late int party;
  final amount = TextEditingController(),
      notes = TextEditingController(),
      gcashReference = TextEditingController();
  PaymentMethod paymentMethod = PaymentMethod.cash;
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
    gcashReference.dispose();
    super.dispose();
  }

  String money(int n) => standardMoney(n);
  Future<void> save() async {
    final cents = parseMoneyCentavos(amount.text);
    final balance = widget.balances[party] ?? 0;
    if (cents == null || cents <= 0) {
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
        paymentMethod: paymentMethod,
        gcashReference: gcashReference.text,
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
  Widget build(BuildContext context) => PageBackGuard(
    controllers: [amount, notes, gcashReference],
    changeToken: (party, paymentMethod),
    busy: saving,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final balance = widget.balances[party] ?? 0;
    return AlertDialog(
      title: const Text('Record Remittance'),
      content: SizedBox(
        width: 500,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom) *
                .55,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: party,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.parties
                      .where((p) => (widget.balances[p.id] ?? 0) > 0)
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
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
                  'Amount Owed to Supplier: ${money(balance)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                if (MediaQuery.sizeOf(context).width < 600)
                  DropdownButtonFormField<PaymentMethod>(
                    isExpanded: true,
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PaymentMethod.cash,
                        child: Text('Cash'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.gcash,
                        child: Text('GCash'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.maya,
                        child: Text('Maya'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => paymentMethod = value);
                            }
                          },
                  )
                else
                  SegmentedButton<PaymentMethod>(
                    segments: const [
                      ButtonSegment(
                        value: PaymentMethod.cash,
                        icon: Icon(Icons.payments_outlined),
                        label: Text('Cash'),
                      ),
                      ButtonSegment(
                        value: PaymentMethod.gcash,
                        icon: Icon(Icons.phone_android),
                        label: Text('GCash'),
                      ),
                      ButtonSegment(
                        value: PaymentMethod.maya,
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        label: Text('Maya'),
                      ),
                    ],
                    selected: {paymentMethod},
                    onSelectionChanged: saving
                        ? null
                        : (value) =>
                              setState(() => paymentMethod = value.single),
                  ),
                if (paymentMethod != PaymentMethod.cash) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: gcashReference,
                    decoration: InputDecoration(
                      labelText: paymentMethod == PaymentMethod.maya
                          ? 'Maya Reference (optional)'
                          : 'GCash Reference (optional)',
                      prefixIcon: Icon(Icons.tag),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  onChanged: (_) => setState(() => error = null),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Supplier Payment Amount',
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.maybePop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record Supplier Payment'),
        ),
      ],
    );
  }
}

class NewCompanyProductFlow extends StatefulWidget {
  const NewCompanyProductFlow({
    super.key,
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
  State<NewCompanyProductFlow> createState() => _NewCompanyProductFlowState();
}

class _NewCompanyProductFlowState extends State<NewCompanyProductFlow> {
  final name = TextEditingController(),
      count = TextEditingController(),
      cost = TextEditingController(),
      price = TextEditingController(),
      minimum = TextEditingController(text: '1');
  late int? categoryId;
  String photoPath = '';
  bool saving = false, choosingPhoto = false, changeCategory = false;
  bool submitted = false;
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
    final supplierCost = parseMoneyCentavos(cost.text);
    final sellingPrice = parseMoneyCentavos(price.text);
    final lowStock = int.tryParse(numericInput(minimum.text)) ?? -1;
    setState(() => submitted = true);
    if (productName.isEmpty || categoryId == null || photoPath.isEmpty) {
      return;
    }
    if (quantity <= 0 ||
        supplierCost == null ||
        sellingPrice == null ||
        sellingPrice <= 0 ||
        lowStock < 0) {
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
  Widget build(BuildContext context) => PageBackGuard(
    controllers: [name, count, cost, price, minimum],
    changeToken: (categoryId, photoPath),
    busy: saving || choosingPhoto,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final quantity = int.tryParse(numericInput(count.text)) ?? 0;
    final supplier = parseMoneyCentavos(cost.text) ?? 0;
    final selling = parseMoneyCentavos(price.text) ?? 0;
    final selectedCategory = widget.categories
        .where((category) => category.id == categoryId)
        .map((category) => category.name)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Consignment Product')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
        ),
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
                if (submitted && photoPath.isEmpty)
                  Text(
                    'Add a product photo.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    final camera = OutlinedButton.icon(
                      onPressed: choosingPhoto
                          ? null
                          : () => _choosePhoto(gallery: false),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take Photo'),
                    );
                    final gallery = OutlinedButton.icon(
                      onPressed: choosingPhoto
                          ? null
                          : () => _choosePhoto(gallery: true),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Upload Image'),
                    );
                    if (box.maxWidth < 400) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [camera, const SizedBox(height: 8), gallery],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: camera),
                        const SizedBox(width: 10),
                        Expanded(child: gallery),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Product Name',
                    border: const OutlineInputBorder(),
                    errorText: submitted && name.text.trim().isEmpty
                        ? 'Enter a product name.'
                        : null,
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
                    isExpanded: true,
                    initialValue: categoryId,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      errorText: submitted && categoryId == null
                          ? 'Choose a category.'
                          : null,
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
                  decoration: InputDecoration(
                    labelText: 'Quantity Received (pieces)',
                    border: const OutlineInputBorder(),
                    errorText:
                        submitted &&
                            (int.tryParse(numericInput(count.text)) ?? 0) <= 0
                        ? 'Enter a whole-number quantity greater than zero.'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Supplier Price per Piece',
                    prefixText: '₱ ',
                    border: const OutlineInputBorder(),
                    errorText:
                        submitted && parseMoneyCentavos(cost.text) == null
                        ? 'Enter a valid price (up to two decimals).'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Selling Price per Piece',
                    prefixText: '₱ ',
                    border: const OutlineInputBorder(),
                    errorText:
                        submitted &&
                            (parseMoneyCentavos(price.text) == null ||
                                parseMoneyCentavos(price.text)! <= 0)
                        ? 'Enter a selling price greater than ₱0.'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Low-Stock Level',
                    border: const OutlineInputBorder(),
                    errorText:
                        submitted &&
                            (int.tryParse(numericInput(minimum.text)) ?? -1) < 0
                        ? 'Enter a whole number of zero or more.'
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '$quantity pieces • Supplier total: ${standardMoney(quantity * supplier)} • Expected profit: ${standardMoney(quantity * (selling - supplier))}',
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
