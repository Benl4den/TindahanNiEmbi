import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract interface class StorePhotoService {
  Future<String?> chooseFromGallery();
  Future<void> delete(String photoPath);
}

class LocalStorePhotoService implements StorePhotoService {
  LocalStorePhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> chooseFromGallery() async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 75,
      requestFullMetadata: false,
    );
    if (photo == null) return null;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'store_images'));
    await directory.create(recursive: true);
    final extension = path.extension(photo.path).toLowerCase();
    final destination = path.join(
      directory.path,
      'store_${DateTime.now().microsecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}',
    );
    await File(photo.path).copy(destination);
    return destination;
  }

  @override
  Future<void> delete(String photoPath) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = path.join(documents.path, 'store_images');
    // Never delete an arbitrary file if a setting was imported or corrupted.
    if (!path.isWithin(directory, photoPath) ||
        !path.basename(photoPath).startsWith('store_')) {
      return;
    }
    final file = File(photoPath);
    if (await file.exists()) await file.delete();
  }
}
