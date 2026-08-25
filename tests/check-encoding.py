# -*- coding: utf-8 -*-
"""Passe en revue tout le depot : encodage, fins de ligne, octets nuls."""
import io, os, glob, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bad = 0

BOM = b'\xef\xbb\xbf'
groups = [
    ('*.ps1 / *.psd1  (UTF-8 avec BOM, CRLF)',
     glob.glob(os.path.join(ROOT, 'src', '*.ps1'))
     + glob.glob(os.path.join(ROOT, 'tests', '*.ps1'))
     + glob.glob(os.path.join(ROOT, 'src', 'lang', '*.psd1')), True, b'\r\n'),
    ('install.ps1 / uninstall.ps1  (ASCII pur, sans BOM)',
     [os.path.join(ROOT, 'install.ps1'), os.path.join(ROOT, 'uninstall.ps1')], False, b'\r\n'),
    ('*.sh  (sans BOM, LF)',
     glob.glob(os.path.join(ROOT, 'platform', '*.sh')), False, b'\n'),
    ('*.md / *.html  (sans BOM, LF)',
     [os.path.join(ROOT, 'README.md'), os.path.join(ROOT, 'docs', 'index.html'),
      os.path.join(ROOT, 'platform', 'README.md'),
      os.path.join(ROOT, 'tests', 'README.md')], False, b'\n'),
    ('tests/*.py  (sans BOM, LF)',
     glob.glob(os.path.join(ROOT, 'tests', '*.py')), False, b'\n'),
]

for label, files, want_bom, want_eol in groups:
    print('  %s' % label)
    for f in files:
        raw = io.open(f, 'rb').read()
        why = []
        has_bom = raw.startswith(BOM)
        if has_bom != want_bom:
            why.append('BOM ' + ('en trop' if has_bom else 'absent'))
        body = raw[3:] if has_bom else raw
        if want_eol == b'\r\n':
            if body.count(b'\n') != body.count(b'\r\n'):
                why.append('des LF isoles')
        else:
            if b'\r\n' in body:
                why.append('des CRLF')
        if b'\x00' in body:
            why.append('octets nuls')
        if not want_bom and label.startswith('install'):
            try:
                body.decode('ascii')
            except UnicodeDecodeError:
                why.append('pas de l ASCII pur')
        if why:
            print('    %-28s %s' % (os.path.basename(f), ', '.join(why)))
            bad += 1
    print('    %d fichiers' % len(files))

print()
print('  %s' % ('tout est conforme' if not bad else '%d fichier(s) a reprendre' % bad))
sys.exit(1 if bad else 0)
