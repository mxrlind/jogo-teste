// Estado do jogo: criação, salvamento, carregamento e migração.
import { generateMap, START_RING, MAX_RING } from './map.js';
import { seasonInfo } from './season.js';
import { BASE_TITLES } from '../data/cosmetics.js';
import { TALENT_BY_ID } from '../data/talents.js';
import { RAID_FIRST_DELAY } from '../data/events.js';

// v1: formato original. v2: id 'fonte' -> 'fogueira', direção das hordas, desbloqueio de abas,
// configurações movidas para src/core/config.js (preferência do dispositivo, não do reino).
export const SAVE_VERSION = 2;
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
  const stats = carry ? { ...freshStats(), ...carry.stats, runGold: 0 } : freshStats();

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
      stone: 25, // paga a primeira muralha (tutorial, passo 4)
      gems: carry?.res?.gems ?? 0,
      crowns: carry?.res?.crowns ?? 0,
    },
    pop: 1,
    grid,
    heroes: carry?.heroes ?? { owned: {}, council: [] },
    items: carry?.items ?? { scrolls: 1 },
    raid: { level: 0, nextAt: now + RAID_FIRST_DELAY * 1000, warned: false, name: null, dir: 'n' },
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
    // Abas reveladas aos poucos (desbloqueio gradual). Veteranos (Ascensão) mantêm o que já viram.
    unlocks: carry?.unlocks ?? { tabs: ['reino', 'perfil'] },
    stats,
    // Foto das estatísticas no início da rodada: o resumo da Ascensão mostra só o que foi feito nela.
    runBase: { ...stats },
    runs: carry?.runs ?? [], // resumos das últimas rodadas (mais recente primeiro)
    records: carry?.records ?? {}, // melhores marcas entre rodadas
    log: [],
  };
}

// Herança para a próxima rodada (Ascensão): o que é "identidade" persiste.
export function carryOver(state) {
  for (const h of Object.values(state.heroes.owned)) {
    h.expedition = null;
    // Treino pago não se perde na Ascensão: o herói sobe de nível na hora.
    if (h.training) { h.level = (h.level || 1) + 1; h.training = null; }
  }
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
    unlocks: state.unlocks,
    runs: state.runs,
    records: state.records,
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

export const ALL_TABS = ['reino', 'herois', 'temporada', 'legado', 'social', 'perfil'];

// Migra qualquer versão anterior para a atual. Cada passo é aplicado em ordem e é idempotente.
// Retorna { state, legacySettings } — legacySettings vem do v1 e é repassado para config.js.
export function migrateWithSettings(data) {
  if (!data || typeof data !== 'object' || !data.grid || !Array.isArray(data.grid.tiles) || !data.res) throw new Error('Save inválido');
  const from = Number(data.version) || 1;
  if (from > SAVE_VERSION) throw new Error(`Save de uma versão mais nova do jogo (v${from})`);
  let legacySettings = null;
  if (from < 2) {
    // Prédio "Fonte" virou "Fogueira" (o pacote de arte não tem fonte d'água).
    for (const t of data.grid.tiles) if (t.b?.id === 'fonte') t.b.id = 'fogueira';
    data.raid = { dir: 'n', ...data.raid };
    // Quem já jogava v1 conhecia todas as abas: nada some.
    data.unlocks = { tabs: [...ALL_TABS] };
    legacySettings = data.settings ?? null;
    delete data.settings;
  }
  const base = createState({ seed: data.seed ?? 1, now: data.lastTick ?? Date.now() });
  const merged = { ...base, ...data, log: [] };
  merged.stats = { ...base.stats, ...data.stats };
  merged.items = { ...base.items, ...data.items };
  merged.social = { ...base.social, ...data.social };
  merged.raid = { ...base.raid, ...data.raid };
  merged.unlocks = { ...base.unlocks, ...data.unlocks };
  for (const h of Object.values(merged.heroes?.owned ?? {})) {
    h.level ??= 1;
    h.training ??= null;
  }
  // Saves de antes do resumo de Ascensão não têm a foto do início da rodada: o resumo mostra só o que é certo.
  merged.runBase = data.runBase ?? null;
  merged.runs = Array.isArray(data.runs) ? data.runs : [];
  merged.records = data.records && typeof data.records === 'object' ? data.records : {};
  merged.version = SAVE_VERSION;
  return { state: merged, legacySettings };
}

export function migrate(data) {
  return migrateWithSettings(data).state;
}
