"""Create synthetic HEIC/AVIF fixtures; never read personal photographs.

python -m pip install --target tests/.codec-deps pillow pillow-heif
python tests/build-device-fixtures.py
"""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parent
sys.path.insert(0, str(root / '.codec-deps'))
from PIL import Image, ImageDraw
import pillow_heif

pillow_heif.register_heif_opener()
out = root / 'device-fixtures'
out.mkdir(exist_ok=True)
image = Image.new('RGB', (800, 600))
image.putdata([(x * 255 // 799, y * 255 // 599, (x + y) % 256)
               for y in range(600) for x in range(800)])
draw = ImageDraw.Draw(image)
draw.rectangle((0, 0, 99, 79), fill='red')
draw.rectangle((700, 520, 799, 599), fill='blue')
image.save(out / 'reference.png')
image.save(out / 'sample.heic', quality=95)
image.save(out / 'sample.avif', quality=95)
manifest = {}
for path in sorted(out.iterdir()):
    if path.suffix not in ('.png', '.heic', '.avif'):
        continue
    with Image.open(path) as decoded:
        decoded.load()
        assert decoded.size == image.size
        manifest[path.name] = {'bytes': path.stat().st_size,
                               'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                               'dimensions': list(decoded.size)}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps(manifest, indent=2))
