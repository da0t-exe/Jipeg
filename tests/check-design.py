# -*- coding: utf-8 -*-
"""Regarde la page avec une regle plutot qu'avec un avis.

Trois choses se mesurent sans ouvrir un navigateur : le contraste de chaque
couleur de texte sur son fond, les tailles de caracteres employees, et les
valeurs d'espacement. Un design tient surtout a ce que ces trois listes soient
courtes et regulieres - une page qui emploie onze tailles de texte en emploie
neuf de trop, et personne ne saurait dire lesquelles en la regardant.
"""
import io, os, re, sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'docs', 'index.html')
s = io.open(P, encoding='utf-8').read()
css = re.search(r'<style>(.*?)</style>', s, re.S).group(1)
bad = 0


def rgb(h):
    h = h.strip().lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def luminance(c):
    def canal(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (canal(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contraste(a, b):
    la, lb = luminance(a), luminance(b)
    clair, sombre = max(la, lb), min(la, lb)
    return (clair + 0.05) / (sombre + 0.05)


# --- les variables de couleur, theme par theme ---------------------------
def palette(bloc):
    return {m.group(1): m.group(2).strip()
            for m in re.finditer(r'--([\w-]+)\s*:\s*(#[0-9a-fA-F]{3,6})', bloc)}

# La page est ecrite en sombre d'abord : :root porte le theme sombre et la
# requete media porte le clair. L'inverse existe aussi, alors on regarde ce que
# la requete annonce plutot que de le supposer - la premiere version de ce
# controle affichait deux fois les memes chiffres sans que rien ne le dise.
base = palette(re.search(r':root\{(.*?)\}', css, re.S).group(1))
autre, quel = dict(base), None
m = re.search(r'prefers-color-scheme:\s*(light|dark)\)\s*\{\s*:root[^{]*\{(.*?)\}', css, re.S)
if m:
    quel = m.group(1)
    autre.update(palette(m.group(2)))
if quel == 'light':
    sombre, clair = base, autre
else:
    clair, sombre = base, autre

print('  contraste du texte sur son fond (WCAG : 4.5 pour du texte courant)')
paires = [('ink', 'bg', 'texte principal', 4.5),
          ('dim', 'bg', 'texte secondaire', 4.5),
          ('mute', 'bg', 'texte attenue', 4.5),
          ('accent', 'bg', 'les chiffres et les liens', 4.5),
          ('dim', 'panel', 'texte sur une carte', 4.5),
          ('mute', 'panel', 'texte attenue sur carte', 4.5)]
for theme, nom in ((sombre, 'sombre'), (clair, 'clair')):
    print('    theme %s' % nom)
    for av, fond, quoi, seuil in paires:
        if av not in theme or fond not in theme:
            continue
        r = contraste(rgb(theme[av]), rgb(theme[fond]))
        etat = 'ok' if r >= seuil else 'FAIBLE'
        if r < seuil:
            bad += 1
        print('      %-26s %5.2f:1  %s' % (quoi, r, etat))

# --- l'echelle typographique --------------------------------------------
tailles = Counter(re.findall(r'font-size:\s*([\d.]+)px', css + s))
print()
print('  tailles de caracteres employees : %d valeurs' % len(tailles))
print('    ' + '  '.join('%spx(%d)' % (t, n) for t, n in
                         sorted(tailles.items(), key=lambda kv: float(kv[0]))))
if len(tailles) > 8:
    print('    -> trop de valeurs : une echelle se lit quand elle est courte')
    bad += 1

# --- le rythme des espacements ------------------------------------------
esp = Counter()
for m in re.finditer(r'(?:margin|padding|gap)[a-z-]*:\s*([^;}\n]+)', css):
    for v in re.findall(r'(\d+)px', m.group(1)):
        esp[int(v)] += 1
hors = sorted(v for v in esp if v % 2 and v > 1)
print()
print('  valeurs d espacement : %d differentes, de %dpx a %dpx'
      % (len(esp), min(esp), max(esp)))
print('    impaires (hors grille) : %s' % (hors if hors else 'aucune'))
if hors:
    bad += 1

# --- ce qui manque a l'accessibilite -------------------------------------
print()
sans_alt = re.findall(r'<img(?![^>]*\balt=)[^>]*>', s)
print('  images sans attribut alt : %d' % len(sans_alt))
if sans_alt:
    bad += 1
boutons = re.findall(r'<button[^>]*>', s)
sans_nom = [b for b in boutons if 'aria-label' not in b and '>' == b[-1]]
print('  focus-visible declare : %s' % ('oui' if ':focus-visible' in css else 'NON'))
if ':focus-visible' not in css:
    bad += 1
print('  reduced-motion respecte : %s' % ('oui' if 'prefers-reduced-motion' in css else 'NON'))
if 'prefers-reduced-motion' not in css:
    bad += 1
print('  langue declaree sur <html> : %s' % ('oui' if re.search(r'<html[^>]+lang=', s) else 'NON'))

# --- regles CSS jamais employees -----------------------------------------
classes = set(re.findall(r'\.([a-zA-Z][\w-]*)\s*[,{:]', css))
utilisees = set(re.findall(r'class="([^"]+)"', s))
vues = set()
for u in utilisees:
    vues.update(u.split())
# celles que le script cree a la volee
vues.update(re.findall(r"className\s*=\s*'([\w -]+)'", s))
vues.update(re.findall(r"classList\.(?:add|remove)\('([\w-]+)'\)", s))
mortes = sorted(c for c in classes - vues if c not in ('on',))
print()
print('  classes CSS sans emploi : %s' % (', '.join(mortes) if mortes else 'aucune'))
if mortes:
    bad += 1

print()
print('  page conforme au regard de la regle' if not bad else '  %d point(s) a reprendre' % bad)
sys.exit(1 if bad else 0)
