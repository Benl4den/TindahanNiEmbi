import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

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
    if (busy) return;
    setState(() => busy = true);
    try {
      final generated = await widget.service.create();
      if (!mounted) return;
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
    if (busy) return;
    setState(() => busy = true);
    Directory? selectedCopy;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked == null) return;
      if (!mounted) return;
      // Android document providers may supply a content URI without a local
      // path. Keep our own copy until validation and restore finish.
      selectedCopy = await Directory.systemTemp.createTemp('tindahan_import_');
      final selectedFile = File(path.join(selectedCopy.path, 'selected.zip'));
      await picked.readAsByteStream().cast<List<int>>().pipe(
        selectedFile.openWrite(),
      );
      await widget.service.validate(selectedFile.path);
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
      if (yes != true || !mounted) return;
      await widget.service.restore(selectedFile.path);
      if (!mounted) return;
      widget.onRestored();
      if (mounted) setState(() => status = 'Backup restored.');
    } on InvalidBackupException catch (error) {
      if (mounted) {
        setState(
          () => status = 'Restore could not be completed: ${error.message}.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Restore could not be completed: $error');
      }
    } finally {
      if (selectedCopy != null && await selectedCopy.exists()) {
        await selectedCopy.delete(recursive: true);
      }
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<BackupHealth>(
                future: backupHealth,
                builder: (_, snapshot) {
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(
                        () => backupHealth = widget.service.health(),
                      ),
                      child: const Text(
                        'Could not check backup health. Try again',
                      ),
                    );
                  }
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
