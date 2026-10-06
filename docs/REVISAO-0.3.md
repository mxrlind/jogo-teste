# Revisão de código e polimento (0.3.0)

Revisão completa do projeto antes de mexer no visual. Método: leitura de todo o código (motor, UI, dados, testes), screenshots do jogo em desktop (1440×900) e celular (390×844), medição de desenho no canvas e testes de ponta a ponta no navegador (Playwright). Nenhuma mecânica foi alterada.

## 1. Como o projeto estava

**Arquitetura: boa.** O motor (`src/core/`) é puro, roda no Node e tem 37 testes; os dados de balanceamento ficam em `src/data/`; a UI só conversa com a classe `Game` por métodos e eventos. Save com envelope, checksum e backups. Delegação de eventos por `data-action`. Isso foi mantido.

**Onde estava fraco:**
- **Visual de protótipo**: painel cinza do UI Pack em tudo, HUD com chips claros sobre fundo escuro sem hierarquia, nenhum estado de hover, botão desativado igual ao ativo.
- **Desempenho no menu**: o mapa de fundo era redesenhado a 60 fps sob um desfoque em tela cheia, embora fosse estático.
- **UX**: paleta com 11 de 15 cartões bloqueados do mesmo tamanho dos disponíveis; status da horda críptico ("Defesa 0 x 8 · Norte · 5m 58s"); toasts cobrindo a paleta; botões de missão desativados parecendo clicáveis; texto de desenvolvedor no menu ("ver EXECUTAR.md").

## 2. Problemas encontrados (prioridade)

### Crítico
| Problema | Onde | Situação |
|---|---|---|
| Mapa do menu redesenhado a 60 fps (~2.700 `drawImage`/s, canvas 1440×1440 sob `blur`) | `app.js`, `showMainMenu` | Corrigido: desenha uma vez e ao redimensionar (medido: 0 desenhos com o menu parado) |
| `ui.pointerHeld` preso se o botão é solto fora da janela: o painel lateral parava de atualizar | `app.js`, `boot` | Corrigido (`blur` zera) |

### Importante
| Problema | Situação |
|---|---|
| Save só em `beforeunload` e `visibilitychange`; celulares nem sempre disparam o primeiro | `pagehide` adicionado |
| Número do ranking usava a classe `.pos`, que colide com a utilitária global (verde, `!important`) | Renomeado; pódio com ouro/prata/bronze |
| "Resgatar todas" do passe disparava um toast por nível | Modo `quiet` no `Game` + um resumo |
| Esc durante a visita abria o menu em vez de voltar; escolher prédio na visita não fazia nada visível | Esc encerra a visita; paleta volta ao reino |
| Regra de desbloqueio duplicada (lista de prédios e cabeçalho da paleta) | `Game.unlockProgress()` único, com teste |
| Código morto: `fmtCost` (quebrado: usava nome de arquivo como ícone), `plainCost`, `icon`, `RESOURCE_ICONS` | Removido |
| Servidor local sem MIME de `.woff2`, `.mp3`, `.webmanifest` | Corrigido |
| `app.js` com 720 linhas misturando telas, ações e ciclo do jogo | **Pendente** (ver seção 4) |

### Melhorias
Visual, microinterações e feedback: ver o CHANGELOG da 0.3.0.

## 3. Desempenho

| Ponto | Antes | Depois |
|---|---|---|
| Menu principal | redesenho contínuo + desfoque | 1 desenho; 0 por segundo parado |
| Aldeões | varredura dos 144 tiles por frame | cache invalidado só quando o mapa muda |
| Efeitos (`fx`) | `filter` cria um array novo por frame | compactação no lugar |
| Modais e toasts | — | sem `backdrop-filter` (o mapa anima por baixo; o desfoque seria refeito a cada frame) |
| Animações CSS | — | só `transform`/`opacity`, desligadas em "Reduzir movimento" |

Medido no jogo: 120 frames seguidos sem nenhum acima de 20 ms (antes e depois).

## 4. O que ainda precisa de atenção

1. **Dividir `src/ui/app.js`**: as telas modais (`showIntro`, `showOptions`, `showSaveMenu`...) podem ir para `src/ui/screens.js`. Não foi feito agora para não misturar refatoração estrutural com a troca visual.
2. **Painel lateral refeito por `innerHTML` a cada segundo** quando há cronômetro na aba (heróis em expedição): perde o hover do botão sob o mouse. Solução: atualizar só os textos dos cronômetros.
3. **Mecânica, só proposta (não alterada)**: com a aba em segundo plano, o reino produz a 100% até o limite offline, enquanto fechar o jogo rende 60%. Deixar a aba escondida por horas é sempre melhor que fechar. Proposta: 100% na primeira hora em segundo plano e a eficiência offline depois.
4. **Mecânica, só proposta**: ouro sobra e madeira trava no meio do jogo (já no ROADMAP, item 3).
5. Toasts no desktop ficam no centro inferior, sobre a borda do mapa; como não capturam clique, não atrapalham, mas um jogador pode preferir no canto. Pode virar opção.

## 5. Próxima versão (sugestões)
- Desfazer a última construção por 5 s: o erro mais comum de iniciante (entregue na 0.4.0).
- Tela de fim de rodada ao Ascender, com estatísticas (ROADMAP, item 4 desde a 0.4.0).
- Sprite diferente por nível (5 e 10) para o crescimento aparecer no mapa.
- Autotile de bordas entre água, grama e pedra.
- Teste com jogadores reais medindo onde o tutorial perde gente.
