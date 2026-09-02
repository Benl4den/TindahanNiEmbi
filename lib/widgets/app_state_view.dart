import 'package:flutter/material.dart';

/// Consistent, friendly feedback for loading, empty, error, and denied states.
class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  const AppStateView.empty({
    Key? key,
    required String title,
    String? message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
         key: key,
         icon: Icons.inbox_outlined,
         title: title,
         message: message,
         actionLabel: actionLabel,
         onAction: onAction,
       );

  const AppStateView.error({
    Key? key,
    String title = 'Something went wrong',
    String? message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
         key: key,
         icon: Icons.error_outline,
         title: title,
         message: message,
         actionLabel: actionLabel,
         onAction: onAction,
         iconColor: const Color(0xFFBA1A1A),
       );

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: (iconColor ?? colors.primary).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 36, color: iconColor ?? colors.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 16),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}
