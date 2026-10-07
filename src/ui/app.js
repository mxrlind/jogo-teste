// Controlador da interface: telas (carregamento, menu, jogo), ciclo do jogo, ações e teclado.
// Toda interação usa delegação: elementos com data-action="..." chamam ACTIONS[nome](el).
import { BUILDINGS, BUILDING_ORDER, RESOURCES } from '../data/buildings.js';
import { HERO_BY_ID, RARITIES } from '../data/heroes.js';
import { BANNERS, DAILY_REWARDS } from '../data/cosmetics.js';
import { SEASON_TIERS, XP_PER_TIER } from '../data/seasons.js';
import { LEVEL_NAMES } from '../data/underground.js';
import { RAID_LOSS_FRACTION } from '../data/events.js';
import { Game, DIR_NAMES, TAB_NAMES, UNDO_WINDOW } from '../core/game.js';
import { createState, newSeed, SAVE_VERSION } from '../core/state.js';
import { loadSave, writeSave, exportCode, importCode, listBackups, restoreBackup, clearSave, BACKUP_SLOTS } from '../core/storage.js';
import { CONFIG_KEY, KEY_ACTIONS, normalizeConfig, actionForKey, keyLabel } from '../core/config.js';
import { buildCost, canAfford, kingdomPower, heroStrength, heroPowerOf } from '../core/economy.js';
import { generateRivals, rivalGrid, encodeKingdom, decodeKingdom } from '../core/social.js';
import { fmt, fmtTime } from '../core/format.js';
import { MapRenderer } from './render.js';
import { showRunSummary } from './ascension.js';
import { preloadAll, iconKey, RES_COLORS } from './assets.js';
import { initAudio, loadSfx, play, setVolumes, hasMusic, musicInfo } from './audio.js';
import { ui, $, esc, bannerColor, emblemIcon } from './ctx.js';
import { ico, resIco } from './icons.js';
import { showModal, replaceModal, closeModal, confirmModal, runConfirm, toast, modalOpen, modalClosable } from './modals.js';
import { renderHud, renderPalette, renderTileInfo, renderSide, renderModeHint, hudInfo, lockedTabHint, describeBonus } from './panels.js';

const GAME_VERSION = '0.12.0';
const TAB_ORDER = ['reino', 'herois', 'temporada', 'legado', 'social', 'perfil'];
const FLOAT_COLORS = RES_COLORS;

// localStorage pode lançar exceção (modo privado, cota cheia): o jogo segue em memória.
const memory = new Map();
const store = {
  getItem: (k) => { try { return localStorage.getItem(k); } catch { return memory.get(k) ?? null; } },
  setItem: (k, v) => { try { localStorage.setItem(k, v); } catch { memory.set(k, v); } },
  removeItem: (k) => { try { localStorage.removeItem(k); } catch { memory.delete(k); } },
};

let loaded = null; // resultado de loadSave no boot
let loopsStarted = false;
let lastSave = 0;
let menuRenderer = null;
let menuGrid = null;
let remapping = null;
let lastModeExit = 0; // Esc logo após sair de um modo não deve abrir o menu (achado do teste com jogador novo)

// ================================================================ boot
export async function boot() {
  let rawConfig = null;
  try { rawConfig = JSON.parse(store.getItem(CONFIG_KEY) || 'null'); } catch { rawConfig = null; }
  loaded = loadSave(store);
  ui.config = normalizeConfig(rawConfig, rawConfig ? null : loaded.legacySettings);
  if (!rawConfig && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) ui.config.reduceMotion = true;
  saveConfig();
  applyConfig();

  document.addEventListener('click', onClick);
  document.addEventListener('keydown', onKey);
  document.addEventListener('input', onInput);
  document.addEventListener('pointerdown', () => { ui.pointerHeld = true; }, true);
  document.addEventListener('pointerup', () => { ui.pointerHeld = false; }, true);
  document.addEventListener('pointercancel', () => { ui.pointerHeld = false; }, true);
  // Soltar o botão fora da janela não gera pointerup: sem isto o painel lateral parava de atualizar.
  window.addEventListener('blur', () => { ui.pointerHeld = false; });
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('beforeunload', save);
  window.addEventListener('pagehide', save); // celulares nem sempre disparam beforeunload
  $('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal' && modalClosable()) closeModal(); });

  initAudio(ui.config);
  let imgDone = 0; let imgTotal = 1; let sfxDone = 0; let sfxTotal = 1;
  const progress = () => {
    const p = Math.round(((imgDone + sfxDone) / (imgTotal + sfxTotal)) * 100);
    $('#loadBar').style.width = `${p}%`;
    $('#loading .progress').setAttribute('aria-valuenow', String(p));
    $('#loadText').textContent = `Carregando assets... ${p}%`;
  };
  const uiImages = ['assets/ui/kenney-ui-pack/yellow_button00.png', 'assets/ui/kenney-ui-pack/grey_button00.png'];
  await Promise.all([
    preloadAll(uiImages, (d, t) => { imgDone = d; imgTotal = t; progress(); }),
    loadSfx((d, t) => { sfxDone = d; sfxTotal = t; progress(); }),
  ]);
  if (new URLSearchParams(location.search).has('debug')) window.reino = { ui, save, store };
  showMainMenu();
  registerServiceWorker();
}

function saveConfig() {
  store.setItem(CONFIG_KEY, JSON.stringify(ui.config));
}

function applyConfig() {
  const c = ui.config;
  document.documentElement.style.setProperty('--fs', String(c.fontScale));
  document.body.classList.toggle('high-contrast', c.highContrast);
  document.body.classList.toggle('reduce-motion', c.reduceMotion);
  setVolumes(c.musicVolume, c.sfxVolume);
}

function save() {
  if (!ui.game) return;
  try {
    writeSave(store, ui.game.state);
    lastSave = Date.now();
  } catch (err) {
    console.warn('Falha ao salvar', err);
    toast('Não foi possível salvar (armazenamento cheio ou bloqueado). Exporte o save pelo menu.', 'bad', 'warning');
  }
}

function registerServiceWorker() {
  // Só em HTTPS publicado (GitHub Pages); em localhost o cache atrapalharia o desenvolvimento.
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}

function setScreen(name) {
  for (const id of ['loading', 'mainMenu', 'game']) $(`#${id}`).hidden = id !== name;
  document.body.className = `${document.body.className.replace(/screen-\S+/g, '').trim()} screen-${name}`.trim();
  applyConfig();
}

// ================================================================ menu principal
function showMainMenu() {
  setScreen('mainMenu');
  const st = ui.game?.state ?? loaded?.state;
  const has = Boolean(st);
  $('#menuButtons').innerHTML = `
    ${has ? `<button class="btn big primary" data-action="continue">${ico('play')} Continuar: ${esc(st.kingdom.name)}</button>` : ''}
    <button class="btn big ${has ? '' : 'primary'}" data-action="newGame">${ico('build')} Novo reino</button>
    <button class="btn big" data-action="howTo">${ico('info')} Como jogar</button>
    <div class="row"><button class="btn" style="flex:1" data-action="options">${ico('settings')} Opções</button><button class="btn" style="flex:1" data-action="credits">${ico('scroll')} Créditos</button></div>`;
  $('#menuVersion').textContent = `Versão ${GAME_VERSION}`;
  $('#menuVersion').title = `Formato de save v${SAVE_VERSION}${hasMusic() ? '' : ' · nenhuma música instalada (ver EXECUTAR.md)'}`;
  $('#menuButtons button')?.focus({ preventScroll: true });
  if (loaded?.recovered && loaded.state) toast(`O save principal estava danificado; recuperamos o backup (${loaded.source}). A cópia danificada foi guardada.`, 'bad', 'warning');
  else if (loaded?.recovered) toast('O save estava danificado e não havia backup íntegro. A cópia danificada foi guardada.', 'bad', 'warning');
  if (loaded) loaded.recovered = false;

  // O fundo do menu é estático e fica borrado: desenha uma vez (e de novo só se a janela mudar de tamanho).
  // Antes era redesenhado a 60 fps, com um filtro de desfoque em tela cheia por cima.
  const canvas = $('#menuMap');
  canvas.dataset.fill = 'cover';
  menuGrid = st ? st.grid : rivalGrid(generateRivals(7, Date.now(), Date.now())[6]);
  if (!menuRenderer) menuRenderer = new MapRenderer(canvas, { getConfig: () => ui.config, onResize: drawMenuMap });
  menuRenderer.view = { grid: menuGrid };
  drawMenuMap();
}

function drawMenuMap() {
  if (!menuRenderer || !menuGrid || $('#mainMenu').hidden) return;
  // Os sprites já foram pré-carregados; o próximo frame garante que o canvas já tem o tamanho final.
  requestAnimationFrame(() => menuRenderer.draw({ state: { grid: menuGrid } }));
}

// Rosa dos ventos no canto superior direito do mapa: ao lado dele quando sobra espaço, senão por cima do canto.
function placeCompass() {
  const c = $('#compass');
  const map = $('#map');
  const wrap = map.parentElement;
  const right = map.offsetLeft + map.offsetWidth;
  const outside = wrap.clientWidth - right >= c.offsetWidth + 14;
  c.classList.toggle('outside', outside);
  c.style.left = `${outside ? right + 10 : right - c.offsetWidth - 8}px`;
  c.style.top = `${map.offsetTop + (outside ? 0 : 8)}px`;
  // Botões de nível: à esquerda do mapa quando sobra espaço, senão por cima do canto.
  const l = $('#layers');
  const lw = l.offsetWidth || 46;
  const lOut = map.offsetLeft >= lw + 14;
  l.style.left = `${lOut ? map.offsetLeft - lw - 10 : map.offsetLeft + 8}px`;
  l.style.top = `${map.offsetTop + (lOut ? 0 : 8)}px`;
}

function startGame(state, { isNew = false } = {}) {
  if (!ui.game) {
    ui.game = new Game(state);
    wireGame();
  } else {
    ui.game.state = state;
  }
  setScreen('game');
  if (!ui.renderer) {
    ui.renderer = new MapRenderer($('#map'), { onTileClick: tileClick, onHover, onResize: placeCompass, getConfig: () => ui.config });
  }
  ui.renderer.resize();
  ui.renderer.selected = null;
  ui.renderer.cursor = null;
  setMode({ type: 'select' });
  ui.game.tick(Date.now());
  save();
  ui.renderer.layer = 0;
  document.body.dataset.layer = 0;
  renderLayers();
  renderAll();
  if (!loopsStarted) startLoops();
  if (isNew) showIntro();
  else if (ui.game.dailyStatus().available) showDaily();
}

function startLoops() {
  loopsStarted = true;
  const gameEl = $('#game');
  setInterval(() => {
    if (!ui.game || gameEl.hidden) return;
    ui.game.tick(Date.now(), { background: document.hidden });
    renderHud();
    renderUndo();
    if (Date.now() - lastSave > 10000) save();
  }, 250);
  setInterval(() => {
    if (!ui.game || gameEl.hidden || ui.pointerHeld) return;
    renderSide();
    renderPalette();
    renderLayers();
    renderTileInfo();
    ambientFx();
  }, 1000);
  const loop = () => {
    if (ui.game && !gameEl.hidden) ui.renderer.draw(ui.game);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}

function onVisibility() {
  if (!ui.game || $('#game').hidden) return;
  if (document.hidden) save();
  else ui.game.tick(Date.now(), { background: true });
}

function renderAll() {
  endVisit();
  renderPalette(true);
  renderHud();
  renderSide(true);
  renderTileInfo(true);
  renderModeHint();
}

// ================================================================ eventos do motor -> som, efeitos, avisos
function wireGame() {
  const r = () => ui.renderer;
  ui.game
    .on('toast', ({ text, kind, icon }) => toast(text, kind, icon))
    .on('built', ({ x, y, id }) => { play(id === 'mina' || id === 'pedreira' ? 'mine' : 'build'); r().pop(x, y); r().addBurst(x, y, '#fff3bf'); })
    .on('repaired', ({ x, y }) => { play('build', 0.8); r().pop(x, y); r().addBurst(x, y, '#fff3bf'); })
    .on('upgraded', ({ x, y, lvl }) => { play('upgrade', 0.8); r().pop(x, y); r().addFloat(x, y, `Nível ${lvl}`, '#ffe08a'); })
    .on('sold', ({ name }) => toast(`${name} demolida (50% devolvido).`, 'info', 'demolish'))
    .on('moved', ({ tx, ty }) => { play('build', 0.6); r().pop(tx, ty); })
    .on('undone', ({ id, x, y }) => { play('close'); r().addBurst(x, y, '#d7dde0'); toast(`Obra desfeita (${BUILDINGS[id].name}): custo devolvido por inteiro.`, 'info', 'time'); })
    .on('cleared', ({ x, y, yieldRes }) => { play('chop'); for (const [res, v] of Object.entries(yieldRes)) r().addFloat(x, y, `+${fmt(v)}`, FLOAT_COLORS[res], iconKey(res, FLOAT_COLORS[res])); })
    .on('planted', ({ x, y }) => { play('build', 0.6); r().addBurst(x, y, '#b2f2bb'); })
    .on('grown', ({ n }) => toast(n > 1 ? `${n} mudas viraram floresta.` : 'Uma muda virou floresta.', 'good', 'emblem-tree'))
    .on('underOpened', () => { renderLayers(); toast('A Escadaria chegou ao subsolo! Use os botões no canto do mapa para descer.', 'good', 'tool-pickaxe'); })
    .on('dug', ({ d, x, y, yieldRes, cavern }) => {
      play('mine');
      if (r().layer === d) {
        r().addBurst(x, y, '#d7c4a8');
        for (const [res, v] of Object.entries(yieldRes)) r().addFloat(x, y, `+${fmt(v)}`, FLOAT_COLORS[res] ?? '#7cc6f0', iconKey(res, FLOAT_COLORS[res] ?? '#7cc6f0'));
      }
      if (cavern) { r().doShake(400); toast(`Os mineiros romperam uma caverna! ${cavern} tiles revelados.`, 'good', 'tool-pickaxe'); }
    })
    .on('stairs', ({ d, x, y, first }) => {
      play('win');
      renderLayers();
      if (first) toast(`Nível novo descoberto: ${LEVEL_NAMES[d]}.`, 'good', 'tool-pickaxe');
      setLayer(d + 1);
      r().selected = { x, y };
      renderTileInfo(true);
    })
    .on('roomBuilt', ({ d, x, y }) => { play('build'); r().popUnder(d, x, y); r().addBurst(x, y, '#fff3bf'); })
    .on('roomUpgraded', ({ d, x, y, lvl }) => { play('upgrade', 0.8); r().popUnder(d, x, y); r().addFloat(x, y, `Nível ${lvl}`, '#ffe08a'); })
    .on('expanded', ({ ring }) => { play('win'); toast(`Novas terras conquistadas (anel ${ring}).`, 'good', 'map'); })
    .on('raidWarning', ({ name, strength, defense, dir }) => {
      play('warn');
      toast(`${name} se aproximam pelo ${DIR_NAMES[dir]}! Força ${strength} contra sua defesa ${Math.floor(defense)} desse lado.`, defense >= strength ? 'info' : 'bad', 'swords');
    })
    .on('raid', (res) => {
      const next = DIR_NAMES[ui.game.state.raid.dir];
      if (res.win) { play('win'); r().doFlash('#f2b632'); toast(`Vitória sobre ${res.name}! +${fmt(res.loot)} de ouro e +${res.gems} gema(s). A próxima horda vem do ${next}.`, 'good', 'swords'); return; }
      play('lose'); r().doShake(650); r().doFlash('#b8412f');
      const lost = Object.entries(res.lost).filter(([, v]) => v > 0).map(([k, v]) => `${fmt(v)} de ${RESOURCES[k].name.toLowerCase()}`).join(', ');
      const broke = [
        res.damaged?.length ? `danificaram ${res.damaged.length === 1 ? '1 construção' : `${res.damaged.length} construções`}` : '',
        res.collapsed?.length ? (res.collapsed.length === 1 ? '1 que não foi consertada desabou' : `${res.collapsed.length} que não foram consertadas desabaram`) : '',
      ].filter(Boolean).join(' e ');
      for (const d of res.damaged || []) r().addBurst(d.x, d.y, '#ff8f7d');
      for (const d of res.collapsed || []) r().addBurst(d.x, d.y, '#8a8a8a');
      toast(`${res.name} saquearam ${lost || 'quase nada'}${broke ? ` e ${broke}` : ''}${res.fraction < RAID_LOSS_FRACTION ? ' (proteção de novato)' : ''}. A próxima horda vem do ${next}.`, 'bad', 'warning');
    })
    .on('event', (ev) => { play('event'); toast(`${ev.name}: ${ev.desc}`, 'event', ev.icon); })
    .on('chest', () => play('cart', 0.6))
    .on('chestOpened', ({ reward, x, y }) => {
      play('cart');
      r().addBurst(x, y);
      if (reward.boost) r().addFloat(x, y, `Bênção ${reward.boost} min`, '#ffe08a', iconKey('boost', '#ffe08a'));
      else Object.entries(reward).forEach(([res, v], i) => setTimeout(() => r().addFloat(x, y, `+${fmt(v)}`, FLOAT_COLORS[res], iconKey(res, FLOAT_COLORS[res])), i * 200));
    })
    .on('recruited', (res) => showRecruit(res))
    .on('expeditionStart', () => play('expedition'))
    .on('expeditionDone', ({ hid, reward }) => {
      play('coin');
      const parts = [`${fmt(reward.gold)} de ouro`, `${fmt(reward.wood)} de madeira`, `${fmt(reward.stone)} de pedra`];
      if (reward.gems) parts.push(`${reward.gems} gema(s)`);
      if (reward.scrolls) parts.push('1 pergaminho');
      toast(`Expedição de ${HERO_BY_ID[hid].name}: ${parts.join(', ')}.`, 'good', 'expedition');
    })
    .on('tierUp', ({ tier }) => { play('tier'); toast(`Passe de temporada: nível ${tier}! Resgate na aba Temporada.`, 'season', 'star'); })
    .on('achievement', (a) => { play('achievement'); toast(`Conquista: ${a.name} (+${a.gems} gemas${a.title ? `, título "${a.title}"` : ''})`, 'good', a.icon); })
    .on('tutorial', () => { play('confirm'); renderPalette(true); renderSide(true); })
    .on('unlock', ({ tab, name }) => { play('tier'); toast(`Nova aba aberta: ${name}.`, 'season', 'star'); if (tab === 'herois') ui.tab = 'herois'; renderSide(true); })
    .on('offline', (sum) => showOffline(sum))
    .on('background', (sum) => {
      if (sum.elapsed >= 60) toast(`Com a aba em segundo plano (${fmtTime(sum.elapsed)}): +${fmt(Math.max(0, sum.gains.gold))} de ouro.`, 'info', 'time');
    })
    .on('ascended', ({ summary }) => { play('ascend'); ui.renderer.doFlash('#f2b632', 1000); renderAll(); showRunSummary(summary, { fresh: true }); });
}

// ================================================================ mapa: clique e hover
function tileClick(x, y) {
  if (ui.visiting) return;
  if (ui.renderer.layer > 0) {
    // Subsolo: o clique só seleciona; cavar e construir ficam no painel do tile.
    play('click', 0.6);
    const sel = ui.renderer.selected;
    ui.renderer.selected = sel && sel.x === x && sel.y === y ? null : { x, y };
    renderTileInfo(true);
    return;
  }
  const g = ui.game;
  const s = g.state;
  const mode = ui.renderer.mode;
  if (s.chest && s.chest.x === x && s.chest.y === y && mode.type === 'select') { g.openChest(); return; }
  if (mode.type === 'build') {
    const res = g.build(mode.id, x, y);
    if (!res.ok) { play('error'); toast(res.reason, 'bad', 'warning'); return; }
    if (!canAfford(s.res, buildCost(s, mode.id, g.econ.mods))) setMode({ type: 'select' });
    ui.hoverDelta = null;
    renderPalette();
    renderModeHint();
    renderUndo();
    return;
  }
  if (mode.type === 'move') {
    const res = g.move(mode.from.x, mode.from.y, x, y);
    if (!res.ok) { play('error'); toast(res.reason, 'bad', 'warning'); return; }
    ui.renderer.selected = { x, y };
    setMode({ type: 'select' });
    renderTileInfo(true);
    return;
  }
  play('click', 0.6);
  const sel = ui.renderer.selected;
  ui.renderer.selected = sel && sel.x === x && sel.y === y ? null : { x, y };
  renderTileInfo(true);
}

function onHover(t) {
  const m = ui.renderer?.mode;
  ui.hoverDelta = null;
  if (t && m?.type === 'build') {
    const tile = ui.game.tileAt(t.x, t.y);
    if (tile.t === 'grass' && !tile.b) ui.hoverDelta = ui.game.previewBuild(m.id, t.x, t.y);
  }
  renderModeHint();
}

function setMode(mode) {
  if (mode.type === 'select' && ui.renderer.mode?.type !== 'select') lastModeExit = Date.now();
  ui.renderer.mode = mode;
  document.body.dataset.mode = mode.type;
  ui.hoverDelta = null;
  renderPalette(true);
  renderModeHint();
}

function selectBuild(id) {
  if (ui.visiting) { endVisit(); refreshAfterVisit(); }
  if (ui.renderer.layer > 0) setLayer(0);
  if (ui.renderer.mode.type === 'build' && ui.renderer.mode.id === id) setMode({ type: 'select' });
  else { ui.renderer.selected = null; setMode({ type: 'build', id }); renderTileInfo(true); }
  play('click', 0.6);
}

// ================================================================ teclado (remapeável)
function onKey(e) {
  const key = e.key.toLowerCase();
  if (remapping) {
    e.preventDefault();
    if (key !== 'escape') {
      const clash = actionForKey(ui.config, key);
      if (clash && clash !== remapping) ui.config.keys[clash] = ui.config.keys[remapping];
      ui.config.keys[remapping] = key;
      saveConfig();
    }
    remapping = null;
    showOptions(true);
    return;
  }
  if (e.target.matches?.('input, textarea, select')) return;
  const action = actionForKey(ui.config, key);
  if (action === 'menu') {
    e.preventDefault();
    if (modalOpen()) { if (modalClosable()) closeModal(); return; }
    if ($('#game').hidden || !ui.game) return;
    const r = ui.renderer;
    if (ui.visiting) { endVisit(); refreshAfterVisit(); return; }
    if (r.mode.type !== 'select' || r.selected || r.cursor) {
      setMode({ type: 'select' }); r.selected = null; r.cursor = null; renderTileInfo(true); return;
    }
    if (Date.now() - lastModeExit < 1500) return;
    showGameMenu();
    return;
  }
  if (modalOpen() || $('#game').hidden || !ui.game) return;
  const r = ui.renderer;
  const moveCursor = (dx, dy) => {
    e.preventDefault();
    const c = r.cursor ?? r.selected ?? { x: 5, y: 5 };
    r.cursor = { x: Math.max(0, Math.min(11, c.x + dx)), y: Math.max(0, Math.min(11, c.y + dy)) };
    onHover(r.cursor);
    $('#map').focus({ preventScroll: true });
  };
  if (action === 'up') return moveCursor(0, -1);
  if (action === 'down') return moveCursor(0, 1);
  if (action === 'left') return moveCursor(-1, 0);
  if (action === 'right') return moveCursor(1, 0);
  if (action === 'confirm' && r.cursor && document.activeElement === $('#map')) {
    e.preventDefault();
    const c = r.cursor;
    tileClick(c.x, c.y);
    r.cursor = c;
    return;
  }
  if (action === 'undo' && ui.game.canUndo(Date.now())) { e.preventDefault(); ACTIONS.undo(); return; }
  const selB = r.layer === 0 && r.selected && ui.game.tileAt(r.selected.x, r.selected.y).b;
  if (action === 'upgrade' && selB) return ACTIONS.upgrade();
  if (action === 'move' && selB) return ACTIONS.move();
  if (action === 'sell' && selB) return ACTIONS.sell();
  if (action === 'nextTab') {
    const open = TAB_ORDER.filter((t) => ui.game.isTabUnlocked(t));
    ui.tab = open[(open.indexOf(ui.tab) + 1) % open.length];
    play('tab', 0.6);
    renderSide(true);
    return;
  }
  const n = Number(e.key);
  if (n >= 1 && n <= 9) {
    const ids = BUILDING_ORDER.filter((id) => ui.game.isAvailable(id));
    if (ids[n - 1]) selectBuild(ids[n - 1]);
  }
}

// ================================================================ ações (data-action)
function result(res, okMsg) {
  if (!res.ok) { play('error'); if (res.reason) toast(res.reason, 'bad', 'warning'); return false; }
  if (okMsg) toast(okMsg, 'good', 'check');
  renderSide(true);
  renderHud();
  renderTileInfo(true);
  renderPalette();
  return true;
}

const ACTIONS = {
  // menu e telas
  continue: () => {
    play('confirm');
    const st = ui.game?.state ?? loaded?.state;
    loaded = null;
    startGame(st);
  },
  newGame: () => {
    const has = Boolean(ui.game || loaded?.state);
    const go = () => { loaded = null; startGame(createState({ seed: newSeed() }), { isNew: true }); };
    if (has) confirmModal(`<h2>${ico('warning')} Começar um reino novo?</h2><p>O reino atual será substituído. Os backups automáticos ficam guardados em Save e backups.</p>`, go, { yes: 'Começar de novo', danger: true });
    else go();
  },
  howTo: () => showHowTo(),
  gameMenu: () => showGameMenu(),
  toMainMenu: () => { save(); closeModal(); showMainMenu(); },
  options: () => showOptions(),
  credits: () => showCredits(),
  saveMenu: () => showSaveMenu(),
  closeModal: () => { play('close', 0.5); closeModal(); },
  confirmYes: () => runConfirm(),
  info: (el) => { const t = hudInfo(el.dataset.arg); if (t) toast(t, 'info', 'info'); },

  // paleta e mapa
  build: (el) => selectBuild(el.dataset.arg),
  lockedBuilding: (el) => { const d = BUILDINGS[el.dataset.arg]; toast(`${d.name}: libera com ${d.unlock.buildings} construções. ${d.desc}`, 'info', 'lock'); },
  cancelMode: () => setMode({ type: 'select' }),
  upgrade: () => { const { x, y } = ui.renderer.selected; result(ui.game.upgrade(x, y)); },
  repair: () => { const { x, y } = ui.renderer.selected; result(ui.game.repair(x, y)); },
  repairAll: () => {
    const res = ui.game.repairAll();
    if (!res.ok) { play('error'); toast(res.reason, 'bad', 'warning'); return; }
    toast(res.left ? `${res.count} consertada(s). Faltam recursos para mais ${res.left}.` : res.count === 1 ? 'Construção consertada.' : `${res.count} construções consertadas.`, 'good', 'build');
    result({ ok: true });
  },
  upgradeMax: () => {
    const { x, y } = ui.renderer.selected;
    const n = ui.game.upgradeMax(x, y);
    if (!n) { play('error'); toast('Recursos insuficientes.', 'bad', 'warning'); return; }
    toast(`Subiu ${n} nível(is).`, 'good', 'upgrade');
    result({ ok: true });
  },
  upgradeAll: () => {
    const { x, y } = ui.renderer.selected;
    const id = ui.game.tileAt(x, y).b.id;
    const n = ui.game.upgradeAll(id);
    if (!n) { play('error'); toast('Recursos insuficientes.', 'bad', 'warning'); return; }
    toast(`${n} melhoria(s) em ${BUILDINGS[id].name}.`, 'good', 'upgrade');
    result({ ok: true });
  },
  move: () => setMode({ type: 'move', from: { ...ui.renderer.selected } }),
  undo: () => {
    const u = ui.game.lastBuild;
    const res = ui.game.undoBuild();
    if (res.ok && u && ui.renderer.selected?.x === u.x && ui.renderer.selected?.y === u.y) ui.renderer.selected = null;
    result(res);
    renderUndo();
  },
  sell: () => {
    const { x, y } = ui.renderer.selected;
    confirmModal(`<h2>${ico('demolish')} Demolir?</h2><p>Você recebe 50% do que gastou de volta.</p>`, () => { result(ui.game.sell(x, y)); ui.renderer.selected = null; renderTileInfo(true); }, { yes: 'Demolir', danger: true });
  },
  clear: () => { const { x, y } = ui.renderer.selected; result(ui.game.clear(x, y)); },
  layer: (el) => { play('tab', 0.6); setLayer(Number(el.dataset.arg)); },
  dig: () => { const { x, y } = ui.renderer.selected; result(ui.game.dig(ui.renderer.layer, x, y)); },
  digStairs: () => { const { x, y } = ui.renderer.selected; result(ui.game.digStairs(ui.renderer.layer, x, y)); },
  room: (el) => { const { x, y } = ui.renderer.selected; result(ui.game.buildRoom(ui.renderer.layer, x, y, el.dataset.arg)); },
  roomUp: () => { const { x, y } = ui.renderer.selected; result(ui.game.upgradeRoom(ui.renderer.layer, x, y)); },
  roomSell: () => {
    const { x, y } = ui.renderer.selected;
    const d = ui.renderer.layer;
    confirmModal(`<h2>${ico('demolish')} Demolir a sala?</h2><p>Você recebe 50% do que gastou de volta.</p>`, () => { result(ui.game.sellRoom(d, x, y)); renderTileInfo(true); }, { yes: 'Demolir', danger: true });
  },
  goLayer: (el) => {
    const r = ui.renderer;
    const sel = r.selected;
    setLayer(Number(el.dataset.arg));
    if (sel) r.selected = { ...sel };
    renderTileInfo(true);
  },
  plant: () => { const { x, y } = ui.renderer.selected; result(ui.game.plant(x, y)); },
  expand: () => result(ui.game.expand()),
  closeTile: () => { ui.renderer.selected = null; renderTileInfo(true); },

  // abas
  tab: (el) => { ui.tab = el.dataset.arg; play('tab', 0.6); renderSide(true); },
  lockedTab: (el) => toast(`${TAB_NAMES[el.dataset.arg]}: ${lockedTabHint(el.dataset.arg)}.`, 'info', 'lock'),
  recruit: (el) => result(ui.game.recruit(el.dataset.arg)),
  council: (el) => result(ui.game.toggleCouncil(el.dataset.arg)),
  expedition: (el) => { const [hid, eid] = el.dataset.arg.split('|'); result(ui.game.startExpedition(hid, eid)); },
  collect: (el) => result(ui.game.collectExpedition(el.dataset.arg)),
  speedup: (el) => result(ui.game.speedUpExpedition(el.dataset.arg)),
  train: (el) => { if (result(ui.game.trainHero(el.dataset.arg))) play('upgrade'); },
  speedupTrain: (el) => result(ui.game.speedUpTraining(el.dataset.arg)),
  claimTier: (el) => { if (result(ui.game.claimTier(Number(el.dataset.arg)))) play('coin'); },
  claimAllTiers: () => {
    // Um aviso só no fim (antes eram até 30 toasts seguidos, um por nível).
    const max = Math.min(SEASON_TIERS, Math.floor(ui.game.state.season.xp / XP_PER_TIER));
    const labels = [];
    ui.game.quiet = true;
    try {
      for (let t = 1; t <= max; t++) if (!ui.game.state.season.claimed.includes(t)) { const r = ui.game.claimTier(t); if (r.ok) labels.push(r.reward.label); }
    } finally { ui.game.quiet = false; }
    if (!labels.length) return;
    play('coin');
    toast(`Resgatou ${labels.length} recompensa(s): ${labels.join(', ')}.`, 'good', 'star');
    result({ ok: true });
  },
  claimMission: (el) => { if (result(ui.game.claimMission(Number(el.dataset.arg)))) play('confirm'); },
  daily: () => { closeModal(); if (result(ui.game.claimDaily())) play('coin'); },
  showDaily: () => showDaily(),
  ascend: () => {
    const adv = ui.game.ascendAdvice();
    if (adv.crowns < 1) { play('error'); toast('Ainda não há Coroas a ganhar.', 'bad', 'warning'); return; }
    confirmModal(`<h2>${resIco('crowns')} Ascender?</h2><p>O reino atual (prédios, recursos, terras) recomeça num mapa novo. Você ganha <b>${adv.crowns} Coroas</b> para a Árvore de Legado.</p><p>Ficam com você: heróis, gemas, Coroas, talentos, temporada, conquistas, cosméticos e estatísticas.</p>${adv.recommended ? '' : `<p class="warn">${ico('warning')} Ainda não é o momento recomendado: esta Ascensão não dobra as suas Coroas.</p>`}`, () => { result(ui.game.ascend()); ui.renderer.selected = null; }, { yes: 'Ascender' });
  },
  toLegacy: () => { closeModal(); ui.tab = 'legado'; play('tab', 0.6); renderSide(true); },
  runSummary: (el) => { const r = ui.game.state.runs?.[Number(el.dataset.arg)]; if (r) { play('open', 0.6); showRunSummary(r); } },
  talent: (el) => { if (result(ui.game.buyTalent(el.dataset.arg))) play('upgrade'); },
  greet: (el) => { const res = ui.game.greetRival(el.dataset.arg); if (result(res)) toast(res.gift ? 'Eles retribuíram com 1 gema!' : 'Saudação enviada (+10 XP).', 'good', 'greet'); },
  trade: (el) => {
    const [rid, res] = el.dataset.arg.split('|');
    const out = ui.game.tradeRival(rid, res);
    if (result(out)) { play('coin'); toast(`Trocou ${fmt(out.amount)} de ${RESOURCES[res].name.toLowerCase()} por ${fmt(out.gold)} de ouro.`, 'good', 'trade'); }
  },
  visit: (el) => {
    const rival = ui.game.rivals().find((x) => x.id === el.dataset.arg);
    if (rival) startVisit({ id: rival.id, name: rival.name, title: rival.title, banner: rival.banner, emblem: rival.emblem, power: rival.power, grid: rivalGrid(rival) });
  },
  visitCode: () => { try { startVisit(decodeKingdom($('#friendCode').value)); } catch (err) { play('error'); toast(err.message, 'bad', 'warning'); } },
  copyCode: () => copyText(encodeKingdom(ui.game.state, kingdomPower(ui.game.state)), 'Código do reino copiado. Mande para um amigo.'),
  endVisit: () => endVisit(),
  rename: () => { if (result(ui.game.setKingdomName($('#kname').value))) toast('Nome atualizado.', 'good', 'check'); },
  equip: (el) => { const [kind, id] = el.dataset.arg.split('|'); result(ui.game.equip(kind, id)); },
  buyCosmetic: (el) => { const [kind, id] = el.dataset.arg.split('|'); if (result(ui.game.buyCosmetic(kind, id))) { ui.game.equip(kind, id); play('coin'); } },

  // save e opções
  exportSave: () => copyText(exportCode(ui.game.state), 'Save copiado para a área de transferência. Guarde em lugar seguro.'),
  importSave: () => {
    try {
      const { state } = importCode($('#saveCode').value);
      closeModal();
      confirmModal(`<h2>${ico('save')} Importar este save?</h2><p>Reino <b>${esc(state.kingdom.name)}</b>, ${fmt(state.stats.totalGold)} de ouro na vida toda. O reino atual será substituído (os backups automáticos continuam guardados).</p>`, () => { save(); startGame(state); toast('Save importado.', 'good', 'save'); }, { yes: 'Importar' });
    } catch (err) { play('error'); toast(`Save inválido: ${err.message}`, 'bad', 'warning'); }
  },
  restoreBackup: (el) => {
    confirmModal(`<h2>${ico('save')} Restaurar este backup?</h2><p>O reino atual será substituído pelo backup.</p>`, () => {
      try { const { state } = restoreBackup(store, Number(el.dataset.arg)); startGame(state); toast('Backup restaurado.', 'good', 'save'); } catch (err) { toast(`Backup ilegível: ${err.message}`, 'bad', 'warning'); }
    }, { yes: 'Restaurar' });
  },
  hardReset: () => confirmModal(`<h2>${ico('warning')} Apagar o reino atual?</h2><p>O save principal será apagado. Os backups automáticos continuam disponíveis em Save e backups.</p>`, () => {
    clearSave(store);
    startGame(createState({ seed: newSeed() }), { isNew: true });
  }, { yes: 'Apagar', danger: true }),
  remap: (el) => { remapping = el.dataset.arg; showOptions(true); },
  resetKeys: () => { ui.config.keys = Object.fromEntries(KEY_ACTIONS.map((a) => [a.id, a.key])); saveConfig(); showOptions(true); },
  startKingdom: () => {
    ui.game.setKingdomName($('#introName').value || 'Reino de Bolso');
    const banner = document.querySelector('input[name=introBanner]:checked')?.value;
    if (banner) ui.game.equip('banner', banner);
    closeModal();
    save();
    renderAll();
    showDaily();
  },
};

function onClick(e) {
  const el = e.target.closest('[data-action]');
  if (!el || el.disabled) return;
  const fn = ACTIONS[el.dataset.action];
  if (fn) { e.preventDefault(); fn(el); }
}

// Opções: sliders e caixas com data-config aplicam na hora.
function onInput(e) {
  const el = e.target.closest('[data-config]');
  if (!el) return;
  const k = el.dataset.config;
  const c = ui.config;
  if (el.type === 'checkbox') c[k] = el.checked;
  else c[k] = Number(el.value) / 100;
  const out = document.querySelector(`[data-out="${k}"]`);
  if (out) out.textContent = `${Math.round(Number(el.value))}%`;
  saveConfig();
  applyConfig();
  if (k === 'sfxVolume') play('click');
  if (k === 'fontScale') ui.renderer?.resize();
}

function copyText(text, msg) {
  const fallback = () => showModal(`<h2>${ico('copy')} Copie manualmente</h2><textarea readonly class="code">${esc(text)}</textarea><div class="row"><button class="btn" data-action="closeModal">Fechar</button></div>`, '', { priority: true });
  if (navigator.clipboard?.writeText) navigator.clipboard.writeText(text).then(() => toast(msg, 'good', 'copy'), fallback);
  else fallback();
}

// ================================================================ subsolo
// Botões de nível no canto do mapa: aparecem depois da primeira Escadaria.
function renderLayers() {
  const el = $('#layers');
  const g = ui.game;
  const reached = g?.state.under?.reached ?? 0;
  if (!g || reached < 1) { el.hidden = true; if (ui.renderer?.layer) setLayer(0); return; }
  el.hidden = false;
  const cur = ui.renderer.layer;
  const btn = (d, label, title) => `<button class="${d === cur ? 'on' : ''}" data-action="layer" data-arg="${d}" title="${title}" aria-pressed="${d === cur}">${label}</button>`;
  const html = [btn(0, ico('house'), 'Superfície')]
    .concat(Array.from({ length: reached }, (_, i) => btn(i + 1, `-${i + 1}`, `Subsolo ${i + 1}: ${LEVEL_NAMES[i]}`))).join('');
  if (el.dataset.sig !== html) { el.innerHTML = html; el.dataset.sig = html; placeCompass(); }
}

function setLayer(d) {
  const r = ui.renderer;
  if (!r || r.layer === d) return;
  r.layer = d;
  r.selected = null;
  r.cursor = null;
  if (d > 0 && r.mode.type !== 'select') setMode({ type: 'select' });
  document.body.dataset.layer = d;
  renderLayers();
  renderTileInfo(true);
}

// ================================================================ visitas
function startVisit(k) {
  setLayer(0);
  ui.visiting = k;
  ui.renderer.view = { grid: k.grid };
  ui.renderer.selected = null;
  setMode({ type: 'select' });
  ui.game.recordVisit(k.id || k.name);
  const el = $('#visitBar');
  el.hidden = false;
  el.innerHTML = `<span class="banner sm" style="--bc:${bannerColor(k.banner)}">${ico(emblemIcon(k.emblem))}</span>
    <span>Visitando <b>${esc(k.name)}</b> · ${esc(k.title)} · Poder ${fmt(k.power)}</span><button class="btn small" data-action="endVisit">${ico('house')} Voltar ao meu reino</button>`;
  renderTileInfo(true);
}

function endVisit() {
  ui.visiting = null;
  if (ui.renderer) ui.renderer.view = null;
  $('#visitBar').hidden = true;
}

// Aviso "no lugar errado? Desfazer" por UNDO_WINDOW após cada construção. Fica na pilha de toasts,
// mas é clicável. Só é recriado quando muda a obra (a barra de tempo é uma animação CSS).
function renderUndo() {
  const g = ui.game;
  const u = g?.lastBuild;
  const now = Date.now();
  let el = $('#undoToast');
  if (!u || ui.visiting || $('#game').hidden || !g.canUndo(now)) { el?.remove(); return; }
  if (el?.dataset.at === String(u.at)) return;
  el?.remove();
  const left = Math.max(0, UNDO_WINDOW - (now - u.at));
  el = document.createElement('div');
  el.id = 'undoToast';
  el.className = 'toast undo';
  el.dataset.at = String(u.at);
  el.innerHTML = `${ico('time')}<span><b>${BUILDINGS[u.id].name}</b> no lugar errado?</span>
    <button class="btn small" data-action="undo">Desfazer <kbd>${esc(keyLabel(ui.config.keys.undo))}</kbd></button><i class="undo-bar" style="animation-duration:${left}ms"></i>`;
  $('#toasts').prepend(el);
}

function refreshAfterVisit() {
  renderHud();
  renderTileInfo(true);
}

// ================================================================ efeitos ambientes
let ambientTick = 0;
function ambientFx() {
  if (!ui.config.particles || ui.visiting || document.hidden) return;
  ambientTick++;
  if (ambientTick % 3 !== 0) return;
  const producers = [];
  const layer = ui.renderer.layer;
  const infos = layer > 0 ? ui.game.econ.under?.[layer - 1] ?? [] : ui.game.econ.tiles;
  infos.forEach((info, i) => { if (info && Object.values(info.out).some((v) => v > 0)) producers.push([i, info]); });
  for (let k = 0; k < Math.min(3, producers.length); k++) {
    const [i, info] = producers[Math.floor(Math.random() * producers.length)];
    const [res, v] = Object.entries(info.out).sort((a, b) => b[1] - a[1])[0];
    if (v > 0) ui.renderer.addFloat(i % 12, Math.floor(i / 12), `+${fmt(v * 3)}`, '#ffffff', iconKey(res, FLOAT_COLORS[res]));
  }
}

// ================================================================ telas modais
function showIntro() {
  showModal(`
    <h2>${resIco('crowns')} Funde o seu reino</h2>
    <p>Você herdou um terreno, uma casa e uma fazenda. O resto é com você.</p>
    <ul class="intro">
      <li>${ico('hero-architect')}<span><b>A posição importa:</b> cada prédio ganha (ou perde) bônus dos 4 vizinhos. Escolha um prédio e passe pelo mapa para ver.</span></li>
      <li>${ico('swords')}<span><b>Hordas atacam</b> sempre por um lado anunciado. Defenda esse lado: se perder, elas quebram construções, e o que não for consertado até a próxima derrota vira ruína.</span></li>
      <li>${ico('tab-heroes')}<span><b>Novas abas aparecem</b> conforme o reino cresce: heróis, temporada, social e legado.</span></li>
      <li>${ico('time')}<span>O reino <b>produz mesmo com você fora</b>. Entre 5 minutos ou fique 2 horas.</span></li>
    </ul>
    <label for="introName">Nome do reino</label>
    <input type="text" id="introName" maxlength="24" placeholder="Reino de Bolso" data-autofocus>
    <label>Estandarte</label>
    <div class="swatches">${BANNERS.filter((b) => b.free).map((b, i) => `<label class="sw" style="--bc:${b.color}" aria-label="${b.name}"><input type="radio" name="introBanner" value="${b.id}" ${i === 0 ? 'checked' : ''}></label>`).join('')}</div>
    <button class="btn big primary" data-action="startKingdom">${ico('build')} Fundar meu reino</button>`, '', { closable: false });
}

function showHowTo() {
  showModal(`<h2>${ico('info')} Como jogar</h2>
    <ul class="intro">
      <li>${ico('build')}<span>Escolha um prédio na paleta e toque no mapa. No celular, o primeiro toque mostra a prévia e o segundo constrói. Errou o lugar? Você tem 5 segundos para desfazer.</span></li>
      <li>${ico('hero-architect')}<span>Os números verdes e vermelhos mostram o bônus de cada vizinho, e a dica no topo mostra quanto o prédio vai render ali.</span></li>
      <li>${ico('people')}<span>Casas trazem moradores; prédios precisam de trabalhadores. Falta de gente reduz toda a produção.</span></li>
      <li>${ico('swords')}<span>A próxima horda sempre diz de que lado vem. Torres e muralhas perto daquela borda contam inteiras.</span></li>
      <li>${ico('cart')}<span>Carroças do mercador aparecem no mapa por 20 segundos: toque nelas.</span></li>
      <li>${ico('crowns')}<span>Quando o crescimento desacelerar, ascenda: recomece num mapa novo com bônus permanentes.</span></li>
      <li>${ico('keyboard')}<span>Teclado: setas movem o cursor, Enter confirma, 1 a 9 escolhem prédios, Esc abre o menu. Tudo remapeável em Opções.</span></li>
    </ul>
    <button class="btn big primary" data-action="closeModal" data-autofocus>Entendi</button>`, '', { priority: true });
}

function showGameMenu() {
  play('open', 0.6);
  showModal(`<h2>${ico('menu')} Menu</h2>
    <div class="stack">
      <button class="btn big primary" data-action="closeModal" data-autofocus>${ico('play')} Continuar</button>
      <button class="btn big" data-action="options">${ico('settings')} Opções</button>
      <button class="btn big" data-action="saveMenu">${ico('save')} Save e backups</button>
      <button class="btn big" data-action="howTo">${ico('info')} Como jogar</button>
      <button class="btn big" data-action="credits">${ico('scroll')} Créditos</button>
      <button class="btn big" data-action="toMainMenu">${ico('exit')} Salvar e voltar ao menu principal</button>
    </div>`);
}

function showOptions(replace = false) {
  const c = ui.config;
  const slider = (k, label, min, max, icon) => `<label for="opt-${k}">${ico(icon)} ${label}: <span data-out="${k}">${Math.round(c[k] * 100)}%</span></label>
    <input type="range" id="opt-${k}" min="${min}" max="${max}" step="5" value="${Math.round(c[k] * 100)}" data-config="${k}">`;
  const check = (k, label) => `<label class="check"><input type="checkbox" data-config="${k}" ${c[k] ? 'checked' : ''}> ${label}</label>`;
  const keys = KEY_ACTIONS.map((a) => `<span>${a.label}</span><button class="btn small ${remapping === a.id ? 'primary' : ''}" data-action="remap" data-arg="${a.id}">${remapping === a.id ? 'Pressione uma tecla...' : esc(keyLabel(c.keys[a.id]))}</button>`).join('');
  const m = musicInfo();
  const html = `<h2>${ico('settings')} Opções</h2>
    <h3>Som</h3>
    ${slider('musicVolume', 'Música', 0, 100, 'music')}
    ${m ? `<p class="muted">Faixa: ${esc(m.title)} (${esc(m.author)}, ${esc(m.license)}).</p>` : '<p class="muted">Nenhuma faixa de música instalada.</p>'}
    ${slider('sfxVolume', 'Efeitos', 0, 100, 'speaker')}
    <h3>Visual e acessibilidade</h3>
    ${slider('fontScale', 'Tamanho do texto', 85, 150, 'font')}
    ${check('particles', 'Partículas, moradores e números flutuantes')}
    ${check('reduceMotion', 'Reduzir movimento (sem tremor, flash nem animações)')}
    ${check('highContrast', 'Alto contraste')}
    <h3>Teclado</h3>
    <div class="keys">${keys}</div>
    <div class="row"><button class="btn small" data-action="resetKeys">Restaurar teclas padrão</button></div>
    <button class="btn big primary" data-action="closeModal">Fechar</button>`;
  if (replace && modalOpen()) { replaceModal(html); return; }
  showModal(html, '', { priority: true });
}

async function showCredits() {
  showModal(`<h2>${ico('scroll')} Créditos</h2><p class="muted">Carregando...</p>`, '', { priority: true });
  let icons = {};
  let sfx = {};
  try { icons = await (await fetch('assets/icons/game-icons/credits.json')).json(); } catch { icons = {}; }
  try { sfx = await (await fetch('assets/sfx/credits.json')).json(); } catch { sfx = {}; }
  const byAuthor = {};
  for (const v of Object.values(icons)) byAuthor[v.author] = (byAuthor[v.author] || 0) + 1;
  const authorNames = { lorc: 'Lorc', delapouite: 'Delapouite', skoll: 'Skoll', sbed: 'Sbed', willdabeast: 'Willdabeast', guard13007: 'Guard13007' };
  const packs = [...new Set(Object.values(sfx).map((v) => v.pack.replace(/^Kenney\s*–\s*/, '')))];
  const m = musicInfo();
  const html = `<h2>${ico('scroll')} Créditos</h2>
    <p><b>Reino de Bolso</b>, versão ${GAME_VERSION}.</p>
    <h3>Arte</h3>
    <ul class="credits">
      <li>Prédios e natureza do mapa: <b>KayKit Medieval Hexagon Pack</b>, por Kay Lousberg (kaylousberg.com). Licença CC0 1.0. Modelos 3D renderizados como imagens 2D.</li>
      <li>Moradores, invasores e carroça: <b>Medieval RTS</b>; interface: <b>UI Pack</b>. Por Kenney (kenney.nl). Licença CC0 1.0.</li>
      <li>Ícones de <a href="https://game-icons.net" target="_blank" rel="noopener">game-icons.net</a>, licença <a href="https://creativecommons.org/licenses/by/3.0/" target="_blank" rel="noopener">CC BY 3.0</a>. Icons made by ${Object.entries(byAuthor).map(([a, n]) => `<b>${authorNames[a] ?? esc(a)}</b> (${n})`).join(', ')}. Cores alteradas e fundo removido.</li>
      <li>Fonte <b>Nunito</b>, por The Nunito Project Authors. SIL Open Font License 1.1.</li>
    </ul>
    <h3>Som</h3>
    <ul class="credits">
      <li>${packs.map((p) => `<b>${esc(p)}</b>`).join(', ')}, por Kenney (kenney.nl). Licença CC0 1.0.</li>
      ${m ? `<li>Música: <b>${esc(m.title)}</b>, por ${esc(m.author)}. Licença ${esc(m.license)}.</li>` : '<li>Música: nenhuma instalada.</li>'}
    </ul>
    <p class="muted">Lista completa, arquivo por arquivo, no ASSETS.md do repositório.</p>
    <button class="btn big primary" data-action="closeModal">Fechar</button>`;
  if (modalOpen()) replaceModal(html);
}

function showSaveMenu() {
  const backups = listBackups(store);
  showModal(`<h2>${ico('save')} Save e backups</h2>
    <p class="muted">O jogo salva sozinho a cada 10 segundos e guarda ${BACKUP_SLOTS} backups em rodízio (um a cada 5 minutos).</p>
    <h3>Exportar</h3>
    <button class="btn" data-action="exportSave">${ico('copy')} Copiar código do save</button>
    <h3>Importar</h3>
    <textarea id="saveCode" class="code" placeholder="Cole aqui um código de save" aria-label="Código de save"></textarea>
    <div class="row"><button class="btn" data-action="importSave">${ico('save')} Importar</button></div>
    <h3>Backups automáticos</h3>
    ${backups.length ? backups.map((b) => (b.broken ? `<p class="muted">Slot ${b.slot + 1}: danificado</p>` : `<div class="row"><span>${esc(b.name)} · ${new Date(b.at).toLocaleString('pt-BR')} · ${fmt(b.gold)} de ouro</span><button class="btn small" data-action="restoreBackup" data-arg="${b.slot}">Restaurar</button></div>`)).join('') : '<p class="muted">Nenhum backup ainda (o primeiro é feito na primeira gravação).</p>'}
    <h3>Zona de perigo</h3>
    <button class="btn danger" data-action="hardReset">${ico('demolish')} Apagar o reino atual</button>
    <div class="row"><button class="btn big primary" data-action="closeModal">Fechar</button></div>`, '', { priority: true });
}

function showDaily() {
  const st = ui.game.dailyStatus();
  const streak = ui.game.state.daily.streak;
  showModal(`<h2>${ico('calendar')} Recompensa diária</h2>
    <div class="daily">${DAILY_REWARDS.map((r) => {
      const cur = ((st.available ? st.nextStreak : streak) - 1) % 7 + 1;
      const done = st.available ? r.day < cur : r.day <= cur;
      const icon = done ? ico('check') : r.gems ? resIco('gems') : r.boost ? ico('boost', 'c-gold') : r.scroll ? ico('scroll', 'c-crowns') : resIco('gold');
      return `<div class="dr ${done ? 'done' : ''} ${st.available && r.day === cur ? 'today' : ''}"><b>Dia ${r.day}</b>${icon}<span>${r.label}</span></div>`;
    }).join('')}</div>
    ${st.available ? `<button class="btn big primary" data-action="daily" data-autofocus>Resgatar: ${st.reward.label}</button>` : '<p class="muted">Já resgatada hoje. Volte amanhã para manter a sequência.</p><button class="btn big" data-action="closeModal">Fechar</button>'}`);
}

function showOffline(sum) {
  const g = sum.gains;
  showModal(`<h2>${ico('time')} Enquanto você esteve fora (${fmtTime(sum.elapsed)})</h2>
    <p>Seu reino trabalhou com ${Math.round(sum.efficiency * 100)}% de eficiência${sum.capped ? ` por até ${fmtTime(sum.simulated)} (limite offline)` : ''}.</p>
    <div class="gains">${['gold', 'food', 'wood', 'stone'].map((r) => `<div>${resIco(r)}<b class="${g[r] < 0 ? 'neg' : ''}">${g[r] >= 0 ? '+' : ''}${fmt(g[r])}</b></div>`).join('')}</div>
    ${sum.expeditionsReady ? `<p>${ico('expedition')} ${sum.expeditionsReady} expedição(ões) pronta(s) para coletar.</p>` : ''}
    ${sum.capped ? '<p class="muted">Aumente o limite com o talento Vigília ou o herói O Relojoeiro.</p>' : ''}
    <button class="btn big primary" data-action="closeModal" data-autofocus>Continuar</button>`);
}

function showRecruit(res) {
  const h = res.hero;
  const rar = RARITIES[h.rarity];
  play(h.rarity === 'lendario' || h.rarity === 'epico' ? 'legendary' : 'recruit');
  showModal(`<div class="reveal" style="--rc:var(--${h.rarity})">
      <div class="portrait">${ico(h.icon)}</div>
      <p class="rarity">${rar.name}</p>
      <h2 style="justify-content:center">${h.name}</h2>
      <p>${res.isNew ? 'Novo herói!' : res.gemsRefund ? `Já está no máximo: +${res.gemsRefund} gemas.` : `Repetido! Agora com ${res.stars} estrelas.`}</p>
      <p class="muted">${describeBonus(h.bonus.type, h.bonus.value * heroStrength(ui.game.state.heroes.owned[h.id]))} · poder ${heroPowerOf(h, ui.game.state.heroes.owned[h.id])}</p>
      <em>${esc(h.lore)}</em>
    </div><button class="btn big primary" data-action="closeModal" data-autofocus>Bem-vindo(a)!</button>`);
}
