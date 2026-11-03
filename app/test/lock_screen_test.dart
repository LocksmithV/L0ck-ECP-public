import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/ui/lock_screen.dart';

void main() {
  late Directory dir;
  late SecurityService security;

  setUp(() async {
    Lang.current.value = const Locale('cs');
    dir = await Directory.systemTemp.createTemp('l0ck_lock_test');
    security = SecurityService(dir, strengthen: (k) async => k, deleteHardwareKey: () async {});
  });

  tearDown(() => dir.delete(recursive: true));

  Future<void> pump(WidgetTester t,
          {Future<String> Function()? panic, Future<void> Function()? compromise, Future<void> Function()? bio}) =>
      t.pumpWidget(MaterialApp(
        locale: const Locale('cs'),
        supportedLocales: Lang.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: LockScreen(
          security: security,
          onUnlocked: (_) {},
          onResumed: () {},
          onWiped: () {},
          onPanic: panic,
          onCompromise: compromise,
          onBiometric: bio,
        ),
      ));

  testWidgets('no profile running: no emergency buttons', (t) async {
    await pump(t);
    expect(find.byKey(const Key('panic')), findsNothing);
    expect(find.byKey(const Key('compromise')), findsNothing);
    expect(find.byKey(const Key('biometric')), findsNothing);
  });

  testWidgets('fingerprint button only when allowed; it asks the shell', (t) async {
    var asked = 0;
    await pump(t, bio: () async => asked++);
    await t.tap(find.byKey(const Key('biometric')));
    await t.pump();
    expect(asked, 1);
  });

  testWidgets('PANIC sends on one tap and shows the result', (t) async {
    var sent = 0;
    await pump(t, panic: () async {
      sent++;
      return 'PANIC odeslán: 2 kontaktům, 1 týmům';
    });
    await t.tap(find.byKey(const Key('panic')));
    await t.pumpAndSettle();
    expect(sent, 1);
    expect(find.text('PANIC odeslán: 2 kontaktům, 1 týmům'), findsOneWidget);
  });

  testWidgets('KOMPROMITOVÁN needs the confirmation at the top; it expires', (t) async {
    var destroyed = 0;
    await pump(t, compromise: () async => destroyed++);
    await t.tap(find.byKey(const Key('compromise')));
    await t.pump();
    expect(destroyed, 0, reason: 'the button itself only arms it');
    final confirm = find.byKey(const Key('confirm-compromise'));
    expect(confirm, findsOneWidget);
    expect(t.getTopLeft(confirm).dy, lessThan(t.getTopLeft(find.byKey(const Key('compromise'))).dy),
        reason: 'the confirmation is elsewhere on the screen');

    await t.pump(const Duration(seconds: 7));
    expect(confirm, findsNothing, reason: 'not confirmed in time: disarmed');

    await t.tap(find.byKey(const Key('compromise')));
    await t.pump();
    await t.tap(confirm);
    await t.pumpAndSettle();
    expect(destroyed, 1);
    expect(confirm, findsNothing);
  });
}
