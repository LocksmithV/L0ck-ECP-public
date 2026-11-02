# L0ck-ECP — Emergency Coordination Platform

> **Stav: testování.** Aplikace je funkční a ověřená na dvou telefonech, ale jde o testovací
> sestavení, ne o stabilní vydání. Formáty zpráv se ještě mohou změnit a APK je podepsané
> vývojovým klíčem.

Šifrovaný komunikátor a koordinační nástroj pro Android, určený pro malé týmy v situacích,
kdy běžná síť selhává nebo není k dispozici: výpadky internetu a mobilní sítě, živelní
pohromy, odlehlé oblasti, terénní akce, dobrovolnické a záchranné týmy.

*English: L0ck-ECP is an encrypted messaging and coordination app for small teams when
regular networks are unreliable or down. One encrypted message, several paths — SimpleX,
Tor/Wi-Fi/Bluetooth, LoRa radio and SMS — with automatic fallback, team channels and
standardised compact reports with GPS position. Czech and English UI. Currently in testing.*

## Stažení

Testovací sestavení **L0ck-ECP_v1.apk** je v [Releases](../../releases) (Android 8.0+,
arm64). Kontrolní součet SHA-256 je u vydání.

## Jedna zpráva, víc cest (PACE)

Každá zpráva je jedna šifrovaná obálka ECP; aplikace ji pošle první cestou, která funguje,
a když nepřijde potvrzení, sama zkusí další. Pořadí jde v nastavení změnit.

| Vrstva | Kanál | Kdy pomůže |
|---|---|---|
| **P** — Primary | [SimpleX](https://simplex.chat/) — relé bez uživatelských identifikátorů | běžný internet |
| **A** — Alternate | Bramble (transportní vrstva [Briar](https://briarproject.org/)) — Tor, místní Wi-Fi, Bluetooth | omezený internet, telefony blízko sebe |
| **C** — Contingency | LoRa přes rádio [MeshCore](https://meshcore.io) (companion, např. Heltec V3 přes Bluetooth) | bez internetu i mobilní sítě, dosah kilometry, i přes okolní repeatery |
| **E** — Emergency | SMS, vždy až po potvrzení uživatelem | jen mobilní síť |

Zprávy bez spojení čekají ve frontě a odejdou samy. U zpráv je čas, doručení a přečtení.
Veřejné kanály MeshCore aplikace ignoruje.

## Co aplikace umí

- **Kontakty** se přidávají skenem QR osobně (ověření) nebo odkazem; změna vlastního
  telefonního čísla (např. místní SIM) se kontaktům rozešle sama.
- **Týmy:** založení a připojení přes týmové QR, týmová konverzace, místní síť skupiny
  přes Wi-Fi/Bluetooth, soukromý kanál LoRa, rozeslání i členům mimo dosah.
- **Standardizovaná hlášení:** poloha, STATUS, SRAZ (místo a čas), SITREP, MEDEVAC 9-line,
  SALTER (pozorování), 5W (kdo, co, kde, kdy, proč). Kompaktní — vejdou se do jednoho LoRa
  paketu a nejvýš dvou SMS. Poloha z GPS bez služeb Google; příjemce vidí souřadnice,
  vzdálenost a azimut a může bod otevřít v offline mapě (OsmAnd, Organic Maps).
- **Bezpečnost:** šifrování end-to-end, šifrované úložiště (SQLCipher) chráněné PINem
  (Argon2id, klíč vázaný na zařízení), nouzový (duress) kód, ochrana obrazovky, oznámení
  bez obsahu, nouzové uzamčení čtyřmi rychlými klepnutími. Žádné účty ani registrace.
- **Provoz:** běží na pozadí i se zamčenou obrazovkou; obnovení jednotlivých kanálů
  v nastavení; čeština a angličtina.

## Omezení

LoRa má malou propustnost (krátké zprávy a hlášení). SMS prozrazuje operátorovi metadata.
Tor přidává zpoždění, Bluetooth má dosah desítek metrů. Nástroj vyžaduje přípravu
a nácvik před nasazením a **nenahrazuje tísňové linky (112)** ani oficiální záchranné
složky.

## Struktura repozitáře

| Cesta | Obsah |
|---|---|
| `app/` | aplikace (Flutter, balíček `cz.l0ck.ecp`) |
| `packages/ecp_core/` | obálka ECP, kryptografie, kontaktní karta, hlášení, PACE router (čistý Dart) |
| `packages/ecp_meshcore/` | companion protokol MeshCore |
| `packages/ecp_simplex/` | napojení na jádro SimpleX (FFI / WebSocket) |
| `tools/` | testovací uzly pro laptop (`ecp_peer`, `bramble-peer`) |
| `docs/ARCHITECTURE_V2.md` | návrh, formáty zpráv, stav implementace, otevřené otázky |

## Sestavení

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

## Licence

L0ck-ECP je svobodný software pod licencí **GNU Affero General Public License v3.0**
([LICENSE](LICENSE)). Kdo aplikaci šíří nebo provozuje upravenou, musí zpřístupnit i její
zdrojový kód.

Použité komponenty a jejich licence:

| Komponenta | Licence |
|---|---|
| [Briar / Bramble](https://code.briarproject.org/briar/briar) 1.5.24 | GPLv3 |
| [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) core 7.0.3 | AGPLv3 |
| [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded) | Apache 2.0 |
| [SQLCipher](https://www.zetetic.net/sqlcipher/) (přes `sqlite3`) | BSD-style |
| [libsodium](https://libsodium.org) (přes `sodium`) | ISC |
| [Flutter](https://flutter.dev), [drift](https://drift.simonbinder.eu), `cryptography` | BSD / MIT / Apache 2.0 |

Protokol companion rádia MeshCore je implementovaný v `packages/ecp_meshcore`; firmware
[MeshCore](https://meshcore.io) běží v rádiu a není součástí aplikace.

## Upozornění

Aplikace je určená k zákonnému použití. Není určená k porušování zákonů země, kde se
používá. Autor nenese odpovědnost za způsob jejího použití ani za škody z něj vzniklé.
Software je poskytován „tak, jak je“, bez záruky.

## Autor

L0ckSm1thV — [GitHub](https://github.com/LocksmithV) ·
[l0cksm1thv.duckdns.org](https://l0cksm1thv.duckdns.org)
