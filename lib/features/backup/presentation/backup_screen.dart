import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/backup_service.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.service,
    required this.onRestored,
  });
  final BackupService service;
  final VoidCallback onRestored;
  @override
  State<BackupScreen> createState() => _State();
}

class _State extends State<BackupScreen> {
  bool busy = false;
  String? status;
  late Future<BackupHealth> backupHealth;
  @override
  void initState() {
    super.initState();
    backupHealth = widget.service.health();
  }

  Future<void> backup() async {
    setState(() => busy = true);
    try {
      final generated = await widget.service.create();
      final save = await FilePicker.saveFile(
        dialogTitle: 'Create Backup',
        fileName: 'TindahanNiEmbi.tnebackup.zip',
        bytes: await File(generated).readAsBytes(),
      );
      if (mounted) {
        setState(() {
          status = save == null
              ? 'Backup saved on this tablet. Save another copy somewhere safe.'
              : 'Backup created and validated: $save';
          backupHealth = widget.service.health();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Backup could not be created or validated.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked?.path == null) return;
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(c).colorScheme.error,
        ),
        title: const Text('Restore this backup?'),
        content: const Text(
          'This replaces the current store records and product images with the selected backup. Create a new backup first if you may need the current data later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => busy = true);
    try {
      await widget.service.restore(picked!.path!);
      if (!mounted) return;
      widget.onRestored();
      setState(() => status = 'Backup restored.');
    } catch (_) {
      if (mounted) {
        setState(() => status = 'The backup is invalid or damaged.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Backup & Restore'),
      actions: const [HelpButton(topic: HelpTopicId.backupRestore)],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<BackupHealth>(
                future: backupHealth,
                builder: (_, snapshot) {
                  final value = snapshot.data;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: value == null
                          ? const Text('Checking backup health…')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value.status,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Last successful backup: ${value.createdAt == null ? 'None yet' : _when(value.createdAt!)}',
                                ),
                                if (value.status != 'Recent') ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Your backup is getting old. Save a new copy.',
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  'File size: ${_size(value.fileSizeBytes)}',
                                ),
                                Text(
                                  'Store Records: ${value.valid ? 'Included and checked' : 'Not checked'}',
                                ),
                                Text(
                                  'Product images: ${value.valid ? '${value.imageCount} included' : 'Not validated'}',
                                ),
                                Text(
                                  'Validation: ${value.valid ? 'Valid' : 'Needs Backup'}',
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'For safer recovery, copy the saved backup to another device or cloud storage.',
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy ? null : backup,
                icon: const Icon(Icons.backup),
                label: const Text('Backup Now'),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: busy ? null : restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore Backup'),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(status!),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _when(DateTime value) =>
      '${MaterialLocalizations.of(context).formatMediumDate(value)} • ${TimeOfDay.fromDateTime(value).format(context)}';
}
