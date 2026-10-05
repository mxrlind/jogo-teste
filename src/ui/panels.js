// HUD, paleta, painel do tile e abas do painel lateral. Só gera HTML/atualiza DOM; ações ficam em app.js.
import { BUILDINGS, BUILDING_ORDER, RESOURCES, TERRAIN } from '../data/buildings.js';
import { HEROES, RARITIES, EXPEDITIONS, RECRUIT_GEM_COST, MAX_STARS } from '../data/heroes.js';
import { TALENTS, CROWN_DIVISOR } from '../data/talents.js';
import { SEASON_TIERS, XP_PER_TIER } from '../data/seasons.js';
import { ACHIEVEMENTS } from '../data/achievements.js';
import { BANNERS, EMBLEMS } from '../data/cosmetics.js';
import { EVENT_BY_ID } from '../data/events.js';
import { TUTORIAL, TAB_UNLOCKS, TAB_NAMES, DIR_NAMES } from '../core/game.js';
import { buildCost, upgradeCost, canAfford, kingdomPower, heroMultiplier, storageMult, countOf, dirWeight } from '../core/economy.js';
import { idx, isUnlocked, ringOf } from '../core/map.js';
import { seasonInfo, tierOf, missionText, rewardFor } from '../core/season.js';
import { councilSlots, recruitGoldCost, speedUpCost } from '../core/heroes.js';
import { fmt, fmtRate, fmtPct, fmtTime } from '../core/format.js';
import { BUILDING_SPRITES, TERRAIN_SPRITES } from './sprites.js';
import { ui, $, esc, costHtml, bannerColor, emblemIcon, deltaText } from './ctx.js';
import { ico, resIco } from './icons.js';

const spriteOf = (id) => BUILDING_SPRITES[id]?.src;

// ================================================================ HUD
let hudBuilt = false;
const RES_LIST = ['gold', 'food', 'wood', 'stone'];

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
    <button class="status event" id="st-event" data-action="info" data-arg="event" hidden></button>
    <button class="status boost" id="st-boost" data-action="info" data-arg="boost" hidden></button>
    <button class="status ascend" id="st-ascend" data-action="tab" data-arg="legado" hidden></button>`;
  hudBuilt = true;
}

const setText = (el, t) => { if (el.textContent !== t) el.textContent = t; };
const setHtml = (el, h) => { if (el.dataset.h !== h) { el.innerHTML = h; el.dataset.h = h; } };

export function renderHud() {
  const g = ui.game;
  const s = g.state;
  const e = g.econ;
  if (!hudBuilt) buildHud();
  for (const r of RES_LIST) {
    const chip = $(`#chip-${r}`);
    const pct = Math.min(100, (s.res[r] / e.caps[r]) * 100);
    chip.classList.toggle('full', pct >= 99.5);
    chip.title = `${RESOURCES[r].name}: ${fmt(s.res[r])} de ${fmt(e.caps[r])}`;
    setText(chip.querySelector('.num'), fmt(s.res[r]));
    const rate = chip.querySelector('.rate');
    setText(rate, fmtRate(e.rates[r]));
    rate.classList.toggle('neg', e.rates[r] < 0);
    chip.querySelector('.bar').style.width = `${pct}%`;
  }
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
  setHtml(raid, `${ico(safe ? 'defense' : 'warning')}<span>Defesa <b>${fmt(e.defense)}</b> x <b>${fmt(strength)}</b> · ${DIR_NAMES[s.raid.dir]} · ${fmtTime(raidIn)}</span>`);
  const ev = s.event && s.event.endsAt > Date.now() ? EVENT_BY_ID[s.event.id] : null;
  const evEl = $('#st-event');
  evEl.hidden = !ev;
  if (ev) setHtml(evEl, `${ico(ev.icon)}<span>${ev.name} · ${fmtTime((s.event.endsAt - Date.now()) / 1000)}</span>`);
  const boostEl = $('#st-boost');
  boostEl.hidden = !(s.boostUntil > Date.now());
  if (!boostEl.hidden) setHtml(boostEl, `${ico('boost')}<span>Bênção +50% · ${fmtTime((s.boostUntil - Date.now()) / 1000)}</span>`);
  const adv = g.isTabUnlocked('legado') ? g.ascendAdvice() : null;
  const asc = $('#st-ascend');
  asc.hidden = !adv?.recommended;
  if (adv?.recommended) setHtml(asc, `${ico('crowns')}<span>Vale ascender: +${adv.crowns} ${adv.crowns === 1 ? 'Coroa' : 'Coroas'}</span>`);

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
    gems: 'Gemas só se ganham jogando: invasões vencidas, carroças, missões, conquistas, passe e expedições.',
    pop: `Moradores ${Math.floor(s.pop)} de ${e.popCap}. Os prédios pedem ${e.workersNeeded} trabalhadores; com menos, todos rendem ${Math.round(e.staffing * 100)}%.`,
    happiness: `Felicidade ${Math.floor(e.happiness)}: multiplica toda a produção por ${e.happinessMult.toFixed(2)}. Tavernas, templos e decorações aumentam; pedreiras, minas e superlotação reduzem.`,
    raid: `A próxima horda vem do ${DIR_NAMES[s.raid.dir]}. Torres e muralhas desse lado do mapa contam 100%; do lado oposto, 50%. Heróis do Conselho sempre contam inteiros.`,
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
  setHtml(el, `${ico('mission')}<b>Primeiros passos ${s.tutorial.step + 1}/${TUTORIAL.length}</b><span>${step.text}</span>`);
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
    setHtml(el, `<img src="${spriteOf(m.id)}" alt="" width="32" height="32"><span><b>${def.name}</b>: ${esc(def.desc)}${d ? `<br><span class="delta">Neste lugar: ${deltaText(d)}</span>` : '<br><span class="muted">Passe o mouse ou toque num tile para ver o ganho.</span>'}</span><button class="btn small" data-action="cancelMode">Cancelar</button>`);
  } else if (m.type === 'move') {
    el.hidden = false;
    setHtml(el, `${ico('move')}<span>Escolha o novo lugar (mover é grátis).</span><button class="btn small" data-action="cancelMode">Cancelar</button>`);
  } else el.hidden = true;
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
  const sig = JSON.stringify(items.map((i) => [i.avail, i.can, i.active, i.focus, i.cost]));
  if (!force && sig === paletteSig) return;
  paletteSig = sig;
  $('#palette').innerHTML = items.map((it) => {
    if (!it.avail) return `<button class="pb locked" data-action="lockedBuilding" data-arg="${it.id}" aria-label="${it.def.name}: bloqueado"><img src="${spriteOf(it.id)}" alt=""><span class="pn">${ico('lock')} ${it.def.name}</span><span class="pc">Libera com ${it.def.unlock.buildings} construções</span></button>`;
    return `<button class="pb ${it.can ? '' : 'poor'} ${it.active ? 'active' : ''} ${it.focus ? 'focus' : ''}" data-action="build" data-arg="${it.id}" aria-pressed="${it.active}">
      <img src="${spriteOf(it.id)}" alt=""><span class="pn">${it.def.name}${it.n <= 9 ? `<kbd>${it.n}</kbd>` : ''}</span><span class="pc">${costHtml(it.cost, s.res)}</span></button>`;
  }).join('');
}

// ================================================================ painel do tile
function outputLines(info, def, tileX, tileY) {
  const lines = [];
  for (const [r, v] of Object.entries(info.out || {})) lines.push(`${resIco(r)} ${fmtRate(v)}`);
  if (info.consume) lines.push(`${resIco('food')} -${fmt(info.consume)}/s`);
  if (info.defense) {
    const st = ui.game.state;
    lines.push(`${ico('defense', 'c-def')} ${fmt(info.defense)} defesa (contra o ${DIR_NAMES[st.raid.dir]}: ${Math.round(dirWeight(st.raid.dir, tileX, tileY) * 100)}%)`);
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
  if (!unlocked) {
    const cost = g.expandCost();
    const nextRing = ringOf(sel.x, sel.y) === s.grid.ring + 1;
    html = `<div class="title-row">${ico('map', 'lg')}<h3>Terra desconhecida</h3></div><p>Expanda o reino para conquistar o próximo anel de terra.</p>
      ${cost && nextRing ? `<button class="btn ${canAfford(s.res, cost) ? 'primary' : 'poor'}" data-action="expand">${ico('map')} Expandir ${costHtml(cost, s.res)}</button>` : '<p class="muted">Conquiste os anéis mais próximos primeiro.</p>'}`;
  } else if (tile.b) {
    const def = BUILDINGS[tile.b.id];
    const info = g.econ.tiles[idx(sel.x, sel.y)];
    const up = upgradeCost(tile.b.id, tile.b.lvl, g.econ.mods);
    const upDelta = up ? g.previewUpgrade(sel.x, sel.y) : null;
    const sameType = countOf(s, tile.b.id);
    const adj = info.adjParts.length
      ? info.adjParts.map((p) => `<li class="${p.value > 0 ? 'pos' : 'neg'}">${p.key in BUILDINGS ? BUILDINGS[p.key].name : TERRAIN[p.key].name} ${fmtPct(p.value)}</li>`).join('')
      : '<li class="muted">Nenhum vizinho com bônus</li>';
    const warn = !info.active ? `<p class="warn">${ico('warning')} Precisa estar encostada em ${TERRAIN[def.requiresAdj].name.toLowerCase()}.</p>`
      : info.workers > 0 && g.econ.staffing < 1 ? `<p class="warn">${ico('warning')} Faltam trabalhadores: rendendo ${Math.round(g.econ.staffing * 100)}%. Construa ou melhore casas.</p>` : '';
    html = `<div class="title-row"><img src="${spriteOf(tile.b.id)}" alt=""><h3>${def.name} <small class="muted">nível ${tile.b.lvl}</small></h3></div>
      <p class="muted">${esc(def.desc)}</p>${warn}
      <div class="stats">${outputLines(info, def, sel.x, sel.y).map((l) => `<span>${l}</span>`).join('')}</div>
      <p><b>Adjacência ${fmtPct(info.adjBonus)}</b></p><ul class="adj">${adj}</ul>
      ${up ? `<div class="row"><button class="btn ${canAfford(s.res, up) ? 'primary' : 'poor'}" data-action="upgrade">${ico('upgrade')} Melhorar ${costHtml(up, s.res)}</button><span class="delta">${deltaText(upDelta)}</span></div>
      <div class="row"><button class="btn small" data-action="upgradeMax">Melhorar ao máximo possível</button>${sameType > 1 ? `<button class="btn small" data-action="upgradeAll">Melhorar todas as ${sameType} (${def.name})</button>` : ''}</div>` : '<p class="muted">Nível máximo.</p>'}
      <div class="row"><button class="btn small" data-action="move">${ico('move')} Mover</button><button class="btn small danger" data-action="sell">${ico('demolish')} Demolir</button></div>`;
  } else {
    const ter = TERRAIN[tile.t];
    const img = TERRAIN_SPRITES[tile.t]?.base[0];
    html = `<div class="title-row">${img ? `<img src="${img}" alt="">` : ''}<h3>${ter.name}</h3></div>`;
    if (ter.clearCost) html += `<p class="muted">Pode ser limpo para construir, mas os vizinhos que gostam de ${ter.name.toLowerCase()} perdem o bônus.</p>
      <button class="btn ${canAfford(s.res, ter.clearCost) ? '' : 'poor'}" data-action="clear">${ico('clear')} Limpar ${costHtml(ter.clearCost, s.res)}, ganha ${costHtml(ter.clearYield)}</button>`;
    else if (ter.buildable) html += '<p class="muted">Terreno livre. Escolha uma construção na paleta.</p>';
    else html += `<p class="muted">Não dá para construir aqui, mas vizinhos podem ganhar bônus com ${tile.t === 'water' ? 'a água' : 'a montanha'}.</p>`;
  }
  const full = `<button class="btn small icon-only x" data-action="closeTile" aria-label="Fechar">${ico('close')}</button>${html}`;
  if (!force && full === tileSig) return;
  tileSig = full;
  el.hidden = false;
  el.innerHTML = full;
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
      <h3>${ico('mission')} Missões do dia</h3>
      ${missions.map((m, i) => `<div class="mission ${m.claimed ? 'done' : ''}">
        <span>${esc(missionText(m))}</span>
        <div class="bar" role="progressbar" aria-valuenow="${Math.round((m.progress / m.target) * 100)}"><i style="width:${(m.progress / m.target) * 100}%"></i><em>${fmt(m.progress)}/${fmt(m.target)}</em></div>
        ${m.claimed ? `<span class="pos">${ico('check')}</span>` : `<button class="btn small ${m.progress >= m.target ? 'primary' : ''}" data-action="claimMission" data-arg="${i}" ${m.progress >= m.target ? '' : 'disabled'}>+${m.xp} XP</button>`}
      </div>`).join('')}
      <button class="btn ${daily.available ? 'primary' : ''}" data-action="showDaily">${ico('calendar')} Recompensa diária ${daily.available ? '(disponível)' : `· sequência de ${s.daily.streak}`}</button>
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
  const card = (h) => {
    const o = s.heroes.owned[h.id];
    const inCouncil = s.heroes.council.includes(h.id);
    let exp = '';
    if (o.expedition) {
      const left = (o.expedition.endsAt - now) / 1000;
      const ex = EXPEDITIONS.find((x) => x.id === o.expedition.id);
      exp = left <= 0
        ? `<button class="btn small primary" data-action="collect" data-arg="${h.id}">${ico('check')} Coletar: ${ex.name}</button>`
        : `<div class="row">${ico('expedition')} ${ex.name} · ${fmtTime(left)} <button class="btn small" data-action="speedup" data-arg="${h.id}">${ico('speedup')} Acelerar (${speedUpCost(left)} ${resIco('gems')})</button></div>`;
    } else if (!inCouncil) {
      exp = `<div class="row">${EXPEDITIONS.map((x) => `<button class="btn small" data-action="expedition" data-arg="${h.id}|${x.id}" title="${x.name}">${ico('expedition')} ${fmtTime(x.duration)}</button>`).join('')}</div>`;
    }
    return `<div class="hero" style="--rc:var(--${h.rarity})">
      <div class="portrait">${ico(h.icon)}</div>
      <div><span class="rar">${RARITIES[h.rarity].name}</span> <b>${h.name}</b> ${starsHtml(o.stars)}
        <small>Poder ${h.power * o.stars} · ${describeBonus(h.bonus.type, h.bonus.value * heroMultiplier(o.stars))}</small>
        <em>${esc(h.lore)}</em>
        ${o.expedition ? '' : `<div class="row"><button class="btn small ${inCouncil ? 'on' : ''}" data-action="council" data-arg="${h.id}">${inCouncil ? 'No Conselho (tirar)' : 'Pôr no Conselho'}</button></div>`}
        ${exp}
      </div></div>`;
  };
  return `
    <section class="card">
      <h3>${ico('scroll')} Recrutar herói</h3>
      <p class="muted">Chances: Comum 60%, Raro 28%, Épico 10%, Lendário 2%. Repetidos ganham estrelas. Tudo se ganha jogando.</p>
      <div class="row">
        <button class="btn ${s.items.scrolls > 0 ? 'primary' : 'poor'}" data-action="recruit" data-arg="scroll">${ico('scroll')} Pergaminho (${s.items.scrolls})</button>
        <button class="btn ${s.res.gold >= goldCost ? '' : 'poor'}" data-action="recruit" data-arg="gold">${resIco('gold')} ${fmt(goldCost)}</button>
        <button class="btn ${s.res.gems >= RECRUIT_GEM_COST ? '' : 'poor'}" data-action="recruit" data-arg="gems">${resIco('gems')} ${RECRUIT_GEM_COST}</button>
      </div>
    </section>
    <section class="card">
      <h3>${ico('tab-heroes')} Conselho ${s.heroes.council.length}/${slots}</h3>
      <p class="muted">Heróis no Conselho dão bônus e defendem o reino de qualquer lado. Heróis fora dele podem partir em expedições.</p>
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
    <section class="card"><h3>${ico('star')} Passe de temporada (gratuito)</h3><div class="tiers">${tiers}</div>
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
      <p>Coroas guardadas: <b>${s.res.crowns}</b> · Ao ascender agora: <b>+${adv.crowns}</b>${g.econ.crownBonus ? ` <small class="muted">(templos +${Math.round(g.econ.crownBonus * 100)}%)</small>` : ''}</p>
      <p class="${adv.recommended ? 'pos' : 'muted'}">${adv.recommended ? 'Recomendado: esta Ascensão pelo menos dobra as Coroas que você já conquistou.' : adv.crowns < 1 ? `A primeira Coroa chega com ${fmt(CROWN_DIVISOR)} de ouro na rodada.` : 'Ainda não dobra as suas Coroas; esperar rende mais.'}${Number.isFinite(adv.secondsToNext) ? ` Próxima Coroa em cerca de ${fmtTime(adv.secondsToNext)}.` : ''}</p>
      <button class="btn ${adv.crowns >= 1 ? 'primary' : 'poor'}" data-action="ascend">${resIco('crowns')} Ascender</button>
    </section>
    <section class="card"><h3>${ico('emblem-tree')} Árvore de Legado</h3>
      ${TALENTS.map((t) => {
        const lvl = s.legacy[t.id] || 0;
        const cost = g.talentCost(t.id);
        return `<div class="talent">${ico(t.icon)}<div><b>${t.name}</b> <small class="muted">${lvl}/${t.max}</small><br><small>${t.desc(Math.max(1, lvl))}${lvl ? '' : ' (no nível 1)'}</small></div>
        ${cost == null ? `<span class="pos">${ico('check')}</span>` : `<button class="btn small ${s.res.crowns >= cost ? 'primary' : 'poor'}" data-action="talent" data-arg="${t.id}">${resIco('crowns')} ${cost}</button>`}</div>`;
      }).join('')}
      <p class="muted">Herança e Terras Ancestrais valem a partir da próxima Ascensão.</p>
    </section>`;
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
        <span class="pos">${i + 1}</span><span class="banner sm" style="--bc:${bannerColor(r.banner)}">${ico(emblemIcon(r.emblem))}</span>
        <span><b>${esc(r.name)}</b><small>${esc(r.ruler)} · ${esc(r.title)}</small></span><b>${fmt(r.power)}</b>
        ${r.me ? '' : `<span class="ra">
          <button class="btn small" data-action="visit" data-arg="${r.id}">${ico('visit')} Visitar</button>
          <button class="btn small" data-action="greet" data-arg="${r.id}" ${s.social.greets[r.id] === key ? 'disabled' : ''}>${ico('greet')} Saudar</button>
          <button class="btn small" data-action="trade" data-arg="${r.id}|wood" title="Troca 25% da madeira por ouro (1 vez por hora)">${resIco('wood')} por ${resIco('gold')}</button>
          <button class="btn small" data-action="trade" data-arg="${r.id}|stone" title="Troca 25% da pedra por ouro (1 vez por hora)">${resIco('stone')} por ${resIco('gold')}</button>
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
  const got = ACHIEVEMENTS.filter((a) => s.achievements[a.id]).length;
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
      <h3>${ico('trophy')} Conquistas ${got}/${ACHIEVEMENTS.length}</h3>
      <div class="achs">${ACHIEVEMENTS.map((a) => `<div class="ach ${s.achievements[a.id] ? 'got' : ''}">${ico(s.achievements[a.id] ? a.icon : 'lock')}<b>${a.name}</b><small>${esc(a.desc)} · ${a.gems} gemas${a.title ? ` · título "${a.title}"` : ''}</small></div>`).join('')}</div>
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
