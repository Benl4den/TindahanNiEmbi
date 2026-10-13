import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/brand_logo.dart';

enum FirstRunStep { welcome, storeName, ownerPin, complete }

class FirstRunSetup extends StatefulWidget {
  const FirstRunSetup({
    super.key,
    required this.auth,
    required this.settings,
    required this.onComplete,
    this.initialName,
    this.initialStep = FirstRunStep.welcome,
  });

  final AuthService auth;
  final SettingsService settings;
  final VoidCallback onComplete;
  final String? initialName;
  final FirstRunStep initialStep;

  @override
  State<FirstRunSetup> createState() => _FirstRunSetupState();
}

class _FirstRunSetupState extends State<FirstRunSetup> {
  static const _storefrontAsset =
      'assets/branding/tindasari_storefront_clean.png';
  static const _lightbulbAsset =
      'assets/branding/tindasari_lightbulb_clean.png';

  late FirstRunStep step;
  late final TextEditingController name;
  final pin = TextEditingController();
  final confirmation = TextEditingController();
  final pinFocus = FocusNode();
  final confirmationFocus = FocusNode();
  bool busy = false;
  bool nameSubmitted = false;
  String? error;

  @override
  void initState() {
    super.initState();
    step = widget.initialStep;
    name = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    confirmation.dispose();
    pinFocus.dispose();
    confirmationFocus.dispose();
    super.dispose();
  }

  void _back() {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      error = null;
      step = step == FirstRunStep.ownerPin
          ? FirstRunStep.storeName
          : FirstRunStep.welcome;
    });
  }

  Future<void> _continueName() async {
    final validation = SettingsService.validateStoreName(name.text);
    if (validation != null) {
      setState(() => nameSubmitted = true);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.settings.saveInitialStoreName(name.text);
      if (!mounted) return;
      name.text = saved;
      FocusScope.of(context).unfocus();
      setState(() => step = FirstRunStep.ownerPin);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save your store name. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _createPin() async {
    if (busy || pin.text.length != 4 || pin.text != confirmation.text) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.setPin(UserRole.owner, pin.text);
      await widget.settings.markOwnerPinCreated();
      if (!mounted) return;
      pin.clear();
      confirmation.clear();
      FocusScope.of(context).unfocus();
      setState(() => step = FirstRunStep.complete);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not secure your store. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finish() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.settings.completeOwnerSetup();
      if (mounted) widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not finish setup. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: SizedBox(
                width: math.min(box.maxWidth, 480),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: box.maxWidth < 340 ? 20 : 28,
                      vertical: 20,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (step == FirstRunStep.storeName ||
                              step == FirstRunStep.ownerPin) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                tooltip: 'Back',
                                onPressed: busy ? null : _back,
                                icon: const Icon(Icons.arrow_back),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _progress(context),
                            const SizedBox(height: 26),
                          ] else
                            const SizedBox(height: 18),
                          if (step == FirstRunStep.welcome)
                            _welcome(context)
                          else if (step == FirstRunStep.storeName)
                            _storeName(context)
                          else if (step == FirstRunStep.ownerPin)
                            _ownerPin(context)
                          else
                            _complete(context),
                          const Spacer(),
                          if (error != null) ...[
                            Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : switch (step) {
                                    FirstRunStep.welcome => () => setState(
                                      () => step = FirstRunStep.storeName,
                                    ),
                                    FirstRunStep.storeName => _continueName,
                                    FirstRunStep.ownerPin =>
                                      pin.text.length == 4 &&
                                              confirmation.text.length == 4 &&
                                              pin.text == confirmation.text
                                          ? _createPin
                                          : null,
                                    FirstRunStep.complete => _finish,
                                  },
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    step == FirstRunStep.ownerPin
                                        ? Icons.lock_outline
                                        : Icons.arrow_forward,
                                  ),
                            iconAlignment: IconAlignment.end,
                            label: Text(switch (step) {
                              FirstRunStep.welcome => 'Get Started',
                              FirstRunStep.storeName => 'Continue',
                              FirstRunStep.ownerPin => 'Create PIN',
                              FirstRunStep.complete => 'Go to Dashboard',
                            }),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onPin = step == FirstRunStep.ownerPin;
    return Row(
      children: [
        Expanded(
          child: _stepMarker(context, 'Store Name', onPin ? '✓' : '1', true),
        ),
        Expanded(
          child: Divider(
            color: onPin ? colors.primary : colors.outlineVariant,
            thickness: 2,
          ),
        ),
        Expanded(child: _stepMarker(context, 'Owner PIN', '2', onPin)),
      ],
    );
  }

  Widget _stepMarker(
    BuildContext context,
    String label,
    String symbol,
    bool active,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: active
              ? colors.primary
              : colors.surfaceContainerHighest,
          foregroundColor: active ? colors.onPrimary : colors.onSurfaceVariant,
          child: Text(symbol),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _heading(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _icon(BuildContext context, IconData icon, {double size = 80}) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primaryContainer,
        ),
        child: Icon(icon, size: size * .48, color: colors.onPrimaryContainer),
      ),
    );
  }

  Widget _storefrontBadge(BuildContext context, {double size = 80}) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primaryContainer.withValues(alpha: .5),
        ),
        child: ClipOval(
          child: Image.asset(
            _storefrontAsset,
            fit: BoxFit.cover,
            semanticLabel: 'Sari-sari storefront',
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        const BrandLogo(size: 76),
        const SizedBox(height: 18),
        Text(
          'TindaSari PH',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: colors.primary, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        Text(
          'Sari-Sari Store Management',
          style: TextStyle(color: colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text(
          'Simple. Complete. Made for\nEvery Tindahan.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 30),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: AspectRatio(
              aspectRatio: 1.8,
              child: Image.asset(
                _storefrontAsset,
                fit: BoxFit.cover,
                semanticLabel: 'Sari-sari storefront',
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        for (final benefit in const [
          'Track your sales',
          'Manage inventory',
          'Keep your utangan and more',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: colors.primary, size: 21),
                const SizedBox(width: 12),
                Expanded(child: Text(benefit)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _storeName(BuildContext context) {
    final theme = Theme.of(context);
    final problem = nameSubmitted
        ? SettingsService.validateStoreName(name.text)
        : null;
    return Column(
      children: [
        _storefrontBadge(context, size: 100),
        const SizedBox(height: 24),
        _heading(
          context,
          'Set up your tindahan',
          'Give your store a name. You can change this later in Tindahan Profile.',
        ),
        const SizedBox(height: 30),
        TextField(
          key: const ValueKey('first-run-store-name'),
          controller: name,
          maxLines: 1,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueName(),
          onChanged: (_) => setState(() => error = null),
          decoration: InputDecoration(
            labelText: 'Store Name *',
            hintText: "e.g. Embi's Sari-Sari Store",
            errorText: problem,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${name.text.runes.length}/60',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Image.asset(
                  _lightbulbAsset,
                  fit: BoxFit.cover,
                  semanticLabel: 'Store name ideas',
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Examples:\n• Embi's Store\n• Tindahan ni Maria\n• Juan's Sari-Sari Store",
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ownerPin(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mismatch =
        confirmation.text.length == 4 &&
        pin.text.length == 4 &&
        confirmation.text != pin.text;
    return Column(
      children: [
        _icon(context, Icons.shield_outlined),
        const SizedBox(height: 24),
        _heading(
          context,
          'Create Owner PIN',
          'Protect access to your store management and owner-only features.',
        ),
        const SizedBox(height: 28),
        _pinInput(context, 'Enter 4-digit PIN', pin, pinFocus, false),
        const SizedBox(height: 22),
        _pinInput(
          context,
          'Confirm PIN',
          confirmation,
          confirmationFocus,
          mismatch,
        ),
        if (mismatch) ...[
          const SizedBox(height: 10),
          Text('PINs do not match', style: TextStyle(color: colors.error)),
        ],
      ],
    );
  }

  Widget _pinInput(
    BuildContext context,
    String label,
    TextEditingController controller,
    FocusNode focus,
    bool mismatch,
  ) {
    final colors = Theme.of(context).colorScheme;
    final count = controller.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        SizedBox(
          height: 58,
          child: Stack(
            children: [
              Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                      decoration: BoxDecoration(
                        color: mismatch
                            ? colors.errorContainer.withValues(alpha: .55)
                            : colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: mismatch
                              ? colors.error
                              : count == 4
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          i < count ? Icons.circle : Icons.circle_outlined,
                          size: 15,
                          color: mismatch
                              ? colors.error
                              : i < count
                              ? colors.primary
                              : colors.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Semantics(
                  label: label,
                  child: TextField(
                    key: ValueKey(
                      controller == pin
                          ? 'first-run-owner-pin'
                          : 'first-run-confirm-pin',
                    ),
                    controller: controller,
                    focusNode: focus,
                    keyboardType: TextInputType.number,
                    textInputAction: controller == pin
                        ? TextInputAction.next
                        : TextInputAction.done,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      setState(() => error = null);
                      if (controller == pin && controller.text.length == 4) {
                        confirmationFocus.requestFocus();
                      }
                    },
                    onSubmitted: (_) {
                      if (controller == confirmation) _createPin();
                    },
                    showCursor: false,
                    style: const TextStyle(
                      color: Colors.transparent,
                      fontSize: 1,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      // The app theme fills text fields. This input sits over
                      // the four painted PIN cells, so its fill must stay off.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _complete(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 45),
        _icon(context, Icons.check, size: 112),
        const SizedBox(height: 24),
        _heading(
          context,
          'All Set!',
          'Your store has been created and is now secured with your PIN.',
        ),
        const SizedBox(height: 36),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 92,
                height: 58,
                child: Image.asset(
                  _storefrontAsset,
                  fit: BoxFit.cover,
                  semanticLabel: 'Sari-sari storefront',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name.text.trim(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text('Your tindahan is ready.'),
            ],
          ),
        ),
      ],
    );
  }
}
