// Catálogo de construções. Todo número de balanceamento das construções vive aqui.
// Documentação: docs/BALANCEAMENTO.md (seção "Construções") e docs/GDD.md (seção "Adjacência").
//
// Campos:
//   cost        custo base (escala 1.12^quantidade e 2.5^nível)
//   workers     trabalhadores exigidos no nível 1 (0 = não precisa)
//   prod        produção por segundo no nível 1 { recurso: valor }
//   consume     consumo por segundo no nível 1 { recurso: valor }
//   popCap      capacidade de população
//   defense     defesa contra invasões
//   happiness   felicidade (global)
//   storage     aumento de armazenamento { recurso: valor }
//   adj         bônus de adjacência ortogonal { vizinho: fração } (vizinho = id de construção ou de terreno)
//   requiresAdj só produz se houver pelo menos um vizinho desse tipo
//   unlock      condição para aparecer na paleta { buildings: n } (total de construções)

export const BUILDINGS = {
  casa: {
    id: 'casa', name: 'Casa', category: 'civil',
    desc: 'Abriga 4 moradores e gera impostos. Adora mercados e tavernas; odeia barulho de pedreiras e minas.',
    cost: { gold: 25, wood: 10 }, workers: 0,
    prod: { gold: 0.8 }, popCap: 4,
    adj: { mercado: 0.5, taverna: 0.3, casa: 0.1, jardim: 0.2, fogueira: 0.3, pedreira: -0.3, mina: -0.3 },
  },
  fazenda: {
    id: 'fazenda', name: 'Fazenda', category: 'producao',
    desc: 'Produz comida. Rende mais perto da água, de moinhos e de outras fazendas.',
    cost: { gold: 20 }, workers: 2,
    prod: { food: 1.2 },
    adj: { water: 0.5, moinho: 0.5, fazenda: 0.1, armazem: 0.15 },
  },
  serraria: {
    id: 'serraria', name: 'Serraria', category: 'producao',
    desc: 'Produz madeira. Cada floresta vizinha dá +40%. Não derrube todas as árvores!',
    cost: { gold: 40 }, workers: 2,
    prod: { wood: 0.6 },
    adj: { forest: 0.4, armazem: 0.15 },
  },
  pedreira: {
    id: 'pedreira', name: 'Pedreira', category: 'producao',
    desc: 'Produz pedra. Cada rocha vizinha dá +50%. Barulhenta: vizinhos de casa ficam infelizes.',
    cost: { gold: 60, wood: 20 }, workers: 2,
    prod: { stone: 0.6 }, happiness: -2,
    adj: { rock: 0.5, mountain: 0.25, armazem: 0.15 },
    unlock: { buildings: 3 },
  },
  mercado: {
    id: 'mercado', name: 'Mercado', category: 'economia',
    desc: 'Transforma comida em ouro. Cada casa vizinha é um cliente (+20%). Mercados vizinhos competem (-20%).',
    cost: { gold: 120, wood: 40 }, workers: 2,
    prod: { gold: 2.0 }, consume: { food: 0.6 },
    adj: { casa: 0.2, mercado: -0.2, armazem: 0.15 },
    unlock: { buildings: 4 },
  },
  moinho: {
    id: 'moinho', name: 'Moinho', category: 'producao',
    desc: 'Um pouco de comida e um grande bônus para fazendas vizinhas.',
    cost: { gold: 100, wood: 50 }, workers: 1,
    prod: { food: 0.4 },
    adj: { fazenda: 0.25, water: 0.25 },
    unlock: { buildings: 5 },
  },
  cais: {
    id: 'cais', name: 'Cais de Pesca', category: 'producao',
    desc: 'Pesca no lago: comida farta, mas só funciona na beira da água. Cada tile de água vizinho dá +40%.',
    cost: { gold: 60, wood: 30 }, workers: 2,
    prod: { food: 1.4 },
    adj: { water: 0.4, armazem: 0.15 },
    requiresAdj: 'water',
    unlock: { buildings: 3 },
  },
  armazem: {
    id: 'armazem', name: 'Armazém', category: 'economia',
    desc: 'Aumenta muito o limite de recursos (cresce com o quadrado do nível). Produtores vizinhos ganham +15%.',
    cost: { gold: 150, wood: 80 }, workers: 1,
    storage: { gold: 8000, food: 1000, wood: 1000, stone: 1000 }, // x nível² (1, 4, 9 … 100)
    adj: {},
    unlock: { buildings: 5 },
  },
  taverna: {
    id: 'taverna', name: 'Taverna', category: 'civil',
    desc: 'Felicidade para o reino inteiro e ouro de quem passa. Cada nível barateia o recrutamento com ouro; nos níveis 5 e 10 abre uma vaga no Conselho. Duas tavernas lado a lado brigam.',
    cost: { gold: 200, wood: 80, stone: 20 }, workers: 2,
    prod: { gold: 0.8 }, happiness: 6,
    adj: { casa: 0.15, taverna: -0.5 },
    unlock: { buildings: 6 },
  },
  muralha: {
    id: 'muralha', name: 'Muralha', category: 'defesa',
    desc: 'Defesa barata. Muralhas e torres vizinhas se reforçam.',
    cost: { stone: 25 }, workers: 0,
    defense: 3,
    adj: { muralha: 0.25, torre: 0.25 },
    unlock: { buildings: 4 }, // o tutorial pede defesa no passo 4: precisa estar liberada
  },
  torre: {
    id: 'torre', name: 'Torre', category: 'defesa',
    desc: 'O coração da defesa. +30% por muralha vizinha.',
    cost: { gold: 150, wood: 40, stone: 60 }, workers: 2,
    defense: 10,
    adj: { muralha: 0.3, torre: 0.1 },
    unlock: { buildings: 6 },
  },
  quartel: {
    id: 'quartel', name: 'Quartel', category: 'defesa',
    desc: 'Treina heróis: cada nível do quartel deixa os heróis subirem um nível a mais. Gosta de muralhas e torres por perto.',
    cost: { gold: 400, wood: 150, stone: 100 }, workers: 3,
    defense: 4,
    adj: { muralha: 0.15, torre: 0.15 },
    unlock: { buildings: 10 },
  },
  mina: {
    id: 'mina', name: 'Mina de Ouro', category: 'economia',
    desc: 'Muito ouro, mas só funciona encostada numa montanha (+60% por montanha).',
    cost: { gold: 500, wood: 150, stone: 120 }, workers: 4,
    prod: { gold: 5.0 }, happiness: -3,
    adj: { mountain: 0.6, armazem: 0.15 },
    requiresAdj: 'mountain',
    unlock: { buildings: 10 },
  },
  templo: {
    id: 'templo', name: 'Templo', category: 'civil',
    desc: 'Grande felicidade e +5% de Coroas ao Ascender (por templo).',
    cost: { gold: 800, stone: 300 }, workers: 3,
    happiness: 10, crownBonus: 0.05,
    adj: { casa: 0.1, jardim: 0.2 },
    unlock: { buildings: 14 },
  },
  jardim: {
    id: 'jardim', name: 'Jardim', category: 'decoracao',
    desc: 'Decoração simples. +2 de felicidade; casas vizinhas ganham +20%.',
    cost: { gold: 60 }, workers: 0,
    happiness: 2, adj: {}, maxLevel: 1,
    unlock: { buildings: 4 },
  },
  fogueira: {
    id: 'fogueira', name: 'Fogueira', category: 'decoracao',
    desc: 'Ponto de encontro do povo (custa gemas). +5 de felicidade; casas vizinhas ganham +30%.',
    cost: { gems: 5 }, workers: 0,
    happiness: 5, adj: {}, maxLevel: 1,
    unlock: { buildings: 8 },
  },
  estatua: {
    id: 'estatua', name: 'Estátua do Fundador', category: 'decoracao',
    desc: 'Símbolo do seu reino. +8 de felicidade e +5% de ouro global.',
    cost: { gems: 15 }, workers: 0,
    happiness: 8, globalGold: 0.05, adj: {}, maxLevel: 1,
    unlock: { buildings: 12 },
  },
  escadaria: {
    id: 'escadaria', name: 'Escadaria', category: 'economia',
    desc: 'Desce para o subsolo: lá embaixo dá para cavar pedra, achar veios de ouro e gemas e abrir salas.',
    cost: { wood: 80, stone: 40 }, workers: 0,
    adj: {}, maxLevel: 1,
    unlock: { buildings: 5 },
  },
};

export const BUILDING_ORDER = [
  'casa', 'fazenda', 'serraria', 'pedreira', 'cais', 'mercado', 'moinho', 'armazem',
  'taverna', 'muralha', 'torre', 'quartel', 'mina', 'templo', 'jardim', 'fogueira', 'estatua', 'escadaria',
];

export const MAX_LEVEL = 10;
export const COUNT_COST_GROWTH = 1.12;
export const LEVEL_COST_GROWTH = 2.5;
export const LEVEL_OUTPUT_STEP = 0.75; // +75% de produção por nível acima do 1
export const SELL_REFUND = 0.5;

export const TERRAIN = {
  grass: { id: 'grass', name: 'Campo', buildable: true },
  forest: { id: 'forest', name: 'Floresta', buildable: false, clearCost: { gold: 30 }, clearYield: { wood: 40 } },
  rock: { id: 'rock', name: 'Rochas', buildable: false, clearCost: { gold: 50 }, clearYield: { stone: 30 } },
  // Muda plantada pelo jogador: cresce sozinha até virar floresta (GROW_SECONDS). Arrancar é de graça.
  sapling: { id: 'sapling', name: 'Muda', buildable: false, clearCost: {}, clearYield: {} },
  water: { id: 'water', name: 'Lago', buildable: false },
  mountain: { id: 'mountain', name: 'Montanha', buildable: false },
};

// Plantar árvores (inspirado no Forester do Banished): ouro sobrando vira floresta, que vira madeira.
export const PLANT_COST = { gold: 25 };
export const GROW_SECONDS = 180; // muda -> árvores jovens na metade -> floresta

// `icon` = nome do arquivo em assets/icons/game-icons/ (sem .svg).
export const RESOURCES = {
  gold: { id: 'gold', name: 'Ouro', icon: 'gold' },
  food: { id: 'food', name: 'Comida', icon: 'food' },
  wood: { id: 'wood', name: 'Madeira', icon: 'wood' },
  stone: { id: 'stone', name: 'Pedra', icon: 'stone' },
  gems: { id: 'gems', name: 'Gemas', icon: 'gems' },
  crowns: { id: 'crowns', name: 'Coroas', icon: 'crowns' },
};

export const BASE_STORAGE = { gold: 2500, food: 500, wood: 500, stone: 500 };
export const FOOD_PER_POP = 0.15;
export const POP_GROWTH = 0.25; // moradores/s rumo à capacidade
export const POP_STARVE = 0.2;  // moradores/s perdidos sem comida
