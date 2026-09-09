import 'package:flutter/material.dart';

/// Official gcash.com webclip, displayed in the store's green palette.
class GCashIcon extends StatelessWidget {
  const GCashIcon({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'GCash',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1,
          0,
          0,
          0,
          0,
          .5,
          0,
          .5,
          0,
          0,
          .5,
          .5,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Image.asset('assets/branding/gcash.png', width: 25, height: 25),
      ),
    ),
  );
}
