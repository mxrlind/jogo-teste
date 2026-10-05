# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] — 2026-10-05
### Adicionado
- Primeiro protótipo jogável completo do **Reino de Bolso**: mapa com adjacência, economia, invasões, heróis, expedições, eventos relâmpago, baús, temporadas com passe e missões diárias, recompensa diária, Ascensão com Árvore de Legado, identidade, conquistas, social assíncrono (rivais e código do reino) e progresso offline.
- Interface responsiva (PC e celular), sons sintetizados e efeitos visuais.
- Testes do motor (`npm test`) e simulador de balanceamento (`npm run simulate`).
- Documentação: GDD, Pesquisa → Design, Balanceamento, Arquitetura, Modelo de Negócio e Roadmap.

### Balanceamento (encontrado pelo simulador antes do lançamento)
- Armazém escala com nível²; limites base maiores; custos de anel revistos.
- Pedreira 0,6/s e pedra inicial 20.
- Perda em invasão 15%, com teto de 2 min de produção e proteção de novato.
- Felicidade limitada a 100; nível máximo 10 com custo ×2,5; XP de temporada recalibrado.
