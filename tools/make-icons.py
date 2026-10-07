# Gera o ícone do app e o favicon a partir dos sprites do KayKit (CC0) gerados por tools/render-kaykit.mjs.
# Uso: python3 tools/make-icons.py   (requer Pillow)
from PIL import Image
import os
ROOT = os.path.join(os.path.dirname(__file__), '..')
KK = os.path.join(ROOT, 'assets/sprites/kaykit')
OUT = os.path.join(ROOT, 'assets/icons/app')
os.makedirs(OUT, exist_ok=True)
grass = Image.open(f'{KK}/grass-1.png').convert('RGBA')
castle = Image.open(f'{KK}/logo-castelo.png').convert('RGBA')
castle = castle.crop(castle.getbbox())
for size, pad in [(512, 0.14), (192, 0.14), (180, 0.14), (64, 0.06), (32, 0.04)]:
    bg = grass.resize((size, size), Image.LANCZOS)
    inner = int(size * (1 - 2 * pad))
    scale = inner / max(castle.size)
    c = castle.resize((max(1, int(castle.width * scale)), max(1, int(castle.height * scale))), Image.LANCZOS)
    bg.alpha_composite(c, ((size - c.width) // 2, (size - c.height) // 2))
    name = {512: 'icon-512.png', 192: 'icon-192.png', 180: 'apple-touch-icon.png', 64: 'favicon-64.png', 32: 'favicon-32.png'}[size]
    bg.save(os.path.join(OUT, name))
print('ícones gerados em', OUT)
