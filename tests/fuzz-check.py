# -*- coding: utf-8 -*-
"""Verifie les regles qui doivent tenir quel que soit le fichier."""
import io, os, sys, glob, json
from PIL import Image, ImageFile
ImageFile.LOAD_TRUNCATED_IMAGES = False
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HERE = os.path.dirname(os.path.abspath(__file__))
LOT = os.path.join(HERE, 'random')
META = json.load(io.open(os.path.join(HERE, 'random-index.json'), encoding='utf-8'))
FICHES = META['fichiers']

def transparents(path):
    """Nombre de pixels reellement traversants. -1 si illisible."""
    try:
        im = Image.open(path); im.load()
        if im.mode == 'P' and 'transparency' not in im.info:
            return 0
        if im.mode not in ('RGBA', 'LA', 'P'):
            return 0
        return sum(1 for p in im.convert('RGBA').get_flattened_data() if p[3] < 255)
    except Exception:
        return -1

def taille(path):
    try:
        im = Image.open(path); im.load()
        return im.size
    except Exception:
        return None

manquements = []
def faute(regle, fichier, detail):
    manquements.append((regle, fichier, detail))

produits = converti = garde = casse = 0
for name in FICHES:
    src = os.path.join(LOT, name)
    if not os.path.exists(src):
        continue
    base = os.path.splitext(name)[0]
    out = None
    for e in ('.jpg', '.png'):
        q = os.path.join(LOT, base + '_jipeg' + e)
        if os.path.exists(q):
            out = q; break
    a = os.path.getsize(src)
    if out is None:
        garde += 1
        continue
    produits += 1
    b = os.path.getsize(out)

    # 1 - jamais plus lourd que la source
    if b >= a:
        faute('plus lourd', name, '%d -> %d' % (a, b))

    # 2 - le resultat doit etre une image lisible
    ta_out = transparents(out)
    if ta_out < 0:
        faute('sortie illisible', name, os.path.basename(out))
        casse += 1
        continue
    converti += 1

    # 3 - un pixel transparent a la source ne disparait jamais
    ta_in = transparents(src)
    if ta_in > 0 and ta_out == 0:
        faute('transparence perdue', name, '%d pixels -> 0' % ta_in)

    # 4 - les dimensions se conservent (au quart de tour pres pour l Exif)
    si, so = taille(src), taille(out)
    if si and so and si != so and si != (so[1], so[0]):
        faute('dimensions', name, '%s -> %s' % (si, so))

print('  %d fichiers presentes' % len(FICHES))
print('  %d sorties ecrites, %d lisibles, %d laisses tels quels, %d cassees'
      % (produits, converti, garde, casse))

# 5 - rien ne traine dans le dossier source
restes = [f for f in os.listdir(LOT) if f.startswith('.jipeg-')]
print('  fichiers temporaires laisses dans le dossier : %d' % len(restes))
if restes:
    faute('reste dans le dossier', ', '.join(restes[:5]), '')

# 6 - rien ne traine dans %TEMP%
tmp = os.environ.get('TEMP', '')
tr = (glob.glob(os.path.join(tmp, 'jipeg-in-*')) + glob.glob(os.path.join(tmp, 'jipeg-raw-*'))
      + glob.glob(os.path.join(tmp, 'jipeg-g-*')) + glob.glob(os.path.join(tmp, 'jipeg-update-*')))
print('  fichiers temporaires laisses dans TEMP         : %d' % len(tr))
if tr:
    faute('reste dans TEMP', ', '.join(os.path.basename(x) for x in tr[:5]), '')

print()
if manquements:
    print('  %d manquement(s) :' % len(manquements))
    for r, f, d in manquements[:40]:
        print('    %-22s %-46s %s' % (r, f[:46], d))
else:
    print('  toutes les regles tiennent')
sys.exit(1 if manquements else 0)
