# 👑 Reino de Bolso

> **Um Idle Tycoon 2D social onde a sua base é o jogo.**
> Construa um reino num mapa 12×12 em que **a posição de cada prédio importa**, defenda-o de hordas, colecione heróis, ascenda para recomeçar mais forte e volte a cada temporada, que muda as regras.

Roda direto no navegador (PC e celular), em **JavaScript puro, sem build e sem dependências**. Foi pensado para virar um jogo de Steam por US$ 3–5 (empacotado com Tauri/Electron), como recomenda a [pesquisa de mercado](docs/pesquisa-de-mercado.md) que originou o projeto.

---

## ▶️ Como jogar

**Online:** https://mxrlind.github.io/jogo-teste/ (GitHub Pages, publicado automaticamente a cada push na `main`)

Localmente:

```bash
npm start          # servidor local em http://localhost:8080 (Node ≥ 18, zero dependências)
```

Também funciona com qualquer servidor estático (`python3 -m http.server`, `npx serve`). Abrir o `index.html` direto pelo `file://` **não** funciona, porque os navegadores bloqueiam módulos ES fora de HTTP.

| Ação | Mouse / teclado | Toque |
|---|---|---|
| Escolher construção | clique na paleta ou teclas `1`–`9` | toque na paleta |
| Ver a adjacência antes de construir | passe o mouse no mapa | 1º toque no tile mostra a prévia |
| Construir | clique no tile | 2º toque no mesmo tile |
| Inspecionar / melhorar / mover / demolir | clique num prédio | toque num prédio |
| Cancelar | `Esc` | botão "Cancelar" |
| Abrir baú do mercador 🎁 | clique nele | toque nele |

## ✨ O que tem no jogo

| Sistema | Resumo | Inspiração (da pesquisa) |
|---|---|---|
| 🧩 **Adjacência** | Cada prédio ganha ou perde bônus dos 4 vizinhos (fazenda + água, serraria + floresta, casa + mercado, pedreira × casa…) | "a posição das construções importa" |
| 💰 **Economia** | Ouro, comida, madeira, pedra, população, trabalhadores, felicidade e armazenamento | GTA Online, Last War |
| 🗺️ **Expansão** | 4 anéis de terra; terrenos de floresta/rocha podem ser limpos (com custo de oportunidade) | Minecraft |
| ⚔️ **Invasões** | Hordas a cada ~4 min, ficando mais fortes a cada vitória; proteção de novato e teto de saque | 4X de sobrevivência |
| 🦸 **Heróis** | 16 heróis em 4 raridades; duplicatas viram estrelas; Conselho com bônus passivos | LoL (coleção) |
| 🧭 **Expedições** | Heróis fora do Conselho saem por 1 min a 2 h e voltam com recursos e gemas | sessões curtas (Honor of Kings) |
| 🎉 **Eventos relâmpago** | Festival da Colheita, Febre do Ouro, Lua de Sangue… + baús surpresa no mapa | Fortnite (novidade constante) |
| ⭐ **Temporadas** | Rotação Fundação → Guerra → Expansão → Catástrofe (28 dias cada), passe gratuito de 30 níveis e missões diárias | Fortnite, LoL |
| 👑 **Ascensão** | Prestígio: recomece por Coroas e invista na Árvore de Legado (9 talentos) | idle/incremental |
| 🎖️ **Identidade** | Nome, estandarte, emblema, títulos e 24 conquistas | "esse é o MEU reino" |
| 🌐 **Social assíncrono** | Ranking regional, visitas, saudações e trocas com vizinhos + **código do reino** para mostrar sua cidade a amigos | Roblox, Monopoly GO! |
| 🌙 **Offline** | O reino produz enquanto você está fora (60%, até 4 h, ampliável) | idle |
| 📅 **Rotina** | Recompensa diária com sequência de 7 dias | EA FC (hábito) |

Tudo que custa gemas se ganha **jogando**. Não existe dinheiro real no jogo.

## 📚 Documentação

| Documento | Para quê |
|---|---|
| [**GDD — Documento de Design**](docs/GDD.md) | Visão, pilares, loops e a especificação de todos os sistemas |
| [**Pesquisa → Design**](docs/PESQUISA-PARA-DESIGN.md) | Como cada insight da pesquisa de mercado virou uma feature (e o que foi descartado de propósito) |
| [**Balanceamento**](docs/BALANCEAMENTO.md) | Todas as fórmulas e constantes, metas de ritmo e resultados do simulador |
| [**Arquitetura**](docs/ARQUITETURA.md) | Código, fluxo de dados, formato do save, como adicionar conteúdo, testes e debug |
| [**Modelo de Negócio**](docs/MODELO-DE-NEGOCIO.md) | Monetização ética, validação na Steam, métricas e riscos |
| [**Roadmap**](docs/ROADMAP.md) | Do protótipo ao lançamento, e o plano de temporadas |
| [Pesquisa de mercado (original)](docs/pesquisa-de-mercado.md) | O estudo que originou o conceito |
| [CHANGELOG](CHANGELOG.md) | Histórico de versões |

## 🗂️ Estrutura

```
index.html · styles.css        página e tema visual
src/
  main.js                      ponto de entrada
  data/                        conteúdo e números de balanceamento (prédios, heróis, temporadas…)
  core/                        motor puro, testável sem navegador (economia, mapa, invasões, save…)
  ui/                          canvas, HUD, painéis, modais e sons sintetizados
tests/core.test.js             testes do motor (node:test)
tools/serve.js                 servidor estático sem dependências
tools/simulate.js              bot que joga N horas para medir o ritmo do jogo
docs/                          documentação
```

## 🧪 Qualidade

```bash
npm test                              # testes do motor
npm run simulate -- 8 1 --ascend      # simula 8 h de jogo (semente 1) com Ascensões
```

Abra `http://localhost:8080/?debug` para expor `window.reino.game` no console (dar recursos, forçar invasão etc.). Os comandos estão em [ARQUITETURA.md](docs/ARQUITETURA.md#8-modo-debug).
