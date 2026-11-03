import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/ui/voice.dart';

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    Lang.current.value = const Locale('cs');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('cz.l0ck.ecp/permissions'), (c) async => true);
    m.setMockMethodCallHandler(const MethodChannel('cz.l0ck.ecp/audio'), (c) async {
      calls.add(c.method);
      return switch (c.method) {
        'start' => VoicePart.opus,
        'level' => 12000,
        'stop' => {'data': Uint8List.fromList([1, 2, 3]), 'codec': VoicePart.opus, 'durationMs': 4200},
        'play' => 4200,
        _ => null,
      };
    });
  });

  Widget app(Widget child) => MaterialApp(
        locale: const Locale('cs'),
        supportedLocales: Lang.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: child),
      );

  testWidgets('recorder: records at once, send stops and hands over the clip', (t) async {
    (int, int, Uint8List)? sent;
    var closed = 0;
    await t.pumpWidget(app(VoiceRecorder(
      onSend: (codec, ms, data) async => sent = (codec, ms, data),
      onClose: () => closed++,
    )));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(calls, containsAllInOrder(['start', 'level']));
    await t.tap(find.byKey(const Key('voice-send')));
    await t.pumpAndSettle();
    expect(calls, contains('stop'));
    expect(sent!.$1, VoicePart.opus);
    expect(sent!.$2, 4200);
    expect(sent!.$3, [1, 2, 3]);
    expect(closed, 1);
  });

  testWidgets('recorder: discard keeps nothing', (t) async {
    var sent = 0, closed = 0;
    await t.pumpWidget(app(VoiceRecorder(onSend: (_, _, _) async => sent++, onClose: () => closed++)));
    await t.pump();
    await t.tap(find.byKey(const Key('voice-discard')));
    await t.pumpAndSettle();
    expect(calls, contains('cancel'));
    expect((sent, closed), (0, 1));
  });

  testWidgets('a clip in a bubble shows its length and plays', (t) async {
    final clip = VoicePart.split(Uint8List.fromList([1, 2, 3, 4]), VoicePart.opus, 7400, Uint8List(10)).single;
    await t.pumpWidget(app(VoiceClipView(id: 'm1', payload: clip.encode())));
    expect(find.text('0:07'), findsOneWidget);
    await t.tap(find.byKey(const Key('play-m1')));
    await t.pump();
    expect(calls, ['play']);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });
}
