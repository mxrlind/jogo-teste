// Heróis colecionáveis. Bônus passivos valem só para heróis no Conselho.
// Estrelas (duplicatas) multiplicam o bônus: 1 + 0.5 * (estrelas - 1); o poder escala linearmente.
// Tipos de bônus (bonus.type):
//   prod:<recurso>   +X de produção do recurso
//   prodAll          +X de toda produção
//   defense          +X de defesa
//   happiness        +X pontos de felicidade (valor absoluto)
//   expedition       +X de recompensa de expedições
//   cost             -X no custo de construções
//   raidLoot         +X de saque em invasões vencidas
//   raidGems         +X gemas por invasão vencida (absoluto)
//   terrainAdj       +X nos bônus de adjacência de terreno (floresta, rocha, água, montanha)
//   offline          +X de eficiência offline e +4h de limite por estrela

export const RARITIES = {
  comum: { id: 'comum', name: 'Comum', color: '#9aa5b1', weight: 60 },
  raro: { id: 'raro', name: 'Raro', color: '#4dabf7', weight: 28 },
  epico: { id: 'epico', name: 'Épico', color: '#b197fc', weight: 10 },
  lendario: { id: 'lendario', name: 'Lendário', color: '#ffd43b', weight: 2 },
};

export const HEROES = [
  { id: 'lavradora', name: 'Marta, a Lavradora', icon: 'hero-farmer', rarity: 'comum', power: 2, bonus: { type: 'prod:food', value: 0.15 }, lore: 'Diz que conversa com as sementes. As sementes parecem concordar.' },
  { id: 'lenhador', name: 'Tito, o Lenhador', icon: 'hero-woodcutter', rarity: 'comum', power: 3, bonus: { type: 'prod:wood', value: 0.15 }, lore: 'Nunca derrubou uma árvore que não pediu desculpas antes.' },
  { id: 'pedreiro', name: 'Joca, o Pedreiro', icon: 'hero-mason', rarity: 'comum', power: 3, bonus: { type: 'prod:stone', value: 0.15 }, lore: 'Constrói muros tão retos que dá pra usar como régua.' },
  { id: 'guarda', name: 'Guarda Bento', icon: 'hero-guard', rarity: 'comum', power: 5, bonus: { type: 'defense', value: 0.15 }, lore: 'Dorme em pé. Literalmente. É um talento.' },
  { id: 'coletora', name: 'Lia, a Coletora', icon: 'hero-collector', rarity: 'comum', power: 2, bonus: { type: 'prod:gold', value: 0.1 }, lore: 'Ninguém escapa dos impostos. Ninguém.' },
  { id: 'mercadora', name: 'Dona Safira', icon: 'hero-merchant', rarity: 'raro', power: 4, bonus: { type: 'prod:gold', value: 0.2 }, lore: 'Vende gelo para pinguins e areia para camelos.' },
  { id: 'arqueira', name: 'Ayla, a Arqueira', icon: 'hero-archer', rarity: 'raro', power: 10, bonus: { type: 'defense', value: 0.25 }, lore: 'Acerta uma maçã a cem passos. Depois come a maçã.' },
  { id: 'bardo', name: 'Rui, o Bardo', icon: 'hero-bard', rarity: 'raro', power: 3, bonus: { type: 'happiness', value: 8 }, lore: 'Conhece 400 canções, 399 sobre si mesmo.' },
  { id: 'exploradora', name: 'Nina, a Exploradora', icon: 'hero-explorer', rarity: 'raro', power: 6, bonus: { type: 'expedition', value: 0.3 }, lore: 'O mapa dela tem uma seção chamada "ainda não".' },
  { id: 'arquiteta', name: 'Helena, a Arquiteta', icon: 'hero-architect', rarity: 'epico', power: 6, bonus: { type: 'cost', value: 0.15 }, lore: 'Projetou o reino inteiro num guardanapo.' },
  { id: 'cavaleiro', name: 'Sir Dourado', icon: 'hero-knight', rarity: 'epico', power: 20, bonus: { type: 'raidLoot', value: 0.5 }, lore: 'Sua armadura brilha tanto que cega os inimigos. E os aliados.' },
  { id: 'alquimista', name: 'Zé Alquimista', icon: 'hero-alchemist', rarity: 'epico', power: 8, bonus: { type: 'prodAll', value: 0.1 }, lore: 'Transformou chumbo em ouro uma vez. Ou foi só tinta.' },
  { id: 'druida', name: 'Iara, a Druida', icon: 'hero-druid', rarity: 'epico', power: 9, bonus: { type: 'terrainAdj', value: 0.5 }, lore: 'As florestas crescem um pouco mais quando ela passa.' },
  { id: 'rainha', name: 'Rainha Aurora', icon: 'hero-queen', rarity: 'lendario', power: 25, bonus: { type: 'prodAll', value: 0.25 }, lore: 'Governou mil reinos. Escolheu o seu.' },
  { id: 'dragao', name: 'Brasa, o Dragão', icon: 'hero-dragon', rarity: 'lendario', power: 50, bonus: { type: 'defense', value: 1.0 }, lore: 'Antes era a ameaça. Agora é o cão de guarda mais caro do continente.' },
  { id: 'relojoeiro', name: 'O Relojoeiro', icon: 'hero-clock', rarity: 'lendario', power: 10, bonus: { type: 'offline', value: 0.25 }, lore: 'Dizem que ele dá corda no próprio tempo.' },
];

export const HERO_BY_ID = Object.fromEntries(HEROES.map((h) => [h.id, h]));
export const MAX_STARS = 5;
export const BASE_COUNCIL_SLOTS = 3;
export const RECRUIT_GOLD_BASE = 300;
export const RECRUIT_GOLD_GROWTH = 1.6;
export const RECRUIT_GEM_COST = 15;

// Expedições: duração em segundos, multiplicador de recompensa, chance de gemas e faixa de gemas.
export const EXPEDITIONS = [
  { id: 'curta', name: 'Patrulha', duration: 60, gemChance: 0.05, gems: [1, 1], scrollChance: 0 },
  { id: 'media', name: 'Exploração', duration: 300, gemChance: 0.25, gems: [1, 2], scrollChance: 0.02 },
  { id: 'longa', name: 'Jornada', duration: 1800, gemChance: 0.6, gems: [1, 4], scrollChance: 0.06 },
  { id: 'epica', name: 'Grande Expedição', duration: 7200, gemChance: 1, gems: [3, 8], scrollChance: 0.15 },
];
