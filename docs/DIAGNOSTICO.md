# Diagnóstico — Reino de Bolso (Fase 1 + Fase 2)

Data: 05/10/2026 · Base: `main` em `fe7e784` + correções pequenas deste branch.
Escopo lido: todos os 22 arquivos do jogo (`index.html`, `styles.css`, `src/**`), testes e ferramentas.

---

## 1. Resumo em 6 linhas

1. O motor está correto: 27 testes passando, economia pura e testável, save versionado.
2. **O jogo viola a regra nº 1: 309 emojis** nos arquivos do jogo. Todo o visual (mapa, HUD, ícones, favicon) é feito de emoji.
3. Não existe **nenhum asset real**: sem sprites, sem áudio (só bipes sintetizados), fontes vindas de CDN externo.
4. Havia **4 bugs de experiência**, já corrigidos neste branch: clique perdido, resumo offline sumindo, save corrompido sendo apagado e missão de visita completável com cliques repetidos.
5. O core loop se sustenta na primeira hora (quebra-cabeça de adjacência), mas **perde força depois do mapa cheio**. Além disso, o jogo mostra sistemas demais de uma vez no início.
6. Faltam itens de "jogo completo": menu principal, créditos com licenças, música, volume separado, acessibilidade (movimento reduzido, tamanho de fonte, remapeamento), ícone do app e tela de carregamento.

## 2. Varredura de emoji (regra nº 1)

Ferramenta nova: `node tools/emoji-scan.js [--all]`. Ela detecta `\p{Extended_Pictographic}`, `\p{Emoji_Presentation}`, seletores de variação U+FE0E/U+FE0F, ZWJ U+200D, keycap U+20E3, indicadores regionais, tons de pele e tags. Sai com código 1 se achar algo nos arquivos do jogo.

Resultado atual (antes da Fase 3):

```
Arquivos do jogo varridos: 22
Ocorrências de emoji no jogo: 309
  index.html: 1                 (favicon)
  src/core/game.js: 20          (tutorial, logs, toasts)
  src/data/achievements.js: 31
  src/data/buildings.js: 26     (ícones de prédios e recursos)
  src/data/cosmetics.js: 15     (emblemas)
  src/data/events.js: 6
  src/data/heroes.js: 21
  src/data/seasons.js: 7
  src/data/talents.js: 11
  src/ui/app.js: 166            (HUD, abas, botões, modais)
  src/ui/render.js: 5           (aviso, baú, terrenos)
[informativo] docs/ferramentas: 258 ocorrências (README e docs)
```

Plano: a Fase 3 troca cada ícone por um asset real (seção 7) e o teste `npm test` passa a rodar a varredura, para impedir regressão.

## 3. Bugs

| # | Severidade | Arquivo:linha | Problema | Status |
|---|---|---|---|---|
| B1 | Alta (UX) | `src/ui/app.js:79`, `:357`, `:424`, `:438`, `:442` | Paleta, abas, painel lateral e painel do tile eram recriados (`innerHTML`) a cada 1 s. Se a troca acontecia entre o `pointerdown` e o `pointerup`, o navegador descartava o clique, e o botão "não respondia" de vez em quando. | **Corrigido**: não re-renderiza com o ponteiro pressionado (`pointerHeld`, `app.js:60`) |
| B2 | Alta | `src/ui/app.js:68` (tick → resumo offline) e `:89` (`setTimeout(showDaily)`) | Ao abrir o jogo depois de um tempo fora, o modal de recompensa diária **substituía** o resumo "Enquanto você esteve fora", que o jogador nunca via. | **Corrigido**: fila de modais (`app.js:719`) |
| B3 | Alta (save) | `src/ui/app.js:42-48` | Save ilegível → jogo novo → autosave em 10 s **sobrescrevia o save original**. Perda total de progresso. | **Corrigido**: cópia em `reino-de-bolso:save:corrompido` antes de recomeçar (verificado no navegador) |
| B4 | Média | `src/ui/app.js:682` (antes: `stats.visits++` a cada visita) | Clicar em "Visitar" 3× completava a missão "Visite 3 reinos". Saudar contava a visita de novo. | **Corrigido**: `Game.recordVisit` conta 1× por reino por dia (`game.js:638`) + teste |
| B5 | Baixa | `src/core/game.js:123` | Uma ausência de 30–60 s sumia com o baú e empurrava a próxima invasão. | **Corrigido**: só para ausências ≥ 1 min + teste |
| B6 | Baixa | `src/ui/sfx.js:25` | Sons tocados antes de qualquer gesto criavam um `AudioContext` bloqueado pela política de autoplay (aviso no console). | **Corrigido**: áudio só depois do 1º gesto |
| B7 | Média | `src/core/game.js:60` | Abas em segundo plano têm `setInterval` limitado pelo navegador. Com mais de 30 s sem tick, a volta conta como "offline" a 60%, então o jogador perde 40% só por trocar de aba. | Pendente (Fase 3: aba oculta deve simular a 100% até o limite) |
| B8 | Baixa | `src/core/rng.js:36`, `src/core/game.js:534` | Dia diário pela data local; `now - 86400000` erra na troca de horário de verão. A doc dizia que as missões eram "iguais para todos", mas isso só vale no mesmo fuso. | Pendente (calcular "ontem" pela data, corrigir a doc) |
| B9 | Baixa | `src/core/economy.js:136` | A felicidade de tavernas e templos ignora a falta de trabalhadores, e só a produção é afetada. É inconsistente. | Pendente (decisão de design) |
| B10 | Baixa | `src/ui/app.js` (abas) | Tooltips (`title=`) são a única explicação de vários elementos, e não existem no toque. | Pendente (Fase 3) |
| B11 | Baixa | `index.html:10-12` | As fontes vêm do Google Fonts. Offline ou em rede restrita, gera erro no console e troca a fonte. | Pendente (fontes locais em `/assets/fonts`) |

## 4. Performance

| Arquivo:linha | Problema | Proposta |
|---|---|---|
| `src/ui/render.js:108-159` | Todo frame (60 fps) redesenha os 144 tiles e chama `fillText` com emoji, que é caro (sobretudo em Android fraco) | Pré-renderizar o terreno num canvas fora da tela; redesenhar só quando o mapa muda; sprites com `drawImage` |
| `src/ui/app.js:315` | O HUD é reconstruído por `innerHTML` a cada 250 ms (layout + GC) | Montar o DOM uma vez e atualizar só o `textContent` e larguras |
| `src/ui/app.js:79` | Painel lateral inteiro a cada 1 s | Re-renderizar por seção ou só quando os dados mudam |
| `src/ui/render.js:80` (loop) | rAF desenha mesmo sem mudança | Manter o rAF (há animações), mas com camada estática em cache |

Sem vazamentos aparentes: listas limitadas (`log` ≤ 50, `fx` filtrado, rivais = 9). Vou confirmar com teste de sessão longa (heap) na Fase 4.

## 5. Segurança

- XSS: textos do jogador e de códigos de reino passam por `esc()` (16 usos em `app.js`), e `decodeKingdom` valida a grade e limita os textos. **OK.**
- Ponto de atenção: `confirmModal(html)` recebe HTML pronto; hoje só com texto fixo do jogo. Manter assim.
- Save local editável é aceitável (jogo single-player). O ranking futuro precisará de validação no servidor (já documentado).

## 6. Dívida técnica

| Item | Onde | Impacto |
|---|---|---|
| UI por `innerHTML` em template strings gigantes | `src/ui/app.js` (793 linhas) | Difícil de manter; motivo do B1 |
| Ícones embutidos nos dados (`icon: '<emoji>'`) | `src/data/*.js` | Mistura conteúdo com apresentação; impede trocar por assets |
| Sem pré-carregamento de assets | — | Necessário quando houver sprites e áudio |
| Configurações mínimas no save (`sound`, `particles`) | `src/core/state.js` | Volume, acessibilidade e atalhos exigem o save v2 (com migração) |
| Docs longos e repetitivos | antigo `docs/GDD.md` (agora `docs/ESPECIFICACAO-SISTEMAS.md`), `README.md` | Substituídos por um GDD curto (este pedido) |

## 7. Assets — pesquisa e escolha

### 7.1 Restrição real deste ambiente
A rede desta sessão **bloqueia** kenney.nl, opengameart.org, itch.io, freesound.org, game-icons.net, fonts.google.com e wikipedia. Funcionam o GitHub (git clone + raw) e o npm. Por isso:
- **Kenney (CC0)**: uso o espelho público [ETdoFresh/kenney.nl](https://github.com/ETdoFresh/kenney.nl), que contém os pacotes extraídos com o `License.txt` original de cada um. Como CC0 permite redistribuição, a origem é legítima, e o EXECUTAR.md explica como conferir os mesmos arquivos em kenney.nl.
- **game-icons.net (CC BY 3.0)**: uso o repositório oficial [game-icons/icons](https://github.com/game-icons/icons), com a pasta de cada autor.
- **Música em loop**: as melhores opções CC0 (RandomMind, no OpenGameArt) só estão no OpenGameArt, que está bloqueado aqui. Vai para o EXECUTAR.md (você baixa um arquivo). O jogo funciona sem música até lá.

### 7.2 Comparação para o mundo (mapa e prédios)

| Opção | Estilo | Licença | Cobertura do jogo | Prós | Contras | Veredito |
|---|---|---|---|---|---|---|
| **Kenney – Medieval RTS** | Vetor plano, top-down, 128 px + SVG | CC0 | Terreno (grama, areia, terra, pedra, água, neve), florestas, rochas, minério, casas, moinho com hélice animável, mercado, templo, castelo, torre, muralha, estátua, fogueira, unidades | Um tile = um prédio (encaixa na grade 12×12); vetor nítido em qualquer DPI; mesmo autor do UI Pack e das fontes | Não tem fonte d'água nem armazém "óbvio"; poucas variações por nível | **Escolhido** |
| Kenney – RPG Pack | Top-down mais detalhado | CC0 | Terreno e props; prédios grandes, de várias células | Bonito | Prédios não cabem em 1 tile; teria que montar | Não |
| Kenney – Roguelike Pack | Pixel 16 px | CC0 | Paredes e telhados modulares | Enorme | Exige montar cada prédio; pixel não combina com o UI vetorial | Não |
| Kenney – Tiny Town | Pixel 16 px | CC0 | Bom para cidade | Coeso | Não está no espelho, e o site está bloqueado | Não (fica como alternativa no ROADMAP) |
| Kenney – Medieval Town Base | 3D isométrico | CC0 | Prédios 3D | — | 3D, exigiria renderizar | Não |

Mapeamento proposto (Medieval RTS): casa = Structure_18/17 · fazenda = tile de plantação · serraria = Structure_21 · pedreira = Structure_20 · mercado = Structure_22 · moinho = Structure_19 + hélice 13/14/15 (animada) · armazém = Structure_09 · taverna = Structure_23 · muralha = Structure_02 · torre = Structure_01 · templo = Structure_04 · mina = Environment_17/18 (minério) · estátua = Structure_12 · jardim = Environment_19 · **fonte → "Fogueira" (Environment_20)**, porque o pacote não tem fonte d'água. Essa troca de id exige migração do save (v1 → v2).

### 7.3 Interface, ícones, fontes e áudio

| Uso | Escolha | Licença | Por quê |
|---|---|---|---|
| Painéis e botões | Kenney **UI Pack** (`uipack_fixed`) | CC0 | Mesmo autor e mesma linguagem plana do Medieval RTS |
| Ícones de recurso, ação e heróis | **game-icons.net** (SVG, cor única, tingidos pela paleta) | CC BY 3.0 (exige crédito por autor) | O Medieval RTS não tem ícones de interface. game-icons cobre todos os temas (trigo, tora, bloco de pedra, moedas, gemas, coroa, rostos de herói) com um traço uniforme. **Justificativa da mistura**: ícone de interface é uma camada separada do mundo, em silhueta chapada, com a mesma paleta, e não aparece dentro do mapa |
| Fonte de títulos e números | **Kenney Future** (`kenney_fontpackage`) | CC0 | Mesmo autor; conferi que tem todos os acentos do português (ÁÂÃÀÉÊÍÓÔÕÚÇ) |
| Fonte de texto corrido | **Nunito** (via `@fontsource/nunito`, npm) | SIL OFL 1.1 | Legível em tamanho pequeno; arredondada como o estilo |
| Efeitos sonoros | Kenney **Interface Sounds**, **RPG Audio**, **Impact Sounds**, **Music Jingles** | CC0 | Cliques, moedas, construção, vitória e derrota, num só "timbre" |
| Música (loop) | RandomMind, "Medieval: Minstrel Dance" (versão loop) — **download manual** | CC0 (segundo a página do OpenGameArt; conferir no download) | Clima medieval leve; há versão loop |

Licenças conferidas nos arquivos: `kenney_medievalrtspack/License.txt` ("License (Creative Commons Zero, CC0) … You may use these assets in personal and commercial projects") e `game-icons/license.txt` ("Icons provided under the Creative Commons 3.0 BY or CC0 if mentioned below", com a lista de autores).

## 8. Pesquisa do gênero

O gênero é **idle/incremental + construção de base com quebra-cabeça de posicionamento**. As 6 referências mais relevantes:

| Jogo | O que a comunidade e as análises apontam como essencial | O que o Reino de Bolso tem | Fonte |
|---|---|---|---|
| **Cookie Clicker** | Recompensa variável ("golden cookie") que premia atenção; crescimento exponencial visível | Baú do mercador (equivalente), números grandes | [Wikipedia: Incremental game](https://en.wikipedia.org/wiki/Incremental_game) |
| **AdVenture Capitalist** | Gerentes que automatizam; ganho offline; prestígio ("angel investors", +2% cada) com a decisão de **quando** resetar | Produção automática, offline, Ascensão. **Falta** mostrar quando vale ascender | [Wikipedia](https://en.wikipedia.org/wiki/AdVenture_Capitalist); [Pecorella, "The Math of Idle Games" I](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i), [II](https://www.gamedeveloper.com/game-platforms/the-math-of-idle-games-part-ii) |
| **Kittens Game** | Profundidade por camadas; **armazenamento como gargalo estratégico**; sem anúncios nem microtransações | Armazém × nível² e limites | [Steam](https://store.steampowered.com/app/1097410/Kittens_Game/) |
| **Melvor Idle** | Offline simulado "tick a tick" (até 24 h); estratégia de longo prazo em vez de cliques | Offline em blocos (até 4 h, ampliável) | [GamingOnLinux](https://www.gamingonlinux.com/2021/06/melvor-idle-is-probably-one-of-the-best-idle-games-around/page=1/); [ModDB](https://www.moddb.com/games/melvor-idle/features/melvor-idle-surpasses-1-million-mod-downloads-powered-by-modio) |
| **Islanders** | Pontuação por **proximidade**, mostrada ao vivo enquanto você arrasta o prédio; regras simples que se sobrepõem e viram um quebra-cabeça | Prévia ao vivo de adjacência (núcleo do jogo) | [Wikipedia](https://en.wikipedia.org/wiki/Islanders_(video_game)); [Nintendo World Report](https://www.nintendoworldreport.com/review/58076) |
| **Clash of Clans** | Loop coletar → construir/treinar → batalhar; **progresso visível a cada retorno**; layout da base importa na defesa | Coletar → construir → hordas. **Falta** o layout influir na defesa | [Deconstructor of Fun](https://www.deconstructoroffun.com/blog//2012/09/clash-of-clans-winning-formula.html) |

Complemento: **Dorfromantik** (encaixe perfeito recompensado com mais peças; missões opcionais que prolongam a partida) — [Screenrex](https://screenrex.com/dorfromantik-review/), [guia](https://gamepretty.com/dorfromantik-beginners-guide-quests-rewards-tile-placement/).

**Princípios recorrentes nas fontes**
1. Custos crescem exponencialmente; produção cresce linear ou polinomialmente; o prestígio rompe a parede (Pecorella).
2. Equilíbrio entre ativo e passivo, sem "paredes" que só passam com espera ou dinheiro.
3. Offline honesto e explicado.
4. Cada retorno precisa mostrar progresso (Clash of Clans).
5. Transparência: o jogador vê o efeito da decisão **antes** de confirmar (Islanders).
6. Reclamações comuns da comunidade: interface poluída, árvores de melhoria sem escolhas reais, conteúdo que acaba depois do "máximo", falta de surpresa ([resumos de reviews da Steam, Vaporlens](https://vaporlens.app/app/4210010/incremental_infinity); [Game Developer: "Lessons of my first incremental game"](https://www.gamedeveloper.com/design/lessons-of-my-first-incremental-game)).

> Transparência: a rede desta sessão bloqueia Wikipedia e Game Developer, então o conteúdo dessas fontes veio dos resumos da busca, não da leitura integral.

## 9. Core loop

**Em uma frase:** *posicionar prédios para criar sinergias de vizinhança → o reino produz sozinho (inclusive offline) → gastar em mais prédios, níveis, terra e defesa contra hordas → quando o crescimento desacelera, ascender para recomeçar mais forte num mapa novo.*

**Ele se sustenta?** Sim na primeira hora; parcialmente depois.

| Fase | Avaliação | Evidência |
|---|---|---|
| 0–60 s | Bom ritmo, com 10 prédios em ~40 s. A escolha espacial aparece cedo (serraria + floresta), mas falta um momento "uau" no primeiro minuto | Simulador: 10 construções em 40 s |
| 1–60 min | **Forte**: anéis novos reabrem o quebra-cabeça; hordas criam tensão | Anel 3 em ~5 min; anel 4 em ~45 min |
| 1–5 h | **Fraco**: com o mapa cheio, a decisão espacial acaba e sobra clicar em "Melhorar" 1 a 1 (sem compra em lote); hordas são passivas (sem decisão do jogador) | Simulador: renda em platô com 99 prédios |
| Meta | Ascensão + temporadas funcionam, mas o jogo não diz **quando** ascender | — |
| Onboarding | 6 abas e 9 indicadores no HUD desde o 1º segundo; heróis, passe e legado aparecem antes de fazerem sentido | Fase 4 vai confirmar jogando |

**Correções de core loop propostas (Fase 3)**: desbloqueio gradual das abas; "Melhorar tudo do tipo" e compra máxima; mostrar **+X/s** antes de comprar; layout das defesas influenciando a horda (ex.: torres cobrem um raio, à la Clash of Clans); indicador "vale ascender" (como o AdVenture Capitalist, que mostra quantos anjos você ganharia).

## 10. Checklist de jogo completo (Fase 2)

Legenda: **Tem** · **Mal feito** · **Falta** · **N/A** (não se aplica ao gênero).

### Jogabilidade
| Item | Status | Observação |
|---|---|---|
| Core loop claro e recompensador nos primeiros 60 s | Mal feito | Ritmo ok, mas a interface densa esconde o loop; falta um momento-chave no 1º minuto |
| Curva de progressão balanceada (fórmulas + simulação) | Tem | `docs/BALANCEAMENTO.md` + `npm run simulate`; precisa reavaliar após as mudanças |
| Metas de curto, médio e longo prazo | Tem | Missões diárias / anéis e passe / Ascensão |
| Variedade para não cansar | Mal feito | Eventos ajudam; o fim do jogo é repetitivo |
| *Gênero:* compra em lote / "melhorar tudo" | Falta | Reclamação nº 1 em idle |
| *Gênero:* prévia do ganho (+X/s) antes de comprar | Falta | A prévia de adjacência existe, mas sem o número final |
| *Gênero:* indicador de "quando ascender" | Falta | — |
| *Gênero:* automação na metade do jogo | Falta | Ex.: talento que melhora prédios sozinho |
| *Gênero:* decisão ativa durante eventos/hordas | Falta | Hordas resolvem sozinhas |

### Sensação (juice)
| Item | Status | Observação |
|---|---|---|
| Feedback visual e sonoro em toda ação | Mal feito | Visual ok; som são bipes sintéticos, sem assets |
| Animações, partículas, transições, tremor | Mal feito | Partículas e tremor existem; prédios não animam (só "balançam"); modais sem transição de saída |
| Efeitos sonoros reais | Falta | — |
| Música com loop | Falta | Depende de download (EXECUTAR.md) |
| Controle de volume | Falta | Só liga/desliga |

### Interface e experiência
| Item | Status | Observação |
|---|---|---|
| Onboarding sem tutorial chato, desbloqueio gradual | Mal feito | Tutorial curto e opcional (bom), mas todas as abas abertas desde o início |
| Menu principal | Falta | Só o modal de fundação |
| Pausa | N/A parcial | Em idle, pausar não faz sentido; mas falta um menu de jogo (opções, créditos, salvar) acessível por Esc |
| Opções | Mal feito | Só som e partículas, escondidas na aba Perfil |
| Créditos com licenças | Falta | Obrigatório para game-icons (CC BY) |
| Tela de carregamento | Falta | Necessária com assets |
| Favicon | Mal feito | É um emoji |
| Título | Tem | — |
| Ícone do app / manifest (instalável) | Falta | — |
| Responsivo de verdade (toque, sem hover obrigatório) | Mal feito | Layout responsivo e toque duplo para construir funcionam; descrições dependem de `title` (hover) |

### Persistência
| Item | Status | Observação |
|---|---|---|
| Save automático | Tem | A cada 10 s, ao ocultar a aba e ao fechar |
| Export / import | Tem | Base64 na aba Perfil |
| Backup | Mal feito | Só a cópia do save corrompido (B3); faltam backups em rodízio |
| Proteção contra corrupção | Mal feito | Sem checksum nem validação de esquema; gravação não atômica |
| Versionamento + migração | Tem | `SAVE_VERSION = 1` + `migrate()`; a v2 vai entrar com o novo formato |
| Estatísticas | Tem | Aba Perfil |
| Conquistas com recompensa real | Tem | 24, com gemas e títulos |

### Opções e acessibilidade
| Item | Status | Observação |
|---|---|---|
| Volume separado (música/efeitos) | Falta | — |
| Efeitos on/off | Tem | Partículas |
| Tema | Falta | Só escuro |
| Contraste | Mal feito | Não auditado; texto cinza sobre roxo em alguns pontos |
| Controle por teclado | Mal feito | 1–9 e Esc; mapa e painéis sem navegação por teclado/foco visível |
| Remapeamento de teclas | Falta | — |
| Tamanho de fonte | Falta | — |
| *Extra:* reduzir movimento (tremor/flash) | Falta | Importante para fotossensibilidade |
| *Extra:* daltonismo (não depender só de verde/vermelho na adjacência) | Mal feito | +/− no texto ajuda; a cor do tile é só verde/vermelho |

### Técnico
| Item | Status | Observação |
|---|---|---|
| Loop de jogo desacoplado da renderização | Tem | Simulação em `setInterval` de 250 ms; desenho em `requestAnimationFrame` |
| Sem vazamento de memória em sessões longas | Tem (a confirmar) | Listas limitadas; teste de heap na Fase 4 |
| Sem erros no console | Mal feito | Falha das fontes externas em rede restrita/offline; aviso de áudio (corrigido) |
| Performance estável em máquina fraca | Mal feito | Ver seção 4 |
| *Extra:* funciona offline (PWA) | Falta | Útil para "jogo de bolso" |
| *Extra:* varredura de emoji automatizada | Tem | `tools/emoji-scan.js` (entra no `npm test` na Fase 3) |

## 11. Plano da Fase 3 (aguardando seu ok)

Ordem pedida: bugs > core loop > save > sensação > interface > extras.

1. **Bugs restantes**: B7 (aba oculta), B8 (dia), B10 (tooltips no toque), B11 (fontes locais) e performance (terreno em cache, HUD sem `innerHTML`).
2. **Core loop**: desbloqueio gradual das abas; "Melhorar tudo do tipo" e compra máxima; +X/s na prévia; defesa com alcance (layout importa); indicador de Ascensão.
3. **Save v2**: migração `fonte → fogueira`; configurações novas (volumes, movimento, fonte, atalhos); backups em rodízio (3) e checksum.
4. **Sensação**: sprites Medieval RTS; moinho animado; som Kenney; música (quando você baixar); transições.
5. **Interface**: zero emoji (ícones game-icons + UI Pack); menu principal; menu de jogo (Esc); opções completas; créditos com licenças; tela de carregamento; favicon, ícone e manifest.
6. **Extras**: acessibilidade (teclado no mapa, remapeamento, contraste), PWA offline.

Entregáveis ao fim: ASSETS.md, EXECUTAR.md, CHANGELOG.md, ROADMAP.md e GDD.md atualizados, com a varredura de emoji, o console limpo e a simulação documentados.
