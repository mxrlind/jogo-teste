// Mapa: grade 12x12 com anéis concêntricos de terra desbloqueável.
import { mulberry32, randInt } from './rng.js';

export const GRID_W = 12;
export const GRID_H = 12;
export const START_RING = 2; // 6x6 central
export const MAX_RING = 5;

// Custo para desbloquear o anel N (índice = anel).
export const RING_COSTS = {
  3: { gold: 2000, wood: 400 },
  4: { gold: 60000, stone: 4000 },
  5: { gold: 1000000, stone: 50000 },
};

export const idx = (x, y) => y * GRID_W + x;
export const inBounds = (x, y) => x >= 0 && y >= 0 && x < GRID_W && y < GRID_H;

export function ringOf(x, y) {
  const cx = (GRID_W - 1) / 2;
  const cy = (GRID_H - 1) / 2;
  return Math.max(Math.abs(x - cx), Math.abs(y - cy)) - 0.5;
}

export function isUnlocked(grid, x, y) {
  return ringOf(x, y) <= grid.ring;
}

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];

// Vizinhos ortogonais (apenas dentro da grade; bloqueio de terra não importa para adjacência).
export function neighbors(x, y) {
  const out = [];
  for (const [dx, dy] of DIRS) {
    const nx = x + dx;
    const ny = y + dy;
    if (inBounds(nx, ny)) out.push([nx, ny]);
  }
  return out;
}

// Muralha que se liga sozinha: quais vizinhos são muralha ou torre.
// Bits: 1 = norte, 2 = leste, 4 = sul, 8 = oeste (mesma ordem dos sprites de tools/render-kaykit.mjs).
const WALL_LINKS = new Set(['muralha', 'torre']);
export function wallMask(grid, x, y) {
  const linked = (nx, ny) => inBounds(nx, ny) && WALL_LINKS.has(grid.tiles[idx(nx, ny)].b?.id);
  return (linked(x, y - 1) ? 1 : 0) | (linked(x + 1, y) ? 2 : 0) | (linked(x, y + 1) ? 4 : 0) | (linked(x - 1, y) ? 8 : 0);
}

// Chave de adjacência de um tile: id da construção se houver, senão o terreno.
export function adjKey(tile) {
  return tile.b ? tile.b.id : tile.t;
}

function cluster(tiles, rand, type, size, startX, startY, allow) {
  let x = startX;
  let y = startY;
  for (let i = 0; i < size; i++) {
    if (inBounds(x, y) && allow(x, y)) tiles[idx(x, y)].t = type;
    const [dx, dy] = DIRS[Math.floor(rand() * 4)];
    x = Math.min(GRID_W - 1, Math.max(0, x + dx));
    y = Math.min(GRID_H - 1, Math.max(0, y + dy));
  }
}

export function generateMap(seed) {
  const rand = mulberry32(seed);
  const tiles = Array.from({ length: GRID_W * GRID_H }, () => ({ t: 'grass', b: null }));
  const isCenter = (x, y) => ringOf(x, y) <= 0;
  const notCenter = (x, y) => !isCenter(x, y);

  // Rio serpenteando pela borda (anéis externos)
  const vertical = rand() < 0.5;
  let pos = rand() < 0.5 ? 0 : 1;
  for (let i = 0; i < GRID_W; i++) {
    const x = vertical ? pos : i;
    const y = vertical ? i : pos;
    tiles[idx(x, y)].t = 'water';
    if (rand() < 0.3) pos = Math.min(1, Math.max(0, pos + (rand() < 0.5 ? -1 : 1)));
  }

  // Lago perto do centro
  cluster(tiles, rand, 'water', 3, randInt(rand, 3, 8), randInt(rand, 3, 8), (x, y) => notCenter(x, y) && ringOf(x, y) <= 2);

  // Florestas, rochas, montanhas
  for (let i = 0; i < 6; i++) cluster(tiles, rand, 'forest', randInt(rand, 3, 7), randInt(rand, 0, 11), randInt(rand, 0, 11), notCenter);
  for (let i = 0; i < 4; i++) cluster(tiles, rand, 'rock', randInt(rand, 2, 4), randInt(rand, 0, 11), randInt(rand, 0, 11), notCenter);
  for (let i = 0; i < 3; i++) {
    const side = randInt(rand, 0, 3);
    const a = randInt(rand, 1, 10);
    const [sx, sy] = [[a, 11], [a, 0], [0, a], [11, a]][side];
    cluster(tiles, rand, 'mountain', randInt(rand, 3, 5), sx, sy, (x, y) => ringOf(x, y) >= 3);
  }

  // Garantias do anel inicial: 2 florestas, 1 rocha, 1 água; e 1 montanha no anel 3.
  const ensure = (type, count, ringMin, ringMax) => {
    const cells = [];
    for (let y = 0; y < GRID_H; y++) for (let x = 0; x < GRID_W; x++) {
      const r = ringOf(x, y);
      if (r >= ringMin && r <= ringMax && !isCenter(x, y)) cells.push([x, y]);
    }
    let have = cells.filter(([x, y]) => tiles[idx(x, y)].t === type).length;
    const free = cells.filter(([x, y]) => tiles[idx(x, y)].t === 'grass');
    while (have < count && free.length) {
      const [x, y] = free.splice(Math.floor(rand() * free.length), 1)[0];
      tiles[idx(x, y)].t = type;
      have++;
    }
  };
  ensure('forest', 3, 1, 2);
  ensure('rock', 2, 1, 2);
  ensure('water', 1, 1, 2);
  ensure('mountain', 2, 3, 3);

  // Prédios iniciais: casa + fazenda no centro (a pesquisa: "começa com 1 casa, 1 produção")
  tiles[idx(5, 5)].b = { id: 'casa', lvl: 1 };
  tiles[idx(6, 5)].b = { id: 'fazenda', lvl: 1 };

  return { w: GRID_W, h: GRID_H, ring: START_RING, tiles };
}
