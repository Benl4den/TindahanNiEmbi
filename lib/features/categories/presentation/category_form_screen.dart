import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/category.dart';
import '../../../repositories/category_repository.dart';

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({
    super.key,
    required this.repository,
    this.category,
  });

  final CategoryRepository repository;
  final Category? category;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final category = widget.category;
      if (category == null) {
        await widget.repository.create(_nameController.text);
      } else {
        await widget.repository.update(
          id: category.id,
          name: _nameController.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on DuplicateCategoryNameException {
      if (mounted) _showMessage(AppStrings.duplicateCategory);
    } on InvalidCategoryNameException {
      if (mounted) _showMessage(AppStrings.requiredCategoryName);
    } catch (_) {
      if (mounted) _showMessage(AppStrings.couldNotSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.category != null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: AppStrings.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(editing ? AppStrings.editCategory : AppStrings.addCategory),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 22),
                      decoration: const InputDecoration(
                        labelText: AppStrings.categoryName,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(20),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? AppStrings.requiredCategoryName
                          : null,
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(Icons.save_outlined, size: 28),
                      label: const Text(AppStrings.save),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(68),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 28),
                      label: const Text(AppStrings.back),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(68),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
