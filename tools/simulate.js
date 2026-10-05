// Simulador de balanceamento: um bot "guloso" joga N horas e registra marcos.
// Uso: npm run simulate -- [horas=8] [semente=1] [--ascend]
// Os resultados alimentam docs/BALANCEAMENTO.md. O bot é ingênuo de propósito:
// um jogador humano que entende adjacência deve ir mais rápido.
import { createState } from '../src/core/state.js';
import { Game } from '../src/core/game.js';
import { BUILDINGS, TERRAIN, MAX_LEVEL } from '../src/data/buildings.js';
import { buildCost, upgradeCost, canAfford, adjacencyAt, computeEconomy, dirWeight } from '../src/core/economy.js';
import { GRID_W, idx, isUnlocked } from '../src/core/map.js';
import { fmt, fmtTime } from '../src/core/format.js';
import { tierOf } from '../src/core/season.js';

const hours = Number(process.argv[2]) || 8;
const seed = Number(process.argv[3]) || 1;
const doAscend = process.argv.includes('--ascend');
const T0 = Date.UTC(2026, 0, 6, 12); // temporada "Fundação" (neutra o suficiente)

// Peso de cada recurso em "ouro equivalente" para comparar investimentos.
const VALUE = { gold: 1, food: 0.6, wood: 1.5, stone: 2, gems: 50 };
const costValue = (c) => Object.entries(c).reduce((s, [r, v]) => s + v * (VALUE[r] || 1), 0);

const s = createState({ seed, now: T0 });
s.tutorial.done = true;
const g = new Game(s, T0);
let now = T0;
const marks = {};
const mark = (k) => { if (!(k in marks)) marks[k] = (now - T0) / 1000; };
const snapshots = [];

function freeTiles() {
  const out = [];
  g.state.grid.tiles.forEach((t, i) => {
    const x = i % GRID_W;
    const y = Math.floor(i / GRID_W);
    if (!t.b && TERRAIN[t.t].buildable && isUnlocked(g.state.grid, x, y)) out.push([x, y]);
  });
  return out;
}

// Defesas preferem o lado de onde vem a próxima horda (a direção é anunciada com antecedência).
function bestSpot(id) {
  let best = null;
  const def = BUILDINGS[id].defense;
  for (const [x, y] of freeTiles()) {
    const a = adjacencyAt(g.state, id, x, y, g.econ.mods);
    if (!a.hasRequired) continue;
    const score = a.total + (def ? 2 * dirWeight(g.state.raid.dir, x, y) : 0);
    if (!best || score > best.total) best = { x, y, total: score };
  }
  return best;
}

// Ganho marginal de valor/s ao aplicar uma mudança hipotética.
// Avalia com a população já crescida até a capacidade (ela converge rápido se houver comida).
function settled() {
  const pop = g.state.pop;
  g.state.pop = computeEconomy(g.state, now).popCap;
  const e = computeEconomy(g.state, now);
  g.state.pop = pop;
  return e;
}

function marginal(apply, undo) {
  const before = settled();
  apply();
  const after = settled();
  undo();
  const v = (e) => e.rates.gold * VALUE.gold + Math.max(0, e.rates.food) * VALUE.food * 0.3 + e.rates.wood * VALUE.wood + e.rates.stone * VALUE.stone;
  return v(after) - v(before);
}

function decide() {
  const st = g.state;
  const e = g.econ;
  if (st.chest) g.openChest();
  if (g.dailyStatus().available) g.claimDaily();
  st.season.missions?.list.forEach((m, i) => { if (!m.claimed && m.progress >= m.target) g.claimMission(i); });
  if (st.items.scrolls > 0) g.recruit('scroll');
  if (st.res.gems >= 15) g.recruit('gems');

  const tryBuild = (id) => {
    if (!g.isAvailable(id)) return false;
    const cost = buildCost(st, id, e.mods);
    if (!canAfford(st.res, cost)) return false;
    const spot = bestSpot(id);
    return spot ? g.build(id, spot.x, spot.y).ok : false;
  };

  // Necessidades básicas primeiro
  if (e.rates.food < 0.3 && tryBuild('fazenda')) return;
  if (e.workersNeeded >= e.popCap * 0.85 && tryBuild('casa')) return;
  const strength = g.raidStrength();
  if (e.defense < strength * 1.3) {
    if (tryBuild(st.res.stone > 200 && g.isAvailable('torre') ? 'torre' : 'muralha')) return;
  }
  if (e.rates.stone < 0.5 + e.rates.gold / 60 && g.isAvailable('pedreira') && tryBuild('pedreira')) return;
  if (e.rates.wood < 0.5 + e.rates.gold / 40 && tryBuild('serraria')) return;
  if (e.happiness < 55 && tryBuild('taverna')) return;
  if (g.expandCost() && canAfford(st.res, g.expandCost()) && freeTiles().length < 6) { g.expand(); return; }

  // Precisa de armazém? (algum objetivo custa mais do que cabe no cofre)
  const fits = (c) => Object.entries(c).every(([r, v]) => r === 'gems' || v <= (e.caps[r] ?? Infinity));
  const exp = g.expandCost();
  if (exp && !fits(exp)) {
    const arm = st.grid.tiles.findIndex((t) => t.b?.id === 'armazem' && upgradeCost('armazem', t.b.lvl, e.mods) && canAfford(st.res, upgradeCost('armazem', t.b.lvl, e.mods)));
    if (arm >= 0) { g.upgrade(arm % GRID_W, Math.floor(arm / GRID_W)); return; }
    if (tryBuild('armazem')) return;
  }

  // Melhor retorno sobre investimento entre construir e melhorar (só o que cabe no cofre)
  let best = null;
  for (const id of ['casa', 'fazenda', 'serraria', 'pedreira', 'mercado', 'moinho', 'mina', 'taverna']) {
    if (!g.isAvailable(id)) continue;
    const cost = buildCost(st, id, e.mods);
    if (!fits(cost)) continue;
    const spot = bestSpot(id);
    if (!spot) continue;
    const tile = st.grid.tiles[idx(spot.x, spot.y)];
    const gain = marginal(() => { tile.b = { id, lvl: 1 }; }, () => { tile.b = null; });
    const roi = gain / costValue(cost);
    if (!best || roi > best.roi) best = { roi, cost, act: () => g.build(id, spot.x, spot.y) };
  }
  st.grid.tiles.forEach((tile, i) => {
    if (!tile.b) return;
    const cost = upgradeCost(tile.b.id, tile.b.lvl, e.mods);
    if (!cost || !fits(cost)) return;
    const gain = marginal(() => { tile.b.lvl++; }, () => { tile.b.lvl--; });
    const roi = gain / costValue(cost);
    if (!best || roi > best.roi) best = { roi, cost, act: () => g.upgrade(i % GRID_W, Math.floor(i / GRID_W)) };
  });
  // Defesa: melhora torres/muralhas quando não há espaço para novas
  if (e.defense < g.raidStrength() * 1.3) {
    const d = st.grid.tiles.findIndex((t) => (t.b?.id === 'torre' || t.b?.id === 'muralha') && t.b.lvl < MAX_LEVEL && canAfford(st.res, upgradeCost(t.b.id, t.b.lvl, e.mods)));
    if (d >= 0) { g.upgrade(d % GRID_W, Math.floor(d / GRID_W)); return; }
  }
  if (best && best.roi > 0 && canAfford(st.res, best.cost)) best.act();
  else if (!best || st.res.gold >= e.caps.gold * 0.95) {
    const arm = st.grid.tiles.findIndex((t) => t.b?.id === 'armazem' && t.b.lvl < MAX_LEVEL && canAfford(st.res, upgradeCost('armazem', t.b.lvl, e.mods)));
    if (arm >= 0) g.upgrade(arm % GRID_W, Math.floor(arm / GRID_W));
    else tryBuild('armazem');
  }
}

// Política de prestígio do bot: ascende quando dobraria as coroas que já tem (mín. 2)
// e gasta tudo no talento mais barato entre Fartura, Engenharia e Herança.
function maybeAscend() {
  const c = g.crownsOnAscend();
  const owned = g.state.res.crowns + Object.entries(g.state.legacy).reduce((s, [id, l]) => s + l, 0);
  if (c < Math.max(2, owned)) return;
  g.ascend();
  g.state.tutorial.done = true;
  mark(`ascensão ${g.state.stats.ascensions} (+${c} coroas)`);
  for (;;) {
    const options = ['fartura', 'engenharia', 'heranca', 'muralhas'].map((id) => ({ id, cost: g.talentCost(id) })).filter((o) => o.cost != null && o.cost <= g.state.res.crowns);
    if (!options.length) break;
    options.sort((a, b) => a.cost - b.cost);
    g.buyTalent(options[0].id);
  }
}

const total = hours * 3600;
for (let t = 1; t <= total; t++) {
  now = T0 + t * 1000;
  g.tick(now);
  if (t % 5 === 0) decide();
  if (doAscend && t % 60 === 0) maybeAscend();
  const st = g.state;
  const n = st.grid.tiles.filter((x) => x.b).length;
  if (n >= 10) mark('10 construções');
  if (n >= 25) mark('25 construções');
  if (n >= 50) mark('50 construções');
  for (const v of [1e3, 1e4, 1e5, 1e6, 1e7]) if (st.stats.totalGold >= v) mark(`${fmt(v)} de ouro (total)`);
  for (const r of [3, 4, 5]) if (st.grid.ring >= r) mark(`anel ${r}`);
  if (st.grid.tiles.some((x) => x.b?.id === 'mercado')) mark('1º mercado');
  if (st.grid.tiles.some((x) => x.b?.id === 'mina')) mark('1ª mina');
  if (st.stats.raidsWon >= 1) mark('1ª invasão vencida');
  if (g.crownsOnAscend() >= 1) mark('1ª Coroa disponível');
  if (t % 1800 === 0) {
    snapshots.push({
      t: fmtTime(t), gold: fmtRate(g.econ.rates.gold), wood: fmtRate(g.econ.rates.wood), stone: fmtRate(g.econ.rates.stone), food: fmtRate(g.econ.rates.food), def: Math.floor(g.econ.defense), str: g.raidStrength(), happy: Math.floor(g.econ.happiness), staff: g.econ.staffing.toFixed(2), pop: Math.floor(st.pop), buildings: n,
      asc: st.stats.ascensions, raid: st.raid.level, won: st.stats.raidsWon, lost: st.stats.raidsLost, crowns: g.crownsOnAscend(), tier: tierOf(st.season.xp),
    });
  }
}

function fmtRate(v) { return fmt(v) + '/s'; }

console.log(`\nSimulação: ${hours}h · semente ${seed}${doAscend ? ' · com Ascensão' : ''}\n`);
console.log('Marcos:');
for (const [k, v] of Object.entries(marks).sort((a, b) => a[1] - b[1])) console.log(`  ${fmtTime(v).padStart(8)}  ${k}`);
console.log('\nA cada 30 min:');
console.table(snapshots);
