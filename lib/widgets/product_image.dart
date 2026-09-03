import 'dart:io';

import 'package:flutter/material.dart';

/// Displays product photography consistently without stretching small images.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.path,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.borderRadius = 0,
  });

  final String path;
  final IconData placeholderIcon;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: ColoredBox(
      color: const Color(0xFFF0F3F0),
      child: path.isEmpty
          ? _placeholder()
          : Image.file(
              File(path),
              fit: BoxFit.scaleDown,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    ),
  );

  Widget _placeholder() => Center(
    child: Icon(placeholderIcon, size: 42, color: const Color(0xFF7A847D)),
  );
}
