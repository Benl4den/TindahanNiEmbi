import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/product.dart';
import '../../../models/category.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';
import 'product_card.dart';
import 'product_form_screen.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_search_field.dart';

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
  String archiveFilter = 'ACTIVE';
  int? categoryId;
  String? groupCode;
  List<Category> categories = const [];
  Map<int, List<String>> groups = const {};
  @override
  void initState() {
    super.initState();
    _reload();
    widget.categoryRepository.getActive().then((value) {
      if (mounted) setState(() => categories = value);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => _products = _loadProducts();
  Future<List<Product>> _loadProducts() async {
    final products = widget.repository is SqliteProductRepository
        ? await (widget.repository as SqliteProductRepository).searchAll(
            query: _search.text,
            archiveFilter: archiveFilter,
            categoryId: categoryId,
            groupCode: groupCode,
          )
        : await widget.repository.searchActive(_search.text);
    if (widget.repository is SqliteProductRepository) {
      groups = await (widget.repository as SqliteProductRepository)
          .inventoryGroups(products.map((x) => x.id));
    }
    return products;
  }

  Future<void> _form([Product? product]) async {
    final categories = await widget.categoryRepository.getActive();
    if (!mounted) return;
    if (categories.isEmpty) {
      _message(AppStrings.chooseCategory);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840, maxHeight: 920),
          child: ProductFormScreen(
            repository: widget.repository,
            photoService: widget.photoService,
            categories: categories,
            product: product,
          ),
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
        content: Text(
          '${product.name}\n\n${product.currentQuantity > 0 ? 'Warning: ${product.currentQuantity} units remain in stock.\n\n' : ''}${AppStrings.archiveProductMessage}',
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
            child: AppSearchField(
              controller: _search,
              hintText: AppStrings.searchProducts,
              onChanged: (_) => setState(_reload),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final x in const [
                  ('ALL', 'All'),
                  ('ACTIVE', 'Active'),
                  ('ARCHIVED', 'Archived'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(x.$2),
                      selected: archiveFilter == x.$1,
                      onSelected: (_) => setState(() {
                        archiveFilter = x.$1;
                        _reload();
                      }),
                    ),
                  ),
                for (final x in const [
                  ('SELECTA', 'Selecta'),
                  ('CONSIGNMENT', 'Consignment'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(x.$2),
                      selected: groupCode == x.$1,
                      onSelected: (_) => setState(() {
                        groupCode = groupCode == x.$1 ? null : x.$1;
                        _reload();
                      }),
                    ),
                  ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: categoryId == c.id,
                      onSelected: (_) => setState(() {
                        categoryId = categoryId == c.id ? null : c.id;
                        _reload();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _products,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AppLoadingView(label: 'Loading products…');
                }
                if (snapshot.hasError) {
                  return AppStateView.error(
                    title: 'Could not load products',
                    message: 'Your inventory records were not changed.',
                    actionLabel: 'Try Again',
                    onAction: () => setState(_reload),
                  );
                }
                final products = snapshot.data ?? const <Product>[];
                if (products.isEmpty) {
                  return AppStateView.empty(
                    title: AppStrings.noProducts,
                    message: 'Try another filter or add your first product.',
                    actionLabel: AppStrings.addProduct,
                    onAction: _form,
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
                    mainAxisExtent: 430,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, index) => ProductCard(
                    product: products[index],
                    categoryName: categories
                        .where((c) => c.id == products[index].categoryId)
                        .map((c) => c.name)
                        .firstOrNull,
                    inventoryGroups: groups[products[index].id] ?? const [],
                    onDetails: () => _details(products[index]),
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

  Future<void> _details(Product product) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(product.name),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selling Price: ₱${(product.sellingPriceCentavos / 100).toStringAsFixed(2)}',
            ),
            Text(
              'Purchase Cost: ₱${(product.purchasePriceCentavos / 100).toStringAsFixed(2)}',
            ),
            Text(
              'Estimated Unit Margin: ₱${((product.sellingPriceCentavos - product.purchasePriceCentavos) / 100).toStringAsFixed(2)}',
            ),
            Text('Current Stock: ${product.currentQuantity}'),
            Text('Minimum Stock: ${product.minimumStockLevel}'),
            Text('Status: ${product.stockStatus.name}'),
            const SizedBox(height: 12),
            const Text(
              'Stock quantity is maintained by inventory movements and cannot be edited here.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(dialog);
            WidgetsBinding.instance.addPostFrameCallback((_) => _form(product));
          },
          child: const Text('Edit'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
