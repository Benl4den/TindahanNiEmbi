import 'package:flutter/material.dart';

import '../../../services/backup_service.dart';
import '../../../services/storage_management_service.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({
    super.key,
    required this.storage,
    required this.backups,
  });
  final StorageManagementService storage;
  final BackupService backups;
  @override
  State<StorageManagementScreen> createState() => _State();
}

class _State extends State<StorageManagementScreen> {
  late Future<StorageSummary> data;
  String? message;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.storage.summary();
  String size(int? bytes) => bytes == null
      ? 'Unavailable'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : bytes < 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  Future<void> clean() async {
    try {
      final count = await widget.storage.cleanOrphanedImages();
      if (mounted) {
        setState(() {
          message = '$count unreferenced image(s) removed.';
          reload();
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not clean images safely.');
    }
  }

  Future<void> manageBackups() async {
    final files = await widget.backups.localBackups();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Manage Local Backups'),
        content: SizedBox(
          width: 620,
          child: files.isEmpty
              ? const Text('No local backups.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(files[i].path.split('/').last),
                    subtitle: Text(size(files[i].lengthSync())),
                    trailing: i == 0
                        ? const Chip(label: Text('Newest'))
                        : IconButton(
                            tooltip: 'Delete old backup',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: dialog,
                                builder: (confirm) => AlertDialog(
                                  title: const Text('Delete this old backup?'),
                                  content: Text(files[i].path.split('/').last),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirm, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirm, true),
                                      child: const Text('Delete Backup'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              await widget.storage.deleteOldBackup(files[i]);
                              if (dialog.mounted) Navigator.pop(dialog);
                              if (mounted) setState(reload);
                            },
                          ),
                  ),
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage Management')),
    body: FutureBuilder<StorageSummary>(
      future: data,
      builder: (_, s) {
        if (s.hasError) {
          return const Center(
            child: Text(
              'Could not read storage information. Your business data was not changed.',
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final x = s.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.storage, size: 38),
                title: Text(
                  x.status,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                subtitle: Text('Tablet Free Space: ${size(x.freeBytes)}'),
              ),
            ),
            _row('SQLite Database', size(x.databaseBytes)),
            _row('Product Images', size(x.imageBytes)),
            _row(
              'Local Backups',
              '${size(x.backupBytes)} • ${x.backupCount} file(s)',
            ),
            _row('Unreferenced Images', '${x.orphanImageCount}'),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: manageBackups,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Manage Backups'),
                ),
                OutlinedButton.icon(
                  onPressed: x.orphanImageCount == 0 ? null : clean,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Clean Unreferenced Images'),
                ),
              ],
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(message!),
              ),
            const SizedBox(height: 20),
            const Text(
              'Sales, credit accounts, payments, inventory movements, and other business history are never removed here.',
            ),
          ],
        );
      },
    ),
  );
  Widget _row(String label, String value) => Card(
    child: ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );
}
