// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhf_rfid_plugin_example/main.dart';

void main() {
  testWidgets('App renders with navigation bar', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app renders with the navigation bar
    expect(find.byType(NavigationBar), findsOneWidget);

    // Verify that both navigation destinations are present
    expect(find.text('RFID UHF'), findsOneWidget);
    expect(find.text('Barcode/QR'), findsOneWidget);
  });
}
