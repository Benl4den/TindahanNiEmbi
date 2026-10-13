import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/app_back_navigation.dart';

import '../../../core/formatters/display_labels.dart';

import '../../../models/product.dart';
import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
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
import '../../help/help_button.dart';
import '../../help/help_content.dart';

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
    this.onPhoneDetailVisibilityChanged,
    this.cashServicesLauncher,
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
  final ValueChanged<bool>? onPhoneDetailVisibilityChanged;
  final Widget? cashServicesLauncher;
  @override
  State<CashSaleScreen> createState() => _State();
}

class _State extends State<CashSaleScreen> {
  late ProductSelectionController c;
  late List<Product> products;
  String search = '';
  String filter = 'ALL';
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
  bool _phoneCartOpen = false;
  CashSaleResult? _phoneCompletedSale;
  PaymentMethod _phonePaymentMethod = PaymentMethod.cash;
  bool _utangSubmitting = false;
  final Set<int> _addingProducts = {};

  bool get _phoneLayout => MediaQuery.sizeOf(context).width < 900;

  void _showPhoneCart() {
    if (saving || c.lines.isEmpty) return;
    setState(() => _phoneCartOpen = true);
    widget.onPhoneDetailVisibilityChanged?.call(true);
  }

  void _closePhoneDetail() {
    setState(() {
      if (_phoneCompletedSale != null) {
        _phonePaymentMethod = PaymentMethod.cash;
      }
      _phoneCartOpen = false;
      _phoneCompletedSale = null;
    });
    widget.onPhoneDetailVisibilityChanged?.call(false);
  }

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
    try {
      setState(change);
    } on StateError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough stock available for this sale.'),
        ),
      );
      return;
    }
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
    if (!_addingProducts.add(product.id)) return;
    try {
      await _addProductUnlocked(product);
    } finally {
      _addingProducts.remove(product.id);
    }
  }

  Future<void> _addProductUnlocked(Product product) async {
    if (saving || _utangSubmitting) return;
    if (product.currentQuantity <= 0) {
      await showStockAlert(context, product.name, product.currentQuantity);
      return;
    }
    List<SellingOption> choices;
    if (options.containsKey(product.id)) {
      choices = options[product.id]!;
    } else if (widget.repository != null) {
      try {
        choices = await ProductUnitRepository(widget.repository!.db)
            .sellingOptions(product.id);
      } catch (_) {
        if (mounted) {
          await showFriendlyError(
            context,
            title: 'Could Not Load Selling Options',
            message: 'Please try this product again in a moment.',
          );
        }
        return;
      }
      if (!mounted) return;
    } else {
      choices = const <SellingOption>[];
    }
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
    if (_phoneLayout) {
      final result = await _phoneOptionSheet(product, usable);
      if (result != null && mounted) {
        _changeCart(
          () => c.add(
            product,
            result.option,
            quantityValue: result.value,
            quantityScale: result.scale,
          ),
        );
      }
      return;
    }
    var selected = usable.where((x) => x.isDefault).firstOrNull ?? usable.first;
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
                  isExpanded: true,
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

  Future<({SellingOption option, int value, int scale})?> _phoneOptionSheet(
    Product product,
    List<SellingOption> usable,
  ) async {
    var selected = usable.where((x) => x.isDefault).firstOrNull ?? usable.first;
    final quantity = TextEditingController(text: '1');
    String? error;
    final result =
        await showModalBottomSheet<
          ({SellingOption option, int value, int scale})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (_, setSheetState) {
              final measured =
                  product.baseUnitCode == 'GRAM' &&
                  selected.baseQuantity == 1000;
              ({int value, int scale})? parsed;
              try {
                parsed = parseSaleQuantity(quantity.text, measured: measured);
              } on FormatException {
                // Keep the preview blank until a valid quantity is entered.
              }
              final total = parsed == null
                  ? 0
                  : (selected.priceCentavos * parsed.value +
                            parsed.scale ~/ 2) ~/
                        parsed.scale;
              void adjust(int direction) {
                final current = double.tryParse(quantity.text) ?? 0;
                final next = current + (measured ? .25 : 1) * direction;
                quantity.text = next <= 0
                    ? (measured ? '0.25' : '1')
                    : measured
                    ? next
                          .toStringAsFixed(2)
                          .replaceFirst(RegExp(r'0+$'), '')
                          .replaceFirst(RegExp(r'\.$'), '')
                    : next.toInt().toString();
                setSheetState(() => error = null);
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (MediaQuery.sizeOf(sheetContext).height -
                            MediaQuery.viewInsetsOf(sheetContext).bottom) *
                        .85,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 58,
                                  height: 58,
                                  child: ProductImage(path: product.photoPath),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const Text('Select selling option'),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Selling Option',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleSmall,
                            ),
                            const SizedBox(height: 6),
                            for (final option in usable)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: Material(
                                  color: selected.id == option.id
                                      ? Theme.of(sheetContext)
                                            .colorScheme
                                            .primaryContainer
                                      : Theme.of(sheetContext)
                                            .colorScheme
                                            .surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => setSheetState(() {
                                      selected = option;
                                      quantity.text = '1';
                                      error = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected.id == option.id
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(option.name)),
                                          Text(
                                            money(option.priceCentavos),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              measured ? 'Quantity (kg)' : 'Quantity',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () => adjust(-1),
                                  icon: const Icon(Icons.remove),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: quantity,
                                    textAlign: TextAlign.center,
                                    keyboardType:
                                        TextInputType.numberWithOptions(
                                          decimal: measured,
                                        ),
                                    onChanged: (_) =>
                                        setSheetState(() => error = null),
                                    decoration: InputDecoration(
                                      errorText: error,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  onPressed: () => adjust(1),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                            if (measured) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final amount in const [
                                    '0.25',
                                    '0.5',
                                    '1',
                                    '2',
                                    '5',
                                  ])
                                    ActionChip(
                                      label: Text(amount),
                                      onPressed: () => setSheetState(() {
                                        quantity.text = amount;
                                        error = null;
                                      }),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text('Available stock: ${_stockText(product)}'),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  money(total),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                try {
                                  final chosen = parseSaleQuantity(
                                    quantity.text,
                                    measured: measured,
                                  );
                                  if (chosen.value *
                                          selected.baseQuantity %
                                          chosen.scale !=
                                      0) {
                                    throw const FormatException(
                                      'Quantity cannot be converted exactly.',
                                    );
                                  }
                                  final reserved = c.lines
                                      .where(
                                        (line) => line.product.id == product.id,
                                      )
                                      .fold<int>(
                                        0,
                                        (sum, line) => sum + line.baseQuantity,
                                      );
                                  if (reserved +
                                          chosen.value *
                                              selected.baseQuantity ~/
                                              chosen.scale >
                                      product.currentQuantity) {
                                    throw const FormatException(
                                      'Not enough stock for this quantity.',
                                    );
                                  }
                                  Navigator.pop(sheetContext, (
                                    option: selected,
                                    value: chosen.value,
                                    scale: chosen.scale,
                                  ));
                                } on FormatException catch (e) {
                                  setSheetState(() => error = e.message);
                                }
                              },
                              child: const Text('Add to Sale'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
    quantity.dispose();
    return result;
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
    var paymentMethod = _phoneLayout ? _phonePaymentMethod : PaymentMethod.cash;
    final saleTotal = c.totalCentavos;
    var received = (saleTotal / 100).toStringAsFixed(2);
    final receivedController = TextEditingController(text: received);
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
          scrollable: true,
          title: const Row(
            children: [
              Icon(Icons.receipt_long),
              SizedBox(width: 10),
              Expanded(child: Text('Review Sale')),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_phoneLayout)
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
                    onSelectionChanged: (value) =>
                        setDialog(() => paymentMethod = value.single),
                  ),
                if (paymentMethod != PaymentMethod.cash) ...[
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => reference = value,
                    decoration: InputDecoration(
                      labelText: paymentMethod == PaymentMethod.maya
                          ? 'Maya Reference (optional)'
                          : 'GCash Reference (optional)',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ],
                const Divider(),
                for (var i = 0; i < c.lines.length; i++) ...[
                  if (i > 0) const Divider(height: 12),
                  Builder(
                    builder: (_) {
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const Divider(),
                if (paymentMethod == PaymentMethod.cash)
                  Column(
                    children: [
                      TextFormField(
                        controller: receivedController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onTap: () {
                          if (receivedController.text.isNotEmpty) {
                            setDialog(() {
                              receivedController.clear();
                              received = '';
                            });
                          }
                        },
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
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'QUICK CASH AMOUNT',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setDialog(() {
                              received = (saleTotal / 100).toStringAsFixed(2);
                              receivedController.text = received;
                            }),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: const Text('Exact amount'),
                          ),
                          for (final cents in const [
                            2000,
                            5000,
                            10000,
                            20000,
                            50000,
                            100000,
                          ])
                            OutlinedButton(
                              onPressed: () => setDialog(() {
                                received = (cents / 100).toStringAsFixed(0);
                                receivedController.text = received;
                              }),
                              child: Text(money(cents)),
                            ),
                        ],
                      ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      money(c.totalCentavos),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
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
        if (_phoneLayout) {
          setState(() {
            _phoneCartOpen = false;
            _phoneCompletedSale = result;
          });
          widget.onPhoneDetailVisibilityChanged?.call(true);
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (x) => AlertDialog(
            title: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(x).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.check_rounded,
                    color: x.semanticColors.success,
                    size: 40,
                  ),
                ),
                SizedBox(height: 16),
                const Text('Sale Completed'),
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
                          fontWeight: FontWeight.w700,
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
    if (_utangSubmitting || widget.onUtang == null || c.totalCentavos == 0) {
      return;
    }
    setState(() => _utangSubmitting = true);
    try {
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
          await _loadSummary();
          if (mounted && _phoneCartOpen) {
            _phonePaymentMethod = PaymentMethod.cash;
            _closePhoneDetail();
          }
        }
      }
    } finally {
      if (mounted) setState(() => _utangSubmitting = false);
    }
  }

  Future<bool> _handleDeviceBack() async {
    if (saving) return true;
    if (_phoneCompletedSale != null || _phoneCartOpen) {
      _closePhoneDetail();
      return true;
    }
    if (c.lines.isEmpty) return false;
    final leave = await confirmLeavingPage(
      context,
      title: 'Leave TindaSari PH?',
      message: widget.drafts == null
          ? 'The current sale has not been completed. Leave the app?'
          : 'The current sale has not been completed. Your cart is saved for recovery. Leave the app?',
      actionLabel: 'Leave App',
    );
    if (!mounted || !leave || saving) return true;
    await _draftWrite;
    return false;
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
    final landscape = !_phoneLayout;
    final content = landscape
        ? Row(
            children: [
              Expanded(flex: 3, child: _catalogWithShortcut()),
              SizedBox(width: 360, child: _cart()),
            ],
          )
        : _phoneCompletedSale != null
        ? _phoneSuccess(_phoneCompletedSale!)
        : _phoneCartOpen
        ? _phoneCurrentSale()
        : Column(
            children: [
              Expanded(child: _catalogWithShortcut()),
              if (c.lines.isNotEmpty) _phoneCartBar(),
            ],
          );
    if (widget.embedded) {
      return SectionBackHandler(onBack: _handleDeviceBack, child: content);
    }
    return PageBackGuard(
      busy: saving,
      hasUnsavedChanges: c.lines.isNotEmpty,
      title: 'Leave current sale?',
      message: 'The current sale has not been completed.',
      actionLabel: 'Leave Sale',
      beforeLeave: () async => await _draftWrite,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
          actions: const [HelpButton(topic: HelpTopicId.cashSale)],
        ),
        body: content,
      ),
    );
  }

  Widget _catalogWithShortcut() {
    final launcher = widget.cashServicesLauncher;
    if (launcher == null) return _catalog();
    return Stack(
      children: [
        Positioned.fill(child: _catalog()),
        if (MediaQuery.viewInsetsOf(context).bottom == 0)
          Positioned(right: 16, bottom: 16, child: launcher),
      ],
    );
  }

  Widget _phoneCartBar() => SafeArea(
    top: false,
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
      child: Material(
        key: const ValueKey('phone-current-sale-bar'),
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showPhoneCart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  '${c.lines.length} ${c.lines.length == 1 ? 'item' : 'items'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  money(c.totalCentavos),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _phoneCurrentSale() {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Add more products',
                  onPressed: saving ? null : _closePhoneDetail,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Current Sale',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final line in c.lines)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 54,
                                height: 54,
                                child: ProductImage(
                                  path: line.product.photoPath,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            line.product.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: 'Item actions',
                                          onSelected: (_) => _changeCart(
                                            () => c.removeLine(line),
                                          ),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'remove',
                                              child: Text('Remove item'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${money(line.option.priceCentavos)} / ${line.displayUnit}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      children: [
                                        IconButton.filledTonal(
                                          tooltip: 'Decrease quantity',
                                          onPressed: saving
                                              ? null
                                              : () => _changeCart(
                                                  () => c.adjustLine(line, -1),
                                                ),
                                          icon: const Icon(Icons.remove),
                                        ),
                                        Text(
                                          line.quantityText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        IconButton.filledTonal(
                                          tooltip: 'Increase quantity',
                                          onPressed: saving
                                              ? null
                                              : () => _changeCart(
                                                  () => c.adjustLine(line, 1),
                                                ),
                                          icon: const Icon(Icons.add),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              money(line.lineTotalCentavos),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: saving ? null : _closePhoneDetail,
                  icon: const Icon(Icons.add),
                  label: const Text('Add more products'),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Items (${c.lines.length})'),
                            Text(money(c.totalCentavos)),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Total',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  money(c.totalCentavos),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (MediaQuery.sizeOf(context).width < 360)
                  DropdownButtonFormField<PaymentMethod>(
                    isExpanded: true,
                    initialValue: _phonePaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
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
                              setState(() => _phonePaymentMethod = value);
                            }
                          },
                  )
                else ...[
                  Text(
                    'Payment Method',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<PaymentMethod>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: PaymentMethod.cash,
                        label: Text('Cash'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                      ButtonSegment(
                        value: PaymentMethod.gcash,
                        label: Text('GCash'),
                      ),
                      ButtonSegment(
                        value: PaymentMethod.maya,
                        label: Text('Maya'),
                      ),
                    ],
                    selected: {_phonePaymentMethod},
                    onSelectionChanged: saving
                        ? null
                        : (value) => setState(
                            () => _phonePaymentMethod = value.single,
                          ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: c.totalCentavos == 0 || saving ? null : save,
                    child: Text(saving ? 'Saving…' : 'Complete Sale'),
                  ),
                ),
                if (widget.onUtang != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                      ),
                      onPressed:
                          c.totalCentavos == 0 || saving || _utangSubmitting
                          ? null
                          : checkoutUtang,
                      child: const Text('UTANG'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                    ),
                    onPressed: c.lines.isEmpty || saving ? null : clearCart,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Sale'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneSuccess(CashSaleResult result) {
    final local = result.occurredAt.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 30),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.check,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Sale Completed!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 6),
          const Center(child: Text('Transaction has been recorded.')),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Total Amount'),
                  Text(
                    money(result.totalCentavos),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Divider(height: 26),
                  _successRow('Payment Method', result.paymentMethod.label),
                  _successRow('Date & Time', '$date $time'),
                  _successRow('Reference No.', result.reference),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _closePhoneDetail,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('New Sale'),
          ),
          const SizedBox(height: 18),
          Text('Last Sale', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(money(result.totalCentavos)),
              subtitle: Text(
                '${result.itemCount} items • ${result.paymentMethod.label} • $time',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showHistory(todayOnly: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _catalog() {
    final shown = products
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .where(
          (p) => switch (filter) {
            'SELECTA' => widget.selectaProductIds.contains(p.id),
            'ALL' => true,
            _ => p.categoryId.toString() == filter,
          },
        )
        .toList();
    if (filter == 'ALL' && widget.frequentProductIds.isNotEmpty) {
      shown.sort((a, b) {
        final left = widget.frequentProductIds.indexOf(a.id);
        final right = widget.frequentProductIds.indexOf(b.id);
        return (left < 0 ? 1 << 30 : left).compareTo(
          right < 0 ? 1 << 30 : right,
        );
      });
    }
    return Column(
      children: [
        if (_phoneLayout && widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sales',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Search products...',
                  onChanged: (v) => setState(() => search = v),
                ),
              ),
              if (widget.embedded) ...[
                const SizedBox(width: 8),
                const HelpButton(topic: HelpTopicId.cashSale),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in <(String, String)>[
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
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  widget.cashServicesLauncher == null ? 16 : 88,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: _phoneLayout ? 230 : 360,
                  crossAxisSpacing: _phoneLayout ? 8 : 12,
                  mainAxisSpacing: _phoneLayout ? 8 : 12,
                ),
                itemCount: shown.length,
                itemBuilder: (_, i) =>
                    _phoneLayout ? _phoneProduct(shown[i]) : _product(shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _phoneProduct(Product p) {
    final out = p.currentQuantity <= 0;
    final low = !out && p.currentQuantity <= p.minimumStockLevel;
    final productOptions = options[p.id] ?? const <SellingOption>[];
    final chosen = productOptions.where((x) => x.isDefault).firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addProduct(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: ProductImage(path: p.photoPath),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    money(chosen?.priceCentavos ?? p.sellingPriceCentavos),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _stockText(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    out
                        ? 'Out of Stock'
                        : low
                        ? 'Low Stock'
                        : 'In Stock',
                    style: TextStyle(
                      color: out
                          ? Theme.of(context).colorScheme.error
                          : low
                          ? Colors.orange.shade800
                          : context.semanticColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: ProductImage(path: p.photoPath),
              ),
            ),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${money(displayPrice)}${priceUnit == null ? '' : ' / $priceUnit'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
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
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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
    color: Theme.of(context).colorScheme.surface,
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
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
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
                  style: TextStyle(
                    color: context.semanticColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: c.selectedProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 42,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your cart is empty.\nSelect products to begin a sale.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
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
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : context.semanticColors.surfaceContainer,
                              border: Border.all(
                                color: _highlightedLine == line.key
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
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
                                                fontWeight: FontWeight.w700,
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
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          IconButton.filled(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: line.quantityScale != 1
                                                ? null
                                                : () => _changeCart(
                                                    () => c.increaseLine(line),
                                                  ),
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
                                            fontWeight: FontWeight.w700,
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
                            fontWeight: FontWeight.w700,
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
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    money(todaySalesTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
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
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                            style: TextStyle(fontWeight: FontWeight.w700),
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
                              fontWeight: FontWeight.w700,
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
                      '${utang ? 'UTANG • ${sale.customerName}' : sale.paymentMethod.label} • ${_saleWhen(sale.occurredAt.toLocal())}',
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
                          ('GCASH', 'GCash'),
                          ('MAYA', 'Maya'),
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
                                    '${e.isUtang ? 'UTANG Sale' : '${e.paymentMethod.label} Sale'} • ${e.reference}',
                                  ),
                                  subtitle: Text(
                                    '${e.customerName == null ? '' : '${e.customerName} • '}${MaterialLocalizations.of(context).formatMediumDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}\n'
                                    '${e.itemCount} items • ${e.correctedById != null
                                        ? DisplayLabels.status('CORRECTED')
                                        : e.status == 'REVERSED'
                                        ? DisplayLabels.status('REVERSED')
                                        : DisplayLabels.status('POSTED')}'
                                    '${e.correctionOfId == null ? '' : '\nFix for #${e.correctionOfId}'}',
                                  ),
                                  trailing: Text(
                                    money(e.totalCentavos),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
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
                      ? DisplayLabels.status('CORRECTED')
                      : entry.status == 'REVERSED'
                      ? DisplayLabels.status('REVERSED')
                      : DisplayLabels.status('POSTED')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (entry.correctedById != null)
                  Text('Fixed by UTANG Sale #${entry.correctedById}'),
                if (entry.correctionOfId != null)
                  Text('Fix for UTANG Sale #${entry.correctionOfId}'),
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
