// Persistência com proteção contra corrupção.
// Formato gravado (envelope):  { "format": "reino-de-bolso", "v": <SAVE_VERSION>, "sum": "<fnv1a hex>", "data": "<json do estado>" }
// - checksum detecta truncamento/edição acidental;
// - backups em rodízio (BACKUP_SLOTS) a cada BACKUP_INTERVAL;
// - save antigo (v1, JSON puro sem envelope) continua sendo lido;
// - nada é sobrescrito sem antes guardar a versão ilegível em ':corrompido'.
// `store` é qualquer objeto com getItem/setItem/removeItem (localStorage no navegador, Map nos testes).
import { SAVE_KEY, SAVE_VERSION, serialize, migrateWithSettings } from './state.js';

export const BACKUP_SLOTS = 3;
export const BACKUP_INTERVAL = 5 * 60 * 1000;
export const CORRUPT_KEY = SAVE_KEY + ':corrompido';
const backupKey = (i) => `${SAVE_KEY}:backup:${i}`;
const META_KEY = SAVE_KEY + ':meta';

export function checksum(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

export function encodeSave(state) {
  const data = serialize(state);
  return JSON.stringify({ format: 'reino-de-bolso', v: SAVE_VERSION, sum: checksum(data), data });
}

// Decodifica envelope (v2+) ou JSON puro (v1). Lança erro se o conteúdo estiver corrompido.
export function decodeSave(raw) {
  if (typeof raw !== 'string' || !raw.trim()) throw new Error('Save vazio');
  const outer = JSON.parse(raw);
  if (outer && outer.format === 'reino-de-bolso') {
    if (typeof outer.data !== 'string' || checksum(outer.data) !== outer.sum) throw new Error('Checksum não confere');
    return migrateWithSettings(JSON.parse(outer.data));
  }
  return migrateWithSettings(outer); // v1: estado puro
}

// Carrega o melhor save disponível: principal, senão o backup mais recente que estiver íntegro.
// Retorna { state, legacySettings, source: 'principal' | 'backup:N' | null, recovered: boolean }.
export function loadSave(store) {
  const main = store.getItem(SAVE_KEY);
  if (main) {
    try {
      return { ...decodeSave(main), source: 'principal', recovered: false };
    } catch (err) {
      try { store.setItem(CORRUPT_KEY, main); } catch { /* sem espaço: segue tentando os backups */ }
    }
  }
  const candidates = [];
  for (let i = 0; i < BACKUP_SLOTS; i++) {
    const raw = store.getItem(backupKey(i));
    if (!raw) continue;
    try {
      const decoded = decodeSave(raw);
      candidates.push({ ...decoded, source: `backup:${i}`, at: decoded.state.lastTick || 0 });
    } catch { /* backup ruim: ignora */ }
  }
  candidates.sort((a, b) => b.at - a.at);
  if (candidates.length) return { ...candidates[0], recovered: true };
  return { state: null, legacySettings: null, source: null, recovered: Boolean(main) };
}

// Grava o principal e, se passou o intervalo, um backup no próximo slot do rodízio.
export function writeSave(store, state, now = Date.now()) {
  const encoded = encodeSave(state);
  store.setItem(SAVE_KEY, encoded);
  let meta = { lastBackupAt: 0, next: 0 };
  try { meta = { ...meta, ...JSON.parse(store.getItem(META_KEY) || '{}') }; } catch { /* meta ruim: recomeça */ }
  if (now - meta.lastBackupAt >= BACKUP_INTERVAL) {
    store.setItem(backupKey(meta.next % BACKUP_SLOTS), encoded);
    meta = { lastBackupAt: now, next: (meta.next + 1) % BACKUP_SLOTS };
    store.setItem(META_KEY, JSON.stringify(meta));
  }
  return encoded.length;
}

// Código de exportação: base64 do envelope (com checksum). Aceita também códigos antigos (v1).
const toB64 = (str) => btoa(String.fromCharCode(...new TextEncoder().encode(str)));
const fromB64 = (b64) => new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));

export function exportCode(state) {
  return toB64(encodeSave(state));
}

export function importCode(code) {
  return decodeSave(fromB64(String(code).trim()));
}

export function clearSave(store) {
  store.removeItem(SAVE_KEY);
  // backups ficam: "apagar progresso" pede confirmação, mas um backup ainda salva um clique errado
}

export function listBackups(store) {
  const out = [];
  for (let i = 0; i < BACKUP_SLOTS; i++) {
    const raw = store.getItem(backupKey(i));
    if (!raw) continue;
    try {
      const { state } = decodeSave(raw);
      out.push({ slot: i, at: state.lastTick, name: state.kingdom?.name, gold: state.stats?.totalGold ?? 0 });
    } catch { out.push({ slot: i, broken: true }); }
  }
  return out.sort((a, b) => (b.at || 0) - (a.at || 0));
}

export function restoreBackup(store, slot) {
  const raw = store.getItem(backupKey(slot));
  const decoded = decodeSave(raw);
  store.setItem(SAVE_KEY, raw);
  return decoded;
}
