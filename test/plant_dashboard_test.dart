import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant/main.dart';

void main() {
  testWidgets('PlantDashboard builds and shows title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PlantDashboard()));
    // avoid pumpAndSettle because animations/timers run; pump briefly
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Emergence-Connect'), findsOneWidget);
    expect(find.text('Manual Pump Override'), findsOneWidget);
  });
}
