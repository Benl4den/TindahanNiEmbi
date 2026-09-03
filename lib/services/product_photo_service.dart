import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

enum PhotoCaptureFailure { permissionDenied, unavailable, saveFailed }

class PhotoCaptureException implements Exception {
  const PhotoCaptureException(this.failure);
  final PhotoCaptureFailure failure;
}

abstract interface class ProductPhotoService {
  Future<String?> capture();
  Future<void> delete(String photoPath);
}

abstract interface class ProductGalleryPhotoService {
  Future<String?> chooseFromGallery();
}

class LocalProductPhotoService
    implements ProductPhotoService, ProductGalleryPhotoService {
  LocalProductPhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<String?> capture() async {
    return _pick(ImageSource.camera);
  }

  @override
  Future<String?> chooseFromGallery() => _pick(ImageSource.gallery);

  Future<String?> _pick(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (photo == null) return null;
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(path.join(documents.path, 'product_images'));
      await directory.create(recursive: true);
      final destination = path.join(
        directory.path,
        'product_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(photo.path).copy(destination);
      return destination;
    } on PlatformException catch (error) {
      if (error.code.toLowerCase().contains('denied') ||
          error.code.toLowerCase().contains('access')) {
        throw const PhotoCaptureException(PhotoCaptureFailure.permissionDenied);
      }
      throw const PhotoCaptureException(PhotoCaptureFailure.unavailable);
    } on FileSystemException {
      throw const PhotoCaptureException(PhotoCaptureFailure.saveFailed);
    }
  }

  @override
  Future<void> delete(String photoPath) async {
    final file = File(photoPath);
    if (await file.exists()) await file.delete();
  }
}
