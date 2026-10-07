// Gera os sprites do mapa a partir dos modelos 3D do KayKit Medieval Hexagon Pack (CC0, Kay Lousberg).
// O jogo continua 2D: este script roda uma vez, fora do jogo, e salva PNGs em assets/sprites/kaykit/.
//
// Uso:
//   git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 /tmp/kaykit
//   npm i --no-save three@0.170.0 playwright
//   git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 /tmp/kaykit-dungeon
//   node tools/render-kaykit.mjs /tmp/kaykit/addons/kaykit_medieval_hexagon_pack/Assets/gltf /tmp/kaykit-dungeon/addons/kaykit_dungeon_remastered/Assets/gltf
//
// O segundo caminho (Dungeon Remastered, CC0) é usado pelo subsolo e pela Escadaria.
//
// Opção --sheet: em vez de salvar os sprites, gera tools/kaykit/sheet.png com todos os modelos (para escolher).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GLTF = process.argv[2];
const DUNGEON = process.argv[3] && !process.argv[3].startsWith('--') ? process.argv[3] : null;
const SHEET = process.argv.includes('--sheet');
// --only=a,b: gera só os sprites cujo nome começa com um desses prefixos (o resto do pacote fica como está).
const ONLY = process.argv.find((a) => a.startsWith('--only='))?.slice(7).split(',');
const want = (name) => !ONLY || ONLY.some((p) => name.startsWith(p));
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
const DG = (n) => `dg/${n}`; // Dungeon Remastered: nome do arquivo com extensão
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
  // O pacote não tem cais nem barco: tábuas e casco são peças simples (primitive em tools/kaykit/render.html).
  cais: {
    parts: [
      ...[-0.75, -0.45, -0.15, 0.15, 0.45, 0.75].map((x, i) => ({ box: [0.28, 0.14, 1.3], x, z: 0.3, color: i % 2 ? '#a8703f' : '#b98150' })),
      ...[[-0.9, -0.3], [0.9, -0.3], [-0.9, 0.9], [0.9, 0.9]].map(([x, z]) => ({ box: [0.14, 0.42, 0.14], x, z, color: '#6e4527' })),
      { model: P('tent'), x: -0.45, z: -0.6, rot: 20, scale: 1.1 },
      { model: P('crate_open'), x: 0.45, z: -0.5, scale: 1.1 },
      { model: P('barrel'), x: 0.75, z: 0.15, scale: 1.1 },
      { model: P('bucket_water'), x: 0.2, z: 0.55, scale: 1.2 },
      { model: P('sack'), x: -0.5, z: 0.5, scale: 1.1 },
    ],
    fit: 0.92,
  },
};
// Barquinho de pesca que fica no lago ao lado do cais (desenhado no jogo por cima da água, balançando).
const BOATS = {
  barco: {
    parts: [
      { hull: { l: 1.6, w: 0.7, h: 0.28 }, color: '#a8703f' },
      { box: [0.16, 0.05, 0.56], x: -0.3, y: 0.2, color: '#8a5a33' },
      { box: [0.16, 0.05, 0.5], x: 0.25, y: 0.2, color: '#8a5a33' },
      { model: P('flag_blue'), x: 0.25, y: 0.12, scale: 3 },
      { model: P('crate_open'), x: -0.6, y: 0.1, scale: 0.9 },
    ],
    fit: 0.9,
  },
};
// Escadaria para o subsolo (Dungeon Remastered): escada de pedra com tochas.
if (DUNGEON) BUILDINGS.escadaria = { parts: [{ model: DG('stairs_walled.gltf.glb') }, { model: DG('torch_mounted.gltf.glb'), x: 1.3, z: 1.2 }, { model: DG('torch_mounted.gltf.glb'), x: -1.3, z: 1.2 }], fit: 0.8 };

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

// Subsolo (precisa do Dungeon Remastered): salas e escadas, no mesmo quadro dos prédios.
const ROCKS = (tintColor, extra = {}) => [
  { model: NAT('rock_single_A'), x: -0.42, z: -0.38, scale: 2.6, rot: 20, tint: tintColor, ...extra },
  { model: NAT('rock_single_C'), x: 0.4, z: 0.36, scale: 2.4, rot: 70, tint: tintColor, ...extra },
  { model: NAT('rock_single_B'), x: 0.42, z: -0.42, scale: 2.0, rot: 140, tint: tintColor, ...extra },
  { model: NAT('rock_single_D'), x: -0.4, z: 0.42, scale: 2.0, rot: 200, tint: tintColor, ...extra },
]
const UNDER = {
  'room-pedreira_funda': { parts: [{ model: DG('rubble_large.gltf.glb') }, { model: P('resource_stone'), x: 0.9, z: 0.8, scale: 1.4 }, { model: P('wheelbarrow'), x: -0.9, z: 0.8, rot: 30, scale: 1.4 }], fit: 0.86 },
  'room-adega': { parts: [{ model: DG('barrel_large.gltf.glb') }, { model: DG('keg_decorated.gltf.glb'), x: 1.3, z: 0.6 }, { model: DG('barrel_small_stack.gltf.glb'), x: -1.2, z: 0.7 }, { model: DG('shelf_small.gltf.glb'), x: 0.2, z: -1.1 }], fit: 0.86 },
  'room-garimpo': { parts: [{ model: DG('coin_stack_large.gltf.glb'), scale: 1.6 }, { model: P('bucket_water'), x: 1.0, z: 0.5, scale: 1.3 }, { model: P('sack'), x: -0.9, z: 0.6, scale: 1.3 }, { model: DG('chest_gold.glb'), x: 0.1, z: -0.9, scale: 0.8 }], fit: 0.84 },
  'room-fungos': {
    parts: [
      { model: NAT('waterplant_A'), scale: 3, tint: '#d7a6ff', glow: 0.35 }, { model: NAT('waterplant_B'), x: 0.6, z: 0.4, scale: 3, tint: '#ffd27a', glow: 0.3 },
      { model: NAT('waterplant_C'), x: -0.6, z: 0.35, scale: 3, tint: '#9fe3c4', glow: 0.3 }, { model: NAT('waterplant_A'), x: 0.45, z: -0.5, rot: 60, scale: 3, tint: '#ffd27a', glow: 0.3 },
      { model: NAT('waterplant_B'), x: -0.5, z: -0.45, rot: 120, scale: 3, tint: '#d7a6ff', glow: 0.35 },
    ],
    fit: 0.86,
  },
  'room-forja': { parts: [{ model: B('blacksmith') }], fit: 0.9 },
};
// Chão do subsolo: vista de cima, como a grama.
const UNDER_GROUND = {
  'u-rock-1': { color: '#4b4552', ground: true, parts: ROCKS('#6d6577') },
  'u-rock-2': { color: '#48424f', ground: true, parts: ROCKS('#655e70').map((p, i) => ({ ...p, rot: p.rot + 90 * i, scale: p.scale * 0.9 })) },
  'u-gold': { color: '#4b4552', ground: true, parts: ROCKS('#f2b632', { flat: true, glow: 0.25 }) },
  'u-gem': { color: '#4b4552', ground: true, parts: [...ROCKS('#7cc6f0', { flat: true, glow: 0.4 }).slice(0, 2), { ...ROCKS('#c08cff', { flat: true, glow: 0.4 })[2] }] },
  'u-water': { color: '#2b6f96', ground: true },
  'u-magma': { color: '#f76707', ground: true, parts: ROCKS('#3a2a2a', { flat: true }).slice(1, 3) },
  'u-floor-1': { color: '#8a7058', ground: true },
  'u-floor-2': { color: '#84694f', ground: true },
  'u-cavern-1': { color: '#5f6b4e', ground: true, parts: [{ model: NAT('rock_single_E'), x: -0.5, z: 0.4, scale: 1.4 }] },
  'u-cavern-2': { color: '#5a664a', ground: true, parts: [{ model: NAT('rock_single_A'), x: 0.45, z: -0.45, scale: 1.3 }] },
};

// Chão: vista de cima, um tile inteiro.
const GROUND_FRAME = { left: -0.5, right: 0.5, top: -0.5, bottom: 0.5 };
const GROUND = {
  'grass-1': { color: '#63a650', ground: true },
  'grass-2': { color: '#5d9f4b', ground: true },
  'water-1': { color: '#4aa3c9', ground: true },
  'water-2': { color: '#4aa3c9', parts: [{ model: NAT('waterlily_A'), x: 0.35, z: -0.3 }, { model: NAT('waterlily_B'), x: -0.4, z: 0.35 }], ground: true },
};

const MIME = { '.glb': 'model/gltf-binary', '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.gltf': 'model/gltf+json', '.bin': 'application/octet-stream', '.png': 'image/png' };
const roots = { ...(DUNGEON ? { '/dg/': DUNGEON + '/' } : {}), '/three/': path.join(ROOT, 'node_modules/three/'), '/kk/': GLTF + '/', '/': path.join(ROOT, 'tools/kaykit/') };
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
    if (!want(`building-${name}`)) continue;
    const r = await render({ ...spec, frame: FRAME, K, ppt: PPT, icon: 128 });
    save(`building-${name}`, r.url);
    save(`icon-${name}`, r.icon);
    if (r.bladesUrl) save(`building-${name}-blades`, r.bladesUrl);
    if (Object.keys(r.meta).length) meta[name] = r.meta;
  }
  for (const [name, spec] of Object.entries(BOATS)) if (want(name)) save(name, (await render({ ...spec, frame: FRAME, K, ppt: PPT })).url);
  for (const [name, spec] of Object.entries(WALLS)) if (want(`building-${name}`)) save(`building-${name}`, (await render({ ...spec, frame: FRAME, K, ppt: PPT })).url);
  for (const [name, spec] of Object.entries(NATURE)) {
    if (!want(name)) continue;
    const r = await render({ ...spec, frame: FRAME, K, ppt: PPT, icon: 128 });
    save(name, r.url);
    save(`icon-${name}`, r.icon);
  }
  for (const [name, spec] of Object.entries(GROUND)) if (want(name)) save(name, (await render({ ...spec, frame: GROUND_FRAME, ppt: PPT })).url);
  if (DUNGEON) {
    for (const [name, spec] of Object.entries(UNDER)) {
      if (!want(name)) continue;
      const r = await render({ ...spec, frame: FRAME, K, ppt: PPT, icon: 128 });
      save(name, r.url);
      save(`icon-${name}`, r.icon);
    }
    for (const [name, spec] of Object.entries(UNDER_GROUND)) if (want(name)) save(name, (await render({ ...spec, frame: GROUND_FRAME, ppt: PPT })).url);
  } else console.log('Sem a pasta do Dungeon Remastered: sprites do subsolo e da Escadaria não foram gerados.');
  // Castelo do logo (menu, tela de carregamento e ícone do app via tools/make-icons.py).
  if (want('logo-castelo')) save('logo-castelo', (await render({ parts: [{ model: B('castle') }], frame: FRAME, K, ppt: PPT, icon: 256, shadow: false })).icon);
  console.log('Sprites salvos em assets/sprites/kaykit/. Metadados (copie para src/ui/sprites.js):');
  console.log(JSON.stringify(meta, null, 2));
}
await browser.close();
server.close();
