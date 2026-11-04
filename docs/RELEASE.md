# Vydání a podpis

## Podpisový klíč

Od verze 0.3.0 se APK podepisuje vlastním klíčem, ne vývojovým klíčem Flutteru.

- Klíč: `~/.l0ck-ecp-signing/l0ck-ecp-release.jks` (PKCS12, RSA 4096, alias `l0ck-ecp`,
  platnost do roku 2056), mimo repozitář.
- Hesla: `~/.l0ck-ecp-signing/key.properties` a jeho kopie `app/android/key.properties`
  (Git ho ignoruje). `app/android/app/build.gradle.kts` ho načte; bez něj se release
  podepíše vývojovým klíčem.
- **Zálohuj** celý adresář `~/.l0ck-ecp-signing/` offline (šifrovaný disk, papír pro heslo).
  Bez klíče nejde vydat aktualizaci, kterou by telefony přijaly přes nainstalovanou verzi.
- Otisk certifikátu (SHA-256), podle kterého si kdokoli ověří, že APK je originál:

  ```
  7A:19:E3:4B:A8:0B:DC:19:14:8F:B7:21:47:01:B5:79:D9:67:A0:DB:0B:21:8C:71:F8:7D:9B:F4:FE:17:A4:F0
  ```

  Ověření: `apksigner verify --print-certs L0ck-ECP_vX.apk` (Android SDK build-tools).

Přechod z vývojového klíče: Android nepovolí instalaci přes aplikaci podepsanou jiným
klíčem. Testovací verze do 0.2.3 je potřeba odinstalovat (profil v telefonu tím zanikne)
a nainstalovat novou; skupinu pak jde rychle obnovit balíčkem ze základny.

## Sestavení

Nástroje (verze, se kterými se vydává):

| Nástroj | Verze |
|---|---|
| Flutter | 3.47.9 (stable) |
| JDK | 17 |
| Android NDK | 28.2.13676358 |
| Briar / Bramble | 1.5.24 (`app/android/bramble/build-bramble.sh`) |
| SimpleX core | 7.0.3 (`app/android/simplex/fetch-simplex.sh`, z oficiálního APK, ověřené SHA-256) |

Závislosti Dartu jsou zamčené v `pubspec.lock`, knihovny stránky základny v
`tools/ecp_base/vendor/SHA256SUMS`, `flutter_webrtc` je připnutý na 1.6.2+hotfix.4.

```bash
cd app && dart run build_runner build
flutter build apk --release --target-platform android-arm64
sha256sum build/app/outputs/flutter-apk/app-release.apk
```

32bitové telefony (armeabi-v7a): `app/android/simplex/fetch-simplex.sh armeabi-v7a`
(jádro SimpleX z `simplex-armv7a.apk`, ověřené SHA-256) a
`flutter build apk --release --target-platform android-arm` → `L0ck-ECP_vX-armv7.apk`.

## F-Droid a ověřitelné sestavení (zatím ne)

F-Droid sestavuje vše ze zdrojů. Překážky:

1. **SimpleX core** (`libsimplex.so`, Haskell) se bere hotový z oficiálního APK SimpleX;
   pro F-Droid by se musel sestavit ze zdrojů (GHC pro Android).
2. **WebRTC** (`io.github.webrtc-sdk:android`) je hotová knihovna z Mavenu; F-Droid ji
   nepřijme bez sestavení ze zdrojů.
3. Bramble se už sestavuje ze zdrojů Briaru (`build-bramble.sh`) — v pořádku.

Do té doby: vydání na GitHubu s otiskem certifikátu a SHA-256 souborů. Ověřitelné
sestavení (stejné bajty z čistého checkoutu) je dalším krokem: připnout přesné verze
Gradle/AGP, vypnout časová razítka a porovnat dvě nezávislá sestavení.
