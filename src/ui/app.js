// Controlador de interface: HUD, paleta, painéis, modais e entrada.
// Toda interação usa delegação: elementos com data-action="..." chamam ACTIONS[nome](el).
import { BUILDINGS, BUILDING_ORDER, RESOURCES, TERRAIN } from '../data/buildings.js';
import { HEROES, HERO_BY_ID, RARITIES, EXPEDITIONS, RECRUIT_GEM_COST } from '../data/heroes.js';
import { TALENTS, CROWN_DIVISOR } from '../data/talents.js';
import { SEASON_TIERS, XP_PER_TIER } from '../data/seasons.js';
import { ACHIEVEMENTS } from '../data/achievements.js';
import { BANNERS, EMBLEMS, DAILY_REWARDS } from '../data/cosmetics.js';
import { EVENT_BY_ID } from '../data/events.js';
import { Game, TUTORIAL } from '../core/game.js';
import { createState, serialize, deserialize, exportSave, importSave, SAVE_KEY } from '../core/state.js';
import { buildCost, upgradeCost, canAfford, kingdomPower, heroMultiplier, storageMult } from '../core/economy.js';
import { idx, isUnlocked, ringOf } from '../core/map.js';
import { seasonInfo, tierOf, missionText, rewardFor } from '../core/season.js';
import { councilSlots, recruitGoldCost, speedUpCost } from '../core/heroes.js';
import { rivalGrid, encodeKingdom, decodeKingdom } from '../core/social.js';
import { fmt, fmtRate, fmtPct, fmtTime, fmtCost } from '../core/format.js';
import { MapRenderer } from './render.js';
import { sfx, setSound } from './sfx.js';

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const costHtml = (cost, res) => Object.entries(cost)
  .map(([r, v]) => `<span class="cost ${res && (res[r] || 0) < v ? 'short' : ''}">${RESOURCES[r]?.icon ?? '📜'}${fmt(v)}</span>`).join(' ');
const bannerColor = (id) => BANNERS.find((b) => b.id === id)?.color ?? '#c92a2a';
const emblemIcon = (id) => EMBLEMS.find((e) => e.id === id)?.icon ?? '👑';

let game;
let renderer;
let tab = 'reino';
let visiting = null;
let lastSave = 0;
// Enquanto um ponteiro está pressionado, os painéis não são re-renderizados: trocar o nó entre
// pointerdown e pointerup faz o navegador descartar o "click" (bug de clique perdido).
let pointerHeld = false;
// Fila de modais: um modal novo espera o atual fechar (ex.: resumo offline + recompensa diária).
const modalQueue = [];

// ------------------------------------------------------------------ boot
export function boot() {
  let state = null;
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (raw) state = deserialize(raw);
  } catch (err) {
    console.warn('Save ilegível: cópia guardada em', SAVE_KEY + ':corrompido', err);
    try { localStorage.setItem(SAVE_KEY + ':corrompido', localStorage.getItem(SAVE_KEY)); } catch { /* sem espaço */ }
  }
  const isNew = !state;
  if (!state) state = createState();
  game = new Game(state);
  wireGame();

  renderer = new MapRenderer($('#map'), {
    onTileClick: tileClick,
    onHover: () => {},
  });

  document.addEventListener('click', onClick);
  document.addEventListener('pointerdown', () => { pointerHeld = true; }, true);
  document.addEventListener('pointerup', () => { pointerHeld = false; }, true);
  document.addEventListener('pointercancel', () => { pointerHeld = false; }, true);
  document.addEventListener('keydown', onKey);
  document.addEventListener('visibilitychange', () => { if (document.hidden) save(); else game.tick(Date.now()); });
  window.addEventListener('beforeunload', save);

  setSound(game.state.settings.sound);
  game.tick(Date.now());
  renderPalette();
  renderHud();
  renderSide();
  renderTileInfo();

  setInterval(() => {
    game.tick(Date.now());
    renderHud();
    if (Date.now() - lastSave > 10000) save();
  }, 250);
  setInterval(() => { if (!pointerHeld) { renderSide(); renderPalette(); renderTileInfo(); } ambientFx(); }, 1000);
  const loop = () => { renderer.draw(game); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);

  // Modo debug (?debug): expõe o jogo no console. Ver docs/ARQUITETURA.md.
  if (new URLSearchParams(location.search).has('debug')) window.reino = { game, renderer, save };

  if (isNew) showIntro();
  else {
    const daily = game.dailyStatus();
    if (daily.available) setTimeout(showDaily, 600);
  }
}

function save() {
  try {
    localStorage.setItem(SAVE_KEY, serialize(game.state));
    lastSave = Date.now();
  } catch (err) {
    console.warn('Falha ao salvar', err);
  }
}

// ------------------------------------------------------------------ eventos do motor
function wireGame() {
  game
    .on('toast', ({ text, kind }) => toast(text, kind))
    .on('built', ({ x, y, id }) => { sfx.build(); renderer.addBurst(x, y, '#fff3bf'); renderer.addFloat(x, y, BUILDINGS[id].icon + ' +1'); })
    .on('upgraded', ({ x, y, lvl }) => { sfx.upgrade(); renderer.addBurst(x, y, '#ffd43b'); renderer.addFloat(x, y, `Nv ${lvl}!`, '#ffd43b'); })
    .on('sold', ({ name }) => toast(`🏚️ ${name} demolida (50% devolvido).`))
    .on('cleared', ({ x, y, yieldRes }) => { sfx.coin(); renderer.addFloat(x, y, fmtCost(yieldRes, RESOURCES), '#c0eb75'); })
    .on('expanded', ({ ring }) => { sfx.win(); toast(`🗺️ Novas terras conquistadas! (anel ${ring})`, 'good'); })
    .on('raidWarning', ({ name, strength, defense }) => {
      sfx.warn();
      toast(`🚨 ${name} se aproximam! Força ${strength} vs sua defesa ${Math.floor(defense)}.`, defense >= strength ? 'info' : 'bad');
    })
    .on('raid', (r) => {
      if (r.win) { sfx.win(); renderer.doFlash('#ffd43b'); toast(`⚔️ Vitória sobre ${r.name}! +${fmt(r.loot)} 💰 +${r.gems} 💎`, 'good'); }
      else { sfx.lose(); renderer.doShake(700); renderer.doFlash('#e03131'); toast(`🔥 ${r.name} saquearam ${fmtCost(r.lost, RESOURCES) || 'quase nada'}${r.fraction < 0.1 ? ' (proteção de novato)' : ''}`, 'bad'); }
    })
    .on('event', (ev) => { sfx.chest(); toast(`${ev.icon} ${ev.name}: ${ev.desc}`, 'event'); })
    .on('chest', () => sfx.coin())
    .on('chestOpened', ({ reward, x, y }) => {
      sfx.chest();
      renderer.addBurst(x, y);
      const label = reward.boost ? `Bênção ${reward.boost}min!` : fmtCost(reward, RESOURCES);
      renderer.addFloat(x, y, label, '#ffe066');
    })
    .on('recruited', (r) => showRecruit(r))
    .on('expeditionDone', ({ hid, reward }) => {
      sfx.coin();
      const extra = (reward.gems ? ` +${reward.gems}💎` : '') + (reward.scrolls ? ' +📜' : '');
      toast(`${HERO_BY_ID[hid].icon} Expedição: +${fmt(reward.gold)}💰 +${fmt(reward.wood)}🪵 +${fmt(reward.stone)}🪨${extra}`, 'good');
    })
    .on('tierUp', ({ tier }) => { sfx.upgrade(); toast(`⭐ Passe de Temporada: nível ${tier}! Resgate na aba Temporada.`, 'season'); })
    .on('achievement', (a) => { sfx.win(); toast(`🏆 Conquista: ${a.icon} ${a.name} (+${a.gems}💎${a.title ? `, título "${a.title}"` : ''})`, 'good'); })
    .on('tutorial', () => sfx.coin())
    .on('offline', (sum) => showOffline(sum))
    .on('ascended', ({ crowns }) => { sfx.ascend(); renderer.doFlash('#ffd43b', 1200); toast(`👑 Você ascendeu! +${crowns} Coroas.`, 'good'); renderPalette(); });
}

// ------------------------------------------------------------------ input
function tileClick(x, y) {
  if (visiting) return;
  const s = game.state;
  const mode = renderer.mode;
  if (s.chest && s.chest.x === x && s.chest.y === y && mode.type === 'select') {
    game.openChest();
    return;
  }
  if (mode.type === 'build') {
    const r = game.build(mode.id, x, y);
    if (!r.ok) { sfx.error(); toast(r.reason, 'bad'); return; }
    // mantém o modo para construir em sequência se ainda der para pagar (Shift força sair)
    if (!canAfford(s.res, buildCost(s, mode.id, game.econ.mods))) setMode({ type: 'select' });
    renderPalette();
    return;
  }
  if (mode.type === 'move') {
    const r = game.move(mode.from.x, mode.from.y, x, y);
    if (!r.ok) { sfx.error(); toast(r.reason, 'bad'); return; }
    sfx.build();
    renderer.selected = { x, y };
    setMode({ type: 'select' });
    renderTileInfo();
    return;
  }
  sfx.click();
  renderer.selected = renderer.selected && renderer.selected.x === x && renderer.selected.y === y ? null : { x, y };
  renderTileInfo();
}

function setMode(mode) {
  renderer.mode = mode;
  document.body.dataset.mode = mode.type;
  renderPalette();
  renderModeHint();
}

function onKey(e) {
  if (e.target.matches('input, textarea')) return;
  if (e.key === 'Escape') { setMode({ type: 'select' }); renderer.selected = null; closeModal(); renderTileInfo(); return; }
  const n = Number(e.key);
  if (n >= 1 && n <= 9) {
    const ids = BUILDING_ORDER.filter((id) => game.isAvailable(id));
    if (ids[n - 1]) selectBuild(ids[n - 1]);
  }
}

function selectBuild(id) {
  if (renderer.mode.type === 'build' && renderer.mode.id === id) setMode({ type: 'select' });
  else { renderer.selected = null; setMode({ type: 'build', id }); renderTileInfo(); }
  sfx.click();
}

function result(r, okMsg) {
  if (!r.ok) { sfx.error(); if (r.reason) toast(r.reason, 'bad'); return false; }
  if (okMsg) toast(okMsg, 'good');
  renderSide(true);
  renderHud();
  renderTileInfo();
  return true;
}

const ACTIONS = {
  tab: (el) => { tab = el.dataset.arg; sfx.click(); renderSide(true); },
  build: (el) => selectBuild(el.dataset.arg),
  cancelMode: () => setMode({ type: 'select' }),
  upgrade: () => { const { x, y } = renderer.selected; result(game.upgrade(x, y)); },
  move: () => { setMode({ type: 'move', from: { ...renderer.selected } }); },
  sell: () => {
    const { x, y } = renderer.selected;
    confirmModal('Demolir esta construção? Você recebe 50% de volta.', () => { result(game.sell(x, y)); renderer.selected = null; renderTileInfo(); });
  },
  clear: () => { const { x, y } = renderer.selected; if (result(game.clear(x, y))) renderTileInfo(); },
  expand: () => result(game.expand()),
  closeTile: () => { renderer.selected = null; renderTileInfo(); },
  recruit: (el) => result(game.recruit(el.dataset.arg)),
  council: (el) => result(game.toggleCouncil(el.dataset.arg)),
  expedition: (el) => { const [hid, eid] = el.dataset.arg.split('|'); if (result(game.startExpedition(hid, eid))) sfx.click(); },
  collect: (el) => result(game.collectExpedition(el.dataset.arg)),
  speedup: (el) => result(game.speedUpExpedition(el.dataset.arg)),
  claimTier: (el) => result(game.claimTier(Number(el.dataset.arg))),
  claimAllTiers: () => {
    const max = tierOf(game.state.season.xp);
    for (let t = 1; t <= max; t++) if (!game.state.season.claimed.includes(t)) game.claimTier(t);
    sfx.chest();
    renderSide(true);
  },
  claimMission: (el) => result(game.claimMission(Number(el.dataset.arg))),
  daily: () => { result(game.claimDaily()); closeModal(); sfx.chest(); },
  showDaily: () => showDaily(),
  ascend: () => {
    const c = game.crownsOnAscend();
    confirmModal(`<h3>👑 Ascender?</h3><p>Seu reino atual (prédios, recursos, terras) recomeça do zero. Você ganha <b>${c} Coroas</b> para a Árvore de Legado.</p><p>Ficam com você: heróis, gemas, coroas, temporada, conquistas, cosméticos e talentos.</p>`, () => { result(game.ascend()); renderer.selected = null; });
  },
  talent: (el) => result(game.buyTalent(el.dataset.arg)),
  greet: (el) => { const r = game.greetRival(el.dataset.arg); if (result(r)) toast(r.gift ? '👋 Eles retribuíram com 1 💎!' : '👋 Saudação enviada (+10 XP).', 'good'); },
  trade: (el) => { const [rid, res] = el.dataset.arg.split('|'); const r = game.tradeRival(rid, res); if (result(r)) toast(`🤝 Trocou ${fmt(r.amount)} ${RESOURCES[res].icon} por ${fmt(r.gold)} 💰`, 'good'); },
  visit: (el) => {
    const rival = game.rivals().find((r) => r.id === el.dataset.arg);
    if (rival) startVisit({ id: rival.id, name: rival.name, title: rival.title, banner: rival.banner, emblem: rival.emblem, power: rival.power, grid: rivalGrid(rival) });
  },
  visitCode: () => {
    try {
      const k = decodeKingdom($('#friendCode').value);
      startVisit(k);
    } catch (err) { sfx.error(); toast(err.message, 'bad'); }
  },
  copyCode: () => copyText(encodeKingdom(game.state, kingdomPower(game.state)), 'Código do reino copiado! Mande para um amigo.'),
  endVisit: () => endVisit(),
  rename: () => { if (result(game.setKingdomName($('#kname').value))) toast('Nome atualizado.', 'good'); },
  equip: (el) => { const [kind, id] = el.dataset.arg.split('|'); result(game.equip(kind, id)); },
  buyCosmetic: (el) => { const [kind, id] = el.dataset.arg.split('|'); if (result(game.buyCosmetic(kind, id))) game.equip(kind, id); },
  toggleSound: () => { game.state.settings.sound = !game.state.settings.sound; setSound(game.state.settings.sound); renderSide(true); },
  toggleParticles: () => { game.state.settings.particles = !game.state.settings.particles; renderSide(true); },
  exportSave: () => copyText(exportSave(game.state), 'Save copiado para a área de transferência.'),
  importSave: () => {
    try {
      const st = importSave($('#saveCode').value);
      game.state = st;
      game.tick(Date.now());
      save();
      toast('Save importado!', 'good');
      renderAll();
    } catch (err) { sfx.error(); toast('Save inválido.', 'bad'); }
  },
  hardReset: () => confirmModal('<h3>Apagar tudo?</h3><p>Isso apaga o save local para sempre (exporte antes, se quiser).</p>', () => {
    localStorage.removeItem(SAVE_KEY);
    game.state = createState();
    game.tick(Date.now());
    renderAll();
    showIntro();
  }),
  closeModal: () => closeModal(),
  confirmYes: () => { const fn = pendingConfirm; closeModal(); fn?.(); },
  startGame: () => {
    game.setKingdomName($('#introName').value || 'Reino de Bolso');
    const color = document.querySelector('input[name=introBanner]:checked')?.value;
    if (color) game.equip('banner', color);
    closeModal();
    save();
    renderAll();
    setTimeout(showDaily, 400);
  },
};

function onClick(e) {
  const el = e.target.closest('[data-action]');
  if (!el) return;
  const fn = ACTIONS[el.dataset.action];
  if (fn) { e.preventDefault(); fn(el); }
}

function copyText(text, msg) {
  const done = () => toast(msg, 'good');
  if (navigator.clipboard?.writeText) navigator.clipboard.writeText(text).then(done, () => showModal(`<h3>Copie manualmente</h3><textarea readonly class="code">${esc(text)}</textarea><button data-action="closeModal">Fechar</button>`));
  else showModal(`<h3>Copie manualmente</h3><textarea readonly class="code">${esc(text)}</textarea><button data-action="closeModal">Fechar</button>`);
}

// ------------------------------------------------------------------ HUD
function renderHud() {
  const s = game.state;
  const e = game.econ;
  const res = ['gold', 'food', 'wood', 'stone'].map((r) => {
    const pct = Math.min(100, (s.res[r] / e.caps[r]) * 100);
    const rate = e.rates[r];
    return `<div class="res ${pct >= 99.5 ? 'full' : ''}" title="${RESOURCES[r].name}: ${fmt(s.res[r])} / ${fmt(e.caps[r])}">
      <span class="ri">${RESOURCES[r].icon}</span><span class="rv">${fmt(s.res[r])}</span>
      <span class="rr ${rate < 0 ? 'neg' : ''}">${fmtRate(rate)}</span><i style="width:${pct}%"></i></div>`;
  }).join('');
  const strength = game.raidStrength();
  const raidIn = (s.raid.nextAt - Date.now()) / 1000;
  const safe = e.defense >= strength;
  const ev = s.event && s.event.endsAt > Date.now() ? EVENT_BY_ID[s.event.id] : null;
  const boost = s.boostUntil > Date.now();
  $('#hud-res').innerHTML = `${res}
    <div class="res gem" title="Gemas (só se ganha jogando)"><span class="ri">💎</span><span class="rv">${fmt(s.res.gems)}</span></div>
    <div class="res" title="Moradores / capacidade · trabalhadores exigidos"><span class="ri">👥</span><span class="rv">${Math.floor(s.pop)}/${e.popCap}</span><span class="rr ${e.staffing < 1 ? 'neg' : ''}">⚒${e.workersNeeded}</span></div>
    <div class="res" title="Felicidade: multiplica toda a produção (x${e.happinessMult.toFixed(2)})"><span class="ri">${e.happiness >= 70 ? '😄' : e.happiness >= 40 ? '🙂' : '😠'}</span><span class="rv">${Math.floor(e.happiness)}</span><span class="rr">x${e.happinessMult.toFixed(2)}</span></div>`;
  $('#hud-status').innerHTML = `
    <div class="raid ${safe ? 'safe' : 'danger'} ${raidIn < 20 ? 'soon' : ''}" title="Próxima invasão">
      ${safe ? '🛡️' : '⚠️'} Defesa <b>${fmt(e.defense)}</b> vs <b>${fmt(strength)}</b> · ⏱ ${fmtTime(raidIn)}</div>
    ${ev ? `<div class="evt">${ev.icon} ${ev.name} · ${fmtTime((s.event.endsAt - Date.now()) / 1000)}</div>` : ''}
    ${boost ? `<div class="evt boost">✨ Bênção +50% · ${fmtTime((s.boostUntil - Date.now()) / 1000)}</div>` : ''}`;
  const k = s.kingdom;
  $('#brand').innerHTML = `<span class="banner" style="--bc:${bannerColor(k.banner)}">${emblemIcon(k.emblem)}</span>
    <span><b>${esc(k.name)}</b><small>${esc(k.title)} · Poder ${fmt(kingdomPower(s))}</small></span>`;
  renderTutorial();
}

function renderTutorial() {
  const s = game.state;
  const el = $('#tutorial');
  if (s.tutorial.done || visiting) { el.hidden = true; return; }
  const step = TUTORIAL[s.tutorial.step];
  el.hidden = false;
  el.innerHTML = `<b>Primeiros passos ${s.tutorial.step + 1}/${TUTORIAL.length}</b> ${step.text}`;
}

function renderModeHint() {
  const m = renderer.mode;
  const el = $('#modeHint');
  if (m.type === 'build') {
    const def = BUILDINGS[m.id];
    el.hidden = false;
    el.innerHTML = `${def.icon} Construindo <b>${def.name}</b> — passe o mouse no mapa para ver a adjacência. <button data-action="cancelMode">Cancelar (Esc)</button>`;
  } else if (m.type === 'move') {
    el.hidden = false;
    el.innerHTML = `↔️ Escolha o novo lugar. <button data-action="cancelMode">Cancelar (Esc)</button>`;
  } else el.hidden = true;
}

// ------------------------------------------------------------------ paleta
function renderPalette() {
  const s = game.state;
  const mods = game.econ.mods;
  let n = 0;
  $('#palette').innerHTML = BUILDING_ORDER.map((id) => {
    const def = BUILDINGS[id];
    const avail = game.isAvailable(id);
    if (avail) n++;
    const cost = buildCost(s, id, mods);
    const can = canAfford(s.res, cost);
    const active = renderer.mode.type === 'build' && renderer.mode.id === id;
    if (!avail) return `<div class="pb locked" title="Desbloqueia com ${def.unlock.buildings} construções"><span class="pi">🔒</span><span class="pn">${def.name}</span><span class="pc">${def.unlock.buildings} prédios</span></div>`;
    return `<button class="pb ${can ? '' : 'poor'} ${active ? 'active' : ''}" data-action="build" data-arg="${id}" title="${esc(def.desc)}">
      <span class="pi">${def.icon}</span><span class="pn">${def.name}${n <= 9 ? `<kbd>${n}</kbd>` : ''}</span><span class="pc">${costHtml(cost, s.res)}</span></button>`;
  }).join('');
}

// ------------------------------------------------------------------ painel do tile
function outputLines(info, def) {
  const lines = [];
  for (const [r, v] of Object.entries(info.out || {})) lines.push(`${RESOURCES[r].icon} ${fmtRate(v)}`);
  if (info.consume) lines.push(`🍖 -${fmt(info.consume)}/s`);
  if (info.defense) lines.push(`🛡️ ${fmt(info.defense)} defesa`);
  if (def.popCap) lines.push(`👥 +${def.popCap * info.lvl} moradores`);
  if (def.happiness) lines.push(`😄 ${def.happiness > 0 ? '+' : ''}${fmt(def.happiness * (def.happiness > 0 ? info.mult : 1))} felicidade`);
  if (def.storage) lines.push(`📦 +${fmt(def.storage.gold * storageMult(info.lvl))}💰 / +${fmt(def.storage.food * storageMult(info.lvl))} demais`);
  if (def.crownBonus) lines.push(`👑 +${def.crownBonus * 100}% Coroas`);
  if (def.globalGold) lines.push(`💰 +${def.globalGold * 100}% ouro global`);
  return lines;
}

function renderTileInfo() {
  const el = $('#tileInfo');
  const sel = renderer?.selected;
  if (!sel || visiting) { el.hidden = true; return; }
  const s = game.state;
  const tile = s.grid.tiles[idx(sel.x, sel.y)];
  const unlocked = isUnlocked(s.grid, sel.x, sel.y);
  let html = '';
  if (!unlocked) {
    const cost = game.expandCost();
    const nextRing = ringOf(sel.x, sel.y) === s.grid.ring + 1;
    html = `<h4>🌫️ Terra desconhecida</h4><p>Expanda o reino para conquistar o próximo anel de terra.</p>
      ${cost && nextRing ? `<button data-action="expand" ${canAfford(s.res, cost) ? '' : 'class="poor"'}>🗺️ Expandir ${costHtml(cost, s.res)}</button>` : '<p class="muted">Conquiste os anéis mais próximos primeiro.</p>'}`;
  } else if (tile.b) {
    const def = BUILDINGS[tile.b.id];
    const info = game.econ.tiles[idx(sel.x, sel.y)];
    const up = upgradeCost(tile.b.id, tile.b.lvl, game.econ.mods);
    const adj = info.adjParts.length
      ? info.adjParts.map((p) => `<li class="${p.value > 0 ? 'pos' : 'neg'}">${p.key in BUILDINGS ? BUILDINGS[p.key].icon : TERRAIN[p.key].icon || '💧'} ${p.key in BUILDINGS ? BUILDINGS[p.key].name : TERRAIN[p.key].name} ${fmtPct(p.value)}</li>`).join('')
      : '<li class="muted">Nenhum vizinho com bônus</li>';
    const warn = !info.active ? `<p class="warn">⚠️ Precisa estar encostada em ${TERRAIN[def.requiresAdj].name.toLowerCase()}.</p>`
      : info.workers > 0 && game.econ.staffing < 1 ? `<p class="warn">⚠️ Faltam trabalhadores: rendendo ${Math.round(game.econ.staffing * 100)}%. Construa casas.</p>` : '';
    html = `<h4>${def.icon} ${def.name} <small>Nv ${tile.b.lvl}</small></h4>
      <p class="muted">${esc(def.desc)}</p>${warn}
      <div class="stats">${outputLines(info, def).map((l) => `<span>${l}</span>`).join('')}${info.workers ? `<span>⚒ ${info.workers} trabalhadores</span>` : ''}</div>
      <p><b>Adjacência ${fmtPct(info.adjBonus)}</b></p><ul class="adj">${adj}</ul>
      <div class="row">
        ${up ? `<button data-action="upgrade" class="${canAfford(s.res, up) ? 'primary' : 'poor'}">⬆️ Melhorar ${costHtml(up, s.res)}</button>` : '<span class="muted">Nível máximo</span>'}
        <button data-action="move">↔️ Mover</button>
        <button data-action="sell" class="danger">🏚️</button>
      </div>`;
  } else {
    const ter = TERRAIN[tile.t];
    html = `<h4>${ter.icon || (tile.t === 'water' ? '💧' : '🟩')} ${ter.name}</h4>`;
    if (ter.clearCost) html += `<p class="muted">Pode ser limpo para construir, mas vizinhos que gostam de ${ter.name.toLowerCase()} perdem o bônus.</p>
      <button data-action="clear" class="${canAfford(s.res, ter.clearCost) ? '' : 'poor'}">🧹 Limpar ${costHtml(ter.clearCost, s.res)} → ${fmtCost(ter.clearYield, RESOURCES)}</button>`;
    else if (ter.buildable) html += '<p class="muted">Terreno livre. Escolha uma construção na paleta.</p>';
    else html += `<p class="muted">Não dá para construir aqui, mas vizinhos podem ganhar bônus com ${tile.t === 'water' ? 'a água' : 'a montanha'}.</p>`;
  }
  el.hidden = false;
  el.innerHTML = `<button class="x" data-action="closeTile">✕</button>${html}`;
}

// ------------------------------------------------------------------ painel lateral
let lastSide = '';
function renderSide(force = false) {
  const side = $('#side-body');
  if (!force && side.contains(document.activeElement) && document.activeElement.matches('input, textarea')) return;
  const tabs = [['reino', '🏰', 'Reino'], ['herois', '🦸', 'Heróis'], ['temporada', '⭐', 'Temporada'], ['legado', '👑', 'Legado'], ['social', '🌐', 'Social'], ['perfil', '🎖️', 'Perfil']];
  const badge = {
    temporada: tierOf(game.state.season.xp) > game.state.season.claimed.length || game.state.season.missions?.list.some((m) => !m.claimed && m.progress >= m.target),
    herois: Object.values(game.state.heroes.owned).some((h) => h.expedition && h.expedition.endsAt <= Date.now()) || game.state.items.scrolls > 0,
    legado: game.crownsOnAscend() >= 1,
  };
  $('#tabs').innerHTML = tabs.map(([id, icon, name]) => `<button class="${tab === id ? 'on' : ''}" data-action="tab" data-arg="${id}">${icon}<span>${name}</span>${badge[id] ? '<i class="dot"></i>' : ''}</button>`).join('');
  const html = { reino: tabReino, herois: tabHerois, temporada: tabTemporada, legado: tabLegado, social: tabSocial, perfil: tabPerfil }[tab]();
  if (html !== lastSide || force) {
    const scroll = side.scrollTop;
    side.innerHTML = html;
    side.scrollTop = scroll;
    lastSide = html;
  }
}

function tabReino() {
  const s = game.state;
  const e = game.econ;
  const cost = game.expandCost();
  const daily = game.dailyStatus();
  const missions = s.season.missions?.list ?? [];
  return `
    <section class="card">
      <h3>📜 Missões do dia</h3>
      ${missions.map((m, i) => `<div class="mission ${m.claimed ? 'done' : ''}">
        <span>${esc(missionText(m))}</span>
        <div class="bar"><i style="width:${(m.progress / m.target) * 100}%"></i><em>${fmt(m.progress)}/${fmt(m.target)}</em></div>
        ${m.claimed ? '<span class="ok">✔</span>' : `<button data-action="claimMission" data-arg="${i}" ${m.progress >= m.target ? 'class="primary"' : 'disabled'}>+${m.xp} XP</button>`}
      </div>`).join('')}
      <button class="${daily.available ? 'primary' : ''}" data-action="showDaily">📅 Recompensa diária ${daily.available ? '(disponível!)' : `· sequência ${s.daily.streak}`}</button>
    </section>
    <section class="card">
      <h3>📊 Economia</h3>
      <div class="grid2">
        <span>Ouro</span><b>${fmtRate(e.rates.gold)}</b>
        <span>Comida</span><b class="${e.rates.food < 0 ? 'neg' : ''}">${fmtRate(e.rates.food)} <small>(consumo ${fmt(e.foodConsumption)})</small></b>
        <span>Madeira</span><b>${fmtRate(e.rates.wood)}</b>
        <span>Pedra</span><b>${fmtRate(e.rates.stone)}</b>
        <span>Trabalho</span><b class="${e.staffing < 1 ? 'neg' : ''}">${Math.round(e.staffing * 100)}% (${Math.floor(s.pop)}/${e.workersNeeded})</b>
        <span>Felicidade</span><b>${Math.floor(e.happiness)} → x${e.happinessMult.toFixed(2)}</b>
        <span>Heróis na defesa</span><b>+${fmt(e.heroPower)} poder</b>
        <span>Invasões</span><b>${s.stats.raidsWon} vitórias · nível ${s.raid.level}</b>
      </div>
      ${e.rates.food < 0 ? '<p class="warn">⚠️ A comida está acabando! Sem comida, moradores vão embora e mercados param.</p>' : ''}
      ${e.marketRatio < 1 ? '<p class="warn">⚠️ Mercados sem comida suficiente.</p>' : ''}
    </section>
    <section class="card">
      <h3>🗺️ Território</h3>
      ${cost ? `<p>Anel ${s.grid.ring}/5. Próxima expansão:</p><button data-action="expand" class="${canAfford(s.res, cost) ? 'primary' : 'poor'}">Expandir ${costHtml(cost, s.res)}</button>` : '<p>Todo o mapa é seu. 🏆</p>'}
    </section>
    <section class="card">
      <h3>📖 Crônica do Reino</h3>
      <ul class="log">${s.log.slice(0, 12).map((l) => `<li>${esc(l.text)}</li>`).join('') || '<li class="muted">Nada aconteceu... ainda.</li>'}</ul>
    </section>`;
}

function tabHerois() {
  const s = game.state;
  const slots = councilSlots(game.econ.mods);
  const goldCost = recruitGoldCost(s);
  const now = Date.now();
  const owned = HEROES.filter((h) => s.heroes.owned[h.id]);
  const missing = HEROES.length - owned.length;
  const card = (h) => {
    const o = s.heroes.owned[h.id];
    const inCouncil = s.heroes.council.includes(h.id);
    const v = h.bonus.value * heroMultiplier(o.stars);
    const bonusText = describeBonus(h.bonus.type, v);
    let exp = '';
    if (o.expedition) {
      const left = (o.expedition.endsAt - now) / 1000;
      const ex = EXPEDITIONS.find((x) => x.id === o.expedition.id);
      exp = left <= 0
        ? `<button class="primary" data-action="collect" data-arg="${h.id}">🎁 Coletar ${ex.name}</button>`
        : `<div class="exp">🧭 ${ex.name} · ${fmtTime(left)} <button data-action="speedup" data-arg="${h.id}">⚡ ${speedUpCost(left)}💎</button></div>`;
    } else if (!inCouncil) {
      exp = `<div class="exps">${EXPEDITIONS.map((x) => `<button data-action="expedition" data-arg="${h.id}|${x.id}" title="${x.name}">🧭 ${fmtTime(x.duration)}</button>`).join('')}</div>`;
    }
    return `<div class="hero" style="--rc:${RARITIES[h.rarity].color}">
      <div class="hi">${h.icon}</div>
      <div class="hb"><b>${h.name}</b> <span class="stars">${'★'.repeat(o.stars)}${'☆'.repeat(5 - o.stars)}</span>
        <small>${RARITIES[h.rarity].name} · ⚔ ${h.power * o.stars} · ${bonusText}</small>
        <em>${esc(h.lore)}</em>
        <div class="row">${o.expedition ? '' : `<button data-action="council" data-arg="${h.id}" class="${inCouncil ? 'on' : ''}">${inCouncil ? '🪑 No Conselho' : '➕ Conselho'}</button>`}</div>
        ${exp}
      </div></div>`;
  };
  return `
    <section class="card">
      <h3>📜 Recrutar herói</h3>
      <p class="muted">Raridades: Comum 60% · Raro 28% · Épico 10% · Lendário 2%. Repetidos ganham estrelas. Tudo se ganha jogando.</p>
      <div class="row wrap">
        <button data-action="recruit" data-arg="scroll" class="${s.items.scrolls > 0 ? 'primary' : 'poor'}">📜 Pergaminho (${s.items.scrolls})</button>
        <button data-action="recruit" data-arg="gold" class="${s.res.gold >= goldCost ? '' : 'poor'}">💰 ${fmt(goldCost)}</button>
        <button data-action="recruit" data-arg="gems" class="${s.res.gems >= RECRUIT_GEM_COST ? '' : 'poor'}">💎 ${RECRUIT_GEM_COST}</button>
      </div>
    </section>
    <section class="card">
      <h3>🪑 Conselho ${s.heroes.council.length}/${slots}</h3>
      <p class="muted">Heróis no Conselho dão bônus passivos e defendem o reino. Heróis fora dele podem partir em expedições.</p>
      ${owned.length ? owned.map(card).join('') : '<p class="muted">Nenhum herói ainda. Use seu pergaminho grátis!</p>'}
      ${missing ? `<div class="collection">${HEROES.filter((h) => !s.heroes.owned[h.id]).map((h) => `<span class="ghost" style="--rc:${RARITIES[h.rarity].color}" title="${RARITIES[h.rarity].name} — ainda não encontrado">❔</span>`).join('')}</div><p class="muted">${missing} heróis por descobrir.</p>` : '<p>📚 Coleção completa!</p>'}
    </section>`;
}

function describeBonus(type, v) {
  const [t, r] = type.split(':');
  const map = {
    prod: () => `+${Math.round(v * 100)}% ${RESOURCES[r].name.toLowerCase()}`,
    prodAll: () => `+${Math.round(v * 100)}% toda produção`,
    defense: () => `+${Math.round(v * 100)}% defesa`,
    happiness: () => `+${Math.round(v)} felicidade`,
    expedition: () => `+${Math.round(v * 100)}% expedições`,
    cost: () => `-${Math.round(v * 100)}% custo de obras`,
    raidLoot: () => `+${Math.round(v * 100)}% saque`,
    terrainAdj: () => `+${Math.round(v * 100)}% adjacência de terreno`,
    offline: () => `+${Math.round(v * 100)}% offline`,
  };
  return (map[t] || (() => t))();
}

function tabTemporada() {
  const s = game.state;
  const info = seasonInfo(Date.now());
  const tier = tierOf(s.season.xp);
  const into = s.season.xp - tier * XP_PER_TIER;
  const unclaimed = Array.from({ length: tier }, (_, i) => i + 1).filter((t) => !s.season.claimed.includes(t)).length;
  const tiers = Array.from({ length: SEASON_TIERS }, (_, i) => {
    const t = i + 1;
    const r = rewardFor(t, s);
    const claimed = s.season.claimed.includes(t);
    const reached = t <= tier;
    return `<button class="tier ${claimed ? 'claimed' : reached ? 'ready' : ''} ${r.type === 'cosmetic' ? 'special' : ''}" data-action="claimTier" data-arg="${t}" title="${esc(r.label)}">
      <b>${t}</b><span>${{ gems: '💎', scroll: '📜', boost: '✨', goldMinutes: '💰', cosmetic: r.kind === 'title' ? '🏷️' : r.kind === 'banner' ? '🚩' : '🔰' }[r.type]}</span></button>`;
  }).join('');
  return `
    <section class="card season" style="--sc:${info.theme.color}">
      <h3>${info.theme.icon} Temporada ${info.number} — ${info.theme.name}</h3>
      <p>${info.theme.desc}</p>
      <p class="muted">Termina em ${fmtTime(info.remaining)}. Próxima temporada traz um novo modificador global.</p>
      <div class="bar big"><i style="width:${tier >= SEASON_TIERS ? 100 : (into / XP_PER_TIER) * 100}%"></i><em>Nível ${tier}/${SEASON_TIERS} · ${tier >= SEASON_TIERS ? 'MÁX' : `${into}/${XP_PER_TIER} XP`}</em></div>
      ${unclaimed ? `<button class="primary" data-action="claimAllTiers">🎁 Resgatar ${unclaimed} recompensa(s)</button>` : ''}
    </section>
    <section class="card"><h3>🎟️ Passe de Temporada (gratuito)</h3><div class="tiers">${tiers}</div>
    <p class="muted">XP vem de construir, melhorar, vencer invasões, expedições, baús, missões e da recompensa diária.</p></section>`;
}

function tabLegado() {
  const s = game.state;
  const crowns = game.crownsOnAscend();
  return `
    <section class="card">
      <h3>👑 Ascensão</h3>
      <p>Recomece o reino com bônus permanentes. Coroas vêm do ouro ganho nesta rodada (${fmt(s.stats.runGold)}).</p>
      <p>Coroas: <b>${s.res.crowns}</b> · Ao ascender agora: <b class="gold">+${crowns}</b> ${game.econ.crownBonus ? `<small>(templos +${Math.round(game.econ.crownBonus * 100)}%)</small>` : ''}</p>
      <button data-action="ascend" class="${crowns >= 1 ? 'primary' : 'poor'}">👑 Ascender</button>
      ${crowns < 1 ? `<p class="muted">Primeira coroa com ${fmt(CROWN_DIVISOR)} de ouro na rodada.</p>` : ''}
    </section>
    <section class="card"><h3>🌳 Árvore de Legado</h3>
      ${TALENTS.map((t) => {
        const lvl = s.legacy[t.id] || 0;
        const cost = game.talentCost(t.id);
        return `<div class="talent"><span class="ti">${t.icon}</span><div><b>${t.name}</b> <small>${lvl}/${t.max}</small><br><small>${t.desc(Math.max(1, lvl))}${lvl ? '' : ' (nv 1)'}</small></div>
        ${cost == null ? '<span class="ok">MÁX</span>' : `<button data-action="talent" data-arg="${t.id}" class="${s.res.crowns >= cost ? 'primary' : 'poor'}">👑 ${cost}</button>`}</div>`;
      }).join('')}
      <p class="muted">Talentos de início (Herança, Terras) valem a partir da próxima Ascensão.</p>
    </section>`;
}

function tabSocial() {
  const s = game.state;
  const list = game.rivals();
  const today = new Date();
  const key = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  return `
    <section class="card">
      <h3>🏆 Ranking da Região</h3>
      <ol class="rank">${list.map((r, i) => `<li class="${r.me ? 'me' : ''}">
        <span class="pos">${i + 1}</span><span class="banner sm" style="--bc:${bannerColor(r.banner)}">${emblemIcon(r.emblem)}</span>
        <span class="rn"><b>${esc(r.name)}</b><small>${esc(r.ruler)} · ${esc(r.title)}</small></span><span class="pw">${fmt(r.power)}</span>
        ${r.me ? '' : `<span class="ra">
          <button data-action="visit" data-arg="${r.id}" title="Visitar">👁️</button>
          <button data-action="greet" data-arg="${r.id}" title="Saudar (1x/dia)" ${s.social.greets[r.id] === key ? 'disabled' : ''}>👋</button>
          <button data-action="trade" data-arg="${r.id}|wood" title="Trocar 25% da madeira por ouro (1x/h)">🪵→💰</button>
          <button data-action="trade" data-arg="${r.id}|stone" title="Trocar 25% da pedra por ouro (1x/h)">🪨→💰</button>
        </span>`}</li>`).join('')}</ol>
      <p class="muted">Poder do Reino = ouro da vida toda, prédios, heróis, ascensões e vitórias.</p>
    </section>
    <section class="card">
      <h3>🔗 Compartilhe seu reino</h3>
      <p class="muted">Gere um código e mande para amigos: eles veem sua cidade exatamente como está.</p>
      <button class="primary" data-action="copyCode">📋 Copiar código do meu reino</button>
      <div class="row"><input id="friendCode" placeholder="Cole o código de um amigo (RB1....)"><button data-action="visitCode">👁️ Visitar</button></div>
    </section>`;
}

function tabPerfil() {
  const s = game.state;
  const k = s.kingdom;
  const got = ACHIEVEMENTS.filter((a) => s.achievements[a.id]).length;
  return `
    <section class="card">
      <h3>🎖️ Identidade</h3>
      <div class="row"><input id="kname" maxlength="24" value="${esc(k.name)}"><button data-action="rename">Salvar</button></div>
      <h4>Estandarte</h4><div class="swatches">${BANNERS.map((b) => {
        const own = game.ownsCosmetic('banner', b.id);
        if (!own && b.season) return `<span class="sw locked" style="--bc:${b.color}" title="Recompensa de temporada">🔒</span>`;
        return `<button class="sw ${k.banner === b.id ? 'on' : ''}" style="--bc:${b.color}" title="${b.name}" data-action="${own ? 'equip' : 'buyCosmetic'}" data-arg="banner|${b.id}">${own ? '' : `${b.price}💎`}</button>`;
      }).join('')}</div>
      <h4>Emblema</h4><div class="swatches">${EMBLEMS.map((e) => {
        const own = game.ownsCosmetic('emblem', e.id);
        if (!own && e.season) return `<span class="sw locked" title="Recompensa de temporada">🔒</span>`;
        return `<button class="sw em ${k.emblem === e.id ? 'on' : ''}" data-action="${own ? 'equip' : 'buyCosmetic'}" data-arg="emblem|${e.id}">${e.icon}${own ? '' : `<small>${e.price}💎</small>`}</button>`;
      }).join('')}</div>
      <h4>Título</h4><div class="row wrap">${s.cosmetics.titles.map((t) => `<button class="${k.title === t ? 'on' : ''}" data-action="equip" data-arg="title|${esc(t)}">${esc(t)}</button>`).join('')}</div>
    </section>
    <section class="card">
      <h3>🏆 Conquistas ${got}/${ACHIEVEMENTS.length}</h3>
      <div class="achs">${ACHIEVEMENTS.map((a) => `<div class="ach ${s.achievements[a.id] ? 'got' : ''}" title="${esc(a.desc)}"><span>${s.achievements[a.id] ? a.icon : '🔒'}</span><b>${a.name}</b><small>${esc(a.desc)} · ${a.gems}💎${a.title ? ` · "${a.title}"` : ''}</small></div>`).join('')}</div>
    </section>
    <section class="card">
      <h3>📈 Estatísticas</h3>
      <div class="grid2">
        <span>Ouro (vida toda)</span><b>${fmt(s.stats.totalGold)}</b>
        <span>Construções erguidas</span><b>${s.stats.built}</b>
        <span>Invasões</span><b>${s.stats.raidsWon}V / ${s.stats.raidsLost}D</b>
        <span>Expedições</span><b>${s.stats.expeditions}</b>
        <span>Ascensões</span><b>${s.stats.ascensions}</b>
        <span>Tempo de jogo</span><b>${fmtTime(s.stats.playTime)}</b>
      </div>
    </section>
    <section class="card">
      <h3>⚙️ Configurações</h3>
      <div class="row wrap">
        <button data-action="toggleSound">${s.settings.sound ? '🔊 Som ligado' : '🔇 Som desligado'}</button>
        <button data-action="toggleParticles">${s.settings.particles ? '✨ Partículas' : '▫️ Sem partículas'}</button>
      </div>
      <div class="row wrap"><button data-action="exportSave">💾 Exportar save</button></div>
      <div class="row"><input id="saveCode" placeholder="Cole um save exportado"><button data-action="importSave">Importar</button></div>
      <button class="danger" data-action="hardReset">🗑️ Apagar progresso</button>
    </section>`;
}

// ------------------------------------------------------------------ visitas
function startVisit(k) {
  visiting = k;
  renderer.view = { grid: k.grid };
  renderer.selected = null;
  setMode({ type: 'select' });
  game.recordVisit(k.id || k.name);
  const el = $('#visitBar');
  el.hidden = false;
  el.innerHTML = `<span class="banner" style="--bc:${bannerColor(k.banner)}">${emblemIcon(k.emblem)}</span>
    <span>Visitando <b>${esc(k.name)}</b> · ${esc(k.title)} · Poder ${fmt(k.power)}</span><button data-action="endVisit">🏠 Voltar ao meu reino</button>`;
  renderTileInfo();
  renderTutorial();
}

function endVisit() {
  visiting = null;
  renderer.view = null;
  $('#visitBar').hidden = true;
}

// ------------------------------------------------------------------ efeitos ambientes
let ambientTick = 0;
function ambientFx() {
  if (!game.state.settings.particles || visiting || document.hidden) return;
  ambientTick++;
  if (ambientTick % 3 !== 0) return;
  const e = game.econ;
  const producers = [];
  e.tiles.forEach((info, i) => { if (info && Object.values(info.out).some((v) => v > 0)) producers.push([i, info]); });
  if (!producers.length) return;
  for (let k = 0; k < Math.min(3, producers.length); k++) {
    const [i, info] = producers[Math.floor(Math.random() * producers.length)];
    const [r, v] = Object.entries(info.out).sort((a, b) => b[1] - a[1])[0];
    if (v <= 0) continue;
    renderer.addFloat(i % 12, Math.floor(i / 12), `+${fmt(v * 3)}${RESOURCES[r].icon}`, '#fff');
  }
}

// ------------------------------------------------------------------ modais e toasts
let pendingConfirm = null;
function showModal(html, cls = '') {
  const m = $('#modal');
  if (!m.hidden) { modalQueue.push([html, cls]); return; }
  m.innerHTML = `<div class="sheet ${cls}">${html}</div>`;
  m.hidden = false;
}
function closeModal() {
  $('#modal').hidden = true;
  pendingConfirm = null;
  const next = modalQueue.shift();
  if (next) showModal(...next);
}
function confirmModal(html, fn) {
  pendingConfirm = fn;
  showModal(`${html.startsWith('<') ? html : `<p>${html}</p>`}<div class="row"><button class="primary" data-action="confirmYes">Confirmar</button><button data-action="closeModal">Cancelar</button></div>`);
}

function toast(text, kind = 'info') {
  const box = $('#toasts');
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.textContent = text;
  box.prepend(el);
  while (box.children.length > 5) box.lastChild.remove();
  setTimeout(() => el.classList.add('out'), 4200);
  setTimeout(() => el.remove(), 4800);
}

function showIntro() {
  showModal(`
    <h2>👑 Reino de Bolso</h2>
    <p>Você herdou um terreno, uma casa e uma fazenda. O resto é com você.</p>
    <ul class="intro">
      <li>🧩 <b>A posição importa:</b> cada prédio ganha (ou perde) bônus dos vizinhos.</li>
      <li>⚔️ <b>Hordas atacam</b> de tempos em tempos. Construa defesa.</li>
      <li>🦸 <b>Colecione heróis</b>, mande em expedições e monte seu Conselho.</li>
      <li>👑 <b>Ascenda</b> para recomeçar mais forte. Cada temporada muda as regras.</li>
      <li>🌙 O reino <b>produz mesmo com você fora</b>. Entre 5 minutos ou fique 2 horas.</li>
    </ul>
    <label>Nome do reino <input id="introName" maxlength="24" placeholder="Reino de Bolso"></label>
    <div class="swatches">${BANNERS.filter((b) => b.free).map((b, i) => `<label class="sw" style="--bc:${b.color}"><input type="radio" name="introBanner" value="${b.id}" ${i === 0 ? 'checked' : ''}></label>`).join('')}</div>
    <button class="primary big" data-action="startGame">Fundar meu reino</button>`, 'intro');
}

function showDaily() {
  const st = game.dailyStatus();
  const streak = game.state.daily.streak;
  showModal(`<h3>📅 Recompensa diária</h3>
    <div class="daily">${DAILY_REWARDS.map((r) => {
      const day = r.day;
      const cur = ((st.available ? st.nextStreak : streak) - 1) % 7 + 1;
      const done = st.available ? day < cur : day <= cur;
      return `<div class="dr ${done ? 'done' : ''} ${st.available && day === cur ? 'today' : ''}"><b>Dia ${day}</b><span>${r.label}</span></div>`;
    }).join('')}</div>
    ${st.available ? `<button class="primary big" data-action="daily">Resgatar: ${st.reward.label}</button>` : '<p class="muted">Já resgatada hoje. Volte amanhã para manter a sequência!</p><button data-action="closeModal">Fechar</button>'}`);
}

function showOffline(sum) {
  const g = sum.gains;
  showModal(`<h3>🌙 Enquanto você esteve fora (${fmtTime(sum.elapsed)})</h3>
    <p>Seu reino trabalhou com ${Math.round(sum.efficiency * 100)}% de eficiência${sum.capped ? ` por até ${fmtTime(sum.simulated)} (limite offline)` : ''}.</p>
    <div class="gains">${['gold', 'food', 'wood', 'stone'].map((r) => `<div><span>${RESOURCES[r].icon}</span><b class="${g[r] < 0 ? 'neg' : ''}">${g[r] >= 0 ? '+' : ''}${fmt(g[r])}</b></div>`).join('')}</div>
    ${sum.expeditionsReady ? `<p>🧭 ${sum.expeditionsReady} expedição(ões) prontas para coletar!</p>` : ''}
    ${sum.capped ? '<p class="muted">Aumente o limite com o talento Vigília ou o herói O Relojoeiro.</p>' : ''}
    <button class="primary big" data-action="closeModal">Continuar</button>`);
}

function showRecruit(r) {
  const h = r.hero;
  const rar = RARITIES[h.rarity];
  if (h.rarity === 'lendario') sfx.legendary(); else sfx.chest();
  showModal(`<div class="reveal" style="--rc:${rar.color}">
      <div class="big-icon">${h.icon}</div>
      <p class="rarity">${rar.name}</p>
      <h2>${h.name}</h2>
      <p>${r.isNew ? 'Novo herói!' : r.gemsRefund ? `Já está no máximo: +${r.gemsRefund} 💎` : `Duplicado! Agora ★${r.stars}`}</p>
      <p class="muted">${describeBonus(h.bonus.type, h.bonus.value * heroMultiplier(r.stars))} · ⚔ ${h.power * r.stars}</p>
      <em>${esc(h.lore)}</em>
    </div><button class="primary big" data-action="closeModal">Bem-vindo(a)!</button>`, 'reveal-sheet');
}

function renderAll() {
  endVisit();
  renderer.selected = null;
  setMode({ type: 'select' });
  setSound(game.state.settings.sound);
  renderPalette();
  renderHud();
  renderSide(true);
  renderTileInfo();
}
