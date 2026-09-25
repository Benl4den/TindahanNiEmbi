import 'package:flutter/material.dart';

/// Shared, data-free preview for modules unavailable on the current plan.
class ProFeaturePreview extends StatelessWidget {
  const ProFeaturePreview({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.workspace_premium_outlined,
    this.leading,
    this.metrics = const [],
    this.benefits = const [],
  });

  final String title, description;
  final IconData icon;
  final Widget? leading;
  final List<String> metrics, benefits;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = dark ? const Color(0xFFFFCC63) : const Color(0xFF805300);
    final panel = Color.alphaBlend(
      colors.primary.withValues(alpha: dark ? .10 : .075),
      colors.surface,
    );
    final metricSurface = dark ? colors.surfaceContainerLow : colors.surface;
    final metricBorder = dark
        ? colors.outlineVariant
        : Color.alphaBlend(
            colors.primary.withValues(alpha: .18),
            colors.outlineVariant,
          );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: colors.primary.withValues(alpha: .17),
                      child:
                          leading ??
                          Icon(icon, color: colors.primary, size: 29),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFFFFCA5C)
                            : const Color(0xFFFFD879),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'PRO FEATURE',
                        style: TextStyle(
                          color: Color(0xFF312100),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                Text(description, style: Theme.of(context).textTheme.bodyLarge),
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, space) {
                      const gap = 12.0;
                      final columns = metrics.length == 4
                          ? (space.maxWidth >= 760
                                ? 4
                                : space.maxWidth >= 420
                                ? 2
                                : 1)
                          : (space.maxWidth >= 660 ? 3 : 1);
                      final cardWidth =
                          (space.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: cardWidth,
                              child: Container(
                                height:
                                    104 *
                                    MediaQuery.textScalerOf(context).scale(1),
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: metricSurface,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: metricBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      metric,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.lock_outline,
                                          size: 20,
                                          color: gold,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          '--',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (benefits.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  for (final benefit in benefits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(Icons.check, color: colors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(benefit)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Preview Pro'),
                        content: const Text(
                          'Pro subscriptions are not available yet. Your existing records stay safely on this device.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Got it'),
                          ),
                        ],
                      ),
                    ),
                    child: const Row(
                      children: [
                        Spacer(),
                        Icon(Icons.workspace_premium_outlined),
                        SizedBox(width: 9),
                        Text('Preview Pro'),
                        Spacer(),
                        Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
