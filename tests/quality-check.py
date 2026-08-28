# -*- coding: utf-8 -*-
"""Mesure la fidelite du resultat, au lieu de la prendre sur parole.

L'arbre demandait ssimulacra2 ou butteraugli. Ni l'un ni l'autre n'est
installe ici et les faire venir voudrait dire installer une chaine de
compilation, ce qu'on ne fait pas. On mesure donc ce qu'on peut mesurer
honnetement : SSIM, PSNR et l'ecart maximum par canal, calcules ici meme.
Ce n'est pas la meme chose - SSIM ne modelise pas la vision comme le fait
ssimulacra2 - et la ligne du compte-rendu le dit.

  python tests/quality-check.py <dossier>
"""
import os, sys
import numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS = None


def gris(chemin):
    im = Image.open(chemin).convert('RGB')
    a = np.asarray(im, dtype=np.float64)
    return a, a @ np.array([0.2126, 0.7152, 0.0722])


def flou(x, r=4):
    """Moyenne glissante separable : une gaussienne serait plus juste, mais
    l'ecart sur le SSIM d'images de cette taille est sous le centieme."""
    k = np.ones(2 * r + 1) / (2 * r + 1)
    y = np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 0, x)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 1, y)


def ssim(a, b):
    C1, C2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = flou(a), flou(b)
    saa = flou(a * a) - ma * ma
    sbb = flou(b * b) - mb * mb
    sab = flou(a * b) - ma * mb
    num = (2 * ma * mb + C1) * (2 * sab + C2)
    den = (ma * ma + mb * mb + C1) * (saa + sbb + C2)
    return float(np.mean(num / den))


def psnr(a, b):
    eqm = float(np.mean((a - b) ** 2))
    return float('inf') if eqm == 0 else 10 * np.log10(255.0 ** 2 / eqm)


base = sys.argv[1] if len(sys.argv) > 1 else '.'
paires = []
ambigus = []
for r, _, fs in os.walk(base):
    for f in fs:
        if '_jipeg.' not in f:
            continue
        sortie = os.path.join(r, f)
        souche = f.split('_jipeg.')[0]
        # Plusieurs sources peuvent porter la meme souche - icc-adobergb.png et
        # icc-adobergb.jpg par exemple. La premiere version prenait la premiere
        # extension de la liste et a compare une sortie JPEG a une source PNG :
        # SSIM 0.99, ecart 205, et une taille annoncee en hausse de 316%. Quand
        # il y a un doute on ne devine pas, on le dit.
        candidats = [os.path.join(r, souche + e)
                     for e in ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif', '.tif')
                     if os.path.exists(os.path.join(r, souche + e))]
        if len(candidats) == 1:
            paires.append((candidats[0], sortie))
        elif len(candidats) > 1:
            ambigus.append((souche, len(candidats)))

if not paires:
    print('  aucune paire source/sortie trouvee dans %s' % base)
    raise SystemExit(1)

if ambigus:
    print('  %d souche(s) ambigues, non mesurees : %s'
          % (len(ambigus), ', '.join('%s (%d sources)' % a for a in ambigus[:4])))
print('  %d paires mesurees   (SSIM, pas ssimulacra2 : voir l en-tete)' % len(paires))
print('  %-28s %8s %8s %7s %s' % ('fichier', 'SSIM', 'PSNR dB', 'ecart', 'taille'))
faibles = []
for src, out in sorted(paires)[:14]:
    a3, ag = gris(src)
    b3, bg = gris(out)
    if a3.shape != b3.shape:
        print('  %-28s dimensions differentes : %s vs %s' % (os.path.basename(src)[:28], a3.shape, b3.shape))
        continue
    s = ssim(ag, bg)
    p = psnr(a3, b3)
    ecart = int(np.max(np.abs(a3 - b3)))
    gain = 100 - os.path.getsize(out) * 100.0 / os.path.getsize(src)
    marque = '' if s >= 0.95 else '   <- sous 0.95'
    if s < 0.95:
        faibles.append((os.path.basename(src), s))
    print('  %-28s %8.4f %8.1f %7d %5.0f%%%s'
          % (os.path.basename(src)[:28], s, p, ecart, gain, marque))

print()
if faibles:
    print('  %d image(s) sous 0.95 de SSIM' % len(faibles))
else:
    print('  toutes au-dessus de 0.95 de SSIM')
