// Conquistas: cada uma dá gemas e, às vezes, um título (identidade).
// check(s, econ) recebe o estado e o resultado de computeEconomy.

const countBuildings = (s) => s.grid.tiles.filter((t) => t.b).length;

export const ACHIEVEMENTS = [
  { id: 'primeira-pedra', name: 'Primeira Pedra', icon: '🧱', desc: 'Construa seu primeiro prédio.', gems: 2, check: (s) => s.stats.built >= 1 },
  { id: 'vila', name: 'Vilarejo', icon: '🏘️', desc: 'Tenha 10 construções.', gems: 3, check: (s) => countBuildings(s) >= 10 },
  { id: 'cidade', name: 'Cidade', icon: '🏙️', desc: 'Tenha 25 construções.', gems: 5, title: 'Prefeito', check: (s) => countBuildings(s) >= 25 },
  { id: 'metropole', name: 'Metrópole', icon: '🌆', desc: 'Tenha 50 construções.', gems: 10, title: 'Grão-Duque', check: (s) => countBuildings(s) >= 50 },
  { id: 'populoso', name: 'Lotado', icon: '👥', desc: 'Alcance 50 moradores.', gems: 4, check: (s) => s.pop >= 50 },
  { id: 'formigueiro', name: 'Formigueiro', icon: '🐜', desc: 'Alcance 150 moradores.', gems: 8, check: (s) => s.pop >= 150 },
  { id: 'rico', name: 'Bolso Cheio', icon: '💰', desc: 'Ganhe 10 mil de ouro (vida toda).', gems: 3, check: (s) => s.stats.totalGold >= 1e4 },
  { id: 'milionario', name: 'Milionário', icon: '🤑', desc: 'Ganhe 1 milhão de ouro (vida toda).', gems: 8, title: 'Magnata', check: (s) => s.stats.totalGold >= 1e6 },
  { id: 'bilionario', name: 'Tesouro do Dragão', icon: '🐲', desc: 'Ganhe 1 bilhão de ouro (vida toda).', gems: 25, title: 'Senhor do Ouro', check: (s) => s.stats.totalGold >= 1e9 },
  { id: 'defensor', name: 'Defensor', icon: '🛡️', desc: 'Vença sua primeira invasão.', gems: 2, check: (s) => s.stats.raidsWon >= 1 },
  { id: 'muralha-viva', name: 'Muralha Viva', icon: '🏰', desc: 'Vença 10 invasões.', gems: 5, title: 'Guardião', check: (s) => s.stats.raidsWon >= 10 },
  { id: 'imbativel', name: 'Imbatível', icon: '⚔️', desc: 'Vença 50 invasões.', gems: 12, title: 'Conquistador', check: (s) => s.stats.raidsWon >= 50 },
  { id: 'recrutador', name: 'Recrutador', icon: '📜', desc: 'Recrute 5 heróis.', gems: 3, check: (s) => s.stats.recruits >= 5 },
  { id: 'lenda', name: 'Lenda Viva', icon: '🌟', desc: 'Tenha um herói Lendário.', gems: 10, title: 'Lendário', check: (s, e, heroes) => Object.keys(s.heroes.owned).some((id) => heroes[id]?.rarity === 'lendario') },
  { id: 'colecionador', name: 'Colecionador', icon: '📚', desc: 'Tenha 10 heróis diferentes.', gems: 10, title: 'Colecionador', check: (s) => Object.keys(s.heroes.owned).length >= 10 },
  { id: 'explorador', name: 'Andarilho', icon: '🧭', desc: 'Complete 10 expedições.', gems: 4, check: (s) => s.stats.expeditions >= 10 },
  { id: 'arquiteto', name: 'Mestre de Obras', icon: '🏗️', desc: 'Leve um prédio ao nível 10.', gems: 8, title: 'Mestre de Obras', check: (s) => s.grid.tiles.some((t) => t.b && t.b.lvl >= 10) },
  { id: 'sinergia', name: 'Sinergia Perfeita', icon: '🧩', desc: 'Tenha um prédio com +150% de adjacência.', gems: 6, title: 'Urbanista', check: (s, e) => e.tiles.some((t) => t && t.adjBonus >= 1.5) },
  { id: 'feliz', name: 'Reino Feliz', icon: '😄', desc: 'Alcance 100 de felicidade.', gems: 5, check: (s, e) => e.happiness >= 100 },
  { id: 'horizonte', name: 'Horizonte', icon: '🗺️', desc: 'Desbloqueie o mapa inteiro.', gems: 8, check: (s) => s.grid.ring >= 5 },
  { id: 'ascensao', name: 'Renascido', icon: '👑', desc: 'Ascenda pela primeira vez.', gems: 10, title: 'Renascido', check: (s) => s.stats.ascensions >= 1 },
  { id: 'dinastia', name: 'Dinastia', icon: '🏛️', desc: 'Ascenda 5 vezes.', gems: 20, title: 'Imperador', check: (s) => s.stats.ascensions >= 5 },
  { id: 'cacador', name: 'Caçador de Baús', icon: '🎁', desc: 'Abra 25 baús do mercador.', gems: 5, check: (s) => s.stats.chests >= 25 },
  { id: 'fiel', name: 'Súdito Fiel', icon: '📅', desc: 'Entre 7 dias seguidos.', gems: 10, title: 'Fiel', check: (s) => s.daily.streak >= 7 },
];
