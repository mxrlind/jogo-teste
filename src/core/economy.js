// Economia: agrega modificadores e calcula produção, população, defesa e custos.
// Função pura: computeEconomy(state, now) não altera o estado.
import {
  BUILDINGS, TERRAIN, BASE_STORAGE, FOOD_PER_POP, COUNT_COST_GROWTH, LEVEL_COST_GROWTH, LEVEL_OUTPUT_STEP, MAX_LEVEL,
} from '../data/buildings.js';
import { HERO_BY_ID, HERO_LEVEL_STEP, TAVERN_COUNCIL_LEVELS } from '../data/heroes.js';
import { TALENT_BY_ID } from '../data/talents.js';
import { EVENT_BY_ID, REPAIR_FRACTION } from '../data/events.js';
import { seasonInfo } from './season.js';
import { GRID_W, GRID_H, neighbors, idx, adjKey, wallMask } from './map.js';
import { underMods, underEconomy } from './underground.js';

export const PROD_RES = ['gold', 'food', 'wood', 'stone'];

export function heroMultiplier(stars) {
  return 1 + 0.5 * (stars - 1);
}

export function heroLevelMult(level = 1) {
  return 1 + HERO_LEVEL_STEP * (level - 1);
}

// Multiplicador do bônus de um herói recrutado (estrelas e nível de treino).
export function heroStrength(owned) {
  return heroMultiplier(owned.stars) * heroLevelMult(owned.level);
}

export function heroPowerOf(hero, owned) {
  return Math.round(hero.power * owned.stars * heroLevelMult(owned.level));
}

// Maior nível de um tipo de prédio no mapa (0 se não houver nenhum).
export function maxLevelOf(state, id) {
  let lvl = 0;
  for (const t of state.grid.tiles) if (t.b?.id === id && t.b.lvl > lvl) lvl = t.b.lvl;
  return lvl;
}

// Soma de todos os modificadores ativos: talentos, conselho, temporada, evento e bênção.
export function collectModifiers(state, now) {
  const m = {
    prodAll: 0, prod: { gold: 0, food: 0, wood: 0, stone: 0 }, eventProd: { gold: 0, food: 0, wood: 0, stone: 0 },
    defense: 0, happiness: 0, cost: 0, raidLoot: 0, raidGems: 0, expedition: 0, terrainAdj: 0,
    offlineEff: 0, offlineHours: 0, councilSlots: 0, xp: 0, houseBonus: 0, landCost: 0,
    raidInterval: 1, eventRate: 1, crowns: 0, autoChest: false, startGold: 0, startWood: 0, startRing: 0,
  };

  for (const [id, lvl] of Object.entries(state.legacy)) {
    const t = TALENT_BY_ID[id];
    if (!t || !lvl) continue;
    const e = t.effect(lvl);
    for (const [k, v] of Object.entries(e)) {
      if (typeof v === 'boolean') m[k] = m[k] || v;
      else m[k] += v;
    }
  }

  const tavern = maxLevelOf(state, 'taverna');
  m.councilSlots += TAVERN_COUNCIL_LEVELS.filter((l) => tavern >= l).length;

  for (const hid of state.heroes.council) {
    const h = HERO_BY_ID[hid];
    const owned = state.heroes.owned[hid];
    if (!h || !owned) continue;
    const v = h.bonus.value * heroStrength(owned);
    const [type, res] = h.bonus.type.split(':');
    if (type === 'prod') m.prod[res] += v;
    else if (type === 'offline') { m.offlineEff += v; m.offlineHours += 4 * owned.stars; }
    else m[type] += v;
  }

  const season = seasonInfo(now).theme.mods;
  if (season.prod) for (const [r, v] of Object.entries(season.prod)) m.prod[r] += v;
  if (season.houseBonus) m.houseBonus += season.houseBonus;
  if (season.cost) m.cost += season.cost;
  if (season.defense) m.defense += season.defense;
  if (season.raidLoot) m.raidLoot += season.raidLoot;
  if (season.raidInterval) m.raidInterval *= season.raidInterval;
  if (season.landCost) m.landCost += season.landCost;
  if (season.expedition) m.expedition += season.expedition;
  if (season.eventRate) m.eventRate *= season.eventRate;
  if (season.happiness) m.happiness += season.happiness;
  if (season.crowns) m.crowns += season.crowns;

  if (state.event && state.event.endsAt > now) {
    const ev = EVENT_BY_ID[state.event.id];
    if (ev?.mods.prod) for (const [r, v] of Object.entries(ev.mods.prod)) m.eventProd[r] += v;
    if (ev?.mods.cost) m.cost += ev.mods.cost;
    if (ev?.mods.xp) m.xp += ev.mods.xp;
    if (ev?.mods.raidLoot) m.raidLoot += ev.mods.raidLoot;
  }

  // Subsolo: Forja de Magma (+produção geral) e Adega (+comida).
  const um = underMods(state);
  m.prodAll += um.prodAll;
  m.prod.food += um.food;

  if (state.boostUntil > now) m.prodAll += 0.5;
  m.cost = Math.min(0.75, m.cost);
  return m;
}

export function levelMult(lvl) {
  return 1 + LEVEL_OUTPUT_STEP * (lvl - 1);
}

// Armazéns crescem com o quadrado do nível para acompanhar custos exponenciais.
export function storageMult(lvl) {
  return lvl * lvl;
}

export function workersFor(def, lvl) {
  return def.workers + Math.floor((lvl - 1) * def.workers * 0.5);
}

const isTerrainKey = (k) => k in TERRAIN;

// Peso de uma defesa em (x, y) contra uma horda vinda de `dir`: 100% na borda de onde ela vem,
// 50% na borda oposta. Assim a posição de torres e muralhas importa (pilar "o lugar importa").
export function dirWeight(dir, x, y) {
  const fy = y / (GRID_H - 1);
  const fx = x / (GRID_W - 1);
  const near = { n: 1 - fy, s: fy, w: 1 - fx, e: fx }[dir] ?? 0.5;
  return 0.5 + 0.5 * near;
}

// Muralha torta: de frente para a horda (atravessada no caminho dela) conta inteira; de lado, só metade.
// Uma muralha leste-oeste segura hordas do norte e do sul; uma norte-sul segura as do leste e do oeste.
// Cantos e cruzamentos têm os dois lados. Muralha sozinha não tem lado e conta inteira.
export const SIDEWAYS_WALL = 0.5;
export function wallFacing(mask, dir) {
  if (!mask) return 1;
  const across = dir === 'n' || dir === 's' ? mask & 10 : mask & 5;
  return across ? 1 : SIDEWAYS_WALL;
}

// Peso total de uma defesa: lado do mapa e, para muralhas, a direção em que ela está virada.
export function defenseWeight(state, id, dir, x, y) {
  const w = dirWeight(dir, x, y);
  return id === 'muralha' ? w * wallFacing(wallMask(state.grid, x, y), dir) : w;
}

// Bônus de adjacência de um prédio hipotético `id` na posição (x, y).
export function adjacencyAt(state, id, x, y, mods) {
  const def = BUILDINGS[id];
  const parts = [];
  let total = 0;
  let hasRequired = !def.requiresAdj;
  for (const [nx, ny] of neighbors(x, y)) {
    const nt = state.grid.tiles[idx(nx, ny)];
    const key = adjKey(nt);
    if (def.requiresAdj && key === def.requiresAdj) hasRequired = true;
    let v = def.adj[key] || 0;
    if (v > 0 && isTerrainKey(key)) v *= 1 + (mods?.terrainAdj || 0);
    if (v !== 0) {
      parts.push({ x: nx, y: ny, key, value: v });
      total += v;
    }
  }
  return { total, parts, hasRequired };
}

export function computeEconomy(state, now) {
  const mods = collectModifiers(state, now);
  const tiles = new Array(state.grid.tiles.length).fill(null);
  let popCap = 0;
  let workersNeeded = 0;
  let happinessRaw = 50 + mods.happiness;
  let globalGold = 0;
  let crownBonus = 0;
  const caps = { ...BASE_STORAGE };

  // 1ª passada: estrutura (adjacência, população, trabalhadores, felicidade, armazenamento)
  state.grid.tiles.forEach((tile, i) => {
    if (!tile.b) return;
    const def = BUILDINGS[tile.b.id];
    if (!def) return;
    const x = i % GRID_W;
    const y = Math.floor(i / GRID_W);
    const lm = levelMult(tile.b.lvl);
    const adj = adjacencyAt(state, tile.b.id, x, y, mods);
    // Danificada por uma horda: não produz, não defende e não ocupa moradores até ser consertada.
    const damaged = !!tile.b.dmg;
    const info = {
      id: tile.b.id, lvl: tile.b.lvl, adjBonus: adj.total, adjParts: adj.parts, damaged,
      active: adj.hasRequired && !damaged, mult: Math.max(0, 1 + adj.total) * lm, workers: damaged ? 0 : workersFor(def, tile.b.lvl),
      out: {}, defense: 0,
    };
    tiles[i] = info;
    // Moradores e estoque continuam (a casa rachada ainda abriga gente); o resto para.
    if (def.popCap) popCap += def.popCap * tile.b.lvl;
    if (def.storage) for (const [r, v] of Object.entries(def.storage)) caps[r] += v * storageMult(tile.b.lvl);
    if (damaged) return;
    workersNeeded += info.workers;
    if (def.happiness) happinessRaw += def.happiness * (def.happiness > 0 ? info.mult : 1);
    if (def.globalGold) globalGold += def.globalGold;
    if (def.crownBonus) crownBonus += def.crownBonus;
  });

  const pop = state.pop;
  happinessRaw -= 2 * Math.floor(pop / 20);
  const happiness = Math.max(0, Math.min(100, happinessRaw));
  const happinessMult = 0.5 + happiness / 100;
  const staffing = workersNeeded > 0 ? Math.min(1, pop / workersNeeded) : 1;
  // Moradores ocupam primeiro as vagas que produzem comida. Sem isso, a fome tira gente
  // das fazendas na mesma proporção que do resto e o reino nunca se recupera.
  let foodWorkers = 0;
  tiles.forEach((info) => { if (info && info.active && BUILDINGS[info.id].prod?.food) foodWorkers += info.workers; });
  const foodStaffing = foodWorkers > 0 ? Math.min(1, pop / foodWorkers) : 1;
  const otherWorkers = workersNeeded - foodWorkers;
  const otherStaffing = otherWorkers > 0 ? Math.max(0, Math.min(1, (pop - foodWorkers) / otherWorkers)) : 1;
  const occupancy = popCap > 0 ? Math.min(1, pop / popCap) : 0;

  const prodMult = {};
  for (const r of PROD_RES) {
    prodMult[r] = (1 + mods.prodAll + mods.prod[r]) * (1 + mods.eventProd[r]) * (r === 'gold' ? 1 + globalGold : 1);
  }

  // 2ª passada: produção bruta
  const gross = { gold: 0, food: 0, wood: 0, stone: 0 };
  let foodDemandMarkets = 0;
  const defDir = { n: 0, s: 0, e: 0, w: 0 };
  const marketTiles = [];
  tiles.forEach((info, i) => {
    if (!info) return;
    const def = BUILDINGS[info.id];
    const staff = info.workers === 0 ? 1 : info.active && def.prod?.food ? foodStaffing : otherStaffing;
    info.staff = staff;
    const eff = info.active ? info.mult * staff : 0;
    if (def.prod) {
      for (const [r, base] of Object.entries(def.prod)) {
        let v = base * eff * happinessMult * prodMult[r];
        if (def.id === 'casa') v *= occupancy * (1 + mods.houseBonus);
        info.out[r] = v;
        gross[r] += v;
      }
    }
    if (def.consume?.food) {
      const c = def.consume.food * levelMult(info.lvl) * staff;
      info.consume = c;
      foodDemandMarkets += c;
      marketTiles.push(info);
    }
    if (def.defense && !info.damaged) {
      info.defense = def.defense * eff;
      const x = i % GRID_W;
      const y = Math.floor(i / GRID_W);
      for (const d of Object.keys(defDir)) defDir[d] += info.defense * defenseWeight(state, info.id, d, x, y);
    }
  });

  // Subsolo: salas não usam moradores, mas seguem felicidade e multiplicadores globais.
  const under = underEconomy(state, (r) => happinessMult * prodMult[r]);
  for (const r of PROD_RES) gross[r] += under.gross[r];
  for (const [r, v] of Object.entries(under.caps)) caps[r] += v;

  // Comida: moradores comem primeiro; mercados só convertem o que sobra quando o estoque acabou.
  const foodPop = pop * FOOD_PER_POP;
  let marketRatio = 1;
  if (state.res.food <= 0.01 && foodDemandMarkets > 0) {
    const available = Math.max(0, gross.food - foodPop);
    marketRatio = Math.min(1, available / foodDemandMarkets);
  }
  for (const info of marketTiles) {
    if (marketRatio < 1) {
      gross.gold -= info.out.gold * (1 - marketRatio);
      info.out.gold *= marketRatio;
      info.consume *= marketRatio;
    }
  }
  const foodConsumption = foodPop + foodDemandMarkets * marketRatio;

  // Heróis do conselho somam poder à defesa.
  let heroPower = 0;
  for (const hid of state.heroes.council) {
    const owned = state.heroes.owned[hid];
    if (owned && !owned.expedition && HERO_BY_ID[hid]) heroPower += heroPowerOf(HERO_BY_ID[hid], owned);
  }
  const defenseByDir = {};
  for (const d of Object.keys(defDir)) defenseByDir[d] = (defDir[d] + heroPower) * (1 + mods.defense);
  const defense = defenseByDir[state.raid?.dir] ?? defenseByDir.n;

  const rates = {
    gold: gross.gold,
    food: gross.food - foodConsumption,
    wood: gross.wood,
    stone: gross.stone,
  };

  return {
    mods, tiles, rates, gross, foodConsumption, popCap, workersNeeded, staffing, occupancy,
    happiness, happinessMult, defense, defenseByDir, heroPower, caps, crownBonus, marketRatio, under: under.levels,
  };
}

export function countOf(state, id) {
  let n = 0;
  for (const t of state.grid.tiles) if (t.b?.id === id) n++;
  return n;
}

function scaleCost(cost, factor) {
  const out = {};
  for (const [r, v] of Object.entries(cost)) out[r] = Math.ceil(v * factor);
  return out;
}

export function buildCost(state, id, mods) {
  const def = BUILDINGS[id];
  return scaleCost(def.cost, COUNT_COST_GROWTH ** countOf(state, id) * (1 - mods.cost));
}

export function upgradeCost(id, lvl, mods) {
  const def = BUILDINGS[id];
  if (lvl >= (def.maxLevel ?? MAX_LEVEL)) return null;
  return scaleCost(def.cost, LEVEL_COST_GROWTH ** lvl * (1 - mods.cost));
}

// Conserto de uma construção danificada: uma fração do custo base, maior quanto mais alto o nível.
export function repairCost(id, lvl, mods) {
  return scaleCost(BUILDINGS[id].cost, REPAIR_FRACTION * lvl * (1 - mods.cost));
}

export function canAfford(res, cost) {
  return Object.entries(cost).every(([r, v]) => (res[r] || 0) >= v);
}

export function pay(res, cost) {
  for (const [r, v] of Object.entries(cost)) res[r] -= v;
}

export function refund(res, cost, fraction) {
  for (const [r, v] of Object.entries(cost)) res[r] = (res[r] || 0) + Math.floor(v * fraction);
}

// "Poder do Reino": pontuação usada no ranking social.
export function kingdomPower(state) {
  const buildings = state.grid.tiles.reduce((s, t) => s + (t.b ? t.b.lvl : 0), 0);
  const stars = Object.values(state.heroes.owned).reduce((s, h) => s + h.stars, 0);
  const levels = Object.values(state.heroes.owned).reduce((s, h) => s + (h.level || 1) - 1, 0);
  return Math.floor(Math.sqrt(state.stats.totalGold) + buildings * 10 + stars * 40 + levels * 15 + state.stats.ascensions * 500 + state.stats.raidsWon * 15);
}
