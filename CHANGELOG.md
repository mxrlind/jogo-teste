# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.12.0] — 2026-10-07
### Adicionado
- **Cais de Pesca** (primeira parte da zona portuária, libera com 3 construções): só funciona encostado num lago e dá 1,4 de comida por segundo, +40% por tile de água vizinho e +15% com armazém ao lado. Inspirado no cais de pesca do Banished.
- Um **barquinho de pesca** fica indo e voltando na água ao lado de cada cais que está funcionando, e um morador novo, o **Pescador**, trabalha no cais e leva o peixe para o armazém.
- Sprites do cais e do barco gerados por `tools/render-kaykit.mjs` com peças do KayKit Medieval Hexagon (CC0). O pacote não tem barco nem tábuas, então o render agora aceita peças simples (`box` e `hull`) feitas na hora.

### Corrigido
- O Código do Reino quebrava com uma Escadaria no mapa (ela não tinha letra). Escadaria e cais ganharam letras no fim da lista, e códigos antigos continuam válidos.
- O aviso de prédio sem o vizinho obrigatório agora diz "Só funciona ao lado de ...", que serve para prédio de qualquer gênero.

## [0.11.0] — 2026-10-07
### Adicionado
- **Subsolo** no estilo Dwarf Fortress. A **Escadaria** (prédio novo, libera com 5 construções) abre o primeiro nível bem embaixo dela, e botões no canto do mapa trocam entre a superfície e os níveis descobertos. Toda a geração de superfície continua igual; só a pedra ganha a parte de baixo.
- **Três níveis**, cada um com névoa: só se vê o que está encostado numa galeria. **Galerias** (veios de ouro e aquíferos), **Cavernas** (cavernas naturais, gemas) e **Profundezas** (magma, mais ouro e gemas). Cavar custa ouro, que sobe a cada tile cavado e a cada nível, e rende pedra, ouro ou gemas conforme o tile. Encostar numa caverna revela a caverna inteira de uma vez. Uma escada cavada numa galeria desce para o nível de baixo.
- **Salas** construídas no chão cavado, sem usar moradores: **Pedreira Funda** (pedra, +15% por parede vizinha), **Adega** (mais armazém de comida e +5% de comida por nível, como o porão do Going Medieval), **Garimpo** (ouro, precisa de um veio de ouro ao lado, +50% por veio a mais), **Horta de Fungos** (comida, só em caverna, +25% por aquífero vizinho) e **Forja de Magma** (+10% de toda a produção por nível, precisa de magma ao lado). Cada uma sobe até o nível 5 (a forja até o 3).
- Saves antigos ganham o subsolo do próprio mapa, ainda fechado.
- Sprites do subsolo e da Escadaria renderizados do **KayKit Dungeon Remastered** e do Medieval Hexagon (ambos CC0) por `tools/render-kaykit.mjs`, que agora aceita a pasta do Dungeon como segundo argumento e `--only=` para gerar só alguns sprites.

## [0.10.0] — 2026-10-07
### Adicionado
- **Muralhas que se ligam sozinhas**: cada muralha olha para as vizinhas (muralhas e torres) e escolhe o sprite certo: deitada, em pé, canto, T ou cruz. São 15 variantes geradas por `tools/render-kaykit.mjs` com a peça reta do KayKit (CC0).
- **Muralha de lado**: uma muralha atravessada no caminho da horda conta inteira; virada de lado para ela, conta só metade. Cantos e cruzamentos contam inteiros, e muralha sozinha também. O painel do tile mostra "muralha de lado" quando for o caso.

## [0.9.0] — 2026-10-07
### Adicionado
- **Quartel** (prédio novo, libera com 10 construções): treina heróis com ouro e comida. Cada treino leva 2 min × o nível atual e sobe o herói 1 nível; cada nível dá +10% de bônus e de poder, somado às estrelas. O herói chega até o nível do quartel mais alto + 1 (máximo 10), e cada quartel treina um herói por vez. Dá para acelerar com gemas. Gosta de muralhas e torres vizinhas.
- **Taverna com níveis que importam**: cada nível acima do 1 deixa o recrutamento com ouro 4% mais barato (até 36% no nível 10), e os níveis 5 e 10 abrem uma vaga a mais no Conselho cada.
- **Prédios crescem no mapa**: taverna e quartel ganham sprite novo nos níveis 5 e 10 (barris, caixotes, armas e estandartes do KayKit, CC0).
- Novo morador: o Soldado, que trabalha no quartel.

### Mudou
- Treino em andamento na hora da Ascensão vira nível na hora. Se o Conselho perder vagas (taverna vendida, nova rodada), os últimos heróis a entrar saem.
- O Código do Reino usa uma ordem fixa de letras, para códigos antigos continuarem válidos com o prédio novo.

## [0.8.0] — 2026-10-07
### Adicionado
- **Plantar árvores**: num campo livre, o botão "Plantar árvores" (25 de ouro) cria uma muda. Ela cresce sozinha e em 3 minutos vira floresta, que dá madeira ao ser limpa e +40% para serrarias vizinhas. Na metade do caminho a muda vira um grupo de árvores jovens. O tempo conta também com o jogo fechado. Ideia tirada do Forester do Banished: ouro sobrando vira madeira.
- Arrancar a própria muda é de graça e não conta para a missão "Limpe terrenos".
- Sprites `sapling-1` e `sapling-2`, renderizados do KayKit Medieval Hexagon Pack (CC0) por `tools/render-kaykit.mjs`.
- **Rosa dos ventos** no canto superior direito do mapa (desenho próprio em SVG, nas cores da interface). A ponta do lado de onde vem a próxima horda fica vermelha e pulsa quando a horda é anunciada; tocar nela explica a defesa por lado.

## [0.7.0] — 2026-10-07
### Mudou
- **Arte nova no mapa**: prédios, árvores, rochas, montanhas e água agora vêm do **KayKit Medieval Hexagon Pack** (Kay Lousberg, CC0 1.0). Os modelos 3D foram renderizados como imagens 2D: o jogo continua um canvas 2D, sem 3D rodando. Os prédios ganharam fachada, volume e sombra e sobem para o tile de cima; natureza e prédios são desenhados linha a linha, de trás para a frente.
- A hélice do moinho continua girando, agora achatada na mesma perspectiva do prédio.
- Miniaturas da paleta, do painel do prédio e da tela de Ascensão usam recortes dos novos sprites. Logo e ícone do app viraram o castelo do KayKit.
- **Moradores, invasores e carroça do mercador continuam os do Kenney Medieval RTS**, com a mesma rotina e animação.
- Jardim, Pedreira e Estátua do Fundador não existem prontos no KayKit: são montagens de modelos do pacote (árvores, plantas e cerca; rochedo, pedras e carrinho; base de torre com bandeira). A Fogueira virou o poço do pacote.

### Adicionado
- `tools/render-kaykit.mjs`: gera os sprites a partir dos modelos GLTF do KayKit (instruções no cabeçalho).

## [0.6.0] — 2026-10-06
### Adicionado
- **Tela de estatísticas ao Ascender**: abre logo depois da Ascensão com as Coroas ganhas (contando até o valor), duração da rodada e tempo com o jogo aberto, ouro da rodada, ouro por segundo no fim, Poder do Reino, construções e melhorias, prédios no mapa (maior nível e anel), hordas vencidas e perdidas, expedições, carroças e o **melhor combo** (o prédio com maior bônus de vizinhos).
- **Recordes**: a partir da 2ª rodada, cartões que bateram a melhor marca anterior (ouro, ouro por segundo, combo, hordas vencidas, Poder) ganham o selo "Recorde".
- **Próxima rodada**: a tela mostra os talentos que dá para comprar com as Coroas guardadas e leva direto à aba Legado.
- **Rodadas anteriores** na aba Legado: as últimas 10 rodadas, com o resumo de cada uma.
- Os números da rodada vêm de uma foto das estatísticas tirada no início de cada rodada. Saves de antes desta versão não têm essa foto: na primeira Ascensão depois da atualização, os números que dependem dela não aparecem (o jogo avisa), em vez de mostrar valores errados.

### Mudou
- **Moradores em "stop motion"**: andam a cerca de metade da velocidade e se movem em quadros de 0,2 s (5 por segundo), parados entre um quadro e outro. Cada quadro alterna a pose: pé no chão e no ar ao andar, ferramenta levantada e batendo ao trabalhar; o "z z z" de quem dorme também sobe em degraus. A rotina passou a ser calculada 5 vezes por segundo em vez de a cada frame.

## [0.5.0] — 2026-10-06
### Adicionado
- **Vida da vila**: os moradores do mapa agora têm profissão e rotina, com sprite próprio do Medieval RTS por ofício e a ferramenta balançando enquanto trabalham.
  - Lavrador colhe na fazenda (foice) e leva comida ao armazém, moinho ou mercado.
  - Lenhador corta na floresta vizinha (machado), serra na serraria e leva a madeira ao armazém.
  - Pedreiro e mineira usam a picareta na rocha ou montanha e levam pedra e ouro ao armazém.
  - Moleira busca grão na fazenda; mercadora busca comida e entrega ouro nas casas; intendente recolhe dos produtores; taverneiro e sacerdote atendem e visitam as casas.
  - Guarda patrulha entre torres e muralhas e, com a horda anunciada, corre para a borda de onde ela vem.
  - De tempos em tempos cada um volta para descansar em casa.
- **Sem emprego, dormem na rua**: quem sobra além das vagas de trabalho aparece deitado ao lado das casas, com "z" subindo. É um jeito visual de ver que falta prédio para tanta gente.
- Quem trabalha onde segue a mesma regra da economia (fazendas e moinhos primeiro). Caminhos de verdade pela grama, parando na porta de cada prédio, com sombra e o recurso carregado acima da cabeça.
- Ícone de picareta (game-icons.net, lorc, CC BY 3.0).

### Desempenho
- Até 32 trabalhadores e 8 dormindo visíveis; desenhar todos custa cerca de 0,6 ms por frame. Desligado junto com "Partículas" ou "Reduzir movimento".

## [0.4.0] — 2026-10-06
### Adicionado
- **Desfazer a última construção**: por 5 segundos depois de construir aparece "no lugar errado? Desfazer", com barra de tempo. O custo volta por inteiro, junto com a estatística, o progresso de missão e o XP da obra. Atalho Z (remapeável em Opções).
- Prêmios automáticos que a obra disparou (passo do tutorial, conquista) voltam junto. A janela fecha antes dos 5 s se o jogador já resgatou algo que a obra liberou (missão, nível do passe), se já gastou o prêmio automático ou se o prédio foi melhorado, movido ou demolido.

### Mudou
- README voltado para quem joga: link do jogo, como jogar, controles, recursos, opções, save e créditos. O conteúdo de desenvolvimento foi para [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).

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
