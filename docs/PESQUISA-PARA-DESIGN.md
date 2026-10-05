# 🔬 Da pesquisa ao design

Este documento liga cada conclusão da [pesquisa de mercado](pesquisa-de-mercado.md) (e da análise que a acompanhou) a uma decisão concreta do Reino de Bolso, com o arquivo onde ela vive. Também registra o que foi **descartado de propósito**.

## 1. A pergunta certa

A pesquisa propõe trocar *"qual gênero ganha mais?"* por:

> **"Qual gênero tem uma relação entre potencial de receita e custo de desenvolvimento que faz sentido para um dev solo?"**

| Modelo | Potencial | Custo para indie | Decisão |
|---|---|---|---|
| Fortnite / GTA / MMO / MOBA / Battle Royale | 🔥🔥🔥🔥🔥 | ☠️☠️–☠️☠️☠️ | ❌ descartado |
| 4X competitivo (Last War, Whiteout) | 🔥🔥🔥🔥 | exige milhões em aquisição de usuários | ❌ só os **mecanismos** foram aproveitados |
| Idle / Tycoon / Base building + economia | 🔥🔥🔥🔥 | 🟢 | ✅ **núcleo do jogo** |
| Social + base + coleção | 🔥🔥🔥🔥🔥 | 🟡 | ✅ **camadas por cima do núcleo**, começando assíncronas |

**Resultado:** "2D Social Tycoon / RPG / Idle com cidade personalizável, economia, trabalhadores, exploração, coleção, progressão e temporadas", exatamente a aposta final da pesquisa, num escopo que uma pessoa consegue entregar.

## 2. Os 8 mecanismos, aplicados

A pesquisa identifica 7 mecanismos recorrentes nos jogos rentáveis, mais um oitavo ("identidade").

| Mecanismo | De onde vem | Como aparece no jogo | Onde está no código |
|---|---|---|---|
| 🧠 **Progressão** | GTA, Minecraft, RPGs | 15 prédios × 10 níveis, 4 anéis de terra, heróis com estrelas, Ascensão | `data/buildings.js`, `core/map.js`, `core/heroes.js` |
| 💰 **Economia** | GTA Online, Roblox, Last War | 4 recursos + população + trabalho + felicidade + armazenamento; mercado converte comida em ouro | `core/economy.js` |
| 🏆 **Competição** | LoL, Fortnite, Honor of Kings | Ranking regional por Poder do Reino; corrida de defesa contra hordas que escalam | `core/social.js`, `Game.resolveRaid` |
| 🎨 **Coleção** | LoL, Fortnite, Pokémon | 16 heróis em 4 raridades, silhuetas "❔" dos que faltam, estandartes, emblemas, títulos | `data/heroes.js`, `data/cosmetics.js` |
| 🏗️ **Criação** | Minecraft, Roblox | O layout É o jogo: adjacência, mover grátis, limpar terreno, código do reino para mostrar | `core/economy.js#adjacencyAt`, `core/social.js#encodeKingdom` |
| 🔄 **Temporadas** | Fortnite, LoL | Fundação → Guerra → Expansão → Catástrofe (os 4 nomes sugeridos na pesquisa), passe de 30 níveis | `data/seasons.js`, `core/season.js` |
| 👥 **Social** | Roblox, Minecraft, Monopoly GO! | Visitar, saudar e trocar com vizinhos; compartilhar o reino por código | `core/social.js`, aba Social |
| 🔥 **Identidade** | (oitavo mecanismo) | Nome, brasão, título e layout únicos, visíveis no HUD e no ranking | `Game.equip`, aba Perfil |

## 3. Lições específicas de cada jogo

| Jogo da pesquisa | Lição | O que fizemos | O que NÃO copiamos |
|---|---|---|---|
| **Roblox** | "Crie uma máquina, não um jogo perfeito" | Conteúdo dirigido por dados (`src/data/`): um prédio novo é um objeto no catálogo. Código do reino = embrião de UGC | Plataforma UGC completa (custo ☠️☠️) |
| **Fortnite** | novidade → retorno → evento → recompensa → coleção → temporada | Eventos relâmpago, baú surpresa, temporadas com modificador global, passe | Battle royale, colaborações pagas |
| **GTA V / Online** | Economia persistente e **identidade**: PERSONAGEM → DINHEIRO → NEGÓCIO → FUNCIONÁRIOS → PRODUÇÃO → EXPANSÃO → PRESTÍGIO | Exatamente essa cadeia: reino → ouro → prédios → trabalhadores → produção → anéis → Ascensão | Mundo 3D, crime |
| **Minecraft** | "Não diga o que fazer; entregue sistemas" | Tutorial opcional que termina com "não existe missão final"; sem campanha | Mundo infinito |
| **League of Legends** | O jogador compra **identidade**, não poder | Cosméticos sem poder; títulos de conquistas e de temporada | Venda de campeões com poder |
| **Honor of Kings** | Sessões curtas, "só mais uma" | Loop de 2–5 min: coletar, construir, expedição, sair | Partidas competitivas em tempo real |
| **Last War / Whiteout** | Progressão + base + estratégia + eventos | Base, defesa, hordas, aceleração de expedições por gemas (ganhas jogando) | Aceleradores pagos, guerra de alianças, "baleias" |
| **EA Sports FC** | **Hábito**: algo para cada dia | Recompensa diária com sequência, 3 missões diárias, temporada mensal | Lançamento anual |
| **Royal Match / Candy Crush** | Metajogo de "reforma" | Decorações (jardim, fonte, estátua) e o reino ficando mais bonito | Vidas e boosters pagos |
| **Monopoly GO!** | Social leve gera retorno | Saudações e trocas com vizinhos | Social casino |
| **Schedule I / Stardew** | Gestão com ciclo viciante; dev solo dá conta | Núcleo tycoon com adjacência | Tema polêmico |
| **Terraria** | Cauda longa com atualizações grátis | Temporadas que mudam regras sem custo de conteúdo novo | — |
| **R.E.P.O. / PEAK** | Precisa ser "divertido de assistir" | Lore engraçada dos heróis, tremor/flash nas invasões, baús, combos de adjacência que rendem prints | Multiplayer em tempo real (escopo médio/alto; ficou no roadmap) |

## 4. "Idle Tycoon onde sua base é o jogo"

A pesquisa propõe isto literalmente:

> *"Uma fábrica perto de um armazém recebe bônus. Uma casa perto de um mercado aumenta consumo. Uma torre perto da muralha aumenta defesa. Uma taverna perto de casas aumenta felicidade."*

| Frase da pesquisa | Regra implementada (`src/data/buildings.js`) |
|---|---|
| fábrica perto de armazém recebe bônus | todo produtor: `armazem: +15%` |
| casa perto de mercado aumenta consumo | mercado: `casa: +20%`; casa: `mercado: +50%` |
| torre perto da muralha aumenta defesa | torre: `muralha: +30%` |
| taverna perto de casas aumenta felicidade | taverna: `casa: +15%` (a felicidade escala com o multiplicador) |

E o início sugerido também está lá: **"[CASA] 💰100 · 1 trabalhador · 1 produção · 1 área"** = casa + fazenda pré-construídas, 100 de ouro e 1 morador (`core/map.js#generateMap`, `core/state.js#createState`).

## 5. Os dois perfis de jogador

| Perfil | Sessão | O que o jogo oferece |
|---|---|---|
| **Casual** | 2–5 min | Modal de "enquanto você esteve fora", baú, expedição, missão diária, sair. O offline cobre o resto |
| **Hardcore** | 30–120 min | Otimização de adjacência, corrida de defesa, passe, Ascensão planejada, ranking |

## 6. Mecânicas "roubadas dos líderes" (seção final da pesquisa)

| Recomendação | Implementação |
|---|---|
| Progressão em camadas (prestígio com bônus permanente) | Ascensão → Coroas → 9 talentos |
| Eventos com prazo e recompensas exclusivas (D1, D7, D30) | Eventos relâmpago, cosméticos de temporada, sequência de 7 dias |
| Uma camada social, nem que seja ranking ou guilda assíncrona | Ranking + visitas + trocas + código do reino |
| Um tema que gere clipe | Hordas com nome, Lua de Sangue, baús surpresa, revelação de herói lendário com fanfarra |

## 7. Riscos que a pesquisa aponta, e a resposta

| Risco | Resposta |
|---|---|
| Mediana de US$ 249 na Steam; 70% dos devs solo sem lucro | Escopo enxuto (navegador, sem assets pagos) e **validação por lista de desejos antes de investir mais** ([MODELO-DE-NEGOCIO](MODELO-DE-NEGOCIO.md)) |
| Nicho idle lotando (+150% de lançamentos) | Diferencial claro: **quebra-cabeça espacial** + camada social, em vez de "números subindo" |
| Precisa de muito conteúdo de progressão | Conteúdo dirigido por dados + temporadas que remixam regras + simulador para medir o ritmo |
| Pay-to-win afasta o público da Steam | Zero dinheiro real no protótipo; plano de monetização só com cosméticos/apoio |
