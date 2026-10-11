"""Junta as imagens do jogo web em poucas folhas PNG (atlas) para o Roblox.

O Roblox só mostra imagens enviadas para ele (rbxassetid://...). Em vez de enviar centenas de arquivos,
o jogo usa poucas folhas de até 1024 px e recorta cada imagem com ImageRectOffset/ImageRectSize.

Folhas:
- sprites-N: KayKit (prédios, natureza, subsolo; CC0), Kenney Medieval RTS (moradores, invasores, carroça; CC0),
  o logo e a hélice do moinho já girada (o web gira no canvas; o Roblox não achata uma imagem girada).
- icones-N: ícones do game-icons.net (CC BY 3.0) em branco, para tingir com ImageColor3.
- ui-N: botões e caixas do Kenney UI Pack (CC0), rosa dos ventos, estandarte e peças desenhadas aqui
  (sombra, brilho, raios, vinheta, chama, tracejado).

Uso (na raiz do repositório): node roblox/tools/render-ui.mjs && python3 roblox/tools/atlas.py
Gera roblox/assets/<folha>.png e roblox/src/client/Modulos/Atlas.luau (onde cada imagem está).
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
KK = ROOT / "assets" / "sprites" / "kaykit"
RTS = ROOT / "assets" / "sprites" / "medieval-rts"
KUI = ROOT / "assets" / "ui" / "kenney-ui-pack"
BUILD = ROOT / "roblox" / "assets" / "build"
OUT_DIR = ROOT / "roblox" / "assets"
LUA = ROOT / "roblox" / "src" / "client" / "Modulos" / "Atlas.luau"
SHEET = 1024
PAD = 2

# Metade do tamanho original: sobra nitidez para os tiles da tela.
SPRITE_SCALE = 0.5
# Unidades e estruturas do Medieval RTS usadas em src/ui/sprites.js.
RTS_UNITS = [1, 2, 3, 4, 8, 9, 10, 12, 13, 17, 18, 19, 21, 23, 24]
RTS_STRUCTURES = [7]
BLADE_FRAMES = 12  # a hélice tem simetria de 90 graus: 12 quadros de 7,5 graus
SPRITE_K = 0.7     # igual a SPRITE_K de src/ui/sprites.js


def scaled(im, k):
    if k == 1:
        return im
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def sprite_images():
    out = []
    for p in sorted(KK.glob("*.png")):
        k = SPRITE_SCALE
        if p.stem == "building-moinho-blades":
            continue
        out.append((p.stem, scaled(Image.open(p).convert("RGBA"), k)))
    for n in RTS_UNITS:
        im = Image.open(RTS / "Unit" / f"medievalUnit_{n:02d}.png").convert("RGBA")
        out.append((f"rts-u{n}", scaled(im, SPRITE_SCALE)))
    for n in RTS_STRUCTURES:
        im = Image.open(RTS / "Structure" / f"medievalStructure_{n:02d}.png").convert("RGBA")
        out.append((f"rts-s{n}", scaled(im, SPRITE_SCALE)))
    blades = Image.open(KK / "building-moinho-blades.png").convert("RGBA")
    for f in range(BLADE_FRAMES):
        ang = 90 * f / BLADE_FRAMES
        # canvas: rotate(ângulo) e depois scale(1, SPRITE_K) -> a imagem girada é achatada na vertical.
        rot = blades.rotate(-ang, resample=Image.BICUBIC)
        out.append((f"blades-{f + 1}", rot.resize((rot.width, round(rot.height * SPRITE_K)), Image.LANCZOS)))
    return out


def icon_images():
    return [(f"ico/{p.stem}", Image.open(p).convert("RGBA")) for p in sorted((BUILD / "icons").glob("*.png"))]


def soft(size, draw_fn, blur):
    im = Image.new("L", (size, size), 0)
    draw_fn(ImageDraw.Draw(im))
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return im


def white_with_alpha(alpha, rgb=(255, 255, 255)):
    im = Image.new("RGBA", alpha.size, rgb + (0,))
    im.putalpha(alpha)
    return im


def ui_images():
    out = []
    for p in sorted(KUI.glob("*.png")):
        out.append((f"ui/{p.stem}", Image.open(p).convert("RGBA")))
    for p in sorted((BUILD / "ui").glob("*.png")):
        out.append((f"ui/{p.stem}", Image.open(p).convert("RGBA")))
    # Sombra suave para 9-slice (box-shadow do CSS): retângulo arredondado borrado, 96 px, miolo de 32 a 64.
    a = soft(96, lambda d: d.rounded_rectangle((24, 24, 72, 72), radius=10, fill=255), 9)
    out.append(("ui/shadow", white_with_alpha(a, (0, 0, 0))))
    # Brilho radial (radial-gradient): branco no centro sumindo na borda.
    g = Image.new("L", (128, 128), 0)
    px = g.load()
    for y in range(128):
        for x in range(128):
            r = math.hypot(x - 63.5, y - 63.5) / 64
            px[x, y] = max(0, min(255, round(255 * (1 - r) ** 1.6))) if r < 1 else 0
    out.append(("ui/glow", white_with_alpha(g)))
    # Disco liso (bolinhas, faíscas, fumaça).
    disc = soft(64, lambda d: d.ellipse((1, 1, 62, 62), fill=255), 0)
    out.append(("ui/disc", white_with_alpha(disc)))
    smoke = soft(64, lambda d: d.ellipse((8, 8, 56, 56), fill=255), 4)
    out.append(("ui/smoke", white_with_alpha(smoke)))
    # Raios girando atrás do retrato do herói (repeating-conic-gradient com máscara radial).
    n = 256
    rays = Image.new("L", (n, n), 0)
    px = rays.load()
    for y in range(n):
        for x in range(n):
            dx, dy = x - n / 2 + 0.5, y - n / 2 + 0.5
            r = math.hypot(dx, dy) / (n / 2)
            if r >= 1:
                continue
            ang = (math.degrees(math.atan2(dy, dx)) + 360) % 30
            on = 255 if ang < 10 else 0
            mask = 1 if r < 0.2 else max(0, 1 - (r - 0.2) / 0.5)
            px[x, y] = round(on * mask)
    out.append(("ui/rays", white_with_alpha(rays)))
    # Vinheta do menu (radial-gradient transparente no meio, escuro na borda).
    v = Image.new("L", (256, 256), 0)
    px = v.load()
    for y in range(256):
        for x in range(256):
            r = math.hypot(x - 127.5, y - 127.5) / 128
            t = 0 if r < 0.3 else min(1, (r - 0.3) / 0.7)
            px[x, y] = round(255 * t)
    out.append(("ui/vignette", white_with_alpha(v, (14, 12, 20))))
    # Chama em gota (drawDamage de src/ui/render.js): base larga, ponta para cima, miolo amarelo.
    fl = Image.new("RGBA", (40, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(fl)
    def drop(cx, by, w, h, color):
        pts = []
        for i in range(21):
            t = i / 20
            pts.append((cx - w + 2 * w * t, by - h * math.sin(math.pi * t) ** 1.5))
        d.polygon([(cx - w, by)] + pts + [(cx + w, by)], fill=color)
        d.ellipse((cx - w, by - w, cx + w, by + w), fill=color)
    drop(20, 50, 13, 46, (232, 89, 40, 235))
    drop(20, 52, 7, 24, (255, 214, 90, 245))
    out.append(("ui/flame", fl))
    # Tracejado da borda do território (setLineDash([8, 5])): um traço e um vão, repetidos com ScaleType.Tile.
    dh = Image.new("RGBA", (13, 3), (0, 0, 0, 0))
    ImageDraw.Draw(dh).rectangle((0, 0, 7, 2), fill=(255, 255, 255, 255))
    out.append(("ui/dash-h", dh))
    out.append(("ui/dash-v", dh.rotate(90, expand=True)))
    return out


def pack(prefix, images):
    images = sorted(images, key=lambda it: (-it[1].height, it[0]))
    sheets, rects = [], {}
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    x = y = shelf = 0
    for name, im in images:
        if x + im.width > SHEET:
            x, y, shelf = 0, y + shelf + PAD, 0
        if y + im.height > SHEET:
            sheets.append(sheet)
            sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
            x = y = shelf = 0
        sheet.paste(im, (x, y))
        rects[name] = (f"{prefix}-{len(sheets) + 1}", x, y, im.width, im.height)
        x += im.width + PAD
        shelf = max(shelf, im.height)
    sheets.append(sheet)
    return [(f"{prefix}-{i}", s) for i, s in enumerate(sheets, 1)], rects


def main():
    all_sheets, all_rects = [], {}
    for prefix, imgs in (("sprites", sprite_images()), ("icones", icon_images()), ("ui", ui_images())):
        sheets, rects = pack(prefix, imgs)
        all_sheets += sheets
        all_rects.update(rects)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.png"):
        old.unlink()
    for name, sh in all_sheets:
        sh.save(OUT_DIR / f"{name}.png", optimize=True)
    lines = [
        "-- Gerado por roblox/tools/atlas.py: onde cada imagem está nas folhas roblox/assets/<folha>.png.",
        "-- Não edite à mão. Os ids das folhas no Roblox ficam em ReplicatedStorage.Reino.Imagens.",
        "return {",
        "\tsheets = { " + ", ".join(f'"{n}"' for n, _ in all_sheets) + " },",
        "\trects = {",
    ]
    for name in sorted(all_rects):
        sheet, x, y, w, h = all_rects[name]
        lines.append(f'\t\t["{name}"] = {{ "{sheet}", {x}, {y}, {w}, {h} }},')
    lines += ["\t},", "}", ""]
    LUA.parent.mkdir(parents=True, exist_ok=True)
    LUA.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(all_rects)} imagens em {len(all_sheets)} folhas: " + ", ".join(n for n, _ in all_sheets))


if __name__ == "__main__":
    main()
