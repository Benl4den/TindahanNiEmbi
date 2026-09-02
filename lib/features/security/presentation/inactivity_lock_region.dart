import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/settings_service.dart';

class InactivityLockRegion extends StatefulWidget {
  const InactivityLockRegion({
    super.key,
    this.settings,
    this.loadMinutes,
    required this.onTimeout,
    required this.child,
  }) : assert(settings != null || loadMinutes != null);
  final SettingsService? settings;
  final Future<int> Function()? loadMinutes;
  final VoidCallback onTimeout;
  final Widget child;
  @override
  State<InactivityLockRegion> createState() => _State();
}

class _State extends State<InactivityLockRegion> {
  Timer? timer;
  StreamSubscription<int>? subscription;
  int minutes = 0;
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.settings != null) {
      subscription = widget.settings!.autoLockChanges.listen((value) {
        minutes = value;
        _reset();
      });
    }
  }

  Future<void> _load() async {
    minutes =
        await (widget.loadMinutes?.call() ?? widget.settings!.autoLockMinutes);
    _reset();
  }

  void _reset() {
    timer?.cancel();
    if (minutes > 0) {
      timer = Timer(Duration(minutes: minutes), widget.onTimeout);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _reset(),
    behavior: HitTestBehavior.translucent,
    child: widget.child,
  );
}
