# Nástroje pro testování na laptopu

Druhý telefon zatím není, tak jeho roli hraje laptop.

- **`bramble-peer/`** — Bramble uzel (Tor + LAN) s klientem ECP obálek z
  `app/android/bramble-ecp`, ovládaný řádkovým protokolem na stdin/stdout (JSON odpovědi a
  události). Sestavení (po `app/android/bramble/build-bramble.sh`):

  ```bash
  cd tools/bramble-peer && gradle installDist
  ```

- **`ecp_peer/`** — plný ECP uzel: identita, kontakty, PACE router z `ecp_core`, vrstva P
  přes CLI SimpleX (`--simplex PORT`, viz níže), vrstva A
  přes `bramble-peer` a vrstva C přes rádio MeshCore na USB (`--lora /dev/ttyUSB0`,
  vlastní kanál skupiny `--lora-key KLÍČ`). `--no-bramble` vypne vrstvu A (test eskalace na
  LoRa). S `--echo` odpoví na každou textovou zprávu.

  ```bash
  cd tools/ecp_peer && dart pub get
  dart run bin/ecp_peer.dart /tmp/ecp-peer ../bramble-peer/build/install/bramble-peer/bin/bramble-peer --echo
  ```

  Po startu vypíše svou kartu `l0ck://c/…` (vlož ji v aplikaci do „Přidat kontakt“).
  Příkazy: `card`, `add <l0ck://c/…>` (karta z domovské obrazovky telefonu; týmová karta
  zároveň připojí k týmu a přepne LoRa na kanál týmu), `contacts`, `send <jméno> <text>`,
  `tsend <text>` (týmu), `quit`. Obě strany ukážou stejné ověřovací číslo.

SimpleX CLI (ověřené z vydání v7.0.3, `simplex-chat-ubuntu-24_04-x86_64`) jako WebSocket
server pro `--simplex 5302`:

```bash
simplex-chat -d /tmp/sx/db -p 5302 -y --user-display-name ecp
```

Rádio jen přečíst (model, firmware, nastavení, kanály; nic nezapisuje):
`cd packages/ecp_meshcore && dart run tool/probe.dart /dev/ttyUSB0`.

Laptop a telefon na jedné Wi-Fi a bez VPN na laptopu — jinak LAN nenaváže a jede se jen
přes Tor. Oba nástroje linkují Bramble (GPLv3).
