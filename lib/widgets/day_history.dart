import 'package:flutter/material.dart';

/// Compact history with independent, persistent expansion for each local day.
class DayHistory<T> extends StatelessWidget {
  const DayHistory({
    super.key,
    required this.items,
    required this.date,
    required this.itemBuilder,
    required this.storageKey,
  });
  final List<T> items;
  final DateTime Function(T) date;
  final Widget Function(T) itemBuilder;
  final String storageKey;
  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<T>>{};
    for (final item in items) {
      final local = date(item).toLocal();
      groups
          .putIfAbsent(DateTime(local.year, local.month, local.day), () => [])
          .add(item);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      children: [
        for (final day in days)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey('$storageKey-$day'),
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                MaterialLocalizations.of(context).formatMediumDate(day),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${groups[day]!.length} transactions • Tap to expand',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: groups[day]!.map(itemBuilder).toList(),
            ),
          ),
      ],
    );
  }
}
