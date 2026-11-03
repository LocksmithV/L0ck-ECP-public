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
  });

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

  PanicConfig copyWith({
    bool? button,
    StatusCode? status,
    String? text,
    bool? position,
    bool? contacts,
    bool? teams,
    bool? compromiseButton,
  }) => PanicConfig(
    button: button ?? this.button,
    status: status ?? this.status,
    text: text ?? this.text,
    position: position ?? this.position,
    contacts: contacts ?? this.contacts,
    teams: teams ?? this.teams,
    compromiseButton: compromiseButton ?? this.compromiseButton,
  );

  String encode() => jsonEncode({
    'button': button,
    'status': status.code,
    'text': text,
    'position': position,
    'contacts': contacts,
    'teams': teams,
    'compromise': compromiseButton,
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
      );
    } on Object {
      return d;
    }
  }
}
