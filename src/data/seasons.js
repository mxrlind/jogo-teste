// Temporadas: rotação de 4 temas (inspirada na pesquisa: Fundação → Guerra → Expansão → Catástrofe).
// Cada temporada dura 28 dias a partir de SEASON_EPOCH e é calculada pelo relógio — sem servidor.

export const SEASON_EPOCH = Date.UTC(2026, 0, 5); // segunda-feira, 5 jan 2026
export const SEASON_LENGTH_DAYS = 28;
export const SEASON_TIERS = 30;
export const XP_PER_TIER = 300;

export const SEASON_THEMES = [
  {
    id: 'fundacao', name: 'Fundação', icon: 'season-foundation', color: '#51cf66',
    desc: 'Tempo de erguer o reino. Ouro +10%, casas +25% e construções -10%.',
    mods: { prod: { gold: 0.1 }, houseBonus: 0.25, cost: 0.1 },
  },
  {
    id: 'guerra', name: 'Guerra', icon: 'season-war', color: '#ff6b6b',
    desc: 'Hordas mais frequentes, porém o saque é dobrado e a defesa ganha +25%.',
    mods: { raidInterval: 0.6, raidLoot: 1.0, defense: 0.25 },
  },
  {
    id: 'expansao', name: 'Expansão', icon: 'season-expansion', color: '#4dabf7',
    desc: 'Novas terras pela metade do preço e expedições +50%.',
    mods: { landCost: 0.5, expedition: 0.5 },
  },
  {
    id: 'catastrofe', name: 'Catástrofe', icon: 'season-catastrophe', color: '#ff922b',
    desc: 'O mundo treme: eventos mais frequentes, felicidade -10, mas +50% de Coroas.',
    mods: { eventRate: 2, happiness: -10, crowns: 0.5 },
  },
];

// Recompensas do Passe de Temporada (gratuito). {s} = número da temporada.
export function tierReward(tier, seasonNumber, themeId) {
  if (tier === SEASON_TIERS) return { type: 'cosmetic', kind: 'title', id: `campeao-${themeId}`, label: `Título: Campeão da ${themeLabel(themeId)}` };
  if (tier === 21) return { type: 'cosmetic', kind: 'emblem', id: `emblema-${themeId}`, label: 'Emblema da Temporada' };
  if (tier === 14) return { type: 'cosmetic', kind: 'banner', id: `estandarte-${themeId}`, label: 'Estandarte da Temporada' };
  if (tier % 5 === 0) return { type: 'scroll', amount: 1, label: '1 Pergaminho de Recrutamento' };
  if (tier % 3 === 0) return { type: 'gems', amount: 5 + Math.floor(tier / 3), label: `${5 + Math.floor(tier / 3)} gemas` };
  if (tier % 2 === 0) return { type: 'boost', minutes: 10, label: 'Bênção: +50% produção por 10 min' };
  return { type: 'goldMinutes', minutes: 5, label: '5 min de produção de ouro' };
}

function themeLabel(themeId) {
  return SEASON_THEMES.find((t) => t.id === themeId)?.name ?? themeId;
}

// Missões diárias: 3 sorteadas por dia (semente = data).
export const MISSION_POOL = [
  { id: 'build', text: (n) => `Construa ${n} prédios`, track: 'build', amounts: [3, 5, 8], xp: 60 },
  { id: 'upgrade', text: (n) => `Melhore ${n} prédios`, track: 'upgrade', amounts: [2, 4, 6], xp: 70 },
  { id: 'raid', text: (n) => `Vença ${n} invasões`, track: 'raidWin', amounts: [1, 2, 3], xp: 90 },
  { id: 'expedition', text: (n) => `Complete ${n} expedições`, track: 'expedition', amounts: [2, 3, 5], xp: 70 },
  { id: 'chest', text: (n) => `Atenda ${n} carroças do mercador`, track: 'chest', amounts: [2, 3, 4], xp: 60 },
  { id: 'gold', text: (n) => `Ganhe ${n} de ouro`, track: 'gold', amounts: [2000, 10000, 50000], xp: 60, scale: true },
  { id: 'clear', text: (n) => `Limpe ${n} terrenos`, track: 'clear', amounts: [1, 2, 3], xp: 50 },
  { id: 'visit', text: (n) => `Visite ${n} reinos vizinhos`, track: 'visit', amounts: [1, 2, 3], xp: 40 },
];

export const XP_REWARDS = { build: 2, upgrade: 3, raidWin: 15, expedition: 10, chest: 5, daily: 50, clear: 1 };
