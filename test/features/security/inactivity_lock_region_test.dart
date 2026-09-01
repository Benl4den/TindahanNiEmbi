import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/security/presentation/inactivity_lock_region.dart';

void main() {
  testWidgets('real interaction resets inactivity lock timer', (tester) async {
    var locks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: InactivityLockRegion(
          loadMinutes: () async => 5,
          onTimeout: () => locks++,
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('Interact'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));
    await tester.tap(find.text('Interact'));
    await tester.pump(const Duration(minutes: 4));
    expect(locks, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(locks, 1);
  });
}
