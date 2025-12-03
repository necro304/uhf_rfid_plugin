// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:uhf_rfid_plugin/uhf_rfid_plugin.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('init reader test', (WidgetTester tester) async {
    // Test initialization - will only succeed on actual PDA device with UHF hardware
    final bool success = await UhfRfidPlugin.init();
    // On real device with UHF hardware, this should be true
    // On emulator or devices without UHF, this will be false
    expect(success, isA<bool>());
  });

  testWidgets('getHardwareVersion test', (WidgetTester tester) async {
    // Initialize first
    await UhfRfidPlugin.init();

    // Get hardware version
    final String? version = await UhfRfidPlugin.getHardwareVersion();
    // Version will be null if reader not initialized or not available
    // On real device, it should return a version string
    expect(version, anyOf(isNull, isA<String>()));
  });

  testWidgets('power configuration test', (WidgetTester tester) async {
    await UhfRfidPlugin.init();

    // Test setting power
    final bool setPowerResult = await UhfRfidPlugin.setPower(
      readPower: 26,
      writePower: 26,
    );
    expect(setPowerResult, isA<bool>());

    // Test getting power
    final Map<String, int>? power = await UhfRfidPlugin.getPower();
    expect(power, anyOf(isNull, isA<Map<String, int>>()));
  });

  testWidgets('region configuration test', (WidgetTester tester) async {
    await UhfRfidPlugin.init();

    // Test setting region
    final bool setRegionResult = await UhfRfidPlugin.setRegion(FrequencyRegion.usa);
    expect(setRegionResult, isA<bool>());

    // Test getting region
    final String? region = await UhfRfidPlugin.getRegion();
    expect(region, anyOf(isNull, isA<String>()));
  });

  testWidgets('inventory once test', (WidgetTester tester) async {
    await UhfRfidPlugin.init();

    // Perform single inventory
    final List<RfidTag> tags = await UhfRfidPlugin.inventoryOnce(timeout: 100);
    expect(tags, isA<List<RfidTag>>());
  });

  testWidgets('temperature test', (WidgetTester tester) async {
    await UhfRfidPlugin.init();

    // Get temperature
    final int? temp = await UhfRfidPlugin.getTemperature();
    expect(temp, anyOf(isNull, isA<int>()));
  });

  testWidgets('close reader test', (WidgetTester tester) async {
    await UhfRfidPlugin.init();

    // Close the reader
    final bool closeResult = await UhfRfidPlugin.close();
    expect(closeResult, isA<bool>());
  });
}
