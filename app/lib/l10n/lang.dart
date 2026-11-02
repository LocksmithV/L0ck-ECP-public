import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// UI language: Czech or English, switched in settings. The choice must apply before any
/// profile is unlocked (lock and first-run screens), so it lives in a small plain file next
/// to the encrypted profiles — the only thing kept outside them, and it tells nothing.
abstract final class Lang {
  static const supported = [Locale('cs'), Locale('en')];

  static final ValueNotifier<Locale> current = ValueNotifier(_system());

  /// For code without a BuildContext (channel status lines, service errors).
  static AppLocalizations get tr => lookupAppLocalizations(current.value);

  static Locale _system() =>
      PlatformDispatcher.instance.locale.languageCode == 'cs' ? const Locale('cs') : const Locale('en');

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/lang');

  static Future<void> load() async {
    try {
      final code = (await (await _file()).readAsString()).trim();
      if (code == 'cs' || code == 'en') current.value = Locale(code);
    } catch (_) {
      // first start: the phone's language
    }
  }

  static Future<void> set(Locale l) async {
    current.value = l;
    await (await _file()).writeAsString(l.languageCode);
  }
}

extension L10n on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}
