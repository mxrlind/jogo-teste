// Testes do motor (sem navegador). Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createState, serialize, deserialize, exportSave, importSave } from '../src/core/state.js';
import { Game } from '../src/core/game.js';
import { computeEconomy, adjacencyAt, buildCost, upgradeCost, collectModifiers } from '../src/core/economy.js';
import { generateMap, ringOf, isUnlocked, idx, GRID_W, GRID_H } from '../src/core/map.js';
import { seasonInfo, dailyMissions, tierOf } from '../src/core/season.js';
import { encodeKingdom, decodeKingdom, generateRivals, rivalGrid } from '../src/core/social.js';
import { addHero } from '../src/core/heroes.js';
import { HERO_BY_ID } from '../src/data/heroes.js';
import { SEASON_EPOCH } from '../src/data/seasons.js';
import { fmt, fmtTime } from '../src/core/format.js';

const T0 = Date.UTC(2026, 9, 5, 12); // 5 out 2026 (temporada "Guerra")

function freshGame(seed = 7) {
  const s = createState({ seed, now: T0 });
  return new Game(s, T0);
}

// Coloca um terreno/prédio arbitrário (para montar cenários de adjacência).
function put(state, x, y, t, b = null) {
  state.grid.tiles[idx(x, y)] = { t, b };
}

function clearArea(state) {
  for (let y = 0; y < GRID_H; y++) for (let x = 0; x < GRID_W; x++) put(state, x, y, 'grass');
}

test('mapa: 12x12, anel inicial 6x6, prédios iniciais e garantias de terreno', () => {
  for (const seed of [1, 2, 3, 99, 12345]) {
    const g = generateMap(seed);
    assert.equal(g.tiles.length, 144);
    assert.equal(g.ring, 2);
    const unlocked = g.tiles.filter((_, i) => isUnlocked(g, i % 12, Math.floor(i / 12))).length;
    assert.equal(unlocked, 36);
    assert.equal(g.tiles[idx(5, 5)].b.id, 'casa');
    assert.equal(g.tiles[idx(6, 5)].b.id, 'fazenda');
    const near = (type, rmax) => g.tiles.filter((t, i) => t.t === type && ringOf(i % 12, Math.floor(i / 12)) <= rmax).length;
    assert.ok(near('forest', 2) >= 3, 'florestas no início');
    assert.ok(near('rock', 2) >= 2, 'rochas no início');
    assert.ok(near('water', 2) >= 1, 'água no início');
    assert.ok(g.tiles.some((t, i) => t.t === 'mountain' && ringOf(i % 12, Math.floor(i / 12)) === 3), 'montanha no anel 3');
  }
});

test('mapa: mesma semente gera o mesmo mapa', () => {
  assert.deepEqual(generateMap(42), generateMap(42));
  assert.notDeepEqual(generateMap(42), generateMap(43));
});

test('adjacência: serraria soma +40% por floresta, armazém +15%', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 5, 4, 'forest');
  put(s, 5, 6, 'forest');
  put(s, 4, 5, 'grass', { id: 'armazem', lvl: 1 });
  const mods = collectModifiers(s, T0);
  const adj = adjacencyAt(s, 'serraria', 5, 5, mods);
  assert.equal(Math.round(adj.total * 100), 95);
  assert.equal(adj.parts.length, 3);
});

test('adjacência: vizinhos negativos (mercado x mercado, pedreira x casa)', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 4, 5, 'grass', { id: 'mercado', lvl: 1 });
  put(s, 6, 5, 'grass', { id: 'pedreira', lvl: 1 });
  const mods = collectModifiers(s, T0);
  assert.equal(adjacencyAt(s, 'mercado', 5, 5, mods).total, -0.2);
  assert.equal(adjacencyAt(s, 'casa', 5, 5, mods).total, 0.5 - 0.3);
});

test('mina só produz encostada em montanha', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  s.pop = 50;
  put(s, 3, 3, 'grass', { id: 'mina', lvl: 1 });
  put(s, 8, 8, 'grass', { id: 'mina', lvl: 1 });
  put(s, 8, 9, 'mountain');
  const e = computeEconomy(s, T0);
  assert.equal(e.tiles[idx(3, 3)].active, false);
  assert.equal(e.tiles[idx(3, 3)].out.gold, 0);
  assert.equal(e.tiles[idx(8, 8)].active, true);
  assert.ok(e.tiles[idx(8, 8)].out.gold > 0);
});

test('economia: falta de trabalhadores reduz produção proporcionalmente', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 5, 5, 'grass', { id: 'serraria', lvl: 1 });
  s.pop = 2;
  const full = computeEconomy(s, T0).rates.wood;
  s.pop = 1;
  const half = computeEconomy(s, T0).rates.wood;
  assert.ok(Math.abs(half - full / 2) < 1e-9);
});

test('economia: mercados param quando a comida acaba', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 5, 5, 'grass', { id: 'mercado', lvl: 1 });
  s.pop = 2;
  s.res.food = 100;
  const withFood = computeEconomy(s, T0);
  s.res.food = 0;
  const noFood = computeEconomy(s, T0);
  assert.ok(withFood.tiles[idx(5, 5)].out.gold > 0);
  assert.equal(noFood.tiles[idx(5, 5)].out.gold, 0);
});

test('custos: escalam 1.12x por cópia e 2.5x por nível (máx. 10)', () => {
  const g = freshGame();
  const s = g.state;
  const mods = { ...collectModifiers(s, T0), cost: 0 };
  const c1 = buildCost(s, 'casa', mods).gold; // já existe 1 casa
  assert.equal(c1, Math.ceil(25 * 1.12));
  assert.equal(upgradeCost('casa', 1, mods).gold, Math.ceil(25 * 2.5));
  assert.ok(upgradeCost('casa', 9, mods));
  assert.equal(upgradeCost('casa', 10, mods), null);
  assert.equal(upgradeCost('jardim', 1, mods), null, 'decoração não sobe de nível');
});

test('ações: construir, melhorar, mover, demolir, limpar', () => {
  const g = freshGame();
  const s = g.state;
  Object.assign(s.res, { gold: 1e6, wood: 1e6, stone: 1e6 });
  assert.equal(g.build('serraria', 5, 5).ok, false, 'tile ocupado');
  assert.equal(g.build('casa', 0, 0).ok, false, 'terra bloqueada');
  put(s, 4, 4, 'grass');
  put(s, 7, 7, 'grass');
  assert.ok(g.build('serraria', 4, 4).ok);
  assert.ok(g.upgrade(4, 4).ok);
  assert.equal(s.grid.tiles[idx(4, 4)].b.lvl, 2);
  assert.ok(g.move(4, 4, 7, 7).ok);
  assert.equal(s.grid.tiles[idx(4, 4)].b, null);
  assert.equal(s.grid.tiles[idx(7, 7)].b.id, 'serraria');
  const goldBefore = s.res.gold;
  assert.ok(g.sell(7, 7).ok);
  assert.ok(s.res.gold > goldBefore, 'demolir devolve recursos');
  put(s, 4, 4, 'forest');
  const wood = s.res.wood;
  assert.ok(g.clear(4, 4).ok);
  assert.equal(s.grid.tiles[idx(4, 4)].t, 'grass');
  assert.equal(s.res.wood, wood + 40);
});

test('ações: recursos insuficientes não alteram o estado', () => {
  const g = freshGame();
  const s = g.state;
  s.res.gold = 0;
  put(s, 4, 4, 'grass');
  const before = JSON.stringify(s.grid);
  const r = g.build('casa', 4, 4);
  assert.equal(r.ok, false);
  assert.equal(JSON.stringify(s.grid), before);
});

test('tick: recursos crescem, respeitam o limite e não ficam negativos', () => {
  const g = freshGame();
  const s = g.state;
  let now = T0;
  for (let i = 0; i < 120; i++) { now += 1000; g.tick(now); }
  assert.ok(s.res.gold > 100);
  assert.ok(s.pop > 1);
  s.res.gold = 999999;
  now += 1000; g.tick(now);
  assert.equal(s.res.gold, 999999, 'acima do limite (presentes) não é cortado');
  s.res.gold = 990;
  for (let i = 0; i < 100; i++) { now += 1000; g.tick(now); }
  assert.ok(s.res.gold <= g.econ.caps.gold);
});

test('invasões: vitória dá saque e sobe nível; derrota tira 5% (novato) e depois 15%', () => {
  const g = freshGame();
  const s = g.state;
  s.res.gold = 1000;
  g.econ = computeEconomy(s, T0);
  g.econ.defense = 0;
  g.econ.gross.gold = 1000; // produção alta: o teto de saque (2 min) não interfere
  const lose = g.resolveRaid(T0);
  assert.equal(lose.win, false);
  assert.equal(s.res.gold, 950, 'proteção de novato: perde só 5%');
  s.stats.raidsLost = 5;
  s.res.gold = 1000;
  g.resolveRaid(T0);
  assert.equal(s.res.gold, 850, 'depois perde 15%');
  g.econ.gross.gold = 1; // produção baixa: saque limitado a max(50, 2 min de produção)
  s.res.gold = 100000;
  g.resolveRaid(T0);
  assert.equal(s.res.gold, 100000 - 120, 'teto de saque protege a poupança');
  g.econ.defense = 1e9;
  const win = g.resolveRaid(T0);
  assert.equal(win.win, true);
  assert.ok(win.loot > 0);
  assert.equal(s.raid.level, 1, 'derrotas baixam o nível (mín. 0), vitória sobe');
  assert.ok(s.res.gems >= 1);
});

test('offline: simula com eficiência reduzida e limite de horas', () => {
  const g = freshGame();
  const s = g.state;
  s.pop = 4;
  const sum = g.catchUp(T0 + 10 * 3600 * 1000);
  assert.ok(sum.capped, 'passou do limite de 4h');
  assert.equal(sum.simulated, 4 * 3600);
  assert.equal(sum.efficiency, 0.6);
  assert.ok(sum.gains.gold > 0);
  assert.ok(s.raid.nextAt > T0 + 10 * 3600 * 1000, 'sem invasão imediata ao voltar');
});

test('heróis: duplicatas viram estrelas; no máximo viram gemas', () => {
  const s = createState({ seed: 1, now: T0 });
  const h = HERO_BY_ID.guarda;
  assert.equal(addHero(s, h).isNew, true);
  for (let i = 2; i <= 5; i++) assert.equal(addHero(s, h).stars, i);
  const r = addHero(s, h);
  assert.equal(r.gemsRefund, 2);
  assert.equal(s.res.gems, 2);
});

test('heróis: conselho aplica bônus; expedição exige sair do conselho', () => {
  const g = freshGame();
  const s = g.state;
  s.heroes.owned.lavradora = { stars: 1, expedition: null };
  const before = computeEconomy(s, T0).gross.food;
  assert.ok(g.toggleCouncil('lavradora').ok);
  const after = computeEconomy(s, T0).gross.food;
  assert.ok(Math.abs(after / before - 1.15) < 1e-9, 'Marta dá +15% de comida');
  assert.equal(g.startExpedition('lavradora', 'curta').ok, false);
  g.toggleCouncil('lavradora');
  assert.ok(g.startExpedition('lavradora', 'curta').ok);
  assert.equal(g.collectExpedition('lavradora').ok, false, 'ainda em andamento');
  g.now = T0 + 61000;
  const r = g.collectExpedition('lavradora');
  assert.ok(r.ok);
  assert.ok(r.reward.gold >= 30);
});

test('prestígio: ascensão mantém identidade e zera o reino', () => {
  const g = freshGame();
  const s = g.state;
  s.stats.runGold = 5e6;
  s.res.gems = 33;
  s.heroes.owned.rainha = { stars: 2, expedition: null };
  s.kingdom.name = 'Teste';
  assert.ok(g.crownsOnAscend() >= 2);
  const r = g.ascend();
  assert.ok(r.ok);
  const n = g.state;
  assert.notEqual(n, s);
  assert.equal(n.res.gems, 33);
  assert.equal(n.res.crowns, r.crowns);
  assert.equal(n.kingdom.name, 'Teste');
  assert.equal(n.heroes.owned.rainha.stars, 2);
  assert.equal(n.stats.runGold, 0);
  assert.equal(n.stats.ascensions, 1);
  assert.ok(g.buyTalent('fartura').ok);
  assert.equal(n.legacy.fartura, 1);
});

test('talentos de início valem na próxima rodada', () => {
  const s = createState({ seed: 3, now: T0, carry: { legacy: { heranca: 2, terras: 1 } } });
  assert.equal(s.res.gold, 100 + 1000);
  assert.equal(s.grid.ring, 3);
});

test('temporadas: calculadas pelo relógio, temas em rotação', () => {
  const a = seasonInfo(SEASON_EPOCH);
  assert.equal(a.number, 1);
  assert.equal(a.theme.id, 'fundacao');
  const b = seasonInfo(SEASON_EPOCH + 28 * 86400000);
  assert.equal(b.number, 2);
  assert.equal(b.theme.id, 'guerra');
  assert.equal(seasonInfo(SEASON_EPOCH + 4 * 28 * 86400000).theme.id, 'fundacao');
  assert.equal(tierOf(0), 0);
  assert.equal(tierOf(300), 1);
  assert.equal(tierOf(1e9), 30);
});

test('missões diárias: determinísticas por data e sem repetição', () => {
  const a = dailyMissions('2026-10-05');
  const b = dailyMissions('2026-10-05');
  assert.deepEqual(a, b);
  assert.equal(new Set(a.map((m) => m.id)).size, 3);
});

test('passe: só resgata níveis alcançados, uma vez', () => {
  const g = freshGame();
  assert.equal(g.claimTier(1).ok, false);
  g.addXp(600);
  assert.ok(g.claimTier(1).ok);
  assert.equal(g.claimTier(1).ok, false);
  assert.ok(g.claimTier(2).ok);
  assert.equal(g.claimTier(3).ok, false);
});

test('recompensa diária: sequência cresce em dias seguidos e reinicia ao pular', () => {
  const g = freshGame();
  assert.ok(g.claimDaily().ok);
  assert.equal(g.claimDaily().ok, false);
  g.now += 86400000;
  assert.ok(g.claimDaily().ok);
  assert.equal(g.state.daily.streak, 2);
  g.now += 3 * 86400000;
  assert.ok(g.claimDaily().ok);
  assert.equal(g.state.daily.streak, 1);
});

test('social: código do reino ida e volta', () => {
  const g = freshGame();
  g.state.kingdom.name = 'Vale <script>';
  const code = encodeKingdom(g.state, 123);
  const k = decodeKingdom(code);
  assert.equal(k.name, 'Vale <script>');
  assert.equal(k.power, 123);
  assert.deepEqual(k.grid.tiles, g.state.grid.tiles);
  assert.throws(() => decodeKingdom('lixo'));
  g.state.grid.tiles[idx(5, 5)].b.lvl = 10;
  assert.equal(decodeKingdom(encodeKingdom(g.state, 1)).grid.tiles[idx(5, 5)].b.lvl, 10, 'nível de 2 dígitos');
});

test('social: rivais determinísticos e ranking inclui o jogador', () => {
  const r1 = generateRivals(5, T0, T0);
  const r2 = generateRivals(5, T0, T0);
  assert.deepEqual(r1, r2);
  assert.equal(r1.length, 9);
  const later = generateRivals(5, T0 + 48 * 3600e3, T0);
  assert.ok(later[3].power > r1[3].power, 'rivais crescem com o tempo');
  assert.equal(rivalGrid(r1[4]).tiles.length, 144);
  const g = freshGame();
  assert.ok(g.rivals().some((r) => r.me));
});

test('save: serializa, importa e migra', () => {
  const g = freshGame();
  g.state.res.gold = 4242;
  const back = deserialize(serialize(g.state));
  assert.equal(back.res.gold, 4242);
  const imp = importSave(exportSave(g.state));
  assert.equal(imp.res.gold, 4242);
  const partial = JSON.parse(serialize(g.state));
  delete partial.settings;
  delete partial.stats.chests;
  const migrated = deserialize(JSON.stringify(partial));
  assert.equal(migrated.settings.sound, true);
  assert.equal(migrated.stats.chests, 0);
  assert.throws(() => deserialize('{"foo":1}'));
});

test('formatação de números e tempo', () => {
  assert.equal(fmt(999), '999');
  assert.equal(fmt(1500), '1.5K');
  assert.equal(fmt(2.5e9), '2.5B');
  assert.equal(fmtTime(65), '1m 05s');
  assert.equal(fmtTime(3700), '1h 1m');
});
