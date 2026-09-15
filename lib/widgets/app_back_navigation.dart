import 'package:flutter/material.dart';

Future<bool> confirmLeavingPage(
  BuildContext context, {
  String title = 'Discard changes?',
  String message = 'Your changes have not been saved.',
  String actionLabel = 'Discard',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    ) ==
    true;

/// Protects an editable route, including dismissals of modal forms.
class PageBackGuard extends StatefulWidget {
  const PageBackGuard({
    super.key,
    required this.child,
    this.controllers = const [],
    this.changeToken,
    this.hasUnsavedChanges = false,
    this.busy = false,
    this.title = 'Discard changes?',
    this.message = 'Your changes have not been saved.',
    this.actionLabel = 'Discard',
    this.beforeLeave,
    this.onBack,
  });

  final Widget child;
  final List<TextEditingController> controllers;
  final Object? changeToken;
  final bool hasUnsavedChanges;
  final bool busy;
  final String title, message, actionLabel;
  final Future<void> Function()? beforeLeave;
  final Future<bool> Function()? onBack;

  @override
  State<PageBackGuard> createState() => _PageBackGuardState();
}

class _PageBackGuardState extends State<PageBackGuard> {
  late final List<String> _initialText;
  late final Object? _initialToken;
  bool _handlingBack = false;

  @override
  void initState() {
    super.initState();
    _initialText = [
      for (final controller in widget.controllers) controller.text,
    ];
    _initialToken = widget.changeToken;
    for (final controller in widget.controllers) {
      controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.removeListener(_changed);
    }
    super.dispose();
  }

  bool get _dirty =>
      widget.hasUnsavedChanges ||
      widget.changeToken != _initialToken ||
      Iterable<int>.generate(widget.controllers.length)
          .any((i) => widget.controllers[i].text != _initialText[i]);

  Future<void> _back() async {
    if (_handlingBack || widget.busy) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusScope.of(context).unfocus();
      return;
    }
    _handlingBack = true;
    try {
      if (await widget.onBack?.call() == true || !mounted) return;
      final leave =
          !_dirty ||
          await confirmLeavingPage(
            context,
            title: widget.title,
            message: widget.message,
            actionLabel: widget.actionLabel,
          );
      if (!leave || !mounted || widget.busy) return;
      await widget.beforeLeave?.call();
      if (mounted && !widget.busy) Navigator.pop(context);
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop:
        !widget.busy &&
        !_dirty &&
        widget.onBack == null &&
        MediaQuery.viewInsetsOf(context).bottom == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: widget.child,
  );
}

/// Embedded sections have no route to pop, so the shell delegates Back here.
class SectionBackController {
  final _handlers = <Object, Future<bool> Function()>{};

  void register(Object owner, Future<bool> Function() handler) {
    _handlers[owner] = handler;
  }

  void unregister(Object owner) => _handlers.remove(owner);

  Future<bool> handleBack() async {
    for (final handler in _handlers.values.toList().reversed) {
      if (await handler()) return true;
    }
    return false;
  }
}

class SectionBackScope extends InheritedWidget {
  const SectionBackScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SectionBackController controller;

  static SectionBackController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SectionBackScope>()
      ?.controller;

  @override
  bool updateShouldNotify(SectionBackScope oldWidget) =>
      controller != oldWidget.controller;
}

class SectionBackHandler extends StatefulWidget {
  const SectionBackHandler({
    super.key,
    required this.onBack,
    required this.child,
  });

  final Future<bool> Function() onBack;
  final Widget child;

  @override
  State<SectionBackHandler> createState() => _SectionBackHandlerState();
}

class _SectionBackHandlerState extends State<SectionBackHandler> {
  SectionBackController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller?.unregister(this);
    _controller = SectionBackScope.maybeOf(context);
    _controller?.register(this, () => widget.onBack());
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
