// HUD, paleta, painel do tile e abas do painel lateral. Só gera HTML/atualiza DOM; ações ficam em app.js.
import { BUILDINGS, BUILDING_ORDER, RESOURCES, TERRAIN, MAX_LEVEL, PLANT_COST, GROW_SECONDS } from '../data/buildings.js';
import { HEROES, RARITIES, EXPEDITIONS, RECRUIT_GEM_COST, MAX_STARS, HERO_MAX_LEVEL } from '../data/heroes.js';
import { TALENTS, CROWN_DIVISOR } from '../data/talents.js';
import { SEASON_TIERS, XP_PER_TIER } from '../data/seasons.js';
import { ACHIEVEMENTS, ACH_PROD_BONUS } from '../data/achievements.js';
import { GEM_SHOP, GEM_PACKS, PAYMENTS_ENABLED } from '../data/shop.js';
import { BANNERS, EMBLEMS } from '../data/cosmetics.js';
import { EVENT_BY_ID } from '../data/events.js';
import { TUTORIAL, TAB_UNLOCKS, TAB_NAMES, DIR_NAMES } from '../core/game.js';
import { buildCost, upgradeCost, repairCost, canAfford, kingdomPower, heroStrength, heroPowerOf, storageMult, countOf, defenseWeight, wallFacing, maxLevelOf } from '../core/economy.js';
import { idx, isUnlocked, ringOf, wallMask, GRID_H } from '../core/map.js';
import { seasonInfo, tierOf, missionText, rewardFor } from '../core/season.js';
import {
  councilSlots, recruitGoldCost, speedUpCost, expeditionSpeedUpCost, expeditionSlots, activeExpeditions, tavernDiscount, heroLevelCap, trainingSlots, trainingCount, trainCost,
} from '../core/heroes.js';
import { fmt, fmtRate, fmtPct, fmtTime } from '../core/format.js';
import { UNDER_SPRITES, ROOM_SPRITES, BUILDING_SPRITES, TERRAIN_SPRITES, RUIN_ICON } from './sprites.js';
import { ui, $, esc, costHtml, bannerColor, emblemIcon, deltaText } from './ctx.js';
import { ico, resIco } from './icons.js';
import { runHistoryHtml } from './ascension.js';
import { UNDER_TILES, ROOMS, ROOM_ORDER, LEVEL_NAMES } from '../data/underground.js';
import { digCost, digYield, canReach, stairsCost, roomCost, roomUpgradeCost, roomAdjacency } from '../core/underground.js';

const spriteOf = (id) => BUILDING_SPRITES[id]?.icon;
const touchUi = () => window.matchMedia?.('(pointer: coarse)').matches ?? false;

// ================================================================ HUD
let hudBuilt = false;
const RES_LIST = ['gold', 'food', 'wood', 'stone'];

// Rosa dos ventos do canto do mapa (SVG próprio). A ponta do lado da próxima horda fica vermelha.
const COMPASS_SVG = (() => {
  const point = (len, w, rot, cls) => `<g class="${cls}" transform="rotate(${rot})"><polygon class="lt" points="0,-${len} -${w},-${w} 0,0"/><polygon class="dk" points="0,-${len} ${w},-${w} 0,0"/></g>`;
  const diag = [45, 135, 225, 315].map((r) => point(19, 4.5, r, 'pt-d')).join('');
  const card = [['n', 0], ['e', 90], ['s', 180], ['w', 270]].map(([d, r]) => point(31, 7, r, `pt pt-${d}`)).join('');
  const letters = [['N', 0, -38.5], ['L', 38.5, 0], ['S', 0, 38.5], ['O', -38.5, 0]].map(([t, x, y]) => `<text x="${x}" y="${y}">${t}</text>`).join('');
  return `<svg viewBox="-50 -50 100 100" aria-hidden="true"><circle class="ring" r="47"/><circle class="ring2" r="31.5"/>${diag}${card}<circle class="hub" r="4"/>${letters}</svg>`;
})();

function buildHud() {
  $('#menuBtn').innerHTML = ico('menu');
  $('#hud-res').innerHTML = [
    ...RES_LIST.map((r) => `<button class="chip" id="chip-${r}" data-action="info" data-arg="${r}">${resIco(r)}<span class="num"></span><span class="rate"></span><i class="bar"></i></button>`),
    `<button class="chip" id="chip-gems" data-action="info" data-arg="gems">${resIco('gems')}<span class="num"></span></button>`,
    `<button class="chip" id="chip-pop" data-action="info" data-arg="pop">${ico('people')}<span class="num"></span><span class="rate"></span></button>`,
    `<button class="chip" id="chip-happy" data-action="info" data-arg="happiness">${ico('heart', 'c-heart')}<span class="num"></span><span class="rate"></span></button>`,
  ].join('');
  $('#hud-status').innerHTML = `
    <button class="status" id="st-raid" data-action="info" data-arg="raid"></button>
    <button class="status danger" id="st-repair" data-action="repairAll" hidden></button>
    <button class="status event" id="st-event" data-action="info" data-arg="event" hidden></button>
    <button class="status boost" id="st-boost" data-action="info" data-arg="boost" hidden></button>
    <button class="status ascend" id="st-ascend" data-action="tab" data-arg="legado" hidden></button>`;
  $('#compass').innerHTML = COMPASS_SVG;
  hudBuilt = true;
}

const setText = (el, t) => { if (el.textContent !== t) el.textContent = t; };
const setHtml = (el, h) => { if (el.dataset.h !== h) { el.innerHTML = h; el.dataset.h = h; } };

// Feedback de recurso: produção normal não anima; ganhos e gastos de uma vez (recompensa, obra) sim.
let lastRes = {};
let lastResState = null;
function bump(chip, r, value, rate) {
  const prev = lastRes[r];
  lastRes[r] = value;
  if (prev === undefined) return;
  const d = value - prev;
  const tickGain = Math.max(0, rate) * 0.6 + 0.5; // folga para o que a produção rende entre dois quadros do HUD
  const kind = d > tickGain + Math.max(1, prev * 0.02) ? 'gain' : d < -Math.max(0.5, -Math.min(0, rate) * 0.6 + 0.5) ? 'spend' : null;
  if (!kind) return;
  chip.classList.remove('gain', 'spend');
  void chip.offsetWidth; // reinicia a animação
  chip.classList.add(kind);
}

export function renderHud() {
  const g = ui.game;
  const s = g.state;
  const e = g.econ;
  if (!hudBuilt) buildHud();
  if (lastResState !== s) { lastRes = {}; lastResState = s; } // reino novo/importado/ascendido: sem "pulo" falso
  for (const r of RES_LIST) {
    const chip = $(`#chip-${r}`);
    bump(chip, r, s.res[r], e.rates[r]);
    const pct = Math.min(100, (s.res[r] / e.caps[r]) * 100);
    chip.classList.toggle('full', pct >= 99.5);
    chip.title = `${RESOURCES[r].name}: ${fmt(s.res[r])} de ${fmt(e.caps[r])}`;
    setText(chip.querySelector('.num'), fmt(s.res[r]));
    const rate = chip.querySelector('.rate');
    setText(rate, fmtRate(e.rates[r]));
    rate.classList.toggle('neg', e.rates[r] < 0);
    chip.querySelector('.bar').style.width = `${pct}%`;
  }
  bump($('#chip-gems'), 'gems', s.res.gems, 0);
  setText($('#chip-gems .num'), fmt(s.res.gems));
  setText($('#chip-pop .num'), `${Math.floor(s.pop)}/${e.popCap}`);
  const popRate = $('#chip-pop .rate');
  setText(popRate, `${e.workersNeeded} trab.`);
  popRate.classList.toggle('neg', e.staffing < 1);
  setText($('#chip-happy .num'), String(Math.floor(e.happiness)));
  setText($('#chip-happy .rate'), `x${e.happinessMult.toFixed(2)}`);

  const strength = g.raidStrength();
  const raidIn = (s.raid.nextAt - Date.now()) / 1000;
  const safe = e.defense >= strength;
  const raid = $('#st-raid');
  raid.className = `status ${safe ? 'safe' : 'danger'} ${raidIn < 20 ? 'soon' : ''}`;
  // Duas linhas: o que é (horda, de onde, quando) e se a defesa daquele lado aguenta.
  setHtml(raid, `${ico(safe ? 'defense' : 'warning')}<span><small>Horda pelo ${DIR_NAMES[s.raid.dir]} · ${s.raid.warned ? 'chegando' : fmtTime(raidIn)}</small>Defesa <b class="def">${fmt(e.defense)}</b> / ${fmt(strength)} ${safe ? '· protegido' : '· vulnerável'}</span>`);
  raid.setAttribute('aria-label', `Próxima horda pelo ${DIR_NAMES[s.raid.dir]} em ${fmtTime(raidIn)}. Defesa ${fmt(e.defense)} contra força ${fmt(strength)}.`);
  const compass = $('#compass');
  compass.dataset.raid = s.raid.dir;
  compass.classList.toggle('warned', !!s.raid.warned);
  compass.hidden = !!ui.renderer?.view; // visitando outro reino: a horda anunciada é a do seu
  const compassLabel = `Rosa dos ventos. Próxima horda pelo ${DIR_NAMES[s.raid.dir]}.`;
  if (compass.title !== compassLabel) { compass.title = compassLabel; compass.setAttribute('aria-label', compassLabel); }
  const broken = g.damagedCount();
  const repEl = $('#st-repair');
  repEl.hidden = !broken || !!ui.renderer?.view;
  if (broken) setHtml(repEl, `${ico('build')}<span><small>${broken} danificada${broken > 1 ? 's' : ''}</small>Consertar tudo</span>`);
  const ev = s.event && s.event.endsAt > Date.now() ? EVENT_BY_ID[s.event.id] : null;
  const evEl = $('#st-event');
  evEl.hidden = !ev;
  if (ev) setHtml(evEl, `${ico(ev.icon)}<span><small>Evento · ${fmtTime((s.event.endsAt - Date.now()) / 1000)}</small>${ev.name}</span>`);
  const boostEl = $('#st-boost');
  boostEl.hidden = !(s.boostUntil > Date.now());
  if (!boostEl.hidden) setHtml(boostEl, `${ico('boost')}<span><small>Bênção · ${fmtTime((s.boostUntil - Date.now()) / 1000)}</small>+50% produção</span>`);
  const adv = g.isTabUnlocked('legado') ? g.ascendAdvice() : null;
  const asc = $('#st-ascend');
  asc.hidden = !adv?.recommended;
  if (adv?.recommended) setHtml(asc, `${ico('crowns')}<span><small>Vale ascender</small>+${adv.crowns} ${adv.crowns === 1 ? 'Coroa' : 'Coroas'}</span>`);

  const k = s.kingdom;
  setHtml($('#brand'), `<span class="banner" style="--bc:${bannerColor(k.banner)}">${ico(emblemIcon(k.emblem))}</span>
    <span><b>${esc(k.name)}</b><small>${esc(k.title)} · Poder ${fmt(kingdomPower(s))}</small></span>`);
  renderTutorial();
}

export function hudInfo(key) {
  const g = ui.game;
  const e = g.econ;
  const s = g.state;
  const txt = {
    gold: `Ouro paga quase tudo. Vem de casas (impostos), mercados e minas. Limite: ${fmt(e.caps.gold)} (armazéns aumentam).`,
    food: `Comida: cada morador come 0,15/s. Sem comida, moradores vão embora e mercados param. Consumo atual: ${fmt(e.foodConsumption)}/s.`,
    wood: 'Madeira vem das serrarias; cada floresta vizinha dá +40%.',
    stone: 'Pedra vem das pedreiras (rochas vizinhas dão +50%). Necessária para defesa e expansão.',
    gems: 'Gemas vêm de invasões, carroças, missões, conquistas, passe e expedições, ou da Loja de Gemas (aba Perfil). Compram recursos, impulsos, pergaminhos, aceleram treinos e expedições e liberam cosméticos.',
    pop: `Moradores ${Math.floor(s.pop)} de ${e.popCap}. Os prédios pedem ${e.workersNeeded} trabalhadores. Fazendas e moinhos são ocupados primeiro; com menos gente, os outros prédios rendem menos.`,
    happiness: `Felicidade ${Math.floor(e.happiness)}: multiplica toda a produção por ${e.happinessMult.toFixed(2)}. Tavernas, templos e decorações aumentam; pedreiras, minas e superlotação reduzem.`,
    raid: `A próxima horda vem do ${DIR_NAMES[s.raid.dir]}. Torres e muralhas desse lado do mapa contam 100%; do lado oposto, 50%. Muralha de lado para a horda conta só metade. Heróis do Conselho sempre contam inteiros. Se a horda vencer, ela danifica construções desse lado (muralhas e torres seguram os golpes primeiro); o que não for consertado até a próxima derrota vira ruína.`,
    event: s.event ? `${EVENT_BY_ID[s.event.id].name}: ${EVENT_BY_ID[s.event.id].desc}` : 'Nenhum evento agora.',
    boost: 'Bênção: +50% em toda a produção enquanto durar.',
  }[key];
  return txt;
}

export function renderTutorial() {
  const s = ui.game.state;
  const el = $('#tutorial');
  if (s.tutorial.done || ui.visiting) { el.hidden = true; return; }
  const step = TUTORIAL[s.tutorial.step];
  el.hidden = false;
  const dots = TUTORIAL.map((_, i) => `<i class="${i <= s.tutorial.step ? 'on' : ''}"></i>`).join('');
  const before = el.dataset.step;
  setHtml(el, `${ico('mission')}<span class="tt"><span class="step">Primeiros passos ${s.tutorial.step + 1}/${TUTORIAL.length}<span class="dots" aria-hidden="true">${dots}</span></span>${step.text}</span>`);
  el.dataset.step = String(s.tutorial.step);
  if (before !== undefined && before !== el.dataset.step) { el.classList.remove('advance'); void el.offsetWidth; el.classList.add('advance'); }
}

export function tutorialFocus() {
  const s = ui.game.state;
  return s.tutorial.done ? null : TUTORIAL[s.tutorial.step]?.focus ?? null;
}

// ================================================================ dica de modo (construir/mover)
export function renderModeHint() {
  const m = ui.renderer.mode;
  const el = $('#modeHint');
  if (m.type === 'build') {
    const def = BUILDINGS[m.id];
    const d = ui.hoverDelta;
    el.hidden = false;
    setHtml(el, `<img src="${spriteOf(m.id)}" alt="" width="32" height="32"><span><b>${def.name}</b>: ${esc(def.desc)}${d ? `<br><span class="delta">Neste lugar: ${deltaText(d)}</span>` : `<br><span class="muted">${touchUi() ? 'Toque num tile para ver o ganho; toque de novo para construir.' : 'Passe o mouse num tile para ver o ganho; clique para construir.'}</span>`}</span><button class="btn small" data-action="cancelMode">Cancelar</button>`);
  } else if (m.type === 'move') {
    el.hidden = false;
    setHtml(el, `${ico('move')}<span>Escolha o novo lugar (mover é grátis).</span><button class="btn small" data-action="cancelMode">Cancelar</button>`);
  } else el.hidden = true;
  dodgeModeHint(el);
}

// Com o mapa todo expandido a dica cobre a fileira da borda: se o tile sob o cursor
// (ou o último toque) ficar embaixo dela, ela pula para a borda oposta.
function dodgeModeHint(el) {
  el.classList.remove('flip');
  const t = ui.renderer.hover;
  if (el.hidden || !t) return;
  const c = ui.renderer.canvas.getBoundingClientRect();
  const size = c.height / GRID_H;
  const top = c.top + t.y * size, bottom = top + size;
  const h = el.getBoundingClientRect();
  if (bottom > h.top && top < h.bottom) el.classList.add('flip');
}

// ================================================================ paleta
let paletteSig = '';
export function renderPalette(force = false) {
  const g = ui.game;
  const s = g.state;
  const mods = g.econ.mods;
  const focus = tutorialFocus();
  let n = 0;
  const items = BUILDING_ORDER.map((id) => {
    const def = BUILDINGS[id];
    const avail = g.isAvailable(id);
    if (avail) n++;
    const cost = buildCost(s, id, mods);
    return { id, def, avail, n, cost, can: canAfford(s.res, cost), active: ui.renderer.mode.type === 'build' && ui.renderer.mode.id === id, focus: focus?.build === id };
  });
  const sig = JSON.stringify([g.unlockProgress(), items.map((i) => [i.avail, i.can, i.active, i.focus, i.cost])]);
  if (!force && sig === paletteSig) return;
  paletteSig = sig;
  // Bloqueados ficam compactos, depois dos disponíveis e em ordem de desbloqueio: o que dá para
  // construir agora não se perde no meio de 11 cartões apagados (achado da revisão de UX).
  const open = items.filter((it) => it.avail);
  const locked = items.filter((it) => !it.avail).sort((a, b) => a.def.unlock.buildings - b.def.unlock.buildings);
  const have = g.unlockProgress();
  const nextAt = locked[0]?.def.unlock.buildings;
  const openHtml = open.map((it) => `<button class="pb ${it.can ? '' : 'poor'} ${it.active ? 'active' : ''} ${it.focus ? 'focus' : ''}" data-action="build" data-arg="${it.id}" aria-pressed="${it.active}" title="${esc(it.def.desc)}">
      <img src="${spriteOf(it.id)}" alt=""><span class="pn">${it.def.name}${it.n <= 9 ? `<kbd>${it.n}</kbd>` : ''}</span><span class="pc">${costHtml(it.cost, s.res)}</span></button>`).join('');
  const lockedHtml = locked.map((it) => `<button class="pb locked ${it.def.unlock.buildings === nextAt ? 'next' : ''}" data-action="lockedBuilding" data-arg="${it.id}" aria-label="${it.def.name}: libera com ${it.def.unlock.buildings} construções">
      <img src="${spriteOf(it.id)}" alt=""><span class="pn">${it.def.name}</span><span class="pc">${ico('lock')} ${it.def.unlock.buildings}</span></button>`).join('');
  $('#palette').innerHTML = `<p class="pal-head"><span>Construir</span><span>${open.length}/${items.length}</span></p>${openHtml}`
    + (locked.length ? `<p class="pal-head"><span>A desbloquear</span><span>${have}/${nextAt} obras</span></p>${lockedHtml}` : '');
}

// ================================================================ painel do tile
// Painel de um tile do subsolo: o que é, o que dá para fazer ali e quanto custa.
function underTileHtml(g, d, x, y) {
  const s = g.state;
  const lv = s.under.levels[d - 1];
  const t = lv.tiles[idx(x, y)];
  const where = `<small class="muted">Nível ${d} · ${LEVEL_NAMES[d - 1]}</small>`;
  if (!t.s) return `<div class="title-row">${ico('hero-dwarf', 'lg')}<h3>${where}Escuridão</h3></div><p class="muted">Ninguém sabe o que tem aqui. Cave galerias até chegar perto para descobrir.</p>`;
  const kind = UNDER_TILES[t.t];
  if (t.b) {
    const def = ROOMS[t.b.id];
    const info = g.econ.under?.[d - 1]?.[idx(x, y)];
    const up = roomUpgradeCost(t.b.id, t.b.lvl, g.econ.mods);
    const adj = info?.adjParts.length
      ? info.adjParts.map((p) => `<li class="pos">${ROOMS[p.key]?.name ?? UNDER_TILES[p.key]?.name ?? 'Parede'} ${fmtPct(p.value)}</li>`).join('')
      : '<li class="muted">Nenhum vizinho com bônus</li>';
    const lines = [];
    for (const [r, v] of Object.entries(info?.out ?? {})) lines.push(`${resIco(r)} ${fmtRate(v)}`);
    if (def.storage) for (const [r, v] of Object.entries(def.storage)) lines.push(`${resIco(r)} +${fmt(v * t.b.lvl * t.b.lvl)} de armazém`);
    if (def.foodBonus) lines.push(`${resIco('food')} +${Math.round(def.foodBonus * t.b.lvl * 100)}% de comida no reino`);
    if (def.prodAll && info?.active) lines.push(`${ico('upgrade')} +${Math.round(def.prodAll * t.b.lvl * 100)}% de toda a produção`);
    const warn = info && !info.active ? `<p class="warn">${ico('warning')} Precisa estar encostada em ${UNDER_TILES[def.requiresAdj].name.toLowerCase()}.</p>` : '';
    return `<div class="title-row"><img src="${ROOM_SPRITES[t.b.id].icon}" alt=""><h3><small class="muted">Nível ${t.b.lvl} de ${def.maxLevel} · subsolo ${d}</small>${def.name}</h3></div>
      <p class="muted">${esc(def.desc)}</p>${warn}
      <div class="lbl"><span>Produção</span></div>
      <div class="stats">${lines.map((l) => `<span>${l}</span>`).join('')}</div>
      ${Object.keys(def.adj).length ? `<div class="lbl"><span>Vizinhos</span><span class="${info?.adjBonus > 0 ? 'pos' : ''}">${fmtPct(info?.adjBonus ?? 0)}</span></div><ul class="adj">${adj}</ul>` : ''}
      ${up ? `<div class="row"><button class="btn ${canAfford(s.res, up) ? 'primary' : 'poor'}" data-action="roomUp">${ico('upgrade')} Melhorar ${costHtml(up, s.res)}</button></div>` : '<p class="muted">Nível máximo.</p>'}
      <hr class="divider"><div class="row"><button class="btn small danger" data-action="roomSell">${ico('demolish')} Demolir</button></div>`;
  }
  let html = `<div class="title-row"><img src="${UNDER_SPRITES[t.t][0]}" alt=""><h3>${where}${t.st ? (t.st === 'down' ? 'Escada para baixo' : 'Escada para cima') : kind.name}</h3></div>`;
  if (t.st) {
    const to = t.st === 'down' ? d + 1 : d - 1;
    return `${html}<p class="muted">${t.st === 'down' ? `Leva às ${LEVEL_NAMES[d].toLowerCase()}.` : to === 0 ? 'Leva de volta à superfície, pela Escadaria.' : `Leva às ${LEVEL_NAMES[to - 1].toLowerCase()}.`}</p>
      <button class="btn primary" data-action="goLayer" data-arg="${to}">${ico('move')} ${t.st === 'down' ? 'Descer' : 'Subir'}</button>`;
  }
  html += `<p class="muted">${esc(kind.desc)}</p>`;
  if (kind.dig) {
    const cost = digCost(s, d, g.econ.mods);
    const reach = canReach(lv, x, y);
    html += reach
      ? `<button class="btn ${canAfford(s.res, cost) ? 'primary' : 'poor'}" data-action="dig">${ico('tool-pickaxe')} Cavar ${costHtml(cost, s.res)}, ganha ${costHtml(digYield(t.t, d))}</button>`
      : '<p class="warn">Cave a partir de uma galeria vizinha (de lado, não na diagonal).</p>';
    return html;
  }
  if (!kind.open) return html;
  const rooms = ROOM_ORDER.filter((id) => ROOMS[id].minDepth <= d && (ROOMS[id].onTile ? t.t === ROOMS[id].onTile : t.t === 'floor'));
  if (rooms.length) {
    html += '<div class="lbl"><span>Construir sala</span></div><div class="rooms">';
    for (const id of rooms) {
      const def = ROOMS[id];
      const cost = roomCost(s, id, g.econ.mods);
      const adj = roomAdjacency(lv, id, x, y);
      const why = adj.hasRequired ? '' : ` (precisa de ${UNDER_TILES[def.requiresAdj].name.toLowerCase()} ao lado)`;
      html += `<button class="btn small room ${adj.hasRequired && canAfford(s.res, cost) ? '' : 'poor'}" data-action="room" data-arg="${id}" title="${esc(def.desc)}${why}"><img src="${ROOM_SPRITES[id].icon}" alt=""><span><b>${def.name}</b>${adj.hasRequired ? (adj.total ? ` <em class="pos">${fmtPct(adj.total)}</em>` : '') : ' <em class="neg">sem vizinho certo</em>'}<br>${costHtml(cost, s.res)}</span></button>`;
    }
    html += '</div>';
  } else if (t.t === 'cavern' && d < 2) html += '<p class="muted">Nada para construir aqui.</p>';
  const stairs = stairsCost(d);
  if (stairs) html += `<hr class="divider"><button class="btn small ${canAfford(s.res, stairs) ? '' : 'poor'}" data-action="digStairs">${ico('tool-pickaxe')} Cavar escada para o nível ${d + 1} ${costHtml(stairs, s.res)}</button>`;
  return html;
}

function outputLines(info, def, tileX, tileY) {
  const lines = [];
  for (const [r, v] of Object.entries(info.out || {})) lines.push(`${resIco(r)} ${fmtRate(v)}`);
  if (info.consume) lines.push(`${resIco('food')} -${fmt(info.consume)}/s`);
  if (info.defense) {
    const st = ui.game.state;
    const id = st.grid.tiles[idx(tileX, tileY)].b.id;
    const sideways = id === 'muralha' && wallFacing(wallMask(st.grid, tileX, tileY), st.raid.dir) < 1;
    lines.push(`${ico('defense', 'c-def')} ${fmt(info.defense)} defesa (contra o ${DIR_NAMES[st.raid.dir]}: ${Math.round(defenseWeight(st, id, st.raid.dir, tileX, tileY) * 100)}%${sideways ? ', muralha de lado' : ''})`);
  }
  if (def.popCap) lines.push(`${ico('people')} +${def.popCap * info.lvl} moradores`);
  if (def.happiness) lines.push(`${ico('heart', 'c-heart')} ${def.happiness > 0 ? '+' : ''}${fmt(def.happiness * (def.happiness > 0 ? info.mult : 1))} felicidade`);
  if (def.storage) lines.push(`${ico('talent-inheritance')} +${fmt(def.storage.gold * storageMult(info.lvl))} de ouro / +${fmt(def.storage.food * storageMult(info.lvl))} dos demais`);
  if (def.crownBonus) lines.push(`${resIco('crowns')} +${def.crownBonus * 100}% Coroas`);
  if (def.globalGold) lines.push(`${resIco('gold')} +${def.globalGold * 100}% de ouro global`);
  if (info.workers) lines.push(`${ico('people')} ${info.workers} trabalhadores`);
  return lines;
}

let tileSig = '';
export function renderTileInfo(force = false) {
  const el = $('#tileInfo');
  const sel = ui.renderer?.selected;
  if (!sel || ui.visiting) { el.hidden = true; tileSig = ''; return; }
  const g = ui.game;
  const s = g.state;
  const tile = s.grid.tiles[idx(sel.x, sel.y)];
  const unlocked = isUnlocked(s.grid, sel.x, sel.y);
  let html = '';
  if (ui.renderer.layer > 0) {
    html = underTileHtml(g, ui.renderer.layer, sel.x, sel.y);
  } else if (!unlocked) {
    const cost = g.expandCost();
    const nextRing = ringOf(sel.x, sel.y) === s.grid.ring + 1;
    html = `<div class="title-row">${ico('map', 'lg')}<h3>Terra desconhecida</h3></div><p>Expanda o reino para conquistar o próximo anel de terra.</p>
      ${cost && nextRing ? `<button class="btn ${canAfford(s.res, cost) ? 'primary' : 'poor'}" data-action="expand">${ico('map')} Expandir ${costHtml(cost, s.res)}</button>` : '<p class="muted">Conquiste os anéis mais próximos primeiro.</p>'}`;
  } else if (tile.b) {
    const def = BUILDINGS[tile.b.id];
    const info = g.econ.tiles[idx(sel.x, sel.y)];
    const up = upgradeCost(tile.b.id, tile.b.lvl, g.econ.mods);
    const fix = tile.b.dmg ? repairCost(tile.b.id, tile.b.lvl, g.econ.mods) : null;
    const upDelta = up && !fix ? g.previewUpgrade(sel.x, sel.y) : null;
    const sameType = countOf(s, tile.b.id);
    const adj = info.adjParts.length
      ? info.adjParts.map((p) => `<li class="${p.value > 0 ? 'pos' : 'neg'}">${p.key in BUILDINGS ? BUILDINGS[p.key].name : TERRAIN[p.key].name} ${fmtPct(p.value)}</li>`).join('')
      : '<li class="muted">Nenhum vizinho com bônus</li>';
    const warn = info.damaged ? `<p class="warn">${ico('warning')} Danificada pela horda: não produz nem defende. Conserte antes da próxima derrota ou ela desaba.</p>`
      : !info.active ? `<p class="warn">${ico('warning')} Só funciona ao lado de ${TERRAIN[def.requiresAdj].id === 'water' ? 'água' : TERRAIN[def.requiresAdj].name.toLowerCase()}.</p>`
      : info.workers > 0 && info.staff < 1 ? `<p class="warn">${ico('warning')} Faltam trabalhadores: rendendo ${Math.round(info.staff * 100)}%. Construa ou melhore casas.</p>` : '';
    const maxLvl = def.maxLevel ?? MAX_LEVEL;
    html = `<div class="title-row"><img src="${spriteOf(tile.b.id)}" alt=""><h3><small class="muted">Nível ${tile.b.lvl} de ${maxLvl}</small>${def.name}</h3></div>
      <p class="muted">${esc(def.desc)}</p>${warn}
      <div class="lbl"><span>Produção</span></div>
      <div class="stats">${outputLines(info, def, sel.x, sel.y).map((l) => `<span>${l}</span>`).join('') || '<span class="muted">Sem produção direta</span>'}</div>
      <div class="lbl"><span>Vizinhos</span><span class="${info.adjBonus > 0 ? 'pos' : info.adjBonus < 0 ? 'neg' : ''}">${fmtPct(info.adjBonus)}</span></div><ul class="adj">${adj}</ul>
      ${tile.b.dmg ? `<div class="row"><button class="btn ${canAfford(s.res, fix) ? 'primary' : 'poor'}" data-action="repair">${ico('build')} Consertar ${costHtml(fix, s.res)}</button></div>`
      : up ? `<div class="row"><button class="btn ${canAfford(s.res, up) ? 'primary' : 'poor'}" data-action="upgrade">${ico('upgrade')} Melhorar ${costHtml(up, s.res)}</button><span class="delta">${deltaText(upDelta)}</span></div>
      <div class="row"><button class="btn small" data-action="upgradeMax">Melhorar ao máximo possível</button>${sameType > 1 ? `<button class="btn small" data-action="upgradeAll">Melhorar todas as ${sameType} (${def.name})</button>` : ''}</div>` : '<p class="muted">Nível máximo.</p>'}
      <hr class="divider"><div class="row"><button class="btn small" data-action="move">${ico('move')} Mover</button><button class="btn small danger" data-action="sell">${ico('demolish')} Demolir</button></div>`;
  } else {
    const ter = TERRAIN[tile.t];
    const img = TERRAIN_SPRITES[tile.t]?.icon;
    html = `<div class="title-row">${img ? `<img src="${img}" alt="">` : ''}<h3>${ter.name}</h3></div>`;
    if (tile.ruin) html = `<div class="title-row"><img src="${RUIN_ICON}" alt=""><h3>Ruína</h3></div><p class="muted">${BUILDINGS[tile.ruin]?.name ?? 'Construção'} destruída por uma horda. Construa algo aqui para limpar o terreno.</p>`;
    if (tile.t === 'sapling') {
      const left = Math.max(0, GROW_SECONDS - (Date.now() - (tile.p ?? 0)) / 1000);
      html += `<p class="muted">Vira floresta em ${fmtTime(left)}. Floresta dá madeira ao ser limpa e +40% para serrarias vizinhas.</p>
      <button class="btn small danger" data-action="clear">${ico('clear')} Arrancar a muda</button>`;
    } else if (ter.clearCost) html += `<p class="muted">Pode ser limpo para construir, mas os vizinhos que gostam de ${ter.name.toLowerCase()} perdem o bônus.</p>
      <button class="btn ${canAfford(s.res, ter.clearCost) ? '' : 'poor'}" data-action="clear">${ico('clear')} Limpar ${costHtml(ter.clearCost, s.res)}, ganha ${costHtml(ter.clearYield)}</button>`;
    else if (ter.buildable) html += `<p class="muted">Terreno livre. Escolha uma construção na paleta, ou plante árvores: em ${fmtTime(GROW_SECONDS)} viram floresta.</p>
      <button class="btn ${canAfford(s.res, PLANT_COST) ? '' : 'poor'}" data-action="plant">${ico('emblem-tree')} Plantar árvores ${costHtml(PLANT_COST, s.res)}</button>`;
    else html += `<p class="muted">Não dá para construir aqui, mas vizinhos podem ganhar bônus com ${tile.t === 'water' ? 'a água' : 'a montanha'}.</p>`;
  }
  const full = `<button class="btn small icon-only x" data-action="closeTile" aria-label="Fechar">${ico('close')}</button>${html}`;
  if (!force && full === tileSig) return;
  tileSig = full;
  // Anima só quando abre ou troca de tile (não a cada atualização de números).
  const key = `${ui.renderer.layer}:${sel.x},${sel.y}`;
  const fresh = el.hidden || el.dataset.tile !== key;
  el.dataset.tile = key;
  el.hidden = false;
  el.innerHTML = full;
  if (fresh) { el.classList.remove('enter'); void el.offsetWidth; el.classList.add('enter'); }
}

// ================================================================ abas
const TAB_LIST = [['reino', 'castle'], ['herois', 'tab-heroes'], ['temporada', 'star'], ['legado', 'crowns'], ['social', 'tab-social'], ['perfil', 'tab-profile']];
let sideSig = '';

export function renderSide(force = false) {
  const g = ui.game;
  const side = $('#side-body');
  if (!force && side.contains(document.activeElement) && document.activeElement.matches('input, textarea, select')) return;
  if (!g.isTabUnlocked(ui.tab)) ui.tab = 'reino';
  const badge = {
    temporada: tierOf(g.state.season.xp) > g.state.season.claimed.filter((t) => t <= tierOf(g.state.season.xp)).length,
    reino: g.state.season.missions?.list.some((m) => !m.claimed && m.progress >= m.target) || g.dailyStatus().available,
    herois: Object.values(g.state.heroes.owned).some((h) => h.expedition && h.expedition.endsAt <= Date.now()) || g.state.items.scrolls > 0,
    legado: g.ascendAdvice().recommended,
  };
  const focusTab = tutorialFocus()?.tab;
  const tabsHtml = TAB_LIST.map(([id, icon]) => {
    const open = g.isTabUnlocked(id);
    return `<button role="tab" aria-selected="${ui.tab === id}" class="${ui.tab === id ? 'on' : ''} ${open ? '' : 'locked'}" data-action="${open ? 'tab' : 'lockedTab'}" data-arg="${id}">
      ${ico(open ? icon : 'lock')}<span>${TAB_NAMES[id]}</span>${open && (badge[id] || focusTab === id) ? '<i class="dot"></i>' : ''}</button>`;
  }).join('');
  setHtml($('#tabs'), tabsHtml);
  const html = { reino: tabReino, herois: tabHerois, temporada: tabTemporada, legado: tabLegado, social: tabSocial, perfil: tabPerfil }[ui.tab]();
  if (html !== sideSig || force) {
    const scroll = side.scrollTop;
    side.innerHTML = html;
    side.scrollTop = scroll;
    sideSig = html;
  }
}

export const lockedTabHint = (id) => TAB_UNLOCKS[id]?.hint ?? '';

function tabReino() {
  const g = ui.game;
  const s = g.state;
  const e = g.econ;
  const cost = g.expandCost();
  const daily = g.dailyStatus();
  const missions = s.season.missions?.list ?? [];
  return `
    <section class="card">
      <h3>${ico('mission')} Missões do dia <span class="count">${missions.filter((m) => m.claimed).length}/${missions.length}</span></h3>
      ${missions.map((m, i) => {
        const ready = !m.claimed && m.progress >= m.target;
        return `<div class="mission ${m.claimed ? 'done' : ''} ${ready ? 'ready' : ''}">
        <span>${esc(missionText(m))}</span>
        <div class="bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round((m.progress / m.target) * 100)}"><i style="width:${(m.progress / m.target) * 100}%"></i><em>${fmt(m.progress)}/${fmt(m.target)}</em></div>
        ${m.claimed ? `<span class="xp">${ico('check')} Feita</span>` : ready ? `<button class="btn small primary" data-action="claimMission" data-arg="${i}" title="+${m.xp} XP de temporada">Resgatar</button>` : `<span class="xp" title="Recompensa ao concluir">+${m.xp} XP</span>`}
      </div>`;
      }).join('')}
      <button class="btn ${daily.available ? 'primary' : ''}" data-action="showDaily">${ico('calendar')} ${daily.available ? 'Recompensa diária disponível' : `Recompensa diária · ${s.daily.streak} ${s.daily.streak === 1 ? 'dia seguido' : 'dias seguidos'}`}</button>
    </section>
    <section class="card">
      <h3>${ico('stats')} Economia</h3>
      <div class="grid2">
        <span>Ouro</span><b>${fmtRate(e.rates.gold)}</b>
        <span>Comida</span><b class="${e.rates.food < 0 ? 'neg' : ''}">${fmtRate(e.rates.food)}</b>
        <span>Madeira</span><b>${fmtRate(e.rates.wood)}</b>
        <span>Pedra</span><b>${fmtRate(e.rates.stone)}</b>
        <span>Trabalho</span><b class="${e.staffing < 1 ? 'neg' : ''}">${Math.round(e.staffing * 100)}% (${Math.floor(s.pop)}/${e.workersNeeded})</b>
        <span>Felicidade</span><b>${Math.floor(e.happiness)} (x${e.happinessMult.toFixed(2)})</b>
        <span>Defesa por lado</span><b>N ${fmt(e.defenseByDir.n)} · S ${fmt(e.defenseByDir.s)} · L ${fmt(e.defenseByDir.e)} · O ${fmt(e.defenseByDir.w)}</b>
        <span>Invasões</span><b>${s.stats.raidsWon} vitórias · nível ${s.raid.level}</b>
      </div>
      ${e.rates.food < 0 ? `<p class="warn">${ico('warning')} A comida está acabando. Sem comida, moradores vão embora e mercados param.</p>` : ''}
      ${e.marketRatio < 1 ? `<p class="warn">${ico('warning')} Mercados sem comida suficiente.</p>` : ''}
    </section>
    <section class="card">
      <h3>${ico('map')} Território</h3>
      ${cost ? `<p>Anel ${s.grid.ring} de 5. Próxima expansão:</p><button class="btn ${canAfford(s.res, cost) ? 'primary' : 'poor'}" data-action="expand">Expandir ${costHtml(cost, s.res)}</button>` : '<p>O mapa inteiro é seu.</p>'}
    </section>
    <section class="card">
      <h3>${ico('scroll')} Crônica do reino</h3>
      <ul class="log">${s.log.slice(0, 12).map((l) => `<li>${ico(l.icon || 'scroll')}<span>${esc(l.text)}</span></li>`).join('') || '<li class="muted">Nada aconteceu... ainda.</li>'}</ul>
    </section>`;
}

const starsHtml = (n) => `<span class="stars" aria-label="${n} de ${MAX_STARS} estrelas">${Array.from({ length: MAX_STARS }, (_, i) => ico('star', i < n ? '' : 'off')).join('')}</span>`;

export function describeBonus(type, v) {
  const [t, r] = type.split(':');
  const map = {
    prod: () => `+${Math.round(v * 100)}% de ${RESOURCES[r].name.toLowerCase()}`,
    prodAll: () => `+${Math.round(v * 100)}% em toda a produção`,
    defense: () => `+${Math.round(v * 100)}% de defesa`,
    happiness: () => `+${Math.round(v)} de felicidade`,
    expedition: () => `+${Math.round(v * 100)}% nas expedições`,
    cost: () => `-${Math.round(v * 100)}% no custo de obras`,
    raidLoot: () => `+${Math.round(v * 100)}% de saque`,
    terrainAdj: () => `+${Math.round(v * 100)}% na adjacência de terreno`,
    offline: () => `+${Math.round(v * 100)}% de eficiência offline`,
  };
  return (map[t] || (() => t))();
}

function tabHerois() {
  const g = ui.game;
  const s = g.state;
  const slots = councilSlots(g.econ.mods);
  const goldCost = recruitGoldCost(s);
  const now = Date.now();
  const owned = HEROES.filter((h) => s.heroes.owned[h.id]);
  const missing = HEROES.filter((h) => !s.heroes.owned[h.id]);
  const cap = heroLevelCap(s);
  const busy = trainingCount(s) >= trainingSlots(s);
  const trainHtml = (h, o) => {
    if (!trainingSlots(s)) return '';
    const lvl = o.level || 1;
    if (o.training) {
      const left = (o.training.endsAt - now) / 1000;
      return `<div class="row"><span>${ico('swords')} Treinando para o nível ${lvl + 1} · ${fmtTime(Math.max(0, left))}</span> <button class="btn small" data-action="speedupTrain" data-arg="${h.id}">${ico('speedup')} Acelerar (${speedUpCost(left)} ${resIco('gems')})</button></div>`;
    }
    if (o.expedition) return '';
    if (lvl >= HERO_MAX_LEVEL) return '';
    if (lvl >= cap) return `<p class="muted">${ico('lock')} Melhore o Quartel para treinar além do nível ${cap}.</p>`;
    const cost = trainCost(h, lvl);
    return `<div class="row"><button class="btn small wrap ${!busy && canAfford(s.res, cost) ? '' : 'poor'}" data-action="train" data-arg="${h.id}" ${busy ? 'title="Quartel ocupado"' : ''}>${ico('swords')} Treinar: nível ${lvl + 1} ${costHtml(cost, s.res)}</button></div>`;
  };
  const card = (h) => {
    const o = s.heroes.owned[h.id];
    const inCouncil = s.heroes.council.includes(h.id);
    let exp = '';
    if (o.expedition) {
      const left = (o.expedition.endsAt - now) / 1000;
      const ex = EXPEDITIONS.find((x) => x.id === o.expedition.id);
      exp = left <= 0
        ? `<button class="btn small primary" data-action="collect" data-arg="${h.id}">${ico('check')} Coletar: ${ex.name}</button>`
        : `<div class="row">${ico('expedition')} ${ex.name} · ${fmtTime(left)} <button class="btn small" data-action="speedup" data-arg="${h.id}">${ico('speedup')} Acelerar (${expeditionSpeedUpCost(left)} ${resIco('gems')})</button></div>`;
    } else if (!inCouncil && !o.training) {
      const full = activeExpeditions(s) >= expeditionSlots(s);
      exp = `<div class="lbl"><span>Enviar em expedição</span><span>${activeExpeditions(s)}/${expeditionSlots(s)} vagas</span></div><div class="row">${EXPEDITIONS.map((x) => `<button class="btn small ${full ? 'poor' : ''}" ${full ? 'title="Todas as vagas de expedição estão ocupadas"' : ''} data-action="expedition" data-arg="${h.id}|${x.id}" ${full ? '' : `title="${x.name}"`} aria-label="${x.name}, ${fmtTime(x.duration)}">${ico('expedition')} ${fmtTime(x.duration)}</button>`).join('')}</div>`;
    }
    return `<div class="hero" style="--rc:var(--${h.rarity})">
      <div class="portrait">${ico(h.icon)}</div>
      <div><span class="rar">${RARITIES[h.rarity].name}${inCouncil ? '<span class="badge-on">No Conselho</span>' : ''}</span><b>${h.name}</b> ${starsHtml(o.stars)}
        <small>Nível ${o.level || 1} · Poder ${heroPowerOf(h, o)} · ${describeBonus(h.bonus.type, h.bonus.value * heroStrength(o))}</small>
        <em>${esc(h.lore)}</em>
        ${o.expedition ? '' : `<div class="row"><button class="btn small ${inCouncil ? 'on' : ''}" data-action="council" data-arg="${h.id}">${inCouncil ? 'Tirar do Conselho' : 'Pôr no Conselho'}</button></div>`}
        ${exp}
        ${trainHtml(h, o)}
      </div></div>`;
  };
  return `
    <section class="card">
      <h3>${ico('scroll')} Recrutar herói</h3>
      <p class="muted">Chances: Comum 60%, Raro 28%, Épico 10%, Lendário 2%. Repetidos ganham estrelas. Tudo se ganha jogando.</p>
      ${tavernDiscount(s) > 0 ? `<p class="muted">${ico('happiness')} Taverna nível ${maxLevelOf(s, 'taverna')}: recrutar com ouro custa ${Math.round(tavernDiscount(s) * 100)}% menos.</p>` : ''}
      <div class="row">
        <button class="btn ${s.items.scrolls > 0 ? 'primary' : 'poor'}" data-action="recruit" data-arg="scroll">${ico('scroll')} Pergaminho (${s.items.scrolls})</button>
        <button class="btn ${s.res.gold >= goldCost ? '' : 'poor'}" data-action="recruit" data-arg="gold">${resIco('gold')} ${fmt(goldCost)}</button>
        <button class="btn ${s.res.gems >= RECRUIT_GEM_COST ? '' : 'poor'}" data-action="recruit" data-arg="gems">${resIco('gems')} ${RECRUIT_GEM_COST}</button>
      </div>
    </section>
    <section class="card">
      <h3>${ico('tab-heroes')} Conselho <span class="count">${s.heroes.council.length}/${slots} vagas</span></h3>
      <p class="muted">Heróis no Conselho dão bônus e defendem o reino de qualquer lado. Heróis fora dele podem partir em expedições (2 de cada vez). Tavernas de nível 5 e 10 abrem uma vaga a mais no Conselho e nas expedições.</p>
      <p class="muted">${trainingSlots(s) ? `${ico('swords')} Quartel: treina ${trainingSlots(s)} herói${trainingSlots(s) > 1 ? 's' : ''} por vez, até o nível ${cap}. Cada nível dá +10% de bônus e poder.` : `${ico('swords')} Construa um Quartel para treinar heróis.`}</p>
      ${owned.length ? owned.map(card).join('') : '<p class="muted">Nenhum herói ainda. Use o pergaminho grátis.</p>'}
      ${missing.length ? `<div class="collection">${missing.map((h) => `<span class="ghost" style="--rc:var(--${h.rarity})" title="${RARITIES[h.rarity].name}, ainda não encontrado">${ico('info')}</span>`).join('')}</div><p class="muted">${missing.length} heróis por descobrir.</p>` : '<p>Coleção completa.</p>'}
    </section>`;
}

function tabTemporada() {
  const g = ui.game;
  const s = g.state;
  const info = seasonInfo(Date.now());
  const tier = tierOf(s.season.xp);
  const into = s.season.xp - tier * XP_PER_TIER;
  const unclaimed = Array.from({ length: tier }, (_, i) => i + 1).filter((t) => !s.season.claimed.includes(t)).length;
  const kindIcon = (r) => ({ gems: 'gems', scroll: 'scroll', boost: 'boost', goldMinutes: 'gold', cosmetic: r.kind === 'title' ? 'trophy' : r.kind === 'banner' ? 'banner' : 'emblem-shield' }[r.type]);
  const tiers = Array.from({ length: SEASON_TIERS }, (_, i) => {
    const t = i + 1;
    const r = rewardFor(t, s);
    const claimed = s.season.claimed.includes(t);
    const reached = t <= tier;
    return `<button class="tier ${claimed ? 'claimed' : reached ? 'ready' : ''} ${r.type === 'cosmetic' ? 'special' : ''}" data-action="claimTier" data-arg="${t}" title="${esc(r.label)}" aria-label="Nível ${t}: ${esc(r.label)}">
      <b>${t}</b>${ico(kindIcon(r))}</button>`;
  }).join('');
  return `
    <section class="card">
      <h3>${ico(info.theme.icon)} Temporada ${info.number}: ${info.theme.name}</h3>
      <p>${info.theme.desc}</p>
      <p class="muted">Termina em ${fmtTime(info.remaining)}. A próxima traz outro modificador global.</p>
      <div class="bar big"><i style="width:${tier >= SEASON_TIERS ? 100 : (into / XP_PER_TIER) * 100}%"></i><em>Nível ${tier}/${SEASON_TIERS} · ${tier >= SEASON_TIERS ? 'máximo' : `${into}/${XP_PER_TIER} XP`}</em></div>
      ${unclaimed ? `<button class="btn primary" data-action="claimAllTiers">${ico('check')} Resgatar ${unclaimed} recompensa(s)</button>` : ''}
    </section>
    <section class="card"><h3>${ico('star')} Passe de temporada <span class="count">gratuito</span></h3><div class="tiers">${tiers}</div>
    <p class="muted">XP vem de construir, melhorar, vencer invasões, expedições, carroças, missões e da recompensa diária.</p></section>`;
}

function tabLegado() {
  const g = ui.game;
  const s = g.state;
  const adv = g.ascendAdvice();
  return `
    <section class="card">
      <h3>${resIco('crowns')} Ascensão</h3>
      <p>Recomece o reino num mapa novo com bônus permanentes. Coroas vêm do ouro ganho nesta rodada (${fmt(s.stats.runGold)}).</p>
      <div class="kpis"><div><small>Coroas guardadas</small><b class="big-num c-crowns">${s.res.crowns}</b></div><div><small>Ao ascender agora</small><b class="big-num ${adv.crowns >= 1 ? 'pos' : 'muted'}">+${adv.crowns}</b>${g.econ.crownBonus ? ` <small class="muted">templos +${Math.round(g.econ.crownBonus * 100)}%</small>` : ''}</div></div>
      <p class="${adv.recommended ? 'pos' : 'muted'}">${adv.recommended ? 'Recomendado: esta Ascensão pelo menos dobra as Coroas que você já conquistou.' : adv.crowns < 1 ? `A primeira Coroa chega com ${fmt(CROWN_DIVISOR)} de ouro na rodada.` : 'Ainda não dobra as suas Coroas; esperar rende mais.'}${Number.isFinite(adv.secondsToNext) ? ` Próxima Coroa em cerca de ${fmtTime(adv.secondsToNext)}.` : ''}</p>
      <button class="btn ${adv.crowns >= 1 ? 'primary' : 'poor'}" data-action="ascend">${resIco('crowns')} Ascender</button>
    </section>
    <section class="card"><h3>${ico('emblem-tree')} Árvore de Legado</h3>
      ${TALENTS.map((t) => {
        const lvl = s.legacy[t.id] || 0;
        const cost = g.talentCost(t.id);
        return `<div class="talent">${ico(t.icon)}<div><b>${t.name}</b>${t.max <= 10 ? `<span class="pips" aria-label="nível ${lvl} de ${t.max}">${Array.from({ length: t.max }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('')}</span>` : ` <small class="muted">${lvl}/${t.max}</small>`}<br><small>${t.desc(Math.max(1, lvl))}${lvl ? '' : ' (no nível 1)'}</small></div>
        ${cost == null ? `<span class="pos">${ico('check')}</span>` : `<button class="btn small ${s.res.crowns >= cost ? 'primary' : 'poor'}" data-action="talent" data-arg="${t.id}">${resIco('crowns')} ${cost}</button>`}</div>`;
      }).join('')}
      <p class="muted">Herança e Terras Ancestrais valem a partir da próxima Ascensão.</p>
    </section>
    ${runHistoryHtml(s.runs)}`;
}

function tabSocial() {
  const g = ui.game;
  const s = g.state;
  const list = g.rivals();
  const today = new Date();
  const key = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  return `
    <section class="card">
      <h3>${ico('trophy')} Ranking da região</h3>
      <ol class="rank">${list.map((r, i) => `<li class="${r.me ? 'me' : ''}">
        <span class="rk">${i + 1}</span><span class="banner sm" style="--bc:${bannerColor(r.banner)}">${ico(emblemIcon(r.emblem))}</span>
        <span><b>${esc(r.name)}</b><small>${esc(r.ruler)} · ${esc(r.title)}</small></span><b>${fmt(r.power)}</b>
        ${r.me ? '' : `<span class="ra">
          <button class="btn small" data-action="visit" data-arg="${r.id}">${ico('visit')} Visitar</button>
          <button class="btn small" data-action="greet" data-arg="${r.id}" ${s.social.greets[r.id] === key ? 'disabled' : ''}>${ico('greet')} Saudar</button>
          <button class="btn small" data-action="trade" data-arg="${r.id}|wood" title="Vende 25% da sua madeira por ouro (1 vez por hora)" aria-label="Vender madeira por ouro">${resIco('wood')}<i class="arr"></i>${resIco('gold')}</button>
          <button class="btn small" data-action="trade" data-arg="${r.id}|stone" title="Vende 25% da sua pedra por ouro (1 vez por hora)" aria-label="Vender pedra por ouro">${resIco('stone')}<i class="arr"></i>${resIco('gold')}</button>
        </span>`}</li>`).join('')}</ol>
      <p class="muted">Poder do Reino soma ouro da vida toda, prédios, heróis, Ascensões e vitórias.</p>
    </section>
    <section class="card">
      <h3>${ico('copy')} Compartilhe seu reino</h3>
      <p class="muted">Gere um código e mande para amigos: eles veem sua cidade exatamente como está.</p>
      <button class="btn primary" data-action="copyCode">${ico('copy')} Copiar código do meu reino</button>
      <label for="friendCode">Código de um amigo</label>
      <div class="row"><input type="text" id="friendCode" placeholder="RB1...."><button class="btn" data-action="visitCode">${ico('visit')} Visitar</button></div>
    </section>`;
}

function tabPerfil() {
  const g = ui.game;
  const s = g.state;
  const k = s.kingdom;
  const main = ACHIEVEMENTS.filter((a) => a.kind !== 'shadow');
  const got = main.filter((a) => s.achievements[a.id]).length;
  const shadows = ACHIEVEMENTS.filter((a) => a.kind === 'shadow');
  const next = g.nextAchievement();
  const achHtml = (a) => {
    const has = !!s.achievements[a.id];
    const hidden = a.kind && !has;
    const name = hidden ? '???' : a.name;
    const desc = hidden ? `Dica: ${a.hint}` : a.desc;
    const extra = `${a.gems ? ` · ${a.gems} gema${a.gems === 1 ? '' : 's'}` : ''}${a.title && !hidden ? ` · título "${a.title}"` : ''}`;
    const tag = has ? 'div' : 'button';
    return `<${tag} class="ach ${has ? 'got' : ''} ${a.kind || ''}" ${has ? '' : 'data-action="achLocked"'}>${ico(has ? a.icon : 'lock')}<b>${esc(name)}</b><small>${esc(desc)}${extra}</small></${tag}>`;
  };
  return `
    <section class="card">
      <h3>${ico('tab-profile')} Identidade</h3>
      <label for="kname">Nome do reino</label>
      <div class="row"><input type="text" id="kname" maxlength="24" value="${esc(k.name)}"><button class="btn" data-action="rename">Salvar</button></div>
      <h4>Estandarte</h4><div class="swatches">${BANNERS.map((b) => {
        const own = g.ownsCosmetic('banner', b.id);
        if (!own && b.season) return `<span class="sw locked" style="--bc:${b.color}" title="Recompensa de temporada">${ico('lock')}</span>`;
        return `<button class="sw ${k.banner === b.id ? 'on' : ''}" style="--bc:${b.color}" title="${b.name}" aria-label="Estandarte ${b.name}" data-action="${own ? 'equip' : 'buyCosmetic'}" data-arg="banner|${b.id}">${own ? '' : `<span class="price">${b.price} gemas</span>`}</button>`;
      }).join('')}</div>
      <h4>Emblema</h4><div class="swatches">${EMBLEMS.map((e) => {
        const own = g.ownsCosmetic('emblem', e.id);
        if (!own && e.season) return `<span class="sw em locked" title="Recompensa de temporada">${ico('lock')}</span>`;
        return `<button class="sw em ${k.emblem === e.id ? 'on' : ''}" aria-label="Emblema" data-action="${own ? 'equip' : 'buyCosmetic'}" data-arg="emblem|${e.id}">${ico(e.icon, 'lg')}${own ? '' : `<span class="price">${e.price} gemas</span>`}</button>`;
      }).join('')}</div>
      <h4>Título</h4><div class="row">${s.cosmetics.titles.map((t) => `<button class="btn small ${k.title === t ? 'on' : ''}" data-action="equip" data-arg="title|${esc(t)}">${esc(t)}</button>`).join('')}</div>
    </section>
    <section class="card">
      <h3>${ico('trophy')} Conquistas ${got}/${main.length}</h3>
      <p class="muted">Cada conquista dá +${Math.round(ACH_PROD_BONUS * 100)}% de produção para sempre. Bônus atual: <b class="pos">+${Math.round(got * ACH_PROD_BONUS * 100)}%</b>.</p>
      ${next ? `<div class="ach-next"><span>${ico(next.a.icon)} Próxima: <b>${esc(next.a.name)}</b> <small>${esc(next.a.desc)}</small></span><span class="bar"><i style="width:${Math.round(next.ratio * 100)}%"></i></span><small>${fmt(next.cur)} / ${fmt(next.goal)}</small></div>` : ''}
      <div class="achs">${main.map(achHtml).join('')}</div>
      <h4>Sombra <small class="muted">(não contam no total)</small></h4>
      <div class="achs">${shadows.map(achHtml).join('')}</div>
    </section>
    <section class="card">
      <h3>${resIco('gems')} Loja de Gemas</h3>
      <p class="muted">Você tem <b>${fmt(s.res.gems)}</b> gemas.</p>
      <div class="shop">${GEM_SHOP.map((i) => `<button class="shop-item ${s.res.gems >= i.gems ? '' : 'poor'}" data-action="buyShop" data-arg="${i.id}">${ico(i.icon)}<span>${esc(i.name)}</span><b>${resIco('gems')} ${i.gems}</b></button>`).join('')}</div>
      <h4>Comprar gemas</h4>
      <div class="shop">${GEM_PACKS.map((p) => `<button class="shop-item pack" data-action="buyGemPack" data-arg="${p.id}">${resIco('gems')}<span><b>${fmt(p.gems)} gemas</b> ${esc(p.name)}${p.tag ? ` <em class="tag">${esc(p.tag)}</em>` : ''}</span><b>${PAYMENTS_ENABLED ? esc(p.price) : 'Em breve'}</b></button>`).join('')}</div>
    </section>
    <section class="card">
      <h3>${ico('stats')} Estatísticas</h3>
      <div class="grid2">
        <span>Ouro (vida toda)</span><b>${fmt(s.stats.totalGold)}</b>
        <span>Construções erguidas</span><b>${s.stats.built}</b>
        <span>Invasões</span><b>${s.stats.raidsWon} vitórias, ${s.stats.raidsLost} derrotas</b>
        <span>Expedições</span><b>${s.stats.expeditions}</b>
        <span>Ascensões</span><b>${s.stats.ascensions}</b>
        <span>Tempo de jogo</span><b>${fmtTime(s.stats.playTime)}</b>
      </div>
    </section>
    <section class="card">
      <h3>${ico('settings')} Jogo</h3>
      <div class="row"><button class="btn" data-action="options">${ico('settings')} Opções</button><button class="btn" data-action="credits">${ico('info')} Créditos</button><button class="btn" data-action="saveMenu">${ico('save')} Save e backups</button></div>
    </section>`;
}
