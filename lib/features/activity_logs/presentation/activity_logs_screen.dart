import 'package:flutter/material.dart';

import '../../../models/activity_log.dart';
import '../../../repositories/activity_log_repository.dart';
import '../../../widgets/app_search_field.dart';

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key, required this.repository});
  final ActivityLogRepository repository;
  @override
  State<ActivityLogsScreen> createState() => _State();
}

class _State extends State<ActivityLogsScreen> {
  DateTime date = DateTime.now();
  String query = '', category = 'All';
  late Future<List<ActivityLog>> logs;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => logs = widget.repository.forDate(
    date,
    category: category == 'All'
        ? null
        : category == 'UTANG'
        ? 'UTANG'
        : category.toUpperCase(),
    query: query,
  );
  void select(DateTime value) => setState(() {
    date = value;
    reload();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity Log'),
          Text(
            'A trace of important store actions',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (_, box) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: box.maxWidth >= 700
                          ? box.maxWidth - 360
                          : box.maxWidth,
                      child: AppSearchField(
                        hintText: 'Search actions, products, or people...',
                        onChanged: (v) => setState(() {
                          query = v;
                          reload();
                        }),
                      ),
                    ),
                    _dateButton('Today', DateTime.now(), Icons.today_outlined),
                    _dateButton(
                      'Yesterday',
                      DateTime.now().subtract(const Duration(days: 1)),
                      Icons.history_outlined,
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Choose Date'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in const [
                      ('All', Icons.apps_outlined),
                      ('Sales', Icons.point_of_sale_outlined),
                      ('UTANG', Icons.people_alt_outlined),
                      ('Inventory', Icons.inventory_2_outlined),
                      ('Security', Icons.security_outlined),
                      ('Backup', Icons.backup_outlined),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          height: 40,
                          child: ChoiceChip(
                            avatar: Icon(item.$2, size: 18),
                            label: Text(item.$1),
                            selected: category == item.$1,
                            onSelected: (_) => setState(() {
                              category = item.$1;
                              reload();
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_note_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      MaterialLocalizations.of(context).formatFullDate(date),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      category == 'All'
                          ? 'All recorded activity'
                          : '$category activity',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ActivityLog>>(
            future: logs,
            builder: (_, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = s.data!;
              if (entries.isEmpty) {
                return const Center(child: Text('No matching activity.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final x = entries[i], color = _color(x.eventType);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: .12),
                            foregroundColor: color,
                            child: Icon(_icon(x.eventType)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: .1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _eventLabel(x.eventType),
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      MaterialLocalizations.of(context)
                                          .formatTimeOfDay(
                                            TimeOfDay.fromDateTime(
                                              x.createdAt.toLocal(),
                                            ),
                                          ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  x.description,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Performed by ${x.actorRole == null ? 'System' : _role(x.actorRole!)}${x.relatedEntityType == null ? '' : ' • ${x.relatedEntityType} record'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _dateButton(String label, DateTime value, IconData icon) =>
      OutlinedButton.icon(
        onPressed: () => select(value),
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: DateUtils.isSameDay(date, value)
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
      );

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: date,
    );
    if (selected != null) select(selected);
  }

  IconData _icon(String type) {
    if (type.startsWith('UTANG') || type.contains('PAYMENT')) {
      return Icons.people_alt_outlined;
    }
    if (type.contains('SALE')) return Icons.point_of_sale_outlined;
    if (type.contains('INVENTORY') || type.contains('STOCK')) {
      return Icons.inventory_2_outlined;
    }
    if (type.contains('SECURITY') || type.contains('PIN')) {
      return Icons.security_outlined;
    }
    if (type.contains('BACKUP')) return Icons.backup_outlined;
    return Icons.history;
  }

  Color _color(String type) {
    if (type.startsWith('UTANG') || type.contains('PAYMENT')) {
      return Colors.orange.shade800;
    }
    if (type.contains('SALE')) return Colors.green.shade800;
    if (type.contains('INVENTORY') || type.contains('STOCK')) {
      return Colors.blue.shade800;
    }
    if (type.contains('SECURITY') || type.contains('PIN')) {
      return Colors.purple.shade700;
    }
    return Colors.blueGrey.shade700;
  }

  String _eventLabel(String type) => type
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  String _role(String role) => role == 'OWNER' ? 'Owner' : 'Staff';
}
