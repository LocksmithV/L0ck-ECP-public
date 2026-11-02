#!/usr/bin/env python3
"""rep.py file.dart replacements.json — [[old, new], …]; every old must occur, else abort."""
import json, sys
path, reps = sys.argv[1], json.load(open(sys.argv[2]))
s = open(path).read()
for old, new in reps:
    if old not in s:
        sys.exit(f'{path}: not found: {old[:70]!r}')
    s = s.replace(old, new)
open(path, 'w').write(s)
print(path, len(reps), 'replacements')
