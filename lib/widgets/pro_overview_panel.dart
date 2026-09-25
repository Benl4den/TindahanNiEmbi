import 'package:flutter/material.dart';

class ProOverviewMetric {
  const ProOverviewMetric(this.label, this.value, this.icon, this.accent);
  final String label, value;
  final IconData icon;
  final Color accent;
}

/// A shared themed summary for the three specialist Pro modules.
class ProOverviewPanel extends StatelessWidget {
  const ProOverviewPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metrics,
  });

  final String title, subtitle;
  final List<ProOverviewMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: .055),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, space) {
              const gap = 10.0;
              final columns = space.maxWidth >= 630 ? 3 : 1;
              final width = (space.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 90),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: dark
                              ? colors.surfaceContainerLow
                              : colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: dark
                                ? colors.outlineVariant
                                : Color.alphaBlend(
                                    colors.primary.withValues(alpha: .16),
                                    colors.outlineVariant,
                                  ),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: metric.accent.withValues(
                                alpha: .13,
                              ),
                              child: Icon(
                                metric.icon,
                                color: metric.accent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metric.label,
                                    maxLines: 2,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    metric.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: metric.accent,
                                        ),
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}
