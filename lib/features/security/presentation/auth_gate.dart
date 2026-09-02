import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final keyboardFocus = FocusNode();
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
    keyboardFocus.dispose();
    super.dispose();
  }

  void enterDigit(String digit) {
    if (pin.text.length >= 4) return;
    setState(() {
      pin.text += digit;
      error = null;
    });
  }

  void backspace() {
    if (pin.text.isEmpty) return;
    setState(() => pin.text = pin.text.substring(0, pin.text.length - 1));
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
      setState(
        () => error = 'Use exactly 4 digits and make sure both PINs match.',
      );
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
        if (!setup) {
          return Scaffold(
            body: KeyboardListener(
              autofocus: true,
              focusNode: keyboardFocus,
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) return;
                final label = event.logicalKey.keyLabel;
                if (RegExp(r'^\d$').hasMatch(label)) {
                  enterDigit(label);
                }
                if (event.logicalKey == LogicalKeyboardKey.backspace) {
                  backspace();
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    pin.text.length >= 4) {
                  submit(false);
                }
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront,
                            size: 58,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'TindahanNiEmbi',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          const Text('Enter your PIN to continue'),
                          const SizedBox(height: 22),
                          Semantics(
                            label: '${pin.text.length} PIN digits entered',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                4,
                                (i) => Container(
                                  width: 16,
                                  height: 16,
                                  margin: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i < pin.text.length
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          for (final row in const [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                          ])
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: row
                                  .map((x) => _numberButton(x))
                                  .toList(),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              const SizedBox(width: 76, height: 64),
                              _numberButton('0'),
                              SizedBox(
                                width: 76,
                                height: 64,
                                child: IconButton.filledTonal(
                                  tooltip: 'Backspace',
                                  onPressed: backspace,
                                  icon: const Icon(Icons.backspace_outlined),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: pin.text.length >= 4
                                  ? () => submit(false)
                                  : null,
                              child: const Text('Unlock'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
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
                      maxLength: 4,
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
                        maxLength: 4,
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

  Widget _numberButton(String digit) => Padding(
    padding: const EdgeInsets.all(5),
    child: SizedBox(
      width: 76,
      height: 64,
      child: FilledButton.tonal(
        onPressed: () => enterDigit(digit),
        child: Text(digit, style: const TextStyle(fontSize: 25)),
      ),
    ),
  );
}
