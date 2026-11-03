import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/ui/recipients.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('teams and several contacts are picked together', (t) async {
    Lang.current.value = const Locale('cs');
    late MessagingService m;
    late Team team;
    final ids = <int>[];
    await t.runAsync(() async {
      final db = EcpDatabase(NativeDatabase.memory());
      m = await MessagingService.start(Session(randomBytes(32), db, await EcpIdentity.generate(), 'Alfa'));
      team = await m.createTeam('Hlídka');
      for (final name in ['Bravo', 'Charlie', 'Delta']) {
        final other = await MessagingService.start(
            Session(randomBytes(32), EcpDatabase(NativeDatabase.memory()), await EcpIdentity.generate(), name));
        ids.add((await m.addContactFromUri(other.myContactUri()) as ContactAdded).contact.id);
        await other.dispose();
        await other.session.close();
      }
    });

    Recipients? picked;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: Lang.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await Navigator.of(context)
              .push<Recipients>(MaterialPageRoute(builder: (_) => RecipientPicker(messaging: m))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 20 && find.byKey(Key('contact-${ids.last}')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
    final send = find.byKey(const Key('send-to'));
    expect(t.widget<ButtonStyleButton>(send).onPressed, isNull, reason: 'nobody picked yet');
    await t.tap(find.byKey(Key('team-${team.id}')));
    await t.tap(find.byKey(Key('contact-${ids[0]}')));
    await t.tap(find.byKey(Key('contact-${ids[2]}')));
    await t.pump();
    expect(find.text('ODESLAT (3)'), findsOneWidget);
    await t.tap(send);
    await t.pumpAndSettle();
    expect(picked!.teams, {team.id});
    expect(picked!.contacts, {ids[0], ids[2]});

    await t.runAsync(() async {
      await m.dispose();
      await m.session.close();
    });
  });
}
