import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';

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
  });
  final ProductRepository repository;
  final ProductPhotoService photoService;
  final List<Category> categories;
  final Product? product;
  final ValueChanged<Product>? onSaved;
  final bool allowStartingStock;
  final ValueChanged<ProductDraft>? onDraft;

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
    _categoryId = product?.categoryId;
    _photoPath = product?.photoPath;
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
    try {
      final result = await widget.photoService.capture();
      if (result != null && mounted) setState(() => _photoPath = result);
    } on PhotoCaptureException catch (error) {
      if (!mounted) return;
      _message(
        error.failure == PhotoCaptureFailure.permissionDenied
            ? AppStrings.cameraDenied
            : AppStrings.cameraUnavailable,
      );
    }
  }

  int? _money(String value) {
    final parsed = double.tryParse(value.trim());
    return parsed == null ? null : (parsed * 100).round();
  }

  int? _whole(String value) => int.tryParse(value.trim());

  Future<void> _save() async {
    if (_photoPath == null) return _message(AppStrings.photoRequired);
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
        );
        if (widget.onDraft != null) {
          widget.onDraft!(draft);
          if (mounted) Navigator.pop(context, true);
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
          ),
        );
        widget.onSaved?.call(saved);
      }
      if (mounted) Navigator.pop(context, true);
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
                    onPressed: _capture,
                    icon: const Icon(Icons.camera_alt_outlined, size: 30),
                    label: Text(
                      _photoPath == null
                          ? AppStrings.takePhoto
                          : AppStrings.retakePhoto,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(68),
                    ),
                  ),
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
                            onChanged: (value) =>
                                setState(() => _categoryId = value),
                            validator: (value) => value == null
                                ? AppStrings.chooseCategory
                                : null,
                          ),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (widget.product == null &&
                                  widget.allowStartingStock) ...[
                                Expanded(
                                  child: _field(
                                    _starting,
                                    AppStrings.startingStock,
                                  ),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
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
    validator: validator ?? (value) => _number(value, money: money),
  );
}
