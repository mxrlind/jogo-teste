# Reino de Bolso — GDD curto

> Documento-âncora para manter o jogo coerente entre sessões. Se uma mudança contradiz este arquivo, atualize este arquivo **antes** de mudar o jogo.
> Detalhes de cada sistema: [docs/ESPECIFICACAO-SISTEMAS.md](docs/ESPECIFICACAO-SISTEMAS.md) · Fórmulas: [docs/BALANCEAMENTO.md](docs/BALANCEAMENTO.md) · Estado atual: [docs/DIAGNOSTICO.md](docs/DIAGNOSTICO.md)

## 1. Conceito

**Idle tycoon 2D em que a posição de cada prédio importa.** Você recebe um terreno 12×12 com uma casa e uma fazenda e o transforma num reino. Cada prédio ganha ou perde produção conforme os 4 vizinhos (água, floresta, montanha, outros prédios). O reino produz sozinho, inclusive offline. Hordas testam a sua defesa, heróis colecionáveis dão bônus, e a Ascensão recomeça tudo num mapa novo com bônus permanentes.

- **Plataforma**: navegador (PC e celular), depois Steam empacotado.
- **Stack**: HTML + CSS + JavaScript (ES modules), canvas 2D, sem build e sem dependências em tempo de execução.
- **Sessão**: 2–5 min (coletar, construir, sair) ou 30–120 min (otimizar).
- **Referências**: Islanders (pontuação por proximidade ao vivo), Kittens Game (armazenamento como gargalo), AdVenture Capitalist (prestígio), Clash of Clans (base + defesa), Cookie Clicker (recompensa surpresa).

## 2. Pilares

1. **O lugar importa**: toda feature nova deve criar uma decisão de *onde*, não só de *quando*.
2. **Só mais uma**: progresso visível a cada retorno; nada de esperar sem ter o que decidir.
3. **Mostre antes de cobrar**: o jogador vê o efeito (adjacência, +X/s, custo) antes de confirmar.
4. **Justo**: nada se compra com dinheiro real; derrota dói, mas não destrói (proteção de novato e teto de saque).
5. **Um estilo só**: mundo em vetor plano top-down (Kenney Medieval RTS); interface plana (Kenney UI Pack) com ícones em silhueta (game-icons). Zero emoji.

## 3. Core loop

> Posicionar prédios para criar sinergias → o reino produz sozinho → gastar em prédios, níveis, terra e defesa → quando o crescimento desacelera, ascender.

```
        +--------------------------------------------------+
        v                                                  |
  [Ver o mapa] -> [Escolher prédio] -> [Prévia: vizinhos +X%, +Y/s]
                                              |
                                              v
                    [Construir / melhorar / mover] -> [Produção sobe]
                                              |
            +---------------+-----------------+---------------+
            v               v                 v               v
      [Horda a cada    [Baú surpresa /   [Expedições e    [Limite de
       ~4 min]          evento curto]     heróis]          armazém]
            +---------------+-----------------+---------------+
                                              v
                         [Mapa cheio, renda em platô] -> [Ascensão: Coroas -> talentos]
                                                                 |
                                                     [Mapa novo, mesma identidade]
```

## 4. Progressão

| Prazo | Meta do jogador | Sistema |
|---|---|---|
| Segundos | Encaixar o próximo prédio no melhor lugar | Adjacência com prévia ao vivo |
| Minutos | Vencer a próxima horda; abrir o próximo anel de terra | Hordas (força 8 × 1,4^nível); anéis 3 → 5 |
| Horas | Prédios até o nível 10; coleção de heróis; primeira Ascensão (~1 h) | Níveis (custo ×2,5), recrutamento, Coroas = ⌊√(ouro da rodada / 10⁶)⌋ |
| Dias | Sequência diária; missões; passe de temporada | Recompensa de 7 dias, 3 missões/dia, 30 níveis × 300 XP |
| Semanas | Temporada nova muda as regras | Rotação Fundação → Guerra → Expansão → Catástrofe (28 dias) |

**Regras de ritmo** (validadas com `npm run simulate`): 10 prédios em < 2 min · anel 3 em 5–15 min · 1ª Coroa perto de 1 h · mapa inteiro em 3–6 h sem ascender · passe completo em 2–3 semanas de ~1 h/dia.

**Desbloqueio gradual** (meta da Fase 3): começar com mapa + paleta + Reino; Heróis aparece na 1ª horda; Temporada aos 10 min; Legado quando a 1ª Coroa estiver perto; Social com 10 prédios.

## 5. Estilo visual

| Camada | Fonte | Regras |
|---|---|---|
| Mundo (terreno, prédios, natureza, unidades) | **Kenney — Medieval RTS** (CC0), PNG 128 px (Retina) | Top-down, vetor plano, contorno escuro suave. Um prédio = um tile. Sem misturar com outro pacote de mundo |
| Interface (painéis, botões, barras) | **Kenney — UI Pack** (CC0) | Cantos arredondados, plano, sem gradiente pesado |
| Ícones (recursos, ações, heróis, conquistas) | **game-icons.net** (CC BY 3.0) | SVG de cor única, tingido com a paleta; nunca dentro do mapa |
| Texto | **Nunito** (OFL), 400 no corpo e 800 em títulos e números | Tamanho mínimo de 14 px; escala configurável. Kenney Future foi testada e descartada: o R estilizado prejudica a leitura |

**Paleta** (derivada do Medieval RTS): grama `#3fae5a` · terra `#c8834a` · pedra `#9aa3a8` · água `#7cc6f0` · madeira `#8a5a33` · telhado `#e0694f` · creme `#f3e3c0` · tinta escura `#2b2a33` · dourado de destaque `#f2b632`.

**Proibido**: emoji (varredura automática em `npm test`), fontes de CDN, ícones desenhados em CSS, pixel art misturado ao vetor.

**Animação**: hélice do moinho gira; prédios "pulam" ao serem construídos (escala 0,8 → 1,1 → 1); partículas de recurso subindo; tremor e flash podem ser desligados (movimento reduzido).

## 6. Estilo sonoro

| Evento | Fonte |
|---|---|
| Clique, abrir e fechar painel | Kenney Interface Sounds (CC0) |
| Moedas, baú, coletar | Kenney RPG Audio (CC0) |
| Construir, melhorar | Kenney Impact Sounds (CC0) |
| Vitória, derrota, nível do passe, herói raro | Kenney Music Jingles (CC0), mesma família de timbre |
| Música ambiente em loop | RandomMind, "Medieval: Minstrel Dance (loop)" (CC0, download manual via EXECUTAR.md) |

Volumes separados para música e efeitos. A música começa só depois do primeiro gesto do jogador e faz *ducking* (abaixa) nas fanfarras.

## 7. Interface

- **Telas**: carregamento → menu principal (Continuar, Novo reino, Opções, Créditos) → jogo. `Esc` abre o menu de jogo (Opções, Créditos, Salvar, Voltar ao menu).
- **Jogo**: HUD superior (recursos, população, felicidade, defesa × próxima horda), paleta à esquerda, mapa no centro, abas à direita. No celular, tudo vira coluna e a construção usa toque duplo.
- **Toda informação de hover precisa existir no toque** (painel do tile ou toque longo).
- **Acessibilidade**: volumes separados, movimento reduzido, escala de fonte, alto contraste, teclado no mapa (setas + Enter) e atalhos remapeáveis.

## 8. Persistência

- Save em `localStorage` (`reino-de-bolso:save`), versionado (`SAVE_VERSION`) com migração em `src/core/state.js#migrate`. **Toda mudança de formato aumenta a versão e ganha teste de migração.**
- Autosave a cada 10 s, ao ocultar a aba e ao fechar; backups em rodízio; cópia de segurança se o save estiver corrompido; exportar/importar.

## 9. Fora do escopo (por enquanto)

Multiplayer em tempo real, dinheiro real, 3D, mapas maiores que 12×12. Ver [ROADMAP](docs/ROADMAP.md).
