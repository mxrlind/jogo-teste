"""Junta os sons do jogo web em 3 arquivos para o Roblox (cada envio de áudio conta no limite mensal da conta).

- efeitos.ogg: os 22 efeitos (Kenney, CC0) em sequência, com 0,25 s de silêncio entre eles.
  O jogo toca cada um com Sound.PlaybackRegion (início e fim em segundos).
- musica-vila.ogg e musica-batalha.ogg: as faixas de cada clima (RandomMind e nene, CC0) em sequência,
  igual à playlist do web, que toca as faixas do clima atual uma depois da outra.

Uso (na raiz do repositório): python3 roblox/tools/audio.py
Gera roblox/assets/audio/*.ogg e roblox/src/client/Modulos/Sons.luau (onde cada som começa e termina).
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "assets" / "sfx"
MUSIC = ROOT / "assets" / "music"
OUT = ROOT / "roblox" / "assets" / "audio"
LUA = ROOT / "roblox" / "src" / "client" / "Modulos" / "Sons.luau"
RATE = 44100
GAP = 0.25
# Mesma ordem de SFX_NAMES em src/ui/audio.js.
SFX_NAMES = ['click', 'open', 'close', 'error', 'tab', 'upgrade', 'confirm', 'event', 'build', 'mine', 'warn',
             'coin', 'cart', 'chop', 'recruit', 'expedition', 'win', 'lose', 'tier', 'achievement', 'legendary', 'ascend']


def pcm(path):
    """Decodifica para PCM 16 bits estéreo: o tamanho em amostras dá a duração exata."""
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-"],
                          check=True, capture_output=True).stdout


def encode(raw, path, quality):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), str(path)], input=raw, check=True)


def concat(files, gap):
    parts, spans, t = [], [], 0.0
    silence = b"\0" * (int(RATE * gap) * 4)
    for f in files:
        raw = pcm(f)
        dur = len(raw) / 4 / RATE
        spans.append((round(t, 3), round(t + dur, 3)))
        parts += [raw, silence]
        t += dur + gap
    return b"".join(parts), spans


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    raw, spans = concat([SFX / f"{n}.mp3" for n in SFX_NAMES], GAP)
    encode(raw, OUT / "efeitos.ogg", 5)
    tracks = json.loads((MUSIC / "music.json").read_text())["tracks"]
    lines = [
        "-- Gerado por roblox/tools/audio.py. Não edite à mão; os ids dos áudios ficam em ReplicatedStorage.Reino.Imagens.",
        "return {",
        "\tefeitos = {",
    ]
    for n, (a, b) in zip(SFX_NAMES, spans):
        lines.append(f"\t\t{n} = {{ {a}, {b} }},")
    lines.append("\t},")
    lines.append("\tmusica = {")
    for mood in ("vila", "batalha"):
        mine = [t for t in tracks if t["mood"] == mood]
        raw, spans = concat([MUSIC / t["file"] for t in mine], 0.5)
        encode(raw, OUT / f"musica-{mood}.ogg", 3)
        lines.append(f"\t\t{mood} = {{")
        for t, (a, b) in zip(mine, spans):
            lines.append(f'\t\t\t{{ title = "{t["title"]}", author = "{t["author"]}", license = "{t["license"]}", '
                         f'url = "{t["url"]}", from = {a}, to = {b} }},')
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    LUA.write_text("\n".join(lines), encoding="utf-8")
    for p in sorted(OUT.glob("*.ogg")):
        print(p.name, p.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
