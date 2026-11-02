#!/usr/bin/env python3
"""Adds strings to both ARB files: arb.py strings.json, where the JSON is
{"key": ["česky", "English"], "key2": ["…{n}…", "…{n}…", {"n": "int"}]} (placeholder types)."""
import json, sys, collections

new = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)
for lang, i in (('cs', 0), ('en', 1)):
    p = f'lib/l10n/app_{lang}.arb'
    arb = json.load(open(p), object_pairs_hook=collections.OrderedDict)
    for k, v in new.items():
        arb[k] = v[i]
        if lang == 'cs' and len(v) > 2:
            arb['@' + k] = {'placeholders': {n: {'type': t} for n, t in v[2].items()}}
    json.dump(arb, open(p, 'w'), ensure_ascii=False, indent=2)
    open(p, 'a').write('\n')
print(len(new), 'keys')
