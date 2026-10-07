// Mapeamento de conteúdo do jogo -> arquivos de sprite e ícones (game-icons.net, CC BY 3.0).
// Mapa: KayKit Medieval Hexagon Pack (CC0), renderizado em PNG por tools/render-kaykit.mjs.
// Moradores, invasores e carroça: Kenney Medieval RTS (CC0). Créditos completos: ASSETS.md.
// Este módulo não desenha nada; só diz qual arquivo representa o quê.

const RTS = 'assets/sprites/medieval-rts';
const s = (n) => `${RTS}/Structure/medievalStructure_${String(n).padStart(2, '0')}.png`;
const u = (n) => `${RTS}/Unit/medievalUnit_${String(n).padStart(2, '0')}.png`;
const KK = 'assets/sprites/kaykit';
const k = (name) => `${KK}/${name}.png`;

// Quadro dos sprites do KayKit em tiles, relativo ao centro do tile (y para baixo): a altura sobe para o tile de cima.
// Igual ao FRAME de tools/render-kaykit.mjs. SPRITE_K = quanto a altura sobe na tela (usado para girar a hélice).
export const SPRITE_FRAME = { left: -0.6, right: 0.6, top: -1.25, bottom: 0.6 };
export const SPRITE_K = 0.7;

// Terreno: chão (tile inteiro, em cache) + natureza opcional por cima (desenhada em ordem de linha, como os prédios).
// `icon` é a miniatura usada nos painéis.
const GRASS = [k('grass-1'), k('grass-2')];
export const TERRAIN_SPRITES = {
  grass: { base: GRASS, icon: k('grass-1') },
  forest: { base: GRASS, over: [k('forest-1'), k('forest-2'), k('forest-3'), k('forest-4')], icon: k('icon-forest-1') },
  // Muda: o desenho troca de estágio com o tempo (saplingSprite); `over` é o primeiro estágio.
  sapling: { base: GRASS, over: [k('sapling-1')], stages: [k('sapling-1'), k('sapling-2')], icon: k('icon-sapling-1') },
  rock: { base: GRASS, over: [k('rock-1'), k('rock-2')], icon: k('icon-rock-1') },
  water: { base: [k('water-1'), k('water-2')], icon: k('water-1') },
  mountain: { base: GRASS, over: [k('mountain-1'), k('mountain-2')], icon: k('icon-mountain-1') },
};

// Prédios: sprite no quadro SPRITE_FRAME + miniatura quadrada para a interface.
// `blades` = hélice do moinho, girada no jogo em volta de `hub` (em tiles, relativo ao centro do tile).
const building = (id, extra = {}) => ({ src: k(`building-${id}`), icon: k(`icon-${id}`), ...extra });
export const BUILDING_SPRITES = {
  casa: building('casa'),
  fazenda: building('fazenda'),
  serraria: building('serraria'),
  pedreira: building('pedreira'),
  mercado: building('mercado'),
  moinho: building('moinho', { blades: { src: k('building-moinho-blades'), hub: { x: -0.004, y: -0.261 }, size: 0.712 } }),
  armazem: building('armazem'),
  taverna: building('taverna'),
  muralha: building('muralha'),
  torre: building('torre'),
  mina: building('mina'),
  templo: building('templo'),
  jardim: building('jardim'),
  fogueira: building('fogueira'), // poço do KayKit (o nome Fogueira vem da época do Medieval RTS)
  estatua: building('estatua'),
};

// Estágio da muda: pequena na 1ª metade do crescimento, árvores jovens na 2ª.
export function saplingSprite(tile, now, growSeconds) {
  const stages = TERRAIN_SPRITES.sapling.stages;
  const p = (now - (tile.p ?? 0)) / 1000 / growSeconds;
  return stages[p < 0.5 ? 0 : 1];
}

export const LOCKED_OVERLAY = 'rgba(20, 22, 32, 0.62)';

// Carroça do mercador (evento surpresa) e invasores (time vermelho, que nenhum morador usa).
export const CART_SPRITE = s(7);
export const RAIDER_SPRITES = [u(9), u(10), u(8)];

// Profissões dos moradores (ver src/ui/villagers.js): sprite do Medieval RTS e ferramenta (ícone game-icons)
// que aparece balançando enquanto trabalham. Times azul, verde e cinza; o vermelho é dos invasores.
export const PROFESSIONS = {
  fazenda: { name: 'Lavrador', sprite: u(13), tool: 'clear' },
  moinho: { name: 'Moleira', sprite: u(12) },
  serraria: { name: 'Lenhador', sprite: u(19), tool: 'hero-woodcutter' },
  pedreira: { name: 'Pedreiro', sprite: u(1), tool: 'tool-pickaxe' },
  mina: { name: 'Mineira', sprite: u(18), tool: 'tool-pickaxe' },
  mercado: { name: 'Mercadora', sprite: u(24) },
  armazem: { name: 'Intendente', sprite: u(17) },
  taverna: { name: 'Taverneiro', sprite: u(23) },
  torre: { name: 'Guarda', sprite: u(3) },
  templo: { name: 'Sacerdote', sprite: u(2) },
};
// Sem emprego: dormem na rua, ao lado das casas.
export const SLEEPER_SPRITES = [u(13), u(19), u(1), u(12)];
export const TOOL_ICONS = ['clear', 'hero-woodcutter', 'tool-pickaxe'];


export function allSpriteUrls() {
  const urls = new Set();
  for (const v of Object.values(TERRAIN_SPRITES)) [...v.base, ...(v.over || []), ...(v.stages || [])].forEach((u) => urls.add(u));
  for (const v of Object.values(BUILDING_SPRITES)) { urls.add(v.src); if (v.blades) urls.add(v.blades.src); }
  [CART_SPRITE, ...RAIDER_SPRITES, ...SLEEPER_SPRITES].forEach((x) => urls.add(x));
  for (const p of Object.values(PROFESSIONS)) urls.add(p.sprite);
  return [...urls];
}
