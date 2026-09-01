import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/product.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';
import 'product_card.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    required this.repository,
    required this.categoryRepository,
    required this.photoService,
  });
  final ProductRepository repository;
  final CategoryRepository categoryRepository;
  final ProductPhotoService photoService;
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _products;
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => _products = widget.repository.searchActive(_search.text);

  Future<void> _form([Product? product]) async {
    final categories = await widget.categoryRepository.getActive();
    if (!mounted) return;
    if (categories.isEmpty) {
      _message(AppStrings.chooseCategory);
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          repository: widget.repository,
          photoService: widget.photoService,
          categories: categories,
          product: product,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _message(AppStrings.productSaved);
    }
  }

  Future<void> _archive(Product product) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.archiveProduct),
        content: Text('${product.name}\n\n${AppStrings.archiveProductMessage}'),
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
    if (yes != true) return;
    await widget.repository.archive(product.id);
    if (mounted) {
      setState(_reload);
      _message(AppStrings.productArchived);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.products)),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: AppStrings.searchProducts,
                prefixIcon: Icon(Icons.search, size: 30),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(20),
              ),
              onChanged: (_) => setState(_reload),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _products,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final products = snapshot.data ?? const <Product>[];
                if (products.isEmpty) {
                  return Center(
                    child: Text(
                      AppStrings.noProducts,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  );
                }
                final width = MediaQuery.sizeOf(context).width;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: width >= 1000
                        ? 4
                        : width >= 650
                        ? 3
                        : 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: .68,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, index) => ProductCard(
                    product: products[index],
                    onEdit: () => _form(products[index]),
                    onArchive: () => _archive(products[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _form,
      icon: const Icon(Icons.add, size: 30),
      label: const Text(AppStrings.addProduct),
    ),
  );
}
