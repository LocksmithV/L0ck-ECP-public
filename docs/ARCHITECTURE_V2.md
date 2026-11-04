# L0ck-ECP — architektura v2 (přestavba pro Evasion)

Stav: návrh F2, 2026-11-01. Nahrazuje kanálovou část `ARCHITECTURE.md` v1.
Rozhodnutí vlastníka: PACE **P SimpleX · A Briar/Bramble přes Tor · C LoRa (Meshtastic +
MeshCore) · E SMS**, lokální síť skupiny (Bluetooth / Wi-Fi / hotspot) **mimo PACE**,
Matrix a Jami vypuštěny, žádná produkční závislost na vlastním serveru, licence AGPLv3.

---

## 1. Princip: jedna obálka, víc cest

```
 Hlášení · poloha · text · mapa (Flutter UI)
                 │
        ECP obálka  ── ecp_core (čistý Dart): klíče, šifrování, formáty zpráv
                 │
        PACE router ── pořadí podle módu, ACK, retry, deduplikace, odchozí fronta (F3)
                 │
 ┌───────────────┼───────────────┬──────────────┬──────────┐
 SimpleX (P)   Bramble/Tor (A)   LoRa (C)        SMS (E)    Síť skupiny (mimo PACE)
 Dart FFI      nativní modul     Meshtastic/     another_   Bramble BT/LAN
               (spike F1)        MeshCore BLE    telephony  + přeposílání s TTL
```

- **Obsah má stejnou ochranu na každém kanálu.** Každá zpráva je ECP obálka; kanál přenáší
  jen neprůhledné bajty (SimpleX a Bramble mají vlastní E2E navíc — dvojí šifrování nevadí).
- **Jeden identifikátor zprávy napříč kanály** → ACK může přijít jinou cestou, než šla zpráva,
  a duplicitní doručení stejné zprávy více kanály se zahodí.
- **Šifrování se nevymýšlí.** Jen standardní primitiva (RFC 7748 X25519, RFC 8439
  ChaCha20-Poly1305, RFC 5869 HKDF-SHA256, RFC 9106 Argon2id) z balíčku `cryptography`.

## 2. Identita a klíče

| Klíč | Typ | K čemu |
|---|---|---|
| Identitní klíč zařízení | X25519, 32 B | párové šifrování ECP obálek; jeho otisk = ověřovací číslo |
| Párové směrové klíče | 2 × 32 B, odvozené | jeden pro směr A→B, jeden pro B→A |
| Týmový klíč | 32 B náhodný | skupinové zprávy (broadcast po LoRa, síť skupiny) |
| Hlavní klíč (MK) | 32 B náhodný | odemyká DB a odvozuje hesla kanálů; chráněný PINem (kap. 6) |

**Párové klíče:**

```
shared   = X25519(můj_privátní, jeho_veřejný)
lo, hi   = seřazené veřejné klíče obou stran (lexikograficky)
okm      = HKDF-SHA256(ikm = shared, salt = "L0ck-ECP v1 pair", info = lo || hi, L = 64)
k_lo→hi  = okm[0:32]      k_hi→lo = okm[32:64]
```

Odesílatel šifruje klíčem svého směru, příjemce opačným. Odraz zprávy zpět odesílateli
tak nejde dešifrovat.

**Dopředná bezpečnost (forward secrecy):** ECP v1 ji pro LoRa a SMS nemá — statické klíče
jsou nutné kvůli ztrátovým kanálům bez stavu. Kompenzace: kanály P a A (SimpleX, Bramble) ji
mají samy; ECP klíče se rotují novou výměnou QR nebo řídicí zprávou přes P/A. Ratchet pro
LoRa/SMS je otevřená otázka pro v2.

## 3. ECP obálka v1 (binární formát)

```
offset  délka  pole
0       1      verze (horní 4 bity = 1) | druh (dolní 4 bity: 0 = párová, 1 = týmová)
1       2      tag (rotující nápověda pro příjemce, viz níže)
3       12     nonce (náhodný)
15      N      šifrovaný vnitřek (ChaCha20-Poly1305, AAD = bajty 0..2)
15+N    16     autentizační značka
```

Režie obálky: **31 B**.

**Tag** dovolí příjemci rychle najít klíč, aniž by zkoušel dešifrovat vším:

```
tag = HMAC-SHA256(k_směru, "tag" || den_UTC_jako_u32)[0:2]
```

Mění se každý den a bez klíče z něj nejde poznat, komu zpráva patří. Příjemce si spočítá
očekávané tagy všech kontaktů pro dnešek a včerejšek; při shodě zkusí dešifrovat (2 B tag
znamená občasnou falešnou shodu, kterou odhalí AEAD).

**Vnitřek (plaintext):**

```
0     1    typ zprávy (kap. 4)
1     1    příznaky: bit0 = žádá ACK, bit1 = priorita, bit2 = podepsáno (rezerva)
2     8    id zprávy (náhodné)
10    4    čas odeslání: sekundy od 2024-01-01T00:00Z, u32
14    2    jen týmová: otisk odesílatele (první 2 B SHA-256 jeho identitního klíče)
...        payload
```

**Ochrana proti přehrání:** příjemce drží id zpráv viděných za posledních 14 dní a zahodí
opakování. Čas se kontroluje volně (±14 dní), protože hodiny zařízení se rozcházejí.

**Týmová obálka:** klíč = týmový klíč, tag = HMAC(týmový klíč, …). Odesílatele určuje
otisk ve vnitřku — kryptograficky ho ale nezaručuje (kterýkoli člen týmu se může vydávat za
jiného). Pro hlášení, kde na tom záleží, je rezervovaný příznak „podepsáno" pro v2.

**Kódování pro kanály:** LoRa a SimpleX/Bramble nesou bajty (případně base64url). SMS nese
base64url **bez rozpoznatelné předpony**; aplikace zkouší dekódovat SMS jen od známých čísel.

## 4. Formáty zpráv (payload)

| Typ | Kód | Payload |
|---|---|---|
| Poloha | 0x01 | lat i32 (1e-7°), lon i32 (1e-7°), výška i16 (m), přesnost u8 (m, max 255), kurz u8 (2°), rychlost u8 (0,5 m/s) — **13 B** |
| Text | 0x02 | UTF-8 |
| Hlášení | 0x03 | id šablony u8 + pole šablony (níže) |
| ACK | 0x04 | id potvrzované zprávy (8 B) |
| Řídicí | 0x05 | rezervováno (rotace klíčů, týmový klíč přes P/A) |

**Šablony hlášení v1:**

| Šablona | Id | Pole |
|---|---|---|
| STATUS | 0x01 | kód u8 (0 OK, 1 potřebuji pomoc, 2 kompromitován, 3 zraněn, 4 v pohybu, 5 na místě), volitelně poloha (13 B) |
| SRAZ | 0x02 | poloha (13 B), čas srazu (u32, stejná epocha) |
| MEDEVAC 9-line | 0x03 | ř.1 poloha (13 B) · ř.2 volací znak (u8 délka + ≤ 8 B ASCII) · ř.3 pacienti dle naléhavosti (5 × u8: A urgentní, B urgentní-chirurgický, C prioritní, D rutinní, E odložitelný) · ř.4 vybavení u8 · ř.5 nosítka/chodící (2 × u8) · ř.6 bezpečnost u8 · ř.7 značení u8 · ř.8 národnost/status u8 · ř.9 terén/NBC u8 |
| SITREP | 0x04 | stav u8, počet osob u8, poloha (13 B), krátký text (≤ 59 B UTF-8) |
| SALTER | 0x05 | S velikost u16 · L poloha (13 B) · T čas pozorování u32 · A činnost, E vybavení, R poznámky (3 texty, každý u8 délka + UTF-8, dohromady ≤ 90 B) |
| 5W | 0x06 | kde: poloha (13 B) · kdy: u32 · kdo, co, proč (3 texty, u8 délka + UTF-8, dohromady ≤ 90 B) |

**Rozpočet velikosti** (obálka 31 B + vnitřek 14 B; hlídá to test `messages_test.dart`):

| Zpráva | Celkem | base64url | Vejde se do |
|---|---|---|---|
| STATUS s polohou | 60 B | 80 znaků | 1 SMS, 1 LoRa paket |
| Poloha | 58 B | 78 znaků | 1 SMS, 1 LoRa paket |
| MEDEVAC (max. volací znak) | 80 B | 107 znaků | 1 SMS, 1 LoRa paket |
| SITREP (max. text 59 B) | 120 B | 160 znaků | 1 SMS (na hraně), 1 LoRa paket |
| SALTER / 5W (texty 90 B) | ≤ 158 B | ≤ 211 znaků | 1 LoRa paket, nejvýš 2 SMS |
| ACK | 53 B | 71 znaků | 1 SMS, 1 LoRa paket |

**Popisky kódů v aplikaci:** STATUS 0 V pořádku, 1 Potřebuji pomoc, 2 Kompromitován, 3 Zraněn,
4 V pohybu, 5 Na místě. SITREP stav 0 Klid, 1 Pozor / sledování, 2 Kontakt, 3 Nouze. MEDEVAC
ř. 4 vybavení 0 žádné, 1 naviják, 2 vyprošťovací technika, 3 ventilátor · ř. 6 bezpečnost
0 bez nepřítele, 1 možný, 2 v oblasti, 3 nutný doprovod · ř. 7 značení 0 panely, 1
pyrotechnika, 2 kouř, 3 žádné, 4 jiné · ř. 8 0 vlastní voják, 1 vlastní civilista, 2 cizí
voják, 3 cizí civilista, 4 zajatec · ř. 9 0 bez kontaminace, 1 N, 2 B, 3 C.

**Hlášení v aplikaci (F5, 2026-11-02):** tlačítko ＋ v přímém i týmovém chatu: poloha, STATUS,
SRAZ, SITREP, MEDEVAC. Poloha z `LocationManager` (GPS → síť → čerstvý poslední fix do 5 min),
bez Google služeb, jen při odeslání hlášení; jde zadat i ručně („50,0880; 14,4208“). Příjemce
vidí souřadnice (DD, 5 míst), přesnost, vzdálenost a azimut od své aktuální polohy (haversine,
`ecp_core/geo.dart`), tlačítko „Mapa“ (intent `geo:` do offline mapové aplikace, např. OsmAnd
nebo Organic Maps z F-Droidu) a kopírování souřadnic. Vlastní offline mapa je další krok.

**SALTER a 5W (2026-11-02):** SALTER = Size, Activity, Location, Time, Equipment, Remarks
(hlášení z pozorování); 5W = Who, What, Where, When, Why. Texty sdílejí jeden rozpočet 90 B
(`maxReportText`), aby se hlášení vešlo do jednoho LoRa paketu; přes SMS jde nejvýš ve dvou.
Prázdné volitelné texty (E, R, proč) zabírají jen bajt délky. Formulář ukazuje zbývající
bajty a čas jde zadat „teď“, „−15 min“… nebo datem a časem.

SITREP má strop 59 B, ne 60: o bajt víc a zpráva by přetekla do druhé SMS. Text s háčky
a čárkami zabírá 2 B na znak, takže česky je to zhruba 30–59 znaků.

## 5. Kontaktní karta (QR)

Jedno QR nastaví všechny vrstvy najednou:

```
l0ck://c/<base64url(karta)>

karta = verze u8 (= 2) || pole*
pole  = tag u8 || délka u16 (big-endian) || hodnota

tag  pole     hodnota
0x01 name     přezdívka, UTF-8 (≤ 24 B)            povinné
0x02 ecp      identitní klíč X25519 (32 B)          povinné
0x03 briar    Briar handshake odkaz (briar://…)     volitelné
0x04 sx       SimpleX odkaz na kontakt              volitelné
0x05 tel      telefon E.164                         volitelné
0x06 mt       Meshtastic node id u32                volitelné
0x07 mc       MeshCore veřejný klíč (32 B)          volitelné
0x10 team     týmový klíč (32 B) — jen týmové QR    volitelné
```

Neznámé tagy se při čtení přeskočí (dopředná kompatibilita). Vlastní TLV místo CBOR, aby
jádro nepotřebovalo další závislost.

**Ověřovací číslo** (jako Signal „safety number"): 12 číslic z
`SHA-256("L0ck-ECP v1 verify" || lo || hi)`, zobrazené na obou telefonech. Při osobní výměně
se porovnají.

**Týmové QR** je oddělené a nese navíc týmový klíč. Ukazuje se **jen osobně**, nikdy se
neposílá — kdo ho vyfotí, čte týmovou komunikaci.

**Tým (F4, 2026-11-02):** týmové QR = vlastní kontaktní karta ukazujícího + týmový klíč
(32 B, náhodný při založení). Načtení přidá (nebo obnoví) ukazujícího jako kontakt a připojí
k týmu. Z klíče se odvodí vše ostatní, takže se členové shodnou bez dalšího přenosu:
`ID týmu = hex(HKDF(klíč, "team-id"))[0:16]`, `klíč kanálu LoRa týmu =
HKDF(klíč, "lora")[0:16]` — rádio se po založení/připojení samo přepne na kanál týmu. Název
týmu je jen místní. Odesílatele týmové zprávy ukazuje 2B otisk (není autentizační; obálku
otevře kdokoli s týmovým klíčem).

## 6. Úložiště, PIN a duress

**Klíčové sloty (místo uloženého hashe PINu):**

```
KEK      = Argon2id(PIN, sůl, m = 64 MiB, t = 3, p = 1) ⊕ posílení klíčem z Android Keystore
slot_i   = ChaCha20-Poly1305(KEK_i, MK_i)
```

- Zařízení má vždy **dva sloty v náhodném pořadí**. Bez duress kódu je druhý slot náhodný
  šum. Úložiště tak neprozradí, jestli duress kód existuje.
- PIN se zkouší proti oběma slotům. Slot, který se otevře, určí profil.
- **Duress kód** otevře návnadový profil (prázdný, věrohodný) a **na pozadí zničí slot
  skutečného profilu a jeho klíč v Keystore** → skutečná data jsou okamžitě nečitelná,
  i když fyzicky zůstanou na flash paměti.
- **Posílení přes Keystore** (neexportovatelný klíč v TEE/StrongBox) znemožní hrubou sílu
  PINu mimo zařízení. Zkopírované úložiště bez telefonu je bezcenné.
- **Chybné pokusy:** trvalé počítadlo; od 3. pokusu narůstající prodleva; po N pokusech
  (výchozí 10) se zničí oba sloty.

**Odvozené klíče z MK:**

```
klíč DB (SQLCipher)    = HKDF(MK, "db")
název souboru DB       = "ecp_" + hex(HKDF(MK, "db-name"))[0:16] + ".db"
adresář profilu Bramble = files/bramble/ + hex(HKDF(MK, "bramble-dir"))[0:32]
adresář DB SimpleX      = <app support>/simplex/ + totéž ID jako Bramble
heslo účtu Bramble     = hex(HKDF(MK, "bramble-password"))     (256 bitů)
heslo DB SimpleX       = hex(HKDF(MK, "simplex"))            (SQLCipher klíč obou DB SimpleX)
```

Všechny databáze (ECP, Bramble, SimpleX, mesh) jsou šifrované. Zničením MK jsou nečitelné.
Názvy souborů a adresářů jsou hashe, nic na disku profil nepojmenuje. Bramble má **vlastní
adresář pro každý profil** (DB, klíče, Tor, mailbox), takže skutečný profil a návnada nesdílí
ani Tor identitu. Totéž platí pro SimpleX. Duress i vymazání smažou adresáře Bramble
a SimpleX všech ostatních profilů; uzel zničeného profilu se nejdřív odpojí.

**Nastavení (2026-11-02):** PIN a duress kód se nikde neukládají, proto je nejde zobrazit,
jen změnit (vždy se současným PINem). Nový PIN = tentýž hlavní klíč zabalený pod nový kód
(odmítne se, kdyby otevřel i druhý slot). Nový duress kód = nová prázdná návnada se stejnou
přezdívkou; stará návnada i její data (DB, Bramble, SimpleX) zmizí; „zrušit“ dá místo ní šum.
Změna přezdívky s duress kódem přejmenuje i návnadu (slot se jen otevře, nic se neničí) —
jinak by pod nátlakem ukázala staré jméno. Nová přezdívka i číslo jdou kontaktům kontrolní
zprávou 0x01. Vlastní číslo se zadává s mezinárodní předvolbou.

**Nouzové zamknutí:** 4× rychlé klepnutí kamkoli (do 1,5 s) aplikaci zamkne a skryje
(`moveTaskToBack`); totéž velké tlačítko v Nastavení. Zprávy dál chodí na pozadí.

**Oznámení:** jen „Nová zpráva“ / „Nové zprávy (N)“, bez odesílatele a textu, i na
zamčené obrazovce; oprávnění se žádá po prvním odemčení. Klepnutí po zadání PINu otevře
konverzaci, ke které oznámení patří (cíl jede jen v intentu, ne na obrazovce).

**Zámek je jen zámek obrazovky (rozhodnutí 2026-11-02):** odemčený profil, Bramble a PACE
router běží dál ve službě na popředí (`EcpService`, typ `remoteMessaging`), aby zprávy
docházely i s telefonem v kapse. Cena: MK zůstává v paměti a v liště je (bez povolených
notifikací skrytá) trvalá notifikace „Aktivní“. Zadání kódu běžícího profilu jen odemkne
obrazovku. Duress kód zadaný při běžícím skutečném profilu ho zavře, zastaví jeho Bramble
uzel, smaže jeho data a otevře návnadu; ta pak do příštího startu procesu jede bez Bramble
(Bramble neumí v jednom procesu nastartovat podruhé). Duress úklid se opakuje při každém
odemčení návnady (zničený slot je k nerozeznání od šumu), proto musí být neškodný.

## 7. PACE router (F3) — pravidla

Implementace: `packages/ecp_core/lib/src/router.dart` (`PaceRouter`). Kanál je pro router
jen `Transport` (`isAvailable`, `canReach`, `sendTo`, `broadcast`), takže skutečné kanály
z F4 se jen zapojí; kanál, který nabíhá déle (Bramble), se přidá za běhu.

**Vrstva P — SimpleX (F4):** `packages/ecp_simplex`. Telefon volá jádro SimpleX Chat
(`libsimplex.so` z oficiálního, reprodukovatelně sestaveného APK v7.0.3, ověřeno podpisem
a hashem; `app/android/simplex/fetch-simplex.sh`) přes Dart FFI, laptop CLI `simplex-chat`
přes jeho WebSocket server. ECP obálka jde jako textová zpráva `ecp1:` + base64url. Profil
SimpleX se jmenuje `ecp-` + 16 hex z SHA-256 ECP klíče; podle toho se SimpleX kontakt páruje
s ECP kontaktem (obě strany znají klíč z karty, jméno klíč neprozradí). Vlastní kontaktní
adresa SimpleX je na kartě (pole 0x04) a žádosti přijímá automaticky — cizí kontakt nic
nedostane, obálky jdou jen známým klíčům. Stačí, když se připojí jedna strana. Běžné texty
SimpleX a skupiny se ignorují. Relé: výchozí servery SimpleX (bez vlastního serveru);
připojení přes Tor (SOCKS z Bramble) zatím není zapnuté.

**Vrstva A — Bramble (F4):** vlastní Bramble klient `cz.l0ck.ecp.envelope`
(`app/android/bramble-ecp`) přenáší ECP obálky jako neprůhledné bajty, jedna skupina na
kontakt (stejně jako soukromé zprávy Briaru, bez briar-core). Bramble dodá Tor, LAN a
Bluetooth, store-and-forward a vlastní šifrování spoje; ECP nad tím dělá end-to-end
šifrování, ACK a deduplikaci. Kontakt Bramble se páruje s ECP kontaktem podle `briar://`
odkazu z kontaktní karty (pole 0x03); Bramble kontakt vznikne, až si odkazy přidají obě
strany (Tor rendezvous). Kontakt je přes Bramble dosažitelný, když k němu vede živé spojení
(LAN, Bluetooth, Tor), nebo běží Tor a telefon má internet. Jen zapnutý Bluetooth nebo LAN
nestačí: router by čekal 120 s na ACK, který nepřijde (2026-11-03).

- Mód určuje pořadí kanálů; výchozí Evasion: **P SimpleX → A Bramble/Tor → C LoRa → E SMS**.
- Zpráva jde nejbezpečnějším **dostupným** kanálem. Když ACK nedorazí v limitu kanálu
  (P 60 s, A 120 s, C 90 s, E 120 s), router pokračuje dalším. SMS se posílá až po potvrzení
  uživatelem nebo v nouzovém módu.
- **Rychlejší přestup (2026-11-03):** kanál, který kontakt právě nedosáhne, se přeskočí hned,
  bez čekání na ACK. Bez internetu (`NetHost.java`: výchozí síť Androidu s `INTERNET`;
  záměrně ne `VALIDATED`, ta se ptá serverů Googlu a tam, kde jsou blokované, by vypnula
  fungující internet) je nedostupný SimpleX i Tor. Když jede jen SMS, potvrzení SMS se
  ukáže hned. Zpráva, která čeká na ACK na kanálu, jenž právě vypadl, přejde na další
  okamžitě (`availabilityChanged`); kdyby dorazila i starou cestou, příjemce duplikát zahodí.
- **Nic není dostupné:** zpráva čeká. Jakmile se kanál objeví (`availabilityChanged`), jde
  nejbezpečnějším z nich; bez změny to router zkusí znovu po 10 min. Po 24 h to vzdá
  (stav „nedoručeno“).
- **ACK** = id zprávy, zapečetěné párovým klíčem. Router ho přijme jen od kontaktu, kterému
  zpráva patřila (cizí ACK ji neuzavře).
- **Duplikáty** (stejná zpráva přišla dvakrát, třeba když se ztratil ACK): příjemce znovu
  potvrdí, ale aplikaci ji nedoručí podruhé. Paměť id (`ReplayGuard`) se ukládá do DB.
- **Odchozí fronta** se ukládá do DB (`OutboxRows`), restart nic neztratí ani neposílá naslepo
  znovu.
- **Nouzový mód:** zpráva jde všemi kanály naráz, SMS bez ptaní.
- **Kontrolní zprávy (typ 0x05):** 0x01 aktualizace karty (jméno, číslo), 0x02 potvrzení o
  přečtení (až 20 id po 8 B), 0x03 „jsem v týmu“ (8B ID týmu, posílá se tomu, čí týmové QR
  člověk načetl), 0x04 „odcházím z týmu“ (8B ID týmu; členové mě vyřadí). Potvrzení o přečtení
  jde `sendOnce`: jeden pokus jen přes P/A, bez ACK,
  nikdy LoRa ani SMS.
- **Pořadí vrstev** si uživatel může v Nastavení přeházet; SMS i tak jen po potvrzení.
- **Týmová zpráva** jde jednou všemi kanály „do éteru“ (síť skupiny, LoRa týmu) a navíc
  stejná obálka každému známému členovi přes první dostupnou z P/A (store-and-forward), takže
  dojde i vzdáleným. Členy aplikace zná: majitel naskenovaného týmového QR, kdo se ohlásil
  zprávou 0x03, kdo do týmu napsal (otisk odesílatele), ruční výběr. Bez ACK; duplicity
  odstraní id.
- **Bluetooth plugin po čisté instalaci:** oprávnění „Zařízení v okolí“ se udělí, až když
  Bramble už startuje; jeho Bluetooth plugin pak zůstane neaktivní. Aplikace ho proto po
  startu (a před „Spojit přes Bluetooth“) vypne a zapne — ověřeno na Nokii: INACTIVE → ACTIVE.
- **Obnovit spojení (Nastavení):** ruční restart jednoho kanálu po výpadku sítě — SimpleX
  (`/reconnect` všech relé), Tor / LAN / Bluetooth (plugin Bramble vypnout a zapnout), LoRa
  (BLE spojení s rádiem znovu), SMS (stav SIM a oprávnění); i „Obnovit vše“.
- **Bluetooth poprvé:** Android aplikaci neprozradí vlastní Bluetooth adresu, takže dva noví
  kontakty se přes Bluetooth nespojí, dokud jednou neproběhne „Spojit přes Bluetooth“ (detail
  kontaktu): oba telefony se na 2 min zviditelní a Bramble hledá službu protějšku
  (`discoverAndConnectForSetup`, jako Briar). Pak si adresy pamatují a spojují se samy.
- **Síť skupiny** běží paralelně mimo PACE: rámec = 1 B TTL + týmová obálka. Člen ji přepošle
  dál se sníženým TTL; TTL z rámce se ořízne na max. 4, vlastní zprávy a už viděná id se
  zahazují. Přenos: Bramble, ale **jen kontaktům právě spojeným přes LAN nebo Bluetooth**
  (nikdy Tor); první bajt zprávy Bramble rozlišuje párovou obálku (0) a rámec sítě skupiny
  (1). Týmová zpráva jde zároveň do kanálu LoRa týmu; bez ACK, deduplikace podle id.
- **Vrstva E — SMS (F4):** obálka jako jedna běžná SMS, base64url bez předpony (do 160
  znaků GSM-7; delší se rozdělí). Číslo kontaktu je na kartě (pole 0x05); čísla se
  porovnávají podle posledních 9 číslic (+420…, 00420…, bez předvolby). Dekóduje se jen SMS
  od čísla z karty, vše ostatní se nechá být. Odeslání čeká na verdikt sítě — SIM bez
  kreditu vrátí chybu a router pokračuje. Odchozí jen po potvrzení uživatelem nebo v nouzi.
  Přijaté SMS zůstávají i v systémové aplikaci SMS (výchozí SMS aplikací ECP není).
  Oprávnění SMS se žádá až při zapnutí (vlastní číslo na domovské obrazovce).
- **Změna vlastního čísla** (místní SIM v místě nasazení): číslo se zadává ručně, QR karty
  se hned přegeneruje a všem kontaktům odejde kontrolní zpráva `control` 0x01 s minimální
  kartou (jméno, klíč, číslo; vejde se i do LoRa). Příjemce ji přijme jen tehdy, když klíč na
  kartě je klíč kontaktu, od kterého obálka přišla; číslo v ní je závazné (žádné = smazat).
- **Vrstva C — MeshCore LoRa (F4):** `packages/ecp_meshcore`. Telefon mluví s rádiem
  MeshCore (firmware Companion, ověřeno Heltec V3, fw 1.17–1.18) přes BLE (Nordic UART,
  rádio spárované v systému s PINem z displeje), laptop přes USB sériovou linku. ECP obálka
  jde jako **binární datagram kanálu** (`CMD_SEND_CHANNEL_DATA`, max. 165 B, `data_type`
  0xFFEC z testovacího rozsahu — před vydáním zaregistrovat) a **flood** přes celou mesh.
  Nepotřebuje MeshCore kontakty ani adverty, takže rádio samo nic pravidelně nevysílá
  (companion firmware advert sám nespouští). Každý repeater v okolí flood přepošle, i když
  k ECP nepatří.
- **Nastavení rádia se nemění:** frekvence, preset i délka hashů cesty zůstávají, jak je má
  místní mesh (ověřeno na českém nastavení 869,432 MHz, BW 62,5, SF7, hash cesty 2 B), aby
  ECP využilo cizí repeatery. Aplikace je jen ukáže.
- **Kanál:** ECP zabere jeden slot kanálu jménem `ecp`. Výchozí je společný ECP kanál
  (klíč = SHA-256("L0ck-ECP v1 lora channel")[0:16]) — jen schová ECP před běžnými
  posluchači MeshCore, důvěrnost dává obálka. **Skupina si může nastavit vlastní soukromý
  kanál** (náhodný 16B klíč, sdílený osobně jako base64url; s týmovým QR v F5); slot `ecp`
  se přepíše, jiné kanály se nemění. Veřejný kanál, hashtag kanály, textové zprávy
  MeshCore a datagramy jiných aplikací aplikace **ignoruje**.
- Rádio drží přijaté datagramy, i když telefon není připojený; po připojení si je aplikace
  stáhne. BLE se po výpadku (mimo dosah) připojí znovu samo.
- Párová zpráva jde floodem ke všem v síti; otevře ji jen adresát (denní štítek + klíč).
  ACK jde zpět stejnou vrstvou.
- Hlídat EU duty cycle 868 MHz: zatím žádné vlastní omezení, posílá se jen při eskalaci a
  odpovědích.

## 8. Model hrozeb (zkráceně)

| Protivník | Co může | Obrana |
|---|---|---|
| Zabavení telefonu | přístup k úložišti, nátlak na PIN | sloty + Keystore, duress se zničením klíče, limit pokusů |
| Operátor / pozorovatel sítě | metadata, poloha buňky | P/A skrývají protějšek, Tor; SMS až poslední |
| Rádiové zaměření | lokalizace vysílače LoRa/BT | Evasion profil rádia, vysílání jen na pokyn, upozornění v UI |
| Provozovatel relay serveru | metadata SimpleX | víc provozovatelů, soukromé směrování, Tor |
| Zlovolný člen týmu | čte a podvrhuje týmové zprávy | párové zprávy pro citlivé věci, podpisy v v2, rotace týmového klíče |

**PANIC a KOMPROMITOVÁN na obrazovce PINu (2026-11-02):** dokud profil běží za zámkem
(zámek je jen obrazovka), jsou na obrazovce PINu dvě tlačítka, která PIN nepotřebují. Po
restartu nebo po výmazu tam nejsou: bez otevřeného profilu nejsou klíče ani kontakty.
- **PANIC** (jedno klepnutí) pošle nastavený STATUS s polohou (čerstvý fix do 6 s, jinak
  poslední známý) a pak vlastní text (≤ 90 B) všem kontaktům a týmům podle nastavení.
  Kontaktům v nouzovém režimu routeru: všemi dostupnými kanály najednou, SMS bez potvrzení;
  týmům jako běžná týmová zpráva (vysílání + rozeslání členům přes P/A).
- **KOMPROMITOVÁN**: první klepnutí jen zobrazí potvrzení nahoře na obrazovce (6 s), daleko
  od tlačítka. Po potvrzení odejde STATUS „kompromitován“ stejným příjemcům, aplikace dá
  kanálům 3–10 s na předání (čeká na ACK kontaktů) a pak `SecurityService.destroyProfile`
  zničí běžící profil jako duress kód: nejdřív jeho slot (crypto-shred), pak zastaví kanály,
  smaže jeho databázi a jen jeho data Bramble a SimpleX. Druhý slot zůstává, jak byl
  (návnada, nebo šum), takže obrazovka PINu vypadá stejně a duress kód dál otevře návnadu.
  Bez duress kódu už aplikaci nic neotevře (po 10 chybách se vymaže vše).
- Nastavení (stav, text, poloha, kontakty/týmy, která tlačítka ukázat) je v šifrované
  databázi profilu (`PanicConfig`, klíč `panic`).

**Zamykání a otisk prstu (0.1.1, 2026-11-03):** zámek je dál jen obrazovka nad běžícím
profilem. Nastavení (`LockConfig`, klíč `lock` v šifrované databázi profilu):
- *Zamknout po odchodu z aplikace*: ihned (výchozí), po 1/5/15 min, nebo jen ručně. Ručně
  znamená nouzové zamknutí (4 rychlá klepnutí), které pak nejde vypnout; jinak je to
  přepínač. Po restartu telefonu nebo aplikace je PIN potřeba vždy (klíč profilu se z něj
  odvozuje).
- *Otisk prstu* (systémový `BiometricPrompt`, jen silná biometrie, Android 11+) jen odkryje
  obrazovku běžícího profilu; žádný klíč na něm nezávisí. Otisk nemá duress kód, proto jde
  zapnout jen s tlačítky PANIC i KOMPROMITOVÁN na obrazovce PINu a ta pak nejdou vypnout.
  PIN je potřeba po restartu, po nouzovém zamknutí a 8 h od posledního zadání PINu.

**Úvodní obrazovka a nastavení (0.1.1):** kanály mají každý řádek se stavem PŘIPOJENO / BEZ
SPOJENÍ, vlastní karta (QR) je na samostatné obrazovce. Tlačítko *Hlášení* vede na formulář
a pak na výběr příjemců (týmy a libovolně kontaktů najednou); každému jde jako běžná zpráva
přes PACE. Nastavení je ve třech rozbalovacích oddílech: Bezpečnost (PIN a duress, zamykání,
otisk, PANIC), Konektivita (číslo pro SMS, pořadí PACE, obnova spojení, rádio LoRa),
Aplikace (přezdívka, jazyk), a samostatně O aplikaci.

**Hromadné nastavení skupiny (0.1.2, 2026-11-03):** offline stránka `tools/ecp_base`
na notebooku načte kamerou kontaktní QR všech telefonů, založí týmy (náhodný klíč z
`crypto.getRandomValues`), zvolí tým pro kanál LoRa a pořadí PACE. Výsledek je *balíček
skupiny* (`GroupBundle` v `ecp_core`): `'G' · verze · karty členů · týmy (název, klíč, indexy
členů) · tým LoRa · pořadí PACE`, rozdělený do QR `l0ck://g/<id>/<i>/<n>/<base64url>` po
700 B. Telefon (Kontakty / Týmy → Načíst balíček skupiny) načte díly v libovolném pořadí,
ukáže souhrn a `MessagingService.importGroup`: ostatní členové jako ověření kontakty, týmy,
kde je telefon zaškrtnutý, i s členy, kanál LoRa (jen členové toho týmu), pořadí PACE.
Nic se neposílá: všichni načtou stejný balíček. Telefon, který v balíčku není, se nenastaví.
Balíček nese klíče všech týmů, proto jen osobně na základně; stránka nic neukládá a má CSP
`connect-src 'none'`. Shodu formátu hlídá test: `tools/ecp_base/test/bundle_test.js` píše
fixture, kterou dekóduje `group_bundle_test.dart`.

**0.3.1:** 32bitové telefony (armeabi-v7a, např. Galaxy S5 mini s Androidem 9): jádro
SimpleX pro ARMv7 čeká od knihovny C symboly, které Android neexportuje (vnitřní funkce
bionicu, na Androidu 9 `reallocarray`), a bez nich se nenačte. `libsimplexshim.so`
(`app/android/simplex/simplex_shim.c`) je doplní; aplikace načte ji a jádro jako její
závislost. SimpleX nastartuje i bez sítě: kontaktní adresu si vytvoří, až se síť objeví
(nebo po *Obnovit spojení*), a kontaktům pak rozešle novou kartu. Oprávnění: ta, která daná
verze Androidu nezná („Zařízení v okolí“ před Androidem 12, oznámení před 13), se
přeskočí; před Androidem 12 se k hledání Bluetooth žádá poloha. APK po procesorech
(`--split-per-abi`).

**0.3.0:** podpis vlastním klíčem (docs/RELEASE.md). *Kontrolní hlášení*
(`CheckInConfig`, Nastavení → Bezpečnost): když majitel do zvolené doby (1–24 h) nepotvrdí
tlačítkem *Jsem v pořádku* na úvodní obrazovce nebo odemknutím PINem, odejde zvolený stav
s polohou příjemcům PANIC (nouzový režim, všemi kanály); 15 min předem připomínka; po
odeslání potvrzení pošle „V pořádku“. Termín je v šifrované databázi, hlídá ho ticker
služby zpráv (jen dokud profil běží). *PANIC s opakováním*: stav s čerstvou polohou znovu
každých 5–30 min, dokud se nezadá PIN (otisk prstu ho nezastaví). *Mizející zprávy*: zprávy
starší než 1 h – 7 dní se mažou ve všech chatech, jen v tomto telefonu. *Odchozí fronta*
na úvodní obrazovce: kolik zpráv a dílů čeká na potvrzení (a kterým kanálem), na kanál,
nebo na souhlas s SMS.

**0.2.3:** SRAZ už není samostatné hlášení v nabídce; STATUS nese volitelně bod srazu
a čas (`status · [poloha 13 B] · [bod 13 B · čas u32]`, rozlišené délkou, takže starší
STATUS i přijaté SRAZ se čtou dál). Chat kontaktu (ⓘ) i týmu (⋮) jde vymazat jen v tomto
telefonu. Oprava: díly hlasu a souborů se skládají jeden po druhém — dva poslední díly
naráz (pomalejší telefon) dřív udělaly zprávu dvakrát. Oprava Bramble: modul Bluetooth,
který nastartoval před udělením „Zařízení v okolí“, se uložil jako vypnutý uživatelem
(DISABLED/1); vypnutí a zapnutí se teď posílá postupně (správce modulů je zapisuje na
vlákna, takže souběžně mohlo „vypnout“ vyhrát).

**Fotky a soubory (0.2.2):** v nabídce + v chatu kontaktu i týmu *Vyfotit* a *Soubor*.
Fotku pořídí systémový fotoaparát do soukromé mezipaměti aplikace (`FileProvider`, jen
složka `cache/photos`); aplikace ji otočí podle orientace, zmenší na nejvýš 1600 px
a znovu uloží jako JPEG (tím zmizí celé EXIF včetně polohy) a soubor smaže. Soubor se
vybírá systémovým výběrem (Storage Access Framework), takže aplikace nepotřebuje přístup
k úložišti; uložení přijatého souboru jde stejně přes systémový dialog. Oprávnění: jen
fotoaparát (při focení). `MessageType.file` (0x08): `Attachment` (`druh · název · MIME ·
data`, nejvýš 512 kB) po dílech `FilePart` 3 kB (`fileId[4] · index u16 · počet u16 ·
data`), stejně jako hlas: s ACK jen po SimpleX a Bramble přes Tor/LAN, týmům jen členům.

**Hlasové zprávy (0.1.6):** `MessageType.voice` (0x06), `VoicePart` v `ecp_core`:
`clipId[4] · index · count · codec · délka ms u16 · data`. Nahrávání v Androidu
(`AudioHost`): Opus v Ogg 8 kbit/s, 16 kHz mono (Android 10+), jinak HE-AAC; nejvýš 30 s
(≈ 30 kB). Klip se dělí po 3 kB, aby se díl i s obálkou vešel do jedné zprávy Bramble
(nejvýš 4096 B, `EcpClient.MAX_ENVELOPE_LENGTH`) i SimpleX; větší díly Bramble odmítal a
zprávy šly přes SimpleX, i když byl Bramble v PACE první.
Díly jdou s ACK, ale jen po vrstvách P a A (`PaceRouter.send(layers:)`, uloženo v outboxu,
sloupec `outbox_rows.layers`): nikdy LoRa ani SMS, ani v nouzovém režimu; bez SimpleX
a Bramble čekají. Bramble jen přes Tor nebo LAN: když má ke kontaktu jen Bluetooth, jde hlas
jen přes SimpleX (Bluetooth je na hlas pomalý). Týmům jde každý díl jen členům přes P/A,
ne vysíláním na síť skupiny ani LoRa.
Příjemce skládá díly v tabulce `voice_parts` (databáze v6) a zprávu ukáže až celou;
odesílatel má jeden řádek, „doručeno“ až po potvrzení všech dílů. Přehrává se z paměti
(`MediaDataSource`), nahrávka je v mezipaměti aplikace jen do převzetí. Mikrofon u kontaktu
i týmu je aktivní, jen když vhodný kanál právě dosáhne příjemce.

**Hovory 1:1 (0.2.0):** zvuk přes WebRTC (`flutter_webrtc` 1.6.2+hotfix.4, Opus,
DTLS-SRTP, potlačení ozvěny a šumu). Domluva `MessageType.call` (0x07, `CallSignal`:
`callId[8] · druh · data`) jde v párové obálce ECP jednou zkouškou po P/A (`sendOnce`)
v pořadí PACE, Bramble jen přes Tor/LAN: nabídka a odpověď SDP i se všemi kandidáty ICE
(bez trickle), komprimované zlib, aby se vešly do zprávy Bramble, konec s důvodem (zavěšeno,
odmítnuto, obsazeno, nikdo to nezvedá, chyba). Obálka SDP autentizuje, takže otisky DTLS
v ní nejde podvrhnout (žádný MITM). ICE: nejdřív přímo (místní síť, STUN
`stun.simplex.im:443`), když to nejde, přenos přes veřejný TURN SimpleX
`turns:turn.simplex.im:443` (TLS) se stejnými údaji, jaké používá aplikace SimpleX;
provozovatel relé vidí IP adresy obou stran, ne zvuk. Volat jde, jen když SimpleX/Bramble
dosáhne kontaktu a je internet nebo spojení LAN přes Bramble (stejná Wi-Fi). Jeden hovor
naráz, druhý volající slyší „obsazeno“; zvoní 45 s (oznámení s opakovaným vyzváněním, bez
jména volajícího), pak zmeškaný hovor. Během hovoru má služba na pozadí typ „mikrofon“
(hovor jde i se zhasnutou obrazovkou a pod zámkem) a senzor přiblížení zhasíná displej.
Výsledek hovoru se zapíše do konverzace (místní typ 0x87, nikdy se neposílá).

**Opakovaný balíček a čísla (0.1.5):** načtení balíčku znovu (opravený na základně) zapíše
jen rozdíly: u známého kontaktu jméno a kanály z karty, které se liší (karta žádný kanál
nemaže), kanál LoRa a pořadí PACE jen když nesedí. `GroupImport` hlásí kontakty nové,
změněné a beze změny a nové týmy. Stránka základny přijme jen číslo s mezinárodní
předvolbou (`+`, 8–15 číslic, E.164) a hlídá ho už při psaní.

**Základna a balíček, opravy (0.1.3–0.1.4):** skener QR je v aplikaci samostatná aktivita
Androidu, takže aplikace odešla do pozadí a se zamykáním „ihned“ se uprostřed načítání
balíčku zamkla. Teď skener a dialog viditelnosti Bluetooth drží `LockHold`: zamkne se až po
2 min. Nastavení z balíčku ukazuje průběh, chybu nespolkne (žádná nekonečná lišta),
přepnutí rádia LoRa i `contactsChanged` kanálů mají časový limit. Číslo, které základna
doplnila do vlastní karty telefonu, se stane vlastním číslem pro SMS. Stránka základny:
zaměřovací čtverec, stav HLEDÁM QR / NAČTENO se zvukem, přidání až po potvrzení, úprava
jména a čísla (karta se přepíše jen v těchto dvou polích), QR karty člena.

**Tovární nastavení (0.1.2):** Nastavení → Aplikace → *Obnovit tovární nastavení*. Tlačítko
jen otevře dialog, smaže až jeho červené potvrzení: stejně jako po 10 chybných PINech
(`SecurityService.wipeAll`) zničí oba sloty, klíč v Keystore, všechny databáze a data Bramble
a SimpleX; aplikace začne nastavením jako po instalaci. Kontaktům nic neposílá. Zůstane jen
zvolený jazyk (soubor `lang`).

**Jazyk a About (2026-11-02):** aplikace je česky a anglicky (Flutter `gen-l10n`,
`app/lib/l10n/app_cs.arb` je šablona, `app_en.arb` překlad). Přepínač je v Nastavení; volba
se ukládá do souboru `lang` vedle šifrovaných profilů, protože musí platit už na zamykací
obrazovce, a nic o uživateli neprozrazuje. Na drátu jazyk nehraje roli: hlášení nesou kódy,
popisky dosazuje přijímající aplikace ve svém jazyce. Kód bez `BuildContext` (stav kanálů,
chyby služeb) bere texty z `Lang.tr`. Dole v Nastavení je About: logo, autor, odkazy na
GitHub a web, licence AGPLv3, použité komponenty a upozornění, že aplikace není určená
k porušování zákonů a autor za její použití neodpovídá.

## 9. Stav implementace (F4 rozpracovaná, 2026-11-02)

Nová aplikace v `app/` (balíček `cz.l0ck.ecp`, běží vedle staré aplikace), jádro
v `packages/ecp_core/`.

| Část | Implementace | Ověřeno |
|---|---|---|
| ECP obálka, zprávy, kontaktní karta | `ecp_core` (čistý Dart, balíček `cryptography`) | 47 testů vč. vektorů RFC 7748/8439/5869 a rozpočtu SMS/LoRa |
| Sloty klíčů, duress, limit pokusů | `ecp_core` `KeySlots` + `app/lib/security/security_service.dart` | testy na laptopu se skutečným SQLCipherem + ruční test na Nokii |
| Argon2id | **nativní libsodium** (`package:sodium`, kompilace přes NDK), 64 MiB / t = 3 / p = 1, v isolate; výstup bajtově shodný s dartovou verzí (test) | odemčení na Nokii ≤ ~3,5 s (dartová verze ~15 s) |
| Vázání na zařízení | `MainActivity.kt` — HMAC-SHA256 klíčem v Android Keystore, StrongBox když je | odemčení na Nokii |
| Šifrovaná DB | SQLCipher přes `sqlite3` build hooks (`source: sqlcipher`); aplikace odmítne otevřít DB, když SQLCipher neběží | hlavička souboru na Nokii = náhodné bajty |
| Ochrana obrazovky a dat | `FLAG_SECURE`, `allowBackup=false`, `dataExtractionRules` bez cloudu i přenosu | — |
| PACE router | `ecp_core` `PaceRouter` (§7) | 12 simulačních testů: eskalace P→A, přeskočení na LoRa, potvrzení SMS, čekání, ztracený ACK, nouzový mód, restart, podvržený ACK, síť skupiny a TTL |
| Vrstva A: Bramble | Briar 1.5.24 → lokální Maven (`app/android/bramble/build-bramble.sh`), klient `bramble-ecp`, `BrambleHost` + `EcpService` (Android), `BrambleTransport` (Dart); Flutter engine patří aplikaci, ne aktivitě | Nokia ↔ laptop (`tools/ecp_peer` + `tools/bramble-peer`): Tor rendezvous, zprávy oběma směry s ACK (~1–6 s), zpráva z fronty přežila přeinstalaci, příjem se zhasnutou obrazovkou a zamčenou aplikací; testy s falešnou sítí Bramble |
| Vrstva P: SimpleX | `packages/ecp_simplex` (`SimplexTransport`, FFI pro telefon, WebSocket pro CLI), `SimplexAppTransport`; APK s jádrem 75,8 MB | 5 testů s falešným SimpleX; dva CLI na laptopu přes skutečnou síť SimpleX (spojení 2 s, zpráva s ACK ~0,3 s); Nokia ↔ laptop: zpráva i odpověď „přes simplex“ s ACK |
| Vrstva C: MeshCore LoRa | `packages/ecp_meshcore` (kodek companion protokolu, klient s frontou příkazů, `MeshCoreTransport`), `RadioHost.java` (BLE), obrazovka Rádio LoRa | 8 testů s falešnými rádii (flood, ACK, soukromý kanál, ignorování veřejného kanálu); naostro Nokia + Heltec V3 (BLE) ↔ laptop + Heltec V3 (USB): text i ACK přes LoRa za ~1 s, SNR ~11–12 dB; zpráva z telefonu sama eskalovala A → C |
| Týmy a síť skupiny | DB v4 (`Teams`, odesílatel zprávy), založení/připojení přes týmové QR, `BrambleSquadTransport`, týmová konverzace, kanál LoRa týmu | 3 testy (stejné ID a klíč LoRa u obou členů, bez místního spojení nic neodejde, přes LAN dorazí se jménem odesílatele); Nokia ↔ laptop: tým založen na telefonu, laptop se připojil týmovou kartou, týmová zpráva dorazila přes LoRa týmu, odpověď sítí skupiny přes LAN |
| Vrstva E: SMS | `SmsHost.java` + `SmsReceiver` (odeslání s verdiktem sítě, příjem, stav SIM), `SmsTransport`, vlastní číslo a rozeslání nového čísla kontaktům | 6 testů s falešnou sítí GSM (formáty čísel, rozpočet 160 znaků bez předpony, potvrzení před odesláním, SIM bez kreditu, doručení s kreditem, cizí čísla ignorována) + test aktualizace čísla; naostro zatím ne (Pixel → Nokia) |
| Skenování QR | ZXing (`zxing-android-embedded`, Apache 2.0, bez Google), na výšku, kamera jen při skenování; kontakt i tým | sestaveno, na zařízení zatím neověřeno |
| Chat a kontakty (z testu dvou telefonů) | nepřečtené zprávy (úvod, kontakty, týmy), čas a stav u zpráv (✓ ✓✓ přečteno), kopírování textu, detail kontaktu (ověření, kanály, QR karty, Bluetooth, přejmenovat, smazat), ověření skenem QR, členové týmu, pořadí PACE; DB v5 | testy: potvrzení o přečtení, týmová zpráva členovi přes P, smazání kontaktu, pořadí PACE po restartu; migrace v4→v5 na Nokii s živými daty |
| Kontakty a zprávy v aplikaci | `app/lib/messaging/messaging_service.dart`, DB v2 (`Messages`, `OutboxRows`, `SeenIds`, migrace z v1) | testy dvou profilů přes testovací kanál + migrace; na Nokii přidání kontaktu z odkazu, ověřovací číslo, zpráva čeká bez kanálu a přežije restart |

**PIN:** 6–12 číslic. Minimum 6, protože útočník s telefonem v ruce může Keystore volat
dál; online hádání tak brzdí jen náklad Argon2id × velikost prostoru PINů a limit pokusů
(3 zdarma, pak 30 s, 1 min, 2 min…, po 10 chybách se vše zničí).

**Duress na Nokii ověřen:** duress kód otevřel profil se stejnou přezdívkou a jiným
otiskem, databáze skutečného profilu zmizela a skutečný PIN už nic neotevře.

**Kanály:** vrstvy P (SimpleX), A (Bramble), C (MeshCore), E (SMS, zatím jen strojově) a síť
skupiny (Bramble LAN; Bluetooth čeká na druhý telefon). Meshtastic zbývá; kontakt i tým se přidává skenováním QR kamerou nebo vložením odkazu `l0ck://c/…`.

**Vzhled:** adaptivní ikona ze znaku L0ck-ECP (popředí s průhledností, pozadí #0A0C09,
jednobarevná varianta pro tematické ikony Androidu 13+), systémový splash Androidu 12+ i
starší `launch_background` se stejným znakem, Flutter pak naváže logem.

**Nálezy z testu na Nokii:**
- LineageOS má pro nové aplikace síť zakázanou (politika `REJECT_ALL`), Tor pak nenaběhne a
  Bramble ukáže jen `lan`. Uživatel musí povolit „Přístup k síti“ v nastavení aplikace.
- Release build potřebuje ProGuard pravidla pro Bramble (`app/android/app/proguard-rules.pro`):
  R8 jinak rozbije SecureRandom provider a H2 databázi.
- Bramble kontakt (handshake přes Tor rendezvous) vznikne až po přidání odkazu na obou
  stranách; zpráva do té doby čeká ve frontě a pak odejde sama.
- Konverzace řadí příchozí zprávy podle času přijetí: hodiny telefonu bez síťového času
  ujížděly o ~11 min.

## 10. Otevřené otázky

- Dopředná bezpečnost pro LoRa/SMS (ratchet odolný vůči ztrátám) — v2.
- Podpisy týmových zpráv (Ed25519, +64 B) — v2.
- Zarovnání délky (padding) tam, kde rozpočet kanálu dovolí.
- Bluetooth síť skupiny mezi telefony — ověřit, jakmile bude druhý telefon (F1 to nestihl).
- Eskalace A → C: první měření 207 s, opakované ~137 s (limit A 120 s + tik + flood) — v
  normě; první číslo zkreslilo měření z UI.
- Kanál LoRa je jeden slot: s týmovým kanálem neslyší párové zprávy ze společného ECP kanálu
  (a naopak) — zvážit dva sloty.
- SimpleX přes Tor (SOCKS proxy z Bramble), aby relé neviděla IP telefonu.
- Po duress jede návnada bez Bramble až do restartu procesu; ověřit, jestli SimpleX jde
  v jednom procesu otevřít pro jiný profil (jinak totéž omezení).
- Registrovat `data_type` pro ECP v MeshCore (`docs/number_allocations.md`).
- Bramble ukládá přijaté obálky ve své DB napořád; přidat úklid (Bramble `CleanupManager`).
- Když první vytvoření účtu Bramble spadne v půlce, zůstane DB bez schématu a start pak
  končí `DB_ERROR`; zvážit automatický úklid takového adresáře.
