import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, required this.auth});
  final AuthService auth;
  @override
  State<SecurityScreen> createState() => _State();
}

class _State extends State<SecurityScreen> {
  late Future<List<StaffAccount>> staff;
  @override
  void initState() {
    super.initState();
    staff = widget.auth.staffAccounts();
  }

  void reload() => staff = widget.auth.staffAccounts();

  Future<void> staffDialog({StaffAccount? account}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffEditorDialog(auth: widget.auth, account: account),
    );
    if (saved == true && mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Security & Staff')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => staffDialog(),
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Add Staff'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Staff Accounts',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'PINs are securely protected. You can reset a PIN, but stored PINs cannot be viewed.',
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<StaffAccount>>(
          future: staff,
          builder: (_, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No staff accounts yet. Select Add Staff to create one.',
                  ),
                ),
              );
            }
            return Column(
              children: snapshot.data!
                  .map(
                    (x) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(x.name.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(
                          x.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${x.active ? 'Active' : 'Disabled'}${x.lastLoginAt == null ? ' • Never logged in' : ' • Last login recorded'}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => staffDialog(account: x),
                              icon: const Icon(Icons.password),
                              label: const Text('Reset PIN'),
                            ),
                            Switch(
                              value: x.active,
                              onChanged: (value) async {
                                await widget.auth.setStaffActive(x.id, value);
                                if (mounted) setState(reload);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Automatic Lock',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        FutureBuilder<int>(
          future: SettingsService(widget.auth.db).autoLockMinutes,
          builder: (_, s) => DropdownButtonFormField<int>(
            initialValue: s.data,
            decoration: const InputDecoration(
              labelText: 'Lock after inactivity',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Off')),
              DropdownMenuItem(value: 5, child: Text('5 minutes')),
              DropdownMenuItem(value: 10, child: Text('10 minutes')),
              DropdownMenuItem(value: 15, child: Text('15 minutes')),
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
            ],
            onChanged: s.hasData
                ? (v) {
                    if (v != null) {
                      SettingsService(widget.auth.db).setAutoLockMinutes(v);
                    }
                  }
                : null,
          ),
        ),
        const SizedBox(height: 90),
      ],
    ),
  );
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog({required this.auth, this.account});
  final AuthService auth;
  final StaffAccount? account;
  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  late final TextEditingController name;
  final pin = TextEditingController(), confirm = TextEditingController();
  String? error;
  bool saving = false, visible = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.account?.name ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (name.text.trim().isEmpty ||
        pin.text.length != 4 ||
        pin.text != confirm.text) {
      setState(() => error = 'Enter a name and matching 4-digit PINs.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.account == null) {
        await widget.auth.addStaff(name.text, pin.text);
      } else {
        await widget.auth.resetStaffPin(widget.account!.id, pin.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString().contains('UNIQUE')
              ? 'That staff name already exists.'
              : 'Could not save the staff account.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.account == null ? 'Add Staff' : 'Reset Staff PIN'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.account == null)
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Staff name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: pin,
            obscureText: !visible,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: 'New 4-digit PIN',
              prefixIcon: const Icon(Icons.pin_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          TextField(
            controller: confirm,
            obscureText: !visible,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
          ),
          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
