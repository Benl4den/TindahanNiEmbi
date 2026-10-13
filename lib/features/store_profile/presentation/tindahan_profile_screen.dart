import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/app_refresh_controller.dart';
import '../../../services/settings_service.dart';
import '../../../services/store_photo_service.dart';

const _storefrontAsset = 'assets/branding/tindasari_storefront_clean.png';

class TindahanProfileScreen extends StatefulWidget {
  const TindahanProfileScreen({super.key, required this.settings, this.photos});

  final SettingsService settings;
  final StorePhotoService? photos;

  @override
  State<TindahanProfileScreen> createState() => _TindahanProfileScreenState();
}

class _TindahanProfileScreenState extends State<TindahanProfileScreen> {
  late Future<StoreProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.settings.storeProfile;
  }

  Future<void> _edit(StoreProfile profile) async {
    final saved = await Navigator.of(context).push<StoreProfile>(
      MaterialPageRoute(
        builder: (_) => EditTindahanProfileScreen(
          settings: widget.settings,
          initial: profile,
          photos: widget.photos,
        ),
      ),
    );
    if (mounted && saved != null) {
      setState(() {
        _profile = Future.value(saved);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Tindahan Profile')),
      body: FutureBuilder<StoreProfile>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _profile = widget.settings.storeProfile;
                }),
                child: const Text('Could not load profile. Try again'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
                children: [
                  Center(child: _StorePhoto(path: profile.storePhotoPath)),
                  const SizedBox(height: 15),
                  Text(
                    profile.storeName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Store Information',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _informationRow(
                          Icons.storefront_outlined,
                          'Store Name',
                          profile.storeName,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _informationRow(
                          Icons.person_outline,
                          'Owner Name',
                          profile.ownerName,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _informationRow(
                          Icons.phone_outlined,
                          'Contact Number',
                          profile.contactNumber,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _informationRow(
                          Icons.place_outlined,
                          'Address',
                          profile.address,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: () => _edit(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Tindahan Profile'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _informationRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final isEmpty = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 23),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 3),
                Text(
                  isEmpty ? 'Not set' : value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EditTindahanProfileScreen extends StatefulWidget {
  const EditTindahanProfileScreen({
    super.key,
    required this.settings,
    required this.initial,
    this.photos,
  });

  final SettingsService settings;
  final StoreProfile initial;
  final StorePhotoService? photos;

  @override
  State<EditTindahanProfileScreen> createState() =>
      _EditTindahanProfileScreenState();
}

class _EditTindahanProfileScreenState extends State<EditTindahanProfileScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.storeName,
  );
  late final TextEditingController _owner = TextEditingController(
    text: widget.initial.ownerName,
  );
  late final TextEditingController _contact = TextEditingController(
    text: widget.initial.contactNumber,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initial.address,
  );
  late final StorePhotoService _photos =
      widget.photos ?? LocalStorePhotoService();
  late String _photoPath = widget.initial.storePhotoPath;
  String? _pendingPhotoPath;
  bool _submitted = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _contact.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _discardPendingPhoto() async {
    final path = _pendingPhotoPath;
    _pendingPhotoPath = null;
    if (path != null) {
      try {
        await _photos.delete(path);
      } catch (_) {
        // Photo cleanup must not trap the user on this screen.
      }
    }
  }

  Future<void> _cancel() async {
    if (_saving) return;
    await _discardPendingPhoto();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _choosePhoto() async {
    try {
      final selected = await _photos.chooseFromGallery();
      if (selected == null) return;
      if (!mounted) {
        await _photos.delete(selected);
        return;
      }
      await _discardPendingPhoto();
      setState(() {
        _photoPath = selected;
        _pendingPhotoPath = selected;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not use that photo. Try again.');
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (SettingsService.validateStoreName(_name.text) != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.settings.saveStoreProfile(
        StoreProfile(
          storeName: _name.text,
          ownerName: _owner.text,
          contactNumber: _contact.text,
          address: _address.text,
          storePhotoPath: _photoPath,
        ),
      );
      _pendingPhotoPath = null;
      if (widget.initial.storePhotoPath.isNotEmpty &&
          widget.initial.storePhotoPath != saved.storePhotoPath) {
        try {
          await _photos.delete(widget.initial.storePhotoPath);
        } catch (_) {
          // A saved profile remains valid even if old-photo cleanup fails.
        }
      }
      AppRefreshController.instance.dataChanged();
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save store details. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nameProblem = _submitted
        ? SettingsService.validateStoreName(_name.text)
        : null;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _saving ? null : _cancel,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Edit Tindahan Profile'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    children: [
                      Center(
                        child: InkWell(
                          key: const ValueKey('change-store-photo'),
                          onTap: _saving ? null : _choosePhoto,
                          borderRadius: BorderRadius.circular(90),
                          child: _StorePhoto(path: _photoPath),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to change store photo',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      _fieldLabel('Store Name *'),
                      TextField(
                        key: const ValueKey('profile-store-name'),
                        controller: _name,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: InputDecoration(
                          hintText: "e.g. Embi's Sari-Sari Store",
                          counterText: '',
                          errorText: nameProblem,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_name.text.runes.length}/60',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 15),
                      _fieldLabel('Owner Name'),
                      TextField(
                        key: const ValueKey('profile-owner-name'),
                        controller: _owner,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Juan Dela Cruz',
                        ),
                      ),
                      const SizedBox(height: 17),
                      _fieldLabel('Contact Number'),
                      TextField(
                        key: const ValueKey('profile-contact-number'),
                        controller: _contact,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 09XX XXX XXXX',
                        ),
                      ),
                      const SizedBox(height: 17),
                      _fieldLabel('Address'),
                      TextField(
                        key: const ValueKey('profile-address'),
                        controller: _address,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Purok 1, Barangay, City',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: TextStyle(color: colors.error)),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: _saving ? null : _cancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _StorePhoto extends StatelessWidget {
  const _StorePhoto({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget fallback() => Image.asset(
      _storefrontAsset,
      fit: BoxFit.cover,
      semanticLabel: 'Sari-sari storefront',
    );
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: ColoredBox(
                color: colors.primaryContainer.withValues(alpha: .55),
                child: path.isEmpty
                    ? fallback()
                    : Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback(),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 3,
            bottom: 7,
            child: Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.surface, width: 2),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 21,
                color: colors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
