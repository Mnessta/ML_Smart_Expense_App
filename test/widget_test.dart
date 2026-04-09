import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('Basic widget tree renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Smoke test')),
        ),
      ),
    );

    expect(find.text('Smoke test'), findsOneWidget);
  });
}
