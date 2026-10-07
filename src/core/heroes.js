// Heróis: recrutamento (sem dinheiro real), conselho e expedições.
import {
  HEROES, HERO_BY_ID, RARITIES, MAX_STARS, BASE_COUNCIL_SLOTS, RECRUIT_GOLD_BASE, RECRUIT_GOLD_GROWTH, RECRUIT_GEM_COST, EXPEDITIONS,
  TAVERN_RECRUIT_DISCOUNT, HERO_MAX_LEVEL, TRAIN_COST, TRAIN_COST_GROWTH, TRAIN_RARITY_COST, TRAIN_SECONDS,
} from '../data/heroes.js';
import { weightedPick, pick, randInt } from './rng.js';
import { maxLevelOf, countOf, heroPowerOf } from './economy.js';

export function councilSlots(mods) {
  return BASE_COUNCIL_SLOTS + (mods.councilSlots || 0);
}

// Desconto da taverna mais alta no recrutamento com ouro (nível 1 = sem desconto, nível 10 = -36%).
export function tavernDiscount(state) {
  return TAVERN_RECRUIT_DISCOUNT * Math.max(0, maxLevelOf(state, 'taverna') - 1);
}

export function recruitGoldCost(state) {
  return Math.ceil(RECRUIT_GOLD_BASE * RECRUIT_GOLD_GROWTH ** state.stats.goldRecruits * (1 - tavernDiscount(state)));
}

// ---- Quartel ----
// Nível máximo de treino: nível do quartel mais alto + 1 (sem quartel, ninguém treina).
export function heroLevelCap(state) {
  const q = maxLevelOf(state, 'quartel');
  return q ? Math.min(HERO_MAX_LEVEL, q + 1) : 1;
}

// Cada quartel treina um herói por vez.
export function trainingSlots(state) {
  return countOf(state, 'quartel');
}

export function trainingCount(state) {
  return Object.values(state.heroes.owned).filter((h) => h.training).length;
}

export function trainCost(hero, level) {
  const f = TRAIN_COST_GROWTH ** (level - 1) * TRAIN_RARITY_COST[hero.rarity];
  return Object.fromEntries(Object.entries(TRAIN_COST).map(([r, v]) => [r, Math.ceil(v * f)]));
}

export function trainSeconds(level) {
  return TRAIN_SECONDS * level;
}

export function recruitCost(state, method) {
  if (method === 'gold') return { gold: recruitGoldCost(state) };
  if (method === 'gems') return { gems: RECRUIT_GEM_COST };
  return { scrolls: 1 };
}

export function rollHero(rand) {
  const rarity = weightedPick(rand, Object.values(RARITIES), (r) => r.weight);
  return pick(rand, HEROES.filter((h) => h.rarity === rarity.id));
}

// Adiciona o herói (ou estrela, se duplicado). Retorna { hero, isNew, stars, gemsRefund }.
export function addHero(state, hero) {
  const owned = state.heroes.owned[hero.id];
  if (!owned) {
    state.heroes.owned[hero.id] = { stars: 1, level: 1, expedition: null, training: null };
    return { hero, isNew: true, stars: 1, gemsRefund: 0 };
  }
  if (owned.stars < MAX_STARS) {
    owned.stars++;
    return { hero, isNew: false, stars: owned.stars, gemsRefund: 0 };
  }
  const refundGems = { comum: 2, raro: 5, epico: 10, lendario: 25 }[hero.rarity];
  state.res.gems += refundGems;
  return { hero, isNew: false, stars: owned.stars, gemsRefund: refundGems };
}

export function expeditionReward(state, hero, exp, econ, rand) {
  const owned = state.heroes.owned[hero.id];
  const power = heroPowerOf(hero, owned);
  const mult = (1 + power * 0.02) * (1 + econ.mods.expedition);
  const reward = {
    gold: Math.floor(Math.max(30, econ.rates.gold * exp.duration * 0.4) * mult),
    wood: Math.floor(Math.max(10, econ.gross.wood * exp.duration * 0.3) * mult),
    stone: Math.floor(Math.max(5, econ.gross.stone * exp.duration * 0.3) * mult),
    gems: 0,
    scrolls: 0,
  };
  if (rand() < exp.gemChance) reward.gems = randInt(rand, exp.gems[0], exp.gems[1]);
  if (rand() < exp.scrollChance) reward.scrolls = 1;
  return reward;
}

export function speedUpCost(remainingSec) {
  return Math.max(1, Math.ceil(remainingSec / 600));
}

export { EXPEDITIONS, HERO_BY_ID };
