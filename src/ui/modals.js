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

export function modalClosable() {
  return $('#modal').dataset.closable !== 'false';
}

// opts.priority = true mostra na hora (empurrando o atual para a fila); padrão: espera o atual fechar.
// opts.closable = false esconde o X (telas em que a escolha precisa ser feita pelos botões).
export function showModal(html, cls = '', opts = {}) {
  const m = $('#modal');
  if (!m.hidden && !opts.priority) { queue.push([html, cls, opts]); return; }
  if (!m.hidden && opts.priority) queue.unshift([m.dataset.html, m.dataset.cls, { closable: m.dataset.closable !== 'false' }]);
  lastFocus = document.activeElement;
  m.dataset.html = html;
  m.dataset.cls = cls;
  m.dataset.closable = String(opts.closable !== false);
  const x = opts.closable === false ? '' : `<button class="btn small icon-only modal-x" data-action="closeModal" aria-label="Fechar">${ico('close')}</button>`;
  m.innerHTML = `<div class="sheet panel ${cls}">${x}${html}</div>`;
  m.hidden = false;
  onCloseCb = opts.onClose ?? null;
  const first = m.querySelector('[data-autofocus], button:not(.modal-x), input, select, textarea');
  first?.focus({ preventScroll: true });
}

// Troca o conteúdo da janela aberta sem fechar (opções, créditos carregados depois). Mantém o X.
export function replaceModal(html) {
  const sheet = $('#modal .sheet');
  if (!sheet) return;
  const x = sheet.querySelector(':scope > .modal-x');
  sheet.innerHTML = html;
  if (x) sheet.prepend(x);
  $('#modal').dataset.html = html;
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
  showModal(`${html}<div class="row" style="margin-top:1rem"><button class="btn ${danger ? 'danger' : 'primary'}" data-action="confirmYes" data-autofocus>${yes}</button><button class="btn" data-action="closeModal">Cancelar</button></div>`, '', { priority: true });
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
  const items = box.querySelectorAll('.toast:not(.undo)'); // o aviso de desfazer não conta nem sai antes da hora
  if (items.length > 5) for (let i = 5; i < items.length; i++) items[i].remove();
  setTimeout(() => el.classList.add('out'), 4200);
  setTimeout(() => el.remove(), 4700);
}
