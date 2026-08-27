# -*- coding: utf-8 -*-
"""Fabrique les cas limites que l'arbre disait n'avoir jamais essayes.

Chacun est un fichier reel dans un dossier reel : rien n'est simule. Le script
ecrit ce qu'il a fabrique pour que le compte-rendu ne repose pas sur ce que le
code croit avoir fait.
"""
import io, os, struct, sys

from PIL import Image, ImageDraw
Image.MAX_IMAGE_PIXELS = None          # le panorama depasse la garde par defaut

BASE = sys.argv[1] if len(sys.argv) > 1 else 'edges'
os.makedirs(BASE, exist_ok=True)


def photo(w, h):
    """Une image qui compresse comme une photo, pas comme un aplat."""
    im = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(0, h, 7):
        d.line([(0, y), (w, y)], fill=((y * 3) % 256, (y * 7) % 256, (y * 11) % 256), width=5)
    for x in range(0, w, 11):
        d.line([(x, 0), (x, h)], fill=((x * 5) % 256, (x * 2) % 256, (x * 13) % 256), width=3)
    return im


faits = []


def note(nom, chemin, quoi):
    taille = os.path.getsize(chemin) if os.path.exists(chemin) else -1
    faits.append((nom, chemin, taille, quoi))


# --- 1.4 les noms ---------------------------------------------------------
p = os.path.join(BASE, 'crochets [1] et #diese.png')
photo(320, 240).save(p)
note('nom-crochets', p, 'crochets et diese : jokers PowerShell')

# --- 1.3 cache et systeme -------------------------------------------------
p = os.path.join(BASE, 'cache.png')
photo(320, 240).save(p)
note('fichier-cache', p, 'sera marque cache')

p = os.path.join(BASE, 'systeme.png')
photo(320, 240).save(p)
note('fichier-systeme', p, 'sera marque systeme')

# --- 1.3 source ouverte ailleurs -----------------------------------------
p = os.path.join(BASE, 'ouverte-ailleurs.png')
photo(320, 240).save(p)
note('source-ouverte', p, 'un autre processus la tiendra ouverte')

# --- 1.2 grande image -----------------------------------------------------
p = os.path.join(BASE, 'grande-4200px.png')
photo(4200, 2800).save(p)
note('grande-image', p, '4200x2800, au-dessus du seuil de 4000')

# --- 1.1 PNG avec profil ICC non sRGB ------------------------------------
icc = None
for cand in (r'C:\Windows\System32\spool\drivers\color\AdobeRGB1998.icc',
             r'C:\Windows\System32\spool\drivers\color\ProPhoto.icm',
             r'C:\Windows\System32\spool\drivers\color\CIERGB.icm',
             r'C:\Windows\System32\spool\drivers\color\WideGamutRGB.icm'):
    if os.path.exists(cand):
        icc = cand
        break
if icc:
    p = os.path.join(BASE, 'profil-non-srgb.png')
    photo(320, 240).save(p, icc_profile=open(icc, 'rb').read())
    note('icc-non-srgb', p, 'profil ' + os.path.basename(icc))
else:
    faits.append(('icc-non-srgb', '', -1, 'aucun profil non sRGB sur la machine'))

# --- 1.3 dossier non inscriptible ----------------------------------------
d = os.path.join(BASE, 'dossier-verrouille')
os.makedirs(d, exist_ok=True)
p = os.path.join(d, 'dedans.png')
photo(320, 240).save(p)
note('dossier-verrouille', p, 'le dossier sera mis en lecture seule')

# --- 2.2 plusieurs centaines de fichiers ---------------------------------
d = os.path.join(BASE, 'lot')
os.makedirs(d, exist_ok=True)
petite = photo(160, 120)
for i in range(300):
    petite.save(os.path.join(d, 'lot-%03d.png' % i))
faits.append(('lot-300', d, 300, '300 fichiers dans un dossier'))

print('  fabrique :')
for nom, chemin, taille, quoi in faits:
    t = ('%d o' % taille) if taille >= 0 else '-'
    print('    %-20s %-10s %s' % (nom, t, quoi))
