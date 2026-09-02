import 'package:flutter/material.dart';

import '../../../models/expense.dart';
import '../../../repositories/expense_repository.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/summary_card.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.repository,
    required this.auth,
  });
  final ExpenseRepository repository;
  final AuthService auth;
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final search = TextEditingController();
  int? categoryId;
  DateTime? date;
  late Future<List<ExpenseCategory>> categoryData;
  late Future<List<Expense>> data;
  late Future<ExpenseSummary> summary;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _reload() {
    categoryData = widget.repository.categories(activeOnly: false);
    final from = date == null
        ? null
        : DateTime(date!.year, date!.month, date!.day);
    data = widget.repository.list(
      query: search.text,
      categoryId: categoryId,
      from: from,
      to: from?.add(const Duration(days: 1)),
    );
    summary = widget.repository.summary(DateTime.now());
  }

  void _refresh() => setState(_reload);
  String money(int value) => '₱${(value / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Expenses'),
      actions: [
        IconButton(
          tooltip: 'Manage categories',
          icon: const Icon(Icons.category_outlined),
          onPressed: _manageCategories,
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add Expense'),
    ),
    body: RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "TODAY'S EXPENSES",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          FutureBuilder<ExpenseSummary>(
            future: summary,
            builder: (_, s) {
              if (s.hasError) return _error(s.error);
              if (!s.hasData) return const LinearProgressIndicator();
              final x = s.data!;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SummaryCard(
                    label: 'Total Expenses Today',
                    value: money(x.total),
                  ),
                  SummaryCard(label: 'Number of Expenses', value: '${x.count}'),
                  SummaryCard(
                    label: 'Largest Expense',
                    value: money(x.largest),
                  ),
                  SummaryCard(
                    label: 'Most Used Category',
                    value: x.topCategory ?? '—',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          TextField(
            controller: search,
            onChanged: (_) => _refresh(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search expenses',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 300,
                child: FutureBuilder<List<ExpenseCategory>>(
                  future: categoryData,
                  builder: (_, snapshot) => DropdownButtonFormField<int?>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.category_outlined),
                      labelText: 'Category',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      ...?snapshot.data
                          ?.where((x) => !x.isArchived)
                          .map(
                            (x) => DropdownMenuItem<int?>(
                              value: x.id,
                              child: Text(x.name),
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      categoryId = value;
                      _refresh();
                    },
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  date == null
                      ? 'All Dates'
                      : MaterialLocalizations.of(context)
                            .formatMediumDate(date!),
                ),
                onPressed: _pickDate,
              ),
              if (date != null)
                TextButton(
                  onPressed: () {
                    date = null;
                    _refresh();
                  },
                  child: const Text('Clear date'),
                ),
            ],
          ),
          FutureBuilder<List<Expense>>(
            future: data,
            builder: (_, s) {
              if (s.hasError) return _error(s.error);
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text('No expenses match these filters.'),
                  ),
                );
              }
              return Column(
                children: s.data!
                    .map(
                      (x) => Card(
                        child: ListTile(
                          minVerticalPadding: 16,
                          leading: const CircleAvatar(
                            child: Icon(Icons.receipt_long),
                          ),
                          title: Text(
                            x.description,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${x.categoryName} • ${x.reference}\n${_when(x.expenseDateTime.toLocal())} • ${x.status}',
                          ),
                          trailing: Text(
                            money(x.amountCentavos),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: () => _details(x.id),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 90),
        ],
      ),
    ),
  );

  Widget _error(Object? e) => const Padding(
    padding: EdgeInsets.all(20),
    child: Text(
      'Expenses could not be loaded. Please try again.',
      style: TextStyle(color: Colors.red),
    ),
  );
  String _when(DateTime d) =>
      '${MaterialLocalizations.of(context).formatMediumDate(d)} • ${TimeOfDay.fromDateTime(d).format(context)}';
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      date = picked;
      _refresh();
    }
  }

  Future<void> _edit({Expense? original}) async {
    final categories = await widget.repository.categories();
    if (!mounted) return;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an active expense category first.')),
      );
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseForm(
        repository: widget.repository,
        auth: widget.auth,
        categories: categories,
        original: original,
      ),
    );
    if (result == true && mounted) _refresh();
  }

  Future<void> _details(int id) async {
    final expense = await widget.repository.get(id);
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(expense.reference),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('Status', expense.status),
                _detail('Category', expense.categoryName),
                _detail('Amount', money(expense.amountCentavos)),
                _detail(
                  'Expense date/time',
                  _when(expense.expenseDateTime.toLocal()),
                ),
                _detail('Description', expense.description),
                if (expense.notes != null) _detail('Notes', expense.notes!),
                if (expense.referenceNo != null)
                  _detail('Reference No.', expense.referenceNo!),
                _detail('Created', _when(expense.createdAt.toLocal())),
                if (expense.correctedByReference != null)
                  _detail('Corrected By', expense.correctedByReference!),
                if (expense.correctionOfReference != null)
                  _detail('Correction Of', expense.correctionOfReference!),
                if (expense.reason != null) _detail('Reason', expense.reason!),
                if (expense.changedAt != null)
                  _detail('Changed', _when(expense.changedAt!.toLocal())),
              ],
            ),
          ),
        ),
        actions: [
          if (expense.status == 'POSTED')
            TextButton(
              onPressed: () => Navigator.pop(c, 'reverse'),
              child: const Text('Reverse Only'),
            ),
          if (expense.status == 'POSTED')
            FilledButton(
              onPressed: () => Navigator.pop(c, 'correct'),
              child: const Text('Correct Expense'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'correct') await _edit(original: expense);
    if (action == 'reverse') await _reverse(expense);
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text('$label\n$value', style: const TextStyle(fontSize: 16)),
  );

  Future<void> _reverse(Expense expense) async {
    final reason = TextEditingController(), pin = TextEditingController();
    var busy = false, error = '';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (outer) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: const Text('Reverse Only'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This will cancel this posted expense. The original record will remain in history.',
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
                TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Owner PIN'),
                ),
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(outer, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (reason.text.trim().isEmpty || pin.text.isEmpty) {
                        setLocal(
                          () => error = 'Reason and Owner PIN are required.',
                        );
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        final role = await widget.auth.verify(pin.text);
                        if (role != UserRole.owner) {
                          throw const ExpenseException('Incorrect Owner PIN.');
                        }
                        await widget.repository.reverse(
                          expense.id,
                          reason: reason.text,
                          ownerPinAuthorized: true,
                        );
                        if (outer.mounted) Navigator.pop(outer, true);
                      } catch (e) {
                        if (outer.mounted) {
                          setLocal(() {
                            busy = false;
                            error = e is ExpenseException ? e.message : 'Expense could not be reversed. Please try again.';
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Reversing…' : 'Confirm Reverse'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    pin.dispose();
    if (ok == true && mounted) _refresh();
  }

  Future<void> _manageCategories() async {
    await showDialog<void>(
      context: context,
      builder: (c) => _CategoryManager(repository: widget.repository),
    );
    if (mounted) _refresh();
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    required this.repository,
    required this.auth,
    required this.categories,
    this.original,
  });
  final ExpenseRepository repository;
  final AuthService auth;
  final List<ExpenseCategory> categories;
  final Expense? original;
  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late int categoryId;
  late DateTime when;
  late final TextEditingController amount,
      description,
      notes,
      reference,
      reason,
      pin;
  String error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final x = widget.original;
    categoryId = x?.categoryId ?? widget.categories.first.id;
    when = x?.expenseDateTime.toLocal() ?? DateTime.now();
    amount = TextEditingController(
      text: x == null ? '' : (x.amountCentavos / 100).toStringAsFixed(2),
    );
    description = TextEditingController(text: x?.description);
    notes = TextEditingController(text: x?.notes);
    reference = TextEditingController(text: x?.referenceNo);
    reason = TextEditingController();
    pin = TextEditingController();
  }

  @override
  void dispose() {
    for (final x in [amount, description, notes, reference, reason, pin]) {
      x.dispose();
    }
    super.dispose();
  }

  int? get cents {
    final value = double.tryParse(amount.text.trim());
    return value == null ? null : (value * 100).round();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.original == null ? 'Add Expense' : 'Correct Expense'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          children: [
            if (widget.original != null)
              Card(
                child: ListTile(
                  title: const Text('ORIGINAL'),
                  subtitle: Text(
                    '${widget.original!.categoryName} • ₱${(widget.original!.amountCentavos / 100).toStringAsFixed(2)}\n${widget.original!.description}',
                  ),
                ),
              ),
            DropdownButtonFormField<int>(
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Expense Category'),
              items: widget.categories
                  .map(
                    (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => categoryId = v!),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(
                labelText: 'Description / Purpose',
              ),
            ),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference No. (optional)',
              ),
            ),
            ListTile(
              title: const Text('Date and time'),
              subtitle: Text(
                '${when.month}/${when.day}/${when.year} • ${TimeOfDay.fromDateTime(when).format(context)}',
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: busy ? null : _pickWhen,
            ),
            if (widget.original != null) ...[
              Card(
                child: ListTile(
                  title: const Text('CORRECTED'),
                  subtitle: Text(
                    'New amount: ₱${((cents ?? 0) / 100).toStringAsFixed(2)}\nDifference: ${_difference()}',
                  ),
                ),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Correction reason',
                ),
              ),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Owner PIN'),
              ),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : _save,
        child: Text(busy ? 'Saving…' : 'Save'),
      ),
    ],
  );
  String _difference() {
    final diff = (cents ?? 0) - widget.original!.amountCentavos;
    return '${diff < 0
        ? '-'
        : diff > 0
        ? '+'
        : ''}₱${(diff.abs() / 100).toStringAsFixed(2)}';
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(when),
    );
    if (t != null) {
      setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }
  }

  Future<void> _save() async {
    if ((cents ?? 0) <= 0 ||
        description.text.trim().isEmpty ||
        (widget.original != null &&
            (reason.text.trim().isEmpty || pin.text.isEmpty))) {
      setState(
        () => error =
            'Complete all required fields. Amount must be greater than zero.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final draft = ExpenseDraft(
        categoryId: categoryId,
        amountCentavos: cents!,
        description: description.text,
        expenseDateTime: when,
        notes: notes.text,
        referenceNo: reference.text,
      );
      if (widget.original == null) {
        await widget.repository.add(draft);
      } else {
        final role = await widget.auth.verify(pin.text);
        if (role != UserRole.owner) {
          throw const ExpenseException('Incorrect Owner PIN.');
        }
        await widget.repository.correct(
          widget.original!.id,
          draft,
          reason: reason.text,
          ownerPinAuthorized: true,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is ExpenseException
              ? e.message
              : 'Expense could not be saved. Please try again.';
        });
      }
    }
  }
}

class _CategoryManager extends StatefulWidget {
  const _CategoryManager({required this.repository});
  final ExpenseRepository repository;
  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  final name = TextEditingController();
  late Future<List<ExpenseCategory>> data;
  String error = '';
  @override
  void initState() {
    super.initState();
    data = widget.repository.categories(activeOnly: false);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void reload() =>
      setState(() => data = widget.repository.categories(activeOnly: false));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Expense Categories'),
    content: SizedBox(
      width: 520,
      height: 500,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'New category'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
          if (error.isNotEmpty)
            Text(error, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: FutureBuilder<List<ExpenseCategory>>(
              future: data,
              builder: (_, snapshot) => ListView(
                children: (snapshot.data ?? const <ExpenseCategory>[])
                    .map(
                      (x) => ListTile(
                        title: Text(x.name),
                        subtitle: Text(x.isArchived ? 'Archived' : 'Active'),
                        trailing: x.isArchived
                            ? null
                            : IconButton(
                                tooltip: 'Archive',
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () async {
                                  await widget.repository.archiveCategory(x.id);
                                  reload();
                                },
                              ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  Future<void> _add() async {
    try {
      await widget.repository.addCategory(name.text);
      name.clear();
      error = '';
      reload();
    } catch (e) {
      setState(
        () => error = e is ExpenseException
            ? e.message
            : 'Category could not be added.',
      );
    }
  }
}
