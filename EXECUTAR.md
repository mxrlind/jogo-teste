# EXECUTAR — o que depende de você

Coisas que não consegui fazer daqui: a rede da sessão de desenvolvimento bloqueia kenney.nl, opengameart.org, itch.io, freesound.org e game-icons.net, e conferir uma licença é decisão de uma pessoa. Siga na ordem. Só os passos 1 e 2 são necessários para jogar; o resto melhora o jogo ou dá mais segurança jurídica.

Comandos para terminal Linux, macOS ou Git Bash no Windows.

---

## 1. Conferir se a versão nova está no ar

1. Abra https://github.com/mxrlind/jogo-teste/actions e veja a execução mais recente do fluxo **"Publicar no GitHub Pages"**. Precisa estar com o ícone verde. Se estiver amarela, espere 1–2 minutos e recarregue.
2. Se estiver vermelha, clique nela, depois no job que falhou, e copie as últimas linhas do log para mim.
3. Abra https://mxrlind.github.io/jogo-teste/. Você deve ver a **tela de carregamento** e depois o **menu principal** com o mapa ao fundo.

## 2. Se aparecer a versão antiga (com emoji)

O jogo funciona offline, então o navegador pode ter guardado a versão anterior.

1. **PC**: com o jogo aberto, aperte `Ctrl + Shift + R` (no Mac, `Cmd + Shift + R`).
2. Se continuar antigo: aperte `F12`, abra a aba **Application** (no Firefox, **Armazenamento**), clique em **Service workers** → **Unregister**, e recarregue a página.
3. **Celular**: feche todas as abas do jogo, abra de novo e espere uns segundos. Se instalou como app, feche o app e abra de novo duas vezes.

O seu save **não se perde** nesse processo: ele fica no `localStorage`, que é separado do cache, e é migrado automaticamente para o formato novo.

## 3. Instalar a música ambiente (recomendado, 10 minutos)

O jogo já toca uma música em loop se ela existir em `assets/music/`, e os créditos mostram a atribuição sozinhos. Não baixei nenhuma faixa porque não consegui abrir as páginas para confirmar a licença.

**Sugestão**: "Medieval: Minstrel Dance", de RandomMind, no OpenGameArt. Qualquer outra faixa serve, desde que a licença permita publicar o jogo (CC0, CC BY 3.0 ou CC BY 4.0; **evite** CC BY-NC, CC BY-ND e "uso pessoal").

1. Abra https://opengameart.org/content/medieval-minstrel-dance
2. Na coluna da direita, em **License(s)**, confira a licença. Se for diferente das permitidas acima, escolha outra faixa (busca: https://opengameart.org/art-search-advanced?field_art_type_tid%5B%5D=12 e filtre por licença).
3. Baixe o arquivo (WAV, OGG, FLAC ou MP3).
4. Clone o repositório, se ainda não tiver:
   ```bash
   git clone https://github.com/mxrlind/jogo-teste.git
   cd jogo-teste
   ```
5. Instale as bibliotecas de conversão (Python 3.9 ou mais novo):
   ```bash
   pip install soundfile lameenc numpy
   ```
6. Converta e registre a faixa. Troque o caminho e, se escolheu outra faixa, título, autor, licença e link **exatamente como estão na página**:
   ```bash
   python3 tools/prepare-music.py ~/Downloads/NOME-DO-ARQUIVO.wav \
     --title "Medieval: Minstrel Dance" \
     --author "RandomMind" \
     --license "CC0" \
     --url "https://opengameart.org/content/medieval-minstrel-dance"
   ```
   Isso cria um MP3 em `assets/music/` e atualiza `assets/music/music.json`.
7. Atualize o registro de assets:
   ```bash
   python3 tools/build-assets-md.py
   ```
8. Teste: `npm start`, abra http://localhost:8080, clique em **Continuar** e ouça. Em **Opções** o volume da música deve funcionar.
9. Publique:
   ```bash
   git add assets/music ASSETS.md
   git commit -m "Adiciona música ambiente"
   git push origin main
   ```
10. Repita o passo 1 para ver no ar.

## 4. Conferir os links da Kenney (5 minutos)

O `ASSETS.md` aponta para páginas no formato `https://kenney.nl/assets/<nome>`. Não consegui abrir o site para confirmar cada endereço. Abra um por um:

1. https://kenney.nl/assets/medieval-rts
2. https://kenney.nl/assets/ui-pack
3. https://kenney.nl/assets/interface-sounds
4. https://kenney.nl/assets/rpg-audio
5. https://kenney.nl/assets/impact-sounds
6. https://kenney.nl/assets/music-jingles

Se algum der erro 404 ou abrir outro pacote, me mande o endereço certo ou corrija em `tools/build-assets-md.py`, rode `python3 tools/build-assets-md.py` e faça commit.

## 5. Conferir os arquivos da Kenney com os ZIPs oficiais (opcional)

Os arquivos vieram do espelho público https://github.com/ETdoFresh/kenney.nl, que contém os ZIPs originais extraídos com o `License.txt` de cada pacote. Como tudo é CC0, a redistribuição é permitida de qualquer jeito; esta conferência só garante que o espelho não alterou nada.

1. Na página do passo 4.1 (Medieval RTS), clique em **Download** (pode pular a doação: "Continue without donating") e extraia o ZIP, por exemplo em `~/Downloads/kenney_medieval-rts/`.
2. Na pasta do repositório, rode:
   ```bash
   ZIP=~/Downloads/kenney_medieval-rts
   for f in assets/sprites/medieval-rts/*/*.png; do
     o=$(find "$ZIP" -name "$(basename "$f")" -path "*128*" | head -1)
     [ -z "$o" ] && o=$(find "$ZIP" -name "$(basename "$f")" | head -1)
     if [ -z "$o" ]; then echo "SEM PAR: $f";
     elif cmp -s "$f" "$o"; then :; else echo "DIFERENTE: $f"; fi
   done; echo "fim"
   ```
   Se aparecer só `fim`, os 126 sprites são idênticos aos oficiais.
3. Para o UI Pack, troque `ZIP` pela pasta extraída e o padrão por `assets/ui/kenney-ui-pack/*.png`.
4. Os efeitos sonoros **não** batem byte a byte: foram convertidos de OGG para MP3 para tocar em todos os navegadores. A origem de cada um (pacote e nome do arquivo original) está em `assets/sfx/credits.json` e no `ASSETS.md`.

## 6. Ícones do game-icons.net (nada a fazer)

Os 104 ícones vêm do repositório oficial (https://github.com/game-icons/icons), licença CC BY 3.0. A atribuição exigida (autor de cada ícone + link da licença) já está no `ASSETS.md` e na tela **Créditos** do jogo. Se adicionar ícones novos, rode `python3 tools/build-assets-md.py` de novo.

## 7. Rodar e testar no seu computador

Requer Node 18 ou mais novo (https://nodejs.org).

```bash
npm start                          # abre em http://localhost:8080
npm test                           # 36 testes do motor + varredura de emoji
npm run simulate -- 8 1 --ascend   # bot joga 8 horas de jogo com a semente 1
```

Não há `npm install`: o jogo não tem dependências.

## 8. Ferramentas de depuração (opcional)

Abra o jogo com `?debug` no fim do endereço (por exemplo http://localhost:8080/?debug), aperte `F12` e use o console:

- `reino.ui.game.state` mostra o estado inteiro do jogo (o objeto `reino` só existe no modo `?debug`).
- Exportar e importar save: **Esc → Save e backups**.
- Se o save estragar, o jogo guarda a cópia danificada em `localStorage['reino-de-bolso:save:corrompido']` e carrega o último backup. Mande essa cópia para mim se acontecer.
