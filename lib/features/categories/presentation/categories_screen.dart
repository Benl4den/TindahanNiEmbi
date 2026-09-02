import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/category.dart';
import '../../../repositories/category_repository.dart';
import 'category_form_screen.dart';
import '../../../widgets/app_state_view.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.repository});
  final CategoryRepository repository;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<Category>> _categories;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _categories = widget.repository.getActive();

  Future<void> _openForm([Category? category]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(
          repository: widget.repository,
          category: category,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _message(AppStrings.categorySaved);
    }
  }

  Future<void> _confirmArchive(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.archiveCategory),
        content: Text(
          '${category.name}\n\n${AppStrings.archiveCategoryMessage}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.confirmArchive),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.archive(category.id);
    if (!mounted) return;
    setState(_reload);
    _message(AppStrings.categoryArchived);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: AppStrings.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(AppStrings.categories),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Category>>(
          future: _categories,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoadingView(label: 'Loading categories…');
            }
            if (snapshot.hasError) {
              return AppStateView.error(
                title: 'Could not load categories',
                message: 'Your category records were not changed.',
                actionLabel: 'Try Again',
                onAction: () => setState(_reload),
              );
            }
            final categories = snapshot.data!;
            if (categories.isEmpty) {
              return AppStateView.empty(
                title: AppStrings.noCategories,
                message: 'Add a category to organize your products.',
                actionLabel: AppStrings.addCategory,
                onAction: _openForm,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final category = categories[index];
                return Card(
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final narrow = box.maxWidth < 560;
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.category_outlined, size: 42),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Text(
                                category.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (narrow)
                              PopupMenuButton<String>(
                                tooltip: 'Category actions',
                                onSelected: (value) => value == 'edit'
                                    ? _openForm(category)
                                    : _confirmArchive(category),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(AppStrings.edit),
                                  ),
                                  PopupMenuItem(
                                    value: 'archive',
                                    child: Text(AppStrings.archive),
                                  ),
                                ],
                              )
                            else ...[
                              OutlinedButton.icon(
                                onPressed: () => _openForm(category),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text(AppStrings.edit),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () => _confirmArchive(category),
                                icon: const Icon(Icons.archive_outlined),
                                label: const Text(AppStrings.archive),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add, size: 30),
        label: const Text(AppStrings.addCategory),
      ),
    );
  }
}
