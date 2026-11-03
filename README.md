# L0ck-ECP — Emergency Coordination Platform

![L0ck-ECP](docs/images/L0ck-ECP_background.png)

**[English](#english)** · **[Česky](#česky)**

## English

> **Status: testing.** The app works and has been tested on two phones, but this is a test
> build, not a stable release. Message formats may still change and the APK is signed with
> a development key.

An encrypted messenger and coordination tool for Android, built for small teams when
regular networks fail or are not available: internet and mobile outages, natural
disasters, remote areas, field events, volunteer and rescue teams.

### Download

The current test build **L0ck-ECP_v0.1.2.apk** is under [Releases](../../releases)
(Android 8.0+, arm64), with its SHA-256 checksum.

### One message, several paths (PACE)

Every message is one encrypted ECP envelope. The app sends it over the first path that
works and, when no acknowledgement comes back, tries the next one by itself. Channels that
cannot work right now (no internet, radio not connected) are skipped at once. The order
can be changed in the settings.

| Layer | Channel | When it helps |
|---|---|---|
| **P** — Primary | [SimpleX](https://simplex.chat/) — relays without user identifiers | regular internet |
| **A** — Alternate | Bramble (the transport layer of [Briar](https://briarproject.org/)) — Tor, local Wi-Fi, Bluetooth | limited internet, phones close to each other |
| **C** — Contingency | LoRa via a [MeshCore](https://meshcore.io) radio (companion, e.g. Heltec V3 over Bluetooth) | no internet and no mobile network, kilometres of range, also through nearby repeaters |
| **E** — Emergency | SMS, always only after the user confirms | mobile network only |

Messages without a connection wait in a queue and go out by themselves. Each message shows
its time, delivery and read state. Public MeshCore channels are ignored.

### Features

- **Contacts** are added by scanning a QR code in person (verified) or by a link; a change
  of the own phone number (e.g. a local SIM) reaches the contacts automatically.
- **Teams:** create and join with a team QR code, team conversation, a local squad net over
  Wi-Fi/Bluetooth, a private LoRa channel, delivery to members out of range as well.
- **Standardised reports:** position, STATUS, RALLY (place and time), SITREP, MEDEVAC
  9-line, SALTER (observation), 5W (who, what, where, when, why). Compact — each fits one
  LoRa packet and at most two SMS. GPS position without Google services; the receiver sees
  the coordinates, distance and bearing, and can open the point in an offline map
  (OsmAnd, Organic Maps). A report can be sent from the home screen to a team and to
  several contacts at once.
- **Group setup at the base:** an offline page on a laptop (`tools/ecp_base`) scans every
  phone's contact QR, creates the teams and shows one group bundle as a series of QR
  codes; each phone scans it and gets every contact (verified), its teams, the team's
  LoRa channel and the PACE order. One scan per phone instead of everyone scanning
  everyone.
- **PANIC and COMPROMISED** on the PIN screen, without the PIN, while the app runs: PANIC
  sends the configured status, position and text to contacts and teams over every channel
  at once; COMPROMISED (with a confirmation elsewhere on the screen) reports "compromised"
  and destroys the profile the way the duress code does.
- **Security:** end-to-end encryption, encrypted storage (SQLCipher) protected by a PIN
  (Argon2id, key bound to the device), duress code, screen protection, notifications
  without content, emergency lock by four quick taps. Locking at once, after a delay or
  only by hand; optional fingerprint to return to the running profile (only with PANIC
  and COMPROMISED on, PIN again after a restart, the emergency lock or 8 hours). Factory
  reset in the settings. No accounts, no sign-up.
- **Operation:** runs in the background and with the screen locked; per-channel reconnect
  in the settings; Czech and English.

### Limitations

LoRa has little bandwidth (short messages and reports). SMS exposes metadata to the
operator. Tor adds latency, Bluetooth reaches tens of metres. The tool needs preparation
and practice before it is relied on, and it **does not replace emergency numbers (112)**
or official rescue services.

### Repository layout

| Path | Contents |
|---|---|
| `app/` | the app (Flutter, package `cz.l0ck.ecp`) |
| `packages/ecp_core/` | ECP envelope, cryptography, contact card, reports, PACE router (pure Dart) |
| `packages/ecp_meshcore/` | MeshCore companion protocol |
| `packages/ecp_simplex/` | binding to the SimpleX core (FFI / WebSocket) |
| `tools/ecp_base/` | offline base page for group setup (open `index.html` in a browser) |
| `tools/` | laptop test nodes (`ecp_peer`, `bramble-peer`) |
| `docs/ARCHITECTURE_V2.md` | design, message formats, implementation status, open questions (Czech) |

### Building

Requires Flutter 3.47+, JDK 17, Android SDK and NDK 28.

```bash
app/android/bramble/build-bramble.sh      # Bramble from Briar 1.5.24 into a local Maven repo
app/android/simplex/fetch-simplex.sh      # libsimplex.so from the official SimpleX v7.0.3 APK (verified)
cd app && dart run build_runner build      # generates database.g.dart (drift)
flutter build apk --release --target-platform android-arm64
```

The scripts keep tools and downloads in `~/.l0ck-ecp-toolchain/` (override with
`BRIAR_SRC`, `BRAMBLE_M2`, `SIMPLEX_DL`).

Tests: `cd packages/ecp_core && dart test`, `cd app && flutter test`.

### License

L0ck-ECP is free software under the **GNU Affero General Public License v3.0**
([LICENSE](LICENSE)). Whoever distributes the app, or runs a modified version of it,
must make its source code available too.

Components and their licenses:

| Component | License |
|---|---|
| [Briar / Bramble](https://code.briarproject.org/briar/briar) 1.5.24 | GPLv3 |
| [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) core 7.0.3 | AGPLv3 |
| [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded) | Apache 2.0 |
| [jsQR](https://github.com/cozmo/jsQR) 1.4.0 (base page) | Apache 2.0 |
| [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) 1.4.4 (base page) | MIT |
| [SQLCipher](https://www.zetetic.net/sqlcipher/) (via `sqlite3`) | BSD-style |
| [libsodium](https://libsodium.org) (via `sodium`) | ISC |
| [Flutter](https://flutter.dev), [drift](https://drift.simonbinder.eu), `cryptography` | BSD / MIT / Apache 2.0 |

The MeshCore companion protocol is implemented in `packages/ecp_meshcore`; the
[MeshCore](https://meshcore.io) firmware runs on the radio and is not part of the app.

### Disclaimer

The app is intended for lawful use. It is not meant for breaking the laws of the country
where it is used. The author bears no responsibility for how it is used or for any damage
resulting from its use. The software is provided "as is", without warranty.

### Author

L0ckSm1thV — [GitHub](https://github.com/LocksmithV) ·
[l0cksm1thv.duckdns.org](https://l0cksm1thv.duckdns.org)

---

## Česky

> **Stav: testování.** Aplikace je funkční a ověřená na dvou telefonech, ale jde o testovací
> sestavení, ne o stabilní vydání. Formáty zpráv se ještě mohou změnit a APK je podepsané
> vývojovým klíčem.

Šifrovaný komunikátor a koordinační nástroj pro Android, určený pro malé týmy v situacích,
kdy běžná síť selhává nebo není k dispozici: výpadky internetu a mobilní sítě, živelní
pohromy, odlehlé oblasti, terénní akce, dobrovolnické a záchranné týmy.

### Stažení

Aktuální testovací sestavení **L0ck-ECP_v0.1.2.apk** je v [Releases](../../releases)
(Android 8.0+, arm64). Kontrolní součet SHA-256 je u vydání.

### Jedna zpráva, víc cest (PACE)

Každá zpráva je jedna šifrovaná obálka ECP; aplikace ji pošle první cestou, která funguje,
a když nepřijde potvrzení, sama zkusí další. Kanály, které právě fungovat nemohou (bez
internetu, rádio nepřipojené), přeskočí hned. Pořadí jde v nastavení změnit.

| Vrstva | Kanál | Kdy pomůže |
|---|---|---|
| **P** — Primary | [SimpleX](https://simplex.chat/) — relé bez uživatelských identifikátorů | běžný internet |
| **A** — Alternate | Bramble (transportní vrstva [Briar](https://briarproject.org/)) — Tor, místní Wi-Fi, Bluetooth | omezený internet, telefony blízko sebe |
| **C** — Contingency | LoRa přes rádio [MeshCore](https://meshcore.io) (companion, např. Heltec V3 přes Bluetooth) | bez internetu i mobilní sítě, dosah kilometry, i přes okolní repeatery |
| **E** — Emergency | SMS, vždy až po potvrzení uživatelem | jen mobilní síť |

Zprávy bez spojení čekají ve frontě a odejdou samy. U zpráv je čas, doručení a přečtení.
Veřejné kanály MeshCore aplikace ignoruje.

### Co aplikace umí

- **Kontakty** se přidávají skenem QR osobně (ověření) nebo odkazem; změna vlastního
  telefonního čísla (např. místní SIM) se kontaktům rozešle sama.
- **Týmy:** založení a připojení přes týmové QR, týmová konverzace, místní síť skupiny
  přes Wi-Fi/Bluetooth, soukromý kanál LoRa, rozeslání i členům mimo dosah.
- **Standardizovaná hlášení:** poloha, STATUS, SRAZ (místo a čas), SITREP, MEDEVAC 9-line,
  SALTER (pozorování), 5W (kdo, co, kde, kdy, proč). Kompaktní — vejdou se do jednoho LoRa
  paketu a nejvýš dvou SMS. Poloha z GPS bez služeb Google; příjemce vidí souřadnice,
  vzdálenost a azimut a může bod otevřít v offline mapě (OsmAnd, Organic Maps). Hlášení
  jde z úvodní obrazovky poslat týmu i více kontaktům najednou.
- **Hromadné nastavení na základně:** offline stránka na notebooku (`tools/ecp_base`)
  načte kontaktní QR všech telefonů, založí týmy a ukáže jeden balíček skupiny jako sérii
  QR kódů; každý telefon ho načte a dostane všechny kontakty (ověřené), svoje týmy, kanál
  LoRa týmu a pořadí PACE. Jedno skenování na telefon místo skenování každý s každým.
- **PANIC a KOMPROMITOVÁN** na obrazovce PINu, bez PINu, dokud aplikace běží: PANIC pošle
  nastavený stav, polohu a text kontaktům a týmům všemi kanály najednou; KOMPROMITOVÁN
  (s potvrzením na jiném místě obrazovky) ohlásí kompromitaci a zničí profil jako duress
  kód.
- **Bezpečnost:** šifrování end-to-end, šifrované úložiště (SQLCipher) chráněné PINem
  (Argon2id, klíč vázaný na zařízení), nouzový (duress) kód, ochrana obrazovky, oznámení
  bez obsahu, nouzové uzamčení čtyřmi rychlými klepnutími. Zamykání ihned, po zvolené
  době nebo jen ručně; volitelně otisk prstu pro návrat do běžícího profilu (jen se
  zapnutým PANIC a KOMPROMITOVÁN, PIN znovu po restartu, nouzovém zamknutí a po 8 h).
  Obnovení továrního nastavení v nastavení. Žádné účty ani registrace.
- **Provoz:** běží na pozadí i se zamčenou obrazovkou; obnovení jednotlivých kanálů
  v nastavení; čeština a angličtina.

### Omezení

LoRa má malou propustnost (krátké zprávy a hlášení). SMS prozrazuje operátorovi metadata.
Tor přidává zpoždění, Bluetooth má dosah desítek metrů. Nástroj vyžaduje přípravu
a nácvik před nasazením a **nenahrazuje tísňové linky (112)** ani oficiální záchranné
složky.

### Struktura repozitáře

| Cesta | Obsah |
|---|---|
| `app/` | aplikace (Flutter, balíček `cz.l0ck.ecp`) |
| `packages/ecp_core/` | obálka ECP, kryptografie, kontaktní karta, hlášení, PACE router (čistý Dart) |
| `packages/ecp_meshcore/` | companion protokol MeshCore |
| `packages/ecp_simplex/` | napojení na jádro SimpleX (FFI / WebSocket) |
| `tools/ecp_base/` | offline stránka základny pro hromadné nastavení (`index.html` v prohlížeči) |
| `tools/` | testovací uzly pro laptop (`ecp_peer`, `bramble-peer`) |
| `docs/ARCHITECTURE_V2.md` | návrh, formáty zpráv, stav implementace, otevřené otázky |

### Sestavení

Potřeba: Flutter 3.47+, JDK 17, Android SDK a NDK 28.

```bash
app/android/bramble/build-bramble.sh      # Bramble z Briar 1.5.24 do lokálního Mavenu
app/android/simplex/fetch-simplex.sh      # libsimplex.so z oficiálního APK SimpleX v7.0.3 (ověřeno)
cd app && dart run build_runner build      # vygeneruje database.g.dart (drift)
flutter build apk --release --target-platform android-arm64
```

Skripty ukládají nástroje a stažené soubory do `~/.l0ck-ecp-toolchain/` (jiné místo:
proměnné `BRIAR_SRC`, `BRAMBLE_M2`, `SIMPLEX_DL`).

Testy: `cd packages/ecp_core && dart test`, `cd app && flutter test`.

### Licence

L0ck-ECP je svobodný software pod licencí **GNU Affero General Public License v3.0**
([LICENSE](LICENSE)). Kdo aplikaci šíří nebo provozuje upravenou, musí zpřístupnit i její
zdrojový kód.

Použité komponenty a jejich licence:

| Komponenta | Licence |
|---|---|
| [Briar / Bramble](https://code.briarproject.org/briar/briar) 1.5.24 | GPLv3 |
| [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) core 7.0.3 | AGPLv3 |
| [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded) | Apache 2.0 |
| [jsQR](https://github.com/cozmo/jsQR) 1.4.0 (stránka základny) | Apache 2.0 |
| [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) 1.4.4 (stránka základny) | MIT |
| [SQLCipher](https://www.zetetic.net/sqlcipher/) (přes `sqlite3`) | BSD-style |
| [libsodium](https://libsodium.org) (přes `sodium`) | ISC |
| [Flutter](https://flutter.dev), [drift](https://drift.simonbinder.eu), `cryptography` | BSD / MIT / Apache 2.0 |

Protokol companion rádia MeshCore je implementovaný v `packages/ecp_meshcore`; firmware
[MeshCore](https://meshcore.io) běží v rádiu a není součástí aplikace.

### Upozornění

Aplikace je určená k zákonnému použití. Není určená k porušování zákonů země, kde se
používá. Autor nenese odpovědnost za způsob jejího použití ani za škody z něj vzniklé.
Software je poskytován „tak, jak je“, bez záruky.
