# ecp_core

Jádro L0ck-ECP v čistém Dartu (bez Flutteru): identitní klíče, ECP obálka, kompaktní
formáty zpráv (poloha, hlášení, ACK), kontaktní karta pro QR a PINem chráněné sloty
klíčů s duress kódem. Návrh a binární formáty: [docs/ARCHITECTURE_V2.md](../../docs/ARCHITECTURE_V2.md).

Staví jen na balíčku `cryptography` a standardních primitivách (X25519, ChaCha20-Poly1305,
HKDF-SHA256, Argon2id). Testy ověřují i samotná primitiva proti vektorům z RFC 7748,
8439 a 5869 a hlídají, že každé hlášení se vejde do jedné SMS a jednoho LoRa paketu.

```bash
dart pub get
dart analyze
dart test
dart run tool/kdf_bench.dart   # doba produkčního Argon2id na tomhle stroji
```
