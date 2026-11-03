import 'dart:convert';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lang.dart';
import '../platform/location.dart';
import 'theme.dart';

/// Sends one message of [type] with [payload] to the open conversation (contact or team), or
/// to recipients picked after the form (home screen).
typedef SendPayload = Future<void> Function(int type, Uint8List payload);

/// Thrown by a [SendPayload] when nothing was sent (no recipient picked): the form stays
/// open with what was filled in.
class SendCancelled implements Exception {
  const SendCancelled();
}

// --- labels (docs/ARCHITECTURE_V2.md §4: the wire carries codes, the UI names them) ---

String statusLabel(StatusCode s) {
  final l = Lang.tr;
  return switch (s) {
    StatusCode.ok => l.stOk,
    StatusCode.needHelp => l.stNeedHelp,
    StatusCode.compromised => l.stCompromised,
    StatusCode.injured => l.stInjured,
    StatusCode.moving => l.stMoving,
    StatusCode.inPosition => l.stInPosition,
  };
}

Color statusColor(StatusCode s) => switch (s) {
  StatusCode.ok || StatusCode.inPosition => L0ckColors.ok,
  StatusCode.moving => L0ckColors.greenLight,
  StatusCode.needHelp || StatusCode.injured => L0ckColors.orange,
  StatusCode.compromised => L0ckColors.red,
};

// Code lists are kept as one translated string each, items separated by '|'.
List<String> get sitrepStates => Lang.tr.sitrepStates.split('|');
List<String> get medevacPrecedence => Lang.tr.medevacPrecedence.split('|');
List<String> get medevacEquipment => Lang.tr.medevacEquipment.split('|');
List<String> get medevacSecurity => Lang.tr.medevacSecurity.split('|');
List<String> get medevacMarking => Lang.tr.medevacMarking.split('|');
List<String> get medevacNationality => Lang.tr.medevacNationality.split('|');
List<String> get medevacTerrain => Lang.tr.medevacTerrain.split('|');

String _pick(List<String> l, int i) => i >= 0 && i < l.length ? l[i] : '? ($i)';

// --- showing a report ---

/// A report or position inside a chat bubble: what, where, how far and which way from here.
class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.type, required this.payload});

  final int type;
  final Uint8List payload;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    try {
      if (type == MessageType.position) {
        return _body(context, l.rPosition, L0ckColors.greenLight, const [], Position.decode(payload));
      }
      return switch (Report.decode(payload)) {
        StatusReport(:final status, :final position) => _body(
          context,
          '${l.rStatus}: ${statusLabel(status)}',
          statusColor(status),
          const [],
          position,
        ),
        RallyReport(:final point, :final at) => _body(context, l.rRally, L0ckColors.orange, [
          l.timeLine(_time(at)),
        ], point),
        SitrepReport(:final state, :final persons, :final position, :final text) => _body(
          context,
          '${l.rSitrep}: ${_pick(sitrepStates, state)}',
          state >= 2 ? L0ckColors.red : L0ckColors.greenLight,
          [l.personsLine(persons), if (text.isNotEmpty) text],
          position,
        ),
        final MedevacReport r => _body(context, l.rMedevac, L0ckColors.red, [
          l.mLine2(r.callsign),
          l.mLine3(
            [
              for (var i = 0; i < 5; i++)
                if (r.patientsByPrecedence[i] > 0) '${r.patientsByPrecedence[i]}× ${medevacPrecedence[i]}',
            ].join(', '),
          ),
          l.mLine4(_pick(medevacEquipment, r.equipment)),
          l.mLine5(r.litter, r.ambulatory),
          l.mLine6(_pick(medevacSecurity, r.security)),
          l.mLine7(_pick(medevacMarking, r.marking)),
          l.mLine8(_pick(medevacNationality, r.nationality)),
          l.mLine9(_pick(medevacTerrain, r.terrain)),
        ], r.location),
        final SalterReport r => _body(context, l.rSalter, L0ckColors.orange, [
          l.sSize(r.size),
          l.sActivity(r.activity),
          l.sTime(_time(r.time)),
          if (r.equipment.isNotEmpty) l.sEquipment(r.equipment),
          if (r.remarks.isNotEmpty) l.sRemarks(r.remarks),
        ], r.location),
        final FiveWReport r => _body(context, l.r5w, L0ckColors.greenLight, [
          l.wWho(r.who),
          l.wWhat(r.what),
          l.wWhen(_time(r.when)),
          if (r.why.isNotEmpty) l.wWhy(r.why),
        ], r.where),
      };
    } on Object {
      return Text(l.reportUnreadable, style: const TextStyle(color: L0ckColors.red));
    }
  }

  static String _time(DateTime t) {
    final l = t.toLocal();
    return '${l.day}. ${l.month}. ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _body(BuildContext context, String title, Color color, List<String> lines, Position? p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
      for (final l in lines) SelectableText(l, style: const TextStyle(color: L0ckColors.text)),
      if (p != null) ...[
        const SizedBox(height: 4),
        SelectableText(formatLatLon(p), style: const TextStyle(color: L0ckColors.data)),
        if (p.accuracy != null)
          Text(context.l.accuracy(p.accuracy!), style: const TextStyle(color: L0ckColors.dim, fontSize: 11)),
        ValueListenableBuilder<Position?>(
          valueListenable: Locator.last,
          builder: (_, me, _) => me == null
              ? TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => Locator.current(timeout: const Duration(seconds: 15)).ignore(),
                  child: Text(context.l.distanceFindMe),
                )
              : Text(
                  context.l.distanceBearing(
                    formatDistance(distanceMeters(me, p)),
                    formatBearing(bearingDegrees(me, p)),
                  ),
                  style: const TextStyle(color: L0ckColors.orange),
                ),
        ),
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(context.l.map),
              onPressed: () async {
                if (!await Locator.openInMap(p, title) && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.noMapApp)));
                }
              },
            ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(context.l.coordinates),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${p.lat.toStringAsFixed(6)}, ${p.lon.toStringAsFixed(6)}'));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.coordsCopied)));
              },
            ),
          ],
        ),
      ],
    ],
  );
}

/// Plain-text form of a report or position, for copying the whole message.
String reportText(int type, Uint8List payload) {
  final l = Lang.tr;
  String t(DateTime d) => ReportView._time(d);
  try {
    if (type == MessageType.position) return '${l.rPosition} ${formatLatLon(Position.decode(payload))}';
    return switch (Report.decode(payload)) {
      StatusReport(:final status, :final position) =>
        '${l.rStatus} ${statusLabel(status)}${position == null ? '' : ' ${formatLatLon(position)}'}',
      RallyReport(:final point, :final at) => '${l.rRally} ${formatLatLon(point)} ${t(at)}',
      SitrepReport(:final state, :final persons, :final position, :final text) =>
        '${l.rSitrep} ${_pick(sitrepStates, state)}, ${l.persons} $persons, ${formatLatLon(position)} $text',
      final MedevacReport r => 'MEDEVAC ${r.callsign} ${formatLatLon(r.location)}',
      final SalterReport r => [
        l.rSalter,
        l.sSize(r.size),
        l.sActivity(r.activity),
        'L ${formatLatLon(r.location)}',
        l.sTime(t(r.time)),
        if (r.equipment.isNotEmpty) l.sEquipment(r.equipment),
        if (r.remarks.isNotEmpty) l.sRemarks(r.remarks),
      ].join('\n'),
      final FiveWReport r => [
        l.r5w,
        l.wWho(r.who),
        l.wWhat(r.what),
        '${l.fwWhere}: ${formatLatLon(r.where)}',
        l.wWhen(t(r.when)),
        if (r.why.isNotEmpty) l.wWhy(r.why),
      ].join('\n'),
    };
  } on Object {
    return '';
  }
}

// --- composing ---

/// The "+" menu in a chat.
Future<void> showReportMenu(BuildContext context, SendPayload send) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true, // all eight entries at once; scrolls only on a small screen
  backgroundColor: L0ckColors.panel,
  builder: (ctx) {
    final l = context.l;
    void open(Widget w) {
      Navigator.pop(ctx);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l.reports, style: labelStyle)),
            ListTile(
              leading: const Icon(Icons.my_location, color: L0ckColors.greenLight),
              title: Text(l.myPosition),
              onTap: () => open(_PositionForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: L0ckColors.greenLight),
              title: Text(l.rStatus),
              subtitle: Text(l.statusSub, style: const TextStyle(color: L0ckColors.dim)),
              onTap: () => open(_StatusForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined, color: L0ckColors.orange),
              title: Text(l.rRally),
              subtitle: Text(l.rallySub, style: const TextStyle(color: L0ckColors.dim)),
              onTap: () => open(_RallyForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_outlined, color: L0ckColors.greenLight),
              title: Text(l.rSitrep),
              subtitle: Text(l.sitrepSub, style: const TextStyle(color: L0ckColors.dim)),
              onTap: () => open(_SitrepForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined, color: L0ckColors.orange),
              title: Text(l.rSalter),
              subtitle: Text(l.salterSub, style: const TextStyle(color: L0ckColors.dim)),
              onTap: () => open(_SalterForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: L0ckColors.greenLight),
              title: Text(l.r5w),
              subtitle: Text(l.fiveWSub, style: const TextStyle(color: L0ckColors.dim)),
              onTap: () => open(_FiveWForm(send: send)),
            ),
            ListTile(
              leading: const Icon(Icons.local_hospital_outlined, color: L0ckColors.red),
              title: Text(l.rMedevac),
              onTap: () => open(_MedevacForm(send: send)),
            ),
          ],
        ),
      ),
    );
  },
);

/// Where: the phone's GPS fix, or coordinates typed in (a rally point, a casualty elsewhere).
class _PositionPicker extends StatefulWidget {
  const _PositionPicker({required this.onChanged});

  final ValueChanged<Position?> onChanged;

  @override
  State<_PositionPicker> createState() => _PositionPickerState();
}

class _PositionPickerState extends State<_PositionPicker> {
  Position? _p;
  String? _error;
  bool _busy = false, _manual = false;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gps();
  }

  Future<void> _gps() async {
    setState(() {
      _busy = true;
      _error = null;
      _manual = false;
    });
    try {
      _set(await Locator.current());
    } on LocationError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(Position? p) {
    setState(() => _p = p);
    widget.onChanged(p);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: L0ckColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l.positionCaps, style: labelStyle),
        const SizedBox(height: 6),
        if (_busy) Text(context.l.gettingGps, style: const TextStyle(color: L0ckColors.dim)),
        if (_p != null && !_manual)
          Text(
            '${formatLatLon(_p!)}${_p!.accuracy == null ? '' : '  ±${_p!.accuracy} m'}',
            style: const TextStyle(color: L0ckColors.data),
          ),
        if (_error != null) Text(_error!, style: const TextStyle(color: L0ckColors.orange)),
        if (_manual)
          TextField(
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(labelText: context.l.coordsLabel),
            onChanged: (t) => _set(Locator.parse(t)),
          ),
        if (_manual && _text.text.isNotEmpty && _p == null)
          Text(context.l.coordsNotUnderstood, style: const TextStyle(color: L0ckColors.red)),
        Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: _busy ? null : _gps, child: Text(context.l.myPositionGps)),
            TextButton(
              onPressed: () => setState(() {
                _manual = true;
                _set(Locator.parse(_text.text));
              }),
              child: Text(context.l.enterManually),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Common frame of the forms: content, then a send button that is live once [ready].
class _Form extends StatelessWidget {
  const _Form({required this.title, required this.children, required this.onSend});

  final String title;
  final List<Widget> children;
  final Future<void> Function()? onSend;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...children,
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: Text(context.l.sendCaps),
          onPressed: onSend == null
              ? null
              : () async {
                  try {
                    await onSend!();
                  } on SendCancelled {
                    return;
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
        ),
      ],
    ),
  );
}

class _PositionForm extends StatefulWidget {
  const _PositionForm({required this.send});
  final SendPayload send;

  @override
  State<_PositionForm> createState() => _PositionFormState();
}

class _PositionFormState extends State<_PositionForm> {
  Position? _p;

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.myPosition,
    onSend: _p == null ? null : () => widget.send(MessageType.position, _p!.encode()),
    children: [_PositionPicker(onChanged: (p) => setState(() => _p = p))],
  );
}

class _StatusForm extends StatefulWidget {
  const _StatusForm({required this.send});
  final SendPayload send;

  @override
  State<_StatusForm> createState() => _StatusFormState();
}

class _StatusFormState extends State<_StatusForm> {
  StatusCode _s = StatusCode.ok;
  Position? _p;
  bool _withPosition = true;

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.rStatus,
    onSend: () => widget.send(MessageType.report, StatusReport(_s, _withPosition ? _p : null).encode()),
    children: [
      for (final s in StatusCode.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: statusColor(s),
              backgroundColor: _s == s ? statusColor(s).withValues(alpha: 0.18) : null,
              side: BorderSide(color: _s == s ? statusColor(s) : L0ckColors.border),
            ),
            onPressed: () => setState(() => _s = s),
            child: Text(statusLabel(s).toUpperCase()),
          ),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _withPosition,
        onChanged: (v) => setState(() => _withPosition = v),
        title: Text(context.l.attachPosition),
      ),
      if (_withPosition) _PositionPicker(onChanged: (p) => setState(() => _p = p)),
    ],
  );
}

class _RallyForm extends StatefulWidget {
  const _RallyForm({required this.send});
  final SendPayload send;

  @override
  State<_RallyForm> createState() => _RallyFormState();
}

class _RallyFormState extends State<_RallyForm> {
  Position? _p;
  DateTime _at = DateTime.now().add(const Duration(minutes: 30));

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.rRally,
    onSend: _p == null ? null : () => widget.send(MessageType.report, RallyReport(_p!, _at).encode()),
    children: [
      _PositionPicker(onChanged: (p) => setState(() => _p = p)),
      const SizedBox(height: 12),
      Text(context.l.rallyTime(ReportView._time(_at)), style: const TextStyle(color: L0ckColors.data)),
      _TimePicker(value: _at, quick: const [15, 30, 60, 120], onChanged: (t) => setState(() => _at = t)),
    ],
  );
}

class _SitrepForm extends StatefulWidget {
  const _SitrepForm({required this.send});
  final SendPayload send;

  @override
  State<_SitrepForm> createState() => _SitrepFormState();
}

class _SitrepFormState extends State<_SitrepForm> {
  int _state = 0, _persons = 1;
  Position? _p;
  final _text = TextEditingController();

  int get _bytes => utf8.encode(_text.text).length;

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.rSitrep,
    onSend: _p == null || _bytes > SitrepReport.maxText
        ? null
        : () => widget.send(
            MessageType.report,
            SitrepReport(state: _state, persons: _persons, position: _p!, text: _text.text.trim()).encode(),
          ),
    children: [
      Text(context.l.stateCaps, style: labelStyle),
      Wrap(
        spacing: 8,
        children: [
          for (final (i, s) in sitrepStates.indexed)
            ChoiceChip(label: Text(s), selected: _state == i, onSelected: (_) => setState(() => _state = i)),
        ],
      ),
      const SizedBox(height: 10),
      _Counter(label: context.l.personCount, value: _persons, onChanged: (v) => setState(() => _persons = v)),
      TextField(
        controller: _text,
        maxLines: 2,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: context.l.shortText,
          counterText: context.l.textBudget(_bytes, SitrepReport.maxText),
          errorText: _bytes > SitrepReport.maxText ? context.l.tooLongSms : null,
        ),
      ),
      const SizedBox(height: 8),
      _PositionPicker(onChanged: (p) => setState(() => _p = p)),
    ],
  );
}

class _MedevacForm extends StatefulWidget {
  const _MedevacForm({required this.send});
  final SendPayload send;

  @override
  State<_MedevacForm> createState() => _MedevacFormState();
}

class _MedevacFormState extends State<_MedevacForm> {
  Position? _p;
  final _callsign = TextEditingController();
  final _patients = List.filled(5, 0);
  int _equipment = 0, _litter = 0, _ambulatory = 0, _security = 0, _marking = 3, _nationality = 0, _terrain = 0;

  bool get _callsignOk =>
      _callsign.text.length <= MedevacReport.maxCallsign && RegExp(r'^[ -~]*$').hasMatch(_callsign.text);

  Widget _dropdown(String label, List<String> items, int value, ValueChanged<int> on) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: L0ckColors.panel,
      decoration: InputDecoration(labelText: label),
      items: [for (final (i, s) in items.indexed) DropdownMenuItem(value: i, child: Text(s))],
      onChanged: (v) => setState(() => on(v!)),
    ),
  );

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.rMedevac,
    onSend: _p == null || !_callsignOk
        ? null
        : () => widget.send(
            MessageType.report,
            MedevacReport(
              location: _p!,
              callsign: _callsign.text,
              patientsByPrecedence: _patients,
              equipment: _equipment,
              litter: _litter,
              ambulatory: _ambulatory,
              security: _security,
              marking: _marking,
              nationality: _nationality,
              terrain: _terrain,
            ).encode(),
          ),
    children: [
      Text(context.l.pickupSite, style: labelStyle),
      _PositionPicker(onChanged: (p) => setState(() => _p = p)),
      const SizedBox(height: 8),
      TextField(
        controller: _callsign,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: context.l.callsignLabel,
          errorText: _callsignOk ? null : context.l.callsignError,
        ),
      ),
      const SizedBox(height: 8),
      Text(context.l.patientsCaps, style: labelStyle),
      for (final (i, label) in medevacPrecedence.indexed)
        _Counter(label: label, value: _patients[i], onChanged: (v) => setState(() => _patients[i] = v)),
      _dropdown(context.l.line4, medevacEquipment, _equipment, (v) => _equipment = v),
      _Counter(label: context.l.line5Litter, value: _litter, onChanged: (v) => setState(() => _litter = v)),
      _Counter(label: context.l.line5Ambulatory, value: _ambulatory, onChanged: (v) => setState(() => _ambulatory = v)),
      _dropdown(context.l.line6, medevacSecurity, _security, (v) => _security = v),
      _dropdown(context.l.line7, medevacMarking, _marking, (v) => _marking = v),
      _dropdown(context.l.line8, medevacNationality, _nationality, (v) => _nationality = v),
      _dropdown(context.l.line9, medevacTerrain, _terrain, (v) => _terrain = v),
    ],
  );
}

/// Several short texts sharing one byte budget ([maxReportText]), so the report fits one
/// LoRa packet.
mixin _TextBudget<T extends StatefulWidget> on State<T> {
  List<TextEditingController> get texts;

  int get bytes => texts.fold(0, (n, c) => n + utf8.encode(c.text.trim()).length);
  bool get withinBudget => bytes <= maxReportText;

  Widget field(TextEditingController c, String label, {bool last = false}) => TextField(
    controller: c,
    maxLines: null,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      counterText: last ? context.l.textBudget(bytes, maxReportText) : null,
      errorText: last && !withinBudget ? context.l.tooLongLora : null,
    ),
  );
}

class _SalterForm extends StatefulWidget {
  const _SalterForm({required this.send});
  final SendPayload send;

  @override
  State<_SalterForm> createState() => _SalterFormState();
}

class _SalterFormState extends State<_SalterForm> with _TextBudget {
  int _size = 1;
  Position? _p;
  DateTime _time = DateTime.now();
  final _activity = TextEditingController(), _equipment = TextEditingController(), _remarks = TextEditingController();

  @override
  List<TextEditingController> get texts => [_activity, _equipment, _remarks];

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.rSalter,
    onSend: _p == null || _activity.text.trim().isEmpty || !withinBudget
        ? null
        : () => widget.send(
            MessageType.report,
            SalterReport(
              size: _size,
              activity: _activity.text.trim(),
              location: _p!,
              time: _time,
              equipment: _equipment.text.trim(),
              remarks: _remarks.text.trim(),
            ).encode(),
          ),
    children: [
      _Counter(label: context.l.salterSize, value: _size, max: 0xffff, onChanged: (v) => setState(() => _size = v)),
      field(_activity, context.l.salterActivity),
      const SizedBox(height: 8),
      Text(context.l.salterLocation, style: labelStyle),
      _PositionPicker(onChanged: (p) => setState(() => _p = p)),
      const SizedBox(height: 8),
      Text(context.l.salterTime(ReportView._time(_time)), style: const TextStyle(color: L0ckColors.data)),
      _TimePicker(value: _time, quick: const [0, -15, -30, -60], onChanged: (t) => setState(() => _time = t)),
      field(_equipment, context.l.salterEquipment),
      field(_remarks, context.l.salterRemarks, last: true),
    ],
  );
}

class _FiveWForm extends StatefulWidget {
  const _FiveWForm({required this.send});
  final SendPayload send;

  @override
  State<_FiveWForm> createState() => _FiveWFormState();
}

class _FiveWFormState extends State<_FiveWForm> with _TextBudget {
  Position? _p;
  DateTime _when = DateTime.now();
  final _who = TextEditingController(), _what = TextEditingController(), _why = TextEditingController();

  @override
  List<TextEditingController> get texts => [_who, _what, _why];

  @override
  Widget build(BuildContext context) => _Form(
    title: context.l.r5w,
    onSend: _p == null || _who.text.trim().isEmpty || _what.text.trim().isEmpty || !withinBudget
        ? null
        : () => widget.send(
            MessageType.report,
            FiveWReport(
              who: _who.text.trim(),
              what: _what.text.trim(),
              where: _p!,
              when: _when,
              why: _why.text.trim(),
            ).encode(),
          ),
    children: [
      field(_who, context.l.fwWho),
      field(_what, context.l.fwWhat),
      const SizedBox(height: 8),
      Text(context.l.fwWhere, style: labelStyle),
      _PositionPicker(onChanged: (p) => setState(() => _p = p)),
      const SizedBox(height: 8),
      Text(context.l.fwWhen(ReportView._time(_when)), style: const TextStyle(color: L0ckColors.data)),
      _TimePicker(value: _when, quick: const [0, -15, -30, -60], onChanged: (t) => setState(() => _when = t)),
      field(_why, context.l.fwWhy, last: true),
    ],
  );
}

/// Quick offsets from now in minutes (negative = ago, 0 = now), plus a full date and time.
class _TimePicker extends StatelessWidget {
  const _TimePicker({required this.value, required this.quick, required this.onChanged});

  final DateTime value;
  final List<int> quick;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    String label(int m) {
      if (m == 0) return l.now;
      final a = m.abs();
      final s = a < 60 ? '$a min' : '${a ~/ 60} h';
      return m > 0 ? (a < 60 ? l.inMinutes(a) : l.inHours(a ~/ 60)) : '−$s';
    }

    return Wrap(
      spacing: 8,
      children: [
        for (final m in quick)
          OutlinedButton(
            onPressed: () => onChanged(DateTime.now().add(Duration(minutes: m))),
            child: Text(label(m)),
          ),
        OutlinedButton(
          onPressed: () async {
            final now = DateTime.now();
            final first = now.subtract(const Duration(days: 30));
            final d = await showDatePicker(
              context: context,
              initialDate: value.isBefore(first) ? first : value,
              firstDate: DateTime(first.year, first.month, first.day),
              lastDate: now.add(const Duration(days: 365)),
            );
            if (d == null || !context.mounted) return;
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
            if (t == null) return;
            onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
          },
          child: Text(l.dateAndTime),
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChanged, this.max = 255});

  final String label;
  final int value, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: L0ckColors.text)),
      ),
      IconButton(
        onPressed: value > 0 ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      SizedBox(
        width: 28,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(color: L0ckColors.data, fontSize: 16),
        ),
      ),
      IconButton(
        onPressed: value < max ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );
}
