import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/product.dart';
import '../../../models/category.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/product_photo_service.dart';
import 'product_card.dart';
import 'product_form_screen.dart';
import 'product_details_screen.dart';
import '../../../widgets/app_state_view.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

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
  String? ownership;
  ProductStockStatus? stockStatus;
  String sort = 'Name';
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

  void _searchNow(String query) {
    setState(() {});
  }

  void _clearSearch() {
    _search.clear();
    _searchNow('');
  }

  void _setArchiveFilter(String value) {
    if (archiveFilter == value) return;
    setState(() {
      archiveFilter = value;
      _reload();
    });
  }

  Future<void> _filterSort() async {
    var nextArchive = archiveFilter;
    var nextCategory = categoryId;
    var nextGroup = groupCode;
    var nextOwnership = ownership;
    var nextStatus = stockStatus;
    var nextSort = sort;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          icon: const Icon(Icons.tune),
          title: const Text('Filter & Sort'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: nextArchive,
                    decoration: const InputDecoration(
                      labelText: 'Product status',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'ARCHIVED',
                        child: Text('Archived'),
                      ),
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('Active & Archived'),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => nextArchive = v!),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: nextCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    hint: const Text('All categories'),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialog(() => nextCategory = v),
                  ),
                  TextButton(
                    onPressed: () => setDialog(() => nextCategory = null),
                    child: const Text('Clear category'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: nextGroup,
                    decoration: const InputDecoration(labelText: 'Group'),
                    hint: const Text('All groups'),
                    items: const [
                      DropdownMenuItem(value: 'SELECTA', child: Text('Brand')),
                      DropdownMenuItem(
                        value: 'CONSIGNMENT',
                        child: Text('Consignment'),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => nextGroup = v),
                  ),
                  TextButton(
                    onPressed: () => setDialog(() => nextGroup = null),
                    child: const Text('Clear group'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: nextOwnership,
                    decoration: const InputDecoration(labelText: 'Ownership'),
                    hint: const Text('All ownership'),
                    items: const [
                      DropdownMenuItem(value: 'OWNED', child: Text('Owned')),
                    ],
                    onChanged: (v) => setDialog(() => nextOwnership = v),
                  ),
                  TextButton(
                    onPressed: () => setDialog(() => nextOwnership = null),
                    child: const Text('Clear ownership'),
                  ),
                  DropdownButtonFormField<ProductStockStatus>(
                    initialValue: nextStatus,
                    decoration: const InputDecoration(
                      labelText: 'Stock status',
                    ),
                    hint: const Text('All stock statuses'),
                    items: const [
                      DropdownMenuItem(
                        value: ProductStockStatus.inStock,
                        child: Text('In Stock'),
                      ),
                      DropdownMenuItem(
                        value: ProductStockStatus.lowStock,
                        child: Text('Low Stock'),
                      ),
                      DropdownMenuItem(
                        value: ProductStockStatus.outOfStock,
                        child: Text('Out of Stock'),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => nextStatus = v),
                  ),
                  TextButton(
                    onPressed: () => setDialog(() => nextStatus = null),
                    child: const Text('Clear stock status'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: nextSort,
                    decoration: const InputDecoration(labelText: 'Sort by'),
                    items:
                        const [
                              'Name',
                              'Lowest Stock',
                              'Highest Stock',
                              'Recently Updated',
                            ]
                            .map(
                              (x) => DropdownMenuItem(value: x, child: Text(x)),
                            )
                            .toList(),
                    onChanged: (v) => setDialog(() => nextSort = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => setDialog(() {
                nextArchive = 'ACTIVE';
                nextCategory = null;
                nextGroup = null;
                nextOwnership = null;
                nextStatus = null;
                nextSort = 'Name';
              }),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      setState(() {
        archiveFilter = nextArchive;
        categoryId = nextCategory;
        groupCode = nextGroup;
        ownership = nextOwnership;
        stockStatus = nextStatus;
        sort = nextSort;
        _reload();
      });
    }
  }

  Future<List<Product>> _loadProducts() async {
    final products = widget.repository is SqliteProductRepository
        ? await (widget.repository as SqliteProductRepository).searchAll(
            query: '',
            archiveFilter: archiveFilter,
            categoryId: categoryId,
            groupCode: groupCode,
            ownership: ownership,
          )
        : await widget.repository.searchActive();
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
      barrierDismissible: false,
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
          '${product.name}\n\n${product.currentQuantity > 0 ? 'Warning: ${productQuantityText(product, product.currentQuantity)} remain in stock.\n\n' : ''}${AppStrings.archiveProductMessage}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
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

  Future<void> _restore(Product product) async {
    if (widget.repository is! SqliteProductRepository) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Product'),
        content: Text('Restore ${product.name} to your active products?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await (widget.repository as SqliteProductRepository).restore(product.id);
      if (mounted) {
        setState(_reload);
        _message('Product restored.');
      }
    } on InvalidProductException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Product could not be restored.');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppStrings.products),
      actions: const [HelpButton(topic: HelpTopicId.products)],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: AppStrings.searchProducts,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: _searchNow,
                  ),
                ),
                const SizedBox(width: 10),
                ToggleButtons(
                  isSelected: [
                    archiveFilter == 'ACTIVE',
                    archiveFilter == 'ARCHIVED',
                  ],
                  onPressed: (index) =>
                      _setArchiveFilter(index == 0 ? 'ACTIVE' : 'ARCHIVED'),
                  borderRadius: BorderRadius.circular(10),
                  constraints: const BoxConstraints(minHeight: 48),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Active'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Archived'),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _filterSort,
                  icon: const Icon(Icons.tune),
                  label: Text(
                    'Filter & Sort${_activeFilters == 0 ? '' : ' ($_activeFilters)'}',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              key: ValueKey('$archiveFilter|$categoryId|$groupCode'),
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
                final query = _search.text.trim().toLowerCase();
                final products = (snapshot.data ?? const <Product>[])
                    .where(
                      (product) =>
                          query.isEmpty ||
                          product.name.toLowerCase().contains(query),
                    )
                    .where(
                      (product) =>
                          stockStatus == null ||
                          product.stockStatus == stockStatus,
                    )
                    .toList();
                products.sort(
                  (a, b) => switch (sort) {
                    'Lowest Stock' => a.currentQuantity.compareTo(
                      b.currentQuantity,
                    ),
                    'Highest Stock' => b.currentQuantity.compareTo(
                      a.currentQuantity,
                    ),
                    'Recently Updated' => b.updatedAt.compareTo(a.updatedAt),
                    _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  },
                );
                if (products.isEmpty) {
                  return AppStateView.empty(
                    title: query.isEmpty
                        ? AppStrings.noProducts
                        : 'No matching products',
                    message: query.isEmpty
                        ? 'Try another filter or add your first product.'
                        : 'No product name contains “${_search.text.trim()}”.',
                    actionLabel: query.isEmpty
                        ? AppStrings.addProduct
                        : 'Clear Search',
                    onAction: query.isEmpty ? _form : _clearSearch,
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
                    onRestore: () => _restore(products[index]),
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

  int get _activeFilters =>
      [
        categoryId,
        groupCode,
        ownership,
        stockStatus,
      ].where((x) => x != null).length +
      (archiveFilter == 'ACTIVE' ? 0 : 1);

  Future<void> _details(Product product) async {
    if (widget.repository is! SqliteProductRepository) return;
    final edit = await showDialog<bool>(
      context: context,
      builder: (dialog) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
          child: ProductDetailsScreen(
            product: product,
            repository: widget.repository as SqliteProductRepository,
            onEdit: () => Navigator.of(dialog).pop(true),
          ),
        ),
      ),
    );
    if (edit == true && mounted) await _form(product);
    if (mounted) setState(_reload);
  }
}
