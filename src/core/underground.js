// Subsolo: geração dos níveis, névoa, custos e a parte da economia que vem lá de baixo.
// Funções puras sobre `state.under`; as ações (cavar, construir salas) ficam em Game (src/core/game.js).
import {
  DEPTHS, UNDER_TILES, ROOMS, DIG_BASE, DIG_DEPTH_GROWTH, DIG_COUNT_GROWTH, DIG_YIELD, STAIRS_COST,
} from '../data/underground.js';
import { LEVEL_COST_GROWTH, LEVEL_OUTPUT_STEP } from '../data/buildings.js';
import { mulberry32, randInt } from './rng.js';
import { GRID_W, GRID_H, idx, inBounds, neighbors } from './map.js';

const DIRS8 = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

export function neighbors8(x, y) {
  const out = [];
  for (const [dx, dy] of DIRS8) if (inBounds(x + dx, y + dy)) out.push([x + dx, y + dy]);
  return out;
}

export const isOpen = (tile) => !!UNDER_TILES[tile.t]?.open;
export const isWall = (tile) => !!UNDER_TILES[tile.t]?.wall;

function blob(tiles, rand, type, size, allow) {
  let x = randInt(rand, 0, GRID_W - 1);
  let y = randInt(rand, 0, GRID_H - 1);
  for (let i = 0; i < size; i++) {
    if (allow(tiles[idx(x, y)])) tiles[idx(x, y)].t = type;
    const [dx, dy] = DIRS8[Math.floor(rand() * 4)];
    x = Math.min(GRID_W - 1, Math.max(0, x + dx));
    y = Math.min(GRID_H - 1, Math.max(0, y + dy));
  }
}

// Quantos aglomerados de cada tipo por nível (índice 0 = nível 1): [quantidade, tamanho mínimo, máximo].
const LAYOUT = [
  { gold: [3, 2, 4], water: [2, 4, 7] },
  { gold: [4, 2, 5], gem: [2, 1, 3], cavern: [2, 9, 15], water: [1, 3, 5] },
  { gold: [5, 3, 6], gem: [3, 2, 4], cavern: [1, 6, 10], magma: [2, 5, 8] },
];

export function generateLevel(seed, d) {
  const rand = mulberry32((seed * 31 + d * 7919) >>> 0);
  const tiles = Array.from({ length: GRID_W * GRID_H }, () => ({ t: 'rock', s: false, b: null }));
  const order = ['magma', 'water', 'cavern', 'gold', 'gem'];
  for (const type of order) {
    const spec = LAYOUT[d - 1][type];
    if (!spec) continue;
    const [n, min, max] = spec;
    // Cada tipo só ocupa rocha: caverna, água, magma e veios não se sobrepõem.
    const allow = (t) => t.t === 'rock';
    for (let i = 0; i < n; i++) blob(tiles, rand, type, randInt(rand, min, max), allow);
  }
  return { tiles };
}

export function createUnder(seed) {
  return { levels: Array.from({ length: DEPTHS }, (_, i) => generateLevel(seed, i + 1)), reached: 0 };
}

export const levelOf = (state, d) => state.under.levels[d - 1];
export const underTile = (state, d, x, y) => state.under.levels[d - 1].tiles[idx(x, y)];

// Revela os 8 vizinhos de um espaço aberto. Ao encostar numa caverna, revela a caverna inteira
// (o momento "rompemos uma caverna!" do Dwarf Fortress). Devolve quantos tiles de caverna apareceram.
export function revealAround(level, x, y) {
  let cavern = 0;
  const stack = [[x, y]];
  const seenCave = new Set();
  level.tiles[idx(x, y)].s = true;
  while (stack.length) {
    const [cx, cy] = stack.pop();
    for (const [nx, ny] of neighbors8(cx, cy)) {
      const t = level.tiles[idx(nx, ny)];
      t.s = true;
      if (t.t === 'cavern' && !seenCave.has(idx(nx, ny))) {
        seenCave.add(idx(nx, ny));
        stack.push([nx, ny]);
      }
    }
  }
  for (const i of seenCave) if (!level.tiles[i].found) { level.tiles[i].found = true; cavern++; }
  return cavern;
}

// Abre um tile (entrada de escada): vira chão, ganha a marca da escada e revela os vizinhos.
export function openAt(level, x, y, stairs) {
  const t = level.tiles[idx(x, y)];
  if (!isOpen(t)) t.t = 'floor';
  t.b = null;
  t.st = stairs;
  return revealAround(level, x, y);
}

export function dugCount(level) {
  let n = 0;
  for (const t of level.tiles) if (t.t === 'floor') n++;
  return n;
}

export function digCost(state, d, mods) {
  const f = DIG_DEPTH_GROWTH ** (d - 1) * DIG_COUNT_GROWTH ** dugCount(levelOf(state, d)) * (1 - (mods?.cost || 0));
  return Object.fromEntries(Object.entries(DIG_BASE).map(([r, v]) => [r, Math.ceil(v * f)]));
}

export const digYield = (type, d) => DIG_YIELD[type]?.[d - 1] ?? {};
export const stairsCost = (d) => STAIRS_COST[d - 1] ?? null;

// Dá para cavar se for rocha/veio e encostar (ortogonal) num espaço aberto.
export function canReach(level, x, y) {
  return neighbors(x, y).some(([nx, ny]) => isOpen(level.tiles[idx(nx, ny)]));
}

export function roomCount(state, id) {
  let n = 0;
  for (const lv of state.under.levels) for (const t of lv.tiles) if (t.b?.id === id) n++;
  return n;
}

function scale(cost, f) {
  return Object.fromEntries(Object.entries(cost).map(([r, v]) => [r, Math.ceil(v * f)]));
}

export function roomCost(state, id, mods) {
  return scale(ROOMS[id].cost, 1.15 ** roomCount(state, id) * (1 - (mods?.cost || 0)));
}

export function roomUpgradeCost(id, lvl, mods) {
  const def = ROOMS[id];
  if (lvl >= def.maxLevel) return null;
  return scale(def.cost, LEVEL_COST_GROWTH ** lvl * (1 - (mods?.cost || 0)));
}

const roomLevelMult = (lvl) => 1 + LEVEL_OUTPUT_STEP * (lvl - 1);

// Bônus de vizinhos de uma sala (hipotética ou construída) em (x, y) no nível.
export function roomAdjacency(level, id, x, y) {
  const def = ROOMS[id];
  let total = 0;
  let hasRequired = !def.requiresAdj;
  const parts = [];
  let skipped = false;
  for (const [nx, ny] of neighbors(x, y)) {
    const nt = level.tiles[idx(nx, ny)];
    const key = nt.b ? nt.b.id : nt.t;
    if (def.requiresAdj && key === def.requiresAdj) hasRequired = true;
    let v = def.adj[key] || 0;
    if (!v && def.adj.wall && isWall(nt)) v = def.adj.wall;
    // Garimpo: o primeiro veio é o que faz funcionar; os seguintes dão bônus.
    if (v && def.adjSkipFirst && key === def.requiresAdj && !skipped) { skipped = true; v = 0; }
    if (v) { total += v; parts.push({ x: nx, y: ny, key: nt.b ? nt.b.id : UNDER_TILES[nt.t] ? nt.t : key, value: v }); }
  }
  return { total, parts, hasRequired };
}

// Modificadores globais que vêm do subsolo (somados em collectModifiers).
export function underMods(state) {
  const m = { prodAll: 0, food: 0 };
  if (!state.under) return m;
  for (let d = 1; d <= DEPTHS; d++) {
    const lv = levelOf(state, d);
    lv.tiles.forEach((t, i) => {
      if (!t.b) return;
      const def = ROOMS[t.b.id];
      if (def.prodAll && roomAdjacency(lv, t.b.id, i % GRID_W, Math.floor(i / GRID_W)).hasRequired) m.prodAll += def.prodAll * t.b.lvl;
      if (def.foodBonus) m.food += def.foodBonus * t.b.lvl;
    });
  }
  return m;
}

// Produção e armazenamento das salas. `mult(r)` = multiplicador global do recurso (felicidade, heróis, eventos).
export function underEconomy(state, mult) {
  const gross = { gold: 0, food: 0, wood: 0, stone: 0 };
  const caps = {};
  const levels = [];
  if (!state.under) return { gross, caps, levels };
  for (let d = 1; d <= DEPTHS; d++) {
    const lv = levelOf(state, d);
    const infos = new Array(lv.tiles.length).fill(null);
    lv.tiles.forEach((t, i) => {
      if (!t.b) return;
      const def = ROOMS[t.b.id];
      const adj = roomAdjacency(lv, t.b.id, i % GRID_W, Math.floor(i / GRID_W));
      const info = { id: t.b.id, lvl: t.b.lvl, active: adj.hasRequired, adjBonus: adj.total, adjParts: adj.parts, out: {} };
      const eff = adj.hasRequired ? (1 + adj.total) * roomLevelMult(t.b.lvl) : 0;
      for (const [r, base] of Object.entries(def.prod ?? {})) {
        info.out[r] = base * eff * mult(r);
        gross[r] += info.out[r];
      }
      for (const [r, v] of Object.entries(def.storage ?? {})) caps[r] = (caps[r] || 0) + v * t.b.lvl * t.b.lvl;
      infos[i] = info;
    });
    levels.push(infos);
  }
  return { gross, caps, levels };
}
