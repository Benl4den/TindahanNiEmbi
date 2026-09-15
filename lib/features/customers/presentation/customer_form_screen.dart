import 'package:flutter/material.dart';

import '../../../widgets/app_back_navigation.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/customer.dart';
import '../../../repositories/customer_repository.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({
    super.key,
    required this.repository,
    this.customer,
    this.compact = false,
  });
  final CustomerRepository repository;
  final Customer? customer;
  final bool compact;
  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _key = GlobalKey<FormState>();
  late final List<TextEditingController> _c;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final x = widget.customer;
    _c = [
      TextEditingController(text: x?.fullName),
      TextEditingController(text: x?.nickname),
      TextEditingController(text: x?.mobileNumber),
      TextEditingController(text: x?.address),
      TextEditingController(text: x?.notes),
    ];
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final d = CustomerDraft(
      fullName: _c[0].text,
      nickname: _c[1].text,
      mobileNumber: _c[2].text,
      address: _c[3].text,
      notes: _c[4].text,
    );
    try {
      final x = widget.customer;
      if (x == null) {
        await widget.repository.create(d);
      } else {
        await widget.repository.update(x.id, d);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.couldNotSave)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageBackGuard(
    controllers: _c,
    busy: _saving,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final form = Form(
      key: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(0, AppStrings.name, required: true),
          if (!widget.compact) ...[
            _field(1, AppStrings.nickname),
            _field(3, AppStrings.address),
          ],
          _field(2, AppStrings.phone, phone: true),
          _field(4, AppStrings.customerNotes, lines: 3),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : AppStrings.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (widget.compact) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.newCustomer,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                form,
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.customer == null ? AppStrings.newCustomer : AppStrings.edit,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: form,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    int i,
    String label, {
    bool required = false,
    bool phone = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _c[i],
      maxLines: lines,
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(20),
      ),
      validator: required
          ? (v) => v == null || v.trim().isEmpty
                ? AppStrings.requiredCategoryName
                : null
          : null,
    ),
  );
}
