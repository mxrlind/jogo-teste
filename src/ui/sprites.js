// Mapeamento de conteúdo do jogo -> arquivos de sprite (Kenney Medieval RTS, CC0) e ícones (game-icons.net, CC BY 3.0).
// Créditos completos: ASSETS.md. Este módulo não desenha nada; só diz qual arquivo representa o quê.

const RTS = 'assets/sprites/medieval-rts';
const t = (n) => `${RTS}/Tile/medievalTile_${String(n).padStart(2, '0')}.png`;
const s = (n) => `${RTS}/Structure/medievalStructure_${String(n).padStart(2, '0')}.png`;
const e = (n) => `${RTS}/Environment/medievalEnvironment_${String(n).padStart(2, '0')}.png`;
const u = (n) => `${RTS}/Unit/medievalUnit_${String(n).padStart(2, '0')}.png`;

// Terreno: base (tile inteiro) + sobreposição opcional (objeto do Environment).
export const TERRAIN_SPRITES = {
  grass: { base: [t(57), t(58)] },
  forest: { base: [t(46), t(47), t(42), t(43)] },
  rock: { base: [t(57), t(58)], over: [e(8), e(7)] },
  water: { base: [t(27), t(28)] },
  // O pacote não tem montanha: chão de pedra + rochedo grande.
  mountain: { base: [t(15), t(16)], over: [e(9), e(11)] },
};

// Prédios. `full: true` = ocupa o tile inteiro (plantação); `blades` = hélice animada do moinho.
export const BUILDING_SPRITES = {
  casa: { src: s(18) },
  fazenda: { src: t(56), full: true },
  serraria: { src: s(21) },
  pedreira: { src: s(20) },
  mercado: { src: s(22) },
  moinho: { src: s(19), blades: s(13) },
  armazem: { src: s(9) },
  taverna: { src: s(23) },
  muralha: { src: s(2) },
  torre: { src: s(1) },
  mina: { src: e(18) },
  templo: { src: s(4) },
  jardim: { src: e(19) },
  fogueira: { src: e(20) }, // substitui a antiga Fonte (o pacote não tem fonte d'água)
  estatua: { src: s(12) },
};

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
  for (const v of Object.values(TERRAIN_SPRITES)) [...v.base, ...(v.over || [])].forEach((u) => urls.add(u));
  for (const v of Object.values(BUILDING_SPRITES)) { urls.add(v.src); if (v.blades) urls.add(v.blades); }
  [CART_SPRITE, ...RAIDER_SPRITES, ...SLEEPER_SPRITES].forEach((x) => urls.add(x));
  for (const p of Object.values(PROFESSIONS)) urls.add(p.sprite);
  return [...urls];
}
