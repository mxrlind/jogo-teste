// Heróis: recrutamento (sem dinheiro real), conselho e expedições.
import {
  HEROES, HERO_BY_ID, RARITIES, MAX_STARS, BASE_COUNCIL_SLOTS, RECRUIT_GOLD_BASE, RECRUIT_GOLD_GROWTH, RECRUIT_GEM_COST, EXPEDITIONS,
} from '../data/heroes.js';
import { weightedPick, pick, randInt } from './rng.js';

export function councilSlots(mods) {
  return BASE_COUNCIL_SLOTS + (mods.councilSlots || 0);
}

export function recruitGoldCost(state) {
  return Math.ceil(RECRUIT_GOLD_BASE * RECRUIT_GOLD_GROWTH ** state.stats.goldRecruits);
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
    state.heroes.owned[hero.id] = { stars: 1, expedition: null };
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
  const power = hero.power * owned.stars;
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
