import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import 'first_run_setup.dart';
import 'inactivity_lock_region.dart';

class _StartupState {
  const _StartupState(this.hasOwner, this.storeName, this.setupStage);
  final bool hasOwner;
  final String? storeName;
  final OwnerSetupStage? setupStage;

  bool get pendingOwnerSetup =>
      hasOwner && setupStage != null && setupStage != OwnerSetupStage.complete;
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.builder});
  final AuthService auth;
  final Widget Function(UserRole role, VoidCallback lock) builder;
  @override
  State<AuthGate> createState() => _State();
}

class _State extends State<AuthGate> {
  final pin = TextEditingController();
  final keyboardFocus = FocusNode();
  late Future<_StartupState> configured;
  late Future<List<StaffAccount>> staff;
  UserRole? role, sessionRole;
  StaffAccount? selectedStaff;
  Widget? session;
  String? error;
  bool submitting = false;
  bool showSetupSuccess = false;
  int failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    configured = _loadStartup();
    staff = widget.auth.staffAccounts(activeOnly: true);
  }

  @override
  void dispose() {
    pin.dispose();
    keyboardFocus.dispose();
    super.dispose();
  }

  void retry() => setState(() {
    configured = _loadStartup();
    staff = widget.auth.staffAccounts(activeOnly: true);
  });

  Future<_StartupState> _loadStartup() async {
    final settings = SettingsService(widget.auth.db);
    final hasOwner = await widget.auth.hasOwner;
    final name = await settings.savedStoreName;
    final stage = await settings.ownerSetupStage;
    return _StartupState(hasOwner, name, stage);
  }

  void digit(String value) {
    if (pin.text.length < 4 && !submitting) {
      setState(() {
        pin.text += value;
        error = null;
      });
      if (pin.text.length == 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) => submit());
      }
    }
  }

  void backspace() {
    if (pin.text.isNotEmpty) {
      setState(() => pin.text = pin.text.substring(0, pin.text.length - 1));
    }
  }

  Future<void> submit() async {
    if (submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final found = await widget.auth.verify(
        pin.text,
        staffId: selectedStaff?.id,
      );
      if (!mounted) return;
      final startup = await configured;
      if (!mounted) return;
      setState(() {
        if (found == null) {
          failedAttempts++;
          final remaining = (5 - failedAttempts).clamp(0, 5);
          error = remaining > 0
              ? 'Incorrect PIN • $remaining attempt${remaining == 1 ? '' : 's'} remaining'
              : 'Too many attempts. Please wait before trying again.';
        } else if (startup.pendingOwnerSetup) {
          if (found == UserRole.owner) {
            failedAttempts = 0;
            showSetupSuccess = true;
          } else {
            error = 'Complete Owner setup before using a staff account.';
          }
        } else {
          failedAttempts = 0;
          role = found;
          CurrentActor.staffName = found == UserRole.staff
              ? selectedStaff?.name
              : null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Could not verify PIN. Try again.',
        );
      }
    } finally {
      pin.clear();
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (role != null) {
      if (session == null || sessionRole != role) {
        sessionRole = role;
        session = InactivityLockRegion(
          settings: SettingsService(widget.auth.db),
          onTimeout: _lock,
          child: widget.builder(role!, _lock),
        );
      }
      return session!;
    }
    return FutureBuilder<_StartupState>(
      future: configured,
      builder: (_, state) {
        if (state.hasError) return _startupError();
        if (!state.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final startup = state.data!;
        if (showSetupSuccess) {
          return FirstRunSetup(
            auth: widget.auth,
            settings: SettingsService(widget.auth.db),
            initialName: startup.storeName,
            initialStep: FirstRunStep.complete,
            onComplete: () => setState(() => role = UserRole.owner),
          );
        }
        if (!startup.hasOwner) {
          return FirstRunSetup(
            auth: widget.auth,
            settings: SettingsService(widget.auth.db),
            initialName: startup.storeName,
            initialStep: startup.storeName == null
                ? FirstRunStep.welcome
                : FirstRunStep.ownerPin,
            onComplete: () => setState(() => role = UserRole.owner),
          );
        }
        return _login(ownerOnly: startup.pendingOwnerSetup);
      },
    );
  }

  void _lock() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      CurrentActor.staffName = null;
      role = null;
      configured = _loadStartup();
      showSetupSuccess = false;
      selectedStaff = null;
      failedAttempts = 0;
      error = null;
      staff = widget.auth.staffAccounts(activeOnly: true);
    });
  }

  Widget _login({bool ownerOnly = false}) => Scaffold(
    body: KeyboardListener(
      autofocus: true,
      focusNode: keyboardFocus,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final key = event.logicalKey.keyLabel;
        if (RegExp(r'^\d$').hasMatch(key)) digit(key);
        if (event.logicalKey == LogicalKeyboardKey.backspace) backspace();
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            pin.text.length == 4) {
          submit();
        }
      },
      child: LayoutBuilder(
        builder: (_, box) {
          final wide = box.maxWidth >= 760;
          final brand = _LoginBrand(compact: !wide);
          final form = Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 44 : 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 510),
                child: _loginCard(compact: !wide, ownerOnly: ownerOnly),
              ),
            ),
          );
          return wide
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: _LoginBackdrop(
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(flex: 47, child: brand),
                        Expanded(flex: 53, child: form),
                      ],
                    ),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 250, child: brand),
                    Expanded(child: form),
                  ],
                );
        },
      ),
    ),
  );

  Widget _loginCard({required bool compact, required bool ownerOnly}) => Card(
    elevation: 8,
    shadowColor: Colors.black.withValues(alpha: .12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 24, 20, 24)
          : const EdgeInsets.fromLTRB(36, 30, 36, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                color: Color(0xffe3f3e8),
                shape: BoxShape.circle,
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 46,
                    color: Color(0xff126b3b),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: Color(0xff126b3b),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'Welcome back!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose your account and enter your 4-digit PIN',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FutureBuilder<List<StaffAccount>>(
            future: staff,
            builder: (_, s) {
              final accounts = ownerOnly
                  ? const <StaffAccount>[]
                  : s.data ?? const <StaffAccount>[];
              return SizedBox(
                height: 76,
                child: DropdownButtonFormField<int?>(
                  initialValue: selectedStaff?.id,
                  isDense: false,
                  itemHeight: 64,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Owner'),
                    ),
                    ...accounts.map(
                      (x) => DropdownMenuItem<int?>(
                        value: x.id,
                        child: Text(x.name),
                      ),
                    ),
                  ],
                  selectedItemBuilder: (_) => [
                    _accountIdentity('O', 'Owner', 'Owner'),
                    ...accounts.map(
                      (x) => _accountIdentity(
                        x.name.substring(0, 1).toUpperCase(),
                        x.name,
                        'Cashier',
                      ),
                    ),
                  ],
                  onChanged: (id) => setState(() {
                    selectedStaff = accounts
                        .where((x) => x.id == id)
                        .firstOrNull;
                    pin.clear();
                    error = null;
                  }),
                ),
              );
            },
          ),
          if (selectedStaff != null)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  selectedStaff = null;
                  pin.clear();
                  error = null;
                }),
                icon: const Icon(Icons.switch_account_outlined, size: 20),
                label: const Text('Switch Account'),
              ),
            ),
          SizedBox(height: selectedStaff == null ? 17 : 2),
          TweenAnimationBuilder<double>(
            key: ValueKey(failedAttempts),
            tween: Tween(begin: failedAttempts == 0 ? 0 : -9, end: 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (_, offset, child) =>
                Transform.translate(offset: Offset(offset, 0), child: child),
            child: Semantics(
              label: '${pin.text.length} PIN digits entered',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (i) => Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < pin.text.length
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
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
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 18),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(children: row.map(_number).toList()),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              _number('0'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: SizedBox(
                    height: 55,
                    child: IconButton(
                      onPressed: backspace,
                      icon: const Icon(Icons.backspace_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface,
                        elevation: 3,
                        shadowColor: Colors.black.withValues(alpha: .12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: pin.text.length == 4 && !submitting
                ? () => submit()
                : null,
            icon: const Icon(Icons.lock_open),
            label: Text(submitting ? 'Checking…' : 'Unlock'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your activity will be recorded securely',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _accountIdentity(String initial, String name, String roleName) => Row(
    children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xff248548),
        foregroundColor: Colors.white,
        child: Text(
          initial,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 11),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.05, fontWeight: FontWeight.w700),
          ),
          Text(
            roleName,
            style: TextStyle(
              height: 1.05,
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _number(String value) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: SizedBox(
        height: 55,
        child: FilledButton(
          onPressed: () => digit(value),
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: .12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .24),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),
  );

  Widget _startupError() => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56),
          const SizedBox(height: 12),
          const Text('Could not load security settings.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xff075d39), Color(0xff003d27)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _GreenPatternPainter()),
        ),
        if (compact)
          Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.paddingOf(context).top + 8,
                20,
                36,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/tindasari_ts_transparent.png',
                    width: 60,
                    height: 60,
                    semanticLabel: 'TindaSari PH',
                  ),
                  const SizedBox(height: 6),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'TindaSari PH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Simple to run. Built for your store.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff8ee19e),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/tindasari_ts_transparent.png',
                    width: 122,
                    height: 122,
                    semanticLabel: 'TindaSari PH',
                  ),
                  const SizedBox(height: 30),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'TindaSari PH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Simple to run. Built for your store.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff8ee19e),
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    width: 46,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xff66d985),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: .14,
                    child: Image.asset(
                      'assets/branding/tindasari_ts_transparent.png',
                      width: 150,
                      height: 150,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          left: compact ? 20 : 30,
          right: compact ? 20 : 30,
          bottom: compact ? 12 : 24,
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xff62dc87),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 14,
                  color: Color(0xff07502f),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Ready  •  Data saved on this device',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop({required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LoginBackdropPainter(dark));
}

class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xFF141816) : const Color(0xfff7f8f7),
    );
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * .51, 0)
      ..lineTo(size.width * .435, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff075635), Color(0xff003d27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _LoginBackdropPainter oldDelegate) =>
      dark != oldDelegate.dark;
}

class _GreenPatternPainter extends CustomPainter {
  const _GreenPatternPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var radius = 130.0; radius < 520; radius += 95) {
      canvas.drawCircle(
        Offset(size.width * .08, size.height * .04),
        radius,
        line,
      );
    }
    final dot = Paint()..color = Colors.white.withValues(alpha: .10);
    for (var x = 24.0; x < 150; x += 14) {
      for (var y = size.height - 150.0; y < size.height - 25; y += 14) {
        canvas.drawCircle(Offset(x, y), 2.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
