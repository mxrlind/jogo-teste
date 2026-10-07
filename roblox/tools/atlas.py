"""Junta os sprites KayKit do jogo web em poucas folhas PNG (atlas) para o Roblox.

O Roblox só mostra imagens enviadas para ele (rbxassetid://...). Em vez de enviar mais de
100 arquivos, o jogo usa 2 folhas e recorta cada sprite com ImageRectOffset/ImageRectSize.

Uso (na raiz do repositório): python3 roblox/tools/atlas.py
Gera roblox/assets/folha-1.png, folha-2.png e roblox/src/client/Atlas.luau (posições dos recortes).
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
KK = ROOT / "assets" / "sprites" / "kaykit"
OUT_DIR = ROOT / "roblox" / "assets"
LUA = ROOT / "roblox" / "src" / "client" / "Atlas.luau"
SHEET = 1024

# Metade do tamanho original: sobra nitidez para os tiles da tela e cabe em 2 folhas.
SCALE = 0.5

def sprites():
    names = sorted(p.stem for p in KK.glob("*.png"))
    skip = {"logo-castelo"}
    return [n for n in names if n not in skip]

def pack(names):
    images = []
    for n in names:
        im = Image.open(KK / f"{n}.png").convert("RGBA")
        w, h = round(im.width * SCALE), round(im.height * SCALE)
        images.append((n, im.resize((w, h), Image.LANCZOS)))
    # Mais altos primeiro: as prateleiras ficam cheias.
    images.sort(key=lambda it: (-it[1].height, it[0]))
    sheets, rects = [], {}
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    x = y = shelf = 0
    pad = 2
    for name, im in images:
        if x + im.width > SHEET:
            x, y, shelf = 0, y + shelf + pad, 0
        if y + im.height > SHEET:
            sheets.append(sheet)
            sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
            x = y = shelf = 0
        sheet.paste(im, (x, y))
        rects[name] = (len(sheets) + 1, x, y, im.width, im.height)
        x += im.width + pad
        shelf = max(shelf, im.height)
    sheets.append(sheet)
    return sheets, rects

def main():
    sheets, rects = pack(sprites())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for i, sh in enumerate(sheets, 1):
        sh.save(OUT_DIR / f"folha-{i}.png", optimize=True)
    lines = [
        "-- Gerado por roblox/tools/atlas.py: onde cada sprite KayKit está nas folhas roblox/assets/folha-N.png.",
        "-- Não edite à mão; os ids das folhas ficam em Imagens.luau.",
        "return {",
        f"\tSHEETS = {len(sheets)},",
        "\tRECTS = {",
    ]
    for name in sorted(rects):
        s, x, y, w, h = rects[name]
        lines.append(f'\t\t["{name}"] = {{ {s}, {x}, {y}, {w}, {h} }},')
    lines += ["\t},", "}", ""]
    LUA.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(rects)} sprites em {len(sheets)} folha(s)")

if __name__ == "__main__":
    main()
