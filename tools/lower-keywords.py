#!/usr/bin/env python3
"""Lowercase Pascal reserved words, leaving strings, comments and type
identifiers (LongInt, Word, ...) untouched."""
import re, sys, glob

RESERVED = """begin end if then else while do for to downto repeat until case of
var const type function procedure unit uses interface implementation record
array and or not div mod shl shr xor in nil with program label set goto file
packed forward""".split()
PAT = re.compile(r'\b(' + '|'.join(RESERVED) + r')\b', re.I)

def masked(s):
    """Mark bytes inside {...}, (*...*) and '...' so we never touch them."""
    m = bytearray(len(s)); i = 0
    while i < len(s):
        if s[i] == '{':
            j = s.find('}', i); j = len(s)-1 if j < 0 else j
        elif s.startswith('(*', i):
            j = s.find('*)', i); j = len(s)-2 if j < 0 else j+1
        elif s[i] == "'":
            j = i+1
            while j < len(s):
                if s[j] == "'":
                    if j+1 < len(s) and s[j+1] == "'": j += 2; continue
                    break
                if s[j] == '\n': break
                j += 1
            j = min(j, len(s)-1)
        else:
            i += 1; continue
        for k in range(i, min(j+1, len(s))): m[k] = 1
        i = j+1
    return m

total = 0
for path in sorted(glob.glob('*.PAS')):
    s = open(path, encoding='latin-1').read()
    m = masked(s)
    out = []; last = 0; n = 0
    for mt in PAT.finditer(s):
        if m[mt.start()]: continue
        w = mt.group(0)
        if w == w.lower(): continue
        out.append(s[last:mt.start()]); out.append(w.lower())
        last = mt.end(); n += 1
    if n:
        out.append(s[last:])
        open(path, 'w', encoding='latin-1').write(''.join(out))
        print(f"  {path}: {n}")
        total += n
print(f"lowercased {total} reserved words")
