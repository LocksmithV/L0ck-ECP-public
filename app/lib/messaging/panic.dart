import 'dart:convert';

import 'package:ecp_core/ecp_core.dart';

/// What the PANIC button on the PIN screen sends, set in the settings. Kept in the profile's
/// encrypted database: the buttons exist only while that profile runs behind the PIN screen.
class PanicConfig {
  const PanicConfig({
    this.button = true,
    this.status = StatusCode.needHelp,
    this.text = '',
    this.position = true,
    this.contacts = true,
    this.teams = true,
    this.compromiseButton = true,
    this.repeatMinutes = 0,
  });

  /// Choices for [repeatMinutes]; 0: once.
  static const repeatChoices = [0, 5, 10, 15, 30];

  /// PANIC is shown on the PIN screen.
  final bool button;
  final StatusCode status;

  /// Own words sent after the status (empty: none); at most [maxReportText] bytes, so it
  /// fits one LoRa packet.
  final String text;
  final bool position;

  /// Recipients: every contact, every team.
  final bool contacts;
  final bool teams;

  /// KOMPROMITOVÁN is shown on the PIN screen.
  final bool compromiseButton;

  /// After PANIC the status with a fresh position goes out again every so many minutes,
  /// until the PIN is typed (0: only once).
  final int repeatMinutes;

  PanicConfig copyWith({
    bool? button,
    StatusCode? status,
    String? text,
    bool? position,
    bool? contacts,
    bool? teams,
    bool? compromiseButton,
    int? repeatMinutes,
  }) => PanicConfig(
    button: button ?? this.button,
    status: status ?? this.status,
    text: text ?? this.text,
    position: position ?? this.position,
    contacts: contacts ?? this.contacts,
    teams: teams ?? this.teams,
    compromiseButton: compromiseButton ?? this.compromiseButton,
    repeatMinutes: repeatMinutes ?? this.repeatMinutes,
  );

  String encode() => jsonEncode({
    'button': button,
    'status': status.code,
    'text': text,
    'position': position,
    'contacts': contacts,
    'teams': teams,
    'compromise': compromiseButton,
    'repeat': repeatMinutes,
  });

  /// Unknown or damaged settings fall back to the defaults, field by field.
  static PanicConfig decode(String? s) {
    const d = PanicConfig();
    if (s == null) return d;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      T f<T>(String k, T fallback) => m[k] is T ? m[k] as T : fallback;
      StatusCode status;
      try {
        status = StatusCode.fromCode(f('status', d.status.code));
      } on Object {
        status = d.status;
      }
      return PanicConfig(
        button: f('button', d.button),
        status: status,
        text: f('text', d.text),
        position: f('position', d.position),
        contacts: f('contacts', d.contacts),
        teams: f('teams', d.teams),
        compromiseButton: f('compromise', d.compromiseButton),
        repeatMinutes: f('repeat', d.repeatMinutes),
      );
    } on Object {
      return d;
    }
  }
}

/// The check-in ("dead man's switch", settings): unless the owner confirms within [minutes]
/// — the home screen button, or unlocking with the PIN — [status] with the position goes to
/// the PANIC recipients. Kept in the profile's encrypted database like [PanicConfig].
class CheckInConfig {
  const CheckInConfig({this.enabled = false, this.minutes = 240, this.status = StatusCode.needHelp, this.position = true});

  /// Choices in the settings.
  static const choices = [60, 120, 240, 480, 720, 1440];

  /// The reminder comes this long before the check-in goes out.
  static const remindBefore = Duration(minutes: 15);

  final bool enabled;
  final int minutes;
  final StatusCode status;
  final bool position;

  Duration get every => Duration(minutes: minutes);

  CheckInConfig copyWith({bool? enabled, int? minutes, StatusCode? status, bool? position}) => CheckInConfig(
    enabled: enabled ?? this.enabled,
    minutes: minutes ?? this.minutes,
    status: status ?? this.status,
    position: position ?? this.position,
  );

  String encode() => jsonEncode({'on': enabled, 'minutes': minutes, 'status': status.code, 'position': position});

  /// Unknown or damaged settings fall back to the defaults, field by field.
  static CheckInConfig decode(String? s) {
    const d = CheckInConfig();
    if (s == null) return d;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      T f<T>(String k, T fallback) => m[k] is T ? m[k] as T : fallback;
      StatusCode status;
      try {
        status = StatusCode.fromCode(f('status', d.status.code));
      } on Object {
        status = d.status;
      }
      final minutes = f('minutes', d.minutes);
      return CheckInConfig(
        enabled: f('on', d.enabled),
        minutes: minutes > 0 ? minutes : d.minutes,
        status: status,
        position: f('position', d.position),
      );
    } on Object {
      return d;
    }
  }
}
