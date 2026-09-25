import 'package:flutter/material.dart';

import 'daily_closing_overview.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';
import '../../../services/app_refresh_controller.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class DailyClosingScreen extends StatefulWidget {
  const DailyClosingScreen({
    super.key,
    required this.repository,
    this.walletServicesAllowed = true,
  });
  final OperationsRepository repository;
  final bool walletServicesAllowed;
  @override
  State<DailyClosingScreen> createState() => _State();
}

class _State extends State<DailyClosingScreen> {
  DateTime date = DateTime.now();
  late Future<DailyClosingSummary> data;
  late Future<List<DateTime>> history;
  @override
  void initState() {
    super.initState();
    reload();
    AppRefreshController.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(reload);
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_refresh);
    super.dispose();
  }

  void reload() {
    data = widget.repository.summaryForDate(date);
    history = widget.repository.closingDates();
  }

  Future<void> pick() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: date,
    );
    if (d != null) {
      setState(() {
        date = d;
        reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily Closing Summary'),
      actions: [
        const HelpButton(topic: HelpTopicId.dailyClosing),
        TextButton.icon(
          onPressed: _confirmCloseDay,
          icon: const Icon(Icons.lock_clock_outlined),
          label: const Text('Close Day'),
        ),
        TextButton.icon(
          onPressed: pick,
          icon: const Icon(Icons.calendar_month),
          label: Text('${date.month}/${date.day}/${date.year}'),
        ),
      ],
    ),
    body: FutureBuilder<DailyClosingSummary>(
      future: data,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(reload),
              child: const Text('Could not load this day. Try again'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final x = s.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              MaterialLocalizations.of(context).formatFullDate(date),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            FutureBuilder<DailyClosingSnapshot?>(
              future: widget.repository.snapshotFor(date),
              builder: (_, snapshot) => Text(
                snapshot.data == null
                    ? 'Live transaction summary. It does not compare your actual cash count.'
                    : 'Saved Daily Closing — ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(snapshot.data!.closedAt))}. Later changes stay in transaction history.',
              ),
            ),
            const SizedBox(height: 16),
            DailyClosingOverview(
              summary: x,
              walletServicesAllowed: widget.walletServicesAllowed,
            ),
            const Divider(height: 40),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'DAILY CLOSING HISTORY',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: pick,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Choose date'),
                ),
              ],
            ),
            FutureBuilder<List<DateTime>>(
              future: history,
              builder: (_, h) => h.hasError
                  ? TextButton(
                      onPressed: () => setState(reload),
                      child: const Text('Could not load history. Try again'),
                    )
                  : !h.hasData
                  ? const LinearProgressIndicator()
                  : Column(
                      children: [
                        if (!h.data!.any(
                          (d) =>
                              d.year != DateTime.now().year ||
                              d.month != DateTime.now().month ||
                              d.day != DateTime.now().day,
                        ))
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No previous daily summaries yet. Use Choose date to review a specific day.',
                            ),
                          ),
                        ...h.data!
                            .where(
                              (d) =>
                                  !(d.year == DateTime.now().year &&
                                      d.month == DateTime.now().month &&
                                      d.day == DateTime.now().day),
                            )
                            .take(5)
                            .map(
                              (d) => Card(
                                child: ListTile(
                                  title: Text(
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(d),
                                  ),
                                  subtitle: FutureBuilder<DailyClosingSummary>(
                                    future: widget.repository.summaryForDate(d),
                                    builder: (_, day) => Text(
                                      day.hasData
                                          ? '${day.data!.transactionCount} transactions • Net Recorded Cash: ${standardMoney(day.data!.netRecordedCash)}'
                                          : 'Open daily summary',
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showDay(d),
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _confirmCloseDay() async {
    final closingDate = date;
    final displayed = data;
    final saved = await widget.repository.snapshotFor(closingDate);
    if (!mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This day is already closed and read-only.'),
        ),
      );
      return;
    }
    DailyClosingSummary expected;
    try {
      expected = await displayed;
    } catch (_) {
      if (mounted) setState(reload);
      return;
    }
    if (!mounted || closingDate != date) return;
    final today = DateTime.now();
    final isToday =
        closingDate.year == today.year &&
        closingDate.month == today.month &&
        closingDate.day == today.day;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined),
        title: const Text('Close this day?'),
        content: Text(
          'This saves the full Daily Closing summary as a read-only record, including all posted cash and wallet movements. Later cancellations or fixes remain visible in transaction history, but will not change this closed record.${isToday ? ' You are closing today before midnight. Any sales or expenses entered later today will not appear in this saved closing. Finish today’s entries first.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close Day'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || closingDate != date) return;
    try {
      await widget.repository.closeDay(closingDate, expectedSummary: expected);
    } catch (_) {
      if (!mounted) return;
      setState(reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Daily Closing changed or could not be saved. Review the refreshed summary and try again.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(reload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Daily Closing saved as a read-only snapshot.'),
      ),
    );
  }

  Future<void> _showDay(DateTime day) async {
    final snapshot = await widget.repository.snapshotFor(day);
    final summary = snapshot?.summary ?? await widget.repository.daily(day);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: CircleAvatar(
          radius: 26,
          backgroundColor: Theme.of(c).colorScheme.primaryContainer,
          child: Icon(
            Icons.calendar_month_outlined,
            color: Theme.of(c).colorScheme.primary,
          ),
        ),
        title: Text(
          MaterialLocalizations.of(c).formatFullDate(day),
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  snapshot == null
                      ? 'Live transaction summary'
                      : 'Saved Daily Closing • ${MaterialLocalizations.of(c).formatTimeOfDay(TimeOfDay.fromDateTime(snapshot.closedAt))}',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DailyClosingOverview(
                  summary: summary,
                  walletServicesAllowed: widget.walletServicesAllowed,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
