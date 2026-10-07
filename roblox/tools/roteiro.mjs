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
