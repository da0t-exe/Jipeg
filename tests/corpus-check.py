# -*- coding: utf-8 -*-
"""Compare ce qui est sorti a ce qui etait attendu, fichier par fichier."""
import io, os, json, sys
from PIL import Image
# la console Windows est en cp1252 : sans cela un nom en japonais fait tout tomber
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HERE = os.path.dirname(os.path.abspath(__file__))
LOT = os.path.join(HERE, 'corpus')
ATTENDU = json.load(io.open(os.path.join(HERE, 'corpus-expected.json'), encoding='utf-8'))

def sortie(name):
    base = os.path.splitext(name)[0]
    for ext in ('.jpg', '.png'):
        q = os.path.join(LOT, base + '_jipeg' + ext)
        if os.path.exists(q):
            return q
    return None

def infos(q):
    try:
        im = Image.open(q); im.load()
        return im.format, im.mode, im.size
    except Exception as e:
        return 'ILLISIBLE', str(e)[:40], (0, 0)

ok = bad = 0
lignes = []
for name in sorted(ATTENDU):
    want, why = ATTENDU[name]
    src = os.path.join(LOT, name)
    a = os.path.getsize(src)
    q = sortie(name)
    got = 'rien'
    detail = ''
    if q:
        fmt, mode, size = infos(q)
        got = 'jpg' if q.endswith('.jpg') else 'png'
        b = os.path.getsize(q)
        pct = round((b - a) * 100.0 / a) if a else 0
        detail = '%8d -> %8d  %+4d%%  %s %s %dx%d' % (a, b, pct, fmt, mode, size[0], size[1])
        if fmt == 'ILLISIBLE':
            got = 'casse'
        # jamais plus lourd
        if b > a:
            got = 'plus-lourd'
    else:
        detail = '%8d -> %8s' % (a, 'rien')

    verdict = 'ok' if got == want else 'ECART'
    if verdict == 'ok':
        ok += 1
    else:
        bad += 1
    lignes.append('  %-3s %-46s %-6s attendu %-6s %s' %
                  (verdict if verdict != 'ok' else '', name[:46], got, want, detail))

for l in lignes:
    print(l)
print()
print('  %d/%d conformes' % (ok, ok + bad))

# --- verifications supplementaires sur les cas ou la perte serait grave ---
print()
print('  sans perte la ou il le faut :')
for name in ('03-png-alpha.png', '04-png-palette-trns.png'):
    q = sortie(name)
    if not q:
        print('    %-28s AUCUNE SORTIE' % name); bad += 1; continue
    a = Image.open(os.path.join(LOT, name)).convert('RGBA')
    b = Image.open(q).convert('RGBA')
    same = list(a.getdata()) == list(b.getdata())
    trans = sum(1 for px in a.getdata() if px[3] < 255)
    print('    %-28s identique a l octet : %-5s  (%d pixels transparents)' % (name, same, trans))
    if not same:
        bad += 1

print()
print('  orientation appliquee aux pixels :')
for n in range(1, 9):
    name = '26-jpg-orientation-%d.jpg' % n
    q = sortie(name)
    if not q:
        print('    %-28s AUCUNE SORTIE' % name); bad += 1; continue
    im = Image.open(q)
    ex = im.getexif()
    tag = ex.get(0x0112, 'absent')
    # 5 a 8 font pivoter d un quart de tour : 300x200 doit devenir 200x300
    attendu = (200, 300) if n >= 5 else (300, 200)
    verdict = 'ok' if (im.size == attendu and tag in ('absent', 1)) else 'ECART'
    if verdict != 'ok':
        bad += 1
    print('    %-28s %dx%d  balise Exif %-6s  %s' % (name, im.width, im.height, tag, verdict))

sys.exit(1 if bad else 0)
