// Renderizador do mapa em <canvas> com os sprites Kenney Medieval RTS.
// Camadas: terreno (em cache, só redesenha quando o mapa muda) -> prédios e unidades -> realces -> efeitos.
import { BUILDINGS, TERRAIN } from '../data/buildings.js';
import { GRID_W, GRID_H, idx, isUnlocked, neighbors, ringOf } from '../core/map.js';
import { adjacencyAt } from '../core/economy.js';
import { fmtPct } from '../core/format.js';
import { TERRAIN_SPRITES, BUILDING_SPRITES, LOCKED_OVERLAY, CART_SPRITE, RAIDER_SPRITES, VILLAGER_SPRITES } from './sprites.js';
import { images, iconKey } from './assets.js';

const pick = (arr, i) => arr[((i % arr.length) + arr.length) % arr.length];
const RAID_WARNING_MS = 20000;

export class MapRenderer {
  constructor(canvas, { onTileClick, onHover, onResize, getConfig } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.onTileClick = onTileClick;
    this.onHover = onHover;
    this.onResize = onResize; // telas estáticas (fundo do menu) redesenham só quando o tamanho muda
    this.getConfig = getConfig ?? (() => ({ particles: true, reduceMotion: false }));
    this.hover = null;
    this.selected = null;
    this.cursor = null; // cursor do teclado
    this.mode = { type: 'select' };
    this.view = null; // { grid } para visitar outro reino ou o fundo do menu
    this.fx = [];
    this.pops = new Map(); // índice do tile -> início da animação de construção
    this.villagers = [];
    this.shake = 0;
    this.flash = null;
    this.lastTouch = null;
    this.terrainCache = document.createElement('canvas');
    this.terrainSig = '';
    this.walkCache = { sig: null, walkable: [], target: 0 }; // tiles livres para aldeões (recalcula só se o mapa mudar)
    this.resize();
    if (window.ResizeObserver) new ResizeObserver(() => this.resize()).observe(canvas.parentElement);
    else window.addEventListener('resize', () => this.resize());
    if (onTileClick) {
      canvas.addEventListener('pointermove', (e) => this.pointer(e, false));
      // No toque, o dedo "sai" do canvas ao levantar: manter a prévia até o 2º toque.
      canvas.addEventListener('pointerleave', (e) => { if (e.pointerType === 'touch') return; this.hover = null; this.onHover?.(null); });
      canvas.addEventListener('pointerdown', (e) => this.pointer(e, true));
    }
  }

  resize() {
    const parent = this.canvas.parentElement.getBoundingClientRect();
    // Elemento oculto: espera o ResizeObserver avisar quando aparecer de novo.
    if (parent.width === 0 && parent.height === 0) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const fill = this.canvas.dataset.fill === 'cover';
    const size = fill ? Math.max(parent.width, parent.height) : Math.max(240, Math.floor(Math.min(parent.width, parent.height || parent.width)));
    this.canvas.style.width = `${size}px`;
    this.canvas.style.height = `${size}px`;
    this.canvas.width = Math.round(size * dpr);
    this.canvas.height = Math.round(size * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.size = size;
    this.dpr = dpr;
    this.tile = size / GRID_W;
    this.terrainSig = ''; // força redesenho do cache
    this.onResize?.();
  }

  tileFromEvent(e) {
    const r = this.canvas.getBoundingClientRect();
    const x = Math.floor(((e.clientX - r.left) / r.width) * GRID_W);
    const y = Math.floor(((e.clientY - r.top) / r.height) * GRID_H);
    return x >= 0 && y >= 0 && x < GRID_W && y < GRID_H ? { x, y } : null;
  }

  pointer(e, isClick) {
    const t = this.tileFromEvent(e);
    const changed = !this.hover || !t || this.hover.x !== t.x || this.hover.y !== t.y;
    this.hover = t;
    if (changed) this.onHover?.(t);
    if (!isClick || !t) return;
    // No toque, em modo construção/mover o 1º toque só mostra a prévia; o 2º no mesmo tile confirma.
    if (e.pointerType === 'touch' && this.mode.type !== 'select') {
      if (!this.lastTouch || this.lastTouch.x !== t.x || this.lastTouch.y !== t.y) {
        this.lastTouch = t;
        return;
      }
    }
    this.lastTouch = null;
    this.onTileClick?.(t.x, t.y);
  }

  // ---------------------------------------------------------------- efeitos
  fxOn() { return this.getConfig().particles; }
  motionOn() { return !this.getConfig().reduceMotion; }

  addFloat(x, y, text, color = '#ffffff', icon = null) {
    if (!this.fxOn()) return;
    this.fx.push({ kind: 'float', x, y, text, color, icon, born: performance.now(), life: 1500 });
    if (this.fx.length > 80) this.fx.splice(0, this.fx.length - 80);
  }

  addBurst(x, y, color = '#f2b632') {
    if (!this.fxOn()) return;
    const now = performance.now();
    this.fx.push({ kind: 'ring', x, y, color, born: now, life: 520 });
    for (let i = 0; i < 12; i++) {
      const a = (Math.PI * 2 * i) / 12;
      this.fx.push({ kind: 'spark', x, y, vx: Math.cos(a) * (0.5 + Math.random() * 0.6), vy: Math.sin(a) * (0.5 + Math.random() * 0.6), color, born: now, life: 650 });
    }
  }

  pop(x, y) { this.pops.set(idx(x, y), performance.now()); }
  doShake(ms = 500) { if (this.motionOn()) this.shake = performance.now() + ms; }
  doFlash(color, ms = 500) { if (this.motionOn()) this.flash = { color, until: performance.now() + ms, ms }; }

  // ---------------------------------------------------------------- desenho
  img(url, x, y, w, h) {
    const im = images.get(url);
    if (im) this.ctx.drawImage(im, x, y, w, h);
  }

  terrainSignature(grid) {
    let s = `${grid.ring}|${this.size}|`;
    for (const t of grid.tiles) s += t.t[0] + (t.b ? '1' : '0');
    return s;
  }

  rebuildTerrain(grid) {
    const c = this.terrainCache;
    c.width = Math.round(this.size * this.dpr);
    c.height = Math.round(this.size * this.dpr);
    const g = c.getContext('2d');
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const T = this.tile;
    const draw = (url, x, y, w, h) => { const im = images.get(url); if (im) g.drawImage(im, x, y, w, h); };
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const tile = grid.tiles[i];
        const spr = TERRAIN_SPRITES[tile.t];
        // Sob prédios, sempre grama (os sprites de prédio não cobrem o tile inteiro).
        const base = tile.b ? pick(TERRAIN_SPRITES.grass.base, i) : pick(spr.base, i * 7 + 3);
        draw(base, x * T, y * T, T + 0.6, T + 0.6);
        if (!tile.b && spr.over) draw(pick(spr.over, i), x * T + T * 0.06, y * T + T * 0.06, T * 0.88, T * 0.88);
        if (!isUnlocked(grid, x, y)) {
          g.fillStyle = ringOf(x, y) === grid.ring + 1 ? 'rgba(20, 22, 32, 0.5)' : LOCKED_OVERLAY;
          g.fillRect(x * T, y * T, T + 0.6, T + 0.6);
        }
      }
    }
    const lo = Math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5);
    const span = (GRID_W - 2 * lo) * T;
    g.setLineDash([8, 5]);
    g.lineWidth = 2.5;
    g.strokeStyle = '#f2b632';
    g.strokeRect(lo * T + 1.5, lo * T + 1.5, span - 3, span - 3);
    g.setLineDash([]);
  }

  draw(game) {
    const ctx = this.ctx;
    const now = performance.now();
    const state = game?.state;
    const grid = this.view?.grid ?? state?.grid;
    if (!grid || !this.size) return;
    const econ = this.view ? null : game.econ;
    const T = this.tile;
    const motion = this.motionOn();

    const sig = this.terrainSignature(grid);
    if (sig !== this.terrainSig) { this.rebuildTerrain(grid); this.terrainSig = sig; }

    ctx.save();
    ctx.clearRect(0, 0, this.size, this.size);
    if (this.shake > now) {
      const k = (this.shake - now) / 500;
      ctx.translate((Math.random() - 0.5) * 9 * k, (Math.random() - 0.5) * 9 * k);
    }
    ctx.drawImage(this.terrainCache, 0, 0, this.size, this.size);

    // Prédios
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const tile = grid.tiles[i];
        if (!tile.b) continue;
        const spr = BUILDING_SPRITES[tile.b.id];
        if (!spr) continue;
        const info = econ?.tiles[i];
        let scale = 1;
        const popAt = this.pops.get(i);
        if (popAt !== undefined) {
          const p = (now - popAt) / 420;
          if (p >= 1 || !motion) this.pops.delete(i);
          else scale = p < 0.6 ? 0.75 + (p / 0.6) * 0.4 : 1.15 - ((p - 0.6) / 0.4) * 0.15;
        }
        const dim = info && (!info.active || (info.workers > 0 && info.staff < 0.5));
        ctx.globalAlpha = dim ? 0.6 : 1;
        const w = (spr.full ? T : T * 0.92) * scale;
        const cx = x * T + T / 2;
        const cy = y * T + T / 2;
        this.img(spr.src, cx - w / 2, cy - w / 2 - (spr.full ? 0 : T * 0.02), w, w);
        if (spr.blades) {
          ctx.save();
          ctx.translate(cx, y * T + T * 0.42);
          ctx.rotate(motion && info?.active !== false ? now / 900 : 0.4);
          this.img(spr.blades, -T * 0.42 * scale, -T * 0.42 * scale, T * 0.84 * scale, T * 0.84 * scale);
          ctx.restore();
        }
        ctx.globalAlpha = 1;
        if (tile.b.lvl > 1) this.badge(x * T + T * 0.84, y * T + T * 0.84, String(tile.b.lvl), T);
        if (info && !info.active) this.img(iconKey('warning', '#ffb020'), x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3);
      }
    }

    if (!this.view && state) {
      this.drawVillagers(grid, now, T, motion);
      this.drawCart(state, now, T, motion);
      this.drawRaiders(state, now, T, motion);
    }

    // Seleção e adjacência do prédio selecionado
    if (this.selected && !this.view) {
      const { x, y } = this.selected;
      const pulse = motion ? 0.5 + 0.5 * Math.sin(now / 260) : 1;
      ctx.fillStyle = `rgba(255, 224, 138, ${0.12 + 0.08 * pulse})`;
      this.roundRect(x * T + 2, y * T + 2, T - 4, T - 4, T * 0.14);
      ctx.fill();
      this.corners(x * T, y * T, T, motion ? pulse * T * 0.035 : 0);
      const info = econ?.tiles[idx(x, y)];
      if (info) for (const p of info.adjParts) this.label(p.x * T + T / 2, p.y * T + T * 0.24, fmtPct(p.value), p.value > 0 ? '#9be7a8' : '#ffb3a6', T);
    }

    if (this.hover && !this.view) this.drawPreview(game, this.hover, T);
    if (this.cursor && !this.view) {
      ctx.setLineDash([6, 4]);
      ctx.lineWidth = 3;
      ctx.strokeStyle = '#f2b632';
      ctx.strokeRect(this.cursor.x * T + 3, this.cursor.y * T + 3, T - 6, T - 6);
      ctx.setLineDash([]);
      if (!this.hover || this.hover.x !== this.cursor.x || this.hover.y !== this.cursor.y) this.drawPreview(game, this.cursor, T);
    }

    // Efeitos (compactação no próprio array: nada de alocar um array novo por frame)
    let alive = 0;
    for (const f of this.fx) {
      if (now - f.born >= f.life) continue;
      this.fx[alive++] = f;
      const p = (now - f.born) / f.life;
      ctx.globalAlpha = 1 - p;
      if (f.kind === 'ring') {
        const e = 1 - (1 - p) ** 3;
        ctx.lineWidth = 3 * (1 - p) + 1;
        ctx.strokeStyle = f.color;
        ctx.beginPath();
        ctx.arc(f.x * T + T / 2, f.y * T + T / 2, T * (0.25 + e * 0.6), 0, Math.PI * 2);
        ctx.stroke();
      } else if (f.kind === 'float') {
        const fy = f.y * T + T * 0.3 - (motion ? p * T * 0.8 : 0);
        ctx.font = `800 ${Math.max(11, T * 0.24)}px Nunito, sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        const tw = ctx.measureText(f.text).width;
        const iconW = f.icon ? T * 0.26 : 0;
        const startX = f.x * T + T / 2 - (tw + iconW) / 2;
        ctx.lineWidth = 3;
        ctx.strokeStyle = 'rgba(0,0,0,0.65)';
        ctx.strokeText(f.text, startX + tw / 2, fy);
        ctx.fillStyle = f.color;
        ctx.fillText(f.text, startX + tw / 2, fy);
        if (f.icon) this.img(f.icon, startX + tw + 2, fy - iconW / 2, iconW, iconW);
      } else {
        ctx.fillStyle = f.color;
        ctx.beginPath();
        ctx.arc(f.x * T + T / 2 + f.vx * p * T, f.y * T + T / 2 + f.vy * p * T, 3 * (1 - p) + 1, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }
    this.fx.length = alive;
    if (this.flash && this.flash.until > now) {
      ctx.globalAlpha = ((this.flash.until - now) / this.flash.ms) * 0.35;
      ctx.fillStyle = this.flash.color;
      ctx.fillRect(-20, -20, this.size + 40, this.size + 40);
      ctx.globalAlpha = 1;
    }
    ctx.restore();
  }

  drawCart(state, now, T, motion) {
    if (!state.chest) return;
    const { x, y } = state.chest;
    const glow = motion ? 0.5 + 0.5 * Math.sin(now / 220) : 0.7;
    const ctx = this.ctx;
    ctx.fillStyle = `rgba(242, 182, 50, ${0.25 + glow * 0.3})`;
    ctx.beginPath();
    ctx.ellipse(x * T + T / 2, y * T + T * 0.62, T * 0.46, T * 0.3, 0, 0, Math.PI * 2);
    ctx.fill();
    const bob = motion ? Math.abs(Math.sin(now / 260)) * T * 0.06 : 0;
    this.img(CART_SPRITE, x * T + T * 0.08, y * T + T * 0.04 - bob, T * 0.84, T * 0.84);
  }

  // Invasores entram pelo lado anunciado durante o aviso da horda.
  drawRaiders(state, now, T, motion) {
    if (!state.raid.warned) return;
    const left = state.raid.nextAt - Date.now();
    const p = Math.max(0, Math.min(1, 1 - left / RAID_WARNING_MS));
    const dir = state.raid.dir || 'n';
    const depth = -0.8 + p * 1.6; // de fora do mapa até 0,8 tile para dentro
    for (let k = 0; k < 3; k++) {
      const along = GRID_W / 2 - 1.5 + k * 1.1;
      let x;
      let y;
      if (dir === 'n') { x = along; y = depth; } else if (dir === 's') { x = along; y = GRID_H - 1 - depth; } else if (dir === 'w') { x = depth; y = along; } else { x = GRID_W - 1 - depth; y = along; }
      const bob = motion ? Math.sin(now / 140 + k) * T * 0.05 : 0;
      this.img(pick(RAIDER_SPRITES, k), x * T + T * 0.1, y * T + T * 0.1 + bob, T * 0.8, T * 0.8);
    }
  }

  drawVillagers(grid, now, T, motion) {
    if (!motion || !this.fxOn()) return;
    // terrainSig muda quando o terreno, um prédio ou o anel mudam: só então refazer a lista.
    if (this.walkCache.sig !== this.terrainSig) {
      const walkable = [];
      let houses = 0;
      grid.tiles.forEach((t, i) => {
        if (t.b?.id === 'casa') houses++;
        if (t.t === 'grass' && !t.b && isUnlocked(grid, i % GRID_W, Math.floor(i / GRID_W))) walkable.push(i);
      });
      this.walkCache = { sig: this.terrainSig, walkable, target: Math.min(4, Math.floor(houses / 2) + 1) };
      // Aldeão parado num tile que virou prédio: escolhe outro destino.
      for (const v of this.villagers) v.to = null;
    }
    const { walkable, target } = this.walkCache;
    if (walkable.length < 4) return;
    while (this.villagers.length < target) {
      const at = pick(walkable, Math.floor(Math.random() * walkable.length));
      this.villagers.push({ x: at % GRID_W, y: Math.floor(at / GRID_W), to: null, spr: pick(VILLAGER_SPRITES, this.villagers.length) });
    }
    if (this.villagers.length > target) this.villagers.length = target;
    for (const v of this.villagers) {
      if (!v.to) {
        const near = walkable.filter((i) => Math.abs((i % GRID_W) - v.x) + Math.abs(Math.floor(i / GRID_W) - v.y) <= 3);
        const i = pick(near.length ? near : walkable, Math.floor(Math.random() * 1000));
        v.to = { x: i % GRID_W, y: Math.floor(i / GRID_W) };
      }
      const dx = v.to.x - v.x;
      const dy = v.to.y - v.y;
      const d = Math.hypot(dx, dy);
      const step = 0.012;
      if (d < step) v.to = null;
      else { v.x += (dx / d) * step; v.y += (dy / d) * step; }
      this.img(v.spr, v.x * T + T * 0.25, v.y * T + T * 0.2 + Math.sin(now / 120 + v.x) * T * 0.02, T * 0.5, T * 0.5);
    }
  }

  drawPreview(game, at, T) {
    const ctx = this.ctx;
    const { x, y } = at;
    const state = game.state;
    const tile = state.grid.tiles[idx(x, y)];
    const mode = this.mode;
    let buildId = null;
    if (mode.type === 'build') buildId = mode.id;
    else if (mode.type === 'move') buildId = state.grid.tiles[idx(mode.from.x, mode.from.y)].b?.id;
    if (!buildId) {
      ctx.fillStyle = 'rgba(255,255,255,0.10)';
      this.roundRect(x * T + 2, y * T + 2, T - 4, T - 4, T * 0.14);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.lineWidth = 2;
      ctx.stroke();
      return;
    }
    const valid = !tile.b && TERRAIN[tile.t].buildable && isUnlocked(state.grid, x, y);
    ctx.fillStyle = valid ? 'rgba(155,231,168,0.30)' : 'rgba(255,110,90,0.38)';
    this.roundRect(x * T + 1, y * T + 1, T - 2, T - 2, T * 0.12);
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = valid ? 'rgba(190,255,200,0.85)' : 'rgba(255,150,130,0.9)';
    ctx.stroke();
    if (!valid) return;
    let restore = null;
    if (mode.type === 'move') {
      const from = state.grid.tiles[idx(mode.from.x, mode.from.y)];
      restore = from.b;
      from.b = null;
    }
    const adj = adjacencyAt(state, buildId, x, y, game.econ.mods);
    if (restore) state.grid.tiles[idx(mode.from.x, mode.from.y)].b = restore;
    const spr = BUILDING_SPRITES[buildId];
    ctx.globalAlpha = 0.75;
    this.img(spr.src, x * T + T * 0.04, y * T + T * 0.04, T * 0.92, T * 0.92);
    ctx.globalAlpha = 1;
    for (const [nx, ny] of neighbors(x, y)) {
      ctx.strokeStyle = 'rgba(255,255,255,0.35)';
      ctx.lineWidth = 1;
      ctx.strokeRect(nx * T + 1, ny * T + 1, T - 2, T - 2);
    }
    for (const p of adj.parts) this.label(p.x * T + T / 2, p.y * T + T * 0.24, fmtPct(p.value), p.value > 0 ? '#9be7a8' : '#ffb3a6', T);
    const total = adj.hasRequired ? `Total ${fmtPct(adj.total)}` : 'Precisa de montanha';
    const color = !adj.hasRequired ? '#ffb3a6' : adj.total > 0 ? '#ffe08a' : adj.total < 0 ? '#ffb3a6' : '#ffffff';
    this.label(x * T + T / 2, y * T - T * 0.14 < T * 0.2 ? y * T + T * 1.12 : y * T - T * 0.14, total, color, T, true);
  }

  // Cantoneiras da seleção: mais legíveis que um contorno inteiro e não escondem o sprite.
  corners(x, y, T, grow = 0) {
    const ctx = this.ctx;
    const g = 3 - grow;
    const len = T * 0.26;
    ctx.lineWidth = Math.max(2.5, T * 0.05);
    ctx.lineCap = 'round';
    ctx.strokeStyle = 'rgba(30, 24, 10, 0.45)';
    for (const pass of [1, 0]) {
      const o = pass; // sombra deslocada 1 px, depois o traço dourado
      ctx.beginPath();
      for (const [cx, cy, sx, sy] of [[x + g, y + g, 1, 1], [x + T - g, y + g, -1, 1], [x + g, y + T - g, 1, -1], [x + T - g, y + T - g, -1, -1]]) {
        ctx.moveTo(cx + o, cy + sy * len + o);
        ctx.lineTo(cx + o, cy + o);
        ctx.lineTo(cx + sx * len + o, cy + o);
      }
      ctx.stroke();
      ctx.strokeStyle = '#ffd45c';
    }
    ctx.lineCap = 'butt';
  }

  badge(cx, cy, text, T) {
    const ctx = this.ctx;
    const r = T * 0.15;
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.beginPath();
    ctx.arc(cx, cy + 1.5, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#2b2a33';
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#f2b632';
    ctx.stroke();
    ctx.fillStyle = '#ffffff';
    ctx.font = `800 ${Math.max(9, T * 0.17)}px Nunito, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, cx, cy + 0.5);
  }

  label(cx, cy, text, color, T, big = false) {
    const ctx = this.ctx;
    ctx.font = `800 ${Math.max(10, T * (big ? 0.26 : 0.21))}px Nunito, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const w = ctx.measureText(text).width + 12;
    const h = Math.max(15, T * (big ? 0.36 : 0.3));
    ctx.fillStyle = 'rgba(43,42,51,0.9)';
    this.roundRect(cx - w / 2, cy - h / 2, w, h, h / 2);
    ctx.fill();
    ctx.fillStyle = color;
    ctx.fillText(text, cx, cy + 1);
  }

  roundRect(x, y, w, h, r) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }
}
