// Tela de estatísticas da Ascensão: fecha a rodada com o que foi conquistado e aponta a próxima.
// Abre sozinha ao ascender e pode ser reaberta pelo histórico na aba Legado.
import { BUILDINGS } from '../data/buildings.js';
import { TALENTS } from '../data/talents.js';
import { fmt, fmtRate, fmtTime } from '../core/format.js';
import { BUILDING_SPRITES } from './sprites.js';
import { ui, esc } from './ctx.js';
import { ico, resIco } from './icons.js';
import { showModal } from './modals.js';

const COUNT_MS = 1100;

// Números do resumo "contam" até o valor final. Com "Reduzir movimento", aparecem prontos.
export function animateCounts(root) {
  const els = [...root.querySelectorAll('[data-count]')];
  const show = (el, v) => { el.textContent = formatValue(Number(el.dataset.count) * v, el.dataset.kind); };
  if (ui.config.reduceMotion) { els.forEach((el) => show(el, 1)); return; }
  const t0 = performance.now();
  const tick = (now) => {
    const p = Math.min(1, (now - t0) / COUNT_MS);
    const e = 1 - (1 - p) ** 3;
    els.forEach((el) => show(el, e));
    if (p < 1 && root.isConnected) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function formatValue(v, kind) {
  if (kind === 'time') return fmtTime(v);
  if (kind === 'rate') return fmtRate(v);
  if (kind === 'pct') return `+${Math.round(v * 100)}%`;
  return fmt(Math.floor(v));
}

const count = (value, kind = 'int') => `<b data-count="${value}" data-kind="${kind}">${formatValue(0, kind)}</b>`;

// summary vem de Game.runSummary(); fresh = acabou de ascender (mostra a chamada para a próxima rodada).
export function showRunSummary(summary, { fresh = false } = {}) {
  const g = ui.game;
  const rec = new Set(summary.newRecords ?? []);
  const badge = (k) => (rec.has(k) ? '<span class="as-rec">Recorde</span>' : '');
  const tile = (label, value, { kind = 'int', sub = '', key = null, icon = null } = {}) => (value == null ? '' : `
    <div class="as-tile ${key && rec.has(key) ? 'is-rec' : ''}">${badge(key)}
      <small>${icon ? ico(icon) : ''}${label}</small>${count(value, kind)}${sub ? `<em>${sub}</em>` : ''}</div>`);
  const tiles = [
    tile('Duração da rodada', summary.duration, { kind: 'time', icon: 'time', sub: summary.played != null ? `${fmtTime(summary.played)} com o jogo aberto` : '' }),
    tile('Ouro na rodada', summary.gold, { key: 'gold', icon: 'gold' }),
    tile('Ouro por segundo no fim', summary.goldRate, { kind: 'rate', key: 'goldRate', icon: 'stats' }),
    tile('Poder do Reino', summary.power, { key: 'power', icon: 'trophy' }),
    tile('Construções erguidas', summary.built, { icon: 'build', sub: summary.upgrades != null ? `${fmt(summary.upgrades)} melhorias` : '' }),
    tile('Prédios no mapa', summary.buildings, { icon: 'house', sub: `maior nível ${summary.maxLvl} · anel ${summary.ring} de 5` }),
    tile('Hordas vencidas', summary.raidsWon, { key: 'raidsWon', icon: 'swords', sub: summary.raidsLost != null ? `${fmt(summary.raidsLost)} derrota(s)` : '' }),
    tile('Expedições', summary.expeditions, { icon: 'expedition', sub: summary.chests != null ? `${fmt(summary.chests)} carroça(s) atendida(s)` : '' }),
  ].join('');
  const c = summary.combo;
  const combo = c ? `<div class="as-combo ${rec.has('combo') ? 'is-rec' : ''}">${badge('combo')}
      <img src="${BUILDING_SPRITES[c.id]?.src}" alt="">
      <span><small>Melhor combo da rodada</small><b>${BUILDINGS[c.id]?.name ?? c.id}</b> nível ${c.lvl}: ${count(c.bonus, 'pct')} dos vizinhos</span></div>` : '';

  let next = '';
  if (fresh) {
    const crowns = g.state.res.crowns;
    const affordable = TALENTS.filter((t) => { const cost = g.talentCost(t.id); return cost != null && cost <= crowns; });
    const cheapest = TALENTS.map((t) => ({ t, cost: g.talentCost(t.id) })).filter((x) => x.cost != null).sort((a, b) => a.cost - b.cost)[0];
    next = `<div class="as-next">
      <h3>${ico('emblem-tree')} Próxima rodada</h3>
      ${affordable.length
        ? `<p>Com ${crowns} Coroas você já pode comprar:</p><ul class="as-talents">${affordable.slice(0, 4).map((t) => `<li>${ico(t.icon)}<span><b>${t.name}</b> ${t.desc((g.state.legacy[t.id] || 0) + 1)}</span><em>${resIco('crowns')}${g.talentCost(t.id)}</em></li>`).join('')}</ul>`
        : cheapest ? `<p>Junte ${cheapest.cost - crowns} Coroa(s) a mais para <b>${cheapest.t.name}</b>.</p>` : '<p>A Árvore de Legado está completa.</p>'}
      <div class="row">${affordable.length ? `<button class="btn primary" data-action="toLegacy" data-autofocus>${ico('crowns')} Gastar Coroas no Legado</button><button class="btn" data-action="closeModal">Começar o novo reino</button>`
        : '<button class="btn primary" data-action="closeModal" data-autofocus>Começar o novo reino</button>'}</div>
    </div>`;
  }

  showModal(`<div class="ascend-sum">
      <div class="as-hero">
        <div class="as-crown">${resIco('crowns')}</div>
        <p class="as-kicker">${fresh ? 'Ascensão' : 'Rodada'} nº ${summary.n} · ${esc(summary.name)}</p>
        <div class="as-crowns">+${count(summary.crowns)} <span>${summary.crowns === 1 ? 'Coroa' : 'Coroas'}</span></div>
        ${summary.totalCrowns != null ? `<small>Coroas guardadas depois desta Ascensão: ${fmt(summary.totalCrowns)}</small>` : ''}
        ${rec.size ? `<p class="as-recs">${rec.size} ${rec.size === 1 ? 'novo recorde' : 'novos recordes'} nesta rodada</p>` : ''}
      </div>
      <div class="as-grid">${tiles}</div>
      ${combo}
      ${summary.built == null ? '<p class="muted as-note">Este save é de antes do resumo de rodadas: alguns números não foram registrados.</p>' : ''}
      ${next || '<div class="row"><button class="btn big primary" data-action="closeModal" data-autofocus>Fechar</button></div>'}
    </div>`, 'wide', { priority: fresh });
  animateCounts(document.getElementById('modal'));
}

// Linhas do histórico na aba Legado.
export function runHistoryHtml(runs) {
  if (!runs?.length) return '';
  return `<section class="card"><h3>${ico('scroll')} Rodadas anteriores <span class="count">${runs.length}</span></h3>
    <ul class="runs">${runs.map((r, i) => `<li>
      <span class="rn">nº ${r.n}</span>
      <span><b>+${fmt(r.crowns)} ${resIco('crowns')}</b><small>${fmtTime(r.duration)} · ${fmt(r.gold)} de ouro${r.newRecords?.length ? ' · recorde' : ''}</small></span>
      <button class="btn small" data-action="runSummary" data-arg="${i}">Ver resumo</button></li>`).join('')}</ul></section>`;
}
