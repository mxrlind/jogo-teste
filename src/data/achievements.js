// Conquistas: cada uma dá gemas e, às vezes, um título (identidade).
// check(s, econ, heroes) recebe o estado, o resultado de computeEconomy e o catálogo de heróis.
// progress(s, econ, heroes) devolve [atual, meta] para a barra de "próxima conquista".
// kind: sem kind = essencial; 'secret' = aparece como "???" com uma dica até sair;
// 'shadow' = sombra (como no Cookie Clicker): não conta no total nem no bônus de produção.
// Cada conquista essencial ou secreta dá ACH_PROD_BONUS de produção para sempre.

export const ACH_PROD_BONUS = 0.01;

const countBuildings = (s) => s.grid.tiles.filter((t) => t.b).length;
const countOf = (s, id) => s.grid.tiles.filter((t) => t.b?.id === id).length;
const maxLvl = (s, id) => s.grid.tiles.reduce((m, t) => (t.b?.id === id && t.b.lvl > m ? t.b.lvl : m), 0);
const flag = (id) => (s) => !!s.flags?.[id];
const legendaries = (s, heroes) => Object.keys(s.heroes.owned).filter((id) => heroes[id]?.rarity === 'lendario').length;

export const ACHIEVEMENTS = [
  { id: 'primeira-pedra', name: 'Primeira Pedra', icon: 'build', desc: 'Construa seu primeiro prédio.', gems: 2, check: (s) => s.stats.built >= 1, progress: (s) => [s.stats.built, 1] },
  { id: 'vila', name: 'Vilarejo', icon: 'house', desc: 'Tenha 10 construções.', gems: 3, check: (s) => countBuildings(s) >= 10, progress: (s) => [countBuildings(s), 10] },
  { id: 'cidade', name: 'Cidade', icon: 'tab-social', desc: 'Tenha 25 construções.', gems: 5, title: 'Prefeito', check: (s) => countBuildings(s) >= 25, progress: (s) => [countBuildings(s), 25] },
  { id: 'metropole', name: 'Metrópole', icon: 'castle', desc: 'Tenha 50 construções.', gems: 10, title: 'Grão-Duque', check: (s) => countBuildings(s) >= 50, progress: (s) => [countBuildings(s), 50] },
  { id: 'populoso', name: 'Lotado', icon: 'people', desc: 'Alcance 50 moradores.', gems: 4, check: (s) => s.pop >= 50, progress: (s) => [Math.floor(s.pop), 50] },
  { id: 'formigueiro', name: 'Formigueiro', icon: 'people', desc: 'Alcance 150 moradores.', gems: 8, check: (s) => s.pop >= 150, progress: (s) => [Math.floor(s.pop), 150] },
  { id: 'rico', name: 'Bolso Cheio', icon: 'gold', desc: 'Ganhe 10 mil de ouro (vida toda).', gems: 3, check: (s) => s.stats.totalGold >= 1e4, progress: (s) => [s.stats.totalGold, 1e4] },
  { id: 'milionario', name: 'Milionário', icon: 'event-gold-rush', desc: 'Ganhe 1 milhão de ouro (vida toda).', gems: 8, title: 'Magnata', check: (s) => s.stats.totalGold >= 1e6, progress: (s) => [s.stats.totalGold, 1e6] },
  { id: 'bilionario', name: 'Tesouro do Dragão', icon: 'hero-dragon', desc: 'Ganhe 1 bilhão de ouro (vida toda).', gems: 25, title: 'Senhor do Ouro', check: (s) => s.stats.totalGold >= 1e9, progress: (s) => [s.stats.totalGold, 1e9] },
  { id: 'defensor', name: 'Defensor', icon: 'defense', desc: 'Vença sua primeira invasão.', gems: 2, check: (s) => s.stats.raidsWon >= 1, progress: (s) => [s.stats.raidsWon, 1] },
  { id: 'muralha-viva', name: 'Muralha Viva', icon: 'talent-walls', desc: 'Vença 10 invasões.', gems: 5, title: 'Guardião', check: (s) => s.stats.raidsWon >= 10, progress: (s) => [s.stats.raidsWon, 10] },
  { id: 'imbativel', name: 'Imbatível', icon: 'swords', desc: 'Vença 50 invasões.', gems: 12, title: 'Conquistador', check: (s) => s.stats.raidsWon >= 50, progress: (s) => [s.stats.raidsWon, 50] },
  { id: 'recrutador', name: 'Recrutador', icon: 'scroll', desc: 'Recrute 5 heróis.', gems: 3, check: (s) => s.stats.recruits >= 5, progress: (s) => [s.stats.recruits, 5] },
  { id: 'lenda', name: 'Lenda Viva', icon: 'star', desc: 'Tenha um herói Lendário.', gems: 10, title: 'Lendário', check: (s, e, heroes) => Object.keys(s.heroes.owned).some((id) => heroes[id]?.rarity === 'lendario') },
  { id: 'colecionador', name: 'Colecionador', icon: 'tab-heroes', desc: 'Tenha 10 heróis diferentes.', gems: 10, title: 'Colecionador', check: (s) => Object.keys(s.heroes.owned).length >= 10, progress: (s) => [Object.keys(s.heroes.owned).length, 10] },
  { id: 'explorador', name: 'Andarilho', icon: 'expedition', desc: 'Complete 10 expedições.', gems: 4, check: (s) => s.stats.expeditions >= 10, progress: (s) => [s.stats.expeditions, 10] },
  { id: 'arquiteto', name: 'Mestre de Obras', icon: 'upgrade', desc: 'Leve um prédio ao nível 10.', gems: 8, title: 'Mestre de Obras', check: (s) => s.grid.tiles.some((t) => t.b && t.b.lvl >= 10), progress: (s) => [s.grid.tiles.reduce((m, t) => Math.max(m, t.b?.lvl ?? 0), 0), 10] },
  { id: 'sinergia', name: 'Sinergia Perfeita', icon: 'hero-architect', desc: 'Tenha um prédio com +150% de adjacência.', gems: 6, title: 'Urbanista', check: (s, e) => e.tiles.some((t) => t && t.adjBonus >= 1.5) },
  { id: 'feliz', name: 'Reino Feliz', icon: 'heart', desc: 'Alcance 100 de felicidade.', gems: 5, check: (s, e) => e.happiness >= 100, progress: (s, e) => [Math.floor(e.happiness), 100] },
  { id: 'horizonte', name: 'Horizonte', icon: 'map', desc: 'Desbloqueie o mapa inteiro.', gems: 8, check: (s) => s.grid.ring >= 5, progress: (s) => [s.grid.ring, 5] },
  { id: 'ascensao', name: 'Renascido', icon: 'crowns', desc: 'Ascenda pela primeira vez.', gems: 10, title: 'Renascido', check: (s) => s.stats.ascensions >= 1 },
  { id: 'dinastia', name: 'Dinastia', icon: 'emblem-lion', desc: 'Ascenda 5 vezes.', gems: 20, title: 'Imperador', check: (s) => s.stats.ascensions >= 5, progress: (s) => [s.stats.ascensions, 5] },
  { id: 'cacador', name: 'Amigo dos Mercadores', icon: 'cart', desc: 'Atenda 25 carroças do mercador.', gems: 5, check: (s) => s.stats.chests >= 25, progress: (s) => [s.stats.chests, 25] },
  { id: 'fiel', name: 'Súdito Fiel', icon: 'calendar', desc: 'Entre 7 dias seguidos.', gems: 10, title: 'Fiel', check: (s) => s.daily.streak >= 7, progress: (s) => [s.daily.streak, 7] },

  // ---- essenciais novas (0.17.0): marcam o caminho do jogo
  { id: 'jardineiro', name: 'Jardineiro', icon: 'emblem-tree', desc: 'Plante 10 árvores.', gems: 2, check: (s) => (s.stats.planted || 0) >= 10, progress: (s) => [s.stats.planted || 0, 10] },
  { id: 'reflorestador', name: 'Reflorestador', icon: 'emblem-tree', desc: 'Plante 100 árvores.', gems: 6, title: 'Druida', check: (s) => (s.stats.planted || 0) >= 100, progress: (s) => [s.stats.planted || 0, 100] },
  { id: 'pedra-sobre-pedra', name: 'Pedra sobre Pedra', icon: 'talent-walls', desc: 'Tenha 20 muralhas.', gems: 3, check: (s) => countOf(s, 'muralha') >= 20, progress: (s) => [countOf(s, 'muralha'), 20] },
  { id: 'primeira-isca', name: 'Primeira Isca', icon: 'food', desc: 'Construa um Cais de Pesca.', gems: 2, check: (s) => countOf(s, 'cais') >= 1, progress: (s) => [countOf(s, 'cais'), 1] },
  { id: 'frota', name: 'Frota Pesqueira', icon: 'food', desc: 'Tenha 3 Cais de Pesca.', gems: 4, check: (s) => countOf(s, 'cais') >= 3, progress: (s) => [countOf(s, 'cais'), 3] },
  { id: 'strike-the-earth', name: 'Strike the Earth!', icon: 'tool-pickaxe', desc: 'Abra o subsolo com uma Escadaria.', gems: 3, check: (s) => (s.under?.reached || 0) >= 1, progress: (s) => [s.under?.reached || 0, 1] },
  { id: 'fundo-demais', name: 'Cavamos Fundo Demais', icon: 'hero-dwarf', desc: 'Chegue ao nível 3 do subsolo.', gems: 8, title: 'Anão Honorário', check: (s) => (s.under?.reached || 0) >= 3, progress: (s) => [s.under?.reached || 0, 3] },
  { id: 'toupeira', name: 'Toupeira Real', icon: 'tool-pickaxe', desc: 'Cave 500 blocos no subsolo.', gems: 6, check: (s) => (s.stats.dug || 0) >= 500, progress: (s) => [s.stats.dug || 0, 500] },
  { id: 'quartel-general', name: 'Quartel-General', icon: 'swords', desc: 'Termine 10 treinos de herói.', gems: 4, check: (s) => (s.stats.trained || 0) >= 10, progress: (s) => [s.stats.trained || 0, 10] },
  { id: 'taverna-lotada', name: 'Taverna Lotada', icon: 'house', desc: 'Leve a Taverna ao nível 10.', gems: 6, title: 'Taverneiro', check: (s) => maxLvl(s, 'taverna') >= 10, progress: (s) => [maxLvl(s, 'taverna'), 10] },
  { id: 'trio-lendario', name: 'Trio Lendário', icon: 'star', desc: 'Tenha 3 heróis Lendários.', gems: 15, check: (s, e, heroes) => legendaries(s, heroes) >= 3, progress: (s, e, heroes) => [legendaries(s, heroes), 3] },
  { id: 'imperador-romano', name: 'Assíduo', icon: 'calendar', desc: 'Entre 30 dias seguidos.', gems: 20, title: 'Inabalável', check: (s) => s.daily.streak >= 30, progress: (s) => [s.daily.streak, 30] },
  { id: 'maratona', name: 'Maratona', icon: 'time', desc: 'Jogue 10 horas no total.', gems: 5, check: (s) => s.stats.playTime >= 36000, progress: (s) => [Math.floor(s.stats.playTime / 3600), 10] },

  // ---- secretas e engraçadas: aparecem como "???" com uma dica até sair
  { id: 'curioso', kind: 'secret', name: 'Curioso', icon: 'info', hint: 'Toque numa conquista trancada.', desc: 'Era só clicar. Sério.', gems: 1, check: flag('curious') },
  { id: 'para-de-cutucar', kind: 'secret', name: 'Para de Cutucar', icon: 'greet', hint: 'Insista num prédio.', desc: 'Clique 30 vezes seguidas no mesmo prédio. Os moradores pediram medida protetiva.', gems: 2, check: flag('poke') },
  { id: 'mudei-de-ideia', kind: 'secret', name: 'Mudei de Ideia', icon: 'demolish', hint: 'Arrependimento é normal.', desc: 'Desfaça 10 construções. O arquiteto pediu demissão.', gems: 2, check: (s) => (s.stats.undos || 0) >= 10 },
  { id: 'engenharia-criativa', kind: 'secret', name: 'Engenharia Criativa', icon: 'talent-engineering', hint: 'Muralha também tem lado.', desc: 'Tenha uma muralha de lado para a próxima horda. Metade da muralha, todo o orgulho.', gems: 2, check: flag('sidewall') },
  { id: 'bolso-furado', kind: 'secret', name: 'Bolso Furado', icon: 'gold', hint: 'Gaste tudo.', desc: 'Fique sem nenhum ouro depois de já ter juntado 1.000. O tesoureiro fugiu com a carroça.', gems: 2, check: flag('broke') },
  { id: 'va-dormir', kind: 'secret', name: 'Vá Dormir, Majestade', icon: 'time', hint: 'Jogue quando o galo ainda dorme.', desc: 'Jogue entre 3h e 5h da manhã. Os aldeões estão preocupados.', gems: 3, check: flag('nightOwl') },
  { id: 'eles-apostaram', kind: 'secret', name: 'Eles Apostaram', icon: 'trade', hint: 'Suma por um tempo.', desc: 'Volte depois de 7 dias fora. Metade da vila apostou que você não voltava.', gems: 5, check: flag('comeback') },
  { id: 'codigo-antigo', kind: 'secret', name: 'Código Antigo', icon: 'keyboard', hint: 'Cima, cima...', desc: 'Digite o código Konami. 30 vidas? Não, 5 gemas.', gems: 5, check: flag('konami') },
  { id: 'paz-e-sossego', kind: 'secret', name: 'Paz e Sossego', icon: 'speaker-off', hint: 'Shhh.', desc: 'Desligue a música e os efeitos. Finalmente dá pra ouvir as galinhas.', gems: 1, check: flag('silence') },
  { id: 'deixa-queimar', kind: 'secret', name: 'Deixa Queimar', icon: 'event-blood-moon', hint: 'Perder também ensina.', desc: 'Perca 3 invasões seguidas. Estratégia ousada.', gems: 3, check: (s) => (s.stats.lossStreak || 0) >= 3 },
  { id: 'lenhador-arrependido', kind: 'secret', name: 'Lenhador Arrependido', icon: 'hero-woodcutter', hint: 'Plantou? Agora...', desc: 'Arranque uma muda que você mesmo plantou. Ela só queria crescer.', gems: 1, check: flag('choppedOwn') },
  { id: 'nome-original', kind: 'secret', name: 'Muito Original', icon: 'scroll', hint: 'Criatividade no nome.', desc: 'Troque o nome do reino e depois volte para "Reino de Bolso". Ninguém pensou nisso antes.', gems: 1, check: flag('defaultName') },
  { id: 'clique-magico', kind: 'secret', name: 'Clique Mágico', icon: 'gems', hint: 'Será que multiplica?', desc: 'Toque 10 vezes seguidas nas suas gemas. Não, elas não multiplicam.', gems: 1, check: flag('gemPoke') },

  // ---- sombra: não contam no total nem no bônus (sorte pura ou meio trapaça)
  { id: 'pura-sorte', kind: 'shadow', name: 'Pura Sorte', icon: 'star', hint: 'Só deixe o jogo aberto.', desc: 'Chance de 1 em 1 milhão por segundo com o jogo aberto. Jogue na loteria hoje.', gems: 10, check: flag('lucky') },
  { id: 'viajante-do-tempo', kind: 'shadow', name: 'Viajante do Tempo', icon: 'hero-clock', hint: 'Mexa no que não devia.', desc: 'O relógio do aparelho voltou mais de 1 hora. O tempo não volta, majestade.', gems: 0, check: flag('timeTravel') },
  { id: 'insistente', kind: 'shadow', name: 'Insistente', icon: 'warning', hint: 'Não aceite um não.', desc: 'Tente construir sem recursos 100 vezes. A resposta continua sendo não.', gems: 1, check: (s) => (s.stats.failBuild || 0) >= 100 },
];
