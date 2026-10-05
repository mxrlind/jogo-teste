# 🗺️ Roadmap

Seguindo a pesquisa: *"dá para começar como um jogo extremamente simples e ir transformando em uma plataforma, em vez de construir a plataforma inteira no primeiro dia."*

## ✅ v0.1: Protótipo jogável (atual)
- [x] Mapa 12×12 por semente, 5 terrenos, 4 anéis de expansão, limpeza de terreno
- [x] 15 construções com adjacência positiva/negativa, níveis 1–10, mover e demolir
- [x] População, trabalho, comida, felicidade e armazenamento
- [x] Invasões escaláveis com aviso, proteção de novato e teto de saque
- [x] 16 heróis, estrelas, Conselho e 4 tipos de expedição
- [x] 6 eventos relâmpago e baú do mercador
- [x] Temporadas em rotação, passe de 30 níveis, missões diárias e sequência de 7 dias
- [x] Ascensão + Árvore de Legado (9 talentos)
- [x] Identidade (nome, estandarte, emblema, título) e 24 conquistas
- [x] Ranking com rivais, visitas, saudações, trocas e código do reino
- [x] Progresso offline com resumo
- [x] Tutorial opcional, sons sintetizados, partículas, layout para celular
- [x] Testes do motor e simulador de balanceamento
- [x] Documentação completa

## 🔜 v0.2: Validação (2–3 semanas)
- [ ] Publicar a demo no itch.io
- [ ] Telemetria anônima e opcional (funil do tutorial, D1/D7, tempo de sessão)
- [ ] Rodada com 10 testadores e ajuste de ritmo
- [ ] Notificação do navegador opcional: "expedição pronta" / "armazém cheio"
- [ ] Tela de estatísticas da rodada ao Ascender
- [ ] Desfazer última construção (5 s)

## 🎨 v0.3: Identidade visual (1–2 meses)
- [ ] Sprite atlas pixel art 32×32 (terrenos com transições, prédios por nível)
- [ ] Pequenas animações (fumaça na serraria, moinho girando, aldeões andando)
- [ ] Trilha sonora lo-fi medieval + ambiência por temporada
- [ ] Fontes locais (offline total)
- [ ] i18n (PT-BR → EN → ES)

## 🌐 v0.4: Social real
- [ ] API mínima (Cloudflare Workers + D1): publicar reino, ranking por temporada
- [ ] Visitas e saudações entre jogadores reais
- [ ] Desafio de layout semanal com ranking próprio
- [ ] Guildas assíncronas com meta coletiva

## 🚀 v1.0: Steam
- [ ] Empacotamento Tauri, save em arquivo + Steam Cloud
- [ ] Conquistas Steam (mapear `ACHIEVEMENTS`), Rich Presence
- [ ] Página "Coming Soon" com trailer e GIFs (meta: 7.000 listas de desejos)
- [ ] Demo no Steam Next Fest
- [ ] Lançamento a US$ 3–5

## 📅 Plano de conteúdo pós-lançamento (cauda longa)

| Atualização | Conteúdo |
|---|---|
| Temporada 5+ | Novos temas: *Inverno Eterno* (comida −30%, lareiras), *Festival* (eventos o tempo todo), *Praga* (prédios adoecem; templos curam) |
| Biomas | Mapas de deserto (oásis = água rara), ilha (rio por todos os lados), montanha |
| Prédios de 2×2 | Castelo, catedral, porto, com adjacência ampliada |
| Heróis com habilidade ativa | Um uso por invasão (ex.: Dragão queima a horda) |
| Modo desafio | Mapas fixos com metas ("maior ouro/s com 25 prédios") e ranking |
| Co-op leve (2–4) | Reinos vizinhos de amigos que compartilham fronteira e bônus de adjacência entre si. É o padrão "co-op com amigos" mais forte de 2025, segundo a pesquisa |
