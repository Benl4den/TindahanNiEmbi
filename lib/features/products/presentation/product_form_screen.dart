import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/product_unit.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';
import 'smart_packaging_editor.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.repository,
    required this.photoService,
    required this.categories,
    this.product,
    this.onSaved,
    this.allowStartingStock = true,
    this.onDraft,
    this.closeAfterDraft = true,
    this.initialCategoryId,
    this.categoryInitiallyLocked = false,
  });
  final ProductRepository repository;
  final ProductPhotoService photoService;
  final List<Category> categories;
  final Product? product;
  final ValueChanged<Product>? onSaved;
  final bool allowStartingStock;
  final ValueChanged<ProductDraft>? onDraft;
  final bool closeAfterDraft;
  final int? initialCategoryId;
  final bool categoryInitiallyLocked;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;
  late final TextEditingController _starting;
  late final TextEditingController _minimum;
  int? _categoryId;
  String? _photoPath;
  bool _saving = false;
  ProductUnitConfiguration? _units;
  late bool _unitsLoading;
  late bool _categoryLocked;
  bool _processingPhoto = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _purchase = TextEditingController(
      text: product == null
          ? ''
          : (product.purchasePriceCentavos / 100).toStringAsFixed(2),
    );
    _selling = TextEditingController(
      text: product == null
          ? ''
          : (product.sellingPriceCentavos / 100).toStringAsFixed(2),
    );
    _starting = TextEditingController(text: '0');
    _minimum = TextEditingController(
      text: product?.minimumStockLevel.toString() ?? '0',
    );
    _categoryId = product?.categoryId ?? widget.initialCategoryId;
    _categoryLocked =
        product == null &&
        widget.categoryInitiallyLocked &&
        _categoryId != null;
    _photoPath = product?.photoPath;
    _unitsLoading =
        product != null && widget.repository is SqliteProductRepository;
    if (product != null && widget.repository is SqliteProductRepository) {
      (widget.repository as SqliteProductRepository)
          .unitConfiguration(product.id)
          .then((value) {
            if (mounted) {
              setState(() {
                _units = value;
                _unitsLoading = false;
              });
            }
          })
          .catchError((Object _) {
            if (mounted) setState(() => _unitsLoading = false);
          });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _purchase,
      _selling,
      _starting,
      _minimum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _capture() async {
    await _selectPhoto(widget.photoService.capture);
  }

  Future<void> _gallery() async {
    final service = widget.photoService;
    if (service is ProductGalleryPhotoService) {
      await _selectPhoto(
        (service as ProductGalleryPhotoService).chooseFromGallery,
      );
    }
  }

  Future<void> _selectPhoto(Future<String?> Function() picker) async {
    if (_processingPhoto) return;
    setState(() => _processingPhoto = true);
    try {
      final result = await picker();
      if (result != null && mounted) setState(() => _photoPath = result);
    } on PhotoCaptureException catch (error) {
      if (!mounted) return;
      _message(
        error.failure == PhotoCaptureFailure.permissionDenied
            ? AppStrings.cameraDenied
            : AppStrings.cameraUnavailable,
      );
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  int? _money(String value) {
    final parsed = double.tryParse(numericInput(value));
    return parsed == null ? null : (parsed * 100).round();
  }

  int? _whole(String value) => int.tryParse(numericInput(value));

  Future<void> _save() async {
    if (_photoPath == null) return _message(AppStrings.photoRequired);
    if (_unitsLoading || _units == null) {
      return _message(
        'Units and packaging are still loading. Please try again.',
      );
    }
    if (!_formKey.currentState!.validate() || _categoryId == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.product;
      if (existing == null) {
        final draft = ProductDraft(
          categoryId: _categoryId!,
          name: _name.text,
          photoPath: _photoPath!,
          purchasePriceCentavos: _money(_purchase.text)!,
          sellingPriceCentavos: _money(_selling.text)!,
          startingQuantity: widget.allowStartingStock
              ? _whole(_starting.text)!
              : 0,
          minimumStockLevel: _whole(_minimum.text)!,
          unitConfiguration: _units,
        );
        if (widget.onDraft != null) {
          widget.onDraft!(draft);
          if (mounted && widget.closeAfterDraft) Navigator.pop(context, true);
          return;
        }
        final saved = await widget.repository.create(draft);
        widget.onSaved?.call(saved);
      } else {
        final saved = await widget.repository.update(
          Product(
            id: existing.id,
            categoryId: _categoryId!,
            name: _name.text,
            photoPath: _photoPath!,
            purchasePriceCentavos: _money(_purchase.text)!,
            sellingPriceCentavos: _money(_selling.text)!,
            currentQuantity: existing.currentQuantity,
            minimumStockLevel: _whole(_minimum.text)!,
            isArchived: existing.isArchived,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            baseUnitCode: existing.baseUnitCode,
            baseUnitLabel: existing.baseUnitLabel,
            unitConfiguration: _units,
          ),
        );
        widget.onSaved?.call(saved);
      }
      if (mounted) Navigator.pop(context, true);
    } on InvalidProductException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message(AppStrings.couldNotSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppStrings.requiredCategoryName
      : null;
  String? _number(String? value, {bool money = false}) {
    final parsed = money ? _money(value ?? '') : _whole(value ?? '');
    return parsed == null || parsed < 0 ? AppStrings.invalidNumber : null;
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final creatingWithoutPhoto = widget.product == null && _photoPath == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product == null ? AppStrings.addProduct : AppStrings.edit,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_photoPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(
                        File(_photoPath!),
                        height: 280,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _processingPhoto ? null : _capture,
                    icon: const Icon(Icons.camera_alt_outlined, size: 30),
                    label: Text(
                      _processingPhoto
                          ? 'Processing photo…'
                          : _photoPath == null
                          ? AppStrings.takePhoto
                          : AppStrings.retakePhoto,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(68),
                    ),
                  ),
                  if (widget.photoService is ProductGalleryPhotoService) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _processingPhoto ? null : _gallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from Gallery'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                      ),
                    ),
                  ],
                  if (!creatingWithoutPhoto) ...[
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _field(
                            _name,
                            AppStrings.productName,
                            validator: _required,
                          ),
                          const SizedBox(height: 16),
                          if (_categoryLocked)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(color: Colors.black26),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              title: const Text('Category'),
                              subtitle: Text(
                                widget.categories
                                        .where((x) => x.id == _categoryId)
                                        .map((x) => x.name)
                                        .firstOrNull ??
                                    '',
                              ),
                              trailing: TextButton(
                                onPressed: () =>
                                    setState(() => _categoryLocked = false),
                                child: const Text('Change Category'),
                              ),
                            )
                          else
                            DropdownButtonFormField<int>(
                              initialValue: _categoryId,
                              decoration: const InputDecoration(
                                labelText: AppStrings.category,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(20),
                              ),
                              style: const TextStyle(
                                fontSize: 20,
                                color: Colors.black,
                              ),
                              items: widget.categories
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                _categoryId = value;
                                _units = null;
                              }),
                              validator: (value) => value == null
                                  ? AppStrings.chooseCategory
                                  : null,
                            ),
                          const SizedBox(height: 16),
                          if (!_usesSmartPackaging)
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    _purchase,
                                    AppStrings.purchasePrice,
                                    money: true,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _field(
                                    _selling,
                                    AppStrings.sellingPrice,
                                    money: true,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 22),
                          if (_unitsLoading)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            SmartPackagingEditor(
                              key: ValueKey(
                                'units-${_categoryId ?? 0}-${_units == null ? 'preset' : 'loaded'}',
                              ),
                              categoryName:
                                  widget.categories
                                      .where((x) => x.id == _categoryId)
                                      .map((x) => x.name)
                                      .firstOrNull ??
                                  '',
                              sellingPriceCentavos: _money(_selling.text) ?? 0,
                              purchasePriceCentavos:
                                  _money(_purchase.text) ?? 0,
                              initial: _units,
                              startingPackageCount:
                                  widget.product == null &&
                                      widget.allowStartingStock &&
                                      _usesSmartPackaging
                                  ? _starting
                                  : null,
                              onChanged: (value) => _units = value,
                              onPricesChanged: (purchase, selling) {
                                _purchase.text = (purchase / 100)
                                    .toStringAsFixed(2);
                                _selling.text = (selling / 100).toStringAsFixed(
                                  2,
                                );
                              },
                            ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (widget.product == null &&
                                  widget.allowStartingStock &&
                                  !_usesSmartPackaging) ...[
                                Expanded(
                                  child: _field(_starting, _startingStockLabel),
                                ),
                                const SizedBox(width: 16),
                              ],
                              Expanded(
                                child: _field(
                                  _minimum,
                                  AppStrings.minimumStock,
                                ),
                              ),
                            ],
                          ),
                          if (widget.product != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Current inventory: ${_friendlyStock(widget.product!)}. '
                              'Changing package size does not change stock already received. '
                              'Use Inventory Adjustment to correct it.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving || _unitsLoading ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(68),
                      ),
                      child: const Text(AppStrings.save),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(68),
                    ),
                    child: const Text(AppStrings.back),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool money = false,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    style: const TextStyle(fontSize: 20),
    keyboardType: money
        ? const TextInputType.numberWithOptions(decimal: true)
        : (controller == _name ? TextInputType.text : TextInputType.number),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.all(20),
      prefixText: money ? '₱ ' : null,
    ),
    onTap: controller == _name
        ? null
        : () {
            if (controller.text == '0' || controller.text == '0.00') {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
    validator: validator ?? (value) => _number(value, money: money),
  );

  String get _startingStockLabel {
    final packages = _units?.purchasePackages ?? const [];
    final defaultPackage = packages.where((x) => x.isDefault).firstOrNull;
    return defaultPackage == null
        ? AppStrings.startingStock
        : 'Starting number of ${defaultPackage.name} packages';
  }

  bool get _usesSmartPackaging {
    final name = widget.categories
        .where((x) => x.id == _categoryId)
        .map(
          (x) => x.name.trim().toLowerCase().replaceAll(RegExp(r'[- ]+'), ' '),
        )
        .firstOrNull;
    return const {
      'rice',
      'cooking oil',
      'soft drinks',
      'softdrinks',
      'cigarettes',
      'cigarettes & tobacco',
    }.contains(name);
  }

  String _friendlyStock(Product product) {
    if (product.baseUnitCode == 'GRAM' && product.currentQuantity >= 1000) {
      return '${_trimDecimal(product.currentQuantity / 1000)} kg';
    }
    if (product.baseUnitCode == 'MILLILITER' &&
        product.currentQuantity >= 1000) {
      return '${_trimDecimal(product.currentQuantity / 1000)} L';
    }
    return '${product.currentQuantity} ${product.baseUnitLabel}';
  }

  String _trimDecimal(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}
