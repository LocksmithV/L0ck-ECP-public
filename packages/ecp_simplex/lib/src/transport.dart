import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ecp_core/ecp_core.dart';

import 'api.dart';

/// PACE layer P: ECP envelopes as SimpleX text messages (`ecp1:` + base64url). SimpleX gives
/// relay-based delivery with no user identifiers; ECP adds its own end-to-end layer, ACKs
/// and de-duplication on top, as on every channel.
///
/// Pairing: each side's SimpleX profile is named after its ECP key ([profileName]), so a
/// SimpleX contact is matched to the ECP contact whose card has that key. The own contact
/// address (on the ECP card, field `sx`) auto-accepts requests; a stranger who connects
/// gets nothing, since only envelopes for a known key are ever sent.
class SimplexTransport extends Transport {
  SimplexTransport(this.api, {required List<int> ownKey}) : profile = profileName(ownKey);

  final SimplexApi api;

  /// Our SimpleX display name.
  final String profile;

  static const prefix = 'ecp1:';

  static String profileName(List<int> ecpKey) =>
      'ecp-${sha256.convert(ecpKey).toString().substring(0, 16)}';

  int? _userId;
  String? _address;
  StreamSubscription<Map<String, dynamic>>? _sub;

  /// SimpleX profile name → SimpleX contact id (connected contacts only).
  final Map<String, int> _contactByName = {};

  /// ECP contact id → profile name its SimpleX side uses.
  final Map<String, String> _nameOf = {};

  /// Addresses we already asked to connect to (this session).
  final Set<String> _connecting = {};

  void Function(Uint8List envelope)? onData;
  void Function()? onChanged;

  @override
  String get id => 'simplex';

  @override
  PaceLayer? get layer => PaceLayer.primary;

  /// Our contact address for the ECP card, once started.
  String? get address => _address;

  /// Creates the profile on first use, starts the core, makes sure the address exists and
  /// auto-accepts, and loads the contact list. Without a network the address cannot be made
  /// yet: the transport still starts, and [ensureAddress] gets it later.
  Future<void> start() async {
    Map<String, dynamic> user;
    try {
      user = (await api.cmd('/user'))['user'] as Map<String, dynamic>;
    } on SimplexError {
      final newUser = {
        'profile': {'displayName': profile, 'fullName': ''},
        'pastTimestamp': false,
      };
      user = (await api.cmd('/_create user ${jsonEncode(newUser)}'))['user'] as Map<String, dynamic>;
    }
    final uid = user['userId'] as int;
    if ((user['profile'] as Map?)?['displayName'] != profile) {
      // e.g. the CLI created the user with another name; contacts match on this one
      await api.cmd('/_profile $uid ${jsonEncode({'displayName': profile, 'fullName': ''})}');
    }
    _userId = uid;
    await api.cmd('/_start');
    _sub = api.events.listen(_onEvent);
    await ensureAddress();
    await refreshContacts();
  }

  /// The own contact address (shown, or created — which needs a relay) with auto-accept on.
  /// False while it cannot be had (no network); call again when the network is back.
  Future<bool> ensureAddress() async {
    final uid = _userId;
    if (uid == null) return false;
    if (_address != null) return true;
    try {
      Map<String, dynamic> link;
      try {
        final r = await api.cmd('/_show_address $uid');
        link = (r['contactLink'] as Map<String, dynamic>)['connLinkContact'] as Map<String, dynamic>;
      } on SimplexError {
        link = (await api.cmd('/_address $uid'))['connLinkContact'] as Map<String, dynamic>;
      }
      final settings = {'businessAddress': false, 'autoAccept': {'acceptIncognito': false}};
      await api.cmd('/_address_settings $uid ${jsonEncode(settings)}');
      _address = (link['connShortLink'] ?? link['connFullLink']) as String;
      onChanged?.call(); // the own card now has the SimpleX address
      return true;
    } on SimplexError {
      return false;
    }
  }

  Future<void> refreshContacts() async {
    final uid = _userId;
    if (uid == null) return;
    final r = await api.cmd('/_contacts $uid');
    _contactByName.clear();
    for (final c in (r['contacts'] as List).cast<Map<String, dynamic>>()) {
      _remember(c);
    }
    onChanged?.call();
  }

  void _remember(Map<String, dynamic> c) {
    final name = (c['profile'] as Map<String, dynamic>?)?['displayName'] as String?;
    final ready = c['activeConn'] != null && c['contactStatus'] != 'deleted';
    if (name != null && name.startsWith('ecp-') && ready) {
      _contactByName[name] = c['contactId'] as int;
    }
  }

  /// The ECP contact list: [keys] maps ECP contact id → its ECP public key, [links] its
  /// SimpleX address (from the card). Unknown addresses are connected to once.
  Future<void> contactsChanged(Map<String, List<int>> keys, Map<String, String> links) async {
    _nameOf
      ..clear()
      ..addAll({for (final e in keys.entries) e.key: profileName(e.value)});
    for (final e in links.entries) {
      final name = _nameOf[e.key];
      if (name == null || _contactByName.containsKey(name) || !_connecting.add(e.value)) {
        continue;
      }
      try {
        final r = await api.cmd('/connect ${e.value}');
        if (r['type'] == 'contactAlreadyExists') _remember(r['contact'] as Map<String, dynamic>);
      } on SimplexError {
        _connecting.remove(e.value); // try again on the next change
      }
    }
  }

  Future<void> _onEvent(Map<String, dynamic> e) async {
    switch (e['type']) {
      case 'contactConnected' || 'contactSndReady' || 'contactUpdated':
        final c = (e['contact'] ?? e['toContact']) as Map<String, dynamic>?;
        if (c != null) _remember(c);
        onChanged?.call();
      case 'contactDeletedByContact':
        await refreshContacts();
      case 'newChatItems':
        for (final item in (e['chatItems'] as List).cast<Map<String, dynamic>>()) {
          final env = _envelopeOf(item);
          if (env != null) onData?.call(env);
        }
    }
  }

  /// An incoming direct text that carries an ECP envelope; everything else is ignored.
  static Uint8List? _envelopeOf(Map<String, dynamic> item) {
    final info = item['chatInfo'] as Map<String, dynamic>?;
    final ci = item['chatItem'] as Map<String, dynamic>?;
    if (info?['type'] != 'direct' || ci == null) return null;
    if ((ci['chatDir'] as Map?)?['type'] != 'directRcv') return null;
    final content = ci['content'] as Map<String, dynamic>?;
    if (content?['type'] != 'rcvMsgContent') return null;
    final text = (content!['msgContent'] as Map?)?['text'];
    if (text is! String || !text.startsWith(prefix)) return null;
    try {
      return base64Url.decode(base64Url.normalize(text.substring(prefix.length)));
    } on FormatException {
      return null;
    }
  }

  static String encode(List<int> envelope) =>
      prefix + base64Url.encode(envelope).replaceAll('=', '');

  @override
  bool get isAvailable => _userId != null;

  @override
  bool canReach(String contactId) => _contactByName.containsKey(_nameOf[contactId]);

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    final c = _contactByName[_nameOf[contactId]];
    if (c == null) return false;
    final msg = [
      {'msgContent': {'type': 'text', 'text': encode(data)}, 'mentions': <String, int>{}},
    ];
    try {
      await api.cmd('/_send @$c json ${jsonEncode(msg)}');
      return true;
    } on SimplexError {
      return false;
    }
  }

  /// Reconnects to every SMP relay (after the network came back); true when the core
  /// accepted it. Contacts are reloaded too.
  Future<bool> reconnect() async {
    try {
      await api.cmd('/reconnect');
      await ensureAddress();
      await refreshContacts();
      return true;
    } on SimplexError {
      return false;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _userId = null;
  }
}
