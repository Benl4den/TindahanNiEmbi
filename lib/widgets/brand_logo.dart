import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 48,
    this.horizontal = false,
    this.dark = false,
  });
  final double size;
  final bool horizontal, dark;
  @override
  Widget build(BuildContext context) => Image.asset(
    horizontal
        ? 'assets/branding/tindasari_logo.png'
        : dark
        ? 'assets/branding/tindasari_icon_dark.png'
        : 'assets/branding/tindasari_icon.png',
    width: horizontal ? null : size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'TindaSari PH',
  );
}
