# ⚖️ Balanceamento

Todas as fórmulas do jogo, onde mexer em cada uma, as metas de ritmo e os resultados do simulador.

> **Regra de ouro:** número de balanceamento só vive em `src/data/*.js` (ou na constante nomeada no topo do módulo citado). Mudou um número? Rode `npm test` e `npm run simulate`, e atualize as tabelas deste documento.

---

## 1. Constantes principais

| Constante | Valor | Arquivo |
|---|---|---|
| Grade | 12×12, anel inicial 2 (6×6) | `core/map.js` |
| Custos de anel | 3: 2.000💰 400🪵 · 4: 60.000💰 4.000🪨 · 5: 1.000.000💰 50.000🪨 | `core/map.js#RING_COSTS` |
| Recursos iniciais | 100💰 50🍖 30🪵 20🪨, 1 morador, 1 pergaminho | `core/state.js#createState` |
| Armazenamento base | 2.500💰, 500 demais | `data/buildings.js#BASE_STORAGE` |
| Comida por morador | 0,15/s | `FOOD_PER_POP` |
| Crescimento populacional | 0,25/s × (0,5 + felicidade/100) | `POP_GROWTH` |
| Fome | −0,2 morador/s | `POP_STARVE` |
| Custo por cópia | ×1,12 | `COUNT_COST_GROWTH` |
| Custo por nível | ×2,5 | `LEVEL_COST_GROWTH` |
| Produção por nível | +75% | `LEVEL_OUTPUT_STEP` |
| Nível máximo | 10 (decorações: 1) | `MAX_LEVEL` |
| Reembolso ao demolir | 50% | `SELL_REFUND` |
| 1ª invasão / intervalo / aviso | 360 s / 240 s ±20% / 20 s | `data/events.js` |
| Força da horda | 8 × 1,4^nível | `RAID_BASE_STRENGTH`, `RAID_GROWTH` |
| Perda na derrota | 15% (5% nas 2 primeiras), teto de 120 s de produção | `RAID_LOSS_*` |
| Eventos / baús | 360–600 s / 100–220 s (dura 20 s) | `EVENT_INTERVAL`, `CHEST_*` |
| Offline | 4 h a 60% | `core/game.js#BASE_OFFLINE_*` |
| Coroas | √(ouro da rodada / 1.000.000) | `data/talents.js#CROWN_DIVISOR` |
| Passe | 30 níveis × 300 XP; temporada de 28 dias | `data/seasons.js` |

## 2. Fórmulas

### 2.1 Produção de um prédio
```
adj          = Σ bônus dos 4 vizinhos   (bônus de terreno positivo × (1 + terrainAdj))
mult         = max(0, 1 + adj) × (1 + 0,75 × (nível − 1))
trabalho     = workers > 0 ? min(1, população / trabalhadoresExigidos) : 1
ativo        = !requiresAdj || existe vizinho do tipo exigido
felic.       = 0,5 + felicidade / 100                      (0,5 … 1,5)
global[r]    = (1 + prodAll + prod[r]) × (1 + evento[r]) × (r = ouro ? 1 + estátuas : 1)

produção[r]  = base[r] × mult × trabalho × ativo × felic. × global[r]
casa         = … × ocupação × (1 + bônus de casas da temporada)
```

### 2.2 Trabalhadores
`exigidos(nível) = base + ⌊(nível − 1) × base × 0,5⌋` → um mercado nv 10 exige 11.

### 2.3 Felicidade
```
bruta = 50 + Σ(felicidade⁺ × mult) + Σ felicidade⁻ + heróis + temporada − 2 × ⌊população / 20⌋
felicidade = clamp(bruta, 0, 100)
```

### 2.4 Comida e mercados
Moradores comem primeiro (`0,15 × população`). Os mercados consomem `0,6 × nívelMult × trabalho`. **Só quando o estoque chega a zero** os mercados passam a converter apenas o excedente: `ratio = max(0, produção − moradores) / demanda dos mercados`.

### 2.5 Custos
```
construir(id) = base × 1,12^(cópias existentes) × (1 − desconto)
melhorar(id, nível) = base × 2,5^nível × (1 − desconto)     (nível = nível atual)
desconto = min(75%, Engenharia + Arquiteta + temporada + Mutirão)
```

### 2.6 Armazenamento
`limite[r] = base[r] + Σ armazém[r] × nível²` → um armazém nv 10 guarda +800.000💰.

### 2.7 Invasões
```
força       = round(8 × 1,4^nível)
defesa      = (Σ defesa × mult × trabalho + Σ poder × ★ dos heróis no Conselho) × (1 + bônus de defesa)
vitória     → ouro += max(força × 12 × (1 + 0,15 × nível), renda × 45) × (1 + saque); gemas += 1 + Garimpo (+2 a cada 5º nível); nível++
derrota     → cada recurso perde min(estoque × fração, max(50, produção bruta × 120)); nível−−
fração      = 5% nas 2 primeiras invasões da conta, depois 15%
```

### 2.8 Heróis e expedições
```
custo em ouro        = 300 × 1,6^(recrutamentos com ouro)
bônus                = valor × (1 + 0,5 × (★ − 1))
recompensa ouro      = max(30, renda × duração × 0,4) × (1 + poder × ★ × 0,02) × (1 + bônus de expedição)
madeira / pedra      = max(10 | 5, produção bruta × duração × 0,3) × o mesmo multiplicador
acelerar             = ⌈segundos restantes / 600⌉ gemas
```

### 2.9 Offline
```
limite     = (4 + 2 × Vigília + 4 × ★Relojoeiro) horas
eficiência = min(1, 0,6 + 0,08 × Vigília + 0,25 × ★Relojoeiro)
simulação em ~400 blocos (mín. 5 s), só para ganhos positivos; gastos (comida) a 100%
```

### 2.10 Prestígio
```
coroas = ⌊ √(ouroDaRodada / 1.000.000) × (1 + 0,05 × templos + bônus da temporada) ⌋
custo do talento = custoBase × (nível atual + 1)
```

### 2.11 Poder do Reino (ranking)
`⌊√(ouro da vida toda) + 10 × Σ níveis + 40 × Σ★ + 500 × ascensões + 15 × vitórias⌋`.
Os rivais seguem `base_i × (1 + horas × g_i)^1,3`, com `base_i ≈ 40 × 3,2^i` e `g_i ∈ [0,02; 0,08]`. O jogador começa no fim da tabela e sobe.

## 3. Metas de ritmo

| Marco | Meta | Por quê |
|---|---|---|
| 10 construções | < 2 min | Ação imediata (P2) |
| 1ª invasão | 6 min, vencível | O tutorial prepara; proteção de novato se perder |
| Anel 3 | 5–15 min | Primeira grande decisão de espaço |
| Anel 4 | 30–60 min | Fim de uma "sessão longa" |
| 1ª Coroa | ~1 h | Revela a camada de prestígio na primeira sessão longa |
| Mapa inteiro | 3–6 h (sem ascender) | Objetivo de vários dias para o casual |
| Passe completo | 2–3 semanas jogando ~1 h/dia | A temporada tem 4 semanas: dá para completar sem precisar jogar todo dia |

## 4. Resultados do simulador

`tools/simulate.js` coloca um bot guloso para jogar (age a cada 5 s, abre baús, resgata missões, escolhe o maior retorno sobre investimento entre construir e melhorar, prioriza comida, casas, pedra, defesa e felicidade, e constrói armazéns quando uma meta não cabe no cofre). Com `--ascend`, ele ascende quando dobraria as Coroas que tem.

> O mapa é determinístico pela semente, mas eventos, baús e recrutamentos usam `Math.random`, então duas execuções da mesma semente variam um pouco.

### 4.1 Marcos (temporada Fundação, 8 h)

| Marco | Semente 1 | Semente 2 | Semente 3 | Semente 1 (sem ascender) |
|---|---|---|---|---|
| 10 construções | 40 s | 40 s | 40 s | 40 s |
| 1º mercado | 1m30 | 1m15 | 55 s | 1m30 |
| Anel 3 | 4m25 | 6m10 | 4m30 | 10m30 |
| 1ª invasão vencida | 6m00 | 6m00 | 4m30 | 6m00 |
| 100K de ouro | 14m | 14m39 | 14m50 | 17m22 |
| Anel 4 | 43m50 | 14m40 | 46m50 | 44m50 |
| **1ª Coroa** | **49m59** | **49m18** | **53m42** | **58m26** |
| 1ª Ascensão | 2h05 | 2h19 | 1h58 | — |
| 10M de ouro | 4h49 | 5h54 | 5h08 | 4h12 |
| Anel 5 | — | 7h59 | 5h33 | 4h31 |

**Leitura:** o começo é rápido (P2), a primeira Coroa chega perto de 1 h (meta) e o mapa inteiro leva de 4 a 8 h. Ascender cedo atrasa o mapa completo e acelera o ouro total; as duas estratégias são viáveis.

### 4.2 Evolução sem ascender (semente 1)

| Tempo | Ouro/s | Prédios | População | Defesa × horda | Vitórias / derrotas | Nível do passe |
|---|---|---|---|---|---|---|
| 30 min | 85 | 47 | 89 | 66 × 84 | 7 / 0 | 3 |
| 1 h | 532 | 70 | 404 | 324 × 324 | 13 / 2 | 5 |
| 2 h | 633 | 70 | 464 | 429 × 454 | 21 / 9 | 7 |
| 4 h | 717 | 70 | 520 | 486 × 635 | 37 / 24 | 8 |
| 5 h | 1.000 | 99 | 1.076 | 1.110 × 889 | 45 / 31 | 11 |
| 8 h | 1.000 | 99 | 1.096 | 1.332 × 1.742 | 69 / 53 | 13 |

**Leitura:** a horda acompanha a defesa e oscila em torno dela (autorregulação). O passe sobe ~1,6 nível/hora de jogo contínuo sem missões nem expedições; um jogador real chega ao nível 30 em 2–3 semanas.

## 5. Histórico de ajustes

O simulador encontrou problemas que não apareciam jogando poucos minutos:

| # | Sintoma | Causa | Ajuste |
|---|---|---|---|
| 1 | Renda travada em ~100/s por horas | Anel 4 custava mais ouro do que cabia no cofre (limite 1.000 + 2.000/armazém) | Limite base 2.500; armazém 8.000 × **nível²**; custos de anel revistos |
| 2 | Sem pedra, sem defesa, sem taverna | Pedreira a 0,4/s e pedra inicial zero | Pedreira 0,6/s; começa com 20🪨 |
| 3 | Metade das invasões perdidas, poupança impossível | Perder 20% do estoque a cada ~8 min cria um teto de equilíbrio (taxa × intervalo / fração) | Perda 15%, **limitada a 2 min de produção**; proteção de novato (5%) |
| 4 | Felicidade 150 (produção ×2) | Tavernas com níveis e adjacência sem teto prático | Felicidade limitada a 100 (×1,5) |
| 5 | Mapa completo em 29 min, Coroa em 24 min | Custos de anel e divisor de Coroas baixos | Anéis 4/5 = 60K/1M; divisor 1.000.000 |
| 6 | Tudo no nível máximo em ~2 h | Nível máx. 5 com custo ×2,2 | Nível máx. 10 com custo ×2,5 |
| 7 | Passe completo em ~2 h | XP generoso demais para ações repetitivas | XP por ação reduzido; 300 XP por nível |

## 6. Alavancas para ajustes futuros

| Se… | Mexa em… |
|---|---|
| O começo está lento | custo base de casa/fazenda/serraria; ouro inicial |
| O jogo fica parado depois do mapa cheio | `LEVEL_COST_GROWTH`, `MAX_LEVEL`, divisor de Coroas |
| Hordas frustram | `RAID_GROWTH`, `RAID_LOSS_FRACTION`, `RAID_LOSS_CAP_SECONDS` |
| Hordas são irrelevantes | `RAID_GROWTH` maior, saque maior (para valer a corrida) |
| Ascensão não compensa | divisor de Coroas, valor de Fartura (+10%/nível) |
| Gemas sobrando | preço de recrutamento (15💎) e de cosméticos |

## 7. Limitações conhecidas
- O bot não usa expedições, eventos de forma inteligente nem heróis além dos recrutados automaticamente, então é mais lento que um humano atento nessas frentes e mais rápido em reação (age a cada 5 s).
- As temporadas mudam o ritmo (Guerra: hordas mais frequentes; Expansão: anéis pela metade). As tabelas acima usam Fundação.
- Os rivais do ranking não reagem ao jogador; o crescimento deles é calibrado só por tempo.
