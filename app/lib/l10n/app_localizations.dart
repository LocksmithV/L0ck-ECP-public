import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('cs'),
    Locale('en'),
  ];

  /// No description provided for @aboutTitle.
  ///
  /// In cs, this message translates to:
  /// **'O aplikaci'**
  String get aboutTitle;

  /// No description provided for @aboutTagline.
  ///
  /// In cs, this message translates to:
  /// **'Platforma pro koordinaci v nouzi — šifrovaná komunikace přes více cest (PACE): SimpleX, Tor, LoRa, SMS a síť skupiny přes Bluetooth/Wi-Fi.'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In cs, this message translates to:
  /// **'Verze {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutAuthor.
  ///
  /// In cs, this message translates to:
  /// **'Autor'**
  String get aboutAuthor;

  /// No description provided for @aboutWeb.
  ///
  /// In cs, this message translates to:
  /// **'Web'**
  String get aboutWeb;

  /// No description provided for @aboutLicense.
  ///
  /// In cs, this message translates to:
  /// **'Licence'**
  String get aboutLicense;

  /// No description provided for @aboutLicenseText.
  ///
  /// In cs, this message translates to:
  /// **'GNU AGPLv3 — svobodný software; zdrojový kód je k dispozici podle licence.'**
  String get aboutLicenseText;

  /// No description provided for @aboutThirdParty.
  ///
  /// In cs, this message translates to:
  /// **'Použité součásti'**
  String get aboutThirdParty;

  /// No description provided for @aboutThirdPartyText.
  ///
  /// In cs, this message translates to:
  /// **'Briar/Bramble (GPLv3) · SimpleX Chat core (AGPLv3) · Tor (BSD) · MeshCore protokol (MIT) · ZXing (Apache 2.0) · SQLCipher (BSD) · libsodium (ISC) · Flutter (BSD)'**
  String get aboutThirdPartyText;

  /// No description provided for @aboutDisclaimer.
  ///
  /// In cs, this message translates to:
  /// **'Upozornění'**
  String get aboutDisclaimer;

  /// No description provided for @aboutDisclaimerText.
  ///
  /// In cs, this message translates to:
  /// **'L0ck-ECP je nástroj pro bezpečnou komunikaci a koordinaci v nouzových situacích. Není určen k porušování zákonů ani k jiné nezákonné činnosti.\n\nUživatel sám odpovídá za to, že aplikaci používá v souladu s právními předpisy země, kde se nachází — mimo jiné o šifrování, elektronických komunikacích a rádiovém vysílání (kmitočty, výkon a střída vysílání LoRa).\n\nSoftware je poskytován „tak, jak je“, bez jakékoli záruky. Autor nenese odpovědnost za škody, ztrátu dat, nedoručené zprávy ani jiné následky použití aplikace. Nespoléhej na ni jako na jediný prostředek k přivolání pomoci.'**
  String get aboutDisclaimerText;

  /// No description provided for @openFailed.
  ///
  /// In cs, this message translates to:
  /// **'Odkaz nejde otevřít (žádný prohlížeč).'**
  String get openFailed;

  /// No description provided for @wrongCode.
  ///
  /// In cs, this message translates to:
  /// **'Nesprávný kód.'**
  String get wrongCode;

  /// No description provided for @pin.
  ///
  /// In cs, this message translates to:
  /// **'PIN'**
  String get pin;

  /// No description provided for @verifying.
  ///
  /// In cs, this message translates to:
  /// **'Ověřuji…'**
  String get verifying;

  /// No description provided for @retryIn.
  ///
  /// In cs, this message translates to:
  /// **'Zkus znovu za {secs} s'**
  String retryIn(int secs);

  /// No description provided for @unlock.
  ///
  /// In cs, this message translates to:
  /// **'Odemknout'**
  String get unlock;

  /// No description provided for @nicknameLength.
  ///
  /// In cs, this message translates to:
  /// **'Přezdívka 1–24 znaků.'**
  String get nicknameLength;

  /// No description provided for @pinError.
  ///
  /// In cs, this message translates to:
  /// **'PIN: {error}'**
  String pinError(String error);

  /// No description provided for @pinMismatch.
  ///
  /// In cs, this message translates to:
  /// **'PIN se neshoduje.'**
  String get pinMismatch;

  /// No description provided for @duressError.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód: {error}'**
  String duressError(String error);

  /// No description provided for @duressMismatch.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód se neshoduje.'**
  String get duressMismatch;

  /// No description provided for @duressSameAsPin.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód musí být jiný než PIN.'**
  String get duressSameAsPin;

  /// No description provided for @setupFailed.
  ///
  /// In cs, this message translates to:
  /// **'Nastavení selhalo: {error}'**
  String setupFailed(String error);

  /// No description provided for @firstRun.
  ///
  /// In cs, this message translates to:
  /// **'První spuštění'**
  String get firstRun;

  /// No description provided for @nickname.
  ///
  /// In cs, this message translates to:
  /// **'Přezdívka'**
  String get nickname;

  /// No description provided for @pinDigits.
  ///
  /// In cs, this message translates to:
  /// **'PIN (6–12 číslic)'**
  String get pinDigits;

  /// No description provided for @pinAgain.
  ///
  /// In cs, this message translates to:
  /// **'PIN znovu'**
  String get pinAgain;

  /// No description provided for @duressCode.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód'**
  String get duressCode;

  /// No description provided for @duressExplain.
  ///
  /// In cs, this message translates to:
  /// **'Pod nátlakem zadej místo PINu: otevře prázdný profil a skutečná data nevratně zničí.'**
  String get duressExplain;

  /// No description provided for @duressDigits.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód (6–12 číslic)'**
  String get duressDigits;

  /// No description provided for @duressAgain.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód znovu'**
  String get duressAgain;

  /// No description provided for @generatingKeys.
  ///
  /// In cs, this message translates to:
  /// **'Generuji klíče…'**
  String get generatingKeys;

  /// No description provided for @create.
  ///
  /// In cs, this message translates to:
  /// **'Vytvořit'**
  String get create;

  /// No description provided for @pinRuleEnter.
  ///
  /// In cs, this message translates to:
  /// **'Zadej {min}–{max} číslic.'**
  String pinRuleEnter(int min, int max);

  /// No description provided for @pinRuleDigits.
  ///
  /// In cs, this message translates to:
  /// **'Jen číslice.'**
  String get pinRuleDigits;

  /// No description provided for @pinRuleMin.
  ///
  /// In cs, this message translates to:
  /// **'Nejméně {min} číslic.'**
  String pinRuleMin(int min);

  /// No description provided for @pinRuleMax.
  ///
  /// In cs, this message translates to:
  /// **'Nejvýše {max} číslic.'**
  String pinRuleMax(int max);

  /// No description provided for @currentCodeWrong.
  ///
  /// In cs, this message translates to:
  /// **'Současný kód nesedí.'**
  String get currentCodeWrong;

  /// No description provided for @codeInUse.
  ///
  /// In cs, this message translates to:
  /// **'Tento kód už se používá.'**
  String get codeInUse;

  /// No description provided for @duressMustDiffer.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód se musí lišit od PINu.'**
  String get duressMustDiffer;

  /// No description provided for @enterNickname.
  ///
  /// In cs, this message translates to:
  /// **'Zadej přezdívku.'**
  String get enterNickname;

  /// No description provided for @duressWrong.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód nesedí.'**
  String get duressWrong;

  /// No description provided for @newMessages.
  ///
  /// In cs, this message translates to:
  /// **'Nové zprávy'**
  String get newMessages;

  /// No description provided for @directMessage.
  ///
  /// In cs, this message translates to:
  /// **'přímá zpráva'**
  String get directMessage;

  /// No description provided for @team.
  ///
  /// In cs, this message translates to:
  /// **'tým'**
  String get team;

  /// No description provided for @contacts.
  ///
  /// In cs, this message translates to:
  /// **'Kontakty'**
  String get contacts;

  /// No description provided for @teams.
  ///
  /// In cs, this message translates to:
  /// **'Týmy'**
  String get teams;

  /// No description provided for @loraRadio.
  ///
  /// In cs, this message translates to:
  /// **'Rádio LoRa'**
  String get loraRadio;

  /// No description provided for @settings.
  ///
  /// In cs, this message translates to:
  /// **'Nastavení'**
  String get settings;

  /// No description provided for @identity.
  ///
  /// In cs, this message translates to:
  /// **'Identita'**
  String get identity;

  /// No description provided for @fingerprint.
  ///
  /// In cs, this message translates to:
  /// **'Otisk: {fp}'**
  String fingerprint(String fp);

  /// No description provided for @smsNumber.
  ///
  /// In cs, this message translates to:
  /// **'SMS číslo: {number}'**
  String smsNumber(String number);

  /// No description provided for @notSet.
  ///
  /// In cs, this message translates to:
  /// **'nenastaveno'**
  String get notSet;

  /// No description provided for @channels.
  ///
  /// In cs, this message translates to:
  /// **'Kanály'**
  String get channels;

  /// No description provided for @noChannel.
  ///
  /// In cs, this message translates to:
  /// **'Žádný kanál'**
  String get noChannel;

  /// No description provided for @myContact.
  ///
  /// In cs, this message translates to:
  /// **'Můj kontakt'**
  String get myContact;

  /// No description provided for @copyMyLink.
  ///
  /// In cs, this message translates to:
  /// **'Kopírovat můj odkaz'**
  String get copyMyLink;

  /// No description provided for @linkCopied.
  ///
  /// In cs, this message translates to:
  /// **'Odkaz zkopírován. Po vložení schránku vymaž.'**
  String get linkCopied;

  /// No description provided for @showInPersonOnly.
  ///
  /// In cs, this message translates to:
  /// **'Ukazuj jen osobně.'**
  String get showInPersonOnly;

  /// No description provided for @contactsButton.
  ///
  /// In cs, this message translates to:
  /// **'KONTAKTY ({count})'**
  String contactsButton(String count);

  /// No description provided for @add.
  ///
  /// In cs, this message translates to:
  /// **'Přidat'**
  String get add;

  /// No description provided for @noContactsYet.
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádné kontakty.'**
  String get noContactsYet;

  /// No description provided for @verifiedInPerson.
  ///
  /// In cs, this message translates to:
  /// **'ověřeno osobně'**
  String get verifiedInPerson;

  /// No description provided for @notVerified.
  ///
  /// In cs, this message translates to:
  /// **'neověřeno'**
  String get notVerified;

  /// No description provided for @openConversation.
  ///
  /// In cs, this message translates to:
  /// **'Otevřít konverzaci'**
  String get openConversation;

  /// No description provided for @contactDetailMenu.
  ///
  /// In cs, this message translates to:
  /// **'Detail: ověření, kanály, QR, Bluetooth, smazat'**
  String get contactDetailMenu;

  /// No description provided for @contactAndTeam.
  ///
  /// In cs, this message translates to:
  /// **'{contact} a tým {team}'**
  String contactAndTeam(String contact, String team);

  /// No description provided for @addContact.
  ///
  /// In cs, this message translates to:
  /// **'Přidat kontakt'**
  String get addContact;

  /// No description provided for @contactLinkLabel.
  ///
  /// In cs, this message translates to:
  /// **'Odkaz kontaktu (l0ck://c/…)'**
  String get contactLinkLabel;

  /// No description provided for @contactUpdated.
  ///
  /// In cs, this message translates to:
  /// **'Kontakt {name} aktualizován (nové kanály z karty).'**
  String contactUpdated(String name);

  /// No description provided for @load.
  ///
  /// In cs, this message translates to:
  /// **'Načíst'**
  String get load;

  /// No description provided for @scanQr.
  ///
  /// In cs, this message translates to:
  /// **'Skenovat QR kontaktu nebo týmu'**
  String get scanQr;

  /// No description provided for @scanPrompt.
  ///
  /// In cs, this message translates to:
  /// **'Namiř na QR druhého telefonu'**
  String get scanPrompt;

  /// No description provided for @joinedTeam.
  ///
  /// In cs, this message translates to:
  /// **'Připojen k týmu {team}. Rádio LoRa přepnuto na kanál týmu.'**
  String joinedTeam(String team);

  /// No description provided for @verificationNumber.
  ///
  /// In cs, this message translates to:
  /// **'Ověřovací číslo'**
  String get verificationNumber;

  /// No description provided for @verificationExplain.
  ///
  /// In cs, this message translates to:
  /// **'Porovnej ho osobně s číslem na telefonu kontaktu. Shodné číslo znamená, že nikdo nepodstrčil cizí klíč.'**
  String get verificationExplain;

  /// No description provided for @numbersMatch.
  ///
  /// In cs, this message translates to:
  /// **'Čísla se shodují (ověřeno osobně)'**
  String get numbersMatch;

  /// No description provided for @done.
  ///
  /// In cs, this message translates to:
  /// **'Hotovo'**
  String get done;

  /// No description provided for @contact.
  ///
  /// In cs, this message translates to:
  /// **'Kontakt'**
  String get contact;

  /// No description provided for @reportsAndPosition.
  ///
  /// In cs, this message translates to:
  /// **'Hlášení a poloha'**
  String get reportsAndPosition;

  /// No description provided for @message.
  ///
  /// In cs, this message translates to:
  /// **'Zpráva'**
  String get message;

  /// No description provided for @send.
  ///
  /// In cs, this message translates to:
  /// **'Odeslat'**
  String get send;

  /// No description provided for @renameContact.
  ///
  /// In cs, this message translates to:
  /// **'Přejmenovat kontakt'**
  String get renameContact;

  /// No description provided for @cancel.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In cs, this message translates to:
  /// **'Uložit'**
  String get save;

  /// No description provided for @deleteContactQ.
  ///
  /// In cs, this message translates to:
  /// **'Smazat {name}?'**
  String deleteContactQ(String name);

  /// No description provided for @deleteContactText.
  ///
  /// In cs, this message translates to:
  /// **'Smaže kontakt, jeho klíče a celou konverzaci. Nejde vrátit; pro nové spojení je třeba znovu naskenovat jeho QR.'**
  String get deleteContactText;

  /// No description provided for @delete.
  ///
  /// In cs, this message translates to:
  /// **'Smazat'**
  String get delete;

  /// No description provided for @brambleNotRunning.
  ///
  /// In cs, this message translates to:
  /// **'Bramble neběží.'**
  String get brambleNotRunning;

  /// No description provided for @needNearbyPermission.
  ///
  /// In cs, this message translates to:
  /// **'Bez oprávnění „Zařízení v okolí“ to nejde.'**
  String get needNearbyPermission;

  /// No description provided for @makingVisible.
  ///
  /// In cs, this message translates to:
  /// **'Zviditelňuji telefon…'**
  String get makingVisible;

  /// No description provided for @noVisibility.
  ///
  /// In cs, this message translates to:
  /// **'Bez viditelnosti se telefony nenajdou.'**
  String get noVisibility;

  /// No description provided for @searchingBt.
  ///
  /// In cs, this message translates to:
  /// **'Hledám kontakt přes Bluetooth (až 30 s)…'**
  String get searchingBt;

  /// No description provided for @btConnected.
  ///
  /// In cs, this message translates to:
  /// **'Spojeno přes Bluetooth. Příště se telefony najdou samy.'**
  String get btConnected;

  /// No description provided for @btNoUuid.
  ///
  /// In cs, this message translates to:
  /// **'Kontakt ještě nebyl spojen jinou cestou (Tor/LAN) — zkus znovu později.'**
  String get btNoUuid;

  /// No description provided for @btNotFound.
  ///
  /// In cs, this message translates to:
  /// **'Nenalezen. Ať kontakt současně udělá totéž, telefony blízko sebe.'**
  String get btNotFound;

  /// No description provided for @btNotBramble.
  ///
  /// In cs, this message translates to:
  /// **'Kontakt zatím není spojený přes Bramble.'**
  String get btNotBramble;

  /// No description provided for @btUnavailable.
  ///
  /// In cs, this message translates to:
  /// **'Bluetooth v Bramble nenaběhl ({state}). Zkus vypnout a zapnout Bluetooth v telefonu.'**
  String btUnavailable(String state);

  /// No description provided for @unexpectedResult.
  ///
  /// In cs, this message translates to:
  /// **'Nečekaný výsledek: {r}'**
  String unexpectedResult(String r);

  /// No description provided for @rename.
  ///
  /// In cs, this message translates to:
  /// **'Přejmenovat'**
  String get rename;

  /// No description provided for @verification.
  ///
  /// In cs, this message translates to:
  /// **'Ověření'**
  String get verification;

  /// No description provided for @verifiedInPersonDot.
  ///
  /// In cs, this message translates to:
  /// **'Ověřeno osobně.'**
  String get verifiedInPersonDot;

  /// No description provided for @notVerifiedExplain.
  ///
  /// In cs, this message translates to:
  /// **'Neověřeno. Porovnej číslo s telefonem kontaktu — shodné číslo znamená, že nikdo nepodstrčil cizí klíč.'**
  String get notVerifiedExplain;

  /// No description provided for @unverify.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit ověření'**
  String get unverify;

  /// No description provided for @markVerified.
  ///
  /// In cs, this message translates to:
  /// **'Čísla se shodují — označit ověřeno'**
  String get markVerified;

  /// No description provided for @missingOnCard.
  ///
  /// In cs, this message translates to:
  /// **'chybí na kartě'**
  String get missingOnCard;

  /// No description provided for @connected.
  ///
  /// In cs, this message translates to:
  /// **'spojeno'**
  String get connected;

  /// No description provided for @connecting.
  ///
  /// In cs, this message translates to:
  /// **'spojuje se…'**
  String get connecting;

  /// No description provided for @contactNoLink.
  ///
  /// In cs, this message translates to:
  /// **'kontakt, teď bez spojení'**
  String get contactNoLink;

  /// No description provided for @linksNow.
  ///
  /// In cs, this message translates to:
  /// **'teď: {links}'**
  String linksNow(String links);

  /// No description provided for @noPhone.
  ///
  /// In cs, this message translates to:
  /// **'číslo chybí'**
  String get noPhone;

  /// No description provided for @loraEveryone.
  ///
  /// In cs, this message translates to:
  /// **'kanál ECP / týmu (všichni v dosahu)'**
  String get loraEveryone;

  /// No description provided for @connectBluetooth.
  ///
  /// In cs, this message translates to:
  /// **'Spojit přes Bluetooth'**
  String get connectBluetooth;

  /// No description provided for @connectBluetoothHelp.
  ///
  /// In cs, this message translates to:
  /// **'Poprvé musí oba telefony zároveň: zviditelní se a najdou se. Pak už se přes Bluetooth spojují samy (i bez Wi-Fi a dat).'**
  String get connectBluetoothHelp;

  /// No description provided for @contactCard.
  ///
  /// In cs, this message translates to:
  /// **'Karta kontaktu'**
  String get contactCard;

  /// No description provided for @theirCard.
  ///
  /// In cs, this message translates to:
  /// **'Jeho veřejná karta — předávej jen s jeho souhlasem.'**
  String get theirCard;

  /// No description provided for @deleteContact.
  ///
  /// In cs, this message translates to:
  /// **'Smazat kontakt'**
  String get deleteContact;

  /// No description provided for @textCopied.
  ///
  /// In cs, this message translates to:
  /// **'Text zkopírován.'**
  String get textCopied;

  /// No description provided for @sendViaSms.
  ///
  /// In cs, this message translates to:
  /// **'Poslat přes SMS'**
  String get sendViaSms;

  /// No description provided for @via.
  ///
  /// In cs, this message translates to:
  /// **'přes {via}'**
  String via(String via);

  /// No description provided for @nobodyInRange.
  ///
  /// In cs, this message translates to:
  /// **'nikdo v dosahu'**
  String get nobodyInRange;

  /// No description provided for @sentTeam.
  ///
  /// In cs, this message translates to:
  /// **'odesláno: {via}'**
  String sentTeam(String via);

  /// No description provided for @stSending.
  ///
  /// In cs, this message translates to:
  /// **'odesílám…'**
  String get stSending;

  /// No description provided for @stSent.
  ///
  /// In cs, this message translates to:
  /// **'odesláno přes {via}'**
  String stSent(String via);

  /// No description provided for @stDelivered.
  ///
  /// In cs, this message translates to:
  /// **'doručeno{at} · {via}'**
  String stDelivered(String at, String via);

  /// No description provided for @stRead.
  ///
  /// In cs, this message translates to:
  /// **'přečteno{at}'**
  String stRead(String at);

  /// No description provided for @stWaiting.
  ///
  /// In cs, this message translates to:
  /// **'čeká na kanál'**
  String get stWaiting;

  /// No description provided for @stConfirm.
  ///
  /// In cs, this message translates to:
  /// **'jen SMS — potvrď'**
  String get stConfirm;

  /// No description provided for @stFailed.
  ///
  /// In cs, this message translates to:
  /// **'nedoručeno'**
  String get stFailed;

  /// No description provided for @squadNet.
  ///
  /// In cs, this message translates to:
  /// **'síť skupiny'**
  String get squadNet;

  /// No description provided for @newTeam.
  ///
  /// In cs, this message translates to:
  /// **'Nový tým'**
  String get newTeam;

  /// No description provided for @teamNameLocal.
  ///
  /// In cs, this message translates to:
  /// **'Název (jen u tebe)'**
  String get teamNameLocal;

  /// No description provided for @found.
  ///
  /// In cs, this message translates to:
  /// **'Založit'**
  String get found;

  /// No description provided for @teamDefaultName.
  ///
  /// In cs, this message translates to:
  /// **'Tým'**
  String get teamDefaultName;

  /// No description provided for @noTeams.
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádný tým.\n\nZaložit: „Nový tým“ a ukaž ostatním týmové QR.\nPřipojit se: v Kontaktech „Přidat“ a vlož odkaz z týmového QR člena.'**
  String get noTeams;

  /// No description provided for @teamId.
  ///
  /// In cs, this message translates to:
  /// **'ID {id}'**
  String teamId(String id);

  /// No description provided for @teamQrTitle.
  ///
  /// In cs, this message translates to:
  /// **'Týmové QR — {team}'**
  String teamQrTitle(String team);

  /// No description provided for @teamQrWarning.
  ///
  /// In cs, this message translates to:
  /// **'Ukazuj jen osobně a jen členům. Kdo QR vyfotí, čte týmovou komunikaci.'**
  String get teamQrWarning;

  /// No description provided for @close.
  ///
  /// In cs, this message translates to:
  /// **'Zavřít'**
  String get close;

  /// No description provided for @leaveTeamQ.
  ///
  /// In cs, this message translates to:
  /// **'Opustit {team}?'**
  String leaveTeamQ(String team);

  /// No description provided for @leaveTeamText.
  ///
  /// In cs, this message translates to:
  /// **'Členové dostanou zprávu, že odcházíš. Z tohoto telefonu zmizí tým, jeho zprávy i klíč; vrátit se jde jen novým naskenováním týmového QR.'**
  String get leaveTeamText;

  /// No description provided for @leave.
  ///
  /// In cs, this message translates to:
  /// **'Opustit'**
  String get leave;

  /// No description provided for @leaveTeamMenu.
  ///
  /// In cs, this message translates to:
  /// **'Opustit a smazat tým'**
  String get leaveTeamMenu;

  /// No description provided for @teamMembers.
  ///
  /// In cs, this message translates to:
  /// **'Členové týmu'**
  String get teamMembers;

  /// No description provided for @teamMembersHelp.
  ///
  /// In cs, this message translates to:
  /// **'Zaškrtnutí dostanou týmové zprávy i přes SimpleX/Tor, když nejsou v dosahu rádia ani Bluetooth.'**
  String get teamMembersHelp;

  /// No description provided for @members.
  ///
  /// In cs, this message translates to:
  /// **'Členové'**
  String get members;

  /// No description provided for @teamQr.
  ///
  /// In cs, this message translates to:
  /// **'Týmové QR'**
  String get teamQr;

  /// No description provided for @unknownSender.
  ///
  /// In cs, this message translates to:
  /// **'neznámý {fp}'**
  String unknownSender(String fp);

  /// No description provided for @teamMessage.
  ///
  /// In cs, this message translates to:
  /// **'Zpráva týmu'**
  String get teamMessage;

  /// No description provided for @noBtPermissionRadio.
  ///
  /// In cs, this message translates to:
  /// **'Bez oprávnění Bluetooth se k rádiu nepřipojím.'**
  String get noBtPermissionRadio;

  /// No description provided for @commonEcpChannel.
  ///
  /// In cs, this message translates to:
  /// **'Společný ECP kanál.'**
  String get commonEcpChannel;

  /// No description provided for @groupChannelSet.
  ///
  /// In cs, this message translates to:
  /// **'Kanál skupiny nastaven.'**
  String get groupChannelSet;

  /// No description provided for @radioRejectedChannel.
  ///
  /// In cs, this message translates to:
  /// **'Rádio kanál nepřijalo: {e}'**
  String radioRejectedChannel(String e);

  /// No description provided for @meshcoreRadioPaired.
  ///
  /// In cs, this message translates to:
  /// **'Rádio MeshCore (spárované v nastavení Bluetooth)'**
  String get meshcoreRadioPaired;

  /// No description provided for @noPairedDevice.
  ///
  /// In cs, this message translates to:
  /// **'Žádné spárované zařízení. Spáruj rádio v nastavení Bluetooth (PIN z displeje rádia).'**
  String get noPairedDevice;

  /// No description provided for @forgetRadio.
  ///
  /// In cs, this message translates to:
  /// **'Odpojit a zapomenout rádio'**
  String get forgetRadio;

  /// No description provided for @loraUnavailable.
  ///
  /// In cs, this message translates to:
  /// **'LoRa: nedostupné'**
  String get loraUnavailable;

  /// No description provided for @firmwareInfo.
  ///
  /// In cs, this message translates to:
  /// **'Firmware {version} · {channels} kanálů'**
  String firmwareInfo(String version, int channels);

  /// No description provided for @pathHash.
  ///
  /// In cs, this message translates to:
  /// **' · hash cesty {bytes} B'**
  String pathHash(int bytes);

  /// No description provided for @loraChannel.
  ///
  /// In cs, this message translates to:
  /// **'Kanál LoRa'**
  String get loraChannel;

  /// No description provided for @commonChannelHelp.
  ///
  /// In cs, this message translates to:
  /// **'Společný ECP kanál. Veřejný a hashtag kanály aplikace ignoruje.'**
  String get commonChannelHelp;

  /// No description provided for @privateChannelHelp.
  ///
  /// In cs, this message translates to:
  /// **'Soukromý kanál skupiny. Klíč sdílej jen osobně.'**
  String get privateChannelHelp;

  /// No description provided for @newGroupChannel.
  ///
  /// In cs, this message translates to:
  /// **'Nový kanál skupiny'**
  String get newGroupChannel;

  /// No description provided for @copyKey.
  ///
  /// In cs, this message translates to:
  /// **'Kopírovat klíč'**
  String get copyKey;

  /// No description provided for @backToEcpChannel.
  ///
  /// In cs, this message translates to:
  /// **'Zpět na ECP kanál'**
  String get backToEcpChannel;

  /// No description provided for @groupKeyPaste.
  ///
  /// In cs, this message translates to:
  /// **'Klíč kanálu skupiny (vložit)'**
  String get groupKeyPaste;

  /// No description provided for @invalidChannelKey.
  ///
  /// In cs, this message translates to:
  /// **'Neplatný klíč kanálu.'**
  String get invalidChannelKey;

  /// No description provided for @layerAlternate.
  ///
  /// In cs, this message translates to:
  /// **'Tor / Bramble (i LAN a Bluetooth)'**
  String get layerAlternate;

  /// No description provided for @layerContingency.
  ///
  /// In cs, this message translates to:
  /// **'LoRa (MeshCore)'**
  String get layerContingency;

  /// No description provided for @cz.
  ///
  /// In cs, this message translates to:
  /// **'Česko'**
  String get cz;

  /// No description provided for @sk.
  ///
  /// In cs, this message translates to:
  /// **'Slovensko'**
  String get sk;

  /// No description provided for @pl.
  ///
  /// In cs, this message translates to:
  /// **'Polsko'**
  String get pl;

  /// No description provided for @de.
  ///
  /// In cs, this message translates to:
  /// **'Německo'**
  String get de;

  /// No description provided for @at.
  ///
  /// In cs, this message translates to:
  /// **'Rakousko'**
  String get at;

  /// No description provided for @hu.
  ///
  /// In cs, this message translates to:
  /// **'Maďarsko'**
  String get hu;

  /// No description provided for @ua.
  ///
  /// In cs, this message translates to:
  /// **'Ukrajina'**
  String get ua;

  /// No description provided for @uk.
  ///
  /// In cs, this message translates to:
  /// **'Spojené království'**
  String get uk;

  /// No description provided for @us.
  ///
  /// In cs, this message translates to:
  /// **'USA / Kanada'**
  String get us;

  /// No description provided for @numberRemoved.
  ///
  /// In cs, this message translates to:
  /// **'Číslo odebráno.'**
  String get numberRemoved;

  /// No description provided for @numberSaved.
  ///
  /// In cs, this message translates to:
  /// **'Uloženo. Kontakty dostanou nové číslo samy.'**
  String get numberSaved;

  /// No description provided for @confirm.
  ///
  /// In cs, this message translates to:
  /// **'Potvrdit'**
  String get confirm;

  /// No description provided for @duressOptional.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód (nepovinné)'**
  String get duressOptional;

  /// No description provided for @renameDecoyHelp.
  ///
  /// In cs, this message translates to:
  /// **'S duress kódem se přejmenuje i prázdný profil, aby pod nátlakem ukázal stejné jméno.'**
  String get renameDecoyHelp;

  /// No description provided for @nicknameChanged.
  ///
  /// In cs, this message translates to:
  /// **'Přezdívka změněna.'**
  String get nicknameChanged;

  /// No description provided for @changePin.
  ///
  /// In cs, this message translates to:
  /// **'Změnit PIN'**
  String get changePin;

  /// No description provided for @currentPin.
  ///
  /// In cs, this message translates to:
  /// **'Současný PIN'**
  String get currentPin;

  /// No description provided for @newPin.
  ///
  /// In cs, this message translates to:
  /// **'Nový PIN'**
  String get newPin;

  /// No description provided for @newPinAgain.
  ///
  /// In cs, this message translates to:
  /// **'Nový PIN znovu'**
  String get newPinAgain;

  /// No description provided for @newPinsMismatch.
  ///
  /// In cs, this message translates to:
  /// **'Nové PINy se neshodují.'**
  String get newPinsMismatch;

  /// No description provided for @pinChanged.
  ///
  /// In cs, this message translates to:
  /// **'PIN změněn.'**
  String get pinChanged;

  /// No description provided for @removeDuress.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit duress kód'**
  String get removeDuress;

  /// No description provided for @removeDuressNote.
  ///
  /// In cs, this message translates to:
  /// **'Prázdný profil i s obsahem zmizí; pod nátlakem pak nebude kam uhnout.'**
  String get removeDuressNote;

  /// No description provided for @newDuress.
  ///
  /// In cs, this message translates to:
  /// **'Nový duress kód'**
  String get newDuress;

  /// No description provided for @newDuressAgain.
  ///
  /// In cs, this message translates to:
  /// **'Nový duress kód znovu'**
  String get newDuressAgain;

  /// No description provided for @newDuressNote.
  ///
  /// In cs, this message translates to:
  /// **'Vznikne nový prázdný profil se stejnou přezdívkou; ten starý i s obsahem zmizí.'**
  String get newDuressNote;

  /// No description provided for @duressCodesMismatch.
  ///
  /// In cs, this message translates to:
  /// **'Duress kódy se neshodují.'**
  String get duressCodesMismatch;

  /// No description provided for @duressRemoved.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód zrušen.'**
  String get duressRemoved;

  /// No description provided for @duressSet.
  ///
  /// In cs, this message translates to:
  /// **'Duress kód nastaven.'**
  String get duressSet;

  /// No description provided for @profile.
  ///
  /// In cs, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @nicknameOnCard.
  ///
  /// In cs, this message translates to:
  /// **'Přezdívka na tvé kartě'**
  String get nicknameOnCard;

  /// No description provided for @smsNumberLayer.
  ///
  /// In cs, this message translates to:
  /// **'SMS číslo (vrstva E)'**
  String get smsNumberLayer;

  /// No description provided for @number.
  ///
  /// In cs, this message translates to:
  /// **'Číslo'**
  String get number;

  /// No description provided for @simChangeHelp.
  ///
  /// In cs, this message translates to:
  /// **'Při změně SIM (místní operátor) zadej nové číslo: QR se obnoví a kontakty ho dostanou automaticky. Prázdné pole číslo odebere.'**
  String get simChangeHelp;

  /// No description provided for @saveNumber.
  ///
  /// In cs, this message translates to:
  /// **'ULOŽIT ČÍSLO'**
  String get saveNumber;

  /// No description provided for @paceOrder.
  ///
  /// In cs, this message translates to:
  /// **'Pořadí kanálů (PACE)'**
  String get paceOrder;

  /// No description provided for @paceOrderHelp.
  ///
  /// In cs, this message translates to:
  /// **'Zpráva jde nejdřív prvním dostupným kanálem shora; bez potvrzení v limitu zkusí další. Přetáhni za ≡. SMS se vždy posílá jen po potvrzení (nebo v nouzi).'**
  String get paceOrderHelp;

  /// No description provided for @paceDefault.
  ///
  /// In cs, this message translates to:
  /// **'Výchozí pořadí (SimpleX → Tor → LoRa → SMS)'**
  String get paceDefault;

  /// No description provided for @security.
  ///
  /// In cs, this message translates to:
  /// **'Zabezpečení'**
  String get security;

  /// No description provided for @pinNotStored.
  ///
  /// In cs, this message translates to:
  /// **'PIN ani duress kód aplikace neukládá, proto je nejde zobrazit — jen změnit. Zapomenutý PIN nejde obnovit.'**
  String get pinNotStored;

  /// No description provided for @setNewDuress.
  ///
  /// In cs, this message translates to:
  /// **'Nastavit nový duress kód'**
  String get setNewDuress;

  /// No description provided for @emergencyLock.
  ///
  /// In cs, this message translates to:
  /// **'Nouzové zamknutí'**
  String get emergencyLock;

  /// No description provided for @emergencyLockHelp.
  ///
  /// In cs, this message translates to:
  /// **'{taps}× rychle klepni kamkoli na obrazovku: aplikace se okamžitě zamkne a skryje. Zprávy dál chodí na pozadí.'**
  String emergencyLockHelp(int taps);

  /// No description provided for @lockAndHide.
  ///
  /// In cs, this message translates to:
  /// **'ZAMKNOUT A SKRÝT'**
  String get lockAndHide;

  /// No description provided for @reconnect.
  ///
  /// In cs, this message translates to:
  /// **'Obnovit spojení'**
  String get reconnect;

  /// No description provided for @reconnectOne.
  ///
  /// In cs, this message translates to:
  /// **'Obnovit {channel}'**
  String reconnectOne(String channel);

  /// No description provided for @reconnectAll.
  ///
  /// In cs, this message translates to:
  /// **'Obnovit vše'**
  String get reconnectAll;

  /// No description provided for @loraRadioShort.
  ///
  /// In cs, this message translates to:
  /// **'LoRa rádio'**
  String get loraRadioShort;

  /// No description provided for @language.
  ///
  /// In cs, this message translates to:
  /// **'Jazyk'**
  String get language;

  /// No description provided for @about.
  ///
  /// In cs, this message translates to:
  /// **'O aplikaci'**
  String get about;

  /// No description provided for @stOk.
  ///
  /// In cs, this message translates to:
  /// **'V pořádku'**
  String get stOk;

  /// No description provided for @stNeedHelp.
  ///
  /// In cs, this message translates to:
  /// **'Potřebuji pomoc'**
  String get stNeedHelp;

  /// No description provided for @stCompromised.
  ///
  /// In cs, this message translates to:
  /// **'Kompromitován'**
  String get stCompromised;

  /// No description provided for @stInjured.
  ///
  /// In cs, this message translates to:
  /// **'Zraněn'**
  String get stInjured;

  /// No description provided for @stMoving.
  ///
  /// In cs, this message translates to:
  /// **'V pohybu'**
  String get stMoving;

  /// No description provided for @stInPosition.
  ///
  /// In cs, this message translates to:
  /// **'Na místě'**
  String get stInPosition;

  /// No description provided for @sitrepStates.
  ///
  /// In cs, this message translates to:
  /// **'Klid|Pozor / sledování|Kontakt|Nouze'**
  String get sitrepStates;

  /// No description provided for @medevacPrecedence.
  ///
  /// In cs, this message translates to:
  /// **'A urgentní|B urgentní-chirurgický|C prioritní|D rutinní|E odložitelný'**
  String get medevacPrecedence;

  /// No description provided for @medevacEquipment.
  ///
  /// In cs, this message translates to:
  /// **'žádné|naviják|vyprošťovací technika|ventilátor'**
  String get medevacEquipment;

  /// No description provided for @medevacSecurity.
  ///
  /// In cs, this message translates to:
  /// **'bez nepřítele|možný nepřítel|nepřítel v oblasti|nepřítel, nutný doprovod'**
  String get medevacSecurity;

  /// No description provided for @medevacMarking.
  ///
  /// In cs, this message translates to:
  /// **'panely|pyrotechnika|kouř|žádné|jiné'**
  String get medevacMarking;

  /// No description provided for @medevacNationality.
  ///
  /// In cs, this message translates to:
  /// **'vlastní voják|vlastní civilista|cizí voják|cizí civilista|zajatec'**
  String get medevacNationality;

  /// No description provided for @medevacTerrain.
  ///
  /// In cs, this message translates to:
  /// **'bez kontaminace|jaderná (N)|biologická (B)|chemická (C)'**
  String get medevacTerrain;

  /// No description provided for @rPosition.
  ///
  /// In cs, this message translates to:
  /// **'POLOHA'**
  String get rPosition;

  /// No description provided for @rStatus.
  ///
  /// In cs, this message translates to:
  /// **'STATUS'**
  String get rStatus;

  /// No description provided for @rRally.
  ///
  /// In cs, this message translates to:
  /// **'SRAZ'**
  String get rRally;

  /// No description provided for @rSitrep.
  ///
  /// In cs, this message translates to:
  /// **'SITREP'**
  String get rSitrep;

  /// No description provided for @rMedevac.
  ///
  /// In cs, this message translates to:
  /// **'MEDEVAC 9-line'**
  String get rMedevac;

  /// No description provided for @rSalter.
  ///
  /// In cs, this message translates to:
  /// **'SALTER'**
  String get rSalter;

  /// No description provided for @r5w.
  ///
  /// In cs, this message translates to:
  /// **'5W'**
  String get r5w;

  /// No description provided for @timeLine.
  ///
  /// In cs, this message translates to:
  /// **'Čas: {t}'**
  String timeLine(String t);

  /// No description provided for @personsLine.
  ///
  /// In cs, this message translates to:
  /// **'Osob: {n}'**
  String personsLine(int n);

  /// No description provided for @mLine2.
  ///
  /// In cs, this message translates to:
  /// **'2 volací znak: {v}'**
  String mLine2(String v);

  /// No description provided for @mLine3.
  ///
  /// In cs, this message translates to:
  /// **'3 pacienti: {v}'**
  String mLine3(String v);

  /// No description provided for @mLine4.
  ///
  /// In cs, this message translates to:
  /// **'4 vybavení: {v}'**
  String mLine4(String v);

  /// No description provided for @mLine5.
  ///
  /// In cs, this message translates to:
  /// **'5 nosítka {l}, chodící {a}'**
  String mLine5(int l, int a);

  /// No description provided for @mLine6.
  ///
  /// In cs, this message translates to:
  /// **'6 bezpečnost: {v}'**
  String mLine6(String v);

  /// No description provided for @mLine7.
  ///
  /// In cs, this message translates to:
  /// **'7 značení: {v}'**
  String mLine7(String v);

  /// No description provided for @mLine8.
  ///
  /// In cs, this message translates to:
  /// **'8 národnost: {v}'**
  String mLine8(String v);

  /// No description provided for @mLine9.
  ///
  /// In cs, this message translates to:
  /// **'9 terén/NBC: {v}'**
  String mLine9(String v);

  /// No description provided for @sSize.
  ///
  /// In cs, this message translates to:
  /// **'S velikost: {v}'**
  String sSize(int v);

  /// No description provided for @sActivity.
  ///
  /// In cs, this message translates to:
  /// **'A činnost: {v}'**
  String sActivity(String v);

  /// No description provided for @sTime.
  ///
  /// In cs, this message translates to:
  /// **'T čas: {v}'**
  String sTime(String v);

  /// No description provided for @sEquipment.
  ///
  /// In cs, this message translates to:
  /// **'E vybavení: {v}'**
  String sEquipment(String v);

  /// No description provided for @sRemarks.
  ///
  /// In cs, this message translates to:
  /// **'R poznámky: {v}'**
  String sRemarks(String v);

  /// No description provided for @wWho.
  ///
  /// In cs, this message translates to:
  /// **'Kdo: {v}'**
  String wWho(String v);

  /// No description provided for @wWhat.
  ///
  /// In cs, this message translates to:
  /// **'Co: {v}'**
  String wWhat(String v);

  /// No description provided for @wWhen.
  ///
  /// In cs, this message translates to:
  /// **'Kdy: {v}'**
  String wWhen(String v);

  /// No description provided for @wWhy.
  ///
  /// In cs, this message translates to:
  /// **'Proč: {v}'**
  String wWhy(String v);

  /// No description provided for @reportUnreadable.
  ///
  /// In cs, this message translates to:
  /// **'(hlášení nejde přečíst)'**
  String get reportUnreadable;

  /// No description provided for @accuracy.
  ///
  /// In cs, this message translates to:
  /// **'přesnost ±{m} m'**
  String accuracy(int m);

  /// No description provided for @distanceFindMe.
  ///
  /// In cs, this message translates to:
  /// **'Vzdálenost a směr: zjistit mou polohu'**
  String get distanceFindMe;

  /// No description provided for @distanceBearing.
  ///
  /// In cs, this message translates to:
  /// **'{d} · azimut {b}'**
  String distanceBearing(String d, String b);

  /// No description provided for @map.
  ///
  /// In cs, this message translates to:
  /// **'Mapa'**
  String get map;

  /// No description provided for @noMapApp.
  ///
  /// In cs, this message translates to:
  /// **'Žádná mapová aplikace. Doporučuji OsmAnd nebo Organic Maps z F-Droidu (offline).'**
  String get noMapApp;

  /// No description provided for @coordinates.
  ///
  /// In cs, this message translates to:
  /// **'Souřadnice'**
  String get coordinates;

  /// No description provided for @coordsCopied.
  ///
  /// In cs, this message translates to:
  /// **'Souřadnice zkopírovány.'**
  String get coordsCopied;

  /// No description provided for @persons.
  ///
  /// In cs, this message translates to:
  /// **'osob'**
  String get persons;

  /// No description provided for @reports.
  ///
  /// In cs, this message translates to:
  /// **'HLÁŠENÍ'**
  String get reports;

  /// No description provided for @myPosition.
  ///
  /// In cs, this message translates to:
  /// **'Moje poloha'**
  String get myPosition;

  /// No description provided for @statusSub.
  ///
  /// In cs, this message translates to:
  /// **'v pořádku, pomoc, zraněn…'**
  String get statusSub;

  /// No description provided for @rallySub.
  ///
  /// In cs, this message translates to:
  /// **'místo a čas setkání'**
  String get rallySub;

  /// No description provided for @sitrepSub.
  ///
  /// In cs, this message translates to:
  /// **'stav, počet osob, krátký text'**
  String get sitrepSub;

  /// No description provided for @salterSub.
  ///
  /// In cs, this message translates to:
  /// **'pozorování: velikost, činnost, místo, čas, vybavení, poznámky'**
  String get salterSub;

  /// No description provided for @fiveWSub.
  ///
  /// In cs, this message translates to:
  /// **'kdo, co, kde, kdy, proč'**
  String get fiveWSub;

  /// No description provided for @positionCaps.
  ///
  /// In cs, this message translates to:
  /// **'POLOHA'**
  String get positionCaps;

  /// No description provided for @gettingGps.
  ///
  /// In cs, this message translates to:
  /// **'Získávám polohu z GPS…'**
  String get gettingGps;

  /// No description provided for @coordsLabel.
  ///
  /// In cs, this message translates to:
  /// **'Souřadnice (např. 50.0880, 14.4208)'**
  String get coordsLabel;

  /// No description provided for @coordsNotUnderstood.
  ///
  /// In cs, this message translates to:
  /// **'Nerozumím souřadnicím.'**
  String get coordsNotUnderstood;

  /// No description provided for @myPositionGps.
  ///
  /// In cs, this message translates to:
  /// **'Moje poloha (GPS)'**
  String get myPositionGps;

  /// No description provided for @enterManually.
  ///
  /// In cs, this message translates to:
  /// **'Zadat ručně'**
  String get enterManually;

  /// No description provided for @sendCaps.
  ///
  /// In cs, this message translates to:
  /// **'ODESLAT'**
  String get sendCaps;

  /// No description provided for @attachPosition.
  ///
  /// In cs, this message translates to:
  /// **'Přiložit polohu'**
  String get attachPosition;

  /// No description provided for @rallyTime.
  ///
  /// In cs, this message translates to:
  /// **'Čas srazu: {t}'**
  String rallyTime(String t);

  /// No description provided for @inMinutes.
  ///
  /// In cs, this message translates to:
  /// **'za {n} min'**
  String inMinutes(int n);

  /// No description provided for @inHours.
  ///
  /// In cs, this message translates to:
  /// **'za {n} h'**
  String inHours(int n);

  /// No description provided for @dateAndTime.
  ///
  /// In cs, this message translates to:
  /// **'datum a čas'**
  String get dateAndTime;

  /// No description provided for @stateCaps.
  ///
  /// In cs, this message translates to:
  /// **'STAV'**
  String get stateCaps;

  /// No description provided for @personCount.
  ///
  /// In cs, this message translates to:
  /// **'Počet osob'**
  String get personCount;

  /// No description provided for @shortText.
  ///
  /// In cs, this message translates to:
  /// **'Krátký text'**
  String get shortText;

  /// No description provided for @tooLongSms.
  ///
  /// In cs, this message translates to:
  /// **'Moc dlouhé — musí se vejít do jedné SMS.'**
  String get tooLongSms;

  /// No description provided for @tooLongLora.
  ///
  /// In cs, this message translates to:
  /// **'Texty dohromady moc dlouhé — musí se vejít do jednoho LoRa paketu.'**
  String get tooLongLora;

  /// No description provided for @pickupSite.
  ///
  /// In cs, this message translates to:
  /// **'1  MÍSTO VYZVEDNUTÍ'**
  String get pickupSite;

  /// No description provided for @callsignLabel.
  ///
  /// In cs, this message translates to:
  /// **'2  Volací znak (max. 8 znaků bez diakritiky)'**
  String get callsignLabel;

  /// No description provided for @callsignError.
  ///
  /// In cs, this message translates to:
  /// **'Max. 8 znaků, bez diakritiky.'**
  String get callsignError;

  /// No description provided for @patientsCaps.
  ///
  /// In cs, this message translates to:
  /// **'3  PACIENTI PODLE NALÉHAVOSTI'**
  String get patientsCaps;

  /// No description provided for @line4.
  ///
  /// In cs, this message translates to:
  /// **'4  Zvláštní vybavení'**
  String get line4;

  /// No description provided for @line5Litter.
  ///
  /// In cs, this message translates to:
  /// **'5  Na nosítkách'**
  String get line5Litter;

  /// No description provided for @line5Ambulatory.
  ///
  /// In cs, this message translates to:
  /// **'5  Chodící'**
  String get line5Ambulatory;

  /// No description provided for @line6.
  ///
  /// In cs, this message translates to:
  /// **'6  Bezpečnost místa'**
  String get line6;

  /// No description provided for @line7.
  ///
  /// In cs, this message translates to:
  /// **'7  Značení místa'**
  String get line7;

  /// No description provided for @line8.
  ///
  /// In cs, this message translates to:
  /// **'8  Národnost / status'**
  String get line8;

  /// No description provided for @line9.
  ///
  /// In cs, this message translates to:
  /// **'9  Terén / kontaminace'**
  String get line9;

  /// No description provided for @salterSize.
  ///
  /// In cs, this message translates to:
  /// **'S  Velikost (počet osob, vozidel…)'**
  String get salterSize;

  /// No description provided for @salterActivity.
  ///
  /// In cs, this message translates to:
  /// **'A  Činnost'**
  String get salterActivity;

  /// No description provided for @salterLocation.
  ///
  /// In cs, this message translates to:
  /// **'L  MÍSTO'**
  String get salterLocation;

  /// No description provided for @salterTime.
  ///
  /// In cs, this message translates to:
  /// **'T  Čas pozorování: {t}'**
  String salterTime(String t);

  /// No description provided for @salterEquipment.
  ///
  /// In cs, this message translates to:
  /// **'E  Vybavení / výzbroj'**
  String get salterEquipment;

  /// No description provided for @salterRemarks.
  ///
  /// In cs, this message translates to:
  /// **'R  Poznámky'**
  String get salterRemarks;

  /// No description provided for @fwWho.
  ///
  /// In cs, this message translates to:
  /// **'Kdo'**
  String get fwWho;

  /// No description provided for @fwWhat.
  ///
  /// In cs, this message translates to:
  /// **'Co'**
  String get fwWhat;

  /// No description provided for @fwWhere.
  ///
  /// In cs, this message translates to:
  /// **'KDE'**
  String get fwWhere;

  /// No description provided for @fwWhen.
  ///
  /// In cs, this message translates to:
  /// **'Kdy: {t}'**
  String fwWhen(String t);

  /// No description provided for @fwWhy.
  ///
  /// In cs, this message translates to:
  /// **'Proč'**
  String get fwWhy;

  /// No description provided for @now.
  ///
  /// In cs, this message translates to:
  /// **'teď'**
  String get now;

  /// No description provided for @textBudget.
  ///
  /// In cs, this message translates to:
  /// **'{n} / {max} B'**
  String textBudget(int n, int max);

  /// No description provided for @stSimplex.
  ///
  /// In cs, this message translates to:
  /// **'SimpleX: {s}'**
  String stSimplex(String s);

  /// No description provided for @active.
  ///
  /// In cs, this message translates to:
  /// **'aktivní'**
  String get active;

  /// No description provided for @unavailable.
  ///
  /// In cs, this message translates to:
  /// **'nedostupné'**
  String get unavailable;

  /// No description provided for @stBramble.
  ///
  /// In cs, this message translates to:
  /// **'Bramble: {s}'**
  String stBramble(String s);

  /// No description provided for @waitingNetwork.
  ///
  /// In cs, this message translates to:
  /// **'čeká na síť'**
  String get waitingNetwork;

  /// No description provided for @stSquad.
  ///
  /// In cs, this message translates to:
  /// **'Síť skupiny: {n} v dosahu'**
  String stSquad(int n);

  /// No description provided for @smsNoSim.
  ///
  /// In cs, this message translates to:
  /// **'SMS: bez SIM'**
  String get smsNoSim;

  /// No description provided for @smsNotAllowed.
  ///
  /// In cs, this message translates to:
  /// **'SMS: nepovoleno'**
  String get smsNotAllowed;

  /// No description provided for @smsReady.
  ///
  /// In cs, this message translates to:
  /// **'SMS: připraveno (jen po potvrzení)'**
  String get smsReady;

  /// No description provided for @loraNotConnected.
  ///
  /// In cs, this message translates to:
  /// **'LoRa: rádio nepřipojeno'**
  String get loraNotConnected;

  /// No description provided for @loraError.
  ///
  /// In cs, this message translates to:
  /// **'LoRa: chyba rádia'**
  String get loraError;

  /// No description provided for @locNoPermission.
  ///
  /// In cs, this message translates to:
  /// **'Bez oprávnění k poloze.'**
  String get locNoPermission;

  /// No description provided for @locOff.
  ///
  /// In cs, this message translates to:
  /// **'Poloha je v telefonu vypnutá.'**
  String get locOff;

  /// No description provided for @locTimeout.
  ///
  /// In cs, this message translates to:
  /// **'GPS zatím nemá fix — zkus venku nebo zadej souřadnice.'**
  String get locTimeout;

  /// No description provided for @locFailed.
  ///
  /// In cs, this message translates to:
  /// **'Polohu se nepodařilo zjistit.'**
  String get locFailed;

  /// No description provided for @invalidContactLink.
  ///
  /// In cs, this message translates to:
  /// **'Neplatný odkaz kontaktu.'**
  String get invalidContactLink;

  /// No description provided for @ownContact.
  ///
  /// In cs, this message translates to:
  /// **'To je tvůj vlastní kontakt.'**
  String get ownContact;

  /// No description provided for @teamOf.
  ///
  /// In cs, this message translates to:
  /// **'Tým {name}'**
  String teamOf(String name);

  /// No description provided for @rcConnectingRelays.
  ///
  /// In cs, this message translates to:
  /// **'připojuji k relé'**
  String get rcConnectingRelays;

  /// No description provided for @rcError.
  ///
  /// In cs, this message translates to:
  /// **'chyba'**
  String get rcError;

  /// No description provided for @rcNotRunning.
  ///
  /// In cs, this message translates to:
  /// **'neběží'**
  String get rcNotRunning;

  /// No description provided for @rcRunning.
  ///
  /// In cs, this message translates to:
  /// **'běží'**
  String get rcRunning;

  /// No description provided for @rcStarting.
  ///
  /// In cs, this message translates to:
  /// **'startuje'**
  String get rcStarting;

  /// No description provided for @rcBtInactive.
  ///
  /// In cs, this message translates to:
  /// **'neaktivní (zapni Bluetooth)'**
  String get rcBtInactive;

  /// No description provided for @rcBrambleNotRunning.
  ///
  /// In cs, this message translates to:
  /// **'Bramble neběží'**
  String get rcBrambleNotRunning;

  /// No description provided for @rcNoRadio.
  ///
  /// In cs, this message translates to:
  /// **'bez rádia'**
  String get rcNoRadio;

  /// No description provided for @rcConnectingRadio.
  ///
  /// In cs, this message translates to:
  /// **'připojuji rádio'**
  String get rcConnectingRadio;

  /// No description provided for @stLora.
  ///
  /// In cs, this message translates to:
  /// **'LoRa: {s}'**
  String stLora(String s);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['cs', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
