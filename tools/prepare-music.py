#!/usr/bin/env python3
"""Instala uma música em loop no jogo.

Converte o arquivo baixado (WAV, OGG, FLAC ou MP3) para MP3 de 128 kbps em assets/music/
e registra título, autor, licença e link em assets/music/music.json. Os créditos do jogo
leem esse arquivo, então a atribuição aparece sozinha.

Uso (exemplo com a faixa recomendada no EXECUTAR.md):
  pip install soundfile lameenc numpy
  python3 tools/prepare-music.py ~/Downloads/<arquivo-baixado>.wav \\
      --title "Medieval: Minstrel Dance" --author "RandomMind" --license "CC0" \\
      --url "https://opengameart.org/content/medieval-minstrel-dance"
"""
import argparse
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT_DIR = os.path.join(ROOT, 'assets', 'music')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('arquivo', help='arquivo de áudio baixado (wav, ogg, flac ou mp3)')
    ap.add_argument('--title', required=True, help='título da faixa')
    ap.add_argument('--author', required=True, help='autor da faixa')
    ap.add_argument('--license', required=True, help='licença (ex.: CC0, CC BY 4.0)')
    ap.add_argument('--url', required=True, help='página de onde a faixa foi baixada')
    ap.add_argument('--kbps', type=int, default=128, help='taxa do MP3 (padrão 128)')
    args = ap.parse_args()

    try:
        import numpy as np
        import soundfile as sf
        import lameenc
    except ImportError:
        sys.exit('Faltam bibliotecas. Rode: pip install soundfile lameenc numpy')

    data, rate = sf.read(args.arquivo, dtype='float32', always_2d=True)
    channels = min(2, data.shape[1])
    pcm = (np.clip(data[:, :channels], -1, 1) * 32767).astype('<i2')
    enc = lameenc.Encoder()
    enc.set_bit_rate(args.kbps)
    enc.set_in_sample_rate(rate)
    enc.set_channels(channels)
    enc.set_quality(2)
    mp3 = enc.encode(pcm.tobytes()) + enc.flush()

    os.makedirs(OUT_DIR, exist_ok=True)
    name = 'tema.mp3'
    with open(os.path.join(OUT_DIR, name), 'wb') as f:
        f.write(mp3)
    meta = {'tracks': [{'file': name, 'title': args.title, 'author': args.author, 'license': args.license, 'url': args.url}]}
    with open(os.path.join(OUT_DIR, 'music.json'), 'w', encoding='utf-8') as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write('\n')
    secs = len(data) / rate
    print(f'OK: assets/music/{name} ({len(mp3) / 1024:.0f} KB, {secs:.1f} s) e assets/music/music.json atualizados.')
    print('Lembre de adicionar a faixa na tabela de Áudio do ASSETS.md.')


if __name__ == '__main__':
    main()
