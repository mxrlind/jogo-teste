// Modais (em fila) e notificações.
import { $ } from './ctx.js';
import { ico } from './icons.js';

const queue = [];
let pendingConfirm = null;
let lastFocus = null;
let onCloseCb = null;

export function modalOpen() {
  return !$('#modal').hidden;
}

// opts.priority = true mostra na hora (empurrando o atual para a fila); padrão: espera o atual fechar.
export function showModal(html, cls = '', opts = {}) {
  const m = $('#modal');
  if (!m.hidden && !opts.priority) { queue.push([html, cls, opts]); return; }
  if (!m.hidden && opts.priority) queue.unshift([m.dataset.html, m.dataset.cls, {}]);
  lastFocus = document.activeElement;
  m.dataset.html = html;
  m.dataset.cls = cls;
  m.innerHTML = `<div class="sheet panel ${cls}">${html}</div>`;
  m.hidden = false;
  onCloseCb = opts.onClose ?? null;
  const first = m.querySelector('[data-autofocus], button, input, select, textarea');
  first?.focus({ preventScroll: true });
}

export function closeModal() {
  const m = $('#modal');
  if (m.hidden) return;
  m.hidden = true;
  pendingConfirm = null;
  const cb = onCloseCb;
  onCloseCb = null;
  cb?.();
  const next = queue.shift();
  if (next) showModal(...next);
  else lastFocus?.focus?.({ preventScroll: true });
}

export function confirmModal(html, fn, { yes = 'Confirmar', danger = false } = {}) {
  showModal(`${html}<div class="row"><button class="btn ${danger ? 'danger' : 'primary'}" data-action="confirmYes" data-autofocus>${yes}</button><button class="btn" data-action="closeModal">Cancelar</button></div>`, '', { priority: true });
  pendingConfirm = fn;
}

export function runConfirm() {
  const fn = pendingConfirm;
  pendingConfirm = null;
  closeModal();
  fn?.();
}

export function toast(text, kind = 'info', icon = null) {
  const box = $('#toasts');
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.innerHTML = `${icon ? ico(icon) : ''}<span></span>`;
  el.querySelector('span').textContent = text;
  box.prepend(el);
  while (box.children.length > 5) box.lastChild.remove();
  setTimeout(() => el.classList.add('out'), 4200);
  setTimeout(() => el.remove(), 4700);
}
