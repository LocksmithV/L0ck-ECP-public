// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutTagline =>
      'Emergency coordination platform — encrypted messaging over several paths (PACE): SimpleX, Tor, LoRa, SMS and a squad net over Bluetooth/Wi-Fi.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutAuthor => 'Author';

  @override
  String get aboutWeb => 'Website';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutLicenseText =>
      'GNU AGPLv3 — free software; source code available under the licence.';

  @override
  String get aboutThirdParty => 'Third-party components';

  @override
  String get aboutThirdPartyText =>
      'Briar/Bramble (GPLv3) · SimpleX Chat core (AGPLv3) · Tor (BSD) · MeshCore protocol (MIT) · ZXing (Apache 2.0) · SQLCipher (BSD) · libsodium (ISC) · Flutter (BSD)';

  @override
  String get aboutDisclaimer => 'Disclaimer';

  @override
  String get aboutDisclaimerText =>
      'L0ck-ECP is a tool for secure communication and coordination in emergencies. It is not intended for breaking the law or for any other unlawful activity.\n\nYou alone are responsible for using the app in line with the laws of the country you are in — among others on encryption, electronic communications and radio transmission (LoRa frequencies, power and duty cycle).\n\nThe software is provided “as is”, without warranty of any kind. The author accepts no liability for damage, data loss, undelivered messages or any other consequences of using the app. Do not rely on it as your only means of calling for help.';

  @override
  String get openFailed => 'The link cannot be opened (no browser).';

  @override
  String get wrongCode => 'Wrong code.';

  @override
  String get pin => 'PIN';

  @override
  String get verifying => 'Checking…';

  @override
  String retryIn(int secs) {
    return 'Try again in $secs s';
  }

  @override
  String get unlock => 'Unlock';

  @override
  String get nicknameLength => 'Nickname: 1–24 characters.';

  @override
  String pinError(String error) {
    return 'PIN: $error';
  }

  @override
  String get pinMismatch => 'The PINs do not match.';

  @override
  String duressError(String error) {
    return 'Duress code: $error';
  }

  @override
  String get duressMismatch => 'The duress codes do not match.';

  @override
  String get duressSameAsPin => 'The duress code must differ from the PIN.';

  @override
  String setupFailed(String error) {
    return 'Setup failed: $error';
  }

  @override
  String get firstRun => 'First run';

  @override
  String get nickname => 'Nickname';

  @override
  String get pinDigits => 'PIN (6–12 digits)';

  @override
  String get pinAgain => 'PIN again';

  @override
  String get duressCode => 'Duress code';

  @override
  String get duressExplain =>
      'Under duress, enter it instead of the PIN: it opens an empty profile and irreversibly destroys the real data.';

  @override
  String get duressDigits => 'Duress code (6–12 digits)';

  @override
  String get duressAgain => 'Duress code again';

  @override
  String get generatingKeys => 'Generating keys…';

  @override
  String get create => 'Create';

  @override
  String pinRuleEnter(int min, int max) {
    return 'Enter $min–$max digits.';
  }

  @override
  String get pinRuleDigits => 'Digits only.';

  @override
  String pinRuleMin(int min) {
    return 'At least $min digits.';
  }

  @override
  String pinRuleMax(int max) {
    return 'At most $max digits.';
  }

  @override
  String get currentCodeWrong => 'The current code is wrong.';

  @override
  String get codeInUse => 'This code is already in use.';

  @override
  String get duressMustDiffer => 'The duress code must differ from the PIN.';

  @override
  String get enterNickname => 'Enter a nickname.';

  @override
  String get duressWrong => 'Wrong duress code.';

  @override
  String get newMessages => 'New messages';

  @override
  String get directMessage => 'direct message';

  @override
  String get team => 'team';

  @override
  String get contacts => 'Contacts';

  @override
  String get teams => 'Teams';

  @override
  String get loraRadio => 'LoRa radio';

  @override
  String get settings => 'Settings';

  @override
  String get identity => 'Identity';

  @override
  String fingerprint(String fp) {
    return 'Fingerprint: $fp';
  }

  @override
  String smsNumber(String number) {
    return 'SMS number: $number';
  }

  @override
  String get notSet => 'not set';

  @override
  String get channels => 'Channels';

  @override
  String get noChannel => 'No channel';

  @override
  String get myContact => 'My contact';

  @override
  String get copyMyLink => 'Copy my link';

  @override
  String get linkCopied => 'Link copied. Clear the clipboard after pasting.';

  @override
  String get showInPersonOnly => 'Show in person only.';

  @override
  String contactsButton(String count) {
    return 'CONTACTS ($count)';
  }

  @override
  String get add => 'Add';

  @override
  String get noContactsYet => 'No contacts yet.';

  @override
  String get verifiedInPerson => 'verified in person';

  @override
  String get notVerified => 'not verified';

  @override
  String get openConversation => 'Open conversation';

  @override
  String get contactDetailMenu =>
      'Details: verification, channels, QR, Bluetooth, delete';

  @override
  String contactAndTeam(String contact, String team) {
    return '$contact and team $team';
  }

  @override
  String get addContact => 'Add contact';

  @override
  String get contactLinkLabel => 'Contact link (l0ck://c/…)';

  @override
  String contactUpdated(String name) {
    return 'Contact $name updated (new channels from the card).';
  }

  @override
  String get load => 'Load';

  @override
  String get scanQr => 'Scan a contact or team QR';

  @override
  String get scanPrompt => 'Point at the other phone\'s QR';

  @override
  String joinedTeam(String team) {
    return 'Joined team $team. LoRa radio switched to the team channel.';
  }

  @override
  String get verificationNumber => 'Verification number';

  @override
  String get verificationExplain =>
      'Compare it in person with the number on the contact\'s phone. The same number means nobody slipped in a foreign key.';

  @override
  String get numbersMatch => 'The numbers match (verified in person)';

  @override
  String get done => 'Done';

  @override
  String get contact => 'Contact';

  @override
  String get reportsAndPosition => 'Reports and position';

  @override
  String get message => 'Message';

  @override
  String get send => 'Send';

  @override
  String get renameContact => 'Rename contact';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String deleteContactQ(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteContactText =>
      'Deletes the contact, its keys and the whole conversation. Cannot be undone; to connect again, scan their QR again.';

  @override
  String get delete => 'Delete';

  @override
  String get brambleNotRunning => 'Bramble is not running.';

  @override
  String get needNearbyPermission =>
      'Not possible without the “Nearby devices” permission.';

  @override
  String get makingVisible => 'Making the phone visible…';

  @override
  String get noVisibility =>
      'Without visibility the phones cannot find each other.';

  @override
  String get searchingBt =>
      'Looking for the contact over Bluetooth (up to 30 s)…';

  @override
  String get btConnected =>
      'Connected over Bluetooth. Next time the phones find each other by themselves.';

  @override
  String get btNoUuid =>
      'The contact has not been connected another way yet (Tor/LAN) — try again later.';

  @override
  String get btNotFound =>
      'Not found. The contact must do the same at the same time, phones close together.';

  @override
  String get btNotBramble =>
      'The contact is not connected through Bramble yet.';

  @override
  String btUnavailable(String state) {
    return 'Bluetooth in Bramble did not start ($state). Try switching Bluetooth off and on in the phone.';
  }

  @override
  String unexpectedResult(String r) {
    return 'Unexpected result: $r';
  }

  @override
  String get rename => 'Rename';

  @override
  String get verification => 'Verification';

  @override
  String get verifiedInPersonDot => 'Verified in person.';

  @override
  String get notVerifiedExplain =>
      'Not verified. Compare the number with the contact\'s phone — the same number means nobody slipped in a foreign key.';

  @override
  String get unverify => 'Remove verification';

  @override
  String get markVerified => 'The numbers match — mark verified';

  @override
  String get missingOnCard => 'not on the card';

  @override
  String get connected => 'connected';

  @override
  String get connecting => 'connecting…';

  @override
  String get contactNoLink => 'contact, no link right now';

  @override
  String linksNow(String links) {
    return 'now: $links';
  }

  @override
  String get noPhone => 'no number';

  @override
  String get loraEveryone => 'ECP / team channel (everyone in range)';

  @override
  String get connectBluetooth => 'Connect via Bluetooth';

  @override
  String get connectBluetoothHelp =>
      'The first time both phones must do it at once: they become visible and find each other. After that they connect over Bluetooth by themselves (even without Wi-Fi and data).';

  @override
  String get contactCard => 'Contact card';

  @override
  String get theirCard =>
      'Their public card — pass it on only with their consent.';

  @override
  String get deleteContact => 'Delete contact';

  @override
  String get textCopied => 'Text copied.';

  @override
  String get sendViaSms => 'Send via SMS';

  @override
  String via(String via) {
    return 'via $via';
  }

  @override
  String get nobodyInRange => 'nobody in range';

  @override
  String sentTeam(String via) {
    return 'sent: $via';
  }

  @override
  String get stSending => 'sending…';

  @override
  String stSent(String via) {
    return 'sent via $via';
  }

  @override
  String stDelivered(String at, String via) {
    return 'delivered$at · $via';
  }

  @override
  String stRead(String at) {
    return 'read$at';
  }

  @override
  String get stWaiting => 'waiting for a channel';

  @override
  String get stConfirm => 'SMS only — confirm';

  @override
  String get stFailed => 'not delivered';

  @override
  String get squadNet => 'squad net';

  @override
  String get newTeam => 'New team';

  @override
  String get teamNameLocal => 'Name (only on your phone)';

  @override
  String get found => 'Create';

  @override
  String get teamDefaultName => 'Team';

  @override
  String get noTeams =>
      'No team yet.\n\nCreate one: “New team”, then show the others the team QR.\nJoin: in Contacts, “Add” and scan or paste a member\'s team QR.';

  @override
  String teamId(String id) {
    return 'ID $id';
  }

  @override
  String teamQrTitle(String team) {
    return 'Team QR — $team';
  }

  @override
  String get teamQrWarning =>
      'Show it in person and to members only. Whoever photographs the QR can read the team\'s traffic.';

  @override
  String get close => 'Close';

  @override
  String leaveTeamQ(String team) {
    return 'Leave $team?';
  }

  @override
  String get leaveTeamText =>
      'Members are told that you leave. The team, its messages and its key disappear from this phone; you can only come back by scanning the team QR again.';

  @override
  String get leave => 'Leave';

  @override
  String get leaveTeamMenu => 'Leave and delete team';

  @override
  String get teamMembers => 'Team members';

  @override
  String get teamMembersHelp =>
      'Ticked members also get team messages over SimpleX/Tor when they are out of radio and Bluetooth range.';

  @override
  String get members => 'Members';

  @override
  String get teamQr => 'Team QR';

  @override
  String unknownSender(String fp) {
    return 'unknown $fp';
  }

  @override
  String get teamMessage => 'Team message';

  @override
  String get noBtPermissionRadio =>
      'Without the Bluetooth permission I cannot connect to the radio.';

  @override
  String get commonEcpChannel => 'Common ECP channel.';

  @override
  String get groupChannelSet => 'Group channel set.';

  @override
  String radioRejectedChannel(String e) {
    return 'The radio did not accept the channel: $e';
  }

  @override
  String get meshcoreRadioPaired =>
      'MeshCore radio (paired in Bluetooth settings)';

  @override
  String get noPairedDevice =>
      'No paired device. Pair the radio in Bluetooth settings (PIN from the radio\'s display).';

  @override
  String get forgetRadio => 'Disconnect and forget the radio';

  @override
  String get loraUnavailable => 'LoRa: unavailable';

  @override
  String firmwareInfo(String version, int channels) {
    return 'Firmware $version · $channels channels';
  }

  @override
  String pathHash(int bytes) {
    return ' · path hash $bytes B';
  }

  @override
  String get loraChannel => 'LoRa channel';

  @override
  String get commonChannelHelp =>
      'Common ECP channel. The app ignores the public and hashtag channels.';

  @override
  String get privateChannelHelp =>
      'Private group channel. Share the key in person only.';

  @override
  String get newGroupChannel => 'New group channel';

  @override
  String get copyKey => 'Copy key';

  @override
  String get backToEcpChannel => 'Back to the ECP channel';

  @override
  String get groupKeyPaste => 'Group channel key (paste)';

  @override
  String get invalidChannelKey => 'Invalid channel key.';

  @override
  String get layerAlternate => 'Tor / Bramble (also LAN and Bluetooth)';

  @override
  String get layerContingency => 'LoRa (MeshCore)';

  @override
  String get cz => 'Czechia';

  @override
  String get sk => 'Slovakia';

  @override
  String get pl => 'Poland';

  @override
  String get de => 'Germany';

  @override
  String get at => 'Austria';

  @override
  String get hu => 'Hungary';

  @override
  String get ua => 'Ukraine';

  @override
  String get uk => 'United Kingdom';

  @override
  String get us => 'USA / Canada';

  @override
  String get numberRemoved => 'Number removed.';

  @override
  String get numberSaved => 'Saved. Contacts get the new number by themselves.';

  @override
  String get confirm => 'Confirm';

  @override
  String get duressOptional => 'Duress code (optional)';

  @override
  String get renameDecoyHelp =>
      'With the duress code the empty profile is renamed too, so it shows the same name under duress.';

  @override
  String get nicknameChanged => 'Nickname changed.';

  @override
  String get changePin => 'Change PIN';

  @override
  String get currentPin => 'Current PIN';

  @override
  String get newPin => 'New PIN';

  @override
  String get newPinAgain => 'New PIN again';

  @override
  String get newPinsMismatch => 'The new PINs do not match.';

  @override
  String get pinChanged => 'PIN changed.';

  @override
  String get removeDuress => 'Remove duress code';

  @override
  String get removeDuressNote =>
      'The empty profile and its content disappear; under duress there is then nowhere to retreat to.';

  @override
  String get newDuress => 'New duress code';

  @override
  String get newDuressAgain => 'New duress code again';

  @override
  String get newDuressNote =>
      'A new empty profile with the same nickname is created; the old one and its content disappear.';

  @override
  String get duressCodesMismatch => 'The duress codes do not match.';

  @override
  String get duressRemoved => 'Duress code removed.';

  @override
  String get duressSet => 'Duress code set.';

  @override
  String get profile => 'Profile';

  @override
  String get nicknameOnCard => 'Nickname on your card';

  @override
  String get smsNumberLayer => 'SMS number (layer E)';

  @override
  String get number => 'Number';

  @override
  String get simChangeHelp =>
      'When the SIM changes (local operator), enter the new number: the QR is renewed and contacts get it automatically. An empty field removes the number.';

  @override
  String get saveNumber => 'SAVE NUMBER';

  @override
  String get paceOrder => 'Channel order (PACE)';

  @override
  String get paceOrderHelp =>
      'A message goes over the first available channel from the top; without an acknowledgement in time it tries the next. Drag by ≡. SMS is always sent only after confirmation (or in an emergency).';

  @override
  String get paceDefault => 'Default order (SimpleX → Tor → LoRa → SMS)';

  @override
  String get security => 'Security';

  @override
  String get pinNotStored =>
      'The app stores neither the PIN nor the duress code, so they cannot be shown — only changed. A forgotten PIN cannot be recovered.';

  @override
  String get setNewDuress => 'Set a new duress code';

  @override
  String get emergencyLock => 'Emergency lock';

  @override
  String emergencyLockHelp(int taps) {
    return 'Tap anywhere $taps× quickly: the app locks and hides at once. Messages keep arriving in the background.';
  }

  @override
  String get lockAndHide => 'LOCK AND HIDE';

  @override
  String get reconnect => 'Reconnect';

  @override
  String reconnectOne(String channel) {
    return 'Reconnect $channel';
  }

  @override
  String get reconnectAll => 'Reconnect all';

  @override
  String get loraRadioShort => 'LoRa radio';

  @override
  String get language => 'Language';

  @override
  String get about => 'About';

  @override
  String get stOk => 'OK';

  @override
  String get stNeedHelp => 'Need help';

  @override
  String get stCompromised => 'Compromised';

  @override
  String get stInjured => 'Injured';

  @override
  String get stMoving => 'Moving';

  @override
  String get stInPosition => 'In position';

  @override
  String get sitrepStates => 'Quiet|Caution / watched|Contact|Emergency';

  @override
  String get medevacPrecedence =>
      'A urgent|B urgent-surgical|C priority|D routine|E convenience';

  @override
  String get medevacEquipment => 'none|hoist|extraction equipment|ventilator';

  @override
  String get medevacSecurity =>
      'no enemy|possible enemy|enemy in area|enemy, armed escort needed';

  @override
  String get medevacMarking => 'panels|pyrotechnic|smoke|none|other';

  @override
  String get medevacNationality =>
      'own military|own civilian|non-own military|non-own civilian|prisoner';

  @override
  String get medevacTerrain =>
      'no contamination|nuclear (N)|biological (B)|chemical (C)';

  @override
  String get rPosition => 'POSITION';

  @override
  String get rStatus => 'STATUS';

  @override
  String get rRally => 'RALLY';

  @override
  String get rSitrep => 'SITREP';

  @override
  String get rMedevac => 'MEDEVAC 9-line';

  @override
  String get rSalter => 'SALTER';

  @override
  String get r5w => '5W';

  @override
  String timeLine(String t) {
    return 'Time: $t';
  }

  @override
  String personsLine(int n) {
    return 'Persons: $n';
  }

  @override
  String mLine2(String v) {
    return '2 callsign: $v';
  }

  @override
  String mLine3(String v) {
    return '3 patients: $v';
  }

  @override
  String mLine4(String v) {
    return '4 equipment: $v';
  }

  @override
  String mLine5(int l, int a) {
    return '5 litter $l, ambulatory $a';
  }

  @override
  String mLine6(String v) {
    return '6 security: $v';
  }

  @override
  String mLine7(String v) {
    return '7 marking: $v';
  }

  @override
  String mLine8(String v) {
    return '8 nationality: $v';
  }

  @override
  String mLine9(String v) {
    return '9 terrain/NBC: $v';
  }

  @override
  String sSize(int v) {
    return 'S size: $v';
  }

  @override
  String sActivity(String v) {
    return 'A activity: $v';
  }

  @override
  String sTime(String v) {
    return 'T time: $v';
  }

  @override
  String sEquipment(String v) {
    return 'E equipment: $v';
  }

  @override
  String sRemarks(String v) {
    return 'R remarks: $v';
  }

  @override
  String wWho(String v) {
    return 'Who: $v';
  }

  @override
  String wWhat(String v) {
    return 'What: $v';
  }

  @override
  String wWhen(String v) {
    return 'When: $v';
  }

  @override
  String wWhy(String v) {
    return 'Why: $v';
  }

  @override
  String get reportUnreadable => '(report cannot be read)';

  @override
  String accuracy(int m) {
    return 'accuracy ±$m m';
  }

  @override
  String get distanceFindMe => 'Distance and bearing: get my position';

  @override
  String distanceBearing(String d, String b) {
    return '$d · bearing $b';
  }

  @override
  String get map => 'Map';

  @override
  String get noMapApp =>
      'No map app. I suggest OsmAnd or Organic Maps from F-Droid (offline).';

  @override
  String get coordinates => 'Coordinates';

  @override
  String get coordsCopied => 'Coordinates copied.';

  @override
  String get persons => 'persons';

  @override
  String get reports => 'REPORTS';

  @override
  String get myPosition => 'My position';

  @override
  String get statusSub => 'OK, help, injured… and a RALLY point';

  @override
  String get sitrepSub => 'state, persons, short text';

  @override
  String get salterSub =>
      'observation: size, activity, location, time, equipment, remarks';

  @override
  String get fiveWSub => 'who, what, where, when, why';

  @override
  String get positionCaps => 'POSITION';

  @override
  String get gettingGps => 'Getting the position from GPS…';

  @override
  String get coordsLabel => 'Coordinates (e.g. 50.0880, 14.4208)';

  @override
  String get coordsNotUnderstood => 'I do not understand these coordinates.';

  @override
  String get myPositionGps => 'My position (GPS)';

  @override
  String get enterManually => 'Enter manually';

  @override
  String get sendCaps => 'SEND';

  @override
  String get attachPosition => 'Attach position';

  @override
  String rallyTime(String t) {
    return 'Rally time: $t';
  }

  @override
  String inMinutes(int n) {
    return 'in $n min';
  }

  @override
  String inHours(int n) {
    return 'in $n h';
  }

  @override
  String get dateAndTime => 'date and time';

  @override
  String get stateCaps => 'STATE';

  @override
  String get personCount => 'Number of persons';

  @override
  String get shortText => 'Short text';

  @override
  String get tooLongSms => 'Too long — it must fit one SMS.';

  @override
  String get tooLongLora =>
      'Texts too long together — they must fit one LoRa packet.';

  @override
  String get pickupSite => '1  PICKUP SITE';

  @override
  String get callsignLabel => '2  Callsign (max. 8 characters, ASCII)';

  @override
  String get callsignError => 'Max. 8 characters, ASCII only.';

  @override
  String get patientsCaps => '3  PATIENTS BY PRECEDENCE';

  @override
  String get line4 => '4  Special equipment';

  @override
  String get line5Litter => '5  Litter';

  @override
  String get line5Ambulatory => '5  Ambulatory';

  @override
  String get line6 => '6  Security at pickup site';

  @override
  String get line7 => '7  Marking of pickup site';

  @override
  String get line8 => '8  Nationality / status';

  @override
  String get line9 => '9  Terrain / contamination';

  @override
  String get salterSize => 'S  Size (persons, vehicles…)';

  @override
  String get salterActivity => 'A  Activity';

  @override
  String get salterLocation => 'L  LOCATION';

  @override
  String salterTime(String t) {
    return 'T  Time observed: $t';
  }

  @override
  String get salterEquipment => 'E  Equipment';

  @override
  String get salterRemarks => 'R  Remarks';

  @override
  String get fwWho => 'Who';

  @override
  String get fwWhat => 'What';

  @override
  String get fwWhere => 'WHERE';

  @override
  String fwWhen(String t) {
    return 'When: $t';
  }

  @override
  String get fwWhy => 'Why';

  @override
  String get now => 'now';

  @override
  String textBudget(int n, int max) {
    return '$n / $max B';
  }

  @override
  String stSimplex(String s) {
    return 'SimpleX: $s';
  }

  @override
  String get active => 'active';

  @override
  String get unavailable => 'unavailable';

  @override
  String stBramble(String s) {
    return 'Bramble: $s';
  }

  @override
  String get waitingNetwork => 'waiting for network';

  @override
  String stSquad(int n) {
    return 'Squad net: $n in range';
  }

  @override
  String get smsNoSim => 'SMS: no SIM';

  @override
  String get smsNotAllowed => 'SMS: not allowed';

  @override
  String get smsReady => 'SMS: ready (only after confirmation)';

  @override
  String get loraNotConnected => 'LoRa: radio not connected';

  @override
  String get loraError => 'LoRa: radio error';

  @override
  String get locNoPermission => 'No location permission.';

  @override
  String get locOff => 'Location is off on the phone.';

  @override
  String get locTimeout =>
      'GPS has no fix yet — try outside or enter coordinates.';

  @override
  String get locFailed => 'Could not get the position.';

  @override
  String get invalidContactLink => 'Invalid contact link.';

  @override
  String get ownContact => 'That is your own contact.';

  @override
  String teamOf(String name) {
    return 'Team $name';
  }

  @override
  String get rcConnectingRelays => 'connecting to relays';

  @override
  String get rcError => 'error';

  @override
  String get rcNotRunning => 'not running';

  @override
  String get rcRunning => 'running';

  @override
  String get rcStarting => 'starting';

  @override
  String get rcBtInactive => 'inactive (turn Bluetooth on)';

  @override
  String get rcBrambleNotRunning => 'Bramble not running';

  @override
  String get rcNoRadio => 'no radio';

  @override
  String get rcConnectingRadio => 'connecting the radio';

  @override
  String stLora(String s) {
    return 'LoRa: $s';
  }

  @override
  String get panicButton => 'PANIC';

  @override
  String get compromiseButton => 'COMPROMISED';

  @override
  String get confirmCompromise =>
      'CONFIRM: COMPROMISED\nsend and destroy the profile';

  @override
  String get panicSending => 'Sending…';

  @override
  String get panicFailed => 'PANIC could not be sent.';

  @override
  String panicSent(int c, int t) {
    return 'PANIC sent: $c contacts, $t teams';
  }

  @override
  String get panicTitle => 'PANIC AND COMPROMISED';

  @override
  String get panicHelp =>
      'The buttons on the PIN screen work without the PIN while the app runs behind the lock. PANIC goes out at once over every channel, SMS without confirmation.';

  @override
  String get panicButtonOn => 'PANIC button';

  @override
  String get panicStatus => 'Status PANIC sends';

  @override
  String get panicText => 'Own message (optional)';

  @override
  String get panicToContacts => 'To all contacts';

  @override
  String get panicToTeams => 'To all teams';

  @override
  String get compromiseOn => 'COMPROMISED button';

  @override
  String get compromiseHelp =>
      'Sends the Compromised status to the same recipients, then destroys this profile just as the duress code does. Confirmed with a second button at the top of the screen. The duress code then opens the decoy; without a duress code nothing opens the app any more.';

  @override
  String get renameTeam => 'Rename team';

  @override
  String get noInternet => 'no internet';

  @override
  String get secSecurity => 'Security';

  @override
  String get secSecuritySub => 'PIN, duress code, locking, fingerprint, PANIC';

  @override
  String get secConnectivity => 'Connectivity';

  @override
  String get secConnectivitySub =>
      'SMS number, PACE order, reconnecting, LoRa radio';

  @override
  String get secApp => 'App';

  @override
  String get secAppSub => 'Nickname, language, factory reset';

  @override
  String get pinCodes => 'PIN and duress code';

  @override
  String get lockTitle => 'Locking';

  @override
  String get lockAfter => 'Lock after leaving the app';

  @override
  String get lockNow => 'At once';

  @override
  String lockMinutes(int n) {
    return 'After $n min';
  }

  @override
  String get lockManual => 'Only by hand (4 taps)';

  @override
  String get lockHelp =>
      'After restarting the phone or the app the PIN is always needed.';

  @override
  String get quickLockNeeded => 'Must stay on while locking is by hand only.';

  @override
  String get bioTitle => 'Unlock with fingerprint';

  @override
  String bioHelp(int h) {
    return 'Only to return to the running profile. The PIN is needed after a restart, after the emergency lock and $h h after it was last typed. A fingerprint has no duress code.';
  }

  @override
  String get bioNeedsPanic =>
      'Needs both the PANIC and the COMPROMISED button on.';

  @override
  String get bioUnavailable => 'No fingerprint is set up on this phone.';

  @override
  String get bioLocksPanic => 'Must stay on while the fingerprint unlocks.';

  @override
  String get bioPrompt => 'Unlock L0ck-ECP';

  @override
  String get bioUsePin => 'Use PIN';

  @override
  String get bioButton => 'Fingerprint';

  @override
  String get chConnected => 'CONNECTED';

  @override
  String get chNoLink => 'NO LINK';

  @override
  String get reportButton => 'Reports';

  @override
  String get sendTo => 'Send to';

  @override
  String get selectAll => 'Select all';

  @override
  String sendToN(int n) {
    return 'SEND ($n)';
  }

  @override
  String sentToN(int n) {
    return 'Sent to $n recipients';
  }

  @override
  String get noRecipients => 'No contacts or teams yet.';

  @override
  String get groupBundle => 'Group bundle';

  @override
  String get groupLoad => 'Load group bundle';

  @override
  String get groupHelp =>
      'The base laptop shows the bundle as a series of QR codes. Scan them all, in any order. The phone then gets the whole group\'s contacts, its teams, the LoRa channel and the PACE order.';

  @override
  String get groupScan => 'SCAN QR';

  @override
  String groupProgress(int have, int total) {
    return '$have of $total QR codes read';
  }

  @override
  String groupPrompt(int i, int total) {
    return 'Group bundle: QR $i of $total';
  }

  @override
  String get groupPromptFirst => 'Group bundle: any QR code';

  @override
  String get groupNotPart => 'This is not a group bundle QR code.';

  @override
  String get groupOther => 'This QR code belongs to another bundle.';

  @override
  String get groupBroken => 'The bundle is damaged. Scan it again.';

  @override
  String get groupNotMember =>
      'This phone is not in the bundle. Scan its contact QR on the laptop first.';

  @override
  String groupContacts(int n) {
    return 'Contacts ($n)';
  }

  @override
  String get groupTeamsFor => 'This phone\'s teams';

  @override
  String get groupNoTeams => 'none';

  @override
  String groupLora(String team) {
    return 'LoRa radio: channel of team $team';
  }

  @override
  String groupPace(String order) {
    return 'PACE order: $order';
  }

  @override
  String get groupApply => 'SET UP THIS PHONE';

  @override
  String groupDone(int added, int changed, int same, int teams) {
    return 'Done. Contacts: $added new, $changed changed, $same unchanged. New teams: $teams.';
  }

  @override
  String get groupAgain => 'Start over';

  @override
  String get factoryReset => 'Factory reset';

  @override
  String get factoryResetHelp =>
      'Erases the profile and the decoy, contacts, teams, messages, keys and settings on this phone. The app then starts again as after installing. Nothing is sent to contacts. It cannot be undone.';

  @override
  String get factoryResetButton => 'FACTORY RESET';

  @override
  String get factoryResetAsk => 'Really erase everything?';

  @override
  String get factoryResetConfirm => 'ERASE ALL';

  @override
  String groupWorking(int done, int total) {
    return 'Setting up… contacts $done of $total';
  }

  @override
  String groupFailed(String error) {
    return 'Setup failed: $error';
  }

  @override
  String groupOwnPhone(String phone) {
    return 'Your SMS number: $phone';
  }

  @override
  String get groupNoChange =>
      'Done. The phone already matches the bundle; nothing changed.';

  @override
  String voiceMessage(String length) {
    return 'Voice message $length';
  }

  @override
  String get voiceRecord => 'Voice message';

  @override
  String get voiceNoChannel =>
      'A voice message needs SimpleX or Bramble (internet, Wi-Fi or Bluetooth). LoRa and SMS cannot carry it.';

  @override
  String get voiceRecording => 'Recording';

  @override
  String get voiceAtLimit => '30 s at most: recording stopped';

  @override
  String get voiceDiscard => 'Discard';

  @override
  String get voiceMicDenied => 'Recording needs access to the microphone.';

  @override
  String get voiceFailed => 'Recording failed.';

  @override
  String get voicePlayFailed => 'The message cannot be played.';

  @override
  String get callAction => 'Call';

  @override
  String get callNoChannel =>
      'A call needs SimpleX or Bramble, and the internet or a shared Wi-Fi.';

  @override
  String get callCalling => 'Calling…';

  @override
  String get callIncoming => 'Incoming call';

  @override
  String get callConnecting => 'Connecting…';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callDeclinedEnd => 'Call declined';

  @override
  String get callBusy => 'Busy';

  @override
  String get callNoAnswer => 'No answer';

  @override
  String get callFailedEnd => 'The connection failed';

  @override
  String get callAccept => 'Accept';

  @override
  String get callDecline => 'Decline';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callMute => 'Mute';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String get callDirect => 'Encrypted · direct';

  @override
  String get callRelayed => 'Encrypted · via a SimpleX relay';

  @override
  String get callEncrypted => 'Encrypted (DTLS-SRTP)';

  @override
  String logOut(String length) {
    return 'Outgoing call $length';
  }

  @override
  String logIn(String length) {
    return 'Incoming call $length';
  }

  @override
  String get logMissedIn => 'Missed call';

  @override
  String get logMissedOut => 'Not answered';

  @override
  String get logDeclined => 'Declined call';

  @override
  String get logFailed => 'Call failed';

  @override
  String get attachPhoto => 'Take a photo';

  @override
  String get attachPhotoSub =>
      'Reduced, without location or camera details (EXIF)';

  @override
  String get attachFile => 'File';

  @override
  String get attachFileSub => '512 kB at most';

  @override
  String get attachNoChannel =>
      'Photos and files need SimpleX or Bramble (internet or Wi-Fi), not Bluetooth, LoRa or SMS.';

  @override
  String attachTooBig(String size) {
    return 'The file is $size; 512 kB at most can be sent.';
  }

  @override
  String attachSending(String size) {
    return 'Sending ($size)…';
  }

  @override
  String get attachCamDenied => 'Taking photos needs access to the camera.';

  @override
  String get attachFailed => 'The attachment could not be read.';

  @override
  String get photoLabel => 'Photo';

  @override
  String fileLabel(String name, String size) {
    return 'File $name ($size)';
  }

  @override
  String get fileSaved => 'Saved.';

  @override
  String get fileSaveFailed => 'Saving failed.';

  @override
  String get attachments => 'ATTACHMENTS';

  @override
  String get contactInfo => 'Contact info';

  @override
  String get clearChat => 'Clear chat';

  @override
  String get clearChatAsk => 'Clear the chat?';

  @override
  String get clearChatText =>
      'Deletes this chat\'s messages, reports, voice messages and attachments on this phone only. The contact or team stays.';

  @override
  String get chatCleared => 'Chat cleared.';

  @override
  String get statusWithRally => 'Add a RALLY point (place and time)';

  @override
  String get rallyPlace => 'Rally point';
}
