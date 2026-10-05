// Renderizador do mapa em <canvas>. Desenha terreno, prédios, prévia de adjacência e efeitos.
import { BUILDINGS, TERRAIN } from '../data/buildings.js';
import { GRID_W, GRID_H, idx, ringOf, isUnlocked, neighbors } from '../core/map.js';
import { adjacencyAt } from '../core/economy.js';
import { fmtPct } from '../core/format.js';
import { mulberry32 } from '../core/rng.js';

const TERRAIN_COLORS = {
  grass: ['#5f9e46', '#67a84d', '#5a9842'],
  forest: ['#2f6b34', '#35733a', '#2c6531'],
  rock: ['#8a8c84', '#93958d', '#80827a'],
  water: ['#2f78bd', '#3482c8', '#2c70b2'],
  mountain: ['#7b6857', '#85715f', '#715f4f'],
};

export class MapRenderer {
  constructor(canvas, { onTileClick, onHover }) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.onTileClick = onTileClick;
    this.onHover = onHover;
    this.hover = null;
    this.selected = null;
    this.mode = { type: 'select' };
    this.fx = [];
    this.shake = 0;
    this.flash = null;
    this.view = null; // { grid, readonly } para visitar outros reinos
    this.lastTouch = null;
    this.noise = Array.from({ length: GRID_W * GRID_H }, (_, i) => mulberry32(i * 7919)());
    this.resize();
    if (window.ResizeObserver) new ResizeObserver(() => this.resize()).observe(canvas.parentElement);
    else window.addEventListener('resize', () => this.resize());
    canvas.addEventListener('pointermove', (e) => this.pointer(e, false));
    canvas.addEventListener('pointerleave', () => { this.hover = null; this.onHover?.(null); });
    canvas.addEventListener('pointerdown', (e) => this.pointer(e, true));
  }

  resize() {
    const rect = this.canvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const size = Math.max(240, Math.floor(Math.min(rect.width, rect.height || rect.width)));
    this.canvas.style.width = size + 'px';
    this.canvas.style.height = size + 'px';
    this.canvas.width = size * dpr;
    this.canvas.height = size * dpr;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.size = size;
    this.tile = size / GRID_W;
  }

  tileFromEvent(e) {
    const r = this.canvas.getBoundingClientRect();
    const x = Math.floor((e.clientX - r.left) / this.tile);
    const y = Math.floor((e.clientY - r.top) / this.tile);
    if (x < 0 || y < 0 || x >= GRID_W || y >= GRID_H) return null;
    return { x, y };
  }

  pointer(e, isClick) {
    const t = this.tileFromEvent(e);
    const changed = !this.hover || !t || this.hover.x !== t.x || this.hover.y !== t.y;
    this.hover = t;
    if (changed) this.onHover?.(t);
    if (!isClick || !t) return;
    // No toque, o primeiro toque em modo construção só mostra a prévia; o segundo confirma.
    if (e.pointerType === 'touch' && this.mode.type !== 'select') {
      if (!this.lastTouch || this.lastTouch.x !== t.x || this.lastTouch.y !== t.y) {
        this.lastTouch = t;
        return;
      }
    }
    this.lastTouch = null;
    this.onTileClick?.(t.x, t.y, e);
  }

  addFloat(x, y, text, color = '#fff') {
    this.fx.push({ kind: 'float', x, y, text, color, born: performance.now(), life: 1400 });
  }

  addBurst(x, y, color = '#ffd43b') {
    const now = performance.now();
    for (let i = 0; i < 14; i++) {
      const a = (Math.PI * 2 * i) / 14;
      this.fx.push({ kind: 'spark', x, y, vx: Math.cos(a) * (0.6 + Math.random()), vy: Math.sin(a) * (0.6 + Math.random()), color, born: now, life: 700 });
    }
  }

  doShake(ms = 500) { this.shake = performance.now() + ms; }
  doFlash(color, ms = 600) { this.flash = { color, until: performance.now() + ms, ms }; }

  draw(game) {
    const ctx = this.ctx;
    const now = performance.now();
    const state = game.state;
    const grid = this.view?.grid ?? state.grid;
    const econ = this.view ? null : game.econ;
    const T = this.tile;

    ctx.save();
    ctx.clearRect(0, 0, this.size, this.size);
    if (this.shake > now) {
      const k = (this.shake - now) / 500;
      ctx.translate((Math.random() - 0.5) * 10 * k, (Math.random() - 0.5) * 10 * k);
    }

    // Terreno
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const i = idx(x, y);
        const tile = grid.tiles[i];
        const palette = TERRAIN_COLORS[tile.t];
        ctx.fillStyle = palette[Math.floor(this.noise[i] * palette.length)];
        ctx.fillRect(x * T, y * T, T + 0.5, T + 0.5);
        if (tile.t === 'water') {
          ctx.strokeStyle = 'rgba(255,255,255,0.25)';
          ctx.lineWidth = 1.5;
          const ph = now / 700 + i;
          for (let k = 0; k < 2; k++) {
            const yy = y * T + T * (0.35 + k * 0.3) + Math.sin(ph + k) * 2;
            ctx.beginPath();
            ctx.moveTo(x * T + T * 0.2, yy);
            ctx.quadraticCurveTo(x * T + T * 0.5, yy - 4, x * T + T * 0.8, yy);
            ctx.stroke();
          }
        }
        const icon = TERRAIN[tile.t].icon;
        if (icon && !tile.b) this.emoji(icon, x * T + T / 2, y * T + T / 2 + 1, T * 0.6);
      }
    }

    // Prédios
    const heroDim = (x, y) => econ && econ.tiles[idx(x, y)];
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        const tile = grid.tiles[idx(x, y)];
        if (!tile.b) continue;
        const def = BUILDINGS[tile.b.id];
        const info = heroDim(x, y);
        const cx = x * T + T / 2;
        const cy = y * T + T / 2;
        ctx.fillStyle = 'rgba(40,28,18,0.35)';
        roundRect(ctx, x * T + T * 0.08, y * T + T * 0.1, T * 0.84, T * 0.84, T * 0.18);
        ctx.fill();
        const bob = def.category === 'producao' && info?.active ? Math.sin(now / 400 + x + y) * 1.2 : 0;
        ctx.globalAlpha = info && (!info.active || (info.workers > 0 && econ.staffing < 0.5)) ? 0.55 : 1;
        this.emoji(def.icon, cx, cy - 1 + bob, T * 0.6);
        ctx.globalAlpha = 1;
        // pips de nível
        // Até 5 pontos; acima do nível 5 os pontos ficam dourados (nível 7 = 2 dourados + 3 claros).
        const pips = Math.min(5, tile.b.lvl);
        const golden = Math.max(0, tile.b.lvl - 5);
        for (let l = 0; l < pips; l++) {
          ctx.fillStyle = l < golden ? '#ffd43b' : '#fff3bf';
          ctx.beginPath();
          ctx.arc(x * T + T * (0.5 - (pips - 1) * 0.06 + l * 0.12), y * T + T * 0.88, T * (l < golden ? 0.05 : 0.04), 0, Math.PI * 2);
          ctx.fill();
        }
        if (info && !info.active) this.emoji('⚠️', x * T + T * 0.8, y * T + T * 0.2, T * 0.28);
      }
    }

    // Terra bloqueada + borda do reino
    for (let y = 0; y < GRID_H; y++) {
      for (let x = 0; x < GRID_W; x++) {
        if (!isUnlocked(grid, x, y)) {
          ctx.fillStyle = ringOf(x, y) === grid.ring + 1 ? 'rgba(12,14,24,0.55)' : 'rgba(12,14,24,0.75)';
          ctx.fillRect(x * T, y * T, T + 0.5, T + 0.5);
        }
      }
    }
    const r = grid.ring;
    const lo = Math.ceil((GRID_W - 1) / 2 - r - 0.5);
    const span = (GRID_W - 2 * lo) * T;
    ctx.strokeStyle = 'rgba(255,212,59,0.85)';
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.strokeRect(lo * T + 1, lo * T + 1, span - 2, span - 2);
    ctx.setLineDash([]);

    // Baú
    if (!this.view && state.chest) {
      const { x, y } = state.chest;
      const glow = 0.5 + 0.5 * Math.sin(now / 200);
      const g = ctx.createRadialGradient(x * T + T / 2, y * T + T / 2, 2, x * T + T / 2, y * T + T / 2, T * 0.7);
      g.addColorStop(0, `rgba(255,224,102,${0.55 + glow * 0.3})`);
      g.addColorStop(1, 'rgba(255,224,102,0)');
      ctx.fillStyle = g;
      ctx.fillRect(x * T - T * 0.2, y * T - T * 0.2, T * 1.4, T * 1.4);
      this.emoji('🎁', x * T + T / 2, y * T + T / 2 - Math.abs(Math.sin(now / 250)) * T * 0.15, T * 0.6);
    }

    // Seleção
    if (this.selected && !this.view) {
      const { x, y } = this.selected;
      ctx.strokeStyle = `rgba(255,255,255,${0.6 + 0.4 * Math.sin(now / 200)})`;
      ctx.lineWidth = 3;
      roundRect(ctx, x * T + 2, y * T + 2, T - 4, T - 4, T * 0.15);
      ctx.stroke();
      const info = econ?.tiles[idx(x, y)];
      if (info) this.drawAdjParts(info.adjParts, T);
    }

    // Prévia de construção / movimento
    if (this.hover && !this.view) this.drawPreview(game, T);

    // Efeitos
    this.fx = this.fx.filter((f) => now - f.born < f.life);
    for (const f of this.fx) {
      const p = (now - f.born) / f.life;
      if (f.kind === 'float') {
        ctx.globalAlpha = 1 - p;
        ctx.font = `bold ${Math.max(11, T * 0.26)}px Nunito, system-ui, sans-serif`;
        ctx.textAlign = 'center';
        ctx.lineWidth = 3;
        ctx.strokeStyle = 'rgba(0,0,0,0.6)';
        const fy = f.y * T + T * 0.3 - p * T * 0.8;
        ctx.strokeText(f.text, f.x * T + T / 2, fy);
        ctx.fillStyle = f.color;
        ctx.fillText(f.text, f.x * T + T / 2, fy);
      } else {
        ctx.globalAlpha = 1 - p;
        ctx.fillStyle = f.color;
        ctx.beginPath();
        ctx.arc(f.x * T + T / 2 + f.vx * p * T, f.y * T + T / 2 + f.vy * p * T, 3 * (1 - p) + 1, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    if (this.flash && this.flash.until > now) {
      ctx.globalAlpha = ((this.flash.until - now) / this.flash.ms) * 0.45;
      ctx.fillStyle = this.flash.color;
      ctx.fillRect(-20, -20, this.size + 40, this.size + 40);
      ctx.globalAlpha = 1;
    }
    ctx.restore();
  }

  drawAdjParts(parts, T) {
    for (const p of parts) this.label(p.x * T + T / 2, p.y * T + T * 0.22, fmtPct(p.value), p.value > 0 ? '#8ce99a' : '#ff8787', T);
  }

  drawPreview(game, T) {
    const ctx = this.ctx;
    const { x, y } = this.hover;
    const state = game.state;
    const tile = state.grid.tiles[idx(x, y)];
    const mode = this.mode;
    let buildId = null;
    let valid = false;
    if (mode.type === 'build') {
      buildId = mode.id;
      valid = !tile.b && TERRAIN[tile.t].buildable && isUnlocked(state.grid, x, y);
    } else if (mode.type === 'move') {
      buildId = state.grid.tiles[idx(mode.from.x, mode.from.y)].b?.id;
      valid = !tile.b && TERRAIN[tile.t].buildable && isUnlocked(state.grid, x, y);
    } else {
      ctx.strokeStyle = 'rgba(255,255,255,0.5)';
      ctx.lineWidth = 2;
      roundRect(ctx, x * T + 2, y * T + 2, T - 4, T - 4, T * 0.15);
      ctx.stroke();
      return;
    }
    if (!buildId) return;
    ctx.fillStyle = valid ? 'rgba(140,233,154,0.28)' : 'rgba(255,107,107,0.35)';
    ctx.fillRect(x * T, y * T, T, T);
    if (!valid) return;
    // Para o modo mover, simula o tile de origem vazio.
    let restore = null;
    if (mode.type === 'move') {
      const from = state.grid.tiles[idx(mode.from.x, mode.from.y)];
      restore = from.b;
      from.b = null;
    }
    const adj = adjacencyAt(state, buildId, x, y, game.econ.mods);
    if (restore) state.grid.tiles[idx(mode.from.x, mode.from.y)].b = restore;
    ctx.globalAlpha = 0.75;
    this.emoji(BUILDINGS[buildId].icon, x * T + T / 2, y * T + T / 2, T * 0.6);
    ctx.globalAlpha = 1;
    for (const [nx, ny] of neighbors(x, y)) {
      ctx.strokeStyle = 'rgba(255,255,255,0.18)';
      ctx.strokeRect(nx * T + 1, ny * T + 1, T - 2, T - 2);
    }
    this.drawAdjParts(adj.parts, T);
    const total = adj.hasRequired ? fmtPct(adj.total) : 'precisa de ⛰️';
    const color = !adj.hasRequired ? '#ff8787' : adj.total > 0 ? '#ffd43b' : adj.total < 0 ? '#ff8787' : '#ffffff';
    this.label(x * T + T / 2, y * T - T * 0.12, total, color, T, true);
  }

  label(cx, cy, text, color, T, big = false) {
    const ctx = this.ctx;
    ctx.font = `800 ${Math.max(10, T * (big ? 0.3 : 0.22))}px Nunito, system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const w = ctx.measureText(text).width + 8;
    const h = Math.max(14, T * (big ? 0.38 : 0.3));
    ctx.fillStyle = 'rgba(20,16,30,0.85)';
    roundRect(ctx, cx - w / 2, cy - h / 2, w, h, h / 2);
    ctx.fill();
    ctx.fillStyle = color;
    ctx.fillText(text, cx, cy + 1);
  }

  emoji(ch, x, y, size) {
    const ctx = this.ctx;
    ctx.font = `${size}px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(ch, x, y);
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
