# ecp_simplex

PACE vrstva P pro L0ck-ECP: ECP obálky přes [SimpleX Chat](https://simplex.chat) (AGPLv3).

- `src/transport.dart` — `SimplexTransport`: profil `ecp-<hash klíče>`, kontaktní adresa
  s automatickým přijímáním, párování kontaktů podle jména profilu, obálky jako text
  `ecp1:` + base64url; vše ostatní ignoruje.
- `src/api.dart` — abstraktní `SimplexApi` (textový příkaz → JSON výsledek, proud událostí).
- `ffi.dart` — `FfiSimplex` nad `libsimplex.so` (telefon; viz `app/android/simplex/fetch-simplex.sh`).
- `ws.dart` — `WsSimplex` nad WebSocket serverem CLI `simplex-chat -p PORT` (laptop).

```bash
dart test                                   # proti falešnému SimpleX
dart run tool/live_pair.dart 5301 5302      # dva CLI přes skutečnou síť SimpleX
```
