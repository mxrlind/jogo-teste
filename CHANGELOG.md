# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.3.0] — 2026-10-06
Revisão de código, polimento visual e de UX. Nenhuma mecânica mudou; saves da 0.2.0 abrem sem migração. Detalhes e plano em [docs/REVISAO-0.3.md](docs/REVISAO-0.3.md).

### Mudou: visual
- Tema novo e coeso: moldura escura, painéis de pergaminho em CSS (camadas de sombra e filete dourado) no lugar do painel cinza do UI Pack; botões do UI Pack mantidos, agora com hover, pressionado e desativado distintos.
- HUD escuro com recursos em destaque; o número "pula" quando você ganha ou gasta de uma vez (recompensa, obra).
- Status da horda em duas linhas e em linguagem clara: "Horda pelo Norte · 5m 58s / Defesa 0 / 8 · vulnerável".
- Paleta: o que dá para construir vem primeiro; bloqueados ficam compactos, em ordem de desbloqueio, com o próximo destacado e o progresso ("2/3 obras").
- Mapa com moldura, seleção com cantoneiras douradas, prévia com cantos arredondados, onda ao construir e selo de nível com sombra.
- Abas, cartões, barras de progresso, missões, passe, Legado (números em destaque e níveis em "pips"), ranking (pódio), recompensa diária (ícones), revelação de herói (raios), toasts e modais redesenhados.
- Menu principal com vinheta e entrada animada; tela de carregamento com logo animada.

### Mudou: UX
- Missão incompleta mostra a recompensa como selo; o botão "Resgatar" só aparece quando dá para resgatar.
- Todo modal tem botão de fechar (menos a fundação do reino, que precisa de uma escolha).
- Esc encerra a visita a outro reino; escolher um prédio durante a visita volta ao seu reino.
- "Resgatar todas" no passe mostra um aviso só, não um por nível.
- Dica de construção fala em toque no celular e em mouse no PC.
- Toasts no centro, sem cobrir a paleta; texto de desenvolvedor saiu do menu principal.

### Corrigido
- Menu principal redesenhava o mapa de fundo a 60 fps (cerca de 2.700 desenhos por segundo, sob um desfoque em tela cheia). Agora desenha uma vez e de novo só ao redimensionar.
- Painel lateral parava de atualizar se o botão do mouse fosse solto fora da janela.
- Save também no `pagehide` (celulares nem sempre disparam `beforeunload`).
- Posição no ranking sempre verde: a classe colidia com a utilitária `.pos`; o pódio agora tem ouro, prata e bronze.
- Servidor local sem tipo MIME para `.woff2`, `.mp3` e `.webmanifest`.

### Desempenho
- Aldeões: lista de tiles livres em cache (antes era refeita a cada frame).
- Efeitos: array compactado no lugar, sem alocar um novo por frame.
- Sem `backdrop-filter` sobre o mapa animado.

### Removido
- Código morto: `fmtCost` (também estava quebrado), `plainCost`, `icon` e `RESOURCE_ICONS`.

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
