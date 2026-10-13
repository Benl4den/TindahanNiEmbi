import 'package:flutter/material.dart';

import '../../../services/data_integrity_service.dart';

class IntegrityScreen extends StatefulWidget {
  const IntegrityScreen({super.key, required this.service});
  final DataIntegrityService service;
  @override
  State<IntegrityScreen> createState() => _State();
}

class _State extends State<IntegrityScreen> {
  IntegrityResult? result;
  bool checking = false;
  Future<void> check() async {
    setState(() => checking = true);
    try {
      final r = await widget.service.check();
      if (mounted) {
        setState(() {
          result = r;
          checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => checking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not complete the integrity check. No data was changed.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        MediaQuery.sizeOf(context).width < 360
            ? 'Store Records'
            : 'Check Store Records',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          ),
          children: [
            const Center(child: Icon(Icons.verified_user_outlined, size: 72)),
            const SizedBox(height: 16),
            const Text(
              'Read-only checks. No financial or inventory data will be changed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: checking ? null : check,
              icon: const Icon(Icons.fact_check),
              label: const Text('Check Store Records'),
            ),
            if (result != null) ...[
              const SizedBox(height: 24),
              Text(
                result!.healthy ? 'All checks passed' : 'Problems found',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              ...result!.sections.map(
                (section) => ExpansionTile(
                  initiallyExpanded: !section.healthy,
                  leading: Icon(
                    section.healthy ? Icons.check_circle : Icons.warning_amber,
                    color: section.healthy
                        ? Colors.green
                        : Colors.orange.shade800,
                  ),
                  title: Text(section.name),
                  subtitle: Text(
                    section.healthy
                        ? 'Healthy'
                        : '${section.problems.length} issue(s)',
                  ),
                  children: section.problems
                      .map((problem) => ListTile(title: Text(problem)))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
