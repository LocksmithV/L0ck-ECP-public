# L0ck-ECP — nová aplikace (v2)

Přestavba L0ck-ECP pro Evasion podle [docs/ARCHITECTURE_V2.md](../docs/ARCHITECTURE_V2.md).
Balíček `cz.l0ck.ecp`, takže během přechodu běží vedle staré aplikace (`com.lock.lock_ecp`,
kořen repa, tag `legacy`).

Stav F4: kanál E přes SMS (jen po potvrzení), skenování QR (ZXing), týmy a síť skupiny (Bramble LAN/Bluetooth + kanál LoRa týmu), kanál P přes SimpleX, kanál A přes Bramble (Tor, LAN, Bluetooth), kanál C přes rádio
MeshCore (BLE; obrazovka Rádio LoRa), služba na pozadí — zámek zamyká jen obrazovku, zprávy
chodí dál. Vzhled podle značky L0ck-ECP (logo, paleta, lišta COMMS v pořadí PACE). Dříve (F3): první spuštění (přezdívka, PIN, duress kód), zámek, domovská obrazovka s otiskem
a vlastním kontaktním QR, kontakty (přidání z odkazu `l0ck://c/…` s ověřovacím číslem)
a konverzace se stavem doručení přes PACE router. Pod tím sloty klíčů s duress, nativní
Argon2id (libsodium), posílení přes Android Keystore a šifrovaná databáze (SQLCipher).
SMS naostro a Bluetooth síť skupiny čekají na test dvou telefonů, mapa, hlášení a skenování
QR v F5.

## Sestavení

Potřeba: Flutter 3.47, Android SDK 36, NDK 28.2.13676358 (libsodium se kompiluje ze
zdrojů přes build hooks), JDK 17–21.

Nejdřív jednou Bramble (Briarovo jádro, GPLv3) do lokálního Maven repa
`~/.l0ck-ecp-toolchain/m2` (jiné místo: `BRAMBLE_M2`):

```bash
git clone --depth 1 --branch release-1.5.24 https://code.briarproject.org/briar/briar.git ~/.l0ck-ecp-toolchain/src/briar
android/bramble/build-bramble.sh
```

a jádro SimpleX (≈190 MB, ověřené APK v7.0.3, do `android/app/src/main/jniLibs`, mimo git):

```bash
android/simplex/fetch-simplex.sh
```

Pak aplikace:

```bash
flutter pub get
dart run build_runner build      # vygeneruje lib/data/database.g.dart (není v gitu)
flutter test                     # mimo jiné nativní vs. dartový Argon2id a SQLCipher
flutter build apk --release --target-platform android-arm64
```

Na LineageOS je potřeba aplikaci povolit **Přístup k síti** (Nastavení → Aplikace →
L0ck-ECP → Mobilní data a Wi-Fi), jinak Tor nenaběhne.

Kontakt, který už existuje, jde znovu načíst z novější karty — doplní nové kanály
(např. adresu SimpleX).

Test bez druhého telefonu: `tools/ecp_peer` (viz jeho README) je ECP uzel na laptopu
s Bramble přes `tools/bramble-peer`.

Release build je zatím podepsaný debug klíčem z šablony Flutteru — před distribucí potřebuje
vlastní release keystore mimo repo.
