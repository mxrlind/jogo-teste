# Roadmap

O que ficou de fora da versão 0.2.0, **em ordem de impacto** (o que mais muda a experiência ou o futuro do jogo vem primeiro). Cada item diz por que importa e o tamanho aproximado do trabalho.

| # | Item | Por que importa | Esforço |
|---|---|---|---|
| 1 | **Música ambiente** | Hoje só há efeitos e fanfarras; um idle fica aberto por horas e o silêncio pesa. O código já toca a faixa, só falta o arquivo (licença precisa ser conferida por uma pessoa) | Minutos: ver [EXECUTAR.md](EXECUTAR.md), passo 3 |
| 2 | **Teste com 10 jogadores reais + telemetria opcional** | Tudo o que sabemos do ritmo vem do simulador e de uma partida com bot. Funil do tutorial, D1/D7 e tempo de sessão dizem onde as pessoas desistem | 1 semana |
| 3 | **Ouro sobrando no meio do jogo** | Na partida de novato, o ouro chega a 1.400 enquanto a madeira trava em 10–40: falta um uso para ouro que alivie a madeira (ex.: mercado que compra madeira, ou serraria mais barata em ouro) | 1–2 dias + simulação |
| 4 | **Desfazer a última construção (5 s)** | O erro mais comum de iniciante é clicar no tile errado; demolir devolve só parte do custo | 1 dia |
| 5 | **Tela de estatísticas ao Ascender** | Fecha a rodada com sensação de conquista (tempo, ouro total, melhor combo) e motiva a próxima | 1 dia |
| 6 | **Notificações opcionais do navegador** | "Expedição pronta" e "armazém cheio" trazem o jogador de volta, que é o que segura um idle | 2 dias |
| 7 | **Página na Steam e lista de desejos** | Valida o negócio antes de investir mais (meta de 7.000 listas, ver [MODELO-DE-NEGOCIO](docs/MODELO-DE-NEGOCIO.md)) | 1 semana (trailer + GIFs) |
| 8 | **i18n (PT-BR, depois EN e ES)** | Multiplica o público possível; os textos já estão concentrados em `src/data/` e `src/core/game.js` | 3–5 dias |
| 9 | **Social real** | Visitas, ranking por temporada e trocas entre jogadores reais (API mínima em Cloudflare Workers + D1) | 2–3 semanas |
| 10 | **Empacotamento para Steam** | Tauri, save em arquivo + Steam Cloud, conquistas Steam mapeadas de `ACHIEVEMENTS` | 2 semanas |
| 11 | **Prédios por nível** | Hoje o nível aparece como número; trocar o sprite em níveis 5 e 10 deixa o crescimento visível. O pacote Medieval RTS tem variações que servem | 2 dias |
| 12 | **Transições de terreno** | Bordas suaves entre água, grama e pedra. O Medieval RTS tem tiles de borda; falta a lógica de escolha (autotile) | 2–3 dias |
| 13 | **Ambiência por temporada** | Som de vento, chuva ou batalha conforme a temporada | 1 dia + busca de assets |
| 14 | **Conteúdo pós-lançamento** | Novas temporadas (Inverno Eterno, Festival, Praga), biomas (deserto, ilha), prédios 2×2, heróis com habilidade ativa, modo desafio com mapa fixo | contínuo |
| 15 | **Co-op leve (2–4 reinos vizinhos)** | Reinos de amigos dividindo fronteira e bônus de adjacência; depende do item 9 | 1 mês+ |

## Já entregue

- **0.1.0**: protótipo completo (mapa, 15 prédios, hordas, heróis, temporadas, Ascensão, social simulado, offline, testes, simulador).
- **0.2.0**: zero emoji, arte e som reais com licença registrada, save v2 com migração e backups, menus completos, acessibilidade, desbloqueio gradual, hordas com direção. Detalhes no [CHANGELOG](CHANGELOG.md).
