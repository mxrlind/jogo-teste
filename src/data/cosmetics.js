// Cosméticos de identidade: estandartes (cor), emblemas e títulos.
// Nada aqui dá poder — só status (lição de League of Legends na pesquisa).

export const BANNERS = [
  { id: 'carmesim', name: 'Carmesim', color: '#c92a2a', free: true },
  { id: 'real', name: 'Azul Real', color: '#1c7ed6', free: true },
  { id: 'floresta', name: 'Floresta', color: '#2b8a3e', free: true },
  { id: 'ouro', name: 'Ouro Velho', color: '#e67700', free: true },
  { id: 'violeta', name: 'Violeta', color: '#7048e8', price: 10 },
  { id: 'noite', name: 'Meia-Noite', color: '#212529', price: 10 },
  { id: 'rosa', name: 'Rosa Selvagem', color: '#d6336c', price: 10 },
  { id: 'estandarte-fundacao', name: 'Fundação', color: '#51cf66', season: true },
  { id: 'estandarte-guerra', name: 'Guerra', color: '#ff6b6b', season: true },
  { id: 'estandarte-expansao', name: 'Expansão', color: '#4dabf7', season: true },
  { id: 'estandarte-catastrofe', name: 'Catástrofe', color: '#ff922b', season: true },
];

export const EMBLEMS = [
  { id: 'coroa', icon: '👑', free: true },
  { id: 'escudo', icon: '🛡️', free: true },
  { id: 'leao', icon: '🦁', free: true },
  { id: 'arvore', icon: '🌳', free: true },
  { id: 'lobo', icon: '🐺', price: 8 },
  { id: 'aguia', icon: '🦅', price: 8 },
  { id: 'rosa', icon: '🌹', price: 8 },
  { id: 'caveira', icon: '💀', price: 12 },
  { id: 'emblema-fundacao', icon: '🏗️', season: true },
  { id: 'emblema-guerra', icon: '⚔️', season: true },
  { id: 'emblema-expansao', icon: '🧭', season: true },
  { id: 'emblema-catastrofe', icon: '🌋', season: true },
];

export const BASE_TITLES = ['Fundador', 'Aldeão Ambicioso'];

export const SEASON_TITLES = {
  'campeao-fundacao': 'Campeão da Fundação',
  'campeao-guerra': 'Campeão da Guerra',
  'campeao-expansao': 'Campeão da Expansão',
  'campeao-catastrofe': 'Campeão da Catástrofe',
};

export const DAILY_REWARDS = [
  { day: 1, label: '200 ouro', gold: 200 },
  { day: 2, label: '2 gemas', gems: 2 },
  { day: 3, label: '10 min de ouro', goldMinutes: 10 },
  { day: 4, label: '3 gemas', gems: 3 },
  { day: 5, label: 'Bênção 15 min', boost: 15 },
  { day: 6, label: '5 gemas', gems: 5 },
  { day: 7, label: 'Pergaminho', scroll: 1 },
];
