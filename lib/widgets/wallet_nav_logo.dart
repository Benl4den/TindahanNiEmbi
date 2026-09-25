import 'package:flutter/material.dart';

/// Compact brand mark sized to match a standard sidebar icon.
class WalletNavLogo extends StatelessWidget {
  const WalletNavLogo({super.key, required this.maya});

  final bool maya;

  @override
  Widget build(BuildContext context) {
    final asset = maya
        ? 'assets/branding/maya_nav_logo.png'
        : 'assets/branding/gcash_nav_logo.png';
    // Crop in layout only, keeping the original transparent image untouched.
    // The GCash crop is its circular G mark; Maya's is its leading "m".
    return SizedBox(
      width: 27,
      height: 27,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: maya ? -17 : -5,
              top: maya ? -26 : -17,
              child: Image.asset(
                asset,
                width: maya ? 117 : 106,
                height: maya ? 78 : 60,
                fit: BoxFit.fill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
