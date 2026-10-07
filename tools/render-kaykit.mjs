// Gera os sprites do mapa a partir dos modelos 3D do KayKit Medieval Hexagon Pack (CC0, Kay Lousberg).
// O jogo continua 2D: este script roda uma vez, fora do jogo, e salva PNGs em assets/sprites/kaykit/.
//
// Uso:
//   git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 /tmp/kaykit
//   npm i --no-save three@0.170.0 playwright
//   node tools/render-kaykit.mjs /tmp/kaykit/addons/kaykit_medieval_hexagon_pack/Assets/gltf
//
// Opção --sheet: em vez de salvar os sprites, gera tools/kaykit/sheet.png com todos os modelos (para escolher).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GLTF = process.argv[2];
const SHEET = process.argv.includes('--sheet');
if (!GLTF || !fs.existsSync(GLTF)) {
  console.error('Informe a pasta gltf do KayKit (veja o cabeçalho deste arquivo).');
  process.exit(1);
}
const OUT = path.join(ROOT, 'assets/sprites/kaykit');

// Quadro dos sprites em tiles, relativo ao centro do tile (y da tela para baixo).
// Coincide com SPRITE_FRAME em src/ui/sprites.js.
const FRAME = { left: -0.6, right: 0.6, top: -1.25, bottom: 0.6 };
const K = 0.7; // quanto a altura sobe na tela
const PPT = 160; // pixels por tile

const B = (n) => `buildings/blue/building_${n}_blue`;
const N = (n) => `buildings/neutral/${n}`;
const NAT = (n) => `decoration/nature/${n}`;
const P = (n) => `decoration/props/${n}`;
const one = (model, extra = {}) => ({ parts: [{ model }], ...extra });

// Prédios do jogo (ids de src/data/buildings.js).
const BUILDINGS = {
  casa: one(B('home_A')),
  fazenda: { parts: [{ model: N('building_grain') }], scale: 1.6, clip: 0.96, shadow: false },
  serraria: one(B('lumbermill')),
  pedreira: { parts: [{ model: NAT('rock_single_E'), scale: 4.5 }, { model: P('resource_stone'), x: 0.8, z: 0.75, scale: 1.4 }, { model: P('wheelbarrow'), x: -0.8, z: 0.8, rot: 30, scale: 1.4 }], fit: 0.9 },
  mercado: one(B('market')),
  moinho: { parts: [{ model: B('windmill') }], blades: 'fan', fit: 0.8 },
  armazem: one(B('barracks')),
  taverna: one(B('tavern')),
  // Taverna e quartel crescem nos níveis 5 e 10 (ver `stages` em src/ui/sprites.js).
  // fitFirst mantém o prédio do mesmo tamanho; os enfeites ficam em volta.
  'taverna-5': {
    parts: [{ model: B('tavern') }, { model: P('barrel'), x: 0.55, z: 0.5, scale: 1.4 }, { model: P('barrel'), x: 0.3, z: 0.62, scale: 1.4 }, { model: P('crate_A_small'), x: -0.55, z: 0.55, scale: 1.4 }],
    fit: 0.9, fitFirst: true,
  },
  'taverna-10': {
    parts: [
      { model: B('tavern') }, { model: P('barrel'), x: 0.55, z: 0.5, scale: 1.4 }, { model: P('barrel'), x: 0.3, z: 0.62, scale: 1.4 }, { model: P('crate_A_small'), x: -0.55, z: 0.55, scale: 1.4 },
      { model: P('flag_blue'), x: -0.68, z: 0.05, scale: 2 }, { model: P('flag_blue'), x: 0.7, z: -0.15, scale: 2 },
    ],
    fit: 0.9, fitFirst: true,
  },
  quartel: one(B('archeryrange')),
  'quartel-5': {
    parts: [{ model: B('archeryrange') }, { model: P('weaponrack'), x: -0.5, z: 0.55, scale: 1.4 }, { model: P('bucket_arrows'), x: 0.5, z: 0.58, scale: 1.4 }],
    fit: 0.9, fitFirst: true,
  },
  'quartel-10': {
    parts: [
      { model: B('archeryrange') }, { model: P('weaponrack'), x: -0.5, z: 0.55, scale: 1.4 }, { model: P('bucket_arrows'), x: 0.5, z: 0.58, scale: 1.4 },
      { model: P('flag_blue'), x: -0.68, z: 0.15, scale: 2 }, { model: P('flag_blue'), x: 0.7, z: 0.15, scale: 2 },
    ],
    fit: 0.9, fitFirst: true,
  },
  muralha: { parts: [{ model: N('wall_straight') }], fit: 1.02 },
  torre: one(B('tower_A'), { fit: 0.8 }),
  mina: one(B('mine')),
  templo: one(B('church')),
  jardim: {
    parts: [
      { model: NAT('tree_single_A'), x: -0.45, z: -0.4 }, { model: NAT('tree_single_B'), x: 0.5, z: -0.3 },
      { model: NAT('waterplant_A'), x: 0.05, z: 0.25, scale: 2.5 }, { model: NAT('waterplant_B'), x: -0.5, z: 0.4, scale: 2.5 }, { model: NAT('waterplant_C'), x: 0.55, z: 0.45, scale: 2.5 },
      { model: N('fence_wood_straight'), z: 0.85, rot: 90, scale: 1.6 },
    ],
    fit: 0.86,
  },
  fogueira: one(B('well'), { fit: 0.7 }),
  estatua: { parts: [{ model: B('tower_base') }, { model: P('flag_blue'), y: 0.6 }], fit: 0.62 },
};

// Muralha que se liga sozinha: uma variante para cada combinação de vizinhos que também são muralha ou torre.
// Bits da máscara: 1 = norte, 2 = leste, 4 = sul, 8 = oeste (mesma ordem de wallMask em src/core/map.js).
// Cada lado ligado ganha meia muralha até a borda do tile; as metades se cruzam no centro e fecham os cantos.
// Máscara 0 (sozinha) usa o sprite normal da muralha, deitada. 1 tile = 2 unidades, e a wall_straight tem exatamente 2 de comprimento.
const T = 0.4; // meia espessura da muralha: cada metade passa um pouco do centro para não abrir buraco nos cantos
function wallVariant(mask) {
  const n = mask & 1, e = mask & 2, s = mask & 4, w = mask & 8;
  const parts = [];
  // A ponta de baixo da muralha em pé fica de frente para a câmera e mostraria o corte: ela para logo atrás da
  // face da peça deitada (que sempre existe nesse caso; sem leste nem oeste vira um bloco que tampa a ponta).
  if (e || w || (n && !s)) parts.push({ model: N('wall_straight'), keep: [w ? -1 : -T, e ? 1 : T, -1, 1] });
  if (n || s) parts.push({ model: N('wall_straight'), rot: 90, keep: [-1, 1, n ? -1 : -T, s ? 1 : T - 0.02] });
  return { parts, fixed: true };
}
const WALLS = Object.fromEntries(Array.from({ length: 15 }, (_, i) => [`muralha-${i + 1}`, wallVariant(i + 1)]));

// Natureza que fica por cima do chão (floresta, rochas, montanha).
const NATURE = {
  'forest-1': { parts: [{ model: NAT('trees_A_medium') }], fit: 1.0 },
  'forest-2': { parts: [{ model: NAT('trees_B_large') }], fit: 1.0 },
  'forest-3': { parts: [{ model: NAT('trees_A_large') }], fit: 1.0 },
  'forest-4': { parts: [{ model: NAT('trees_B_medium') }], fit: 1.0 },
  // Árvore plantada pelo jogador, em dois estágios antes de virar floresta.
  'sapling-1': { parts: [{ model: NAT('tree_single_A') }], fit: 0.26 },
  'sapling-2': { parts: [{ model: NAT('trees_A_small') }], fit: 0.62 },
  'rock-1': { parts: [{ model: NAT('rock_single_A') }, { model: NAT('rock_single_C'), x: 0.3, z: 0.2 }], fit: 0.62 },
  'rock-2': { parts: [{ model: NAT('rock_single_B') }, { model: NAT('rock_single_D'), x: -0.3, z: 0.22 }], fit: 0.62 },
  'mountain-1': { parts: [{ model: NAT('mountain_A') }], fit: 1.0 },
  'mountain-2': { parts: [{ model: NAT('mountain_C') }], fit: 1.0 },
};

// Chão: vista de cima, um tile inteiro.
const GROUND_FRAME = { left: -0.5, right: 0.5, top: -0.5, bottom: 0.5 };
const GROUND = {
  'grass-1': { color: '#63a650', ground: true },
  'grass-2': { color: '#5d9f4b', ground: true },
  'water-1': { color: '#4aa3c9', ground: true },
  'water-2': { color: '#4aa3c9', parts: [{ model: NAT('waterlily_A'), x: 0.35, z: -0.3 }, { model: NAT('waterlily_B'), x: -0.4, z: 0.35 }], ground: true },
};

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.gltf': 'model/gltf+json', '.bin': 'application/octet-stream', '.png': 'image/png' };
const roots = { '/three/': path.join(ROOT, 'node_modules/three/'), '/kk/': GLTF + '/', '/': path.join(ROOT, 'tools/kaykit/') };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const prefix = Object.keys(roots).find((p) => url.startsWith(p));
  const file = path.join(roots[prefix], url.slice(prefix.length));
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(0);
const port = server.address().port;

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
page.on('pageerror', (e) => console.error('Erro na página:', e.message));
await page.goto(`http://localhost:${port}/render.html`);
await page.waitForFunction('window.READY');

const save = (name, dataUrl) => fs.writeFileSync(path.join(OUT, `${name}.png`), Buffer.from(dataUrl.split(',')[1], 'base64'));
const render = (spec) => page.evaluate((s) => window.renderSprite(s), spec);

if (SHEET) {
  const all = { ...BUILDINGS, ...WALLS, ...NATURE };
  const shots = [];
  for (const [name, spec] of Object.entries(all)) shots.push([name, (await render({ ...spec, frame: FRAME, K, ppt: PPT })).url]);
  const html = `<body style="margin:0;background:#5fa04a;display:flex;flex-wrap:wrap;gap:6px;font:12px sans-serif">${shots.map(([n, u]) => `<div style="outline:1px dashed #0004"><img src="${u}"><div>${n}</div></div>`).join('')}</body>`;
  const p2 = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  await p2.setContent(html);
  await p2.screenshot({ path: path.join(ROOT, 'tools/kaykit/sheet.png'), fullPage: true });
} else {
  fs.mkdirSync(OUT, { recursive: true });
  const meta = {};
  for (const [name, spec] of Object.entries(BUILDINGS)) {
    const r = await render({ ...spec, frame: FRAME, K, ppt: PPT, icon: 128 });
    save(`building-${name}`, r.url);
    save(`icon-${name}`, r.icon);
    if (r.bladesUrl) save(`building-${name}-blades`, r.bladesUrl);
    if (Object.keys(r.meta).length) meta[name] = r.meta;
  }
  for (const [name, spec] of Object.entries(WALLS)) save(`building-${name}`, (await render({ ...spec, frame: FRAME, K, ppt: PPT })).url);
  for (const [name, spec] of Object.entries(NATURE)) {
    const r = await render({ ...spec, frame: FRAME, K, ppt: PPT, icon: 128 });
    save(name, r.url);
    save(`icon-${name}`, r.icon);
  }
  for (const [name, spec] of Object.entries(GROUND)) save(name, (await render({ ...spec, frame: GROUND_FRAME, ppt: PPT })).url);
  // Castelo do logo (menu, tela de carregamento e ícone do app via tools/make-icons.py).
  save('logo-castelo', (await render({ parts: [{ model: B('castle') }], frame: FRAME, K, ppt: PPT, icon: 256, shadow: false })).icon);
  console.log('Sprites salvos em assets/sprites/kaykit/. Metadados (copie para src/ui/sprites.js):');
  console.log(JSON.stringify(meta, null, 2));
}
await browser.close();
server.close();
