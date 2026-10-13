import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/services/device_orientation_policy.dart';

void main() {
  test('phone is compact in portrait and landscape', () {
    expect(isCompactDisplay(const Size(1080, 2400), 3), isTrue);
    expect(isCompactDisplay(const Size(2400, 1080), 3), isTrue);
    expect(preferredOrientationsForMetrics(const Size(1080, 2400), 3), [
      DeviceOrientation.portraitUp,
    ]);
    expect(preferredOrientationsForMetrics(const Size(2400, 1080), 3), [
      DeviceOrientation.portraitUp,
    ]);
  });

  test('tablet uses landscape in either physical rotation', () {
    expect(isCompactDisplay(const Size(1600, 2560), 2), isFalse);
    expect(isCompactDisplay(const Size(2560, 1600), 2), isFalse);
    const landscape = [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    expect(
      preferredOrientationsForMetrics(const Size(1600, 2560), 2),
      landscape,
    );
    expect(
      preferredOrientationsForMetrics(const Size(2560, 1600), 2),
      landscape,
    );
  });

  test('600 logical pixels is the expanded breakpoint', () {
    expect(isCompactDisplay(const Size(1200, 2400), 2), isFalse);
    expect(isCompactDisplay(const Size(1198, 2400), 2), isTrue);
    expect(preferredOrientationsForMetrics(const Size(1200, 2400), 2), [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });

  test('unknown display leaves platform orientation unchanged', () {
    expect(preferredOrientationsForDisplay(null), isEmpty);
  });

  test('portrait tablet window is guarded when rotation is not enforced', () {
    expect(
      requiresTabletLandscapePrompt(
        const Size(1600, 2560),
        2,
        const Size(800, 1280),
      ),
      isTrue,
    );
    expect(
      requiresTabletLandscapePrompt(
        const Size(2560, 1600),
        2,
        const Size(1280, 800),
      ),
      isFalse,
    );
    expect(
      requiresTabletLandscapePrompt(
        const Size(1080, 2400),
        3,
        const Size(360, 800),
      ),
      isFalse,
    );
  });
}
