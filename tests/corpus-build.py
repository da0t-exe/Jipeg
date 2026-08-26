# -*- coding: utf-8 -*-
"""Fabrique un lot d'epreuve large et varie, avec pour chaque fichier ce qu'on
attend de lui. 'jpg' = doit sortir en JPEG, 'png' = doit rester un PNG,
'rien' = ne doit produire aucun fichier (trop petit, illisible, ou deja bon)."""
import io, os, stat, struct, random, shutil, sys

random.seed(11)
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'corpus')
def _forcer(fonction, chemin, info):
    # Le lot contient un fichier en lecture seule, expres. Sous Windows,
    # os.unlink refuse d'y toucher : il faut lever l'attribut d'abord, sinon
    # le generateur ne sait pas nettoyer ce qu'il a lui-meme ecrit.
    os.chmod(chemin, stat.S_IWRITE)
    fonction(chemin)

if os.path.isdir(OUT):
    shutil.rmtree(OUT, onexc=_forcer)
os.makedirs(OUT)

ATTENDU = {}

def p(name):
    return os.path.join(OUT, name)

def note(name, expect, why):
    ATTENDU[name] = (expect, why)

# ---------------------------------------------------------------- fabriques
def photo(w, h):
    """Du bruit lisse : ce qu'un JPEG sait comprimer et un PNG non."""
    im = Image.new('RGB', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            n = random.randint(-18, 18)
            px[x, y] = (max(0, min(255, 120 + (x * 255 // w) // 2 + n)),
                        max(0, min(255, 90 + (y * 255 // h) // 2 + n)),
                        max(0, min(255, 160 - (x * 120 // w) + n)))
    return im.filter(__import__('PIL.ImageFilter', fromlist=['x']).GaussianBlur(1.1))

def aplats(w, h):
    """Des aplats et du texte : ce que le JPEG rend plus lourd."""
    im = Image.new('RGB', (w, h), (250, 250, 252))
    d = ImageDraw.Draw(im)
    for i in range(6):
        d.rectangle((10, 10 + i * (h // 7), w - 10, 10 + i * (h // 7) + h // 9),
                    fill=((i * 40) % 256, 200 - i * 20, 90 + i * 25))
    d.text((14, h - 30), 'Jipeg' * 6, fill=(20, 20, 20))
    return im

# ---------------------------------------------------------------- 1. PNG
photo(700, 500).save(p('01-png-photo.png'))
note('01-png-photo.png', 'jpg', 'photo bruitee, le JPEG doit gagner gros')

aplats(600, 420).save(p('02-png-aplats.png'))
note('02-png-aplats.png', 'png', 'aplats et texte : le JPEG serait plus lourd')

im = Image.new('RGBA', (400, 300), (0, 0, 0, 0))
ImageDraw.Draw(im).ellipse((30, 20, 370, 280), fill=(230, 80, 60, 255))
im.save(p('03-png-alpha.png'))
note('03-png-alpha.png', 'png', 'alpha vrai, doit rester PNG sans perte')

im = Image.new('RGBA', (300, 200), (0, 0, 0, 0))
ImageDraw.Draw(im).rectangle((20, 20, 280, 180), fill=(40, 190, 120, 255))
im.convert('P', palette=Image.ADAPTIVE, colors=32).save(p('04-png-palette-trns.png'), transparency=0)
note('04-png-palette-trns.png', 'png', 'palette avec tRNS : transparence a garder')

aplats(500, 350).convert('P', palette=Image.ADAPTIVE, colors=64).save(p('05-png-palette-opaque.png'))
note('05-png-palette-opaque.png', 'png', 'palette opaque, aplats : doit rester PNG')

photo(600, 400).convert('L').save(p('06-png-gris.png'))
note('06-png-gris.png', 'jpg', 'gris : doit sortir en JPEG mode L')

photo(500, 380).save(p('07-png-entrelace.png'), interlace=True)
note('07-png-entrelace.png', 'jpg', 'PNG entrelace (Adam7)')

im = Image.new('I;16', (300, 200))
px = im.load()
for y in range(200):
    for x in range(300):
        px[x, y] = (x * 200 + y * 90) % 65535
im.save(p('08-png-16bits.png'))
note('08-png-16bits.png', 'png', '16 bits : le JPEG serait plus lourd, la reprise sans perte gagne')

photo(1, 1).save(p('09-png-1x1.png'))
note('09-png-1x1.png', 'rien', 'un seul pixel : rien de plus leger a produire')

photo(2000, 40).save(p('10-png-tres-large.png'))
note('10-png-tres-large.png', 'jpg', 'rapport d aspect extreme')

photo(37, 1301).save(p('11-png-tres-haut.png'))
note('11-png-tres-haut.png', 'jpg', 'hauteur impaire et etroite')

photo(1600, 1200).save(p('12-png-grand.png'))
note('12-png-grand.png', 'jpg', 'grande image')

# ---------------------------------------------------------------- 2. JPEG
photo(700, 500).save(p('20-jpg-qualite95.jpg'), quality=95)
note('20-jpg-qualite95.jpg', 'jpg', 'JPEG de bonne qualite : doit maigrir')

photo(600, 400).save(p('21-jpg-progressif.jpg'), quality=92, progressive=True)
note('21-jpg-progressif.jpg', 'jpg', 'JPEG progressif')

photo(500, 350).convert('L').save(p('22-jpg-gris.jpg'), quality=90)
note('22-jpg-gris.jpg', 'jpg', 'JPEG deja en gris')

photo(400, 300).save(p('23-jpg-deja-petit.jpg'), quality=35)
note('23-jpg-deja-petit.jpg', 'rien', 'deja tres comprime : ne doit pas grossir')

photo(300, 200).convert('CMYK').save(p('24-jpg-cmjn.jpg'), quality=90)
note('24-jpg-cmjn.jpg', 'jpg', 'quatre composantes : cjpegli refuse, Windows decode')

photo(500, 350).save(p('25-jpg-444.jpg'), quality=95, subsampling=0)
note('25-jpg-444.jpg', 'jpg', 'source en 4:4:4')

# les huit orientations Exif
def exif_oriente(n, name):
    im = photo(300, 200)
    ex = im.getexif()
    ex[0x0112] = n
    im.save(p(name), quality=92, exif=ex)
for n in range(1, 9):
    nom = '26-jpg-orientation-%d.jpg' % n
    exif_oriente(n, nom)
    note(nom, 'jpg', 'Exif orientation %d' % n)

# ---------------------------------------------------------------- 3. WebP
photo(600, 420).save(p('30-webp-avec-perte.webp'), quality=80)
note('30-webp-avec-perte.webp', 'rien', 'photo deja legere : le JPEG serait plus gros, original garde')

photo(500, 350).save(p('31-webp-sans-perte.webp'), lossless=True)
note('31-webp-sans-perte.webp', 'jpg', 'WebP sans perte')

im = Image.new('RGBA', (300, 220), (0, 0, 0, 0))
ImageDraw.Draw(im).ellipse((20, 20, 280, 200), fill=(60, 120, 240, 255))
im.save(p('32-webp-alpha.webp'), lossless=True)
note('32-webp-alpha.webp', 'rien', 'transparent et minuscule : rien de plus leger sans perte')

frames = [photo(200, 150) for _ in range(4)]
frames[0].save(p('33-webp-anime.webp'), save_all=True, append_images=frames[1:], duration=120, loop=0)
note('33-webp-anime.webp', 'jpg', 'WebP anime : webpmux doit extraire la 1re image')

# ---------------------------------------------------------------- 4. autres
aplats(400, 300).convert('P', palette=Image.ADAPTIVE, colors=64).save(p('40-gif-fixe.gif'))
note('40-gif-fixe.gif', 'png', 'GIF d aplats : le JPEG serait plus gros, la reprise sans perte prend le relais')

gf = [photo(200, 150).convert('P', palette=Image.ADAPTIVE) for _ in range(5)]
gf[0].save(p('41-gif-anime.gif'), save_all=True, append_images=gf[1:], duration=100, loop=0)
note('41-gif-anime.gif', 'jpg', 'GIF anime : premiere image')

photo(600, 400).save(p('42-bmp.bmp'))
note('42-bmp.bmp', 'jpg', 'BMP non comprime')

photo(500, 400).save(p('43-tiff.tif'))
note('43-tiff.tif', 'jpg', 'TIFF')

aplats(256, 256).save(p('44-ico.ico'))
note('44-ico.ico', 'rien', 'ICO ecrite par Pillow que Windows lui-meme refuse, GDI+ comme WIC')

photo(400, 300).save(p('45-ppm.ppm'))
note('45-ppm.ppm', 'jpg', 'PPM, lu par cjpegli lui-meme')

# APNG
af = [photo(200, 150).convert('RGBA') for _ in range(4)]
af[0].save(p('46-apng.png'), save_all=True, append_images=af[1:], duration=120, loop=0)
note('46-apng.png', 'png', 'APNG : alpha present, donc reste un PNG')

# ---------------------------------------------------------------- 5. tordus
io.open(p('50-vide.png'), 'wb').write(b'')
note('50-vide.png', 'rien', 'fichier vide')

raw = io.open(p('01-png-photo.png'), 'rb').read()
io.open(p('51-tronque.png'), 'wb').write(raw[:len(raw) // 3])
note('51-tronque.png', 'rien', 'PNG coupe au tiers')

shutil.copy(p('20-jpg-qualite95.jpg'), p('52-jpeg-deguise-en-png.png'))
note('52-jpeg-deguise-en-png.png', 'jpg', 'JPEG portant une extension .png')

shutil.copy(p('01-png-photo.png'), p('53-png-deguise-en-jpg.jpg'))
note('53-png-deguise-en-jpg.jpg', 'jpg', 'PNG portant une extension .jpg')

io.open(p('54-texte.png'), 'wb').write(b'ceci n est pas une image, seulement du texte' * 40)
note('54-texte.png', 'rien', 'du texte avec une extension d image')

photo(400, 300).save(p('55-nom avec des espaces et des accents ete.png'))
note('55-nom avec des espaces et des accents ete.png', 'jpg', 'espaces et accents dans le nom')

photo(400, 300).save(p('56-nom-tres-' + 'long' * 30 + '.png'))
note('56-nom-tres-' + 'long' * 30 + '.png', 'jpg', 'nom de 130 caracteres')

photo(400, 300).save(p('57-lecture-seule.png'))
note('57-lecture-seule.png', 'jpg', 'source en lecture seule')

photo(400, 300).save(p('58-deja-converti_jipeg.png'))
note('58-deja-converti_jipeg.png', 'jpg', 'nom portant deja le suffixe')

photo(300, 220).save(p('59-点心-日本語.png'))
note('59-点心-日本語.png', 'jpg', 'nom en caracteres CJK')

io.open(p('60-entete-png-corps-vide.png'), 'wb').write(
    b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\x0dIHDR' + struct.pack('>II', 10, 10) + b'\x08\x02\x00\x00\x00')
note('60-entete-png-corps-vide.png', 'rien', 'signature PNG mais rien derriere')

# ---------------------------------------------------------------- inventaire
os.chmod(p('57-lecture-seule.png'), 0o444)

print('%d fichiers dans %s' % (len(ATTENDU), OUT))
import json
io.open(os.path.join(os.path.dirname(OUT), 'corpus-expected.json'), 'w', encoding='utf-8').write(
    json.dumps(ATTENDU, ensure_ascii=False, indent=1))
tot = sum(os.path.getsize(p(n)) for n in ATTENDU)
print('%.1f Mo au total' % (tot / 1048576.0))
