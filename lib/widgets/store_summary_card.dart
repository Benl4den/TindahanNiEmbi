import 'package:flutter/material.dart';

/// Compact, responsive summary treatment shared by the owner overview screens.
class StoreSummaryCard extends StatelessWidget {
  const StoreSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.caption,
  });
  final String title, value;
  final String? caption;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark
            ? theme.colorScheme.surfaceContainer
            : Color.alphaBlend(
                accent.withValues(alpha: .035),
                theme.colorScheme.surface,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark
              ? theme.colorScheme.outlineVariant
              : accent.withValues(alpha: .16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? .16 : .10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                if (value.isNotEmpty)
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (caption != null)
                  Text(caption!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StoreSummaryHero extends StatelessWidget {
  const StoreSummaryHero({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    this.footer,
  });
  final String title, value, caption;
  final IconData icon;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFD9F3DE),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: const Color(0xFF0F6B46), size: 34),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                caption,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFE1F1E8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF203A2D), const Color(0xFF243B36)]
              : [const Color(0xFF086339), const Color(0xFF329C90)],
        ),
      ),
      child: LayoutBuilder(
        builder: (_, box) {
          if (footer != null && box.maxWidth >= 800) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: summary),
                const SizedBox(width: 24),
                Container(width: 1, height: 86, color: const Color(0xFF85B9A2)),
                const SizedBox(width: 24),
                SizedBox(width: 440, child: footer!),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              summary,
              if (footer != null) ...[const SizedBox(height: 16), footer!],
            ],
          );
        },
      ),
    );
  }
}
