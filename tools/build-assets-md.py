#!/usr/bin/env python3
"""Gera ASSETS.md a partir das pastas de assets e dos arquivos de créditos.
Uso: python3 tools/build-assets-md.py   (rode sempre que adicionar ou trocar um asset)
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
A = os.path.join(ROOT, 'assets')
KENNEY = 'Kenney Vleugels (Kenney.nl)'
AUTHORS = {'lorc': 'Lorc', 'delapouite': 'Delapouite', 'skoll': 'Skoll', 'sbed': 'Sbed', 'willdabeast': 'Willdabeast', 'guard13007': 'Guard13007'}
ICON_USE = {
    'hero-': 'retrato de herói', 'talent-': 'talento da Árvore de Legado', 'season-': 'tema de temporada / emblema',
    'event-': 'evento relâmpago', 'emblem-': 'emblema do reino',
}
ICON_USE_EXACT = {
    'gold': 'recurso Ouro (HUD, custos, números flutuantes)', 'food': 'recurso Comida', 'wood': 'recurso Madeira', 'stone': 'recurso Pedra',
    'gems': 'recurso Gemas', 'crowns': 'Coroas, Ascensão, aba Legado', 'pop': 'moradores (legado)', 'people': 'moradores e trabalhadores',
    'happiness': 'felicidade (legado)', 'heart': 'felicidade', 'defense': 'defesa', 'raid': 'horda', 'swords': 'hordas, conquista',
    'time': 'tempo, offline', 'build': 'construir, novo reino', 'upgrade': 'melhorar', 'map': 'território, expansão',
    'trophy': 'conquistas, ranking', 'settings': 'opções', 'scroll': 'pergaminho, créditos, crônica', 'castle': 'aba Reino',
    'banner': 'recompensa de estandarte', 'move': 'mover prédio', 'demolish': 'demolir', 'clear': 'limpar terreno', 'close': 'fechar',
    'check': 'confirmado', 'lock': 'bloqueado', 'warning': 'aviso (HUD e mapa)', 'menu': 'menu do jogo', 'speaker': 'volume de efeitos',
    'speaker-off': 'som desligado', 'music': 'volume da música', 'calendar': 'recompensa diária', 'mission': 'missões, tutorial',
    'star': 'passe de temporada, estrelas', 'boost': 'bênção', 'tab-heroes': 'aba Heróis', 'tab-social': 'aba Social',
    'tab-profile': 'aba Perfil', 'stats': 'economia, estatísticas', 'info': 'informações, heróis não descobertos', 'copy': 'copiar código',
    'visit': 'visitar reino', 'greet': 'saudar reino', 'trade': 'troca', 'save': 'save e backups', 'speedup': 'acelerar expedição',
    'cart': 'carroça do mercador (interface)', 'keyboard': 'atalhos de teclado', 'play': 'continuar', 'exit': 'voltar ao menu',
    'expedition': 'expedições', 'sun': 'reservado', 'contrast': 'reservado (alto contraste)', 'font': 'tamanho do texto',
    'motion': 'reservado (movimento)', 'house': 'voltar ao meu reino, conquista',
}
SFX_USE = {
    'click': 'cliques e seleção', 'open': 'abrir menu', 'close': 'fechar janela', 'error': 'ação inválida', 'tab': 'trocar de aba',
    'upgrade': 'melhorar prédio', 'confirm': 'missão, tutorial', 'event': 'evento relâmpago', 'build': 'construir/mover',
    'mine': 'construir pedreira/mina', 'warn': 'aviso de horda', 'coin': 'recompensas, expedição', 'cart': 'carroça do mercador',
    'chop': 'limpar terreno', 'recruit': 'recrutar herói comum/raro', 'expedition': 'iniciar expedição', 'win': 'vitória, expansão',
    'lose': 'derrota em horda', 'tier': 'nível do passe, nova aba', 'achievement': 'conquista', 'legendary': 'herói épico/lendário',
    'ascend': 'Ascensão',
}


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, '/')


def main():
    out = []
    w = out.append
    w('# ASSETS\n')
    w('Todo asset usado ou publicado com o jogo, com onde é usado, fonte, autor, licença e link. **Gerado por `python3 tools/build-assets-md.py`**: rode de novo sempre que mudar algo em `/assets`.\n')
    w('## Licenças\n')
    w('| Licença | O que exige | Onde se aplica |')
    w('|---|---|---|')
    w('| [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Nada (crédito é cortesia, e damos) | Kenney: Medieval RTS, UI Pack, Interface Sounds, RPG Audio, Impact Sounds, Music Jingles |')
    w('| [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Crédito ao autor ("Icons made by {autor}"), link da licença e indicação de mudanças. Atendido na tela de Créditos do jogo e neste arquivo | Ícones de game-icons.net |')
    w('| [SIL OFL 1.1](https://openfontlicense.org/) | Manter o aviso de licença junto da fonte; não vender a fonte isolada | Nunito |')
    w('')
    w('Os arquivos de licença originais estão junto de cada pacote: `assets/sprites/medieval-rts/License.txt`, `assets/ui/kenney-ui-pack/License.txt`, `assets/icons/game-icons/License.txt`, `assets/sfx/License-*.txt`, `assets/fonts/Nunito-OFL.txt`.\n')
    w('## Origem dos downloads\n')
    w('A rede da sessão de desenvolvimento bloqueia kenney.nl, opengameart.org, itch.io, freesound.org e game-icons.net. Por isso:')
    w('- **Kenney**: espelho público [github.com/ETdoFresh/kenney.nl](https://github.com/ETdoFresh/kenney.nl) (ZIPs extraídos, com o `License.txt` original). Como a licença é CC0, a redistribuição é permitida. O [EXECUTAR.md](EXECUTAR.md) explica como conferir com os ZIPs oficiais.')
    w('- **game-icons.net**: repositório oficial [github.com/game-icons/icons](https://github.com/game-icons/icons). **Modificações**: fundo preto removido e cor trocada por `currentColor` (tingida por CSS).')
    w('- **Sons Kenney**: convertidos de OGG para MP3 (96 kbps) para tocar em todos os navegadores. **Modificação**: só conversão de formato.')
    w('- **Nunito**: pacote npm [@fontsource/nunito](https://www.npmjs.com/package/@fontsource/nunito) (arquivos do Google Fonts).')
    w('- **Ícone do app**: composição gerada por `tools/make-icons.py` com dois sprites CC0 do Medieval RTS.\n')

    # Sprites
    w('## Sprites do mapa (Kenney – Medieval RTS, CC0)\n')
    w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    rts = os.path.join(A, 'sprites', 'medieval-rts')
    usage = {
        'Tile': 'terreno: grama 57/58, floresta 42/43/46/47, água 27/28, pedra (montanha) 15/16, plantação da Fazenda 56; demais reservados',
        'Structure': 'prédios (casa 18, serraria 21, pedreira 20, mercado 22, moinho 19 + hélice 13, armazém 9, taverna 23, muralha 2, torre 1, templo 4, estátua 12), carroça do mercador 7, castelo 6 (logo e ícone)',
        'Environment': 'rochas 7/8, rochedo da montanha 9/11, mina de ouro 18, jardim 19, fogueira 20; demais reservados',
        'Unit': 'invasores 8/9/10, aldeões 1/13/19/24; demais reservados',
    }
    for d in ['Tile', 'Structure', 'Environment', 'Unit']:
        files = sorted(f for f in os.listdir(os.path.join(rts, d)) if f.endswith('.png'))
        w(f'| `assets/sprites/medieval-rts/{d}/` ({len(files)} PNG, 128 px: `{files[0]}` a `{files[-1]}`) | {usage[d]} | Kenney – Medieval RTS | {KENNEY} | CC0 1.0 | [kenney.nl/assets/medieval-rts](https://kenney.nl/assets/medieval-rts) |')
    w('')

    # UI
    w('## Interface (Kenney – UI Pack, CC0)\n')
    w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    ui_use = {'grey_panel': 'só na prévia de estilo (estilo.html); no jogo os painéis são CSS', 'yellow_button00': 'botão principal', 'yellow_button01': 'botão principal pressionado',
              'grey_button00': 'botão padrão', 'grey_button01': 'botão padrão pressionado', 'green_button00': 'botão positivo',
              'green_button01': 'botão positivo pressionado', 'red_button00': 'botão de perigo', 'red_button01': 'botão de perigo pressionado',
              'grey_box': 'caixa de seleção vazia', 'yellow_boxCheckmark': 'caixa de seleção marcada'}
    for f in sorted(os.listdir(os.path.join(A, 'ui', 'kenney-ui-pack'))):
        if not f.endswith('.png'):
            continue
        w(f'| `assets/ui/kenney-ui-pack/{f}` | {ui_use.get(f[:-4], "reservado")} | Kenney – UI Pack | {KENNEY} | CC0 1.0 | [kenney.nl/assets/ui-pack](https://kenney.nl/assets/ui-pack) |')
    w('')

    # Ícones
    creds = json.load(open(os.path.join(A, 'icons', 'game-icons', 'credits.json'), encoding='utf-8'))
    w(f'## Ícones (game-icons.net, CC BY 3.0) — {len(creds)} arquivos\n')
    w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    for name in sorted(creds):
        c = creds[name]
        use = ICON_USE_EXACT.get(name) or next((v for k, v in ICON_USE.items() if name.startswith(k)), 'interface')
        src = c['source'].split('/master/')[1]
        w(f'| `assets/icons/game-icons/{name}.svg` | {use} | game-icons.net (`{src}`) | {AUTHORS.get(c["author"], c["author"])} | CC BY 3.0 | [{src}]({c["page"]}) |')
    w('')

    # Som
    sfx = json.load(open(os.path.join(A, 'sfx', 'credits.json'), encoding='utf-8'))
    w('## Efeitos sonoros (Kenney, CC0)\n')
    w('| Arquivo | Onde é usado | Fonte (arquivo original) | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    links = {'Interface Sounds': 'interface-sounds', 'RPG Audio': 'rpg-audio', 'Impact Sounds': 'impact-sounds', 'Music Jingles': 'music-jingles'}
    for name in sorted(sfx):
        c = sfx[name]
        pack = c['pack'].replace('Kenney – ', '')
        w(f'| `assets/sfx/{name}.mp3` | {SFX_USE.get(name, "efeito")} | {c["pack"]} (`{c["file"]}`) | {KENNEY} | CC0 1.0 | [kenney.nl/assets/{links[pack]}](https://kenney.nl/assets/{links[pack]}) |')
    w('')

    # Música
    w('## Música\n')
    music = json.load(open(os.path.join(A, 'music', 'music.json'), encoding='utf-8'))
    if music.get('tracks'):
        w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
        w('|---|---|---|---|---|---|')
        for t in music['tracks']:
            w(f'| `assets/music/{t["file"]}` | música ambiente em loop | {t["title"]} | {t["author"]} | {t["license"]} | [{t["url"]}]({t["url"]}) |')
    else:
        w('Nenhuma faixa instalada ainda. Recomendação e passo a passo: [EXECUTAR.md](EXECUTAR.md), seção "Música". O jogo funciona sem música.')
    w('')

    # Fontes e ícone do app
    w('## Fontes\n')
    w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    for f in sorted(os.listdir(os.path.join(A, 'fonts'))):
        if f.endswith('.woff2'):
            w(f'| `assets/fonts/{f}` | todo o texto (400 corpo, 800 títulos e números) | Fontsource / Google Fonts | The Nunito Project Authors | SIL OFL 1.1 | [github.com/googlefonts/nunito](https://github.com/googlefonts/nunito) |')
    w('')
    w('## Ícone do app e favicon\n')
    w('| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |')
    w('|---|---|---|---|---|---|')
    for f in sorted(os.listdir(os.path.join(A, 'icons', 'app'))):
        w(f'| `assets/icons/app/{f}` | favicon, ícone de tela inicial, manifest | composição de `medievalTile_57` + `medievalStructure_06` (Kenney – Medieval RTS) via `tools/make-icons.py` | {KENNEY} | CC0 1.0 | [kenney.nl/assets/medieval-rts](https://kenney.nl/assets/medieval-rts) |')
    w('')
    with open(os.path.join(ROOT, 'ASSETS.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(out))
    print('ASSETS.md gerado.')


if __name__ == '__main__':
    main()
