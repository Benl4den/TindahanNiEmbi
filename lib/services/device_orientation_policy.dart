import 'dart:ui' as ui;

import 'package:flutter/services.dart';

// Match Flutter's compact/medium breakpoint using the full display, not the
// possibly letterboxed app window. The shortest side is rotation-independent.
const double compactDisplayBreakpoint = 600;

bool isCompactDisplay(ui.Size physicalSize, double devicePixelRatio) =>
    devicePixelRatio > 0 &&
    physicalSize.shortestSide / devicePixelRatio < compactDisplayBreakpoint;

List<DeviceOrientation> preferredOrientationsForMetrics(
  ui.Size physicalSize,
  double devicePixelRatio,
) {
  if (isCompactDisplay(physicalSize, devicePixelRatio)) {
    return const [DeviceOrientation.portraitUp];
  }
  // An empty list delegates to the platform and keeps tablets rotatable.
  return const [];
}

List<DeviceOrientation> preferredOrientationsForDisplay(ui.Display? display) =>
    display == null
    ? const []
    : preferredOrientationsForMetrics(display.size, display.devicePixelRatio);
