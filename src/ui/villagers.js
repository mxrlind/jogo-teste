// Vida da vila: moradores com profissão e rotina, desenhados sobre o mapa.
// Só visual: lê o estado e a economia (moradores, vagas por prédio) e nunca os altera.
//
// - Quem trabalha onde segue a mesma regra do motor (economy.js): fazendas e moinhos são ocupados
//   primeiro; o resto vai para os outros prédios. Quem sobra sem emprego dorme na rua.
// - Cada profissão tem uma rotina de paradas (ex.: lavrador colhe na fazenda e leva comida ao armazém).
//   A rotina é refeita a cada volta, então reage a prédios novos, demolidos e à horda anunciada.
// - O caminho é uma busca em largura pela grama livre; se não houver, atravessa o que der.
import { BUILDINGS } from '../data/buildings.js';
import { GRID_W, GRID_H, idx, isUnlocked, neighbors } from '../core/map.js';
import { PROFESSIONS, SLEEPER_SPRITES } from './sprites.js';
import { iconKey, RES_COLORS, TOOL_COLOR } from './assets.js';

const MAX_WORKERS = 32; // moradores trabalhando visíveis ao mesmo tempo
const MAX_SLEEPERS = 8;
const SPEED = 0.6; // tiles por segundo
// Estilo "stop motion": a vila só avança em quadros de STEP segundos (5 por segundo). Entre um quadro e
// outro ninguém se mexe; cada quadro é um passinho e alterna a pose (pé no chão / no ar, ferramenta em cima / embaixo).
const STEP = 0.2;
const SYNC_MS = 1000;
const REST_EVERY = 3; // voltas de trabalho antes de descansar em casa
const PRODUCERS = { fazenda: 'food', moinho: 'food', serraria: 'wood', pedreira: 'stone', mina: 'gold' };
const isFood = (id) => Boolean(BUILDINGS[id]?.prod?.food);
const rand = (a, b) => a + Math.random() * (b - a);
const pickOne = (arr) => arr[Math.floor(Math.random() * arr.length)];

export class VillageLife {
  constructor() {
    this.people = new Map(); // chave estável -> morador
    this.lastSync = 0;
    this.lastTime = 0;
    this.stateRef = null;
  }

  // ---------------------------------------------------------------- quem existe
  sync(game) {
    const s = game.state;
    const econ = game.econ;
    const grid = s.grid;
    const houses = [];
    const jobs = [];
    grid.tiles.forEach((t, i) => {
      if (!t.b) return;
      if (t.b.id === 'casa') houses.push(i);
      const info = econ.tiles[i];
      if (info && info.workers > 0 && info.active !== false && PROFESSIONS[t.b.id]) jobs.push({ i, id: t.b.id, need: info.workers });
    });
    // Mesma prioridade do motor: quem produz comida é ocupado primeiro.
    jobs.sort((a, b) => Number(isFood(b.id)) - Number(isFood(a.id)) || a.i - b.i);
    const pop = Math.floor(s.pop);
    let free = pop;
    for (const j of jobs) { j.filled = Math.min(j.need, free); free -= j.filled; }
    const employed = pop - free;

    // Até 2 visíveis por prédio; com muitos prédios, primeiro 1 em cada, depois o 2º.
    const want = new Map();
    let budget = MAX_WORKERS;
    for (const round of [0, 1]) {
      for (const j of jobs) {
        if (budget <= 0 || j.filled <= round) continue;
        const key = `w:${j.i}:${j.id}:${round}`;
        want.set(key, { kind: 'work', job: j.id, at: j.i, home: houses.length ? houses[(want.size) % houses.length] : j.i });
        budget--;
      }
    }
    const sleepers = Math.min(MAX_SLEEPERS, Math.max(0, pop - employed));
    const spots = this.sleepSpots(grid, houses, sleepers);
    for (let k = 0; k < spots.length; k++) want.set(`z:${k}`, { kind: 'sleep', spot: spots[k], sprite: SLEEPER_SPRITES[k % SLEEPER_SPRITES.length] });

    for (const key of [...this.people.keys()]) if (!want.has(key)) this.people.delete(key);
    for (const [key, w] of want) {
      const p = this.people.get(key);
      if (p) {
        if (w.kind === 'work') p.home = w.home;
        else { p.x = w.spot.x; p.y = w.spot.y; }
        continue;
      }
      if (w.kind === 'sleep') {
        this.people.set(key, { kind: 'sleep', x: w.spot.x, y: w.spot.y, sprite: w.sprite, seed: Math.random() * 10 });
      } else {
        const start = cellCenter(w.home);
        this.people.set(key, {
          kind: 'work', job: w.job, at: w.at, home: w.home, sprite: PROFESSIONS[w.job].sprite, tool: PROFESSIONS[w.job].tool,
          x: start.x + rand(-0.15, 0.15), y: start.y + 0.3, path: [], stops: [], stop: 0, wait: rand(0, 1.2), state: 'wait',
          carry: null, cycles: Math.floor(rand(0, REST_EVERY)), hidden: false, flip: false, pose: Math.random() < 0.5 ? 1 : 0,
        });
      }
    }
  }

  // Lugares na rua para quem não tem emprego: grama livre encostada nas casas (depois, qualquer grama).
  sleepSpots(grid, houses, n) {
    if (!n) return [];
    const near = [];
    const other = [];
    grid.tiles.forEach((t, i) => {
      const x = i % GRID_W;
      const y = Math.floor(i / GRID_W);
      if (t.b || t.t !== 'grass' || !isUnlocked(grid, x, y)) return;
      (neighbors(x, y).some(([nx, ny]) => houses.includes(idx(nx, ny))) ? near : other).push(i);
    });
    const cells = [...near, ...other];
    const out = [];
    for (let k = 0; k < n && cells.length; k++) {
      const i = cells[Math.floor(k / 2) % cells.length]; // até 2 por tile, lado a lado
      out.push({ x: (i % GRID_W) + (k % 2 ? 0.66 : 0.34), y: Math.floor(i / GRID_W) + 0.55 });
    }
    return out;
  }

  // ---------------------------------------------------------------- rotinas
  // Cada parada: { cell, dur, tool?, carry? } — carry é o que vai na mão a caminho daquela parada.
  plan(p, game) {
    const s = game.state;
    const grid = s.grid;
    const w = p.at;
    const nearest = (ids, from = w) => nearestBuilding(grid, ids, from);
    const store = (from = w) => nearest(['armazem'], from);
    const adjacent = (types) => adjacentTerrain(grid, w, types);
    const anyOf = (ids) => { const all = buildingsOf(grid, ids); return all.length ? pickOne(all) : null; };
    const stops = [];
    const add = (cell, dur, extra = {}) => { if (cell != null) stops.push({ cell, dur, ...extra }); };
    switch (p.job) {
      case 'fazenda':
        add(w, rand(3, 4.5), { tool: 'clear' });
        add(nearest(['armazem', 'moinho', 'mercado']) ?? p.home, 0.8, { carry: 'food' });
        break;
      case 'serraria':
        add(adjacent(['forest']) ?? w, rand(2.5, 3.5), { tool: 'hero-woodcutter' });
        add(w, 1.2, { carry: 'wood' });
        add(store(), 0.8, { carry: 'wood' });
        break;
      case 'pedreira':
      case 'mina': {
        const res = PRODUCERS[p.job];
        add(adjacent(p.job === 'mina' ? ['mountain'] : ['rock', 'mountain']) ?? w, rand(2.5, 3.5), { tool: 'tool-pickaxe' });
        add(w, 1, { carry: res });
        add(store(), 0.8, { carry: res });
        break;
      }
      case 'moinho':
        add(nearest(['fazenda']) ?? w, 1.2);
        add(w, rand(2.5, 3.5), { carry: 'food' });
        add(store(), 0.8, { carry: 'food' });
        break;
      case 'mercado':
        add(nearest(['armazem', 'fazenda', 'moinho']) ?? w, 1);
        add(w, rand(2.5, 3.5), { carry: 'food' });
        add(anyOf(['casa']), 0.8, { carry: 'gold' });
        break;
      case 'armazem': {
        const src = anyOf(Object.keys(PRODUCERS));
        add(src ?? w, 1);
        add(w, 1.5, { carry: src != null ? PRODUCERS[grid.tiles[src].b.id] : null });
        break;
      }
      case 'taverna':
        add(w, rand(3, 5));
        add(anyOf(['casa']), 1);
        break;
      case 'torre':
        add(w, rand(3, 5));
        // Com a horda anunciada, o guarda corre para a borda de onde ela vem.
        add(s.raid.warned ? raidEdge(grid, s.raid.dir) : anyOf(['torre', 'muralha']) ?? w, 2);
        break;
      case 'templo':
        add(w, rand(4, 6));
        add(anyOf(['jardim', 'fogueira', 'estatua', 'casa']), 1.5);
        break;
      default:
        add(w, 3);
    }
    p.cycles++;
    if (p.cycles % REST_EVERY === 0 && p.home !== w) add(p.home, rand(3, 5), { rest: true });
    p.stops = stops;
    p.stop = -1;
  }

  // Próxima parada: traça o caminho e começa a andar.
  next(p, game) {
    p.stop++;
    if (p.stop >= p.stops.length) { this.plan(p, game); p.stop = 0; }
    const st = p.stops[p.stop];
    if (!st) { p.state = 'wait'; p.wait = 1; return; }
    p.carry = st.carry ?? null;
    p.hidden = false;
    p.path = route(game.state.grid, { x: p.x, y: p.y }, st.cell);
    p.state = 'walk';
  }

  // ---------------------------------------------------------------- tempo
  update(game, now) {
    const dt = Math.max(0, (now - (this.lastTime || now)) / 1000);
    this.lastTime = now;
    if (game.state !== this.stateRef) { this.stateRef = game.state; this.people.clear(); this.lastSync = 0; } // reino novo ou ascendido
    if (now - this.lastSync > SYNC_MS) { this.lastSync = now; this.sync(game); }
    // Acumula o tempo e avança em quadros fixos; no máximo 2 de uma vez (aba que volta de segundo plano não "teleporta").
    this.acc = Math.min((this.acc || 0) + dt, STEP * 2);
    while (this.acc >= STEP) { this.acc -= STEP; this.step(game, STEP); }
  }

  step(game, dt) {
    for (const p of this.people.values()) {
      if (p.kind !== 'work') continue;
      if (p.state === 'walk') {
        const tgt = p.path[0];
        if (!tgt) {
          const st = p.stops[p.stop];
          p.state = 'act';
          p.wait = st?.dur ?? 1;
          if (st?.rest) p.hidden = true; // entrou em casa
          continue;
        }
        const dx = tgt.x - p.x;
        const dy = tgt.y - p.y;
        const d = Math.hypot(dx, dy);
        const step = SPEED * dt;
        if (d <= step) { p.x = tgt.x; p.y = tgt.y; p.path.shift(); } else { p.x += (dx / d) * step; p.y += (dy / d) * step; }
        if (Math.abs(dx) > 0.01) p.flip = dx < 0;
        p.pose ^= 1;
      } else {
        p.wait -= dt;
        p.pose ^= 1;
        if (p.wait <= 0) this.next(p, game);
      }
    }
  }

  // ---------------------------------------------------------------- desenho
  draw(r, now, T) {
    const ctx = r.ctx;
    const list = [...this.people.values()].filter((p) => !p.hidden).sort((a, b) => a.y - b.y);
    const size = T * 0.5;
    for (const p of list) {
      const cx = p.x * T;
      const cy = p.y * T;
      // sombra
      ctx.fillStyle = 'rgba(0, 0, 0, 0.22)';
      ctx.beginPath();
      ctx.ellipse(cx, cy + size * 0.36, size * (p.kind === 'sleep' ? 0.42 : 0.26), size * 0.1, 0, 0, Math.PI * 2);
      ctx.fill();
      if (p.kind === 'sleep') { this.drawSleeper(r, p, now, cx, cy, size, T); continue; }
      const walking = p.state === 'walk';
      const working = p.state === 'act' && p.stops[p.stop]?.tool;
      // duas poses por ação, trocadas a cada quadro
      const bob = p.pose ? (walking ? -T * 0.04 : working ? -T * 0.025 : 0) : 0;
      ctx.save();
      ctx.translate(cx, cy + bob);
      if (p.flip) ctx.scale(-1, 1);
      r.img(p.sprite, -size / 2, -size / 2, size, size);
      if (working) {
        // ferramenta balançando na mão
        ctx.save();
        ctx.translate(size * 0.3, -size * 0.02);
        ctx.rotate(p.pose ? -0.9 : 0.55); // ferramenta levantada / batendo
        r.img(iconKey(p.stops[p.stop].tool, TOOL_COLOR), -size * 0.06, -size * 0.42, size * 0.42, size * 0.42);
        ctx.restore();
      }
      ctx.restore();
      if (p.carry && walking) {
        const s = size * 0.42;
        r.img(iconKey(p.carry, RES_COLORS[p.carry]), cx - s / 2, cy + bob - size * 0.62 - s / 2, s, s);
      }
    }
  }

  drawSleeper(r, p, now, cx, cy, size, T) {
    const ctx = r.ctx;
    ctx.save();
    ctx.translate(cx, cy + size * 0.1);
    ctx.rotate(-Math.PI / 2); // deitado
    ctx.globalAlpha = 0.92;
    r.img(p.sprite, -size / 2, -size / 2, size, size);
    ctx.restore();
    // "z z z" subindo, cada um com um atraso
    ctx.font = `800 ${Math.max(9, T * 0.16)}px Nunito, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = 'rgba(30, 30, 50, 0.55)';
    ctx.fillStyle = '#ffffff';
    const frame = Math.floor(now / (STEP * 1000)) * STEP * 1000; // os "z" também sobem em degraus
    for (let k = 0; k < 3; k++) {
      const t = ((frame / 1600 + p.seed + k / 3) % 1);
      const zx = cx + size * 0.25 + t * size * 0.35;
      const zy = cy - size * 0.15 - t * size * 0.9;
      ctx.globalAlpha = Math.sin(t * Math.PI);
      ctx.strokeText('z', zx, zy);
      ctx.fillText('z', zx, zy);
    }
    ctx.globalAlpha = 1;
  }
}

// ================================================================ grade e caminhos
const cellCenter = (i) => ({ x: (i % GRID_W) + 0.5, y: Math.floor(i / GRID_W) + 0.5 });

function buildingsOf(grid, ids) {
  const out = [];
  grid.tiles.forEach((t, i) => { if (t.b && ids.includes(t.b.id)) out.push(i); });
  return out;
}

function nearestBuilding(grid, ids, from) {
  const fx = from % GRID_W;
  const fy = Math.floor(from / GRID_W);
  let best = null;
  let bestD = Infinity;
  for (const i of buildingsOf(grid, ids)) {
    if (i === from) continue;
    const d = Math.abs((i % GRID_W) - fx) + Math.abs(Math.floor(i / GRID_W) - fy);
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

function adjacentTerrain(grid, at, types) {
  const options = neighbors(at % GRID_W, Math.floor(at / GRID_W)).filter(([x, y]) => isUnlocked(grid, x, y) && types.includes(grid.tiles[idx(x, y)].t));
  if (!options.length) return null;
  const [x, y] = pickOne(options);
  return idx(x, y);
}

// Ponto na borda da área conquistada, do lado de onde vem a horda.
function raidEdge(grid, dir) {
  const lo = Math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5);
  const hi = GRID_W - 1 - lo;
  const along = Math.round(rand(lo + 1, hi - 1));
  const [x, y] = { n: [along, lo], s: [along, hi], w: [lo, along], e: [hi, along] }[dir] ?? [along, lo];
  return idx(x, y);
}

// Busca em largura do tile atual até `goal`. Primeiro só pela grama livre; se não houver caminho,
// por qualquer chão conquistado que não seja água ou montanha; por fim, em linha reta.
function route(grid, from, goal) {
  const start = idx(Math.max(0, Math.min(GRID_W - 1, Math.floor(from.x))), Math.max(0, Math.min(GRID_H - 1, Math.floor(from.y))));
  const strict = (i) => { const t = grid.tiles[i]; return !t.b && t.t === 'grass'; };
  const loose = (i) => { const t = grid.tiles[i]; return t.t !== 'water' && t.t !== 'mountain'; };
  const cells = bfs(grid, start, goal, strict) ?? bfs(grid, start, goal, loose) ?? [start, goal];
  const pts = cells.slice(1).map((i) => {
    const c = cellCenter(i);
    return { x: c.x + rand(-0.12, 0.12), y: c.y + rand(-0.12, 0.12) };
  });
  // Para na "porta": um pouco antes do centro do destino, do lado de onde veio.
  const prev = cells.length > 1 ? cellCenter(cells[cells.length - 2]) : from;
  const g = cellCenter(goal);
  const dx = prev.x - g.x;
  const dy = prev.y - g.y;
  const d = Math.hypot(dx, dy) || 1;
  const door = { x: g.x + (dx / d) * 0.3, y: g.y + (dy / d) * 0.3 };
  if (pts.length) pts[pts.length - 1] = door; else pts.push(door);
  return pts;
}

function bfs(grid, start, goal, passable) {
  if (start === goal) return [start];
  const prev = new Int16Array(grid.tiles.length).fill(-1);
  prev[start] = start;
  const queue = [start];
  for (let q = 0; q < queue.length; q++) {
    const cur = queue[q];
    for (const [nx, ny] of neighbors(cur % GRID_W, Math.floor(cur / GRID_W))) {
      const n = idx(nx, ny);
      if (prev[n] !== -1 || !isUnlocked(grid, nx, ny)) continue;
      if (n !== goal && !passable(n)) continue;
      prev[n] = cur;
      if (n === goal) {
        const path = [n];
        for (let c = cur; c !== start; c = prev[c]) path.push(c);
        path.push(start);
        return path.reverse();
      }
      queue.push(n);
    }
  }
  return null;
}
