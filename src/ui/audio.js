// Áudio: efeitos (Kenney, CC0) via Web Audio e música em loop (opcional) via <audio>.
// - Nada toca antes do primeiro gesto do jogador (política de autoplay dos navegadores).
// - Volumes separados para música e efeitos; a música "abaixa" durante fanfarras (ducking).
// - A música só existe se assets/music/music.json listar uma faixa (ver EXECUTAR.md).
export const SFX_NAMES = ['click', 'open', 'close', 'error', 'tab', 'upgrade', 'confirm', 'event', 'build', 'mine', 'warn',
  'coin', 'cart', 'chop', 'recruit', 'expedition', 'win', 'lose', 'tier', 'achievement', 'legendary', 'ascend'];
const JINGLES = new Set(['win', 'lose', 'tier', 'achievement', 'legendary', 'ascend']);

let ctx = null;
let sfxGain = null;
let unlocked = false;
let sfxVolume = 0.8;
let musicVolume = 0.5;
const raw = new Map(); // nome -> ArrayBuffer (baixado no carregamento)
const buffers = new Map(); // nome -> AudioBuffer (decodificado após o gesto)
let music = null;
let musicTrack = null;
let duckTimer = null;

export async function loadSfx(onProgress) {
  let done = 0;
  await Promise.all(SFX_NAMES.map(async (n) => {
    try {
      const res = await fetch(`assets/sfx/${n}.mp3`);
      if (res.ok) raw.set(n, await res.arrayBuffer());
    } catch { /* sem som: o jogo segue */ }
    onProgress?.(++done, SFX_NAMES.length);
  }));
  try {
    const res = await fetch('assets/music/music.json', { cache: 'no-store' });
    if (res.ok) {
      const list = await res.json();
      musicTrack = Array.isArray(list.tracks) && list.tracks[0] ? list.tracks[0] : null;
    }
  } catch { musicTrack = null; }
}

export function hasMusic() {
  return Boolean(musicTrack);
}

export function musicInfo() {
  return musicTrack;
}

async function unlock() {
  if (unlocked) return;
  unlocked = true;
  const AC = window.AudioContext || window.webkitAudioContext;
  if (AC) {
    ctx = new AC();
    sfxGain = ctx.createGain();
    sfxGain.gain.value = sfxVolume;
    sfxGain.connect(ctx.destination);
    for (const [n, buf] of raw) {
      ctx.decodeAudioData(buf.slice(0)).then((b) => buffers.set(n, b)).catch(() => {});
    }
  }
  startMusic();
}

export function initAudio(config) {
  setVolumes(config.musicVolume, config.sfxVolume);
  const once = () => { unlock(); window.removeEventListener('pointerdown', once, true); window.removeEventListener('keydown', once, true); };
  window.addEventListener('pointerdown', once, true);
  window.addEventListener('keydown', once, true);
}

export function setVolumes(m, s) {
  musicVolume = m;
  sfxVolume = s;
  if (sfxGain) sfxGain.gain.value = s;
  if (music) music.volume = m;
  if (music && m > 0 && music.paused && unlocked) music.play().catch(() => {});
}

function startMusic() {
  if (!musicTrack || music) return;
  music = new Audio(`assets/music/${musicTrack.file}`);
  music.loop = true;
  music.volume = musicVolume;
  if (musicVolume > 0) music.play().catch(() => {});
}

function duck() {
  if (!music) return;
  music.volume = musicVolume * 0.3;
  clearTimeout(duckTimer);
  duckTimer = setTimeout(() => { if (music) music.volume = musicVolume; }, 1800);
}

export function play(name, volume = 1) {
  if (!unlocked || !ctx || sfxVolume <= 0) return;
  const buf = buffers.get(name);
  if (!buf) return;
  if (ctx.state === 'suspended') ctx.resume();
  const src = ctx.createBufferSource();
  src.buffer = buf;
  const g = ctx.createGain();
  g.gain.value = volume;
  src.connect(g).connect(sfxGain);
  src.start();
  if (JINGLES.has(name)) duck();
}
