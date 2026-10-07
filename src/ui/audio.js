// Áudio: efeitos (Kenney, CC0) via Web Audio e trilha sonora via <audio>.
// - Nada toca antes do primeiro gesto do jogador (política de autoplay dos navegadores).
// - Volumes separados para música e efeitos; a música "abaixa" durante fanfarras (ducking).
// - assets/music/music.json lista as faixas, cada uma com um clima ("vila" ou "batalha").
//   As faixas do clima atual tocam em sequência; trocar de clima faz uma transição suave.
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
let musicOn = true;
let music = null; // <audio> da faixa atual
let tracks = [];
let mood = 'vila';
let current = null; // faixa tocando agora
const nextIdx = {}; // clima -> próxima posição na playlist
let duckLevel = 1;
let fadeLevel = 1;
let fadeTimer = null;
let duckTimer = null;
const FADE_MS = 1200;

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
      tracks = Array.isArray(list.tracks) ? list.tracks.filter((t) => t && t.file) : [];
    }
  } catch { tracks = []; }
}

export function hasMusic() {
  return tracks.length > 0;
}

// Todas as faixas instaladas (para Opções e Créditos).
export function musicTracks() {
  return tracks;
}

export function nowPlaying() {
  return current;
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
  setVolumes(config.musicVolume, config.sfxVolume, config.musicOn);
  const once = () => { unlock(); window.removeEventListener('pointerdown', once, true); window.removeEventListener('keydown', once, true); };
  window.addEventListener('pointerdown', once, true);
  window.addEventListener('keydown', once, true);
}

export function setVolumes(m, s, on = musicOn) {
  musicVolume = m;
  sfxVolume = s;
  musicOn = on !== false;
  if (sfxGain) sfxGain.gain.value = s;
  applyMusicVolume();
  if (!music) { startMusic(); return; }
  if (!musicOn || m <= 0) music.pause();
  else if (music.paused && unlocked) music.play().catch(() => {});
}

// Clima da trilha: "vila" (folk de taverna) ou "batalha" (metal). Sem faixas do clima, fica na vila.
export function setMood(m) {
  const want = tracks.some((t) => t.mood === m) ? m : 'vila';
  if (want === mood) return;
  mood = want;
  if (music) fadeTo(() => playNext());
}

function moodTracks() {
  const list = tracks.filter((t) => (t.mood ?? 'vila') === mood);
  return list.length ? list : tracks;
}

function applyMusicVolume() {
  if (music) music.volume = Math.max(0, Math.min(1, musicVolume * duckLevel * fadeLevel));
}

function startMusic() {
  if (!unlocked || music || !tracks.length || !musicOn || musicVolume <= 0) return;
  music = new Audio();
  music.preload = 'auto';
  music.addEventListener('ended', () => playNext());
  playNext();
}

function playNext() {
  if (!music) return;
  const list = moodTracks();
  const i = (nextIdx[mood] ?? 0) % list.length;
  nextIdx[mood] = i + 1;
  current = list[i];
  // Com uma faixa só no clima, ela repete; com várias, o "ended" passa para a próxima.
  music.loop = list.length === 1;
  music.src = `assets/music/${current.file}`;
  fadeLevel = 0;
  applyMusicVolume();
  if (musicOn && musicVolume > 0) music.play().catch(() => {});
  ramp(1);
}

// Abaixa o volume até zero e chama next(), que começa a próxima faixa subindo o volume.
function fadeTo(next) {
  if (!music || music.paused) { next(); return; }
  ramp(0, next);
}

function ramp(target, done) {
  clearInterval(fadeTimer);
  const from = fadeLevel;
  const t0 = performance.now();
  fadeTimer = setInterval(() => {
    const k = Math.min(1, (performance.now() - t0) / FADE_MS);
    fadeLevel = from + (target - from) * k;
    applyMusicVolume();
    if (k >= 1) { clearInterval(fadeTimer); done?.(); }
  }, 50);
}

function duck() {
  if (!music) return;
  duckLevel = 0.3;
  applyMusicVolume();
  clearTimeout(duckTimer);
  duckTimer = setTimeout(() => { duckLevel = 1; applyMusicVolume(); }, 1800);
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
