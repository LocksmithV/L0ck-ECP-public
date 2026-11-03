import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/messaging/meshcore_app_transport.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/ui/group_import.dart';

Future<MessagingService> phone(String name) async => MessagingService.start(
    Session(randomBytes(32), EcpDatabase(NativeDatabase.memory()), await EcpIdentity.generate(), name));

/// What the base laptop makes after scanning Alfa, Bravo and Charlie: a team of all three
/// (its LoRa channel for the radios), a team of Bravo and Charlie only, and a PACE order.
GroupBundle bundleOf(List<MessagingService> m) => GroupBundle(
      members: [for (final p in m) ContactCard.fromUri(p.myContactUri())],
      teams: [
        GroupTeam(name: 'Hlídka', key: randomBytes(32), members: [0, 1, 2]),
        GroupTeam(name: 'Spojka', key: randomBytes(32), members: [1, 2]),
      ],
      loraTeam: 0,
      pace: [PaceLayer.alternate, PaceLayer.primary, PaceLayer.contingency, PaceLayer.emergency],
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a phone takes the others as verified contacts, its own teams, LoRa and PACE', () async {
    final m = [await phone('Alfa'), await phone('Bravo'), await phone('Charlie')];
    final outsider = await phone('Delta');
    final b = GroupBundle.decode(bundleOf(m).encode());

    final r = (await m[0].importGroup(b))!;
    expect((r.added, r.changed, r.same, r.newTeams), (2, 0, 0, 1));
    expect(r.teams.map((t) => t.name), ['Hlídka'], reason: 'Spojka does not list Alfa');
    expect(r.lora!.name, 'Hlídka');
    expect(r.pace, isTrue);
    final db = m[0].session.db;
    final contacts = await db.select(db.contacts).get();
    expect(contacts.map((c) => (c.name, c.verified)).toSet(), {('Bravo', true), ('Charlie', true)});
    final members = await db.select(db.teamMembers).get();
    expect(members.map((x) => x.contactId).toSet(), contacts.map((c) => c.id).toSet());
    expect(await db.setting(radioChannelKey), encodeChannelKey(await MessagingService.teamLoraKey(b.teams[0].key)));
    expect(m[0].paceOrder.first, PaceLayer.alternate);

    // Bravo is in both teams, with the same team ids as everyone else
    final rb = (await m[1].importGroup(b))!;
    expect(rb.teams.map((t) => t.name).toSet(), {'Hlídka', 'Spojka'});
    expect(rb.teams.first.id, r.teams.first.id);

    // Importing twice changes nothing; a phone not in the bundle gets nothing
    final again = (await m[0].importGroup(b))!;
    expect((again.added, again.changed, again.same, again.newTeams), (0, 0, 2, 0));
    expect((again.lora, again.pace, again.nothing), (null, false, true));
    expect(await db.select(db.contacts).get(), hasLength(2));

    // A corrected bundle: only Charlie's new name and number are written
    final c = b.members[2];
    final fixed = GroupBundle(
      members: [
        b.members[0],
        b.members[1],
        ContactCard(name: 'Charlie 2', ecpKey: c.ecpKey, briarLink: c.briarLink, simplexLink: c.simplexLink,
            phone: '+420 777 000 003'),
      ],
      teams: b.teams,
      loraTeam: b.loraTeam,
      pace: b.pace,
    );
    final third = (await m[0].importGroup(fixed))!;
    expect((third.added, third.changed, third.same, third.newTeams, third.nothing), (0, 1, 1, 0, false));
    final charlie = (await db.select(db.contacts).get()).singleWhere((x) => constantTimeEquals(x.ecpKey, c.ecpKey));
    expect((charlie.name, charlie.phone), ('Charlie 2', '+420 777 000 003'));
    expect(await outsider.importGroup(b), isNull);
    final odb = outsider.session.db;
    expect(await odb.select(odb.contacts).get(), isEmpty);

    for (final p in [...m, outsider]) {
      await p.dispose();
      await p.session.close();
    }
  });

  test('a number the base typed in for this phone becomes its own number', () async {
    final m = [await phone('Alfa'), await phone('Bravo')];
    GroupBundle bundle(String? alfaPhone) {
      final a = ContactCard.fromUri(m[0].myContactUri());
      return GroupBundle(members: [
        ContactCard(name: a.name, ecpKey: a.ecpKey, briarLink: a.briarLink, simplexLink: a.simplexLink, phone: alfaPhone),
        ContactCard.fromUri(m[1].myContactUri()),
      ]);
    }

    expect(m[0].ownPhone, isNull);
    final b = bundle('+420 600 111 222');
    expect(m[0].ownPhoneFrom(b), '+420 600 111 222');
    expect((await m[0].importGroup(b))!.phone, '+420 600 111 222');
    expect(m[0].ownPhone, '+420 600 111 222');
    expect(m[0].ownPhoneFrom(b), isNull, reason: 'already the own number');
    final second = (await m[0].importGroup(bundle(null)))!;
    expect(second.phone, isNull, reason: 'no number: the own one stays');
    expect(m[0].ownPhone, '+420 600 111 222');
    expect(m[1].ownPhoneFrom(b), isNull, reason: 'Bravo\'s card has none');

    for (final p in m) {
      await p.dispose();
      await p.session.close();
    }
  });

  testWidgets('screen: parts in any order, a foreign QR is refused, then one tap sets up', (t) async {
    Lang.current.value = const Locale('cs');
    late List<MessagingService> m;
    late List<String> parts;
    await t.runAsync(() async {
      m = [await phone('Alfa'), await phone('Bravo')];
      final data = GroupBundle(members: [for (final p in m) ContactCard.fromUri(p.myContactUri())]).encode();
      parts = GroupBundle.toQrParts(data, id: '01234567', chunk: (data.length + 1) ~/ 2);
    });
    expect(parts, hasLength(2));
    final queue = ['l0ck://c/AAAA', parts[1], parts[0]];
    final prompts = <String>[];
    await t.pumpWidget(MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: Lang.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: GroupImportScreen(
        messaging: m[1],
        scan: ({String prompt = ''}) async {
          prompts.add(prompt);
          return queue.removeAt(0);
        },
      ),
    ));
    await t.tap(find.byKey(const Key('group-scan')));
    await t.pump();
    expect(find.text('Tohle není QR balíčku skupiny.'), findsOneWidget, reason: 'a contact QR stops the scanning');
    await t.tap(find.byKey(const Key('group-scan')));
    await t.pump();
    expect(prompts, ['Balíček skupiny: kterýkoli QR', 'Balíček skupiny: kterýkoli QR', 'Balíček skupiny: QR 1 z 2']);
    expect(find.text('KONTAKTY (1)'), findsOneWidget); // panel titles are upper case
    expect(find.text('Alfa'), findsOneWidget);
    await t.tap(find.byKey(const Key('group-apply')));
    for (var i = 0; i < 20 && find.byKey(const Key('group-done')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.text('Hotovo. Kontakty: nové 1, změněné 0, beze změny 0. Nové týmy: 0.'), findsOneWidget);

    await t.runAsync(() async {
      for (final p in m) {
        await p.dispose();
        await p.session.close();
      }
    });
  });

  testWidgets('screen: a failing setup shows the error instead of loading for ever', (t) async {
    Lang.current.value = const Locale('cs');
    late List<MessagingService> m;
    late String part;
    await t.runAsync(() async {
      m = [await phone('Alfa'), await phone('Bravo')];
      final data = GroupBundle(members: [for (final p in m) ContactCard.fromUri(p.myContactUri())]).encode();
      part = GroupBundle.toQrParts(data, id: '89abcdef').single;
      await m[1].session.db.close(); // every write from now on fails
    });
    await t.pumpWidget(MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: Lang.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: GroupImportScreen(messaging: m[1], scan: ({String prompt = ''}) async => part),
    ));
    await t.tap(find.byKey(const Key('group-scan')));
    await t.pump();
    await t.tap(find.byKey(const Key('group-apply')));
    for (var i = 0; i < 20 && find.textContaining('Nastavení se nepovedlo').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.textContaining('Nastavení se nepovedlo'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.widget<ButtonStyleButton>(find.byKey(const Key('group-apply'))).onPressed, isNotNull,
        reason: 'another try is possible');

    await t.runAsync(() async {
      await m[0].dispose();
      await m[0].session.close();
    });
  });
}
