# ASSETS

Todo asset usado ou publicado com o jogo, com fonte, autor e licença. Mantenha esta tabela atualizada a cada arquivo novo em `/assets`.

## Licenças em resumo

| Licença | Exige | Pacotes |
|---|---|---|
| [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Nada (crédito é cortesia) | Kenney Medieval RTS, Kenney UI Pack |
| [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | **Crédito ao autor** e link para a licença, num lugar visível (tela de créditos + este arquivo) | game-icons.net (Lorc, Delapouite, Skoll) |
| [SIL OFL 1.1](https://openfontlicense.org/) | Manter o aviso de licença junto da fonte; não vender a fonte sozinha | Nunito |

Arquivos de licença originais estão junto de cada pacote: `assets/sprites/medieval-rts/License.txt`, `assets/ui/kenney-ui-pack/License.txt`, `assets/icons/game-icons/License.txt`, `assets/fonts/Nunito-OFL.txt`.

## Origem dos downloads

A rede da sessão de desenvolvimento bloqueia kenney.nl e game-icons.net, então os arquivos vieram de:
- **Kenney**: espelho público [github.com/ETdoFresh/kenney.nl](https://github.com/ETdoFresh/kenney.nl), que contém os ZIPs extraídos com o `License.txt` original. Páginas oficiais: [Medieval RTS](https://kenney.nl/assets/medieval-rts), [UI Pack](https://kenney.nl/assets/ui-pack). O EXECUTAR.md explica como conferir.
- **game-icons.net**: repositório oficial [github.com/game-icons/icons](https://github.com/game-icons/icons). O fundo preto de cada SVG foi removido e a cor trocada por `currentColor` para tingir via CSS (modificação permitida pela CC BY, e declarada aqui).
- **Nunito**: pacote npm [@fontsource/nunito](https://www.npmjs.com/package/@fontsource/nunito) 5.x (arquivos do Google Fonts).

## Sprites e interface (Kenney, CC0)

| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |
|---|---|---|---|---|---|
| `assets/sprites/medieval-rts/Tile/*.png` (58, 128 px) | Terreno do mapa (grama 57/58, floresta 42/43/46/47, água 27/28, pedra 15/16, plantação 56) | Kenney – Medieval RTS | Kenney Vleugels | CC0 | [kenney.nl/assets/medieval-rts](https://kenney.nl/assets/medieval-rts) |
| `assets/sprites/medieval-rts/Structure/*.png` (23) | Prédios (mapeamento em `src/ui/sprites.js`) | Kenney – Medieval RTS | Kenney Vleugels | CC0 | idem |
| `assets/sprites/medieval-rts/Environment/*.png` (21) | Rochas, minério, arbustos, fogueira | Kenney – Medieval RTS | Kenney Vleugels | CC0 | idem |
| `assets/sprites/medieval-rts/Unit/*.png` (24) | Reservado (aldeões animados, Fase 3) | Kenney – Medieval RTS | Kenney Vleugels | CC0 | idem |
| `assets/ui/kenney-ui-pack/*.png` (9) | Painéis e botões | Kenney – UI Pack | Kenney Vleugels | CC0 | [kenney.nl/assets/ui-pack](https://kenney.nl/assets/ui-pack) |

## Ícones (game-icons.net, CC BY 3.0)

| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |
|---|---|---|---|---|---|
| `assets/icons/game-icons/gold.svg` | ícone de interface (gold) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/two-coins.html](https://game-icons.net/1x1/delapouite/two-coins.html) |
| `assets/icons/game-icons/food.svg` | ícone de interface (food) | game-icons.net | Lorc | CC BY 3.0 | [lorc/wheat.html](https://game-icons.net/1x1/lorc/wheat.html) |
| `assets/icons/game-icons/wood.svg` | ícone de interface (wood) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/wood-pile.html](https://game-icons.net/1x1/delapouite/wood-pile.html) |
| `assets/icons/game-icons/stone.svg` | ícone de interface (stone) | game-icons.net | Lorc | CC BY 3.0 | [lorc/stone-block.html](https://game-icons.net/1x1/lorc/stone-block.html) |
| `assets/icons/game-icons/gems.svg` | ícone de interface (gems) | game-icons.net | Lorc | CC BY 3.0 | [lorc/cut-diamond.html](https://game-icons.net/1x1/lorc/cut-diamond.html) |
| `assets/icons/game-icons/crowns.svg` | ícone de interface (crowns) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/imperial-crown.html](https://game-icons.net/1x1/delapouite/imperial-crown.html) |
| `assets/icons/game-icons/pop.svg` | ícone de interface (pop) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/person.html](https://game-icons.net/1x1/delapouite/person.html) |
| `assets/icons/game-icons/happiness.svg` | ícone de interface (happiness) | game-icons.net | Skoll | CC BY 3.0 | [skoll/hearts.html](https://game-icons.net/1x1/skoll/hearts.html) |
| `assets/icons/game-icons/defense.svg` | ícone de interface (defense) | game-icons.net | Lorc | CC BY 3.0 | [lorc/checked-shield.html](https://game-icons.net/1x1/lorc/checked-shield.html) |
| `assets/icons/game-icons/raid.svg` | ícone de interface (raid) | game-icons.net | Lorc | CC BY 3.0 | [lorc/crossed-swords.html](https://game-icons.net/1x1/lorc/crossed-swords.html) |
| `assets/icons/game-icons/time.svg` | ícone de interface (time) | game-icons.net | Lorc | CC BY 3.0 | [lorc/hourglass.html](https://game-icons.net/1x1/lorc/hourglass.html) |
| `assets/icons/game-icons/build.svg` | ícone de interface (build) | game-icons.net | Lorc | CC BY 3.0 | [lorc/hammer-nails.html](https://game-icons.net/1x1/lorc/hammer-nails.html) |
| `assets/icons/game-icons/upgrade.svg` | ícone de interface (upgrade) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/upgrade.html](https://game-icons.net/1x1/delapouite/upgrade.html) |
| `assets/icons/game-icons/map.svg` | ícone de interface (map) | game-icons.net | Lorc | CC BY 3.0 | [lorc/treasure-map.html](https://game-icons.net/1x1/lorc/treasure-map.html) |
| `assets/icons/game-icons/trophy.svg` | ícone de interface (trophy) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/trophy-cup.html](https://game-icons.net/1x1/delapouite/trophy-cup.html) |
| `assets/icons/game-icons/settings.svg` | ícone de interface (settings) | game-icons.net | Lorc | CC BY 3.0 | [lorc/gears.html](https://game-icons.net/1x1/lorc/gears.html) |
| `assets/icons/game-icons/scroll.svg` | ícone de interface (scroll) | game-icons.net | Lorc | CC BY 3.0 | [lorc/scroll-unfurled.html](https://game-icons.net/1x1/lorc/scroll-unfurled.html) |
| `assets/icons/game-icons/castle.svg` | ícone de interface (castle) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/castle.html](https://game-icons.net/1x1/delapouite/castle.html) |
| `assets/icons/game-icons/hero-farmer.svg` | retrato de herói (hero-farmer) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/farmer.html](https://game-icons.net/1x1/delapouite/farmer.html) |
| `assets/icons/game-icons/hero-archer.svg` | retrato de herói (hero-archer) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/archer.html](https://game-icons.net/1x1/delapouite/archer.html) |
| `assets/icons/game-icons/hero-wizard.svg` | retrato de herói (hero-wizard) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/wizard-face.html](https://game-icons.net/1x1/delapouite/wizard-face.html) |
| `assets/icons/game-icons/hero-dwarf.svg` | retrato de herói (hero-dwarf) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/dwarf-face.html](https://game-icons.net/1x1/delapouite/dwarf-face.html) |
| `assets/icons/game-icons/hero-elf.svg` | retrato de herói (hero-elf) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/woman-elf-face.html](https://game-icons.net/1x1/delapouite/woman-elf-face.html) |
| `assets/icons/game-icons/hero-dragon.svg` | retrato de herói (hero-dragon) | game-icons.net | Lorc | CC BY 3.0 | [lorc/dragon-head.html](https://game-icons.net/1x1/lorc/dragon-head.html) |
| `assets/icons/game-icons/hero-queen.svg` | retrato de herói (hero-queen) | game-icons.net | Lorc | CC BY 3.0 | [lorc/queen-crown.html](https://game-icons.net/1x1/lorc/queen-crown.html) |
| `assets/icons/game-icons/hero-guard.svg` | retrato de herói (hero-guard) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/guards.html](https://game-icons.net/1x1/delapouite/guards.html) |
| `assets/icons/game-icons/hero-explorer.svg` | retrato de herói (hero-explorer) | game-icons.net | Lorc | CC BY 3.0 | [lorc/compass.html](https://game-icons.net/1x1/lorc/compass.html) |
| `assets/icons/game-icons/hero-bard.svg` | retrato de herói (hero-bard) | game-icons.net | Delapouite | CC BY 3.0 | [delapouite/musical-notes.html](https://game-icons.net/1x1/delapouite/musical-notes.html) |
| `assets/icons/game-icons/hero-clock.svg` | retrato de herói (hero-clock) | game-icons.net | Skoll | CC BY 3.0 | [skoll/pocket-watch.html](https://game-icons.net/1x1/skoll/pocket-watch.html) |

## Fontes

| Arquivo | Onde é usado | Fonte | Autor | Licença | Link |
|---|---|---|---|---|---|
| `assets/fonts/nunito-latin-400-normal.woff2`, `nunito-latin-ext-400-normal.woff2`, `nunito-latin-800-normal.woff2` | Todo o texto | Fontsource / Google Fonts | The Nunito Project Authors | SIL OFL 1.1 | [github.com/googlefonts/nunito](https://github.com/googlefonts/nunito) |

## Áudio

Ainda nenhum arquivo (Fase 3: Kenney Interface Sounds, RPG Audio, Impact Sounds, Music Jingles, CC0; música RandomMind, CC0, download manual).
