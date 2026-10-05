// Estado do jogo: criação, salvamento, carregamento e migração.
import { generateMap, START_RING, MAX_RING } from './map.js';
import { seasonInfo } from './season.js';
import { BASE_TITLES } from '../data/cosmetics.js';
import { TALENT_BY_ID } from '../data/talents.js';
import { RAID_FIRST_DELAY } from '../data/events.js';

export const SAVE_VERSION = 1;
export const SAVE_KEY = 'reino-de-bolso:save';

export function newSeed() {
  return Math.floor(Math.random() * 2 ** 31);
}

function freshStats() {
  return {
    totalGold: 0, runGold: 0, built: 0, upgrades: 0, raidsWon: 0, raidsLost: 0, recruits: 0, goldRecruits: 0,
    expeditions: 0, chests: 0, ascensions: 0, cleared: 0, visits: 0, playTime: 0, bestRaid: 0,
  };
}

export function createState({ seed = newSeed(), now = Date.now(), carry = null } = {}) {
  const legacy = carry?.legacy ?? {};
  const lvl = (id) => legacy[id] || 0;
  const startTalent = TALENT_BY_ID.heranca.effect(lvl('heranca'));
  const ringTalent = TALENT_BY_ID.terras.effect(lvl('terras'));

  const grid = generateMap(seed);
  grid.ring = Math.min(MAX_RING, START_RING + ringTalent.startRing);

  return {
    version: SAVE_VERSION,
    seed,
    createdAt: carry?.createdAt ?? now,
    runStartedAt: now,
    lastTick: now,
    kingdom: carry?.kingdom ?? { name: 'Reino de Bolso', banner: 'carmesim', emblem: 'coroa', title: 'Fundador' },
    res: {
      gold: 100 + startTalent.startGold,
      food: 50,
      wood: 30 + startTalent.startWood,
      stone: 20,
      gems: carry?.res?.gems ?? 0,
      crowns: carry?.res?.crowns ?? 0,
    },
    pop: 1,
    grid,
    heroes: carry?.heroes ?? { owned: {}, council: [] },
    items: carry?.items ?? { scrolls: 1 },
    raid: { level: 0, nextAt: now + RAID_FIRST_DELAY * 1000, warned: false, name: null },
    event: null,
    nextEventAt: now + 240000,
    chest: null,
    nextChestAt: now + 60000,
    boostUntil: 0,
    legacy,
    season: carry?.season ?? { number: seasonInfo(now).number, xp: 0, claimed: [], missions: null },
    achievements: carry?.achievements ?? {},
    cosmetics: carry?.cosmetics ?? { banners: [], emblems: [], titles: [...BASE_TITLES] },
    daily: carry?.daily ?? { lastDay: null, streak: 0 },
    social: carry?.social ?? { trades: {}, greets: {}, rivalsSeed: seed },
    tutorial: carry ? { done: true, step: 99 } : { done: false, step: 0 },
    stats: carry ? { ...freshStats(), ...carry.stats, runGold: 0 } : freshStats(),
    settings: carry?.settings ?? { sound: true, particles: true },
    log: [],
  };
}

// Herança para a próxima rodada (Ascensão): o que é "identidade" persiste.
export function carryOver(state) {
  for (const h of Object.values(state.heroes.owned)) h.expedition = null;
  return {
    legacy: state.legacy,
    createdAt: state.createdAt,
    kingdom: state.kingdom,
    res: { gems: state.res.gems, crowns: state.res.crowns },
    heroes: state.heroes,
    items: state.items,
    season: state.season,
    achievements: state.achievements,
    cosmetics: state.cosmetics,
    daily: state.daily,
    social: state.social,
    stats: state.stats,
    settings: state.settings,
  };
}

export function serialize(state) {
  const { log, ...rest } = state;
  return JSON.stringify(rest);
}

export function deserialize(json) {
  const data = JSON.parse(json);
  return migrate(data);
}

export function migrate(data) {
  if (!data || typeof data !== 'object' || !data.grid || !data.res) throw new Error('Save inválido');
  // v1 é a primeira versão; migrações futuras entram aqui (if (data.version < 2) {...}).
  const base = createState({ seed: data.seed ?? 1, now: data.lastTick ?? Date.now() });
  const merged = { ...base, ...data, log: [] };
  merged.stats = { ...base.stats, ...data.stats };
  merged.settings = { ...base.settings, ...data.settings };
  merged.items = { ...base.items, ...data.items };
  merged.social = { ...base.social, ...data.social };
  merged.version = SAVE_VERSION;
  return merged;
}

export function exportSave(state) {
  return btoa(unescape(encodeURIComponent(serialize(state))));
}

export function importSave(code) {
  return deserialize(decodeURIComponent(escape(atob(code.trim()))));
}
