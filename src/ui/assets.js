// Pré-carregamento de imagens (sprites e ícones coloridos para o canvas) com progresso.
import { allSpriteUrls } from './sprites.js';
import { ICON_DIR } from './icons.js';

export const images = new Map();

export function loadImage(url, key = url) {
  return new Promise((resolve) => {
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => { images.set(key, img); resolve(img); };
    img.onerror = () => { console.error('Asset não carregou:', url); resolve(null); };
    img.src = url;
  });
}

// No canvas, um SVG com currentColor sai preto; aqui geramos variantes coloridas em memória.
const colored = new Map();
export function iconKey(name, color) { return `icon:${name}:${color}`; }

export async function loadColoredIcon(name, color) {
  const key = iconKey(name, color);
  if (colored.has(key)) return colored.get(key);
  const res = await fetch(`${ICON_DIR}${name}.svg`);
  const svg = (await res.text()).replaceAll('currentColor', color);
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  const img = await loadImage(url, key);
  colored.set(key, img);
  return img;
}

// Ícones desenhados dentro do canvas (números flutuantes, avisos).
export const CANVAS_ICONS = [
  ['gold', '#f2b632'], ['food', '#f0c27a'], ['wood', '#c8834a'], ['stone', '#d7dde0'], ['gems', '#7cc6f0'],
  ['warning', '#ffb020'], ['swords', '#ff8a7a'], ['defense', '#9be7a8'], ['boost', '#ffe08a'],
];

export async function preloadAll(extraUrls, onProgress) {
  const jobs = [
    ...allSpriteUrls().map((u) => () => loadImage(u)),
    ...extraUrls.map((u) => () => loadImage(u)),
    ...CANVAS_ICONS.map(([n, c]) => () => loadColoredIcon(n, c)),
  ];
  let done = 0;
  await Promise.all(jobs.map((job) => job().then(() => onProgress?.(++done, jobs.length))));
}
