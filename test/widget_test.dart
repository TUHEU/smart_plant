import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant/main.dart';

void main() {
  testWidgets('Dashboard loads correctly', (WidgetTester tester) async {
    // Build the app using the correct class name
    await tester.pumpWidget(FarmLinkApp());
    await tester.pumpAndSettle();

    // Verify the top items that are immediately visible
    expect(find.text('FarmLink Analytics'), findsOneWidget);
    expect(find.text('Soil Moisture'), findsOneWidget);
    expect(find.text('Tank Level'), findsOneWidget);

    // Scroll down the GridView to reveal the bottom cards
    final gridFinder = find.byType(GridView);
    await tester.drag(gridFinder, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Verify the bottom cards are now visible after scrolling
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Soil Temp'), findsOneWidget);
  });
}
