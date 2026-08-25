# -*- coding: utf-8 -*-
"""Fabrique un lot aleatoire et un lot mute.

Le lot ecrit a la main teste 48 situations que j'ai imaginees, et le bug de la
transparence est passe dessous pendant des mois parce que je n'avais pas pense
a "WebP transparent". Ici on ne verifie plus un resultat attendu mais des
regles qui doivent tenir quoi qu'il arrive.
"""
import io, os, random, shutil, struct, sys, json
from PIL import Image, ImageDraw, ImageFilter

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 4242
random.seed(SEED)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'random')
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)

FORMATS = ['png', 'jpg', 'webp', 'gif', 'bmp', 'tif']

def contenu(w, h):
    """Trois familles : du bruit doux, des aplats, un degrade."""
    kind = random.choice(('photo', 'aplats', 'degrade'))
    im = Image.new('RGB', (w, h))
    px = im.load()
    if kind == 'photo':
        for y in range(h):
            for x in range(w):
                n = random.randint(-16, 16)
                px[x, y] = (max(0, min(255, 110 + x * 90 // max(1, w) + n)),
                            max(0, min(255, 100 + y * 90 // max(1, h) + n)),
                            max(0, min(255, 150 - x * 60 // max(1, w) + n)))
        im = im.filter(ImageFilter.GaussianBlur(1.0))
    elif kind == 'aplats':
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, w, h), fill=(248, 248, 250))
        for i in range(random.randint(2, 7)):
            x0 = random.randint(0, max(0, w - 2)); y0 = random.randint(0, max(0, h - 2))
            d.rectangle((x0, y0, min(w, x0 + w // 3), min(h, y0 + h // 5)),
                        fill=(random.randint(0, 255), random.randint(0, 255), random.randint(0, 255)))
    else:
        for y in range(h):
            for x in range(w):
                px[x, y] = (x * 255 // max(1, w), y * 255 // max(1, h), 128)
    return im, kind

def avec_alpha(im, w, h):
    """Perce un trou : un vrai pixel transparent, pas seulement un canal."""
    r = im.convert('RGBA')
    d = ImageDraw.Draw(r)
    d.ellipse((max(0, w // 6), max(0, h // 6), max(2, w * 5 // 6), max(2, h * 5 // 6)),
              fill=(0, 0, 0, 0))
    return r

FICHES = []

# ------------------------------------------------------- 1. lot aleatoire
N = int(os.environ.get('JIPEG_FUZZ_N', '100'))
for i in range(N):
    w = random.choice([1, 2, 3, 7, 16, 33, 64, 120, 200, 320, 400, 500])
    h = random.choice([1, 2, 5, 11, 24, 50, 90, 150, 240, 300, 380])
    fmt = random.choice(FORMATS)
    im, kind = contenu(w, h)
    alpha = random.random() < 0.35 and fmt in ('png', 'webp', 'gif', 'tif')
    if alpha:
        im = avec_alpha(im, w, h)
    mode = 'RGBA' if alpha else 'RGB'

    name = 'a%03d-%s-%dx%d-%s%s.%s' % (i, fmt, w, h, kind, '-alpha' if alpha else '', fmt)
    p = os.path.join(OUT, name)
    try:
        if fmt == 'jpg':
            im.convert('RGB').save(p, quality=random.choice([70, 85, 92, 97]))
        elif fmt == 'gif':
            g = im.convert('RGBA') if alpha else im
            g = g.convert('P', palette=Image.ADAPTIVE, colors=random.choice([16, 64, 256]))
            if alpha:
                g.save(p, transparency=0)
            else:
                g.save(p)
        elif fmt == 'webp':
            im.save(p, lossless=random.random() < 0.5, quality=random.randint(60, 95))
        elif fmt == 'bmp':
            im.convert('RGB').save(p)
        else:
            im.save(p)
    except Exception:
        continue
    FICHES.append(name)

# ------------------------------------------------------- 2. lot mute
# Des octets retournes au hasard dans un fichier valide. Rien n'est attendu de
# ces fichiers sinon que Jipeg ne se bloque pas, n'ecrive rien de casse et ne
# laisse rien derriere lui.
sains = [f for f in FICHES if os.path.getsize(os.path.join(OUT, f)) > 200]
M = int(os.environ.get('JIPEG_FUZZ_M', '60'))
for i in range(M):
    src = random.choice(sains)
    raw = bytearray(io.open(os.path.join(OUT, src), 'rb').read())
    combien = random.choice([1, 1, 2, 4, 12, 40])
    for _ in range(combien):
        pos = random.randrange(len(raw))
        raw[pos] = random.randrange(256)
    if random.random() < 0.2:                       # parfois on coupe la fin
        raw = raw[:random.randrange(1, len(raw))]
    ext = os.path.splitext(src)[1]
    name = 'm%03d-mute%d%s' % (i, combien, ext)
    io.open(os.path.join(OUT, name), 'wb').write(bytes(raw))
    FICHES.append(name)

io.open(os.path.join(HERE, 'random-index.json'), 'w', encoding='utf-8').write(
    json.dumps({'graine': SEED, 'fichiers': FICHES}, ensure_ascii=False))
total = sum(os.path.getsize(os.path.join(OUT, f)) for f in FICHES)
print('%d fichiers (%d aleatoires, %d mutes), %.1f Mo, graine %d'
      % (len(FICHES), len(FICHES) - M, M, total / 1048576.0, SEED))
