// Testes do motor (sem navegador). Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createState, serialize, deserialize, SAVE_VERSION, SAVE_KEY } from '../src/core/state.js';
import { encodeSave, decodeSave, loadSave, writeSave, exportCode, importCode, checksum, CORRUPT_KEY, BACKUP_INTERVAL, listBackups } from '../src/core/storage.js';
import { defaultConfig, normalizeConfig, actionForKey } from '../src/core/config.js';
import { dirWeight, wallFacing } from '../src/core/economy.js';
import { Game } from '../src/core/game.js';
import { computeEconomy, adjacencyAt, buildCost, upgradeCost, collectModifiers } from '../src/core/economy.js';
import { generateMap, ringOf, isUnlocked, idx, wallMask, GRID_W, GRID_H } from '../src/core/map.js';
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

test('economia: fazendas recebem trabalhadores primeiro e o reino sai da fome', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 5, 5, 'grass', { id: 'fazenda', lvl: 1 });
  for (let x = 2; x <= 9; x++) put(s, x, 8, 'forest');
  for (let x = 2; x <= 9; x++) put(s, x, 7, 'grass', { id: 'serraria', lvl: 1 });
  s.pop = 2;
  const e = computeEconomy(s, T0);
  assert.equal(e.tiles[idx(5, 5)].staff, 1);
  assert.equal(e.tiles[idx(3, 7)].staff, 0);
  // Fome extrema: 1 morador, estoque zerado. A comida precisa voltar a subir.
  s.pop = 1;
  s.res.food = 0;
  assert.ok(computeEconomy(s, T0).rates.food > 0);
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
  g.econ.defense = 0;
  g.econ.gross.gold = 1000;
  g.resolveRaid(T0);
  assert.equal(s.res.gold, 850, 'depois perde 15%');
  g.econ.defense = 0;
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

test('save: envelope com checksum, exportar/importar', () => {
  const g = freshGame();
  g.state.res.gold = 4242;
  const back = decodeSave(encodeSave(g.state)).state;
  assert.equal(back.res.gold, 4242);
  assert.equal(importCode(exportCode(g.state)).state.res.gold, 4242);
  const env = JSON.parse(encodeSave(g.state));
  assert.equal(env.v, SAVE_VERSION);
  assert.equal(env.sum, checksum(env.data));
  env.data = env.data.replace('4242', '4243');
  assert.throws(() => decodeSave(JSON.stringify(env)), /Checksum/);
  assert.throws(() => decodeSave('{"foo":1}'));
});

test('save: migração v1 -> v2 (fonte vira fogueira, abas abertas, configurações antigas)', () => {
  const g = freshGame();
  const v1 = JSON.parse(serialize(g.state));
  v1.version = 1;
  v1.grid.tiles[idx(4, 4)] = { t: 'grass', b: { id: 'fonte', lvl: 1 } };
  delete v1.raid.dir;
  delete v1.unlocks;
  v1.settings = { sound: false, particles: true };
  delete v1.stats.chests;
  const { state, legacySettings } = decodeSave(JSON.stringify(v1));
  assert.equal(state.version, 2);
  assert.equal(state.grid.tiles[idx(4, 4)].b.id, 'fogueira');
  assert.equal(state.raid.dir, 'n');
  assert.equal(state.unlocks.tabs.length, 6, 'jogador antigo não perde abas');
  assert.equal(state.stats.chests, 0);
  assert.equal(state.settings, undefined);
  const cfg = normalizeConfig(null, legacySettings);
  assert.equal(cfg.sfxVolume, 0, 'som desligado no v1 vira volume 0');
  // código de exportação antigo (base64 do estado puro) continua importável
  const oldCode = btoa(unescape(encodeURIComponent(JSON.stringify(v1))));
  assert.equal(importCode(oldCode).state.grid.tiles[idx(4, 4)].b.id, 'fogueira');
  assert.throws(() => decodeSave(JSON.stringify({ ...v1, version: 99 })), /mais nova/);
});

test('save: backups em rodízio e recuperação de save corrompido', () => {
  const mem = new Map();
  const store = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) };
  const g = freshGame();
  for (let i = 0; i < 4; i++) {
    g.state.res.gold = 1000 + i;
    g.state.lastTick = T0 + i * BACKUP_INTERVAL;
    writeSave(store, g.state, T0 + i * BACKUP_INTERVAL);
  }
  assert.equal(listBackups(store).length, 3, 'só 3 slots');
  store.setItem(SAVE_KEY, '{"format":"reino-de-bolso","v":2,"sum":"00000000","data":"{}"}');
  const loaded = loadSave(store);
  assert.equal(loaded.recovered, true);
  assert.equal(loaded.state.res.gold, 1003, 'backup mais recente');
  assert.ok(store.getItem(CORRUPT_KEY), 'save ruim guardado à parte');
  assert.equal(loadSave({ getItem: () => null, setItem() {}, removeItem() {} }).state, null);
});

test('config: padrões, limites e atalhos', () => {
  const c = normalizeConfig({ musicVolume: 7, fontScale: 0.1, keys: { upgrade: 'J' } });
  assert.equal(c.musicVolume, 1);
  assert.equal(c.fontScale, 0.85);
  assert.equal(c.keys.upgrade, 'j');
  assert.equal(actionForKey(c, 'J'), 'upgrade');
  assert.equal(actionForKey(defaultConfig(), 'Escape'), 'menu');
});

test('formatação de números e tempo', () => {
  assert.equal(fmt(999), '999');
  assert.equal(fmt(1500), '1,5K');
  assert.equal(fmt(2.5e9), '2,5B');
  assert.equal(fmt(0.25), '0,3');
  assert.equal(fmtTime(65), '1m 05s');
  assert.equal(fmtTime(3700), '1h 1m');
});

test('social: visitar o mesmo reino várias vezes no dia conta uma vez só', () => {
  const g = freshGame();
  g.state.season.missions = { day: 'x', list: [{ id: 'visit', track: 'visit', target: 3, xp: 40, progress: 0, claimed: false }] };
  assert.equal(g.recordVisit('r1'), true);
  assert.equal(g.recordVisit('r1'), false);
  assert.equal(g.recordVisit('r1'), false);
  assert.equal(g.state.season.missions.list[0].progress, 1);
  g.greetRival('r1');
  assert.equal(g.state.stats.visits, 1, 'saudar o mesmo reino no mesmo dia não conta de novo');
});

test('offline: ausência curta (< 1 min) não some com o baú', () => {
  const g = freshGame();
  g.state.chest = { x: 4, y: 4, expiresAt: T0 + 100000 };
  g.catchUp(T0 + 40000);
  assert.ok(g.state.chest, 'baú continua');
});

test('hordas: a defesa pesa mais do lado de onde a horda vem', () => {
  assert.equal(dirWeight('n', 5, 0), 1);
  assert.equal(dirWeight('n', 5, GRID_H - 1), 0.5);
  assert.equal(dirWeight('e', GRID_W - 1, 3), 1);
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  s.pop = 50;
  put(s, 5, 0, 'grass', { id: 'torre', lvl: 1 });
  s.raid.dir = 'n';
  const north = computeEconomy(s, T0).defense;
  s.raid.dir = 's';
  const south = computeEconomy(s, T0).defense;
  assert.ok(north > south * 1.9, 'torre no norte defende o dobro contra horda do norte');
  const r = (() => { g.econ = computeEconomy(s, T0); return g.resolveRaid(T0); })();
  assert.ok(['n', 's', 'e', 'w'].includes(s.raid.dir), 'próxima horda já tem direção');
  assert.equal(r.dir, 's');
});

test('muralhas: se ligam sozinhas e de lado para a horda contam metade', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  s.pop = 50;
  // Linha norte-sul de três muralhas, com uma torre a leste da do meio.
  for (const y of [4, 5, 6]) put(s, 5, y, 'grass', { id: 'muralha', lvl: 1 });
  put(s, 6, 5, 'grass', { id: 'torre', lvl: 1 });
  assert.equal(wallMask(s.grid, 5, 4), 4, 'ponta de cima liga só para o sul');
  assert.equal(wallMask(s.grid, 5, 5), 1 | 2 | 4, 'a do meio liga norte, sul e a torre a leste');
  assert.equal(wallMask(s.grid, 5, 6), 1);
  assert.equal(wallFacing(0, 'n'), 1, 'sozinha conta inteira');
  assert.equal(wallFacing(5, 'n'), 0.5, 'norte-sul fica de lado para horda do norte');
  assert.equal(wallFacing(5, 'e'), 1, 'norte-sul fica de frente para horda do leste');
  assert.equal(wallFacing(3, 's'), 1, 'canto tem os dois lados');
  // A linha norte-sul defende mais contra o oeste que contra o norte, mesmo estando no centro.
  s.grid.tiles[idx(6, 5)].b = null;
  s.raid.dir = 'n';
  const n = computeEconomy(s, T0).defense;
  s.raid.dir = 'w';
  const w = computeEconomy(s, T0).defense;
  assert.ok(w > n * 1.5);
});

test('core loop: melhorar ao máximo e melhorar todos do tipo', () => {
  const g = freshGame();
  const s = g.state;
  Object.assign(s.res, { gold: 5000, wood: 5000, stone: 5000 });
  put(s, 4, 4, 'grass', { id: 'casa', lvl: 1 });
  put(s, 7, 7, 'grass', { id: 'casa', lvl: 3 });
  g.econ = computeEconomy(s, T0);
  const n = g.upgradeAll('casa');
  assert.ok(n >= 3);
  const lv = s.grid.tiles.filter((t) => t.b?.id === 'casa').map((t) => t.b.lvl);
  assert.ok(Math.max(...lv) - Math.min(...lv) <= 1, 'nivela por baixo primeiro');
  s.res.gold = 1e9; s.res.wood = 1e9;
  assert.ok(g.upgradeMax(4, 4) > 0);
  assert.equal(s.grid.tiles[idx(4, 4)].b.lvl, 10);
});

test('core loop: prévia de ganho por segundo antes de construir/melhorar', () => {
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 5, 4, 'forest');
  s.pop = 10;
  put(s, 6, 6, 'grass', { id: 'casa', lvl: 3 });
  g.econ = computeEconomy(s, T0);
  const d = g.previewBuild('serraria', 5, 5);
  assert.ok(d.wood > 0);
  assert.equal(s.grid.tiles[idx(5, 5)].b, null, 'prévia não altera o mapa');
  const up = g.previewUpgrade(6, 6);
  assert.ok(up.popCap > 0);
  assert.equal(s.grid.tiles[idx(6, 6)].b.lvl, 3);
});

test('core loop: abas abrem aos poucos e aviso de quando ascender', () => {
  const g = freshGame();
  const s = g.state;
  const opened = [];
  g.on('unlock', (u) => opened.push(u.tab));
  assert.equal(g.isTabUnlocked('herois'), false);
  s.tutorial.step = 2;
  g.checkUnlocks();
  assert.deepEqual(opened, ['herois']);
  s.stats.runGold = 4e6;
  g.checkUnlocks();
  assert.ok(g.isTabUnlocked('legado'));
  const adv = g.ascendAdvice();
  assert.equal(adv.crowns, 2);
  assert.equal(adv.recommended, true);
  s.res.crowns = 5;
  assert.equal(g.ascendAdvice().recommended, false, 'não dobra as coroas que já tem');
});

test('aba oculta produz a 100% (não a eficiência offline)', () => {
  const g = freshGame();
  const s = g.state;
  s.pop = 4;
  const evs = [];
  g.on('background', (x) => evs.push(x)).on('offline', () => evs.push('offline'));
  g.tick(T0 + 10 * 60 * 1000, { background: true });
  assert.equal(evs.length, 1);
  assert.equal(evs[0].efficiency, 1);
});

test('recompensa diária: "ontem" pela data, mesmo na troca de horário de verão', () => {
  const g = freshGame();
  g.now = new Date(2026, 9, 17, 23, 30).getTime();
  g.claimDaily();
  g.now = new Date(2026, 9, 18, 0, 30).getTime();
  assert.ok(g.claimDaily().ok);
  assert.equal(g.state.daily.streak, 2);
});

test('desbloqueio: progresso conta o histórico e não volta a bloquear ao demolir', () => {
  const g = freshGame();
  assert.equal(g.unlockProgress(), 2); // casa + fazenda iniciais
  assert.equal(g.isAvailable('pedreira'), false); // libera com 3
  g.state.stats.built = 1;
  assert.equal(g.unlockProgress(), 3);
  assert.equal(g.isAvailable('pedreira'), true);
  for (const t of g.state.grid.tiles) t.b = null; // demolir tudo não tira o que já foi liberado
  assert.equal(g.isAvailable('pedreira'), true);
});

test('modo silencioso: ações em lote não disparam um aviso por item', () => {
  const g = freshGame();
  const toasts = [];
  g.on('toast', (t) => toasts.push(t));
  g.state.season.xp = 10000;
  g.quiet = true;
  assert.equal(g.claimTier(1).ok, true);
  assert.equal(g.claimTier(2).ok, true);
  g.quiet = false;
  assert.equal(toasts.length, 0);
  g.claimTier(3);
  assert.equal(toasts.length, 1);
});

// Monta um jogo com grama livre em (3, 3) e dinheiro de sobra.
function undoGame() {
  const g = freshGame();
  put(g.state, 3, 3, 'grass');
  Object.assign(g.state.res, { gold: 1000, wood: 1000, stone: 1000 });
  return g;
}

test('desfazer: devolve 100% do custo e volta mapa, estatística, missão e XP', () => {
  const g = undoGame();
  const s = g.state;
  s.season.missions = { day: 'x', list: [{ id: 'build', track: 'build', target: 5, xp: 50, progress: 2, claimed: false }] };
  const before = { res: { ...s.res }, built: s.stats.built, xp: s.season.xp };
  assert.equal(g.build('casa', 3, 3).ok, true);
  assert.ok(s.season.xp > before.xp);
  assert.equal(g.canUndo(), true);
  assert.equal(g.undoBuild().ok, true);
  assert.equal(g.tileAt(3, 3).b, null);
  assert.deepEqual(s.res, before.res);
  assert.equal(s.stats.built, before.built);
  assert.equal(s.season.xp, before.xp);
  assert.equal(s.season.missions.list[0].progress, 2);
  assert.equal(g.undoBuild().ok, false); // só uma vez
});

test('desfazer: expira em 5 s e some se o prédio foi mexido ou um prêmio foi resgatado', () => {
  let g = undoGame();
  g.build('casa', 3, 3);
  assert.equal(g.canUndo(T0 + 5001), false);

  g = undoGame();
  g.build('casa', 3, 3);
  g.upgrade(3, 3);
  assert.equal(g.canUndo(), false);

  g = undoGame();
  g.state.season.missions = { day: 'x', list: [{ id: 'build', track: 'build', target: 1, xp: 50, progress: 0, claimed: false }] };
  g.build('casa', 3, 3);
  assert.equal(g.claimMission(0).ok, true); // a obra completou a missão e o XP já foi pago
  assert.equal(g.canUndo(), false);
  assert.equal(g.undoBuild().ok, false);
  assert.ok(g.tileAt(3, 3).b);
});

test('desfazer: conquista e passo do tutorial disparados pela obra voltam junto', () => {
  const g = undoGame();
  const s = g.state;
  s.tutorial.step = 0; // passo 1 pede uma serraria
  put(s, 2, 3, 'forest');
  const gems = s.res.gems;
  const gold = s.res.gold;
  g.build('serraria', 3, 3);
  g.checkTutorial();
  g.checkAchievements();
  assert.equal(s.tutorial.step, 1);
  assert.ok(Object.keys(s.achievements).length >= 1);
  assert.equal(g.canUndo(), true);
  assert.equal(g.undoBuild().ok, true);
  assert.equal(s.tutorial.step, 0);
  assert.equal(Object.keys(s.achievements).length, 0);
  assert.equal(s.res.gems, gems);
  assert.equal(s.res.gold, gold);
});

test('desfazer: prêmio automático já gasto fecha a janela', () => {
  const g = undoGame();
  const s = g.state;
  s.res.gems = 0;
  g.build('casa', 3, 3);
  g.checkAchievements(); // "primeira construção" dá gemas
  assert.ok(s.res.gems > 0);
  s.res.gems = 0; // gastou
  assert.equal(g.canUndo(), false);
});

test('vida da vila: vagas ocupadas como no motor (comida primeiro) e sobra dorme na rua', async () => {
  const { VillageLife } = await import('../src/ui/villagers.js');
  const g = freshGame();
  const s = g.state;
  clearArea(s);
  put(s, 4, 4, 'grass', { id: 'casa', lvl: 1 });
  put(s, 5, 4, 'grass', { id: 'serraria', lvl: 1 });
  put(s, 6, 4, 'grass', { id: 'fazenda', lvl: 1 });
  s.pop = 3; // fazenda (2 vagas) é ocupada primeiro, sobra 1 para a serraria
  g.econ = computeEconomy(s, T0);
  const life = new VillageLife();
  life.sync(g);
  const jobs = [...life.people.values()].map((p) => p.job ?? p.kind).sort();
  assert.deepEqual(jobs, ['fazenda', 'fazenda', 'serraria']);
  s.pop = 7; // 4 vagas: 3 dormem
  g.econ = computeEconomy(s, T0);
  life.sync(g);
  assert.equal([...life.people.values()].filter((p) => p.kind === 'sleep').length, 3);
  // rotina do lavrador: trabalha na fazenda e leva comida a algum lugar
  const farmer = [...life.people.values()].find((p) => p.job === 'fazenda');
  life.plan(farmer, g);
  assert.equal(farmer.stops[0].cell, idx(6, 4));
  assert.equal(farmer.stops[0].tool, 'clear');
  assert.equal(farmer.stops[1].carry, 'food');
});

test('Ascensão: resumo só da rodada, histórico e recordes atravessam a Ascensão', () => {
  const g = freshGame();
  const s = g.state;
  s.stats.built = 5; s.stats.raidsWon = 2; // vida toda antes desta rodada
  s.runBase = { ...s.stats };
  s.stats.built = 12; s.stats.raidsWon = 5;
  s.stats.runGold = 4e6; s.stats.totalGold = 5e6;
  g.now = T0 + 3600e3;
  const r1 = g.ascend();
  assert.equal(r1.ok, true);
  const sum = r1.summary;
  assert.equal(sum.built, 7);
  assert.equal(sum.raidsWon, 3);
  assert.equal(sum.gold, 4e6);
  assert.equal(sum.duration, 3600);
  assert.equal(sum.n, 1);
  assert.deepEqual(sum.newRecords, []); // 1ª rodada: sem "recorde"
  const s2 = g.state;
  assert.equal(s2.runs.length, 1);
  assert.equal(s2.records.gold, 4e6);
  assert.equal(s2.runBase.built, s2.stats.built); // nova foto no início da rodada
  // 2ª rodada maior: recorde de ouro
  s2.stats.runGold = 9e6;
  const r2 = g.ascend();
  assert.ok(r2.summary.newRecords.includes('gold'));
  assert.equal(g.state.runs.length, 2);
  assert.equal(g.state.runs[0].n, 2);
});

test('Ascensão: save antigo sem foto da rodada não inventa números', () => {
  const g = freshGame();
  g.state.runBase = null; // como um save de antes da 0.6.0
  g.state.stats.runGold = 4e6;
  const { summary } = g.ascend();
  assert.equal(summary.built, null);
  assert.equal(summary.gold, 4e6);
});

test('save: migração mantém runs/records e marca runBase ausente como null', () => {
  const g = freshGame();
  const data = JSON.parse(serialize(g.state));
  delete data.runBase; delete data.runs; delete data.records;
  const st = deserialize(JSON.stringify(data));
  assert.equal(st.runBase, null);
  assert.deepEqual(st.runs, []);
  assert.deepEqual(st.records, {});
  const st2 = deserialize(serialize(g.state));
  assert.ok(st2.runBase);
});
