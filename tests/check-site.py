# -*- coding: utf-8 -*-
"""Verifie la page : chaque chaine traduite dans les neuf langues, aucune
ressource externe, et le HTML se referme."""
import io, os, re, sys

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'docs', 'index.html')
s = io.open(P, encoding='utf-8').read()
bad = 0

ids = sorted(set(re.findall(r'data-t="([^"]+)"', s)))
print('  %d chaines portent un data-t' % len(ids))

langs = re.findall(r'\n  ([a-z]{2}): \{', s)
print('  %d tables de traduction : %s' % (len(langs), ' '.join(langs)))

for code in langs:
    m = re.search(r'\n  ' + code + r': \{(.*?)\n  \}', s, re.S)
    if not m:
        print('  %s : table illisible' % code); bad += 1; continue
    keys = set(re.findall(r'(?:^|\s)([A-Za-z]\w*):"', m.group(1)))
    miss = [i for i in ids if i not in keys]
    if miss:
        print('  %s : %d manquantes -> %s' % (code, len(miss), ', '.join(miss[:8])))
        bad += 1

ext = [u for u in re.findall(r'(?:src|href)="(https?://[^"]+)"', s)
       if 'github.com' not in u and 'raw.githubusercontent' not in u]
print('  ressources externes chargees : %s' % (', '.join(ext) if ext else 'aucune'))
if ext:
    bad += 1

for tag in ('section', 'div', 'p', 'h2', 'h3'):
    o = len(re.findall(r'<' + tag + r'[ >]', s))
    c = len(re.findall(r'</' + tag + r'>', s))
    if o != c:
        print('  <%s> : %d ouverts, %d fermes' % (tag, o, c)); bad += 1

for img in re.findall(r'<img[^>]+src="([^"]+)"', s):
    if img.startswith('data:'):
        continue
    q = os.path.join(os.path.dirname(P), img)
    if os.path.exists(q):
        print('  image %-16s %d o' % (img, os.path.getsize(q)))
    else:
        print('  image %s ABSENTE' % img); bad += 1

print('  page : %d o' % os.path.getsize(P))
print()
print('  page conforme' if not bad else '  %d probleme(s)' % bad)
sys.exit(1 if bad else 0)
