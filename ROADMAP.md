# Roadmap

O que ficou de fora da versão 0.7.0, **em ordem de impacto** (o que mais muda a experiência ou o futuro do jogo vem primeiro). Cada item diz por que importa e o tamanho aproximado do trabalho.

| # | Item | Por que importa | Esforço |
|---|---|---|---|
| 1 | **Música ambiente** | Hoje só há efeitos e fanfarras; um idle fica aberto por horas e o silêncio pesa. O código já toca a faixa, só falta o arquivo (licença precisa ser conferida por uma pessoa) | Minutos: ver [EXECUTAR.md](EXECUTAR.md), passo 3 |
| 2 | **Teste com 10 jogadores reais + telemetria opcional** | Tudo o que sabemos do ritmo vem do simulador e de uma partida com bot. Funil do tutorial, D1/D7 e tempo de sessão dizem onde as pessoas desistem | 1 semana |
| 3 | **Ouro sobrando no meio do jogo** | Na partida de novato, o ouro chega a 1.400 enquanto a madeira trava em 10–40: falta um uso para ouro que alivie a madeira (ex.: mercado que compra madeira, ou serraria mais barata em ouro) | 1–2 dias + simulação |
| 4 | **Notificações opcionais do navegador** | "Expedição pronta" e "armazém cheio" trazem o jogador de volta, que é o que segura um idle | 2 dias |
| 5 | **Página na Steam e lista de desejos** | Valida o negócio antes de investir mais (meta de 7.000 listas, ver [MODELO-DE-NEGOCIO](docs/MODELO-DE-NEGOCIO.md)) | 1 semana (trailer + GIFs) |
| 6 | **i18n (PT-BR, depois EN e ES)** | Multiplica o público possível; os textos já estão concentrados em `src/data/` e `src/core/game.js` | 3–5 dias |
| 7 | **Social real** | Visitas, ranking por temporada e trocas entre jogadores reais (API mínima em Cloudflare Workers + D1) | 2–3 semanas |
| 8 | **Empacotamento para Steam** | Tauri, save em arquivo + Steam Cloud, conquistas Steam mapeadas de `ACHIEVEMENTS` | 2 semanas |
| 9 | **Prédios por nível** | Taverna e quartel já trocam de sprite nos níveis 5 e 10 (`stages` em `src/ui/sprites.js`); falta fazer o mesmo com os outros prédios. O KayKit tem variações que servem (castelo, quartel, torre com catapulta, casa B) e cada prédio vem em 4 cores | 2 dias |
| 10 | **Transições de terreno** | Bordas suaves entre água e grama. O KayKit tem margens de rio e costa em hexágono, que não servem direto; seria preciso desenhar as bordas no próprio render | 2–3 dias |
| 11 | **Ambiência por temporada** | Som de vento, chuva ou batalha conforme a temporada | 1 dia + busca de assets |
| 12 | **Conteúdo pós-lançamento** | Novas temporadas (Inverno Eterno, Festival, Praga), biomas (deserto, ilha), prédios 2×2, heróis com habilidade ativa, modo desafio com mapa fixo | contínuo |
| 13 | **Co-op leve (2–4 reinos vizinhos)** | Reinos de amigos dividindo fronteira e bônus de adjacência; depende do item 7 | 1 mês+ |

## Já entregue

- **0.1.0**: protótipo completo (mapa, 15 prédios, hordas, heróis, temporadas, Ascensão, social simulado, offline, testes, simulador).
- **0.9.0**: Quartel para treinar heróis, taverna que barateia recrutas e abre vagas no Conselho, e sprites por nível (começando pela taverna e pelo quartel).
- **0.7.0**: arte do mapa trocada pelo KayKit Medieval Hexagon Pack (prédios e natureza com volume e sombra); moradores continuam andando.
- **0.6.0**: tela de estatísticas ao Ascender, com recordes e histórico das rodadas.
- **0.5.0**: vida da vila (moradores com profissão, rotina e sprite por ofício; sem emprego dormem na rua).
- **0.4.0**: desfazer a última construção (5 s, custo devolvido por inteiro) e README voltado para quem joga.
- **0.3.0**: revisão de código, tema visual novo, melhorias de UX e de desempenho. Ver [docs/REVISAO-0.3.md](docs/REVISAO-0.3.md).
- **0.2.0**: zero emoji, arte e som reais com licença registrada, save v2 com migração e backups, menus completos, acessibilidade, desbloqueio gradual, hordas com direção. Detalhes no [CHANGELOG](CHANGELOG.md).
