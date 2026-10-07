// Camada social assíncrona: reinos vizinhos simulados + compartilhamento real de reino por código.
// Os vizinhos são determinísticos (semente do jogador); o design para backend real está em docs/ARQUITETURA.md.
import { mulberry32, hashString, randInt, pick } from './rng.js';
import { BUILDINGS, BUILDING_ORDER } from '../data/buildings.js';
import { BANNERS, EMBLEMS } from '../data/cosmetics.js';
import { generateMap, GRID_W, GRID_H, ringOf } from './map.js';

const SYL_A = ['Val', 'Mor', 'Bel', 'Cas', 'Dra', 'Fen', 'Gor', 'Lum', 'Nor', 'Ros', 'Tar', 'Zan', 'Aur', 'Pra'];
const SYL_B = ['dor', 'vale', 'mar', 'tânia', 'gard', 'lis', 'brasa', 'fundo', 'pedra', 'luz', 'monte', 'rio'];
const RULERS = ['Rei Otávio', 'Rainha Lúcia', 'Duque Ferraz', 'Baronesa Ivy', 'Lorde Cássio', 'Imperatriz Yara', 'Conde Bruno', 'Sultão Amir', 'Chefe Taíra', 'Mago Olavo'];
const TITLES = ['Fundador', 'Prefeito', 'Guardião', 'Magnata', 'Conquistador', 'Urbanista', 'Colecionador', 'Imperador'];

export const RIVAL_COUNT = 9;

export function generateRivals(seed, now, createdAt) {
  const rand = mulberry32(hashString('rivais-' + seed));
  const hours = Math.max(0, (now - createdAt) / 3600000);
  const rivals = [];
  for (let i = 0; i < RIVAL_COUNT; i++) {
    const base = 40 * 3.2 ** i * (0.7 + rand() * 0.6);
    const growth = 0.02 + rand() * 0.06;
    const power = Math.floor(base * (1 + hours * growth) ** 1.3);
    rivals.push({
      id: `r${i}`,
      seed: hashString(`rival-${seed}-${i}`),
      name: pick(rand, SYL_A) + pick(rand, SYL_B),
      ruler: pick(rand, RULERS),
      title: TITLES[Math.min(TITLES.length - 1, Math.floor(i * 0.9))],
      banner: pick(rand, BANNERS.filter((b) => b.free || b.price)).id,
      emblem: pick(rand, EMBLEMS.filter((e) => e.free || e.price)).id,
      power,
      tier: i,
    });
  }
  return rivals;
}

// Cidade de um rival gerada a partir do poder (quanto mais poder, mais densa e nivelada).
export function rivalGrid(rival) {
  const grid = generateMap(rival.seed);
  const rand = mulberry32(rival.seed ^ 0x9e3779b9);
  grid.ring = Math.min(5, 2 + Math.floor(rival.tier / 2));
  const density = Math.min(0.85, 0.3 + rival.tier * 0.07);
  const maxLvl = Math.min(10, 1 + rival.tier);
  const choices = BUILDING_ORDER.filter((id) => id !== 'mina');
  grid.tiles.forEach((t, i) => {
    const x = i % GRID_W;
    const y = Math.floor(i / GRID_W);
    if (t.t !== 'grass' || ringOf(x, y) > grid.ring || t.b) return;
    if (rand() < density) t.b = { id: pick(rand, choices), lvl: randInt(rand, 1, maxLvl) };
  });
  return grid;
}

// ---- Código do Reino (compartilhamento real, sem servidor) ----
const TERRAIN_CODE = { grass: 'g', forest: 'f', rock: 'r', water: 'w', mountain: 'm' };
const CODE_TERRAIN = Object.fromEntries(Object.entries(TERRAIN_CODE).map(([k, v]) => [v, k]));
// Ordem fixa das letras: prédio novo entra no fim, para códigos antigos continuarem válidos.
const CODE_ORDER = [
  'casa', 'fazenda', 'serraria', 'pedreira', 'mercado', 'moinho', 'armazem',
  'taverna', 'muralha', 'torre', 'mina', 'templo', 'jardim', 'fogueira', 'estatua', 'quartel',
];
const BUILD_CODE = Object.fromEntries(CODE_ORDER.map((id, i) => [id, String.fromCharCode(65 + i)]));
const CODE_BUILD = Object.fromEntries(Object.entries(BUILD_CODE).map(([k, v]) => [v, k]));

export function encodeKingdom(state, power) {
  const cells = state.grid.tiles.map((t) => TERRAIN_CODE[t.t] + (t.b ? BUILD_CODE[t.b.id] + t.b.lvl : '')).join('');
  const payload = { v: 1, n: state.kingdom.name, b: state.kingdom.banner, e: state.kingdom.emblem, t: state.kingdom.title, r: state.grid.ring, p: power, c: cells };
  return 'RB1.' + btoa(unescape(encodeURIComponent(JSON.stringify(payload))));
}

export function decodeKingdom(code) {
  const raw = code.trim();
  if (!raw.startsWith('RB1.')) throw new Error('Código de reino inválido');
  const p = JSON.parse(decodeURIComponent(escape(atob(raw.slice(4)))));
  const tiles = [];
  const re = /([gfrwm])([A-Z]\d{1,2})?/g;
  let m;
  while ((m = re.exec(p.c)) !== null) {
    const b = m[2] ? { id: CODE_BUILD[m[2][0]], lvl: Math.min(10, Number(m[2].slice(1))) } : null;
    tiles.push({ t: CODE_TERRAIN[m[1]], b: b && BUILDINGS[b.id] ? b : null });
  }
  if (tiles.length !== GRID_W * GRID_H) throw new Error('Código de reino corrompido');
  return {
    name: String(p.n).slice(0, 24), banner: p.b, emblem: p.e, title: String(p.t).slice(0, 30), power: Number(p.p) || 0,
    grid: { w: GRID_W, h: GRID_H, ring: Math.min(5, Number(p.r) || 2), tiles },
  };
}
