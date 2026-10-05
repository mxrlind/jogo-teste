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

export const TUTORIAL = [
  { text: 'Construa uma 🪓 Serraria ao lado de uma 🌲 floresta.', done: (s) => countOf(s, 'serraria') >= 1, reward: { gold: 50 } },
  { text: 'Construa mais uma 🏠 Casa — mais moradores, mais trabalho.', done: (s) => countOf(s, 'casa') >= 2, reward: { gold: 60, wood: 20 } },
  { text: 'Use o pergaminho grátis: recrute um herói na aba Heróis.', done: (s) => Object.keys(s.heroes.owned).length >= 1, reward: { gold: 80 } },
  { text: 'Hordas atacam a cada poucos minutos! Construa uma 🧱 Muralha ou 🗼 Torre.', done: (s) => countOf(s, 'muralha') + countOf(s, 'torre') >= 1, reward: { stone: 40 } },
  { text: 'Construa um 🏪 Mercado encostado em casas.', done: (s) => countOf(s, 'mercado') >= 1, reward: { gold: 150 } },
  { text: 'Não existe "missão final": o reino é seu. Chegue a 10 construções e veja o que consegue criar.', done: (s) => s.grid.tiles.filter((t) => t.b).length >= 10, reward: { gems: 3 } },
];

export class Game {
  constructor(state, now = Date.now()) {
    this.state = state;
    this.listeners = {};
    this.lastAchCheck = 0;
    this.econ = computeEconomy(state, now);
    this.now = now;
  }

  on(evt, fn) {
    (this.listeners[evt] ||= []).push(fn);
    return this;
  }

  emit(evt, data) {
    for (const fn of this.listeners[evt] || []) fn(data);
  }

  log(text) {
    this.state.log.unshift({ at: this.now, text });
    if (this.state.log.length > 50) this.state.log.pop();
  }

  // ------------------------------------------------------------ loop
  tick(now = Date.now()) {
    const s = this.state;
    this.now = now;
    const dt = (now - s.lastTick) / 1000;
    if (dt <= 0) return;
    if (dt > OFFLINE_THRESHOLD) {
      const summary = this.catchUp(now);
      if (summary) this.emit('offline', summary);
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
      if (syncSeason(s, now)) this.emit('toast', { text: '🎊 Uma nova temporada começou!', kind: 'season' });
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
  catchUp(now) {
    const s = this.state;
    const elapsed = (now - s.lastTick) / 1000;
    const mods = computeEconomy(s, now).mods;
    const capSec = (BASE_OFFLINE_HOURS + mods.offlineHours) * 3600;
    const eff = Math.min(1, BASE_OFFLINE_EFF + mods.offlineEff);
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
      this.emit('raidWarning', { name: s.raid.name, strength: this.raidStrength(), defense: e.defense });
    }
    if (now >= s.raid.nextAt) this.resolveRaid(now);

    // Eventos relâmpago
    if (s.event && s.event.endsAt <= now) {
      this.emit('toast', { text: `${EVENT_BY_ID[s.event.id].icon} ${EVENT_BY_ID[s.event.id].name} terminou.`, kind: 'info' });
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
      this.log(`${ev.icon} Evento: ${ev.name}`);
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
        this.emit('toast', { text: `${HERO_BY_ID[hid].icon} ${HERO_BY_ID[hid].name} voltou da expedição!`, kind: 'good' });
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
      this.log(`⚔️ Vitória contra ${name} (força ${strength}): +${Math.floor(loot)} ouro, +${gems} 💎`);
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
      this.log(`🔥 ${name} saquearam o reino (força ${strength} vs defesa ${Math.floor(e.defense)}).`);
    }
    const interval = RAID_INTERVAL * e.mods.raidInterval * (0.8 + Math.random() * 0.4);
    s.raid.nextAt = now + interval * 1000;
    s.raid.warned = false;
    s.raid.name = null;
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
    return this.state.stats.built + 2 >= def.unlock.buildings || this.state.grid.tiles.filter((t) => t.b).length >= def.unlock.buildings;
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
    pay(s.res, cost);
    tile.b = { id, lvl: 1 };
    s.stats.built++;
    this.econ = computeEconomy(s, this.now);
    this.track('build');
    this.emit('built', { id, x, y });
    return { ok: true };
  }

  upgrade(x, y) {
    const s = this.state;
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
    if (s.grid.ring >= MAX_RING) return { ok: false, reason: 'O mapa inteiro já é seu' };
    const cost = this.expandCost();
    if (!canAfford(s.res, cost)) return { ok: false, reason: 'Recursos insuficientes' };
    pay(s.res, cost);
    s.grid.ring++;
    this.log(`🗺️ O reino se expandiu para o anel ${s.grid.ring}.`);
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
    this.log(`📜 Recrutou ${result.hero.icon} ${result.hero.name}${result.isNew ? '' : ` (★${result.stars})`}`);
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
    this.emit('toast', { text: `✅ Missão concluída: +${m.xp} XP de temporada`, kind: 'good' });
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
    this.emit('toast', { text: `🎁 Passe nível ${tier}: ${reward.label}`, kind: 'good' });
    return { ok: true, reward };
  }

  dailyStatus() {
    const today = dayKey(this.now);
    const yesterday = dayKey(this.now - 86400000);
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
    this.emit('toast', { text: `📅 Dia ${st.nextStreak} seguido: ${r.label}`, kind: 'good' });
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
    const s = this.state;
    s.res.crowns += crowns;
    s.stats.ascensions++;
    const next = createState({ seed: newSeed(), now: this.now, carry: carryOver(s) });
    next.log = [{ at: this.now, text: `👑 Ascensão nº ${next.stats.ascensions}: +${crowns} Coroas. Um novo reino começa.` }];
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

  // ------------------------------------------------------------ conquistas e tutorial
  checkAchievements() {
    const s = this.state;
    for (const a of ACHIEVEMENTS) {
      if (s.achievements[a.id]) continue;
      if (a.check(s, this.econ, HERO_BY_ID)) {
        s.achievements[a.id] = this.now;
        s.res.gems += a.gems;
        if (a.title && !s.cosmetics.titles.includes(a.title)) s.cosmetics.titles.push(a.title);
        this.log(`🏆 Conquista: ${a.name}`);
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
