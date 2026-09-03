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
    appBar: AppBar(title: const Text('Activity Logs')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Today'),
                selected: DateUtils.isSameDay(date, DateTime.now()),
                onSelected: (_) => select(DateTime.now()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSearchField(
                  hintText: 'Search activity...',
                  onChanged: (v) => setState(() {
                    query = v;
                    reload();
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children:
                      [
                            'All',
                            'Sales',
                            'UTANG',
                            'Inventory',
                            'Security',
                            'Backup',
                          ]
                          .map(
                            (x) => ChoiceChip(
                              label: Text(x),
                              selected: category == x,
                              onSelected: (_) => setState(() {
                                category = x;
                                reload();
                              }),
                            ),
                          )
                          .toList(),
                ),
              ),
              ChoiceChip(
                label: const Text('Yesterday'),
                selected: DateUtils.isSameDay(
                  date,
                  DateTime.now().subtract(const Duration(days: 1)),
                ),
                onSelected: (_) =>
                    select(DateTime.now().subtract(const Duration(days: 1))),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDate: date,
                  );
                  if (d != null) select(d);
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text('Select Date'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              MaterialLocalizations.of(context).formatFullDate(date),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ActivityLog>>(
            future: logs,
            builder: (_, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return const Center(child: Text('No activity for this date.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: s.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final x = s.data![i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(child: Icon(Icons.history)),
                      title: Text(x.description),
                      subtitle: Text(
                        x.actorRole == null ? 'System' : _role(x.actorRole!),
                      ),
                      trailing: Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(x.createdAt.toLocal()),
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
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
  String _role(String role) => role == 'OWNER' ? 'Owner' : 'Staff';
}
