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
  return const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
}

List<DeviceOrientation> preferredOrientationsForDisplay(ui.Display? display) =>
    display == null
    ? const []
    : preferredOrientationsForMetrics(display.size, display.devicePixelRatio);

// Android can ignore orientation requests for large displays. Keep the tablet
// interface inaccessible in a portrait window even when the OS does so.
bool requiresTabletLandscapePrompt(
  ui.Size physicalDisplaySize,
  double devicePixelRatio,
  ui.Size windowSize,
) =>
    devicePixelRatio > 0 &&
    !isCompactDisplay(physicalDisplaySize, devicePixelRatio) &&
    windowSize.height > windowSize.width;
