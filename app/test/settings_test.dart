import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/ui/settings_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('factory reset sits in App and erases only after the confirmation', (t) async {
    Lang.current.value = const Locale('cs');
    late MessagingService m;
    late Directory dir;
    await t.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('l0ck_settings_test');
      m = await MessagingService.start(
          Session(randomBytes(32), EcpDatabase(NativeDatabase.memory()), await EcpIdentity.generate(), 'Alfa'));
    });
    var resets = 0;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: Lang.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SettingsScreen(
        messaging: m,
        security: SecurityService(dir, strengthen: (k) async => k, deleteHardwareKey: () async {}),
        onFactoryReset: () async => resets++,
      ),
    ));
    expect(find.byKey(const Key('factory-reset')), findsNothing, reason: 'sections start closed');
    await t.tap(find.byKey(const Key('section-app')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('factory-reset')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('factory-reset')));
    await t.pumpAndSettle();
    expect(resets, 0, reason: 'the button only asks');
    await t.tap(find.text('Zrušit'));
    await t.pumpAndSettle();
    expect(resets, 0);

    await t.tap(find.byKey(const Key('factory-reset')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('factory-reset-confirm')));
    await t.pumpAndSettle();
    expect(resets, 1);

    await t.runAsync(() async {
      await m.dispose();
      await m.session.close();
      await dir.delete(recursive: true);
    });
  });
}
