# Reino de Bolso

**Idle tycoon 2D em que a posição de cada prédio importa.** Construa um reino num tabuleiro 12×12: cada prédio ganha ou perde produção conforme os 4 vizinhos. O reino produz sozinho (inclusive offline), hordas atacam pelo lado anunciado, heróis colecionáveis dão bônus e a Ascensão recomeça tudo num mapa novo com bônus permanentes.

Roda no navegador (PC e celular, instalável como app), em HTML + CSS + JavaScript puro, **sem build e sem dependências**. Arte e som com licenças abertas: Kenney (CC0), game-icons.net (CC BY 3.0) e Nunito (OFL). Lista completa em [ASSETS.md](ASSETS.md).

**Jogar online:** https://mxrlind.github.io/jogo-teste/ · **Prévia do estilo visual:** https://mxrlind.github.io/jogo-teste/estilo.html

## Rodar localmente

```bash
npm start            # http://localhost:8080 (Node 18 ou mais novo; nenhuma dependência)
npm test             # testes do motor + varredura de emoji (falha se achar algum)
npm run simulate -- 8 1 --ascend   # bot joga 8 h de jogo (semente 1) e mostra o ritmo
```

Abrir o `index.html` direto pelo `file://` não funciona, porque navegadores bloqueiam módulos ES fora de HTTP. Use `npm start` ou qualquer servidor estático.

## Controles

| Ação | Mouse / teclado | Toque |
|---|---|---|
| Escolher prédio | clique na paleta ou teclas 1 a 9 | toque na paleta |
| Ver o bônus e o ganho antes de construir | passe o mouse no mapa | 1º toque no tile |
| Construir | clique | 2º toque no mesmo tile |
| Inspecionar, melhorar, mover, demolir | clique no prédio (U melhora, M move, Delete demole) | toque no prédio |
| Cursor no mapa | setas + Enter | |
| Menu do jogo / cancelar | Esc | botão de menu no topo |
| Próxima aba | T | toque na aba |

Todas as teclas podem ser remapeadas em **Opções**.

## O que tem no jogo

- **Adjacência**: fazenda + água, serraria + floresta, casa + mercado, torre + muralha; pedreira ao lado de casas atrapalha. A prévia mostra o bônus de cada vizinho e o ganho por segundo antes de construir.
- **Economia**: ouro, comida, madeira, pedra, moradores, trabalhadores, felicidade e armazenamento.
- **Hordas**: a cada ~4 minutos, sempre por um lado anunciado; torres e muralhas daquele lado contam inteiras.
- **Heróis**: 16 em 4 raridades, com estrelas, Conselho e expedições de 1 minuto a 2 horas.
- **Eventos e carroça do mercador**: bônus curtos e recompensas surpresa no mapa.
- **Temporadas**: rotação de 4 temas a cada 28 dias, passe gratuito de 30 níveis e missões diárias.
- **Ascensão**: recomeço com Coroas e 9 talentos permanentes; o jogo avisa quando vale a pena.
- **Social assíncrono**: ranking regional, visitas, saudações, trocas e código para mostrar o seu reino a amigos.
- **Desbloqueio gradual**: as abas aparecem conforme o reino cresce.
- **Opções e acessibilidade**: volumes separados de música e efeitos, tamanho do texto, alto contraste, movimento reduzido e remapeamento de teclas.
- **Save**: automático, com checksum, 3 backups em rodízio, recuperação de save danificado e exportar/importar.

Não existe dinheiro real no jogo: gemas só se ganham jogando.

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [GDD.md](GDD.md) | Documento de design curto: conceito, core loop, progressão, estilo visual e sonoro |
| [EXECUTAR.md](EXECUTAR.md) | O que depende de você: música, publicação, conferência de assets |
| [ASSETS.md](ASSETS.md) | Cada asset: arquivo, uso, fonte, autor, licença e link |
| [CHANGELOG.md](CHANGELOG.md) | O que mudou e por quê |
| [ROADMAP.md](ROADMAP.md) | O que ficou de fora, em ordem de impacto |
| [docs/DIAGNOSTICO.md](docs/DIAGNOSTICO.md) | Diagnóstico: bugs, checklist de jogo completo, pesquisa do gênero |
| [docs/REVISAO-0.3.md](docs/REVISAO-0.3.md) | Revisão de código da 0.3.0: problemas encontrados, plano priorizado e o que ficou pendente |
| [docs/BALANCEAMENTO.md](docs/BALANCEAMENTO.md) | Fórmulas, constantes e resultados do simulador |
| [docs/ARQUITETURA.md](docs/ARQUITETURA.md) | Código, formato do save, como adicionar conteúdo, debug |
| [docs/ESPECIFICACAO-SISTEMAS.md](docs/ESPECIFICACAO-SISTEMAS.md) | Especificação detalhada de cada sistema |
| [docs/PESQUISA-PARA-DESIGN.md](docs/PESQUISA-PARA-DESIGN.md) · [docs/pesquisa-de-mercado.md](docs/pesquisa-de-mercado.md) | Pesquisa de mercado e como ela virou design |
| [docs/MODELO-DE-NEGOCIO.md](docs/MODELO-DE-NEGOCIO.md) | Monetização ética, validação na Steam, riscos |

## Estrutura

```
index.html · styles.css · manifest.webmanifest · sw.js    página, tema, app instalável, offline
estilo.html                                              prévia do estilo visual
src/core/     motor puro, roda no Node (economia, mapa, save, hordas, temporadas...)
src/data/     conteúdo e números de balanceamento
src/ui/       canvas, HUD, painéis, menus, áudio
assets/       sprites, ui, icons, sfx, music, fonts (com as licenças originais)
tests/        testes do motor (node:test)
tools/        servidor, simulador, varredura de emoji, geradores (ASSETS.md, ícones, música)
```
