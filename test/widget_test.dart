import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_plant/main.dart';

void main() {
  testWidgets('Dashboard loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartPlantApp());

    // Check if title appears
    expect(find.text('Emergence-Connect: Plant Monitor'), findsOneWidget);

    // Check if key widgets exist
    expect(find.text('Moisture'), findsOneWidget);
    expect(find.text('Temp'), findsOneWidget);
    expect(find.text('Manual Pump Override'), findsOneWidget);
  });
}
