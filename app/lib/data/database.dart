import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';

part 'database.g.dart';

/// The profile's own identity; exactly one row (id = 1).
class IdentityRows extends Table {
  IntColumn get id => integer()();
  BlobColumn get privateKey => blob()();
  TextColumn get nickname => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Contacts as read from their contact card (docs/ARCHITECTURE_V2.md §5).
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BlobColumn get ecpKey => blob().unique()();
  TextColumn get briarLink => text().nullable()();
  TextColumn get simplexLink => text().nullable()();
  TextColumn get phone => text().nullable()();
  IntColumn get meshtasticId => integer().nullable()();
  BlobColumn get meshcoreKey => blob().nullable()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
}

/// What the user sees in a conversation. [id] is the ECP message id (hex), shared with the
/// router's outbox so delivery events can update the row.
class Messages extends Table {
  TextColumn get id => text()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  TextColumn get teamId => text().nullable()();
  BoolColumn get outgoing => boolean()();
  IntColumn get type => integer()();
  BlobColumn get payload => blob()();
  DateTimeColumn get at => dateTime()();

  /// Outgoing: sending · sent · delivered · read · waiting · confirm · failed.
  /// Incoming: received (unread) · seen.
  TextColumn get status => text()();

  /// When [status] last changed (delivered/read time shown in the chat).
  DateTimeColumn get statusAt => dateTime().nullable()();

  /// Team messages: the sender's 2-byte fingerprint (hex), shown as a contact name if known.
  TextColumn get sender => text().nullable()();
  TextColumn get via => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The router's in-flight pair messages (ecp_core OutboxEntry), so a restart neither loses
/// nor blindly re-sends them.
class OutboxRows extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  BlobColumn get envelope => blob()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get emergency => boolean()();
  IntColumn get state => integer()();
  IntColumn get layerIndex => integer()();
  DateTimeColumn get deadline => dateTime().nullable()();
  BoolColumn get smsApproved => boolean()();
  TextColumn get tried => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Replay-guard memory (message id → ECP time first seen), survives restarts.
class SeenIds extends Table {
  TextColumn get id => text()();
  IntColumn get seenAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Teams this profile belongs to. The id and the team's LoRa channel are derived from the
/// key, so every member arrives at the same ones (docs/ARCHITECTURE_V2.md §5).
class Teams extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BlobColumn get key => blob()();
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Who is in which team, as far as this phone knows (the member whose team QR was scanned,
/// members who announced themselves or wrote to the team, manual additions). Team messages
/// also go to these contacts over SimpleX/Bramble, so members out of radio range get them.
class TeamMembers extends Table {
  TextColumn get teamId => text()();
  IntColumn get contactId => integer().references(Contacts, #id)();

  @override
  Set<Column> get primaryKey => {teamId, contactId};
}

/// Per-profile settings (e.g. which LoRa radio this profile uses), key → value.
class SettingRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [IdentityRows, Contacts, Messages, OutboxRows, SeenIds, SettingRows, Teams, TeamMembers])
class EcpDatabase extends _$EcpDatabase {
  EcpDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(messages);
            await m.createTable(outboxRows);
            await m.createTable(seenIds);
          }
          if (from < 3) await m.createTable(settingRows);
          if (from < 4) {
            await m.createTable(teams);
            if (from >= 2) await m.addColumn(messages, messages.sender);
          }
          if (from < 5) {
            await m.createTable(teamMembers);
            if (from >= 2) await m.addColumn(messages, messages.statusAt);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Opens (or creates) a SQLCipher database. Refuses to run on plain SQLite, so a build
  /// mistake can never silently store data unencrypted.
  static EcpDatabase openEncrypted(File file, List<int> key) {
    final hexKey = toHex(key);
    return EcpDatabase(NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        raw.execute("PRAGMA key = \"x'$hexKey'\";");
        final cipher = raw.select('PRAGMA cipher_version;');
        if (cipher.isEmpty || '${cipher.first.values.first}'.isEmpty) {
          throw StateError('SQLCipher is not active — refusing an unencrypted database');
        }
        // A wrong key only surfaces on first read; fail here, not later
        raw.select('SELECT count(*) FROM sqlite_master;');
      },
    ));
  }

  Future<IdentityRow?> identity() =>
      (select(identityRows)..where((t) => t.id.equals(1))).getSingleOrNull();

  Future<void> saveIdentity(List<int> privateKey, String nickname) =>
      into(identityRows).insertOnConflictUpdate(IdentityRowsCompanion.insert(
        id: const Value(1),
        privateKey: Uint8List.fromList(privateKey),
        nickname: nickname,
        createdAt: DateTime.now(),
      ));

  Future<int> contactCount() async {
    final c = contacts.id.count();
    final row = await (selectOnly(contacts)..addColumns([c])).getSingle();
    return row.read(c) ?? 0;
  }

  Stream<List<Contact>> watchContacts() =>
      (select(contacts)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Stream<Contact?> watchContact(int id) =>
      (select(contacts)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Contact?> contactByKey(List<int> ecpKey) =>
      (select(contacts)..where((t) => t.ecpKey.equals(Uint8List.fromList(ecpKey))))
          .getSingleOrNull();

  Stream<List<Message>> watchConversation(int contactId) => (select(messages)
        ..where((t) => t.contactId.equals(contactId))
        ..orderBy([(t) => OrderingTerm.asc(t.at)]))
      .watch();

  Stream<List<Team>> watchTeams() =>
      (select(teams)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Stream<List<Message>> watchTeamConversation(String teamId) => (select(messages)
        ..where((t) => t.teamId.equals(teamId))
        ..orderBy([(t) => OrderingTerm.asc(t.at)]))
      .watch();

  /// Unread incoming messages per contact id and per team id.
  Stream<({Map<int, int> contacts, Map<String, int> teams})> watchUnread() {
    final q = select(messages)..where((t) => t.outgoing.equals(false) & t.status.equals('received'));
    return q.watch().map((rows) {
      final c = <int, int>{}, t = <String, int>{};
      for (final m in rows) {
        if (m.teamId != null) {
          t[m.teamId!] = (t[m.teamId!] ?? 0) + 1;
        } else if (m.contactId != null) {
          c[m.contactId!] = (c[m.contactId!] ?? 0) + 1;
        }
      }
      return (contacts: c, teams: t);
    });
  }

  Stream<List<Contact>> watchTeamMembers(String teamId) {
    final q = select(contacts).join([
      innerJoin(teamMembers, teamMembers.contactId.equalsExp(contacts.id)),
    ])
      ..where(teamMembers.teamId.equals(teamId));
    return q.watch().map((rows) => [for (final r in rows) r.readTable(contacts)]);
  }

  Future<String?> setting(String key) async =>
      (await (select(settingRows)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String? value) => value == null
      ? (delete(settingRows)..where((t) => t.key.equals(key))).go()
      : into(settingRows).insertOnConflictUpdate(SettingRowsCompanion.insert(key: key, value: value));

  Future<void> setMessageStatus(String id, String status, {String? via}) =>
      (update(messages)..where((t) => t.id.equals(id))).write(MessagesCompanion(
        status: Value(status),
        via: via == null ? const Value.absent() : Value(via),
      ));
}
