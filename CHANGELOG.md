# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] — 2026-10-05
Saves da 0.1.0 continuam funcionando: são migrados automaticamente para o formato v2 na primeira abertura.

### Mudou: visual e som (regra "zero emoji, só assets reais")
- Todo emoji saiu do jogo e da documentação. `npm test` agora roda `tools/emoji-scan.js`, que falha se encontrar emoji, variation selector ou ZWJ.
- Mapa desenhado com sprites do **Kenney Medieval RTS** (CC0): terreno, 15 prédios, árvores, rochas, aldeões, invasores e a carroça do mercador.
- Interface com o **Kenney UI Pack** (CC0); ícones do **game-icons.net** (CC BY 3.0) tingidos por CSS; fonte **Nunito** (OFL) servida localmente.
- Sons sintetizados trocados por efeitos e fanfarras da Kenney (CC0). Volumes separados de música e efeitos; música em loop opcional (ver EXECUTAR.md).
- Fonte (decoração) virou **Fogueira** e o baú virou **carroça do mercador**, porque o pacote não tem fonte nem baú no mesmo estilo.
- Cada arquivo com autor, link e licença no `ASSETS.md`, gerado por `tools/build-assets-md.py`; os créditos do jogo mostram as mesmas atribuições.

### Adicionado
- Tela de carregamento, menu principal (com o mapa ao fundo), menu de jogo no Esc, Opções, Créditos, Como jogar e gerenciador de saves.
- Acessibilidade: tamanho do texto, alto contraste, reduzir movimento e remapeamento de todas as teclas.
- Teclado completo: cursor no mapa com setas e Enter, teclas 1–9 na paleta, U/M/Delete no prédio, T troca de aba.
- **Hordas com direção**: cada horda vem de um lado anunciado; defesa daquele lado conta 100% e do lado oposto 50%. Os invasores aparecem marchando naquela borda.
- **Desbloqueio gradual**: o jogo começa com as abas Reino e Perfil; Heróis, Temporada, Social e Legado aparecem conforme o reino cresce.
- Prévia de ganho (+X/s) antes de construir e melhorar; "melhorar ao máximo" e "melhorar tudo"; aviso de quando vale ascender.
- Ícone do app e manifest com sprites do jogo.

### Corrigido
- Save: envelope com checksum, 3 backups em rodízio, cópia separada de save danificado e recuperação automática do último backup. Códigos de exportação da 0.1.0 continuam aceitos.
- Preferências (volume, acessibilidade, teclas) saíram do save e ficam por dispositivo.
- Aba em segundo plano produz com eficiência total (antes caía para a taxa offline).
- Recompensa diária: "ontem" calculado pela data, sem quebrar no horário de verão.
- No celular, a prévia de construção não some mais ao levantar o dedo.
- Esc logo após construir não abre mais o menu sem querer.
- O tutorial pedia uma muralha ainda bloqueada: a muralha libera com 4 construções e o jogo começa com 25 de pedra.
- Números como "-0,0/s" não aparecem mais na prévia.
- Fome em espiral: com pouca comida, a população podia cair para 1 morador e o reino parar por mais de uma hora. Agora fazendas e moinhos recebem trabalhadores primeiro.
- Voltar ao menu principal e continuar gerava um erro no console (o mapa tentava desenhar enquanto estava oculto).

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
