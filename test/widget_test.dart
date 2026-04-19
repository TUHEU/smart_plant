import 'package:flutter_test/flutter_test.dart';

import 'package:smart_plant/main.dart';

void main() {
  testWidgets('Dashboard loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartPlantApp());

    // Check if title appears
    expect(find.text('Emergence-Connect'), findsOneWidget);

    // Check if key widgets exist (names used by app)
    expect(find.text('Moisture'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Manual Pump Override'), findsOneWidget);
  });
}
