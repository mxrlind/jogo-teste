// Roteiro de jogo determinístico usado para comparar o jogo web com o porte Luau.
// tests/roteiro.luau é a mesma coisa em Luau: mudou um, mude o outro.
const ORDER = ['fazenda', 'casa', 'serraria', 'casa', 'pedreira', 'mercado', 'muralha', 'cais', 'torre', 'moinho', 'taverna', 'armazem', 'jardim', 'quartel'];

export function roteiro(game, T0, seconds) {
  const log = [];
  const rec = (t, what, r) => log.push(`${t}:${what}:${r.ok ? 'ok' : r.reason}`);
  const W = 12;
  let k = 0;
  for (let t = 1; t <= seconds; t++) {
    game.tick(T0 + t * 1000);
    const s = game.state;
    if (t % 3 === 0) {
      const id = ORDER[k % ORDER.length];
      let r = { ok: false, reason: 'sem lugar' };
      for (let i = 0; i < 144 && !r.ok; i++) {
        if (s.grid.tiles[i].b) continue;
        r = game.build(id, i % W, Math.floor(i / W));
      }
      rec(t, 'build-' + id, r);
      if (r.ok) k++;
    }
    if (t % 37 === 0) {
      const i = s.grid.tiles.findIndex((tile, j) => tile.t === 'forest' && game.build('casa', j % W, Math.floor(j / W)).reason?.startsWith('Limpe'));
      if (i >= 0) rec(t, 'clear', game.clear(i % W, Math.floor(i / W)));
    }
    if (t % 50 === 0) {
      rec(t, 'scroll', game.recruit('scroll'));
      rec(t, 'gold', game.recruit('gold'));
    }
    if (t % 41 === 0) {
      const i = s.grid.tiles.findIndex((tile) => tile.b);
      rec(t, 'upgrade', game.upgrade(i % W, Math.floor(i / W)));
    }
    if (t % 300 === 0) rec(t, 'expand', game.expand());
    if (t % 120 === 0) {
      const free = Object.keys(s.heroes.owned).sort().find((h) => !s.heroes.council.includes(h) && !s.heroes.owned[h].expedition);
      if (free) rec(t, 'exp-' + free, game.startExpedition(free, 'curta'));
      for (const h of Object.keys(s.heroes.owned).sort()) if (s.heroes.owned[h].expedition) rec(t, 'collect-' + h, game.collectExpedition(h));
    }
    if (s.chest && t % 7 === 0) rec(t, 'chest', game.openChest());
    if (t % 60 === 0) {
      for (let m = 0; m < 3; m++) rec(t, 'mission', game.claimMission(m));
      rec(t, 'tier', game.claimTier(1));
      rec(t, 'daily', game.claimDaily());
    }
    if (t === 1500) {
      s.res.wood += 300; s.res.stone += 300; s.res.gold += 3000;
      let r = { ok: false, reason: 'sem lugar' };
      for (let i = 0; i < 144 && !r.ok; i++) if (!s.grid.tiles[i].b) r = game.build('escadaria', i % W, Math.floor(i / W));
      rec(t, 'escadaria', r);
    }
    if (t > 1500 && t % 45 === 0 && s.under.reached >= 1) {
      let r = { ok: false, reason: 'nada' };
      for (let i = 0; i < 144 && !r.ok; i++) {
        const u = s.under.levels[0].tiles[i];
        if (u.s && (u.t === 'rock' || u.t === 'gold' || u.t === 'gem')) r = game.dig(1, i % W, Math.floor(i / W));
      }
      rec(t, 'dig', r);
      if (t % 90 === 0) {
        let q = { ok: false, reason: 'nada' };
        for (const id of ['garimpo', 'pedreira_funda', 'adega']) for (let i = 0; i < 144 && !q.ok; i++) q = game.buildRoom(1, i % W, Math.floor(i / W), id);
        rec(t, 'room', q);
      }
    }
    if (t === 900) {
      let r = { ok: false, reason: 'sem lugar' };
      for (let i = 0; i < 144 && !r.ok; i++) r = game.plant(i % W, Math.floor(i / W));
      rec(t, 'plant', r);
    }
  }
  return log;
}

// Cenários das novidades de 0.16 a 0.18 (hordas que quebram prédios, conserto, ruínas, conquistas,
// secretas, loja de gemas, pacote de volta, escudo da sequência, relógio voltando, Cais/Mina e Opções).
// tests/roteiro.luau tem a mesma função: mudou um, mude o outro.
// deps: { fmt, dayKey, config } (format.js, rng.js e config.js).
export function cenarios(game, T0, { fmt, dayKey, config }) {
  const log = [];
  const W = 12;
  const s = game.state;
  const rec = (what, r) => log.push(`${what}:${r.ok ? 'ok' : r.reason}`);
  const put = (what, v) => log.push(`${what}=${v}`);
  let now = T0;
  const tick = (sec) => { now += sec * 1000; game.tick(now); };
  let lastRaid = null;
  let offline = null;
  game.on('raid', (r) => { lastRaid = r; });
  game.on('offline', (r) => { offline = r; });
  const sortedKeys = (o) => Object.keys(o).sort().join(',');
  const fill = () => Object.assign(s.res, { gold: 20000, wood: 8000, stone: 8000, food: 2000 });
  const free = (i) => !s.grid.tiles[i].b && s.grid.tiles[i].t === 'grass';
  const firstFree = () => { for (let i = 0; i < 144; i++) if (free(i)) return i; return -1; };
  const tryAll = (id, want) => {
    for (let i = 0; i < 144; i++) {
      if (!free(i)) continue;
      const x = i % W;
      const y = Math.floor(i / W);
      if (want === 'fail') {
        if (game.missingNeighbor(id, x, y)) return [i, game.build(id, x, y)];
      } else {
        const r = game.build(id, x, y);
        if (r.ok) return [i, r];
      }
    }
    return [-1, { ok: false, reason: 'sem lugar' }];
  };
  const raidLog = (tag) => {
    const r = lastRaid;
    put(tag, `${r.win}|${r.strength}|${(r.damaged || []).map((d) => `${d.x},${d.y},${d.id}`).join(';')}|${(r.collapsed || []).map((d) => `${d.x},${d.y},${d.id}`).join(';')}`);
    if (r.lost) put(tag + '-saque', `${r.lost.gold}|${r.lost.food}|${r.lost.wood}|${r.lost.stone}`);
    put(tag + '-danificados', game.damagedCount());
  };

  s.stats.built = 20; // libera todos os prédios
  s.grid.ring = 5;
  s.res.gems = 200;
  fill();

  // ---- Cais e Mina só onde funcionam (0.16.1)
  let [i, r] = tryAll('cais', 'fail');
  rec(`cais-longe@${i}`, r);
  [i, r] = tryAll('mina', 'fail');
  rec(`mina-longe@${i}`, r);
  [i, r] = tryAll('cais', 'ok');
  rec(`cais@${i}`, r);
  if (i >= 0) {
    let j = -1;
    for (let k = 0; k < 144; k++) if (free(k) && game.missingNeighbor('cais', k % W, Math.floor(k / W))) { j = k; break; }
    if (j >= 0) rec(`mover-cais@${j}`, game.move(i % W, Math.floor(i / W), j % W, Math.floor(j / W)));
  }
  [i, r] = tryAll('mina', 'ok');
  rec(`mina@${i}`, r);
  for (const id of ['casa', 'fazenda', 'muralha', 'torre', 'serraria', 'casa', 'mercado', 'casa', 'fazenda', 'muralha', 'quartel', 'taverna']) {
    [i, r] = tryAll(id, 'ok');
    rec(`${id}@${i}`, r);
  }

  // ---- teimosia sem recursos (sombra "Insistente")
  s.res.gold = 0;
  i = firstFree();
  for (let k = 0; k < 3; k++) rec('sem-ouro', game.build('casa', i % W, Math.floor(i / W)));
  put('failBuild', s.stats.failBuild);
  fill();

  // ---- conquistas e o bônus de produção
  tick(1);
  put('conquistas', sortedKeys(s.achievements));
  put('prodAll', fmt(game.econ.mods.prodAll, 2));

  // ---- horda perdida quebra construções (0.16.0)
  s.stats.raidsLost = 2; // passa da proteção de novato
  s.raid.level = 12;
  s.raid.dir = 'n';
  s.raid.nextAt = now + 1000;
  tick(1);
  raidLog('horda1');
  const dmg = lastRaid.damaged[0];
  if (dmg) {
    const info = game.econ.tiles[dmg.y * W + dmg.x];
    put('danificado-info', `${info.damaged}|${info.active}|${info.workers}|${info.defense}`);
    rec('melhorar-danificado', game.upgrade(dmg.x, dmg.y));
    const before = { ...s.res };
    rec('consertar', game.repair(dmg.x, dmg.y));
    put('conserto-custou', `${before.gold - s.res.gold}|${before.wood - s.res.wood}|${before.stone - s.res.stone}`);
    rec('consertar-de-novo', game.repair(dmg.x, dmg.y));
  }
  Object.assign(s.res, { gold: 0, wood: 0, stone: 0 });
  let all = game.repairAll();
  put('consertar-tudo-sem-recursos', `${all.ok}|${all.count}|${all.left}|${all.reason}`);
  fill();

  // ---- segunda derrota: o que continuou quebrado vira ruína
  s.raid.level = 12;
  s.raid.dir = 'w';
  s.raid.nextAt = now + 1000;
  tick(1);
  raidLog('horda2');
  const ruins = [];
  s.grid.tiles.forEach((t, k) => { if (t.ruin) ruins.push(`${k}:${t.ruin}`); });
  put('ruinas', ruins.join(','));
  const ruinAt = s.grid.tiles.findIndex((t) => t.ruin && t.t === 'grass' && !t.b);
  if (ruinAt >= 0) {
    rec('construir-na-ruina', game.build('casa', ruinAt % W, Math.floor(ruinAt / W)));
    put('ruina-depois', s.grid.tiles[ruinAt].ruin ?? 'nenhuma');
  }

  // ---- terceira derrota seguida e depois uma vitória
  s.raid.level = 12;
  s.raid.dir = 's';
  s.raid.nextAt = now + 1000;
  tick(1);
  raidLog('horda3');
  put('lossStreak', s.stats.lossStreak);
  tick(3);
  all = game.repairAll();
  put('consertar-tudo', `${all.ok}|${all.count}|${all.left}`);
  for (let k = 0; k < 3; k++) rec('torre', tryAll('torre', 'ok')[1]);
  s.pop = 60; // gente para guarnecer as torres
  s.raid.level = 0;
  s.raid.dir = 'n';
  s.raid.nextAt = now + 1000;
  tick(1);
  raidLog('horda4');
  put('lossStreak-depois', s.stats.lossStreak);

  // ---- secretas
  let gems = s.res.gems;
  game.secret('konami');
  game.secret('konami');
  put('konami-gemas', s.res.gems - gems);
  rec('nome-1', game.setKingdomName('Outro Reino'));
  rec('nome-2', game.setKingdomName('Reino de Bolso'));
  [i, r] = [-1, { ok: false, reason: 'sem lugar' }];
  for (let k = 0; k < 144 && !r.ok; k++) { r = game.plant(k % W, Math.floor(k / W)); i = k; }
  rec(`plantar@${i}`, r);
  rec('arrancar-muda', game.clear(i % W, Math.floor(i / W)));
  s.stats.totalGold = Math.max(s.stats.totalGold, 5000);
  s.res.gold = 0;
  tick(3);
  fill();
  for (let k = 0; k < 10; k++) {
    rec('obra', tryAll('jardim', 'ok')[1]);
    rec('desfazer', game.undoBuild());
  }
  put('undos', s.stats.undos);
  rec('recrutar', game.recruit('scroll'));
  const hid = Object.keys(s.heroes.owned).sort()[0];
  if (hid) {
    rec('treinar', game.trainHero(hid));
    rec('acelerar-treino', game.speedUpTraining(hid));
  }
  put('trained', s.stats.trained);
  tick(3);
  put('flags', sortedKeys(s.flags));
  put('conquistas', sortedKeys(s.achievements));
  put('prodAll', fmt(game.econ.mods.prodAll, 2));
  const n = game.nextAchievement();
  put('proxima', n ? `${n.a.id}|${fmt(n.cur)}|${n.goal}|${fmt(n.ratio, 3)}` : 'nenhuma');

  // ---- relógio voltando (0.16.1)
  const play = s.stats.playTime;
  now -= 2 * 3600 * 1000;
  game.tick(now);
  put('relogio-voltou', s.lastTick === now);
  tick(1);
  put('jogou-depois', fmt(s.stats.playTime - play));
  put('viajante', !!s.achievements['viajante-do-tempo']);
  put('prodAll-sombra', fmt(game.econ.mods.prodAll, 2));

  // ---- loja de gemas (0.17.0)
  rec('loja-mudas-sem-muda', game.buyShop('mudas'));
  for (const id of ['ouro', 'madeira', 'pedra', 'comida', 'impulso', 'pergaminho']) {
    const before = { ...s.res, scrolls: s.items.scrolls, boost: s.boostUntil };
    rec('loja-' + id, game.buyShop(id));
    put('loja-' + id + '-deu', `${fmt(s.res.gold - before.gold)}|${fmt(s.res.wood - before.wood)}|${fmt(s.res.stone - before.stone)}|${fmt(s.res.food - before.food)}|${before.gems - s.res.gems}|${s.items.scrolls - before.scrolls}|${(s.boostUntil - Math.max(before.boost, now)) / 1000}`);
  }
  [i, r] = [-1, { ok: false, reason: 'sem lugar' }];
  for (let k = 0; k < 144 && !r.ok; k++) { r = game.plant(k % W, Math.floor(k / W)); i = k; }
  rec(`plantar@${i}`, r);
  rec('loja-mudas', game.buyShop('mudas'));
  put('muda-virou', s.grid.tiles[i].t);
  rec('loja-nada', game.buyShop('nada'));
  gems = s.res.gems;
  s.res.gems = 2;
  rec('loja-sem-gemas', game.buyShop('ouro'));
  s.res.gems = gems;
  rec('pacote', game.buyGemPack('saco'));
  rec('pacote-nada', game.buyGemPack('nada'));
  game.creditPurchasedGems(80);
  put('gemsBought', s.stats.gemsBought);

  // ---- escudo da sequência (0.17.0)
  s.daily = { lastDay: dayKey(now - 2 * 86400000), streak: 5, shieldWeek: null };
  let st = game.dailyStatus();
  put('escudo', `${st.shield}|${st.nextStreak}|${st.shieldReady}`);
  rec('diario-escudo', game.claimDaily());
  put('sequencia', `${s.daily.streak}|${s.daily.shieldWeek}`);
  s.daily.lastDay = dayKey(now - 2 * 86400000);
  st = game.dailyStatus();
  put('escudo-gasto', `${st.shield}|${st.nextStreak}|${st.shieldReady}`);

  // ---- pacote de volta, madrugada e 7 dias fora
  const welcome = () => { const w = offline?.welcome; return w ? `${w.gems}|${w.scroll}|${w.goldMinutes}|${w.days}` : 'nenhum'; };
  gems = s.res.gems;
  let scrolls = s.items.scrolls;
  now = T0 + 3 * 86400000 - 8 * 3600000; // sábado, 4h da manhã em Brasília
  game.tick(now);
  put('volta-1', `${welcome()}|${s.res.gems - gems}|${s.items.scrolls - scrolls}|${fmt(offline.gains.gold)}`);
  tick(3);
  put('madrugada', !!s.flags.nightOwl);
  rec('diario-sabado', game.claimDaily());
  put('sequencia-sabado', `${s.daily.streak}|${s.daily.shieldWeek}`);
  now += 8 * 86400000; // domingo seguinte, depois de 8 dias fora
  game.tick(now);
  put('volta-2', `${welcome()}|${!!s.achievements['eles-apostaram']}`);
  s.daily = { lastDay: dayKey(now - 2 * 86400000), streak: 3, shieldWeek: '2026-10-05' };
  st = game.dailyStatus();
  put('escudo-domingo', `${st.shield}|${st.nextStreak}|${st.shieldReady}`);
  rec('diario-domingo', game.claimDaily());
  put('sequencia-domingo', `${s.daily.streak}|${s.daily.shieldWeek}`);
  offline = null;
  now += 86400000; // segunda-feira: 1 dia fora não dá pacote
  game.tick(now);
  put('volta-3', welcome());
  st = game.dailyStatus();
  put('segunda', `${st.available}|${st.shield}|${st.nextStreak}|${st.shieldReady}`);

  // ---- Opções (0.18.0)
  const keys = (c) => config.KEY_ACTIONS.map((a) => c.keys[a.id]).join(',');
  const cfg = (c) => `${c.version}|${c.masterVolume}|${c.musicVolume}|${c.musicOn}|${c.sfxVolume}|${c.muteInBackground}|${c.batterySaver}|${c.confirmDemolish}|${c.particles}|${c.villagers}|${c.reduceMotion}|${c.fontScale}|${c.highContrast}|${keys(c)}`;
  const c1 = config.normalizeConfig(null, { sound: false, particles: false });
  put('config-legado', cfg(c1));
  const c2 = config.normalizeConfig({ masterVolume: '0.3', musicVolume: 2, sfxVolume: -1, fontScale: 3, muteInBackground: 'sim', batterySaver: true, confirmDemolish: false, highContrast: 1, keys: { menu: 'Q', up: '', down: 5 } }, { sound: false });
  put('config-bagunca', cfg(c2));
  const c3 = config.normalizeConfig({ masterVolume: 'abc', fontScale: true, musicVolume: '', sfxVolume: ' 0.25 ' });
  put('config-textos', cfg(c3));
  const c4 = config.normalizeConfig({ masterVolume: 0.5, musicVolume: 0.8, sfxVolume: 0.6, muteInBackground: false });
  for (const [tag, c] of [['c2', c2], ['c4', c4]]) {
    for (const hidden of [false, true]) {
      const v = config.effectiveVolumes(c, hidden);
      put(`volumes-${tag}-${hidden}`, `${v.music}|${v.sfx}`);
    }
  }
  put('restaurar', cfg(config.resetOptions(c2)));
  put('tecla', `${config.actionForKey(c2, 'Q') ?? 'nenhuma'}|${config.actionForKey(c2, 'x') ?? 'nenhuma'}|${config.keyLabel('arrowup')}|${config.keyLabel('q')}|${config.keyLabel('f5')}`);

  return log;
}
