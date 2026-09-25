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

    for (final size in [const Size(1200, 800), const Size(550, 900)]) {
      testWidgets('four wallet metrics wrap cleanly at $size in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
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
                title: 'Track your GCash transactions in one place',
                description: 'Record Cash-In, Cash-Out, and service fees.',
                metrics: [
                  'Current GCash Balance',
                  'Cash-In Today',
                  'Cash-Out Today',
                  'Service Fees\nAll time',
                ],
                benefits: ['Record GCash Cash-In and Cash-Out'],
              ),
            ),
          ),
        );
        final cards = find.text('--');
        expect(cards, findsNWidgets(4));
        final y = [
          for (var i = 0; i < 4; i++) tester.getTopLeft(cards.at(i)).dy,
        ];
        expect(y[0], y[1]);
        if (size.width > 1000) {
          expect(y[1], y[2]);
          expect(y[2], y[3]);
        } else {
          expect(y[2], y[3]);
          expect(y[2], greaterThan(y[1]));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
