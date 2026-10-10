// Gera tests/fixtures.json rodando o jogo web (src/) com aleatoriedade fixa.
// O teste do porte (tests/run.luau) roda o mesmo roteiro no Luau e compara os números.
// Uso: TZ=America/Sao_Paulo node roblox/tools/fixtures.mjs
import { writeFileSync } from 'node:fs';
import { mulberry32 } from '../../src/core/rng.js';
import { generateMap } from '../../src/core/map.js';
import { createUnder } from '../../src/core/underground.js';
import { dailyMissions } from '../../src/core/season.js';
import { generateRivals } from '../../src/core/social.js';
import { createState } from '../../src/core/state.js';
import { Game } from '../../src/core/game.js';
import { fmt, fmtRate, fmtPct, fmtTime } from '../../src/core/format.js';
import { dayKey } from '../../src/core/rng.js';
import * as config from '../../src/core/config.js';
import { roteiro, cenarios } from './roteiro.mjs';

const T0 = 1791385200000; // 2026-10-07 15:00 UTC

const out = { maps: {}, under: {}, missions: {}, rivals: {}, fmt: {}, sessions: {} };

for (const seed of [1, 42, 4242, 123456, 987654321]) {
  out.maps[seed] = generateMap(seed).tiles.map((t) => t.t[0] + (t.b ? t.b.id[0] : '')).join('');
  out.under[seed] = createUnder(seed).levels.map((lv) => lv.tiles.map((t) => t.t[0]).join(''));
}
for (const day of ['2026-10-07', '2026-12-25', '2027-01-01']) out.missions[day] = dailyMissions(day, 3.7);
out.rivals = generateRivals(4242, T0 + 7200000, T0).map((r) => ({ name: r.name, ruler: r.ruler, power: r.power, banner: r.banner }));
for (const n of [0, 0.25, 7.5, 999, 1000, 1534.2, 98765, 1.5e7, 2.5e12, -42.5]) out.fmt[n] = fmt(n);
out.fmtTime = [5, 75, 3725, 90061].map(fmtTime);
// Casos difíceis do toFixed (empates exatos e doubles logo abaixo do empate) e números grandes.
out.fmtExtra = [0.15, 0.25, 0.35, 1.45, 2.5, 9.95, 9.96, 0.95, 6.05, 72550, 98945, 99950, 1.25e6, -0.15, -2.25, 1e21, 1e40, 0.1 + 0.2].map((n) => [n, fmt(n), fmt(n, 2), fmtRate(n), fmtPct(n / 7), fmtTime(n * 37)]);

for (const [name, seed] of [['a', 4242], ['b', 77]]) {
  Math.random = mulberry32(seed * 3 + 1);
  const game = new Game(createState({ seed, now: T0 }), T0);
  const log = roteiro(game, T0, 3600);
  const s = game.state;
  // 5 horas fora: produção offline
  game.tick(T0 + 3600 * 1000 + 5 * 3600 * 1000);
  out.sessions[name] = {
    log,
    res: s.res, pop: s.pop, stats: s.stats, raid: { level: s.raid.level, dir: s.raid.dir },
    heroes: s.heroes, items: s.items, xp: s.season.xp, tutorial: s.tutorial,
    achievements: Object.keys(s.achievements).sort(), ring: s.grid.ring, unlocks: s.unlocks.tabs,
    grid: s.grid.tiles.map((t) => t.t[0] + (t.b ? t.b.id + t.b.lvl : '')).join(','),
    rates: game.econ.rates, defense: game.econ.defense, happiness: game.econ.happiness,
  };
}

// Novidades de 0.16 a 0.18 (hordas que quebram prédios, conquistas, loja, Opções...).
{
  Math.random = mulberry32(99);
  const game = new Game(createState({ seed: 4242, now: T0 }), T0);
  const log = cenarios(game, T0, { fmt, dayKey, config });
  const s = game.state;
  out.cenarios = {
    log,
    res: s.res, items: s.items, stats: s.stats, daily: s.daily,
    achievements: Object.keys(s.achievements).sort(), flags: Object.keys(s.flags).sort(),
    grid: s.grid.tiles.map((t) => t.t[0] + (t.b ? t.b.id + t.b.lvl + (t.b.dmg ? '!' : '') : '') + (t.ruin ? '#' + t.ruin : '')).join(','),
    rates: game.econ.rates, defense: game.econ.defense, prodAll: game.econ.mods.prodAll,
  };
}

writeFileSync(new URL('../tests/fixtures.json', import.meta.url), JSON.stringify(out, null, 1));
console.log('fixtures.json gerado');
