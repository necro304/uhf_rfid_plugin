import 'package:flutter_test/flutter_test.dart';
import 'package:uhf_rfid_plugin/uhf_rfid_plugin.dart';
import 'package:uhf_rfid_plugin/uhf_rfid_plugin_platform_interface.dart';
import 'package:uhf_rfid_plugin/uhf_rfid_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockUhfRfidPluginPlatform
    with MockPlatformInterfaceMixin
    implements UhfRfidPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final UhfRfidPluginPlatform initialPlatform = UhfRfidPluginPlatform.instance;

  test('$MethodChannelUhfRfidPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelUhfRfidPlugin>());
  });

  test('getPlatformVersion', () async {
    UhfRfidPlugin uhfRfidPlugin = UhfRfidPlugin();
    MockUhfRfidPluginPlatform fakePlatform = MockUhfRfidPluginPlatform();
    UhfRfidPluginPlatform.instance = fakePlatform;

    expect(await uhfRfidPlugin.getPlatformVersion(), '42');
  });
}
