import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/backup_service.dart';

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
              ? 'Backup created and validated in local app storage.'
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
        title: const Text('Restore this backup?'),
        content: const Text('The current data will be replaced.'),
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
      widget.onRestored();
      setState(() => status = 'Backup restored.');
    } catch (_) {
      setState(() => status = 'The backup is invalid or damaged.');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & Restore')),
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
                      child: Text(
                        value == null
                            ? 'Checking backup health…'
                            : 'Backup Health: ${value.status}\n'
                                  'Last Successful Backup: ${value.createdAt?.toString() ?? 'None'}\n'
                                  'File Size: ${_size(value.fileSizeBytes)}\n'
                                  'Database: ${value.valid ? 'Included • Schema V${value.schemaVersion}' : 'Not validated'}\n'
                                  'Product Images: ${value.valid ? '${value.imageCount} included' : 'Not validated'}\n'
                                  'Validation: ${value.valid ? 'Valid' : 'Needs Backup'}',
                        style: Theme.of(context).textTheme.titleMedium,
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
}
