// Game: orquestra estado + sistemas. A UI só conversa com esta classe.
// Toda ação retorna { ok, reason? } e emite eventos para a UI (toast, fx, som).
import { BUILDINGS, TERRAIN, SELL_REFUND, POP_GROWTH, POP_STARVE } from '../data/buildings.js';
import { HERO_BY_ID, EXPEDITIONS, RECRUIT_GEM_COST } from '../data/heroes.js';
import { TALENT_BY_ID, CROWN_DIVISOR } from '../data/talents.js';
import { EVENTS, EVENT_BY_ID, EVENT_INTERVAL, CHEST_INTERVAL, CHEST_LIFETIME, RAID_INTERVAL, RAID_WARNING, RAID_BASE_STRENGTH, RAID_GROWTH, RAID_LOSS_FRACTION, RAID_NEWBIE_LOSS, RAID_NEWBIE_COUNT, RAID_LOSS_CAP_SECONDS, RAID_NAMES } from '../data/events.js';
import { XP_REWARDS, SEASON_TIERS } from '../data/seasons.js';
import { ACHIEVEMENTS } from '../data/achievements.js';
import { BANNERS, EMBLEMS, DAILY_REWARDS, SEASON_TITLES } from '../data/cosmetics.js';
import { computeEconomy, buildCost, upgradeCost, canAfford, pay, refund, countOf, PROD_RES, kingdomPower } from './economy.js';
import { createState, carryOver, newSeed } from './state.js';
import { GRID_W, idx, isUnlocked, RING_COSTS, MAX_RING } from './map.js';
import { syncSeason, syncMissions, tierOf, rewardFor } from './season.js';
import { councilSlots, recruitCost, rollHero, addHero, expeditionReward, speedUpCost } from './heroes.js';
import { generateRivals } from './social.js';
import { dayKey, randInt } from './rng.js';

export const OFFLINE_THRESHOLD = 30; // s sem tick = sessão offline
export const BASE_OFFLINE_HOURS = 4;
export const BASE_OFFLINE_EFF = 0.6;
// Janela para desfazer a última construção (o erro mais comum de iniciante é o tile errado).
export const UNDO_WINDOW = 5000;

// `focus` diz à interface o que destacar (prédio na paleta ou aba).
export const TUTORIAL = [
  { text: 'Construa uma Serraria encostada numa floresta: cada floresta vizinha dá +40% de madeira.', focus: { build: 'serraria' }, done: (s) => countOf(s, 'serraria') >= 1, reward: { gold: 50 } },
  { text: 'Construa mais uma Casa: mais moradores, mais gente para trabalhar.', focus: { build: 'casa' }, done: (s) => countOf(s, 'casa') >= 2, reward: { gold: 60, wood: 20 } },
  { text: 'Abriu a aba Heróis: use o pergaminho grátis para recrutar seu primeiro herói.', focus: { tab: 'herois' }, done: (s) => Object.keys(s.heroes.owned).length >= 1, reward: { gold: 80 } },
  { text: 'Hordas atacam a cada poucos minutos, sempre por um lado do mapa. Construa uma Muralha ou Torre desse lado.', focus: { build: 'muralha' }, done: (s) => countOf(s, 'muralha') + countOf(s, 'torre') >= 1, reward: { stone: 40 } },
  { text: 'Construa um Mercado encostado em casas: cada casa vizinha é um cliente.', focus: { build: 'mercado' }, done: (s) => countOf(s, 'mercado') >= 1, reward: { gold: 150 } },
  { text: 'Não existe "missão final": o reino é seu. Chegue a 10 construções e veja o que consegue criar.', done: (s) => s.grid.tiles.filter((t) => t.b).length >= 10, reward: { gems: 3 } },
];

export const RAID_DIRS = ['n', 's', 'e', 'w'];
export const DIR_NAMES = { n: 'Norte', s: 'Sul', e: 'Leste', w: 'Oeste' };

// Regras de desbloqueio gradual das abas (as abas 'reino' e 'perfil' existem desde o início).
export const TAB_UNLOCKS = {
  herois: { hint: 'Abre depois das primeiras construções', check: (g) => g.state.tutorial.step >= 2 || g.state.stats.built >= 2 || g.state.stats.raidsWon + g.state.stats.raidsLost > 0 },
  temporada: { hint: 'Abre com 10 construções ou 8 min de jogo', check: (g) => g.state.stats.playTime >= 480 || g.state.grid.tiles.filter((t) => t.b).length >= 10 },
  social: { hint: 'Abre com 12 construções', check: (g) => g.state.grid.tiles.filter((t) => t.b).length >= 12 },
  legado: { hint: 'Abre perto da primeira Coroa', check: (g) => g.state.stats.ascensions > 0 || g.state.stats.runGold >= CROWN_DIVISOR * 0.5 },
};
export const TAB_NAMES = { reino: 'Reino', herois: 'Heróis', temporada: 'Temporada', legado: 'Legado', social: 'Social', perfil: 'Perfil' };

export class Game {
  constructor(state, now = Date.now()) {
    this.state = state;
    this.listeners = {};
    this.quiet = false;
    this.lastBuild = null; // última construção desfazível (não vai para o save)
    this.lastAchCheck = 0;
    this.econ = computeEconomy(state, now);
    this.now = now;
  }

  on(evt, fn) {
    (this.listeners[evt] ||= []).push(fn);
    return this;
  }

  // quiet = true silencia só os avisos de texto (ações em lote mostram um resumo no lugar).
  emit(evt, data) {
    if (this.quiet && evt === 'toast') return;
    for (const fn of this.listeners[evt] || []) fn(data);
  }

  log(text, icon = 'scroll') {
    this.state.log.unshift({ at: this.now, text, icon });
    if (this.state.log.length > 50) this.state.log.pop();
  }

  // ------------------------------------------------------------ loop
  // background: true quando o intervalo longo veio de aba oculta/minimizada (o jogo continuava
  // aberto). Nesse caso a produção é integral (100%), não a eficiência offline.
  tick(now = Date.now(), { background = false } = {}) {
    const s = this.state;
    this.now = now;
    const dt = (now - s.lastTick) / 1000;
    if (dt <= 0) return;
    if (dt > OFFLINE_THRESHOLD) {
      const summary = this.catchUp(now, { efficiency: background ? 1 : undefined });
      if (summary) this.emit(background ? 'background' : 'offline', summary);
      return;
    }
    s.lastTick = now;
    s.stats.playTime += dt;
    this.econ = computeEconomy(s, now);
    this.step(dt);
    this.updateLive(now);
    if (now - this.lastAchCheck > 2000) {
      this.lastAchCheck = now;
      this.checkAchievements();
      this.checkTutorial();
      this.checkUnlocks();
      if (syncSeason(s, now)) this.emit('toast', { text: 'Uma nova temporada começou!', kind: 'season', icon: 'star' });
      if (syncMissions(s, now, this.goldScale())) this.emit('missions');
    }
  }

  step(dt, efficiency = 1) {
    const s = this.state;
    const e = this.econ;
    for (const r of PROD_RES) {
      const gain = e.rates[r] * dt * (e.rates[r] > 0 ? efficiency : 1);
      const before = s.res[r];
      if (gain > 0) s.res[r] = before >= e.caps[r] ? before : Math.min(e.caps[r], before + gain);
      else s.res[r] = Math.max(0, before + gain);
      if (r === 'gold' && s.res.gold > before) {
        const earned = s.res.gold - before;
        s.stats.totalGold += earned;
        s.stats.runGold += earned;
        this.trackMission('gold', earned);
      }
    }
    // População cresce até a capacidade se houver comida; passa fome se não houver.
    if (s.res.food > 0.5 || e.rates.food >= 0) {
      if (s.pop < e.popCap) s.pop = Math.min(e.popCap, s.pop + POP_GROWTH * dt * (0.5 + e.happiness / 100));
      else if (s.pop > e.popCap) s.pop = Math.max(e.popCap, s.pop - POP_STARVE * dt);
    } else {
      s.pop = Math.max(1, s.pop - POP_STARVE * dt);
    }
  }

  // Progresso offline: simulado em blocos para respeitar limites de armazenamento e comida.
  catchUp(now, { efficiency } = {}) {
    const s = this.state;
    const elapsed = (now - s.lastTick) / 1000;
    const mods = computeEconomy(s, now).mods;
    const capSec = (BASE_OFFLINE_HOURS + mods.offlineHours) * 3600;
    const eff = efficiency ?? Math.min(1, BASE_OFFLINE_EFF + mods.offlineEff);
    const simSec = Math.min(elapsed, capSec);
    const before = { ...s.res, pop: s.pop };
    const chunk = Math.max(5, simSec / 400);
    let t = 0;
    while (t < simSec) {
      const d = Math.min(chunk, simSec - t);
      this.econ = computeEconomy(s, s.lastTick + t * 1000);
      this.step(d, eff);
      t += d;
    }
    s.lastTick = now;
    this.now = now;
    // Nada de invasão/evento/baú instantâneo ao voltar (só para ausências de 1 min ou mais).
    if (elapsed >= 60) {
      s.raid.nextAt = Math.max(s.raid.nextAt, now + 90000);
      s.raid.warned = false;
      s.nextEventAt = Math.max(s.nextEventAt, now + 120000);
      s.chest = null;
      s.nextChestAt = now + 30000;
    }
    if (s.event && s.event.endsAt < now) s.event = null;
    this.econ = computeEconomy(s, now);
    syncSeason(s, now);
    syncMissions(s, now, this.goldScale());
    if (elapsed < 60) return null;
    const gains = {};
    for (const r of PROD_RES) gains[r] = s.res[r] - before[r];
    const ready = Object.values(s.heroes.owned).filter((h) => h.expedition && h.expedition.endsAt <= now).length;
    return { elapsed, simulated: simSec, capped: elapsed > capSec, efficiency: eff, gains, popDelta: s.pop - before.pop, expeditionsReady: ready };
  }

  updateLive(now) {
    const s = this.state;
    const e = this.econ;
    // Invasões
    if (!s.raid.warned && now >= s.raid.nextAt - RAID_WARNING * 1000) {
      s.raid.warned = true;
      s.raid.name = RAID_NAMES[Math.min(RAID_NAMES.length - 1, Math.floor(s.raid.level / 3))];
      this.emit('raidWarning', { name: s.raid.name, strength: this.raidStrength(), defense: e.defense, dir: s.raid.dir });
    }
    if (now >= s.raid.nextAt) this.resolveRaid(now);

    // Eventos relâmpago
    if (s.event && s.event.endsAt <= now) {
      this.emit('toast', { text: `${EVENT_BY_ID[s.event.id].name} terminou.`, kind: 'info', icon: EVENT_BY_ID[s.event.id].icon });
      s.event = null;
    }
    if (!s.event && now >= s.nextEventAt) {
      const ev = EVENTS[Math.floor(Math.random() * EVENTS.length)];
      s.event = { id: ev.id, endsAt: now + ev.duration * 1000 };
      if (ev.triggersRaid) {
        s.raid.nextAt = now + ev.triggersRaid * 1000;
        s.raid.warned = false;
      }
      s.nextEventAt = now + (randInt(Math.random, EVENT_INTERVAL[0], EVENT_INTERVAL[1]) / e.mods.eventRate) * 1000;
      this.log(`Evento: ${ev.name}`, ev.icon);
      this.emit('event', ev);
    }

    // Baú do mercador
    if (s.chest && s.chest.expiresAt <= now) {
      s.chest = null;
      s.nextChestAt = now + randInt(Math.random, CHEST_INTERVAL[0], CHEST_INTERVAL[1]) * 1000;
    }
    if (!s.chest && now >= s.nextChestAt) {
      const free = [];
      s.grid.tiles.forEach((t, i) => {
        const x = i % GRID_W;
        const y = Math.floor(i / GRID_W);
        if (!t.b && t.t === 'grass' && isUnlocked(s.grid, x, y)) free.push([x, y]);
      });
      if (free.length) {
        const [x, y] = free[Math.floor(Math.random() * free.length)];
        s.chest = { x, y, expiresAt: now + CHEST_LIFETIME * 1000 };
        if (e.mods.autoChest) this.openChest();
        else this.emit('chest', s.chest);
      } else s.nextChestAt = now + 60000;
    }

    // Expedições prontas (aviso único)
    for (const [hid, h] of Object.entries(s.heroes.owned)) {
      if (h.expedition && !h.expedition.notified && h.expedition.endsAt <= now) {
        h.expedition.notified = true;
        this.emit('toast', { text: `${HERO_BY_ID[hid].name} voltou da expedição!`, kind: 'good', icon: HERO_BY_ID[hid].icon });
      }
    }
  }

  goldScale() {
    return Math.max(1, Math.min(1000, (this.econ?.rates.gold || 1) / 5));
  }

  // ------------------------------------------------------------ invasões
  raidStrength() {
    return Math.round(RAID_BASE_STRENGTH * RAID_GROWTH ** this.state.raid.level);
  }

  resolveRaid(now) {
    const s = this.state;
    const e = this.econ;
    const strength = this.raidStrength();
    const name = s.raid.name || RAID_NAMES[0];
    const result = { name, strength, defense: e.defense, level: s.raid.level };
    if (e.defense >= strength) {
      const loot = Math.floor(Math.max(strength * 12 * (1 + s.raid.level * 0.15), e.rates.gold * 45) * (1 + e.mods.raidLoot));
      const gems = 1 + e.mods.raidGems + (s.raid.level % 5 === 4 ? 2 : 0);
      s.res.gold += loot;
      s.res.gems += gems;
      s.stats.totalGold += loot;
      s.stats.runGold += loot;
      s.stats.raidsWon++;
      s.stats.bestRaid = Math.max(s.stats.bestRaid, s.raid.level + 1);
      s.raid.level++;
      Object.assign(result, { win: true, loot, gems });
      this.track('raidWin');
      this.log(`Vitória contra ${name} (força ${strength}): +${Math.floor(loot)} de ouro, +${gems} gema(s)`, 'swords');
    } else {
      const lost = {};
      const newbie = s.stats.raidsWon + s.stats.raidsLost < RAID_NEWBIE_COUNT;
      const fraction = newbie ? RAID_NEWBIE_LOSS : RAID_LOSS_FRACTION;
      result.fraction = fraction;
      for (const r of PROD_RES) {
        const cap = Math.max(50, (e.gross[r] || 0) * RAID_LOSS_CAP_SECONDS);
        lost[r] = Math.floor(Math.min(s.res[r] * fraction, cap));
        s.res[r] -= lost[r];
      }
      s.stats.raidsLost++;
      s.raid.level = Math.max(0, s.raid.level - 1);
      Object.assign(result, { win: false, lost });
      this.log(`${name} saquearam o reino (força ${strength} contra defesa ${Math.floor(e.defense)}).`, 'warning');
    }
    const interval = RAID_INTERVAL * e.mods.raidInterval * (0.8 + Math.random() * 0.4);
    s.raid.nextAt = now + interval * 1000;
    s.raid.warned = false;
    s.raid.name = null;
    result.dir = s.raid.dir;
    // A próxima horda já anuncia de onde vem: o jogador tem o intervalo inteiro para reforçar aquele lado.
    s.raid.dir = RAID_DIRS[Math.floor(Math.random() * RAID_DIRS.length)];
    this.econ = computeEconomy(s, now);
    this.emit('raid', result);
    return result;
  }

  // ------------------------------------------------------------ construção
  tileAt(x, y) {
    return this.state.grid.tiles[idx(x, y)];
  }

  // Desbloqueio pela quantidade de construções. Conta o histórico (built + 2 iniciais) para que
  // demolir não volte a bloquear, e para que veteranos (stats persistem na Ascensão) já comecem com tudo.
  isAvailable(id) {
    const def = BUILDINGS[id];
    if (!def.unlock) return true;
    return this.unlockProgress() >= def.unlock.buildings;
  }

  // Quantas construções contam para desbloquear prédios (o maior entre o histórico e o mapa atual).
  unlockProgress() {
    let onMap = 0;
    for (const t of this.state.grid.tiles) if (t.b) onMap++;
    return Math.max(this.state.stats.built + 2, onMap);
  }

  build(id, x, y) {
    const s = this.state;
    const def = BUILDINGS[id];
    if (!def) return { ok: false, reason: 'Construção desconhecida' };
    if (!this.isAvailable(id)) return { ok: false, reason: `Desbloqueia com ${def.unlock.buildings} construções` };
    if (!isUnlocked(s.grid, x, y)) return { ok: false, reason: 'Terra ainda não conquistada' };
    const tile = this.tileAt(x, y);
    if (tile.b) return { ok: false, reason: 'Já existe uma construção aqui' };
    if (!TERRAIN[tile.t].buildable) return { ok: false, reason: TERRAIN[tile.t].clearCost ? `Limpe a ${TERRAIN[tile.t].name.toLowerCase()} primeiro` : `Não dá para construir em ${TERRAIN[tile.t].name.toLowerCase()}` };
    const cost = buildCost(s, id, this.econ.mods);
    if (!canAfford(s.res, cost)) return { ok: false, reason: 'Recursos insuficientes' };
    const missions = s.season.missions?.list.map((m) => m.progress) ?? [];
    const xpBefore = s.season.xp;
    pay(s.res, cost);
    tile.b = { id, lvl: 1 };
    s.stats.built++;
    this.econ = computeEconomy(s, this.now);
    this.track('build');
    this.lastBuild = {
      id, x, y, cost, at: this.now, xp: s.season.xp - xpBefore, missions, guard: this.undoGuard(),
      tutorial: { ...s.tutorial }, achs: Object.keys(s.achievements), titles: [...s.cosmetics.titles], title: s.kingdom.title,
    };
    this.emit('built', { id, x, y });
    return { ok: true };
  }

  upgrade(x, y) {
    const s = this.state;
    this.lastBuild = null;
    const tile = this.tileAt(x, y);
    if (!tile.b) return { ok: false, reason: 'Nada para melhorar' };
    const cost = upgradeCost(tile.b.id, tile.b.lvl, this.econ.mods);
    if (!cost) return { ok: false, reason: 'Nível máximo' };
    if (!canAfford(s.res, cost)) return { ok: false, reason: 'Recursos insuficientes' };
    pay(s.res, cost);
    tile.b.lvl++;
    s.stats.upgrades++;
    this.econ = computeEconomy(s, this.now);
    this.track('upgrade');
    this.emit('upgraded', { x, y, lvl: tile.b.lvl });
    return { ok: true };
  }

  sell(x, y) {
    const s = this.state;
    this.lastBuild = null;
    const tile = this.tileAt(x, y);
    if (!tile.b) return { ok: false, reason: 'Nada para demolir' };
    const def = BUILDINGS[tile.b.id];
    const id = tile.b.id;
    const lvl = tile.b.lvl;
    tile.b = null;
    // reembolso: metade do custo base escalado pela quantidade restante + metade das melhorias
    refund(s.res, buildCost(s, id, this.econ.mods), SELL_REFUND);
    for (let l = 1; l < lvl; l++) refund(s.res, upgradeCost(id, l, this.econ.mods) || {}, SELL_REFUND);
    this.econ = computeEconomy(s, this.now);
    this.emit('sold', { id, x, y, name: def.name });
    return { ok: true };
  }

  move(fx, fy, tx, ty) {
    const s = this.state;
    this.lastBuild = null;
    const from = this.tileAt(fx, fy);
    const to = this.tileAt(tx, ty);
    if (!from.b) return { ok: false, reason: 'Nada para mover' };
    if (!isUnlocked(s.grid, tx, ty)) return { ok: false, reason: 'Terra ainda não conquistada' };
    if (to.b) return { ok: false, reason: 'Destino ocupado' };
    if (!TERRAIN[to.t].buildable) return { ok: false, reason: 'Terreno inválido' };
    to.b = from.b;
    from.b = null;
    this.econ = computeEconomy(s, this.now);
    this.emit('moved', { fx, fy, tx, ty });
    return { ok: true };
  }

  clear(x, y) {
    const s = this.state;
    this.lastBuild = null;
    const tile = this.tileAt(x, y);
    const ter = TERRAIN[tile.t];
    if (!isUnlocked(s.grid, x, y)) return { ok: false, reason: 'Terra ainda não conquistada' };
    if (!ter.clearCost) return { ok: false, reason: 'Não dá para limpar isso' };
    if (!canAfford(s.res, ter.clearCost)) return { ok: false, reason: 'Recursos insuficientes' };
    pay(s.res, ter.clearCost);
    for (const [r, v] of Object.entries(ter.clearYield)) s.res[r] += v;
    tile.t = 'grass';
    s.stats.cleared++;
    this.econ = computeEconomy(s, this.now);
    this.track('clear');
    this.emit('cleared', { x, y, yieldRes: ter.clearYield });
    return { ok: true };
  }

  expandCost() {
    const next = this.state.grid.ring + 1;
    const base = RING_COSTS[next];
    if (!base) return null;
    const f = 1 - this.econ.mods.landCost;
    return Object.fromEntries(Object.entries(base).map(([r, v]) => [r, Math.ceil(v * f)]));
  }

  expand() {
    const s = this.state;
    this.lastBuild = null;
    if (s.grid.ring >= MAX_RING) return { ok: false, reason: 'O mapa inteiro já é seu' };
    const cost = this.expandCost();
    if (!canAfford(s.res, cost)) return { ok: false, reason: 'Recursos insuficientes' };
    pay(s.res, cost);
    s.grid.ring++;
    this.log(`O reino se expandiu para o anel ${s.grid.ring}.`, 'map');
    this.emit('expanded', { ring: s.grid.ring });
    return { ok: true };
  }

  // ------------------------------------------------------------ heróis
  recruit(method) {
    const s = this.state;
    const cost = recruitCost(s, method);
    const pool = method === 'scroll' ? s.items : s.res;
    if (!canAfford(pool, cost)) return { ok: false, reason: method === 'scroll' ? 'Sem pergaminhos' : 'Recursos insuficientes' };
    pay(pool, cost);
    if (method === 'gold') s.stats.goldRecruits++;
    const result = addHero(s, rollHero(Math.random));
    s.stats.recruits++;
    if (result.isNew && s.heroes.council.length < councilSlots(this.econ.mods)) s.heroes.council.push(result.hero.id);
    this.econ = computeEconomy(s, this.now);
    this.track('recruit');
    this.log(`Recrutou ${result.hero.name}${result.isNew ? '' : ` (${result.stars} estrelas)`}`, result.hero.icon);
    this.emit('recruited', result);
    return { ok: true, result };
  }

  toggleCouncil(hid) {
    const s = this.state;
    const owned = s.heroes.owned[hid];
    if (!owned) return { ok: false, reason: 'Herói não recrutado' };
    const i = s.heroes.council.indexOf(hid);
    if (i >= 0) s.heroes.council.splice(i, 1);
    else {
      if (owned.expedition) return { ok: false, reason: 'Herói em expedição' };
      if (s.heroes.council.length >= councilSlots(this.econ.mods)) return { ok: false, reason: 'Conselho cheio' };
      s.heroes.council.push(hid);
    }
    this.econ = computeEconomy(s, this.now);
    return { ok: true };
  }

  startExpedition(hid, expId) {
    const s = this.state;
    const owned = s.heroes.owned[hid];
    const exp = EXPEDITIONS.find((x) => x.id === expId);
    if (!owned || !exp) return { ok: false, reason: 'Inválido' };
    if (owned.expedition) return { ok: false, reason: 'Já está em expedição' };
    if (s.heroes.council.includes(hid)) return { ok: false, reason: 'Tire o herói do Conselho primeiro' };
    owned.expedition = { id: exp.id, startedAt: this.now, endsAt: this.now + exp.duration * 1000 };
    this.emit('expeditionStart', { hid, exp });
    return { ok: true };
  }

  collectExpedition(hid) {
    const s = this.state;
    const owned = s.heroes.owned[hid];
    if (!owned?.expedition) return { ok: false, reason: 'Sem expedição' };
    if (owned.expedition.endsAt > this.now) return { ok: false, reason: 'Ainda em andamento' };
    const exp = EXPEDITIONS.find((x) => x.id === owned.expedition.id);
    const reward = expeditionReward(s, HERO_BY_ID[hid], exp, this.econ, Math.random);
    s.res.gold += reward.gold;
    s.res.wood += reward.wood;
    s.res.stone += reward.stone;
    s.res.gems += reward.gems;
    s.items.scrolls += reward.scrolls;
    s.stats.totalGold += reward.gold;
    s.stats.runGold += reward.gold;
    s.stats.expeditions++;
    owned.expedition = null;
    this.track('expedition', 1, XP_REWARDS.expedition * (EXPEDITIONS.indexOf(exp) + 1));
    this.emit('expeditionDone', { hid, reward });
    return { ok: true, reward };
  }

  speedUpExpedition(hid) {
    const s = this.state;
    const owned = s.heroes.owned[hid];
    if (!owned?.expedition) return { ok: false, reason: 'Sem expedição' };
    const remaining = (owned.expedition.endsAt - this.now) / 1000;
    if (remaining <= 0) return { ok: false, reason: 'Já terminou' };
    const cost = speedUpCost(remaining);
    if (s.res.gems < cost) return { ok: false, reason: 'Gemas insuficientes' };
    s.res.gems -= cost;
    owned.expedition.endsAt = this.now;
    return { ok: true };
  }

  // ------------------------------------------------------------ baú
  openChest() {
    const s = this.state;
    if (!s.chest) return { ok: false };
    const e = this.econ;
    const roll = Math.random();
    let reward;
    if (roll < 0.45) reward = { gold: Math.floor(Math.max(60, e.rates.gold * 60)) };
    else if (roll < 0.65) reward = { food: Math.floor(Math.max(40, e.gross.food * 60)), wood: Math.floor(Math.max(30, e.gross.wood * 60)) };
    else if (roll < 0.8) reward = { gems: 1 + (Math.random() < 0.3 ? 1 : 0) };
    else if (roll < 0.9) reward = { stone: Math.floor(Math.max(30, e.gross.stone * 90)) };
    else reward = { boost: 2 };
    for (const [r, v] of Object.entries(reward)) {
      if (r === 'boost') s.boostUntil = Math.max(s.boostUntil, this.now) + v * 60000;
      else s.res[r] += v;
      if (r === 'gold') { s.stats.totalGold += v; s.stats.runGold += v; }
    }
    const at = { x: s.chest.x, y: s.chest.y };
    s.chest = null;
    s.nextChestAt = this.now + randInt(Math.random, CHEST_INTERVAL[0], CHEST_INTERVAL[1]) * 1000;
    s.stats.chests++;
    this.track('chest');
    this.emit('chestOpened', { reward, ...at });
    return { ok: true, reward };
  }

  // ------------------------------------------------------------ progressão: missões, passe, XP
  addXp(amount) {
    const s = this.state;
    const before = tierOf(s.season.xp);
    s.season.xp += Math.round(amount * (1 + this.econ.mods.xp));
    const after = tierOf(s.season.xp);
    if (after > before) this.emit('tierUp', { tier: after });
  }

  trackMission(kind, amount = 1) {
    const list = this.state.season.missions?.list;
    if (!list) return;
    for (const m of list) if (m.track === kind && !m.claimed) m.progress = Math.min(m.target, m.progress + amount);
  }

  track(kind, amount = 1, xpOverride) {
    this.trackMission(kind, amount);
    const xp = xpOverride ?? XP_REWARDS[kind];
    if (xp) this.addXp(xp * amount);
  }

  claimMission(i) {
    const m = this.state.season.missions?.list[i];
    if (!m || m.claimed || m.progress < m.target) return { ok: false, reason: 'Missão incompleta' };
    m.claimed = true;
    this.addXp(m.xp);
    this.emit('toast', { text: `Missão concluída: +${m.xp} XP de temporada`, kind: 'good', icon: 'mission' });
    return { ok: true };
  }

  grant(reward) {
    const s = this.state;
    switch (reward.type) {
      case 'gems': s.res.gems += reward.amount; break;
      case 'scroll': s.items.scrolls += reward.amount; break;
      case 'boost': s.boostUntil = Math.max(s.boostUntil, this.now) + reward.minutes * 60000; break;
      case 'goldMinutes': {
        const v = Math.floor(Math.max(100, this.econ.rates.gold * reward.minutes * 60));
        s.res.gold += v; s.stats.totalGold += v; s.stats.runGold += v; break;
      }
      case 'cosmetic': {
        const list = { title: 'titles', banner: 'banners', emblem: 'emblems' }[reward.kind];
        const value = reward.kind === 'title' ? SEASON_TITLES[reward.id] || reward.id : reward.id;
        if (!s.cosmetics[list].includes(value)) s.cosmetics[list].push(value);
        break;
      }
      default: break;
    }
  }

  claimTier(tier) {
    const s = this.state;
    if (tier < 1 || tier > SEASON_TIERS || tier > tierOf(s.season.xp)) return { ok: false, reason: 'Nível do passe não alcançado' };
    if (s.season.claimed.includes(tier)) return { ok: false, reason: 'Já resgatado' };
    const reward = rewardFor(tier, s);
    s.season.claimed.push(tier);
    this.grant(reward);
    this.emit('toast', { text: `Passe nível ${tier}: ${reward.label}`, kind: 'good', icon: 'star' });
    return { ok: true, reward };
  }

  dailyStatus() {
    const today = dayKey(this.now);
    const y = new Date(this.now);
    y.setDate(y.getDate() - 1); // pela data, não por 24 h: dias de troca de horário têm 23 ou 25 h
    const yesterday = dayKey(y.getTime());
    const d = this.state.daily;
    const available = d.lastDay !== today;
    const nextStreak = d.lastDay === yesterday ? d.streak + 1 : 1;
    return { available, nextStreak, reward: DAILY_REWARDS[(nextStreak - 1) % 7] };
  }

  claimDaily() {
    const s = this.state;
    const st = this.dailyStatus();
    if (!st.available) return { ok: false, reason: 'Volte amanhã' };
    s.daily = { lastDay: dayKey(this.now), streak: st.nextStreak };
    const r = st.reward;
    if (r.gold) s.res.gold += r.gold;
    if (r.gems) s.res.gems += r.gems;
    if (r.goldMinutes) this.grant({ type: 'goldMinutes', minutes: r.goldMinutes });
    if (r.boost) this.grant({ type: 'boost', minutes: r.boost });
    if (r.scroll) s.items.scrolls += r.scroll;
    this.track('daily');
    this.emit('toast', { text: `Dia ${st.nextStreak} seguido: ${r.label}`, kind: 'good', icon: 'calendar' });
    return { ok: true };
  }

  // ------------------------------------------------------------ prestígio
  crownsOnAscend() {
    const s = this.state;
    return Math.floor(Math.sqrt(s.stats.runGold / CROWN_DIVISOR) * (1 + this.econ.crownBonus + this.econ.mods.crowns));
  }

  ascend() {
    const crowns = this.crownsOnAscend();
    if (crowns < 1) return { ok: false, reason: 'Ainda não há Coroas a ganhar' };
    this.lastBuild = null;
    const s = this.state;
    s.res.crowns += crowns;
    s.stats.ascensions++;
    const next = createState({ seed: newSeed(), now: this.now, carry: carryOver(s) });
    next.log = [{ at: this.now, text: `Ascensão nº ${next.stats.ascensions}: +${crowns} Coroas. Um novo reino começa.`, icon: 'crowns' }];
    this.state = next;
    this.econ = computeEconomy(next, this.now);
    this.emit('ascended', { crowns });
    return { ok: true, crowns };
  }

  talentCost(id) {
    const t = TALENT_BY_ID[id];
    const lvl = this.state.legacy[id] || 0;
    return lvl >= t.max ? null : t.baseCost * (lvl + 1);
  }

  buyTalent(id) {
    const cost = this.talentCost(id);
    if (cost == null) return { ok: false, reason: 'Nível máximo' };
    if (this.state.res.crowns < cost) return { ok: false, reason: 'Coroas insuficientes' };
    this.state.res.crowns -= cost;
    this.state.legacy[id] = (this.state.legacy[id] || 0) + 1;
    // Talentos de início valem já na rodada atual de forma parcial: só os de efeito contínuo.
    this.econ = computeEconomy(this.state, this.now);
    return { ok: true };
  }

  // ------------------------------------------------------------ identidade
  setKingdomName(name) {
    const clean = String(name).replace(/[<>]/g, '').trim().slice(0, 24);
    if (!clean) return { ok: false, reason: 'Nome vazio' };
    this.state.kingdom.name = clean;
    return { ok: true };
  }

  ownsCosmetic(kind, id) {
    const def = (kind === 'banner' ? BANNERS : EMBLEMS).find((c) => c.id === id);
    if (!def) return false;
    return def.free || this.state.cosmetics[kind === 'banner' ? 'banners' : 'emblems'].includes(id);
  }

  buyCosmetic(kind, id) {
    const def = (kind === 'banner' ? BANNERS : EMBLEMS).find((c) => c.id === id);
    if (!def || !def.price) return { ok: false, reason: 'Não está à venda' };
    if (this.ownsCosmetic(kind, id)) return { ok: false, reason: 'Já é seu' };
    if (this.state.res.gems < def.price) return { ok: false, reason: 'Gemas insuficientes' };
    this.state.res.gems -= def.price;
    this.state.cosmetics[kind === 'banner' ? 'banners' : 'emblems'].push(id);
    return { ok: true };
  }

  equip(kind, id) {
    if (kind === 'title') {
      if (!this.state.cosmetics.titles.includes(id)) return { ok: false, reason: 'Título bloqueado' };
      this.state.kingdom.title = id;
      return { ok: true };
    }
    if (!this.ownsCosmetic(kind, id)) return { ok: false, reason: 'Bloqueado' };
    this.state.kingdom[kind] = id;
    return { ok: true };
  }

  // ------------------------------------------------------------ social
  rivals() {
    const s = this.state;
    const list = generateRivals(s.social.rivalsSeed, this.now, s.createdAt);
    const me = { id: 'me', name: s.kingdom.name, ruler: 'Você', title: s.kingdom.title, banner: s.kingdom.banner, emblem: s.kingdom.emblem, power: kingdomPower(s), me: true };
    return [...list, me].sort((a, b) => b.power - a.power);
  }

  // Visita conta para estatística/missão uma vez por reino por dia (evita completar missão clicando).
  recordVisit(key) {
    const s = this.state;
    const today = dayKey(this.now);
    s.social.visited ||= {};
    if (s.social.visited[key] === today) return false;
    s.social.visited[key] = today;
    s.stats.visits++;
    this.track('visit');
    return true;
  }

  greetRival(rid) {
    const s = this.state;
    const today = dayKey(this.now);
    if (s.social.greets[rid] === today) return { ok: false, reason: 'Você já saudou este reino hoje' };
    s.social.greets[rid] = today;
    this.recordVisit(rid);
    this.addXp(10);
    let gift = null;
    if (Math.random() < 0.25) {
      gift = 1;
      s.res.gems += 1;
    }
    return { ok: true, gift };
  }

  tradeRival(rid, giveRes) {
    const s = this.state;
    const last = s.social.trades[rid] || 0;
    if (this.now - last < 3600000) return { ok: false, reason: `Próxima troca em ${Math.ceil((3600000 - (this.now - last)) / 60000)} min` };
    const amount = Math.floor(s.res[giveRes] * 0.25);
    if (amount < 10) return { ok: false, reason: 'Recursos insuficientes para trocar' };
    const value = { food: 1, wood: 2, stone: 3 }[giveRes] || 1;
    const gold = Math.floor(amount * value * 1.5);
    s.res[giveRes] -= amount;
    s.res.gold += gold;
    s.stats.totalGold += gold;
    s.stats.runGold += gold;
    s.social.trades[rid] = this.now;
    return { ok: true, amount, gold };
  }

  // ------------------------------------------------------------ desfazer
  // Prêmios que o jogador resgata por ação própria (missão, nível do passe): se mudaram desde a obra,
  // a janela fecha, senão desfazer devolveria o custo e manteria o prêmio.
  undoGuard() {
    const s = this.state;
    return [s.season.number, s.season.claimed.length, s.season.missions?.day,
      (s.season.missions?.list ?? []).filter((m) => m.claimed).length].join('|');
  }

  // Prêmios automáticos que a obra disparou (passo do tutorial, conquista): voltam junto ao desfazer.
  // Sem isto, a primeira obra do jogo quase nunca poderia ser desfeita (a conquista sai em até 2 s).
  undoClawback(u) {
    const s = this.state;
    const back = {};
    const add = (r, v) => { back[r] = (back[r] || 0) + v; };
    for (let i = u.tutorial.step; i < Math.min(s.tutorial.step, TUTORIAL.length); i++) for (const [r, v] of Object.entries(TUTORIAL[i].reward)) add(r, v);
    for (const a of ACHIEVEMENTS) if (s.achievements[a.id] && !u.achs.includes(a.id)) add('gems', a.gems);
    return back;
  }

  canUndo(now = this.now) {
    const u = this.lastBuild;
    if (!u || now - u.at > UNDO_WINDOW) return false;
    const b = this.tileAt(u.x, u.y).b;
    if (!b || b.id !== u.id || b.lvl !== 1 || this.undoGuard() !== u.guard) return false;
    return canAfford(this.state.res, this.undoClawback(u)); // prêmio já gasto: não dá para devolver
  }

  // Devolve 100% do custo e volta estatística, missões e XP ao que eram antes da obra.
  undoBuild() {
    if (!this.canUndo()) { this.lastBuild = null; return { ok: false, reason: 'Não dá mais para desfazer' }; }
    const s = this.state;
    const u = this.lastBuild;
    this.lastBuild = null;
    pay(s.res, this.undoClawback(u));
    for (const id of Object.keys(s.achievements)) if (!u.achs.includes(id)) delete s.achievements[id];
    s.tutorial = { ...u.tutorial };
    s.cosmetics.titles = u.titles;
    if (!u.titles.includes(s.kingdom.title)) s.kingdom.title = u.title;
    s.log = s.log.filter((l) => !(l.at >= u.at && l.text.startsWith('Conquista: ')));
    this.tileAt(u.x, u.y).b = null;
    refund(s.res, u.cost, 1);
    s.stats.built = Math.max(0, s.stats.built - 1);
    s.season.xp = Math.max(0, s.season.xp - u.xp);
    (s.season.missions?.list ?? []).forEach((m, i) => { if (m.track === 'build' && !m.claimed && u.missions[i] !== undefined) m.progress = u.missions[i]; });
    this.econ = computeEconomy(s, this.now);
    this.emit('undone', { id: u.id, x: u.x, y: u.y });
    return { ok: true };
  }

  // ------------------------------------------------------------ melhorias em lote e prévias
  // Melhora o prédio (x, y) quantos níveis der. Retorna quantos níveis subiu.
  upgradeMax(x, y) {
    let n = 0;
    while (this.upgrade(x, y).ok) n++;
    return n;
  }

  // Melhora todos os prédios de um tipo, sempre o de menor nível primeiro, enquanto der para pagar.
  upgradeAll(id) {
    const s = this.state;
    let n = 0;
    for (;;) {
      let best = null;
      s.grid.tiles.forEach((t, i) => {
        if (t.b?.id !== id || !upgradeCost(id, t.b.lvl, this.econ.mods)) return;
        if (!best || t.b.lvl < best.lvl) best = { i, lvl: t.b.lvl };
      });
      if (!best || !this.upgrade(best.i % GRID_W, Math.floor(best.i / GRID_W)).ok) break;
      n++;
    }
    return n;
  }

  // Diferença de produção (por segundo), defesa e capacidade se `mutate` fosse aplicado.
  // A população é considerada já crescida até a capacidade, para a prévia não mentir sobre casas.
  previewDelta(mutate, undo) {
    const s = this.state;
    const settled = () => {
      const pop = s.pop;
      s.pop = Math.max(pop, computeEconomy(s, this.now).popCap);
      const e = computeEconomy(s, this.now);
      s.pop = pop;
      return e;
    };
    const before = settled();
    mutate();
    const after = settled();
    undo();
    const d = { defense: after.defense - before.defense, popCap: after.popCap - before.popCap, happiness: after.happiness - before.happiness };
    for (const r of PROD_RES) d[r] = after.rates[r] - before.rates[r];
    return d;
  }

  previewBuild(id, x, y) {
    const tile = this.tileAt(x, y);
    if (tile.b) return null;
    return this.previewDelta(() => { tile.b = { id, lvl: 1 }; }, () => { tile.b = null; });
  }

  previewUpgrade(x, y) {
    const tile = this.tileAt(x, y);
    if (!tile.b || !upgradeCost(tile.b.id, tile.b.lvl, this.econ.mods)) return null;
    return this.previewDelta(() => { tile.b.lvl++; }, () => { tile.b.lvl--; });
  }

  // Conselho de quando ascender (inspirado no "anjos ao resetar" do AdVenture Capitalist):
  // recomendado quando a Ascensão pelo menos dobra as Coroas que você já conquistou.
  ascendAdvice() {
    const s = this.state;
    const crowns = this.crownsOnAscend();
    const spent = Object.entries(s.legacy).reduce((sum, [id, lvl]) => {
      const t = TALENT_BY_ID[id];
      return sum + (t ? (t.baseCost * lvl * (lvl + 1)) / 2 : 0);
    }, 0);
    const owned = s.res.crowns + spent;
    const mult = 1 + this.econ.crownBonus + this.econ.mods.crowns;
    const nextGold = CROWN_DIVISOR * ((crowns + 1) / mult) ** 2;
    const rate = Math.max(0, this.econ.rates.gold);
    const secondsToNext = rate > 0 ? Math.max(0, (nextGold - s.stats.runGold) / rate) : Infinity;
    return { crowns, owned, recommended: crowns >= 1 && crowns >= Math.max(1, owned), secondsToNext };
  }

  // ------------------------------------------------------------ desbloqueio gradual
  isTabUnlocked(tab) {
    return this.state.unlocks.tabs.includes(tab);
  }

  checkUnlocks() {
    for (const [tab, rule] of Object.entries(TAB_UNLOCKS)) {
      if (this.isTabUnlocked(tab) || !rule.check(this)) continue;
      this.state.unlocks.tabs.push(tab);
      this.emit('unlock', { tab, name: TAB_NAMES[tab] });
    }
  }

  // ------------------------------------------------------------ conquistas e tutorial
  checkAchievements() {
    const s = this.state;
    for (const a of ACHIEVEMENTS) {
      if (s.achievements[a.id]) continue;
      if (a.check(s, this.econ, HERO_BY_ID)) {
        s.achievements[a.id] = this.now;
        s.res.gems += a.gems;
        if (a.title && !s.cosmetics.titles.includes(a.title)) s.cosmetics.titles.push(a.title);
        this.log(`Conquista: ${a.name}`, a.icon);
        this.emit('achievement', a);
      }
    }
  }

  checkTutorial() {
    const s = this.state;
    if (s.tutorial.done) return;
    const step = TUTORIAL[s.tutorial.step];
    if (!step) { s.tutorial.done = true; return; }
    if (step.done(s)) {
      for (const [r, v] of Object.entries(step.reward)) s.res[r] += v;
      s.tutorial.step++;
      if (s.tutorial.step >= TUTORIAL.length) s.tutorial.done = true;
      this.emit('tutorial', { step: s.tutorial.step });
    }
  }
}

export { RECRUIT_GEM_COST };
