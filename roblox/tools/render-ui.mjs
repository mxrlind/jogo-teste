// Gera as imagens de interface que o Roblox precisa a partir dos arquivos do jogo web, num navegador sem tela:
// - ícones do game-icons.net (CC BY 3.0) em branco, para tingir com ImageColor3 (no web eles herdam a cor por máscara CSS);
// - rosa dos ventos (o SVG de src/ui/panels.js), uma por lado da horda;
// - forma do estandarte (o clip-path do styles.css).
// Uso (na raiz do repositório): node roblox/tools/render-ui.mjs   (depois: python3 roblox/tools/atlas.py)
import { chromium } from '/opt/node-tools/node_modules/playwright/index.mjs';
import { readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const OUT = resolve(ROOT, 'roblox/assets/build');
const ICON_DIR = resolve(ROOT, 'assets/icons/game-icons');
const ICON_PX = 80;

mkdirSync(`${OUT}/icons`, { recursive: true });
mkdirSync(`${OUT}/ui`, { recursive: true });

// Mesmo desenho do COMPASS_SVG de src/ui/panels.js, com as cores do styles.css já aplicadas.
function compassSvg(dir) {
  const point = (len, w, rot, lt, dk) => `<g transform="rotate(${rot})"><polygon fill="${lt}" points="0,-${len} -${w},-${w} 0,0"/><polygon fill="${dk}" points="0,-${len} ${w},-${w} 0,0"/></g>`;
  const diag = [45, 135, 225, 315].map((r) => point(19, 4.5, r, '#ffd45c', '#c48a12')).join('');
  const card = [['n', 0], ['e', 90], ['s', 180], ['w', 270]].map(([d, r]) => (d === dir ? point(31, 7, r, '#e0523d', '#b8412f') : point(31, 7, r, '#5a4a3a', '#2a2433'))).join('');
  const letters = [['N', 0, -38.5], ['L', 38.5, 0], ['S', 0, 38.5], ['O', -38.5, 0]].map(([t, x, y]) => `<text x="${x}" y="${y}">${t}</text>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-50 -50 100 100" width="120" height="120" style="overflow:visible">
    <style>text{font:900 11px Nunito,sans-serif;fill:#2a2433;text-anchor:middle;dominant-baseline:central}</style>
    <circle r="47" fill="#f3ecdc" stroke="#2a2433" stroke-width="3"/><circle r="31.5" fill="none" stroke="rgba(185,130,14,.55)" stroke-width="1.5"/>
    ${diag}${card}<circle r="4" fill="#f2b632" stroke="#2a2433" stroke-width="1.5"/>${letters}</svg>`;
}

const font = readFileSync(resolve(ROOT, 'assets/fonts/nunito-latin-800-normal.woff2')).toString('base64');
const page0 = `<style>@font-face{font-family:Nunito;font-weight:800 900;src:url(data:font/woff2;base64,${font})}
  html,body{margin:0;background:transparent} .box{display:inline-block}</style><div id="s" class="box"></div>`;

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const page = await browser.newPage({ deviceScaleFactor: 1 });
await page.setContent(page0);

async function shot(html, file, w, h) {
  await page.evaluate(([html, w, h]) => {
    const s = document.getElementById('s');
    s.style.width = `${w}px`;
    s.style.height = `${h}px`;
    s.innerHTML = html;
  }, [html, w, h]);
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#s').screenshot({ path: file, omitBackground: true });
}

const icons = readdirSync(ICON_DIR).filter((f) => f.endsWith('.svg'));
for (const f of icons) {
  const svg = readFileSync(`${ICON_DIR}/${f}`, 'utf8').replaceAll('currentColor', '#ffffff')
    .replace('<svg ', `<svg width="${ICON_PX}" height="${ICON_PX}" `);
  await shot(svg, `${OUT}/icons/${f.replace('.svg', '.png')}`, ICON_PX, ICON_PX);
}

for (const d of ['n', 's', 'e', 'w']) await shot(compassSvg(d), `${OUT}/ui/compass-${d}.png`, 120, 120);

// Estandarte: forma branca (tingida com a cor do reino) e o brilho de cima (linear-gradient do styles.css).
const clip = 'clip-path:polygon(0 0,100% 0,100% 80%,50% 100%,0 80%)';
await shot(`<div style="width:68px;height:80px;background:#fff;${clip}"></div>`, `${OUT}/ui/banner-shape.png`, 68, 80);
await shot(`<div style="width:68px;height:80px;background:linear-gradient(180deg,rgba(255,255,255,.22),transparent 55%);${clip}"></div>`, `${OUT}/ui/banner-shine.png`, 68, 80);

await browser.close();
writeFileSync(`${OUT}/icons.json`, JSON.stringify(icons.map((f) => f.replace('.svg', '')), null, 1));
console.log(`${icons.length} ícones, 4 rosas dos ventos e o estandarte em ${OUT}`);
