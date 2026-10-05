// Prévia de estilo: desenha um reino de exemplo com os assets reais propostos.
// Usa o gerador de mapa e as regras de adjacência do jogo (src/core), sem o resto do motor.
import { generateMap, GRID_W, GRID_H, idx, isUnlocked, ringOf, neighbors } from '../core/map.js';
import { adjacencyAt } from '../core/economy.js';
import { BUILDINGS, TERRAIN } from '../data/buildings.js';
import { HEROES, RARITIES } from '../data/heroes.js';
import { TERRAIN_SPRITES, BUILDING_SPRITES, LOCKED_OVERLAY, icon, allSpriteUrls } from '../ui/sprites.js';

const NAMES = { ...Object.fromEntries(Object.entries(BUILDINGS).map(([k, v]) => [k, v.name])), fonte: 'Fogueira' };
const SEED = 20261005;
const grid = generateMap(SEED);
grid.ring = 3;
const state = { grid };
const mods = { terrainAdj: 0 };

// Posiciona prédios buscando o maior bônus de adjacência (regras reais do jogo).
const ORDER = ['serraria', 'casa', 'casa', 'mercado', 'casa', 'casa', 'fazenda', 'moinho', 'fazenda', 'pedreira', 'taverna',
  'armazem', 'torre', 'muralha', 'muralha', 'templo', 'jardim', 'fonte', 'estatua', 'casa', 'mina'];
for (const id of ORDER) {
  let best = null;
  grid.tiles.forEach((tile, i) => {
    const x = i % GRID_W;
    const y = Math.floor(i / GRID_W);
    if (tile.b || tile.t !== 'grass' || !isUnlocked(grid, x, y)) return;
    const a = adjacencyAt(state, id, x, y, mods);
    if (!a.hasRequired) return;
    const score = a.total - ringOf(x, y) * 0.01; // empate: mais perto do centro
    if (!best || score > best.score) best = { i, score };
  });
  if (best) grid.tiles[best.i].b = { id, lvl: 1 + (id === 'casa' ? best.i % 3 : 0) };
}

// ---------------------------------------------------------------- carregamento de imagens
const images = new Map();
function load(url) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => { images.set(url, img); resolve(); };
    img.onerror = () => { console.error('Falha ao carregar', url); resolve(); };
    img.src = url;
  });
}

const canvas = document.getElementById('map');
const ctx = canvas.getContext('2d');
const T = canvas.width / GRID_W;
const pick = (arr, i) => arr[i % arr.length];
let hover = null;

function drawImg(url, x, y, w, h) {
  const img = images.get(url);
  if (img) ctx.drawImage(img, x, y, w, h);
}

function label(cx, cy, text, color) {
  ctx.font = `800 ${Math.round(T * 0.24)}px Nunito, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const w = ctx.measureText(text).width + 12;
  const h = T * 0.34;
  ctx.fillStyle = 'rgba(43, 42, 51, 0.88)';
  ctx.beginPath();
  ctx.roundRect(cx - w / 2, cy - h / 2, w, h, h / 2);
  ctx.fill();
  ctx.fillStyle = color;
  ctx.fillText(text, cx, cy + 1);
}

function draw(now) {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  for (let y = 0; y < GRID_H; y++) {
    for (let x = 0; x < GRID_W; x++) {
      const i = idx(x, y);
      const tile = grid.tiles[i];
      const spr = TERRAIN_SPRITES[tile.t];
      const base = tile.b ? pick(TERRAIN_SPRITES.grass.base, i) : pick(spr.base, i * 7 + 3);
      drawImg(base, x * T, y * T, T + 0.5, T + 0.5);
      if (!tile.b && spr.over) drawImg(pick(spr.over, i), x * T + T * 0.05, y * T + T * 0.05, T * 0.9, T * 0.9);
      if (tile.b) {
        const b = BUILDING_SPRITES[tile.b.id];
        if (b.full) drawImg(b.src, x * T, y * T, T, T);
        else drawImg(b.src, x * T + T * 0.04, y * T + T * 0.02, T * 0.92, T * 0.92);
        if (b.blades) {
          ctx.save();
          ctx.translate(x * T + T * 0.5, y * T + T * 0.42);
          ctx.rotate(now / 900);
          drawImg(b.blades, -T * 0.42, -T * 0.42, T * 0.84, T * 0.84);
          ctx.restore();
        }
      }
      if (!isUnlocked(grid, x, y)) {
        ctx.fillStyle = LOCKED_OVERLAY;
        ctx.fillRect(x * T, y * T, T + 0.5, T + 0.5);
      }
    }
  }
  // borda do território
  const lo = Math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5);
  const span = (GRID_W - 2 * lo) * T;
  ctx.setLineDash([10, 6]);
  ctx.lineWidth = 3;
  ctx.strokeStyle = '#f2b632';
  ctx.strokeRect(lo * T + 1.5, lo * T + 1.5, span - 3, span - 3);
  ctx.setLineDash([]);

  if (hover) {
    const tile = grid.tiles[idx(hover.x, hover.y)];
    ctx.lineWidth = 4;
    ctx.strokeStyle = '#ffffff';
    ctx.strokeRect(hover.x * T + 2, hover.y * T + 2, T - 4, T - 4);
    if (tile.b) {
      const a = adjacencyAt(state, tile.b.id, hover.x, hover.y, mods);
      for (const p of a.parts) label(p.x * T + T / 2, p.y * T + T * 0.25, `${p.value > 0 ? '+' : ''}${Math.round(p.value * 100)}%`, p.value > 0 ? '#9be7a8' : '#ff9b8a');
    }
  }
  requestAnimationFrame(draw);
}

function tileFromEvent(ev) {
  const r = canvas.getBoundingClientRect();
  const x = Math.floor(((ev.clientX - r.left) / r.width) * GRID_W);
  const y = Math.floor(((ev.clientY - r.top) / r.height) * GRID_H);
  return x >= 0 && y >= 0 && x < GRID_W && y < GRID_H ? { x, y } : null;
}

function describe(t) {
  const tip = document.getElementById('tip');
  if (!t) return;
  const tile = grid.tiles[idx(t.x, t.y)];
  if (!tile.b) {
    tip.innerHTML = `<p><b>${TERRAIN[tile.t].name}</b>${isUnlocked(grid, t.x, t.y) ? '' : ' (terra ainda não conquistada)'}</p>`;
    return;
  }
  const a = adjacencyAt(state, tile.b.id, t.x, t.y, mods);
  const parts = a.parts.map((p) => `${p.key in BUILDINGS ? NAMES[p.key] : TERRAIN[p.key].name} ${p.value > 0 ? '+' : ''}${Math.round(p.value * 100)}%`).join(', ');
  tip.innerHTML = `<p><b>${NAMES[tile.b.id]}</b> · adjacência total <b>${a.total >= 0 ? '+' : ''}${Math.round(a.total * 100)}%</b>${parts ? ` (${parts})` : ''}</p>`;
}

canvas.addEventListener('pointermove', (ev) => { hover = tileFromEvent(ev); describe(hover); });
canvas.addEventListener('pointerdown', (ev) => { hover = tileFromEvent(ev); describe(hover); });
canvas.addEventListener('pointerleave', () => { hover = null; });

// ---------------------------------------------------------------- painéis
const catalog = document.getElementById('catalog');
catalog.innerHTML = Object.entries(BUILDING_SPRITES).map(([id, b]) => `
  <div class="card ${id === 'fonte' ? 'swap' : ''}"><img src="${b.src}" alt=""><b>${NAMES[id]}</b>${id === 'fonte' ? '<small>no lugar de Fonte</small>' : ''}</div>`).join('');

const HERO_ICONS = { lavradora: 'hero-farmer', arqueira: 'hero-archer', bardo: 'hero-bard', exploradora: 'hero-explorer', alquimista: 'hero-wizard', druida: 'hero-elf', rainha: 'hero-queen', dragao: 'hero-dragon', relojoeiro: 'hero-clock', guarda: 'hero-guard', pedreiro: 'hero-dwarf' };
const sample = ['lavradora', 'guarda', 'arqueira', 'bardo', 'druida', 'rainha', 'dragao'];
document.getElementById('heroes').innerHTML = sample.map((id) => {
  const h = HEROES.find((x) => x.id === id);
  const r = RARITIES[h.rarity];
  return `<div class="hero" style="--rc:var(--${h.rarity})"><div class="portrait"><i class="ico" style="--src:url(${icon(HERO_ICONS[id])})"></i></div>
    <div><span class="rar">${r.name}</span><b> ${h.name}</b><small>${h.lore}</small></div></div>`;
}).join('');

const UI_ICONS = [['gold', 'Ouro'], ['food', 'Comida'], ['wood', 'Madeira'], ['stone', 'Pedra'], ['gems', 'Gemas'], ['crowns', 'Coroas'], ['pop', 'Moradores'], ['happiness', 'Felicidade'], ['defense', 'Defesa'], ['raid', 'Horda'], ['time', 'Tempo'], ['scroll', 'Pergaminho'], ['map', 'Território'], ['trophy', 'Conquista'], ['castle', 'Reino'], ['settings', 'Opções']];
document.getElementById('icons').innerHTML = UI_ICONS.map(([n, l]) => `<span><i class="ico" style="--src:url(${icon(n)})"></i>${l}</span>`).join('');

Promise.all(allSpriteUrls().map(load)).then(() => requestAnimationFrame(draw));
