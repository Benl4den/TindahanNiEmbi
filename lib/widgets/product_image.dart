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
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: path.isEmpty
          ? _placeholder(context)
          : Image.file(
              File(path),
              fit: BoxFit.scaleDown,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _placeholder(context),
            ),
    ),
  );

  Widget _placeholder(BuildContext context) => Center(
    child: Icon(
      placeholderIcon,
      size: 42,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
