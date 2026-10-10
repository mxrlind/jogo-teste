// Preferências do dispositivo (volume, acessibilidade, atalhos). Ficam fora do save do reino:
// começar um reino novo ou ascender não deve zerar o volume de ninguém.
export const CONFIG_KEY = 'reino-de-bolso:config';
export const CONFIG_VERSION = 1;

// Ações remapeáveis e teclas padrão (valores de KeyboardEvent.key, em minúsculas).
export const KEY_ACTIONS = [
  { id: 'menu', label: 'Abrir o menu / cancelar', key: 'escape' },
  { id: 'up', label: 'Cursor para cima', key: 'arrowup' },
  { id: 'down', label: 'Cursor para baixo', key: 'arrowdown' },
  { id: 'left', label: 'Cursor para a esquerda', key: 'arrowleft' },
  { id: 'right', label: 'Cursor para a direita', key: 'arrowright' },
  { id: 'confirm', label: 'Confirmar no tile do cursor', key: 'enter' },
  { id: 'upgrade', label: 'Melhorar o prédio selecionado', key: 'u' },
  { id: 'move', label: 'Mover o prédio selecionado', key: 'm' },
  { id: 'sell', label: 'Demolir o prédio selecionado', key: 'delete' },
  { id: 'nextTab', label: 'Próxima aba do painel', key: 't' },
  { id: 'undo', label: 'Desfazer a última construção', key: 'z' },
];

export function defaultConfig() {
  return {
    version: CONFIG_VERSION,
    masterVolume: 1,
    musicVolume: 0.5,
    musicOn: true,
    sfxVolume: 0.8,
    muteInBackground: true,
    batterySaver: false,
    confirmDemolish: true,
    particles: true,
    villagers: true,
    reduceMotion: false,
    fontScale: 1,
    highContrast: false,
    keys: Object.fromEntries(KEY_ACTIONS.map((a) => [a.id, a.key])),
  };
}

const clamp = (v, lo, hi, d) => (Number.isFinite(Number(v)) ? Math.min(hi, Math.max(lo, Number(v))) : d);

// Aceita config salva (qualquer versão) e/ou as configurações antigas do save v1 ({ sound, particles }).
export function normalizeConfig(raw, legacySettings = null) {
  const d = defaultConfig();
  const c = raw && typeof raw === 'object' ? raw : {};
  if (legacySettings && !raw) {
    if (legacySettings.sound === false) d.sfxVolume = 0;
    if (legacySettings.particles === false) d.particles = false;
  }
  const keys = { ...d.keys };
  for (const a of KEY_ACTIONS) if (typeof c.keys?.[a.id] === 'string' && c.keys[a.id]) keys[a.id] = c.keys[a.id].toLowerCase();
  const bool = (k) => (typeof c[k] === 'boolean' ? c[k] : d[k]);
  return {
    version: CONFIG_VERSION,
    masterVolume: clamp(c.masterVolume, 0, 1, d.masterVolume),
    musicVolume: clamp(c.musicVolume, 0, 1, d.musicVolume),
    musicOn: bool('musicOn'),
    sfxVolume: clamp(c.sfxVolume, 0, 1, d.sfxVolume),
    muteInBackground: bool('muteInBackground'),
    batterySaver: bool('batterySaver'),
    confirmDemolish: bool('confirmDemolish'),
    particles: bool('particles'),
    villagers: bool('villagers'),
    reduceMotion: bool('reduceMotion'),
    fontScale: clamp(c.fontScale, 0.85, 1.5, d.fontScale),
    highContrast: bool('highContrast'),
    keys,
  };
}

// Volumes que de fato tocam: o volume geral multiplica música e efeitos, e a aba em segundo plano
// silencia tudo quando a opção está ligada.
export function effectiveVolumes(config, hidden = false) {
  const m = hidden && config.muteInBackground ? 0 : config.masterVolume;
  return { music: config.musicVolume * m, sfx: config.sfxVolume * m };
}

// Restaura as opções padrão sem mexer nas teclas (elas têm botão próprio).
export function resetOptions(config) {
  return { ...defaultConfig(), keys: { ...config.keys } };
}

// Primeira ação ligada a uma tecla (para o atalho e para detectar conflitos no remapeamento).
export function actionForKey(config, key) {
  const k = String(key).toLowerCase();
  return KEY_ACTIONS.find((a) => config.keys[a.id] === k)?.id ?? null;
}

export function keyLabel(key) {
  const names = { escape: 'Esc', enter: 'Enter', delete: 'Delete', tab: 'Tab', ' ': 'Espaço', arrowup: 'Seta para cima', arrowdown: 'Seta para baixo', arrowleft: 'Seta para a esquerda', arrowright: 'Seta para a direita', backspace: 'Backspace' };
  return names[key] ?? (key.length === 1 ? key.toUpperCase() : key);
}
