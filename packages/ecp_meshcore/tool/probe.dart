/// Read-only check of a MeshCore companion on a serial port: who it is, its radio settings
/// and channel slots. Writes nothing to the radio.  dart run tool/probe.dart /dev/ttyUSB0
import 'dart:io';

import 'package:ecp_meshcore/ecp_meshcore.dart';

import 'package:ecp_meshcore/serial.dart';

Future<void> main(List<String> args) async {
  final link = await SerialLink.open(args.isEmpty ? '/dev/ttyUSB0' : args.first);
  await Future<void>.delayed(const Duration(seconds: 3)); // ESP32 may reboot on open
  final c = CompanionClient(link);
  final self = SelfInfo.parse(await c.request(appStart('probe'), {Resp.selfInfo}))!;
  final dev = DeviceInfo.parse(await c.request(deviceQuery(), {Resp.deviceInfo}))!;
  print('model ${dev.model}, firmware ${dev.version} (protocol ${dev.firmwareVersion})');
  print('radio ${self.radio}');
  print('channels: ${dev.maxChannels} slots');
  for (var i = 0; i < dev.maxChannels; i++) {
    final ch = ChannelInfo.parse(await c.request(getChannel(i), {Resp.channelInfo}))!;
    if (!ch.isEmpty) print('  slot $i: "${ch.name}"');
  }
  final b = await c.battery();
  print('battery ${b?.millivolts} mV');
  exit(0);
}
