import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import 'inactivity_lock_region.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.builder});
  final AuthService auth;
  final Widget Function(UserRole role, VoidCallback lock) builder;
  @override
  State<AuthGate> createState() => _State();
}

class _State extends State<AuthGate> {
  final pin = TextEditingController(), confirm = TextEditingController();
  UserRole? role;
  String? error;
  late Future<bool> configured;
  Widget? session;
  UserRole? sessionRole;
  @override
  void initState() {
    super.initState();
    configured = widget.auth.hasOwner;
  }

  void retryConfiguration() =>
      setState(() => configured = widget.auth.hasOwner);

  @override
  void dispose() {
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit(bool setup) async {
    try {
      if (setup) {
        if (pin.text != confirm.text) throw ArgumentError();
        await widget.auth.setPin(UserRole.owner, pin.text);
        setState(() => role = UserRole.owner);
      } else {
        final found = await widget.auth.verify(pin.text);
        if (found == null) {
          setState(() => error = 'Incorrect PIN.');
        } else {
          setState(() => role = found);
        }
      }
    } catch (_) {
      setState(() => error = 'Use 4–6 digits and make sure both PINs match.');
    }
    pin.clear();
    confirm.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (role != null) {
      if (session == null || sessionRole != role) {
        sessionRole = role;
        session = InactivityLockRegion(
          settings: SettingsService(widget.auth.db),
          onTimeout: () => setState(() => role = null),
          child: widget.builder(role!, () => setState(() => role = null)),
        );
      }
      return Stack(children: [Offstage(offstage: false, child: session!)]);
    }
    final login = FutureBuilder<bool>(
      future: configured,
      builder: (_, s) {
        if (s.hasError) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_person_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Could not load the PIN settings.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: retryConfiguration,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!s.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final setup = !s.data!;
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      setup ? 'Set Owner PIN' : 'TindahanNiEmbi',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Enter PIN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (setup)
                      TextField(
                        controller: confirm,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Confirm PIN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    FilledButton(
                      onPressed: () => submit(setup),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                      ),
                      child: Text(setup ? 'Save PIN' : 'Log In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (session == null) return login;
    return Stack(
      children: [
        Offstage(offstage: true, child: session!),
        Positioned.fill(child: login),
      ],
    );
  }
}
