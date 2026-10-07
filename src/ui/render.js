// Renderizador do mapa em <canvas> com os sprites do KayKit (prédios e natureza) e do Kenney Medieval RTS (moradores).
// Camadas: chão (em cache, só redesenha quando o mapa muda) -> natureza e prédios, linha a linha de trás para a frente
// (o que é alto invade o tile de cima) -> território bloqueado -> unidades -> realces -> efeitos.
import { BUILDINGS, TERRAIN, GROW_SECONDS } from '../data/buildings.js';
import { GRID_W, GRID_H, idx, isUnlocked, neighbors, ringOf, wallMask } from '../core/map.js';
import { adjacencyAt } from '../core/economy.js';
import { fmtPct } from '../core/format.js';
import { UNDER_SPRITES, ROOM_SPRITES, TERRAIN_SPRITES, BUILDING_SPRITES, buildingSrc, wallSrc, SPRITE_FRAME, SPRITE_K, LOCKED_OVERLAY, CART_SPRITE, BOAT_SPRITE, RAIDER_SPRITES, saplingSprite } from './sprites.js';
import { VillageLife } from './villagers.js';
import { images, iconKey, TOOL_COLOR } from './assets.js';
import { UNDER_TILES } from '../data/underground.js';
import { canReach } from '../core/underground.js';

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
    this.layer = 0; // 0 = superfície; 1..3 = nível do subsolo
    this.fx = [];
    this.pops = new Map(); // índice do tile -> início da animação de construção
    this.life = new VillageLife(); // moradores com profissão e rotina (src/ui/villagers.js)
    this.shake = 0;
    this.flash = null;
    this.lastTouch = null;
    this.terrainCache = document.createElement('canvas');
    this.terrainSig = '';
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
  popUnder(d, x, y) { this.pops.set(-1 - idx(x, y) - d * 1000, performance.now()); }
  doShake(ms = 500) { if (this.motionOn()) this.shake = performance.now() + ms; }
  doFlash(color, ms = 500) { if (this.motionOn()) this.flash = { color, until: performance.now() + ms, ms }; }

  // ---------------------------------------------------------------- desenho
  img(url, x, y, w, h) {
    const im = images.get(url);
    if (im) this.ctx.drawImage(im, x, y, w, h);
  }

  // Sprite do KayKit no quadro SPRITE_FRAME, ancorado no centro do tile (cx, cy).
  framed(url, cx, cy, T, scale = 1) {
    const f = SPRITE_FRAME;
    this.img(url, cx + f.left * T * scale, cy + f.top * T * scale, (f.right - f.left) * T * scale, (f.bottom - f.top) * T * scale);
  }

  // Água onde fica o barquinho de cada cais funcionando: a primeira água vizinha. Mapa água -> cais.
  boatSpots(grid, econ) {
    const out = new Map();
    grid.tiles.forEach((t, i) => {
      if (t.b?.id !== 'cais' || (econ && econ.tiles[i] && !econ.tiles[i].active)) return;
      const w = neighbors(i % GRID_W, Math.floor(i / GRID_W)).find(([nx, ny]) => grid.tiles[idx(nx, ny)].t === 'water');
      if (w && !out.has(idx(w[0], w[1]))) out.set(idx(w[0], w[1]), i);
    });
    return out;
  }

  // Barquinho indo e voltando devagar dentro do tile de água, balançando; vira para o lado em que anda.
  drawBoat(x, y, T, now, seed, motion) {
    const ctx = this.ctx;
    const t = motion ? now / 2600 + seed : seed;
    const cx = x * T + T / 2 + Math.sin(t) * T * 0.16;
    const cy = y * T + T * 0.62 + (motion ? Math.sin(now / 520 + seed) * T * 0.025 : 0);
    ctx.save();
    ctx.translate(cx, cy);
    if (Math.cos(t) < 0) ctx.scale(-1, 1);
    this.framed(BOAT_SPRITE, 0, 0, T, 0.58);
    ctx.restore();
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
      }
    }
  }

  // Contorno tracejado do território.
  drawBorder(grid, T) {
    const g = this.ctx;
    const lo = Math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5);
    const span = (GRID_W - 2 * lo) * T;
    g.setLineDash([8, 5]);
    g.lineWidth = 2.5;
    g.strokeStyle = '#f2b632';
    g.strokeRect(lo * T + 1.5, lo * T + 1.5, span - 3, span - 3);
    g.setLineDash([]);
  }

  // Hélice do moinho: renderizada de frente; achatada por SPRITE_K, como a altura do resto do sprite.
  drawBlades(blades, cx, cy, T, scale, angle) {
    const ctx = this.ctx;
    const w = blades.size * T * scale;
    ctx.save();
    ctx.translate(cx + blades.hub.x * T * scale, cy + blades.hub.y * T * scale);
    ctx.scale(1, SPRITE_K);
    ctx.rotate(angle);
    this.img(blades.src, -w / 2, -w / 2, w, w);
    ctx.restore();
  }

  draw(game) {
    const ctx = this.ctx;
    const now = performance.now();
    const state = game?.state;
    const grid = this.view?.grid ?? state?.grid;
    if (!grid || !this.size) return;
    if (this.layer > 0 && !this.view && state?.under) { this.drawUnder(game, now); return; }
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

    const boats = this.boatSpots(grid, econ);
    // Natureza e prédios, de trás para a frente
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const tile = grid.tiles[i];
        if (!tile.b) {
          if (boats.has(i)) this.drawBoat(x, y, T, now, boats.get(i), motion);
          const over = tile.t === 'sapling' ? [saplingSprite(tile, Date.now(), GROW_SECONDS)] : TERRAIN_SPRITES[tile.t]?.over;
          if (over) this.framed(pick(over, i), x * T + T / 2, y * T + T / 2, T);
          continue;
        }
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
        const cx = x * T + T / 2;
        const cy = y * T + T / 2;
        this.framed(tile.b.id === 'muralha' ? wallSrc(wallMask(grid, x, y)) : buildingSrc(spr, tile.b.lvl), cx, cy, T, scale);
        if (spr.blades) this.drawBlades(spr.blades, cx, cy, T, scale, motion && info?.active !== false ? now / 900 : 0.4);
        ctx.globalAlpha = 1;
      }
    }

    // Território bloqueado escurecido por cima da natureza (que sobe para o tile de cima).
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        if (isUnlocked(grid, x, y)) continue;
        ctx.fillStyle = ringOf(x, y) === grid.ring + 1 ? 'rgba(20, 22, 32, 0.5)' : LOCKED_OVERLAY;
        ctx.fillRect(x * T, y * T, T + 0.6, T + 0.6);
      }
    }
    this.drawBorder(grid, T);

    // Nível e avisos por cima de tudo que é do mapa.
    for (let i = 0; i < grid.tiles.length; i++) {
      const b = grid.tiles[i].b;
      if (!b) continue;
      const x = i % GRID_W;
      const y = Math.floor(i / GRID_W);
      if (b.lvl > 1) this.badge(x * T + T * 0.84, y * T + T * 0.84, String(b.lvl), T);
      if (econ?.tiles[i] && !econ.tiles[i].active) this.img(iconKey('warning', '#ffb020'), x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3);
    }

    if (!this.view && state) {
      if (motion && this.fxOn()) { this.life.update(game, now); this.life.draw(this, now, T); }
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

    this.drawEffects(now, T, motion);
    ctx.restore();
  }

  // ---------------------------------------------------------------- subsolo
  // Vista de cima no estilo Dwarf Fortress: rocha é parede, o que foi cavado é chão, e o que ninguém viu é escuro.
  drawUnder(game, now) {
    const ctx = this.ctx;
    const T = this.tile;
    const motion = this.motionOn();
    const d = this.layer;
    const lv = game.state.under.levels[d - 1];
    const infos = game.econ?.under?.[d - 1];
    const open = (x, y) => x >= 0 && y >= 0 && x < GRID_W && y < GRID_H && lv.tiles[idx(x, y)].s && UNDER_TILES[lv.tiles[idx(x, y)].t]?.open;
    ctx.save();
    ctx.clearRect(0, 0, this.size, this.size);
    if (this.shake > now) {
      const k = (this.shake - now) / 500;
      ctx.translate((Math.random() - 0.5) * 9 * k, (Math.random() - 0.5) * 9 * k);
    }
    ctx.fillStyle = '#121019';
    ctx.fillRect(0, 0, this.size, this.size);
    const glow = motion ? 0.5 + 0.5 * Math.sin(now / 700) : 0.5;
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const t = lv.tiles[i];
        if (!t.s) continue;
        const spr = UNDER_SPRITES[t.t];
        if (spr) this.img(pick(spr, i * 7 + 3), x * T, y * T, T + 0.6, T + 0.6);
        if (t.t === 'magma') {
          ctx.fillStyle = `rgba(255, 200, 60, ${0.08 + 0.14 * glow})`;
          ctx.fillRect(x * T, y * T, T + 0.6, T + 0.6);
        }
        if (!UNDER_TILES[t.t]?.open) continue;
        // Sombra das paredes sobre o chão: dá volume às galerias.
        const sh = T * 0.16;
        const edge = (x0, y0, w, h, gx0, gy0, gx1, gy1) => {
          const g = ctx.createLinearGradient(gx0, gy0, gx1, gy1);
          g.addColorStop(0, 'rgba(10, 8, 16, 0.55)');
          g.addColorStop(1, 'rgba(10, 8, 16, 0)');
          ctx.fillStyle = g;
          ctx.fillRect(x0, y0, w, h);
        };
        if (!open(x, y - 1)) edge(x * T, y * T, T, sh, 0, y * T, 0, y * T + sh);
        if (!open(x - 1, y)) edge(x * T, y * T, sh, T, x * T, 0, x * T + sh, 0);
        if (!open(x + 1, y)) edge(x * T + T - sh, y * T, sh, T, x * T + T, 0, x * T + T - sh, 0);
        if (!open(x, y + 1)) edge(x * T, y * T + T - sh * 0.6, T, sh * 0.6, 0, y * T + T, 0, y * T + T - sh * 0.6);
        if (t.st) this.drawStairs(x, y, T, t.st);
      }
    }
    // Borda da névoa: o escuro avança um pouco sobre o que já se vê.
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        if (lv.tiles[idx(x, y)].s) continue;
        ctx.fillStyle = 'rgba(18, 16, 25, 0.85)';
        ctx.fillRect(x * T - T * 0.12, y * T - T * 0.12, T * 1.24, T * 1.24);
      }
    }
    // Salas, de trás para a frente.
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const b = lv.tiles[i].b;
        if (!b) continue;
        let scale = 1;
        const popAt = this.pops.get(-1 - i - d * 1000);
        if (popAt !== undefined) {
          const p = (now - popAt) / 420;
          if (p >= 1 || !motion) this.pops.delete(-1 - i - d * 1000);
          else scale = p < 0.6 ? 0.75 + (p / 0.6) * 0.4 : 1.15 - ((p - 0.6) / 0.4) * 0.15;
        }
        ctx.globalAlpha = infos?.[i] && !infos[i].active ? 0.6 : 1;
        this.framed(ROOM_SPRITES[b.id].src, x * T + T / 2, y * T + T / 2, T, scale);
        ctx.globalAlpha = 1;
      }
    }
    for (let i = 0; i < lv.tiles.length; i++) {
      const b = lv.tiles[i].b;
      if (!b) continue;
      const x = i % GRID_W;
      const y = Math.floor(i / GRID_W);
      if (b.lvl > 1) this.badge(x * T + T * 0.84, y * T + T * 0.84, String(b.lvl), T);
      if (infos?.[i] && !infos[i].active) this.img(iconKey('warning', '#ffb020'), x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3);
    }
    // Seleção, vizinhos da sala selecionada e picareta sobre o que dá para cavar.
    if (this.selected) {
      const { x, y } = this.selected;
      const pulse = motion ? 0.5 + 0.5 * Math.sin(now / 260) : 1;
      ctx.fillStyle = `rgba(255, 224, 138, ${0.12 + 0.08 * pulse})`;
      this.roundRect(x * T + 2, y * T + 2, T - 4, T - 4, T * 0.14);
      ctx.fill();
      this.corners(x * T, y * T, T, motion ? pulse * T * 0.035 : 0);
      const info = infos?.[idx(x, y)];
      if (info) for (const p of info.adjParts) this.label(p.x * T + T / 2, p.y * T + T * 0.24, fmtPct(p.value), p.value > 0 ? '#9be7a8' : '#ffb3a6', T);
    }
    for (const at of [this.hover, this.cursor]) {
      if (!at) continue;
      const t = lv.tiles[idx(at.x, at.y)];
      ctx.fillStyle = 'rgba(255,255,255,0.10)';
      this.roundRect(at.x * T + 2, at.y * T + 2, T - 4, T - 4, T * 0.14);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.lineWidth = 2;
      ctx.stroke();
      if (t.s && UNDER_TILES[t.t].dig && canReach(lv, at.x, at.y)) this.img(iconKey('tool-pickaxe', TOOL_COLOR), at.x * T + T * 0.3, at.y * T + T * 0.3, T * 0.4, T * 0.4);
    }
    this.drawEffects(now, T, motion);
    ctx.restore();
  }

  // Escada desenhada de cima: degraus que clareiam (sobe) ou escurecem (desce) em direção ao fundo.
  drawStairs(x, y, T, dir) {
    const ctx = this.ctx;
    const m = T * 0.16;
    const w = T - m * 2;
    const n = 5;
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    this.roundRect(x * T + m - 2, y * T + m - 2, w + 4, w + 4, T * 0.08);
    ctx.fill();
    for (let k = 0; k < n; k++) {
      const f = dir === 'down' ? k / (n - 1) : 1 - k / (n - 1);
      const c = Math.round(200 - 170 * f);
      ctx.fillStyle = `rgb(${c}, ${c - 8}, ${c - 18})`;
      ctx.fillRect(x * T + m, y * T + m + (w / n) * k, w, w / n - 1.5);
    }
    this.label(x * T + T / 2, y * T + T * 0.86, dir === 'down' ? 'desce' : 'sobe', '#ffe08a', T);
  }

  // Efeitos por cima de tudo (números flutuantes, faíscas, clarão). Compactação no próprio array:
  // nada de alocar um array novo por frame.
  drawEffects(now, T, motion) {
    const ctx = this.ctx;
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
    this.framed(buildId === 'muralha' ? wallSrc(wallMask(state.grid, x, y)) : buildingSrc(spr, 1), x * T + T / 2, y * T + T / 2, T);
    if (spr.blades) this.drawBlades(spr.blades, x * T + T / 2, y * T + T / 2, T, 1, 0.4);
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
