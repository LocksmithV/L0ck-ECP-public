import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/ui/attachments.dart';
import 'package:l0ck_ecp/ui/reports.dart';

void main() {
  setUp(() => Lang.current.value = const Locale('cs'));

  Widget app(Widget Function(BuildContext) child) => MaterialApp(
        locale: const Locale('cs'),
        supportedLocales: Lang.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Builder(builder: child)),
      );

  testWidgets('+ menu: photo and file go out when a fit channel is there, else it says why', (t) async {
    final sent = <Attachment>[];
    var up = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('cz.l0ck.ecp/files'),
        (c) async => c.method == 'pick'
            ? {'name': 'mapa.pdf', 'mime': 'application/pdf', 'data': Uint8List.fromList([1, 2, 3])}
            : null);
    final actions = AttachActions(available: () => up, send: (a) async => sent.add(a));
    await t.pumpWidget(app((context) => TextButton(
        onPressed: () => showReportMenu(context, (_, _) async {}, attach: actions), child: const Text('+'))));

    await t.tap(find.text('+'));
    await t.pumpAndSettle();
    expect(find.text('Vyfotit'), findsOneWidget);
    await t.tap(find.text('Soubor'));
    await t.pumpAndSettle();
    expect(find.textContaining('Fotky a soubory potřebují SimpleX'), findsWidgets);
    expect(sent, isEmpty);

    up = true;
    await t.tap(find.text('+'));
    await t.pumpAndSettle();
    await t.tap(find.text('Soubor'));
    await t.pumpAndSettle();
    expect(sent.single.name, 'mapa.pdf');
    expect(sent.single.kind, Attachment.file);
  });

  testWidgets('a file in a bubble shows its name and size', (t) async {
    final a = Attachment(kind: Attachment.file, name: 'mapa.pdf', mime: 'application/pdf', bytes: Uint8List(2048));
    await t.pumpWidget(app((_) => AttachmentView(payload: a.encode())));
    expect(find.text('mapa.pdf'), findsOneWidget);
    expect(find.text('2 kB'), findsOneWidget);
  });
}
