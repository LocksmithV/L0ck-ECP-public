# Základna: hromadné nastavení skupiny

Offline webová stránka pro notebook. Načte kontaktní QR všech telefonů, založí týmy a ukáže
**balíček skupiny** jako sérii QR kódů. Každý telefon ho načte v aplikaci a dostane:

- kontakty všech ostatních členů (jako ověřené, protože je základna viděla osobně),
- týmy, ve kterých je zaškrtnutý, i s jejich členy,
- soukromý kanál LoRa vybraného týmu (jen členové toho týmu),
- pořadí PACE, pokud je zapnuté.

Pro 10 lidí je to jedno skenování na telefon místo zhruba 90 vzájemných.

## Použití

1. Otevři `tools/ecp_base/index.html` v prohlížeči (Chrome, Chromium, Firefox). Internet není
   potřeba. Když prohlížeč u souboru z disku nepovolí kameru, spusť v kořeni repozitáře
   `python3 -m http.server 8741 --bind 127.0.0.1` a otevři
   `http://127.0.0.1:8741/tools/ecp_base/`.
2. **Členové:** zapni kameru a na každém telefonu ukaž *Můj kontakt*. Odkaz jde i vložit.
3. **Týmy:** přidej týmy a zaškrtni, kdo v kterém je. U jednoho týmu můžeš zvolit *Kanál LoRa*.
4. **Pořadí PACE:** volitelně stejné pořadí kanálů pro všechny.
5. **Vytvořit balíček.** Na telefonu: *Kontakty* nebo *Týmy* → ikona skeneru → *Načíst balíček
   skupiny* → *Skenovat QR*. Skener se po každém QR sám otevře znovu, dokud nejsou všechny.
   Na pořadí nezáleží. Pak *Nastavit telefon*.
6. Po nastavení všech telefonů **Smazat vše** (nebo zavři kartu).

Telefon, jehož kontakt v balíčku není, se nenastaví. Po každé změně členů nebo týmů je
potřeba balíček vytvořit znovu.

## Bezpečnost

- Stránka nic neukládá (ani do prohlížeče) a nesmí nic odeslat: má CSP `connect-src 'none'`.
  Všechno je jen v paměti otevřené karty.
- Balíček obsahuje **klíče všech týmů**. Kdo si ho vyfotí, čte provoz týmů. Ukazuj ho jen
  na základně, osobně. Telefon si ponechá jen klíče týmů, kde je členem, ale balíček sám
  nese všechny.
- Klíče týmů se generují v prohlížeči (`crypto.getRandomValues`).

## Soubory

| Soubor | Obsah |
|---|---|
| `index.html`, `base.js` | stránka (čeština a angličtina) |
| `img/` | logo a pozadí (kopie v JPEG z `docs/images/L0ck-ECP_background.png`), aby stránka fungovala i zkopírovaná samostatně |
| `bundle.js` | formát balíčku, stejný jako `packages/ecp_core/lib/src/group_bundle.dart` |
| `vendor/jsQR.js` | čtení QR z kamery, [jsQR](https://github.com/cozmo/jsQR) 1.4.0, Apache 2.0 (`jsQR.LICENSE`) |
| `vendor/qrcode.js` | kreslení QR, [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) 1.4.4, MIT (licence v hlavičce souboru) |
| `vendor/SHA256SUMS` | kontrolní součty knihoven (z balíčků npm, ověřené proti registru) |
| `test/bundle_test.js` | test kodéru; `--write` obnoví fixture pro test v Dartu |

Testy: `node tools/ecp_base/test/bundle_test.js` a `cd packages/ecp_core && dart test`.
