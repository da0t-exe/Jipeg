# -*- coding: utf-8 -*-
"""Cherche les fonctions et variables definies mais jamais utilisees."""
import io, os, re, glob

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = (sorted(glob.glob(os.path.join(SRC, 'src', '*.ps1')))
         + [os.path.join(SRC, 'install.ps1'), os.path.join(SRC, 'uninstall.ps1')])
text = {}
for f in files:
    text[f] = io.open(f, encoding='utf-8-sig').read()

whole = '\n'.join(text.values())

print('=== fonctions definies mais jamais appelees ===')
dead = 0
for f, s in text.items():
    for m in re.finditer(r'^function\s+([A-Za-z][\w-]*)', s, re.M):
        name = m.group(1)
        # une definition + zero autre mention = personne ne s'en sert
        uses = len(re.findall(r'(?<![\w-])' + re.escape(name) + r'(?![\w-])', whole))
        if uses <= 1:
            print('  %-22s %s' % (os.path.basename(f), name))
            dead += 1
if not dead:
    print('  aucune')

print()
print('=== variables de portee fichier jamais relues ===')
for f, s in text.items():
    body = s
    for m in re.finditer(r'^\$([A-Za-z]\w*)\s*=', body, re.M):
        name = m.group(1)
        if name in ('_', 'args', 'true', 'false', 'null'):
            continue
        uses = len(re.findall(r'\$' + re.escape(name) + r'(?![\w])', whole))
        if uses <= 1:
            print('  %-22s $%s' % (os.path.basename(f), name))

print()
print('=== taille ===')
tot = 0
for f in files:
    n = len(text[f].split('\n'))
    b = os.path.getsize(f)
    tot += b
    print('  %-24s %5d lignes  %7d o' % (os.path.basename(f), n, b))
for f in sorted(glob.glob(os.path.join(SRC, 'src', 'lang', '*.psd1'))):
    tot += os.path.getsize(f)
print('  %-24s %5s          %7d o' % ('lang/*.psd1 (10)', '',
      sum(os.path.getsize(f) for f in glob.glob(os.path.join(SRC, 'src', 'lang', '*.psd1')))))
print('  %-24s %5s          %7d o  au total' % ('', '', tot))
