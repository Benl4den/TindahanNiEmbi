import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/widgets/pro_feature_preview.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('premium preview is readable in $brightness', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.green,
              brightness: brightness,
            ),
          ),
          home: const Scaffold(
            body: ProFeaturePreview(
              title: 'Understand your brands better',
              description: 'A private premium feature.',
              icon: Icons.sell_outlined,
              metrics: ['Brand Sales', 'Brand Profit', 'Total Products'],
              benefits: ['Manage individual brands'],
            ),
          ),
        ),
      );
      expect(find.text('PRO FEATURE'), findsOneWidget);
      expect(find.text('--'), findsNWidgets(3));
      expect(find.text('Preview Pro'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Preview Pro'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('subscriptions are not available'),
        findsOneWidget,
      );
    });
  }
}
