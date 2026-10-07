# Reino de Bolso — GDD curto

> Documento-âncora para manter o jogo coerente entre sessões. Se uma mudança contradiz este arquivo, atualize este arquivo **antes** de mudar o jogo.
> Detalhes por sistema: [docs/ESPECIFICACAO-SISTEMAS.md](docs/ESPECIFICACAO-SISTEMAS.md) · Fórmulas: [docs/BALANCEAMENTO.md](docs/BALANCEAMENTO.md) · Diagnóstico: [docs/DIAGNOSTICO.md](docs/DIAGNOSTICO.md) · Versão: 0.2.0 (save v2)

## 1. Conceito

**Idle tycoon 2D em que a posição de cada prédio importa.** Você recebe um terreno 12×12 com uma casa e uma fazenda e o transforma num reino. Cada prédio ganha ou perde produção conforme os 4 vizinhos (água, floresta, montanha, outros prédios). O reino produz sozinho, inclusive offline. Hordas atacam por um lado anunciado, heróis colecionáveis dão bônus, e a Ascensão recomeça tudo num mapa novo com bônus permanentes.

- **Plataforma**: navegador (PC e celular, instalável como PWA); depois, Steam empacotado.
- **Stack**: HTML + CSS + JavaScript (ES modules), canvas 2D, sem build e sem dependências em tempo de execução.
- **Sessão**: 2–5 min (coletar, construir, sair) ou 30–120 min (otimizar).
- **Referências**: Islanders (pontuação por proximidade, mostrada ao vivo), Kittens Game (armazenamento como gargalo), AdVenture Capitalist (prestígio e "quando resetar"), Clash of Clans (base e defesa por layout), Cookie Clicker (recompensa surpresa).

## 2. Pilares

1. **O lugar importa**: toda feature nova deve criar uma decisão de *onde*, não só de *quando*. Hoje: adjacência, limpar ou não um terreno, e de que lado defender.
2. **Só mais uma**: progresso visível a cada retorno; nunca esperar sem ter o que decidir.
3. **Mostre antes de cobrar**: bônus de cada vizinho, +X/s, custo e "vale ascender" aparecem antes da confirmação.
4. **Justo**: nada se compra com dinheiro real; derrota dói, mas não destrói (proteção de novato e teto de saque).
5. **Um estilo só**: mundo low poly com luz e sombra (KayKit, renderizado em 2D), interface plana (Kenney UI Pack), ícones em silhueta (game-icons). Zero emoji.

## 3. Core loop

> Posicionar prédios para criar sinergias → o reino produz sozinho → gastar em prédios, níveis, terra e defesa do lado anunciado → quando o crescimento desacelera, ascender.

```
  [Escolher prédio] -> [Prévia: vizinhos +X%, ganho +Y/s] -> [Construir / melhorar / mover] -> [Produção sobe]
          ^                                                                                        |
          |          +--------------------+------------------+-----------------+                  |
          |          v                    v                  v                 v                  |
          |   [Horda anunciada:     [Carroça do        [Heróis e          [Limite de             |
          |    reforçar um lado]     mercador/evento]   expedições]        armazém]               |
          +------------------------------------------------------------------------------------+
                                     [Mapa cheio, renda em platô] -> [Ascensão: Coroas -> talentos -> mapa novo]
```

## 4. Progressão

| Prazo | Meta do jogador | Sistema |
|---|---|---|
| Segundos | Encaixar o próximo prédio no melhor lugar | Adjacência com prévia ao vivo e +X/s |
| Minutos | Vencer a próxima horda; abrir o próximo anel | Hordas (força 8 × 1,4^nível, lado anunciado); anéis 3 → 5 |
| Horas | Prédios até o nível 10; heróis; 1ª Ascensão | Custo ×2,5 por nível; Coroas = ⌊√(ouro da rodada / 10⁶)⌋ |
| Dias | Sequência diária; missões; passe | Recompensa de 7 dias, 3 missões/dia, 30 níveis × 300 XP |
| Semanas | A temporada muda as regras | Fundação → Guerra → Expansão → Catástrofe (28 dias cada) |

**Desbloqueio gradual**: começa com mapa, paleta e as abas Reino e Perfil. Heróis abre depois das primeiras construções (o tutorial leva até lá), Temporada com 10 prédios ou 8 minutos, Social com 12 prédios, Legado perto da 1ª Coroa. Prédios liberam pela quantidade de construções.

**Ritmo medido** (`npm run simulate`, 3 sementes): 10 prédios em 40 s · 1ª horda vencida aos 6 min · anel 3 entre 6 e 26 min · anel 4 entre 16 min e 2h36 · 1ª Coroa entre 44 min e 1h20 · mapa inteiro entre 3h30 e 6h30.

## 5. Estilo visual

| Camada | Fonte | Regras |
|---|---|---|
| Mundo (prédios, natureza, chão) | **KayKit Medieval Hexagon Pack** (CC0), modelos 3D renderizados em PNG por `tools/render-kaykit.mjs` | Vista de cima com a altura subindo na tela (projeção oblíqua, fator 0,7): o chão continua um quadrado do tile. Um prédio = um tile; o que é alto invade o tile de cima. Desenho linha a linha, de trás para a frente |
| Mundo (moradores, invasores, carroça) | **Kenney Medieval RTS** (CC0), PNG 128 px | Top-down, vetor plano. Ficam até haver personagens no estilo do KayKit |
| Interface (botões, caixas de seleção) | **Kenney UI Pack** (CC0), via `border-image` | Plano, cantos arredondados, com estados de hover, pressionado e desativado |
| Interface (painéis, cartões, HUD) | CSS com tokens em `styles.css` | Moldura escura (tinta) + superfícies de pergaminho + filete dourado. Sem `backdrop-filter` sobre o mapa (custaria um desfoque por frame) |
| Ícones (recursos, ações, heróis, conquistas) | **game-icons.net** (CC BY 3.0), SVG tingido por CSS mask | Silhueta de uma cor; dentro do mapa só como número flutuante e aviso |
| Texto | **Nunito** (OFL), 400 no corpo e 800 em títulos e números | Mínimo 14 px; escala ajustável. Kenney Future foi testada e descartada: o R estilizado prejudica a leitura |
| Overlays desenhados (seleção, prévia, rótulos, nível) | Primitivas do canvas na paleta | Só realces funcionais, nunca "arte" |

**Paleta**: tinta `#2b2a33` · papel `#f4f1ea` · creme `#f3e3c0` · grama `#2e8b47` · dourado `#f2b632` · vermelho `#b8412f` · azul `#1f6fb2`. Raridades: comum `#6f7782`, raro `#2f7cc0`, épico `#7a52c4`, lendário `#b9820e`.

**Lacunas do pacote e soluções**: o KayKit é feito para hexágonos, então só usamos prédios, natureza e adereços; o chão é cor lisa renderizada na mesma luz (a grama e a água dos tiles hexagonais saem com a cor errada vistas de cima). Jardim, Pedreira e Estátua do Fundador são montagens de modelos do pacote; a Fogueira é o poço. Personagens só existem na versão paga do pacote, por isso os moradores seguem no Medieval RTS.

**Animação**: hélice do moinho, "pop" ao construir, moradores com profissão e rotina (sprite e ferramenta por ofício; sem emprego dormem na rua; de folga passeiam entre pontos de encontro e conversam) em ritmo de stop motion, 5 quadros por segundo com duas poses, invasores marchando pelo lado anunciado, carroça balançando, partículas. Tudo respeita "Reduzir movimento", menos os moradores, que têm opção própria (o sistema do aparelho liga "Reduzir movimento" sozinho, e a vila não pode sumir por isso).

**Proibido**: emoji (varredura em `npm test`), fontes ou ícones de CDN, pixel art misturado ao vetor, ícones desenhados em CSS.

## 6. Estilo sonoro

| Evento | Fonte |
|---|---|
| Cliques, abas, abrir e fechar, erro, confirmação | Kenney Interface Sounds (CC0) |
| Moedas, carroça, livro (recrutar), corte (limpar) | Kenney RPG Audio (CC0) |
| Construir (madeira), pedreira e mina (mineração), sino da horda | Kenney Impact Sounds (CC0) |
| Vitória, derrota, nível, conquista, herói raro, Ascensão | Kenney Music Jingles, família Pizzicato (CC0), escolhidos pela direção da melodia |
| Música de fundo | 5 faixas CC0 em `assets/music/`: folk na vila, metal na horda e no subsolo, com botão para ligar e desligar |

Volumes separados; nada toca antes do primeiro gesto; a música abaixa durante fanfarras.

## 7. Interface

- **Telas**: carregamento (com progresso) → menu principal (Continuar, Novo reino, Como jogar, Opções, Créditos) → jogo. Esc abre o menu do jogo.
- **Jogo**: HUD (recursos, moradores, felicidade, defesa × horda com lado e tempo), paleta, mapa, abas. No celular, tudo vira coluna, a dica de construção fica no rodapé e construir usa toque duplo.
- **Regra**: toda informação de hover precisa existir no toque (chips do HUD e prédios bloqueados explicam ao tocar).

## 8. Persistência

- Save em `localStorage` (`reino-de-bolso:save`) dentro de um envelope com checksum; versão em `SAVE_VERSION` com migração em `src/core/state.js#migrateWithSettings`. **Toda mudança de formato aumenta a versão e ganha teste de migração.**
- Backups em rodízio (3, a cada 5 min); save danificado é guardado à parte e o jogo recupera o backup mais recente.
- Preferências do dispositivo (volume, acessibilidade, teclas) ficam separadas em `reino-de-bolso:config`.

## 9. Fora do escopo (por enquanto)

Multiplayer em tempo real, dinheiro real, 3D, mapas maiores que 12×12. Ver [ROADMAP.md](ROADMAP.md).
