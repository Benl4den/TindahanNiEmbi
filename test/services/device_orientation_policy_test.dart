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

  test('tablet stays expanded in portrait and landscape', () {
    expect(isCompactDisplay(const Size(1600, 2560), 2), isFalse);
    expect(isCompactDisplay(const Size(2560, 1600), 2), isFalse);
    expect(preferredOrientationsForMetrics(const Size(1600, 2560), 2), isEmpty);
    expect(preferredOrientationsForMetrics(const Size(2560, 1600), 2), isEmpty);
  });

  test('600 logical pixels is the expanded breakpoint', () {
    expect(isCompactDisplay(const Size(1200, 2400), 2), isFalse);
    expect(isCompactDisplay(const Size(1198, 2400), 2), isTrue);
  });

  test('unknown display leaves platform orientation unchanged', () {
    expect(preferredOrientationsForDisplay(null), isEmpty);
  });
}
