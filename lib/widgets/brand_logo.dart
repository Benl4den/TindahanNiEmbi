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
  Widget build(BuildContext context) {
    final isDark = dark || Theme.of(context).brightness == Brightness.dark;
    final icon = Image.asset(
      isDark
          ? 'assets/branding/tindasari_ts_transparent.png'
          : 'assets/branding/tindasari_icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    if (!horizontal) return Semantics(label: 'TindaSari PH', child: icon);
    return Semantics(
      label: 'TindaSari PH',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'TindaSari PH',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: isDark
                    ? const Color(0xFFF4F6F5)
                    : const Color(0xFF0F6B46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
