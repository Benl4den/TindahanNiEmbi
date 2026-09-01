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
  final pin = TextEditingController();
  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Security')),
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'New Staff PIN',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton(
            onPressed: () async {
              await widget.auth.setPin(UserRole.staff, pin.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Staff PIN saved.')),
                );
              }
            },
            child: const Text('Save Staff PIN'),
          ),
          const SizedBox(height: 32),
          Text('Automatic Lock', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<int>(
            future: SettingsService(widget.auth.db).autoLockMinutes,
            builder: (_, s) => DropdownButtonFormField<int>(
              initialValue: s.data,
              decoration: const InputDecoration(
                labelText: 'Lock after inactivity',
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
        ],
      ),
    ),
  );
}
