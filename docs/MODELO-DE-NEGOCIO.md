# Modelo de negócio

> Base: [pesquisa de mercado](pesquisa-de-mercado.md). Os números de mercado citados são estimativas de terceiros (Sensor Tower, AppMagic, Newzoo, Alinea) e servem para comparar ordens de grandeza.

## 1. Posicionamento

| Pergunta | Resposta |
|---|---|
| O que é? | Idle tycoon 2D com quebra-cabeça de adjacência, defesa contra hordas, coleção de heróis e temporadas |
| Para quem? | Fãs de idle/incremental e de city builders leves; jogadores de "segunda tela" |
| Por que agora? | A tag Idler cresceu ~150% em lançamentos em 2026, e esses jogos batem 1.000 reviews com mais frequência que a média da Steam |
| Diferencial | **Posição importa** (decisão espacial em vez de só números subindo) + camada social + temporadas que mudam regras |
| Concorrentes de referência | Upload Labs, Shelldiver (idle Steam), Stardew (gestão), Whiteout/Last War (mecânicas de base) |

## 2. Monetização recomendada (em ordem)

| Fase | Plataforma | Modelo | Preço | Notas |
|---|---|---|---|---|
| 1. Validação | Navegador (itch.io) | Grátis | — | Demo para medir retenção e gerar lista de desejos |
| 2. Lançamento | **Steam** | **Pago, venda única** | **US$ 3–5** | Na Steam, 78% da receita vem de jogos pagos |
| 3. Cauda longa | Steam | DLC de apoio ("Pacote do Fundador": estandartes, emblemas, trilha sonora) | US$ 2–3 | Só cosméticos; temporadas continuam grátis (lição de Terraria) |
| 4. Opcional | Mobile | Grátis + anúncio recompensado (ex.: "dobrar expedição") | — | Só se a retenção web justificar; sem aquisição paga de usuários |

### Regras éticas (inegociáveis)
1. **Nada de pay-to-win.** Dinheiro real nunca compra produção, defesa, heróis ou Coroas.
2. **Nada de loot box paga.** O recrutamento aleatório usa só moedas do jogo.
3. **Gemas só se ganham jogando** (já é assim no protótipo).
4. Cosmético pago nunca é exclusivo de forma que deixe o jogador gratuito "feio": existem opções grátis em todas as categorias.

## 3. Projeção (cenários)

Regra prática do mercado indie (não vem da pesquisa; é o chamado "método Boxleiter"): cada review na Steam corresponde a ~30–60 cópias vendidas. Para um jogo de US$ 4, usando ~40 cópias por review:

| Cenário | Reviews | Cópias (aprox.) | Bruto | Líquido estimado* |
|---|---|---|---|---|
| Pessimista (mediana da Steam) | < 10 | < 300 | < US$ 1 mil | — |
| Base | 100 | ~4.000 | ~US$ 16 mil | ~US$ 9 mil |
| Bom | 1.000 | ~40.000 | ~US$ 160 mil | ~US$ 90 mil |
| Excelente (top 0,5%) | 5.000+ | 200.000+ | US$ 800 mil+ | — |

\*Descontando ~30% da Steam, impostos e descontos médios. **A mediana de um jogo na Steam é de ~US$ 249**: o cenário pessimista é o mais provável sem validação e marketing.

## 4. Validação antes de investir (o "próximo passo" da pesquisa)

| Etapa | Critério para seguir | Prazo |
|---|---|---|
| Protótipo jogável | feito (este repositório) | — |
| 10 testadores próximos | ≥ 6 jogam > 30 min no 1º dia sem pedir; ≥ 3 voltam no dia seguinte | 1 semana |
| Demo no itch.io + Reddit (r/incremental_games, r/idlegames) | D1 ≥ 35%, D7 ≥ 15% (referência: os top casuais têm D7 de 14,9% e os mid-core, 20,9%) | 2–3 semanas |
| Página na Steam ("Coming Soon") | **≥ 7.000 listas de desejos** antes do lançamento (referência comum entre devs indie, não da pesquisa) | 2–3 meses |
| Participar do Steam Next Fest com a demo | Picos de listas de desejos e feedback | próximo festival |

## 5. Métricas a instrumentar
- Funil do tutorial (passo 1 → 6), tempo até a 1ª invasão vencida, até o anel 3 e até a 1ª Ascensão.
- D1 / D7 / D30, sessões por dia, duração média (meta: muitas de 2–5 min + algumas longas).
- % de jogadores que compartilham o código do reino (proxy de viralidade).
- Abandono por derrota em invasão (se alto: ajustar `RAID_GROWTH` / perda).

Telemetria ainda não existe. Plano: endpoint anônimo e opcional com eventos agregados, sem dados pessoais (ver [ROADMAP](../ROADMAP.md)).

## 6. Marketing de baixo custo
- **"Divertido de assistir"**: o momento do herói lendário, a Lua de Sangue e combos absurdos de adjacência são feitos para GIF e clipe curto.
- **Desafios de layout semanais** ("maior produção de ouro só com 20 prédios"), compartilhados por código do reino. É conteúdo gerado pela comunidade.
- **Streamers de idle/cozy**: chave grátis + uma temporada com o nome deles.
- **Devlog** (TikTok/Shorts) mostrando o simulador de balanceamento e os bugs engraçados.

## 7. Riscos

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| Ninguém descobre o jogo | Alta | Alto | Validação antes de investir; Next Fest; desafios compartilháveis |
| Nicho idle saturado | Média | Médio | Diferencial espacial + social; arte com identidade |
| Conteúdo acaba rápido | Média | Alto | Temporadas que remixam regras; níveis até 10; prestígio; simulador para medir |
| Emojis parecem "baratos" na Steam | Alta | Médio | Sprite atlas pixel art antes da página na Steam |
| Escopo social real cresce demais | Média | Médio | Fases pequenas (ranking → visitas → guildas) |
