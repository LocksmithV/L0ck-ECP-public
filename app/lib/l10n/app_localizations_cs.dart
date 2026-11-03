// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get aboutTitle => 'O aplikaci';

  @override
  String get aboutTagline =>
      'Platforma pro koordinaci v nouzi — šifrovaná komunikace přes více cest (PACE): SimpleX, Tor, LoRa, SMS a síť skupiny přes Bluetooth/Wi-Fi.';

  @override
  String aboutVersion(String version) {
    return 'Verze $version';
  }

  @override
  String get aboutAuthor => 'Autor';

  @override
  String get aboutWeb => 'Web';

  @override
  String get aboutLicense => 'Licence';

  @override
  String get aboutLicenseText =>
      'GNU AGPLv3 — svobodný software; zdrojový kód je k dispozici podle licence.';

  @override
  String get aboutThirdParty => 'Použité součásti';

  @override
  String get aboutThirdPartyText =>
      'Briar/Bramble (GPLv3) · SimpleX Chat core (AGPLv3) · Tor (BSD) · MeshCore protokol (MIT) · ZXing (Apache 2.0) · SQLCipher (BSD) · libsodium (ISC) · Flutter (BSD)';

  @override
  String get aboutDisclaimer => 'Upozornění';

  @override
  String get aboutDisclaimerText =>
      'L0ck-ECP je nástroj pro bezpečnou komunikaci a koordinaci v nouzových situacích. Není určen k porušování zákonů ani k jiné nezákonné činnosti.\n\nUživatel sám odpovídá za to, že aplikaci používá v souladu s právními předpisy země, kde se nachází — mimo jiné o šifrování, elektronických komunikacích a rádiovém vysílání (kmitočty, výkon a střída vysílání LoRa).\n\nSoftware je poskytován „tak, jak je“, bez jakékoli záruky. Autor nenese odpovědnost za škody, ztrátu dat, nedoručené zprávy ani jiné následky použití aplikace. Nespoléhej na ni jako na jediný prostředek k přivolání pomoci.';

  @override
  String get openFailed => 'Odkaz nejde otevřít (žádný prohlížeč).';

  @override
  String get wrongCode => 'Nesprávný kód.';

  @override
  String get pin => 'PIN';

  @override
  String get verifying => 'Ověřuji…';

  @override
  String retryIn(int secs) {
    return 'Zkus znovu za $secs s';
  }

  @override
  String get unlock => 'Odemknout';

  @override
  String get nicknameLength => 'Přezdívka 1–24 znaků.';

  @override
  String pinError(String error) {
    return 'PIN: $error';
  }

  @override
  String get pinMismatch => 'PIN se neshoduje.';

  @override
  String duressError(String error) {
    return 'Duress kód: $error';
  }

  @override
  String get duressMismatch => 'Duress kód se neshoduje.';

  @override
  String get duressSameAsPin => 'Duress kód musí být jiný než PIN.';

  @override
  String setupFailed(String error) {
    return 'Nastavení selhalo: $error';
  }

  @override
  String get firstRun => 'První spuštění';

  @override
  String get nickname => 'Přezdívka';

  @override
  String get pinDigits => 'PIN (6–12 číslic)';

  @override
  String get pinAgain => 'PIN znovu';

  @override
  String get duressCode => 'Duress kód';

  @override
  String get duressExplain =>
      'Pod nátlakem zadej místo PINu: otevře prázdný profil a skutečná data nevratně zničí.';

  @override
  String get duressDigits => 'Duress kód (6–12 číslic)';

  @override
  String get duressAgain => 'Duress kód znovu';

  @override
  String get generatingKeys => 'Generuji klíče…';

  @override
  String get create => 'Vytvořit';

  @override
  String pinRuleEnter(int min, int max) {
    return 'Zadej $min–$max číslic.';
  }

  @override
  String get pinRuleDigits => 'Jen číslice.';

  @override
  String pinRuleMin(int min) {
    return 'Nejméně $min číslic.';
  }

  @override
  String pinRuleMax(int max) {
    return 'Nejvýše $max číslic.';
  }

  @override
  String get currentCodeWrong => 'Současný kód nesedí.';

  @override
  String get codeInUse => 'Tento kód už se používá.';

  @override
  String get duressMustDiffer => 'Duress kód se musí lišit od PINu.';

  @override
  String get enterNickname => 'Zadej přezdívku.';

  @override
  String get duressWrong => 'Duress kód nesedí.';

  @override
  String get newMessages => 'Nové zprávy';

  @override
  String get directMessage => 'přímá zpráva';

  @override
  String get team => 'tým';

  @override
  String get contacts => 'Kontakty';

  @override
  String get teams => 'Týmy';

  @override
  String get loraRadio => 'Rádio LoRa';

  @override
  String get settings => 'Nastavení';

  @override
  String get identity => 'Identita';

  @override
  String fingerprint(String fp) {
    return 'Otisk: $fp';
  }

  @override
  String smsNumber(String number) {
    return 'SMS číslo: $number';
  }

  @override
  String get notSet => 'nenastaveno';

  @override
  String get channels => 'Kanály';

  @override
  String get noChannel => 'Žádný kanál';

  @override
  String get myContact => 'Můj kontakt';

  @override
  String get copyMyLink => 'Kopírovat můj odkaz';

  @override
  String get linkCopied => 'Odkaz zkopírován. Po vložení schránku vymaž.';

  @override
  String get showInPersonOnly => 'Ukazuj jen osobně.';

  @override
  String contactsButton(String count) {
    return 'KONTAKTY ($count)';
  }

  @override
  String get add => 'Přidat';

  @override
  String get noContactsYet => 'Zatím žádné kontakty.';

  @override
  String get verifiedInPerson => 'ověřeno osobně';

  @override
  String get notVerified => 'neověřeno';

  @override
  String get openConversation => 'Otevřít konverzaci';

  @override
  String get contactDetailMenu =>
      'Detail: ověření, kanály, QR, Bluetooth, smazat';

  @override
  String contactAndTeam(String contact, String team) {
    return '$contact a tým $team';
  }

  @override
  String get addContact => 'Přidat kontakt';

  @override
  String get contactLinkLabel => 'Odkaz kontaktu (l0ck://c/…)';

  @override
  String contactUpdated(String name) {
    return 'Kontakt $name aktualizován (nové kanály z karty).';
  }

  @override
  String get load => 'Načíst';

  @override
  String get scanQr => 'Skenovat QR kontaktu nebo týmu';

  @override
  String get scanPrompt => 'Namiř na QR druhého telefonu';

  @override
  String joinedTeam(String team) {
    return 'Připojen k týmu $team. Rádio LoRa přepnuto na kanál týmu.';
  }

  @override
  String get verificationNumber => 'Ověřovací číslo';

  @override
  String get verificationExplain =>
      'Porovnej ho osobně s číslem na telefonu kontaktu. Shodné číslo znamená, že nikdo nepodstrčil cizí klíč.';

  @override
  String get numbersMatch => 'Čísla se shodují (ověřeno osobně)';

  @override
  String get done => 'Hotovo';

  @override
  String get contact => 'Kontakt';

  @override
  String get reportsAndPosition => 'Hlášení a poloha';

  @override
  String get message => 'Zpráva';

  @override
  String get send => 'Odeslat';

  @override
  String get renameContact => 'Přejmenovat kontakt';

  @override
  String get cancel => 'Zrušit';

  @override
  String get save => 'Uložit';

  @override
  String deleteContactQ(String name) {
    return 'Smazat $name?';
  }

  @override
  String get deleteContactText =>
      'Smaže kontakt, jeho klíče a celou konverzaci. Nejde vrátit; pro nové spojení je třeba znovu naskenovat jeho QR.';

  @override
  String get delete => 'Smazat';

  @override
  String get brambleNotRunning => 'Bramble neběží.';

  @override
  String get needNearbyPermission =>
      'Bez oprávnění „Zařízení v okolí“ to nejde.';

  @override
  String get makingVisible => 'Zviditelňuji telefon…';

  @override
  String get noVisibility => 'Bez viditelnosti se telefony nenajdou.';

  @override
  String get searchingBt => 'Hledám kontakt přes Bluetooth (až 30 s)…';

  @override
  String get btConnected =>
      'Spojeno přes Bluetooth. Příště se telefony najdou samy.';

  @override
  String get btNoUuid =>
      'Kontakt ještě nebyl spojen jinou cestou (Tor/LAN) — zkus znovu později.';

  @override
  String get btNotFound =>
      'Nenalezen. Ať kontakt současně udělá totéž, telefony blízko sebe.';

  @override
  String get btNotBramble => 'Kontakt zatím není spojený přes Bramble.';

  @override
  String btUnavailable(String state) {
    return 'Bluetooth v Bramble nenaběhl ($state). Zkus vypnout a zapnout Bluetooth v telefonu.';
  }

  @override
  String unexpectedResult(String r) {
    return 'Nečekaný výsledek: $r';
  }

  @override
  String get rename => 'Přejmenovat';

  @override
  String get verification => 'Ověření';

  @override
  String get verifiedInPersonDot => 'Ověřeno osobně.';

  @override
  String get notVerifiedExplain =>
      'Neověřeno. Porovnej číslo s telefonem kontaktu — shodné číslo znamená, že nikdo nepodstrčil cizí klíč.';

  @override
  String get unverify => 'Zrušit ověření';

  @override
  String get markVerified => 'Čísla se shodují — označit ověřeno';

  @override
  String get missingOnCard => 'chybí na kartě';

  @override
  String get connected => 'spojeno';

  @override
  String get connecting => 'spojuje se…';

  @override
  String get contactNoLink => 'kontakt, teď bez spojení';

  @override
  String linksNow(String links) {
    return 'teď: $links';
  }

  @override
  String get noPhone => 'číslo chybí';

  @override
  String get loraEveryone => 'kanál ECP / týmu (všichni v dosahu)';

  @override
  String get connectBluetooth => 'Spojit přes Bluetooth';

  @override
  String get connectBluetoothHelp =>
      'Poprvé musí oba telefony zároveň: zviditelní se a najdou se. Pak už se přes Bluetooth spojují samy (i bez Wi-Fi a dat).';

  @override
  String get contactCard => 'Karta kontaktu';

  @override
  String get theirCard => 'Jeho veřejná karta — předávej jen s jeho souhlasem.';

  @override
  String get deleteContact => 'Smazat kontakt';

  @override
  String get textCopied => 'Text zkopírován.';

  @override
  String get sendViaSms => 'Poslat přes SMS';

  @override
  String via(String via) {
    return 'přes $via';
  }

  @override
  String get nobodyInRange => 'nikdo v dosahu';

  @override
  String sentTeam(String via) {
    return 'odesláno: $via';
  }

  @override
  String get stSending => 'odesílám…';

  @override
  String stSent(String via) {
    return 'odesláno přes $via';
  }

  @override
  String stDelivered(String at, String via) {
    return 'doručeno$at · $via';
  }

  @override
  String stRead(String at) {
    return 'přečteno$at';
  }

  @override
  String get stWaiting => 'čeká na kanál';

  @override
  String get stConfirm => 'jen SMS — potvrď';

  @override
  String get stFailed => 'nedoručeno';

  @override
  String get squadNet => 'síť skupiny';

  @override
  String get newTeam => 'Nový tým';

  @override
  String get teamNameLocal => 'Název (jen u tebe)';

  @override
  String get found => 'Založit';

  @override
  String get teamDefaultName => 'Tým';

  @override
  String get noTeams =>
      'Zatím žádný tým.\n\nZaložit: „Nový tým“ a ukaž ostatním týmové QR.\nPřipojit se: v Kontaktech „Přidat“ a vlož odkaz z týmového QR člena.';

  @override
  String teamId(String id) {
    return 'ID $id';
  }

  @override
  String teamQrTitle(String team) {
    return 'Týmové QR — $team';
  }

  @override
  String get teamQrWarning =>
      'Ukazuj jen osobně a jen členům. Kdo QR vyfotí, čte týmovou komunikaci.';

  @override
  String get close => 'Zavřít';

  @override
  String leaveTeamQ(String team) {
    return 'Opustit $team?';
  }

  @override
  String get leaveTeamText =>
      'Členové dostanou zprávu, že odcházíš. Z tohoto telefonu zmizí tým, jeho zprávy i klíč; vrátit se jde jen novým naskenováním týmového QR.';

  @override
  String get leave => 'Opustit';

  @override
  String get leaveTeamMenu => 'Opustit a smazat tým';

  @override
  String get teamMembers => 'Členové týmu';

  @override
  String get teamMembersHelp =>
      'Zaškrtnutí dostanou týmové zprávy i přes SimpleX/Tor, když nejsou v dosahu rádia ani Bluetooth.';

  @override
  String get members => 'Členové';

  @override
  String get teamQr => 'Týmové QR';

  @override
  String unknownSender(String fp) {
    return 'neznámý $fp';
  }

  @override
  String get teamMessage => 'Zpráva týmu';

  @override
  String get noBtPermissionRadio =>
      'Bez oprávnění Bluetooth se k rádiu nepřipojím.';

  @override
  String get commonEcpChannel => 'Společný ECP kanál.';

  @override
  String get groupChannelSet => 'Kanál skupiny nastaven.';

  @override
  String radioRejectedChannel(String e) {
    return 'Rádio kanál nepřijalo: $e';
  }

  @override
  String get meshcoreRadioPaired =>
      'Rádio MeshCore (spárované v nastavení Bluetooth)';

  @override
  String get noPairedDevice =>
      'Žádné spárované zařízení. Spáruj rádio v nastavení Bluetooth (PIN z displeje rádia).';

  @override
  String get forgetRadio => 'Odpojit a zapomenout rádio';

  @override
  String get loraUnavailable => 'LoRa: nedostupné';

  @override
  String firmwareInfo(String version, int channels) {
    return 'Firmware $version · $channels kanálů';
  }

  @override
  String pathHash(int bytes) {
    return ' · hash cesty $bytes B';
  }

  @override
  String get loraChannel => 'Kanál LoRa';

  @override
  String get commonChannelHelp =>
      'Společný ECP kanál. Veřejný a hashtag kanály aplikace ignoruje.';

  @override
  String get privateChannelHelp =>
      'Soukromý kanál skupiny. Klíč sdílej jen osobně.';

  @override
  String get newGroupChannel => 'Nový kanál skupiny';

  @override
  String get copyKey => 'Kopírovat klíč';

  @override
  String get backToEcpChannel => 'Zpět na ECP kanál';

  @override
  String get groupKeyPaste => 'Klíč kanálu skupiny (vložit)';

  @override
  String get invalidChannelKey => 'Neplatný klíč kanálu.';

  @override
  String get layerAlternate => 'Tor / Bramble (i LAN a Bluetooth)';

  @override
  String get layerContingency => 'LoRa (MeshCore)';

  @override
  String get cz => 'Česko';

  @override
  String get sk => 'Slovensko';

  @override
  String get pl => 'Polsko';

  @override
  String get de => 'Německo';

  @override
  String get at => 'Rakousko';

  @override
  String get hu => 'Maďarsko';

  @override
  String get ua => 'Ukrajina';

  @override
  String get uk => 'Spojené království';

  @override
  String get us => 'USA / Kanada';

  @override
  String get numberRemoved => 'Číslo odebráno.';

  @override
  String get numberSaved => 'Uloženo. Kontakty dostanou nové číslo samy.';

  @override
  String get confirm => 'Potvrdit';

  @override
  String get duressOptional => 'Duress kód (nepovinné)';

  @override
  String get renameDecoyHelp =>
      'S duress kódem se přejmenuje i prázdný profil, aby pod nátlakem ukázal stejné jméno.';

  @override
  String get nicknameChanged => 'Přezdívka změněna.';

  @override
  String get changePin => 'Změnit PIN';

  @override
  String get currentPin => 'Současný PIN';

  @override
  String get newPin => 'Nový PIN';

  @override
  String get newPinAgain => 'Nový PIN znovu';

  @override
  String get newPinsMismatch => 'Nové PINy se neshodují.';

  @override
  String get pinChanged => 'PIN změněn.';

  @override
  String get removeDuress => 'Zrušit duress kód';

  @override
  String get removeDuressNote =>
      'Prázdný profil i s obsahem zmizí; pod nátlakem pak nebude kam uhnout.';

  @override
  String get newDuress => 'Nový duress kód';

  @override
  String get newDuressAgain => 'Nový duress kód znovu';

  @override
  String get newDuressNote =>
      'Vznikne nový prázdný profil se stejnou přezdívkou; ten starý i s obsahem zmizí.';

  @override
  String get duressCodesMismatch => 'Duress kódy se neshodují.';

  @override
  String get duressRemoved => 'Duress kód zrušen.';

  @override
  String get duressSet => 'Duress kód nastaven.';

  @override
  String get profile => 'Profil';

  @override
  String get nicknameOnCard => 'Přezdívka na tvé kartě';

  @override
  String get smsNumberLayer => 'SMS číslo (vrstva E)';

  @override
  String get number => 'Číslo';

  @override
  String get simChangeHelp =>
      'Při změně SIM (místní operátor) zadej nové číslo: QR se obnoví a kontakty ho dostanou automaticky. Prázdné pole číslo odebere.';

  @override
  String get saveNumber => 'ULOŽIT ČÍSLO';

  @override
  String get paceOrder => 'Pořadí kanálů (PACE)';

  @override
  String get paceOrderHelp =>
      'Zpráva jde nejdřív prvním dostupným kanálem shora; bez potvrzení v limitu zkusí další. Přetáhni za ≡. SMS se vždy posílá jen po potvrzení (nebo v nouzi).';

  @override
  String get paceDefault => 'Výchozí pořadí (SimpleX → Tor → LoRa → SMS)';

  @override
  String get security => 'Zabezpečení';

  @override
  String get pinNotStored =>
      'PIN ani duress kód aplikace neukládá, proto je nejde zobrazit — jen změnit. Zapomenutý PIN nejde obnovit.';

  @override
  String get setNewDuress => 'Nastavit nový duress kód';

  @override
  String get emergencyLock => 'Nouzové zamknutí';

  @override
  String emergencyLockHelp(int taps) {
    return '$taps× rychle klepni kamkoli na obrazovku: aplikace se okamžitě zamkne a skryje. Zprávy dál chodí na pozadí.';
  }

  @override
  String get lockAndHide => 'ZAMKNOUT A SKRÝT';

  @override
  String get reconnect => 'Obnovit spojení';

  @override
  String reconnectOne(String channel) {
    return 'Obnovit $channel';
  }

  @override
  String get reconnectAll => 'Obnovit vše';

  @override
  String get loraRadioShort => 'LoRa rádio';

  @override
  String get language => 'Jazyk';

  @override
  String get about => 'O aplikaci';

  @override
  String get stOk => 'V pořádku';

  @override
  String get stNeedHelp => 'Potřebuji pomoc';

  @override
  String get stCompromised => 'Kompromitován';

  @override
  String get stInjured => 'Zraněn';

  @override
  String get stMoving => 'V pohybu';

  @override
  String get stInPosition => 'Na místě';

  @override
  String get sitrepStates => 'Klid|Pozor / sledování|Kontakt|Nouze';

  @override
  String get medevacPrecedence =>
      'A urgentní|B urgentní-chirurgický|C prioritní|D rutinní|E odložitelný';

  @override
  String get medevacEquipment =>
      'žádné|naviják|vyprošťovací technika|ventilátor';

  @override
  String get medevacSecurity =>
      'bez nepřítele|možný nepřítel|nepřítel v oblasti|nepřítel, nutný doprovod';

  @override
  String get medevacMarking => 'panely|pyrotechnika|kouř|žádné|jiné';

  @override
  String get medevacNationality =>
      'vlastní voják|vlastní civilista|cizí voják|cizí civilista|zajatec';

  @override
  String get medevacTerrain =>
      'bez kontaminace|jaderná (N)|biologická (B)|chemická (C)';

  @override
  String get rPosition => 'POLOHA';

  @override
  String get rStatus => 'STATUS';

  @override
  String get rRally => 'SRAZ';

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
    return 'Čas: $t';
  }

  @override
  String personsLine(int n) {
    return 'Osob: $n';
  }

  @override
  String mLine2(String v) {
    return '2 volací znak: $v';
  }

  @override
  String mLine3(String v) {
    return '3 pacienti: $v';
  }

  @override
  String mLine4(String v) {
    return '4 vybavení: $v';
  }

  @override
  String mLine5(int l, int a) {
    return '5 nosítka $l, chodící $a';
  }

  @override
  String mLine6(String v) {
    return '6 bezpečnost: $v';
  }

  @override
  String mLine7(String v) {
    return '7 značení: $v';
  }

  @override
  String mLine8(String v) {
    return '8 národnost: $v';
  }

  @override
  String mLine9(String v) {
    return '9 terén/NBC: $v';
  }

  @override
  String sSize(int v) {
    return 'S velikost: $v';
  }

  @override
  String sActivity(String v) {
    return 'A činnost: $v';
  }

  @override
  String sTime(String v) {
    return 'T čas: $v';
  }

  @override
  String sEquipment(String v) {
    return 'E vybavení: $v';
  }

  @override
  String sRemarks(String v) {
    return 'R poznámky: $v';
  }

  @override
  String wWho(String v) {
    return 'Kdo: $v';
  }

  @override
  String wWhat(String v) {
    return 'Co: $v';
  }

  @override
  String wWhen(String v) {
    return 'Kdy: $v';
  }

  @override
  String wWhy(String v) {
    return 'Proč: $v';
  }

  @override
  String get reportUnreadable => '(hlášení nejde přečíst)';

  @override
  String accuracy(int m) {
    return 'přesnost ±$m m';
  }

  @override
  String get distanceFindMe => 'Vzdálenost a směr: zjistit mou polohu';

  @override
  String distanceBearing(String d, String b) {
    return '$d · azimut $b';
  }

  @override
  String get map => 'Mapa';

  @override
  String get noMapApp =>
      'Žádná mapová aplikace. Doporučuji OsmAnd nebo Organic Maps z F-Droidu (offline).';

  @override
  String get coordinates => 'Souřadnice';

  @override
  String get coordsCopied => 'Souřadnice zkopírovány.';

  @override
  String get persons => 'osob';

  @override
  String get reports => 'HLÁŠENÍ';

  @override
  String get myPosition => 'Moje poloha';

  @override
  String get statusSub => 'v pořádku, pomoc, zraněn…';

  @override
  String get rallySub => 'místo a čas setkání';

  @override
  String get sitrepSub => 'stav, počet osob, krátký text';

  @override
  String get salterSub =>
      'pozorování: velikost, činnost, místo, čas, vybavení, poznámky';

  @override
  String get fiveWSub => 'kdo, co, kde, kdy, proč';

  @override
  String get positionCaps => 'POLOHA';

  @override
  String get gettingGps => 'Získávám polohu z GPS…';

  @override
  String get coordsLabel => 'Souřadnice (např. 50.0880, 14.4208)';

  @override
  String get coordsNotUnderstood => 'Nerozumím souřadnicím.';

  @override
  String get myPositionGps => 'Moje poloha (GPS)';

  @override
  String get enterManually => 'Zadat ručně';

  @override
  String get sendCaps => 'ODESLAT';

  @override
  String get attachPosition => 'Přiložit polohu';

  @override
  String rallyTime(String t) {
    return 'Čas srazu: $t';
  }

  @override
  String inMinutes(int n) {
    return 'za $n min';
  }

  @override
  String inHours(int n) {
    return 'za $n h';
  }

  @override
  String get dateAndTime => 'datum a čas';

  @override
  String get stateCaps => 'STAV';

  @override
  String get personCount => 'Počet osob';

  @override
  String get shortText => 'Krátký text';

  @override
  String get tooLongSms => 'Moc dlouhé — musí se vejít do jedné SMS.';

  @override
  String get tooLongLora =>
      'Texty dohromady moc dlouhé — musí se vejít do jednoho LoRa paketu.';

  @override
  String get pickupSite => '1  MÍSTO VYZVEDNUTÍ';

  @override
  String get callsignLabel => '2  Volací znak (max. 8 znaků bez diakritiky)';

  @override
  String get callsignError => 'Max. 8 znaků, bez diakritiky.';

  @override
  String get patientsCaps => '3  PACIENTI PODLE NALÉHAVOSTI';

  @override
  String get line4 => '4  Zvláštní vybavení';

  @override
  String get line5Litter => '5  Na nosítkách';

  @override
  String get line5Ambulatory => '5  Chodící';

  @override
  String get line6 => '6  Bezpečnost místa';

  @override
  String get line7 => '7  Značení místa';

  @override
  String get line8 => '8  Národnost / status';

  @override
  String get line9 => '9  Terén / kontaminace';

  @override
  String get salterSize => 'S  Velikost (počet osob, vozidel…)';

  @override
  String get salterActivity => 'A  Činnost';

  @override
  String get salterLocation => 'L  MÍSTO';

  @override
  String salterTime(String t) {
    return 'T  Čas pozorování: $t';
  }

  @override
  String get salterEquipment => 'E  Vybavení / výzbroj';

  @override
  String get salterRemarks => 'R  Poznámky';

  @override
  String get fwWho => 'Kdo';

  @override
  String get fwWhat => 'Co';

  @override
  String get fwWhere => 'KDE';

  @override
  String fwWhen(String t) {
    return 'Kdy: $t';
  }

  @override
  String get fwWhy => 'Proč';

  @override
  String get now => 'teď';

  @override
  String textBudget(int n, int max) {
    return '$n / $max B';
  }

  @override
  String stSimplex(String s) {
    return 'SimpleX: $s';
  }

  @override
  String get active => 'aktivní';

  @override
  String get unavailable => 'nedostupné';

  @override
  String stBramble(String s) {
    return 'Bramble: $s';
  }

  @override
  String get waitingNetwork => 'čeká na síť';

  @override
  String stSquad(int n) {
    return 'Síť skupiny: $n v dosahu';
  }

  @override
  String get smsNoSim => 'SMS: bez SIM';

  @override
  String get smsNotAllowed => 'SMS: nepovoleno';

  @override
  String get smsReady => 'SMS: připraveno (jen po potvrzení)';

  @override
  String get loraNotConnected => 'LoRa: rádio nepřipojeno';

  @override
  String get loraError => 'LoRa: chyba rádia';

  @override
  String get locNoPermission => 'Bez oprávnění k poloze.';

  @override
  String get locOff => 'Poloha je v telefonu vypnutá.';

  @override
  String get locTimeout =>
      'GPS zatím nemá fix — zkus venku nebo zadej souřadnice.';

  @override
  String get locFailed => 'Polohu se nepodařilo zjistit.';

  @override
  String get invalidContactLink => 'Neplatný odkaz kontaktu.';

  @override
  String get ownContact => 'To je tvůj vlastní kontakt.';

  @override
  String teamOf(String name) {
    return 'Tým $name';
  }

  @override
  String get rcConnectingRelays => 'připojuji k relé';

  @override
  String get rcError => 'chyba';

  @override
  String get rcNotRunning => 'neběží';

  @override
  String get rcRunning => 'běží';

  @override
  String get rcStarting => 'startuje';

  @override
  String get rcBtInactive => 'neaktivní (zapni Bluetooth)';

  @override
  String get rcBrambleNotRunning => 'Bramble neběží';

  @override
  String get rcNoRadio => 'bez rádia';

  @override
  String get rcConnectingRadio => 'připojuji rádio';

  @override
  String stLora(String s) {
    return 'LoRa: $s';
  }

  @override
  String get panicButton => 'PANIC';

  @override
  String get compromiseButton => 'KOMPROMITOVÁN';

  @override
  String get confirmCompromise =>
      'POTVRDIT: KOMPROMITOVÁN\nodeslat a smazat profil';

  @override
  String get panicSending => 'Odesílám…';

  @override
  String get panicFailed => 'PANIC se nepodařilo odeslat.';

  @override
  String panicSent(int c, int t) {
    return 'PANIC odeslán: $c kontaktům, $t týmům';
  }

  @override
  String get panicTitle => 'PANIC A KOMPROMITOVÁN';

  @override
  String get panicHelp =>
      'Tlačítka na obrazovce PINu fungují bez PINu, dokud aplikace běží za zámkem. PANIC odejde hned všemi kanály najednou, SMS bez potvrzení.';

  @override
  String get panicButtonOn => 'Tlačítko PANIC';

  @override
  String get panicStatus => 'Stav, který PANIC pošle';

  @override
  String get panicText => 'Vlastní zpráva (nepovinné)';

  @override
  String get panicToContacts => 'Všem kontaktům';

  @override
  String get panicToTeams => 'Všem týmům';

  @override
  String get compromiseOn => 'Tlačítko KOMPROMITOVÁN';

  @override
  String get compromiseHelp =>
      'Pošle stejným příjemcům stav Kompromitován a pak zničí tento profil stejně jako duress kód. Potvrzuje se druhým tlačítkem nahoře na obrazovce. Duress kód pak otevře návnadu; bez duress kódu už aplikaci nic neotevře.';

  @override
  String get renameTeam => 'Přejmenovat tým';

  @override
  String get noInternet => 'bez internetu';

  @override
  String get secSecurity => 'Bezpečnost';

  @override
  String get secSecuritySub => 'PIN, duress kód, zamykání, otisk prstu, PANIC';

  @override
  String get secConnectivity => 'Konektivita';

  @override
  String get secConnectivitySub =>
      'Číslo pro SMS, pořadí PACE, obnova spojení, rádio LoRa';

  @override
  String get secApp => 'Aplikace';

  @override
  String get secAppSub => 'Přezdívka, jazyk, tovární nastavení';

  @override
  String get pinCodes => 'PIN a duress kód';

  @override
  String get lockTitle => 'Zamykání';

  @override
  String get lockAfter => 'Zamknout po odchodu z aplikace';

  @override
  String get lockNow => 'Ihned';

  @override
  String lockMinutes(int n) {
    return 'Po $n min';
  }

  @override
  String get lockManual => 'Jen ručně (4 klepnutí)';

  @override
  String get lockHelp =>
      'Po restartu telefonu nebo aplikace je PIN potřeba vždy.';

  @override
  String get quickLockNeeded => 'Při zamykání jen ručně musí zůstat zapnuté.';

  @override
  String get bioTitle => 'Odemknutí otiskem prstu';

  @override
  String bioHelp(int h) {
    return 'Jen pro návrat do běžícího profilu. PIN je potřeba po restartu, po nouzovém zamknutí a $h h od posledního zadání PINu. Otisk nemá duress kód.';
  }

  @override
  String get bioNeedsPanic =>
      'Vyžaduje zapnuté tlačítko PANIC i KOMPROMITOVÁN.';

  @override
  String get bioUnavailable => 'Telefon nemá nastavený otisk prstu.';

  @override
  String get bioLocksPanic => 'Při odemykání otiskem musí zůstat zapnuté.';

  @override
  String get bioPrompt => 'Odemknout L0ck-ECP';

  @override
  String get bioUsePin => 'Použít PIN';

  @override
  String get bioButton => 'Otisk prstu';

  @override
  String get chConnected => 'PŘIPOJENO';

  @override
  String get chNoLink => 'BEZ SPOJENÍ';

  @override
  String get reportButton => 'Hlášení';

  @override
  String get sendTo => 'Komu poslat';

  @override
  String get selectAll => 'Vybrat vše';

  @override
  String sendToN(int n) {
    return 'ODESLAT ($n)';
  }

  @override
  String sentToN(int n) {
    return 'Odesláno: $n příjemcům';
  }

  @override
  String get noRecipients => 'Zatím nemáš žádné kontakty ani týmy.';

  @override
  String get groupBundle => 'Balíček skupiny';

  @override
  String get groupLoad => 'Načíst balíček skupiny';

  @override
  String get groupHelp =>
      'Balíček ukazuje notebook na základně jako sérii QR kódů. Načti je všechny, na pořadí nezáleží. Telefon pak dostane kontakty celé skupiny, svoje týmy, kanál LoRa a pořadí PACE.';

  @override
  String get groupScan => 'SKENOVAT QR';

  @override
  String groupProgress(int have, int total) {
    return 'Načteno $have z $total QR';
  }

  @override
  String groupPrompt(int i, int total) {
    return 'Balíček skupiny: QR $i z $total';
  }

  @override
  String get groupPromptFirst => 'Balíček skupiny: kterýkoli QR';

  @override
  String get groupNotPart => 'Tohle není QR balíčku skupiny.';

  @override
  String get groupOther => 'Tento QR patří k jinému balíčku.';

  @override
  String get groupBroken => 'Balíček je poškozený. Načti ho znovu.';

  @override
  String get groupNotMember =>
      'Tento telefon v balíčku není. Na notebooku nejdřív načti jeho kontaktní QR.';

  @override
  String groupContacts(int n) {
    return 'Kontakty ($n)';
  }

  @override
  String get groupTeamsFor => 'Týmy tohoto telefonu';

  @override
  String get groupNoTeams => 'žádný';

  @override
  String groupLora(String team) {
    return 'Rádio LoRa: kanál týmu $team';
  }

  @override
  String groupPace(String order) {
    return 'Pořadí PACE: $order';
  }

  @override
  String get groupApply => 'NASTAVIT TELEFON';

  @override
  String groupDone(int contacts, int teams) {
    return 'Hotovo: $contacts kontaktů, $teams týmů.';
  }

  @override
  String get groupAgain => 'Začít znovu';

  @override
  String get factoryReset => 'Obnovit tovární nastavení';

  @override
  String get factoryResetHelp =>
      'Smaže profil i návnadu, kontakty, týmy, zprávy, klíče a nastavení na tomto telefonu. Aplikace pak začne znovu jako po instalaci. Kontaktům se nic neposílá. Nejde to vrátit.';

  @override
  String get factoryResetButton => 'OBNOVIT TOVÁRNÍ NASTAVENÍ';

  @override
  String get factoryResetAsk => 'Opravdu smazat vše?';

  @override
  String get factoryResetConfirm => 'SMAZAT VŠE';

  @override
  String groupWorking(int done, int total) {
    return 'Nastavuji… kontakty $done z $total';
  }

  @override
  String groupFailed(String error) {
    return 'Nastavení se nepovedlo: $error';
  }

  @override
  String groupOwnPhone(String phone) {
    return 'Tvoje číslo pro SMS: $phone';
  }
}
