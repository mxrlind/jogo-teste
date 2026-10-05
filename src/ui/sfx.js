// Efeitos sonoros sintetizados com WebAudio: sem arquivos de áudio.
let ctx = null;
let enabled = true;

export function setSound(on) { enabled = on; }

function ac() {
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

function tone(freq, dur = 0.1, type = 'sine', vol = 0.08, delay = 0, slide = 0) {
  if (!enabled) return;
  const a = ac();
  if (!a) return;
  const t = a.currentTime + delay;
  const o = a.createOscillator();
  const g = a.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(a.destination);
  o.start(t);
  o.stop(t + dur + 0.02);
}

export const sfx = {
  click: () => tone(660, 0.05, 'triangle', 0.05),
  build: () => { tone(330, 0.08, 'square', 0.05); tone(495, 0.12, 'triangle', 0.06, 0.06); },
  upgrade: () => [523, 659, 784].forEach((f, i) => tone(f, 0.12, 'triangle', 0.06, i * 0.07)),
  error: () => tone(180, 0.15, 'sawtooth', 0.04, 0, -60),
  coin: () => { tone(988, 0.06, 'square', 0.04); tone(1319, 0.12, 'square', 0.04, 0.05); },
  chest: () => [784, 988, 1175, 1568].forEach((f, i) => tone(f, 0.1, 'triangle', 0.06, i * 0.06)),
  warn: () => { tone(440, 0.2, 'sawtooth', 0.05); tone(440, 0.2, 'sawtooth', 0.05, 0.3); },
  win: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.18, 'triangle', 0.07, i * 0.09)),
  lose: () => [392, 330, 262].forEach((f, i) => tone(f, 0.25, 'sawtooth', 0.05, i * 0.15)),
  legendary: () => [523, 784, 1047, 1319, 1568, 2093].forEach((f, i) => tone(f, 0.25, 'triangle', 0.06, i * 0.08)),
  ascend: () => [262, 330, 392, 523, 659, 784, 1047].forEach((f, i) => tone(f, 0.35, 'sine', 0.07, i * 0.1)),
};
