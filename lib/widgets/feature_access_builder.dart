import 'package:flutter/material.dart';

import '../services/feature_access_service.dart';

/// Loads the plan once, then rebuilds immediately when the debug plan changes.
class FeatureAccessBuilder extends StatefulWidget {
  const FeatureAccessBuilder({
    super.key,
    required this.access,
    required this.feature,
    required this.builder,
  });

  final FeatureAccessService access;
  final ProFeature feature;
  final Widget Function(BuildContext context, bool allowed) builder;

  @override
  State<FeatureAccessBuilder> createState() => _FeatureAccessBuilderState();
}

class _FeatureAccessBuilderState extends State<FeatureAccessBuilder> {
  late Future<AppPlan> _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = widget.access.currentPlan();
    widget.access.planController.addListener(_planChanged);
  }

  @override
  void didUpdateWidget(covariant FeatureAccessBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access.planController != widget.access.planController) {
      oldWidget.access.planController.removeListener(_planChanged);
      _loaded = widget.access.currentPlan();
      widget.access.planController.addListener(_planChanged);
    }
  }

  void _planChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.access.planController.removeListener(_planChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppPlan>(
    future: _loaded,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Could not check plan access. Reopen this section.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.builder(
        context,
        widget.access.allowsCurrent(widget.feature),
      );
    },
  );
}
