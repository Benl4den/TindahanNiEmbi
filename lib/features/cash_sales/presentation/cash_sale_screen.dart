import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/utang_draft.dart';
import '../../../models/product_unit.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/product_unit_repository.dart';
import '../../../repositories/sale_draft_repository.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_alerts.dart';
import '../../../widgets/product_image.dart';
import '../../transactions/product_selection_controller.dart';
import 'sale_details_screen.dart';

class CashSaleScreen extends StatefulWidget {
  const CashSaleScreen({
    super.key,
    required this.products,
    this.repository,
    this.saveSale,
    this.loadProducts,
    this.embedded = false,
    this.onUtang,
    this.categoryNames = const {},
    this.frequentProductNames = const {},
    this.frequentProductIds = const [],
    this.selectaProductIds = const {},
    this.reversals,
    this.drafts,
  }) : assert(repository != null || saveSale != null);
  final List<Product> products;
  final CashSaleRepository? repository;
  final Future<int> Function(List<UtangItemDraft>)? saveSale;
  final Future<List<Product>> Function()? loadProducts;
  final bool embedded;
  final Future<bool> Function(List<UtangItemDraft>)? onUtang;
  final Map<int, String> categoryNames;
  final Set<String> frequentProductNames;
  final List<int> frequentProductIds;
  final Set<int> selectaProductIds;
  final ReversalRepository? reversals;
  final SaleDraftRepository? drafts;
  @override
  State<CashSaleScreen> createState() => _State();
}

class _State extends State<CashSaleScreen> {
  late ProductSelectionController c;
  late List<Product> products;
  String search = '';
  String filter = 'FREQUENT';
  bool saving = false;
  SalesHistoryEntry? lastTransaction;
  int todaySalesTotal = 0;
  int todayTransactionCount = 0;
  Map<int, List<SellingOption>> options = const {};
  int _optionsRevision = 0;
  Future<void> _draftWrite = Future.value();
  final _cartScroll = ScrollController();
  final _cartViewport = GlobalKey();
  final _cartKeys = <String, GlobalKey>{};
  Timer? _feedbackTimer;
  String? _highlightedLine;
  String? _cartFeedback;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _cartScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    products = widget.products.where((x) => !x.isArchived).toList();
    c = ProductSelectionController(products);
    _loadSummary();
    _loadOptions();
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final repository = widget.drafts;
    if (repository == null) return;
    final lines = await repository.load(products);
    if (!mounted || lines.isEmpty) return;
    setState(() => c.restore(lines));
    await _loadOptions();
  }

  void _changeCart(VoidCallback change) {
    final previous = {for (final line in c.lines) line.key: line.baseQuantity};
    setState(change);
    _cartKeys.removeWhere((key, _) => !c.lines.any((line) => line.key == key));
    for (final line in c.lines) {
      if (line.baseQuantity > (previous[line.key] ?? 0)) {
        _highlightedLine = line.key;
        _cartFeedback =
            '${line.product.name} ${previous.containsKey(line.key) ? 'updated' : 'added'} → ${line.displayQuantity}';
        _feedbackTimer?.cancel();
        _feedbackTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _highlightedLine = null;
              _cartFeedback = null;
            });
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_cartScroll.hasClients) return;
          final itemContext = _cartKeys[line.key]?.currentContext;
          final item = itemContext?.findRenderObject();
          final viewport = _cartViewport.currentContext?.findRenderObject();
          if (item is RenderBox && viewport is RenderBox) {
            final top = item.localToGlobal(Offset.zero).dy;
            final visibleTop = viewport.localToGlobal(Offset.zero).dy;
            if (top < visibleTop ||
                top + item.size.height > visibleTop + viewport.size.height) {
              Scrollable.ensureVisible(
                itemContext!,
                duration: const Duration(milliseconds: 220),
                alignment: top < visibleTop ? 0 : 1,
              );
            }
          }
        });
        break;
      }
    }
    if (c.lines.isEmpty) {
      _highlightedLine = null;
      _cartFeedback = null;
    }
    final repository = widget.drafts;
    if (repository != null) {
      final snapshot = List<SaleCartLine>.of(c.lines);
      _draftWrite = _draftWrite
          .then((_) => repository.save(snapshot))
          .catchError((Object error, StackTrace stack) {
            if (mounted) {
              showFriendlyError(
                context,
                title: 'Could Not Save Current Sale',
                message: 'The cart is still open, but it could not be saved for recovery.',
              );
            }
          });
    }
  }

  Future<void> _clearSavedDraft() async {
    await _draftWrite;
    await widget.drafts?.clear();
  }

  @override
  void reassemble() {
    super.reassemble();
    _refreshCatalog();
  }

  Future<void> _refreshCatalog() async {
    final loader = widget.loadProducts;
    if (loader == null) return;
    final active = (await loader()).where((x) => !x.isArchived).toList();
    if (!mounted) return;
    setState(() {
      products = active;
      c = ProductSelectionController(products);
      options = const {};
    });
    await _loadOptions();
  }

  @override
  void didUpdateWidget(covariant CashSaleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.products.where((x) => !x.isArchived).toList();
    if (!identical(widget.products, oldWidget.products)) {
      final lines = c.lines;
      products = active;
      c = ProductSelectionController(products);
      c.restore(
        lines
            .where((line) => active.any((p) => p.id == line.product.id))
            .map(
              (line) => SaleCartLine(
                product: active.firstWhere((p) => p.id == line.product.id),
                option: line.option,
                quantityValue: line.quantityValue,
                quantityScale: line.quantityScale,
              ),
            ),
      );
      options = const {};
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    final revision = ++_optionsRevision;
    final repository = widget.repository;
    if (repository == null) return;
    final units = ProductUnitRepository(repository.db);
    final loaded = <int, List<SellingOption>>{};
    for (final product in products) {
      loaded[product.id] = await units.sellingOptions(product.id);
    }
    if (mounted && revision == _optionsRevision) {
      final refreshed = <SaleCartLine>[];
      for (final line in c.lines) {
        final product = products
            .where((p) => p.id == line.product.id)
            .firstOrNull;
        if (product == null) continue;
        final option = line.option.id < 0
            ? SellingOption(
                id: line.option.id,
                productId: product.id,
                name: line.option.name,
                baseQuantity: line.option.baseQuantity,
                priceCentavos: product.sellingPriceCentavos,
                isDefault: true,
              )
            : loaded[product.id]
                  ?.where((o) => o.id == line.option.id)
                  .firstOrNull;
        if (option == null) continue;
        refreshed.add(
          SaleCartLine(
            product: product,
            option: option,
            quantityValue: line.quantityValue,
            quantityScale: line.quantityScale,
          ),
        );
      }
      setState(() {
        options = loaded;
        c.restore(refreshed);
      });
    }
  }

  Future<void> _addProduct(Product product) async {
    if (product.currentQuantity <= 0) {
      await showStockAlert(context, product.name, product.currentQuantity);
      return;
    }
    final choices = options[product.id] ?? const <SellingOption>[];
    final usable = choices.isEmpty
        ? [
            SellingOption(
              id: -product.id,
              productId: product.id,
              name: 'Piece',
              baseQuantity: 1,
              priceCentavos: product.sellingPriceCentavos,
              isDefault: true,
            ),
          ]
        : choices;
    final measured =
        product.baseUnitCode == 'GRAM' &&
        usable.any((x) => x.baseQuantity >= 1000);
    if (usable.length == 1 && !measured) {
      _changeCart(() => c.add(product, usable.single));
      return;
    }
    var selected = usable.first;
    final quantity = TextEditingController(text: '1');
    String? error;
    final result = await showDialog<({SellingOption option, int value, int scale})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(product.name),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SellingOption>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'How do you sell this product?',
                  ),
                  items: usable
                      .map(
                        (x) => DropdownMenuItem(
                          value: x,
                          child: Text('${x.name} — ${money(x.priceCentavos)}'),
                        ),
                      )
                      .toList(),
                  onChanged: (x) {
                    if (x != null) {
                      setDialogState(() {
                        selected = x;
                        error = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        product.baseUnitCode == 'GRAM' &&
                            selected.baseQuantity >= 1000
                        ? 'Quantity in kg'
                        : 'Quantity',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '1 ${selected.name} uses ${selected.baseQuantity} ${product.baseUnitLabel}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final parsed = parseSaleQuantity(
                    quantity.text,
                    measured:
                        product.baseUnitCode == 'GRAM' &&
                        selected.baseQuantity >= 1000,
                  );
                  if (parsed.value * selected.baseQuantity % parsed.scale !=
                      0) {
                    throw const FormatException(
                      'Quantity cannot be converted exactly.',
                    );
                  }
                  Navigator.pop(dialogContext, (
                    option: selected,
                    value: parsed.value,
                    scale: parsed.scale,
                  ));
                } on FormatException catch (e) {
                  setDialogState(() => error = e.message);
                }
              },
              child: const Text('Add to Sale'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        _changeCart(
          () => c.add(
            product,
            result.option,
            quantityValue: result.value,
            quantityScale: result.scale,
          ),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not enough stock for that quantity.')),
        );
      }
    }
  }

  Future<void> _loadSummary() async {
    if (widget.repository == null) return;
    final values = await Future.wait<Object?>([
      widget.repository!.latestTransaction(),
      widget.repository!.dailySummary(),
    ]);
    if (mounted) {
      final today = values[1]! as ({int total, int count});
      setState(() {
        lastTransaction = values[0] as SalesHistoryEntry?;
        todaySalesTotal = today.total;
        todayTransactionCount = today.count;
      });
    }
  }

  String money(int cents) => standardMoney(cents);

  Future<void> save() async {
    if (saving || c.totalCentavos == 0) return;
    var paymentMethod = PaymentMethod.cash;
    final saleTotal = c.totalCentavos;
    var received = (saleTotal / 100).toStringAsFixed(2);
    int receivedCents() {
      final value = double.tryParse(received) ?? 0;
      return value.isFinite && value >= 0 && value <= 90000000000
          ? (value * 100).round()
          : 0;
    }

    var confirmed = false;
    var reference = '';
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (x) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long),
              SizedBox(width: 10),
              Text('Review Sale'),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  ],
                  selected: {paymentMethod},
                  onSelectionChanged: (value) =>
                      setDialog(() => paymentMethod = value.single),
                ),
                if (paymentMethod == PaymentMethod.gcash) ...[
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => reference = value,
                    decoration: const InputDecoration(
                      labelText: 'GCash Reference (optional)',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ],
                const Divider(),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: c.lines.length,
                      separatorBuilder: (_, _) => const Divider(height: 12),
                      itemBuilder: (_, i) {
                        final line = c.lines[i], p = line.product;
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${line.quantityText}${line.option.id < 0 ? '' : ' ${line.option.name}'} × ${money(line.option.priceCentavos)}',
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              money(line.lineTotalCentavos),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const Divider(),
                if (paymentMethod == PaymentMethod.cash)
                  TextFormField(
                    initialValue: received,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => setDialog(() => received = value),
                    decoration: InputDecoration(
                      labelText: 'Amount received',
                      prefixText: '₱ ',
                      errorText: receivedCents() < saleTotal
                          ? 'Amount must cover the total'
                          : null,
                      helperText:
                          'Change: ${money((receivedCents() - saleTotal).clamp(0, 1 << 53))}',
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      money(c.totalCentavos),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  paymentMethod == PaymentMethod.cash &&
                      receivedCents() < saleTotal
                  ? null
                  : () {
                      if (confirmed) return;
                      confirmed = true;
                      Navigator.pop(x, true);
                    },
              child: const Text('Complete Sale'),
            ),
          ],
        ),
      ),
    );
    final amountReceived = paymentMethod == PaymentMethod.cash
        ? receivedCents()
        : saleTotal;
    if (yes != true) return;
    setState(() => saving = true);
    var committed = false;
    try {
      await _draftWrite;
      final items = c.drafts;
      CashSaleResult? result;
      if (widget.saveSale != null) {
        await widget.saveSale!(items);
      } else {
        result = await widget.repository!.saveWithResult(
          items,
          paymentMethod: paymentMethod,
          gcashReference: reference,
        );
      }
      committed = true;
      if (mounted) setState(() => c.clear());
      final fresh =
          await (widget.loadProducts?.call() ?? Future.value(products));
      if (!mounted) return;
      setState(() {
        products = fresh;
        c = ProductSelectionController(fresh);
      });
      await _clearSavedDraft();
      await _loadSummary();
      if (result != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (x) => AlertDialog(
            title: const Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFFE5F3E9),
                  child: Icon(
                    Icons.check_rounded,
                    color: Color(0xFF287443),
                    size: 40,
                  ),
                ),
                SizedBox(height: 16),
                Text('Sale Completed'),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Payment recorded. Ready for your next customer.'),
                  const SizedBox(height: 20),
                  Text(
                    money(result!.totalCentavos),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  Text(result.paymentMethod.label),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount received'),
                      Text(money(amountReceived)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change'),
                      Text(
                        money(amountReceived - result.totalCentavos),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(x),
                child: const Text('New Sale'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        await showFriendlyError(
          context,
          title: committed ? 'Sale Saved' : 'Could Not Complete Sale',
          message: committed
              ? 'Your sale was saved, but the screen could not refresh. Do not enter this sale again. Reopen Sales to refresh the catalog.'
              : transactionFailureMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<UtangItemDraft> get _items => c.drafts;
  Future<void> checkoutUtang() async {
    if (widget.onUtang == null || c.totalCentavos == 0) return;
    final ok = await widget.onUtang!(_items);
    if (ok) {
      final fresh =
          await (widget.loadProducts?.call() ?? Future.value(products));
      if (mounted) {
        setState(() {
          products = fresh;
          c = ProductSelectionController(fresh);
        });
        await _clearSavedDraft();
      }
      await _loadSummary();
    }
  }

  Future<void> clearCart() async {
    if (c.selectedProducts.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Clear current sale?'),
        content: const Text('The selected products will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear Sale'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      _changeCart(c.clear);
      await _clearSavedDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.sizeOf(context).width >= 900;
    final content = Row(
      children: [
        Expanded(flex: landscape ? 3 : 1, child: _catalog()),
        if (landscape) SizedBox(width: 360, child: _cart()),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: content,
      floatingActionButton: landscape
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * .8,
                  child: _cart(),
                ),
              ),
              icon: const Icon(Icons.shopping_cart),
              label: Text('Cart (${c.selectedProducts.length})'),
            ),
    );
  }

  Widget _catalog() {
    final shown = products
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .where(
          (p) => switch (filter) {
            'FREQUENT' =>
              widget.frequentProductIds.contains(p.id) ||
                  widget.frequentProductNames.contains(p.name),
            'SELECTA' => widget.selectaProductIds.contains(p.id),
            'ALL' => true,
            _ => p.categoryId.toString() == filter,
          },
        )
        .toList();
    if (filter == 'FREQUENT' && widget.frequentProductIds.isNotEmpty) {
      shown.sort(
        (a, b) => widget.frequentProductIds
            .indexOf(a.id)
            .compareTo(widget.frequentProductIds.indexOf(b.id)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: AppSearchField(
            hintText: 'Search products...',
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in <(String, String)>[
                ('FREQUENT', 'Frequently Sold'),
                ('ALL', 'All'),
                if (widget.selectaProductIds.isNotEmpty) ('SELECTA', 'Selecta'),
                ...widget.categoryNames.entries.map(
                  (entry) => (entry.key.toString(), entry.value),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.$2),
                    selected: filter == item.$1,
                    onSelected: (_) => setState(() => filter = item.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              // The landscape cart uses 360px; the remaining difference is
              // the sidebar. React to its width without resetting the cart.
              final sidebarExpanded = screenWidth - box.maxWidth - 360 > 200;
              final cols = screenWidth >= 900 ? (sidebarExpanded ? 3 : 4) : 2;
              if (shown.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        filter == 'FREQUENT'
                            ? 'Frequently sold products will appear after sales.'
                            : 'No matching products',
                      ),
                      TextButton(
                        onPressed: () => setState(() => filter = 'ALL'),
                        child: const Text('Browse All Products'),
                      ),
                    ],
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: 360,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: shown.length,
                itemBuilder: (_, i) => _product(shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _product(Product p) {
    final q = c.quantityFor(p),
        out = p.currentQuantity == 0,
        low = !out && p.currentQuantity <= p.minimumStockLevel;
    final productOptions = options[p.id] ?? const <SellingOption>[];
    final defaultOption = productOptions.where((x) => x.isDefault).firstOrNull;
    final displayPrice = defaultOption?.priceCentavos ?? p.sellingPriceCentavos;
    final priceUnit = defaultOption?.name;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addProduct(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ProductImage(path: p.photoPath)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 56,
                    child: Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${money(displayPrice)}${priceUnit == null ? '' : ' / $priceUnit'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    out
                        ? 'Out of Stock'
                        : low
                        ? '${_stockText(p)} left • Low Stock'
                        : '${_stockText(p)} available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: out
                          ? Colors.red.shade700
                          : low
                          ? Colors.orange.shade800
                          : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: q > 0
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton.filledTonal(
                                onPressed: () =>
                                    _changeCart(() => c.decrease(p)),
                                icon: const Icon(Icons.remove),
                              ),
                              Text(
                                '$q',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton.filled(
                                onPressed: () => _addProduct(p),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: () => _addProduct(p),
                              child: const Text('Add'),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stockText(Product product) {
    if (product.baseUnitCode == 'GRAM') {
      return '${_friendlyDecimal(product.currentQuantity, 1000)} kg';
    }
    if (product.baseUnitCode == 'MILLILITER' &&
        product.currentQuantity >= 1000) {
      return '${_friendlyDecimal(product.currentQuantity, 1000)} L';
    }
    return '${standardNumber(product.currentQuantity)} ${product.baseUnitLabel}${product.currentQuantity == 1 ? '' : 's'}';
  }

  String _friendlyDecimal(int value, int scale) =>
      standardNumber(value / scale);

  Widget _cart() => Material(
    color: Colors.white,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Current Sale',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: c.selectedProducts.isEmpty ? null : clearCart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    backgroundColor: Colors.red.shade50,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Sale'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '${c.selectedProducts.length} products in cart',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_cartFeedback != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _cartFeedback!,
                  style: const TextStyle(
                    color: Color(0xFF126343),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: c.selectedProducts.isEmpty
                ? const Center(
                    child: Text(
                      'Your cart is empty.\nSelect products to begin a sale.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : Scrollbar(
                    controller: _cartScroll,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      key: _cartViewport,
                      controller: _cartScroll,
                      padding: const EdgeInsets.only(
                        right: 10,
                        top: 8,
                        bottom: 8,
                      ),
                      child: Column(
                        children: c.lines.map((line) {
                          final p = line.product;
                          return AnimatedContainer(
                            key: _cartKeys.putIfAbsent(
                              line.key,
                              () => GlobalKey(),
                            ),
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _highlightedLine == line.key
                                  ? const Color(0xFFB7E6C9)
                                  : const Color(0xFFEDF7EF),
                              border: Border.all(
                                color: _highlightedLine == line.key
                                    ? const Color(0xFF228557)
                                    : const Color(0xFFC4DFCD),
                                width: _highlightedLine == line.key ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: ProductImage(path: p.photoPath),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Remove item',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => _changeCart(
                                              () => c.removeLine(line),
                                            ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 19,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${line.displayQuantity} × ${money(line.option.priceCentavos)}/${line.displayUnit}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          IconButton.filledTonal(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => _changeCart(
                                              () => c.decreaseLine(line),
                                            ),
                                            icon: const Icon(
                                              Icons.remove,
                                              size: 18,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              line.quantityText,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          IconButton.filled(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: line.quantityScale != 1
                                                ? null
                                                : () {
                                                    try {
                                                      _changeCart(
                                                        () => c.increaseLine(
                                                          line,
                                                        ),
                                                      );
                                                    } catch (_) {}
                                                  },
                                            icon: const Icon(
                                              Icons.add,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          money(line.lineTotalCentavos),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          money(c.totalCentavos),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: c.totalCentavos == 0 || saving ? null : save,
                      icon: const Icon(Icons.check_circle),
                      label: Text(
                        saving ? 'Saving...' : 'Review & Complete Sale',
                      ),
                    ),
                    if (widget.onUtang != null) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: c.totalCentavos == 0 || saving
                            ? null
                            : checkoutUtang,
                        icon: const Icon(Icons.people_alt),
                        label: const Text('UTANG'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _lastTransactionCard(),
                    if (widget.repository != null) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showHistory(todayOnly: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.today, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  "TODAY'S SALES",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    money(todaySalesTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    '$todayTransactionCount transactions',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _showHistory,
                          icon: const Icon(Icons.history, size: 19),
                          label: const Text('Cash & UTANG History'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _lastTransactionCard() {
    final sale = lastTransaction;
    final utang = sale?.isUtang ?? false;
    final accent = utang
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      color: accent.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: accent.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: sale == null ? null : () => _showHistoryDetails(sale),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: sale == null
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LAST TRANSACTION',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 10),
                    Text('No sales recorded yet.'),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'LAST TRANSACTION',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            sale.reference,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            money(sale.totalCentavos),
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                          ),
                        ),
                        const Text(
                          'Click to view details ›',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      '${utang ? 'UTANG • ${sale.customerName}' : 'Cash'} • ${_saleWhen(sale.occurredAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _saleWhen(DateTime value) {
    final now = DateTime.now(),
        sameDay =
            now.year == value.year &&
            now.month == value.month &&
            now.day == value.day;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(value));
    return '${sameDay ? 'Today' : MaterialLocalizations.of(context).formatShortDate(value)} • $time';
  }

  Future<void> _showHistory({bool todayOnly = false}) async {
    var filter = 'ALL';
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setModal) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          todayOnly ? "Today's Sales" : 'All Transactions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialog),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final x in const [
                          ('ALL', 'All'),
                          ('CASH', 'Cash'),
                          ('UTANG', 'UTANG'),
                        ])
                          ChoiceChip(
                            label: Text(x.$2),
                            selected: filter == x.$1,
                            onSelected: (_) => setModal(() => filter = x.$1),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<SalesHistoryEntry>>(
                    future: widget.repository!.history(type: filter),
                    builder: (_, s) {
                      final entries = (s.data ?? const <SalesHistoryEntry>[])
                          .where((e) {
                            if (!todayOnly) return true;
                            final d = e.occurredAt.toLocal(),
                                now = DateTime.now();
                            return d.year == now.year &&
                                d.month == now.month &&
                                d.day == now.day;
                          })
                          .toList();
                      return !s.hasData
                          ? const Center(child: CircularProgressIndicator())
                          : entries.isEmpty
                          ? const Center(child: Text('No transactions found.'))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: entries.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                indent: 76,
                                endIndent: 20,
                              ),
                              itemBuilder: (_, i) {
                                final e = entries[i],
                                    local = e.occurredAt.toLocal();
                                return ListTile(
                                  leading: Icon(
                                    e.isUtang
                                        ? Icons.people_alt
                                        : Icons.payments,
                                  ),
                                  title: Text(
                                    '${e.isUtang ? 'UTANG Sale' : 'Cash Sale'} • ${e.reference}',
                                  ),
                                  subtitle: Text(
                                    '${e.customerName == null ? '' : '${e.customerName} • '}${MaterialLocalizations.of(context).formatMediumDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}\n'
                                    '${e.itemCount} items • ${e.correctedById != null
                                        ? 'CORRECTED'
                                        : e.status == 'REVERSED'
                                        ? 'REVERSED'
                                        : 'COMPLETED'}'
                                    '${e.correctionOfId == null ? '' : '\nCorrection of #${e.correctionOfId}'}',
                                  ),
                                  trailing: Text(
                                    money(e.totalCentavos),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: e.isUtang
                                          ? Colors.orange.shade800
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialog);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => _showHistoryDetails(e),
                                        );
                                  },
                                );
                              },
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHistoryDetails(SalesHistoryEntry entry) async {
    if (!entry.isUtang) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
            child: SaleDetailsScreen(
              repository: widget.repository!,
              saleId: entry.id,
              reversals: widget.reversals,
            ),
          ),
        ),
      );
      return;
    }
    final items = await widget.repository!.utangItems(entry.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('UTANG Sale • ${entry.reference}'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.customerName != null)
                  Text('Customer: ${entry.customerName}'),
                Text(_saleWhen(entry.occurredAt.toLocal())),
                const SizedBox(height: 8),
                Text(
                  'Status: ${entry.correctedById != null
                      ? 'CORRECTED'
                      : entry.status == 'REVERSED'
                      ? 'REVERSED'
                      : 'COMPLETED'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (entry.correctedById != null)
                  Text('Corrected by UTANG Sale #${entry.correctedById}'),
                if (entry.correctionOfId != null)
                  Text('Correction of UTANG Sale #${entry.correctionOfId}'),
                const Divider(),
                ...items.map(
                  (x) => ListTile(
                    title: Text(x['product_name_snapshot']! as String),
                    subtitle: Text(
                      '${x['quantity']} × ${money(x['unit_price_centavos']! as int)}',
                    ),
                    trailing: Text(money(x['line_total_centavos']! as int)),
                  ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${entry.itemCount} items\nTotal: ${money(entry.totalCentavos)}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
