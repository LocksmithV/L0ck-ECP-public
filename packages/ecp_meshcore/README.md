# ecp_meshcore

PACE vrstva C pro L0ck-ECP: rádia [MeshCore](https://github.com/meshcore-dev/MeshCore)
s firmwarem Companion. Čistý Dart bez I/O (kromě `serial.dart` pro Linux).

- `frames.dart` — rámce companion protokolu (APP_START, DEVICE_QUERY, kanály, binární
  datagramy kanálu, stahování zpráv) a obal pro USB sériovou linku.
- `client.dart` — `CompanionClient`: jeden příkaz naráz, odpověď podle typu, stažení
  fronty z rádia po notifikaci „zprávy čekají“.
- `transport.dart` — `MeshCoreTransport`: ECP obálky jako datagramy kanálu `ecp`
  (`data_type` 0xFFEC), flood; společný ECP kanál nebo soukromý kanál skupiny. Vše ostatní
  na rádiu ignoruje.
- `serial.dart` — `SerialLink` pro rádio na `/dev/ttyUSB*` (laptopový uzel, `tool/probe.dart`).

Spojení s rádiem dodá ten, kdo balíček používá (`FrameLink`): aplikace přes BLE
(`RadioHost.java`), laptop přes USB. Podrobnosti v `docs/ARCHITECTURE_V2.md` §7.

```bash
dart test
dart run tool/probe.dart /dev/ttyUSB0   # jen čtení
```
