// Estado compartilhado da interface e utilitários de HTML.
import { RESOURCES } from '../data/buildings.js';
import { BANNERS, EMBLEMS } from '../data/cosmetics.js';
import { fmt } from '../core/format.js';
import { resIco } from './icons.js';

export const ui = {
  game: null,
  renderer: null,
  config: null,
  tab: 'reino',
  visiting: null,
  pointerHeld: false,
  hoverDelta: null,
};

export const $ = (sel) => document.querySelector(sel);

export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function costHtml(cost, res) {
  return Object.entries(cost)
    .map(([r, v]) => `<span class="cost ${res && (res[r] || 0) < v ? 'short' : ''}" title="${RESOURCES[r]?.name ?? 'Pergaminho'}">${resIco(r)}${fmt(v)}</span>`)
    .join(' ');
}


export const bannerColor = (id) => BANNERS.find((b) => b.id === id)?.color ?? '#c92a2a';
export const emblemIcon = (id) => EMBLEMS.find((e) => e.id === id)?.icon ?? 'crowns';

// Texto curto do ganho por segundo (prévia): "+1,2 ouro/s, +4 moradores".
export function deltaText(d) {
  if (!d) return '';
  const parts = [];
  const names = { gold: 'ouro', food: 'comida', wood: 'madeira', stone: 'pedra' };
  for (const r of Object.keys(names)) if (Math.abs(d[r]) >= 0.05) parts.push(`${d[r] > 0 ? '+' : ''}${fmt(d[r])} ${names[r]}/s`);
  if (Math.abs(d.defense) >= 0.5) parts.push(`${d.defense > 0 ? '+' : ''}${fmt(d.defense)} defesa`);
  if (d.popCap) parts.push(`+${d.popCap} moradores`);
  if (Math.abs(d.happiness) >= 0.5) parts.push(`${d.happiness > 0 ? '+' : ''}${fmt(d.happiness)} felicidade`);
  return parts.join(', ') || 'sem ganho direto';
}
