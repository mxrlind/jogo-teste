// Ícones de interface (game-icons.net, CC BY 3.0). Renderizados por CSS mask: herdam `color`.
export const ICON_DIR = 'assets/icons/game-icons/';

export function ico(name, cls = '') {
  return `<i class="ico ${cls}" style="--src:url(${ICON_DIR}${name}.svg)" aria-hidden="true"></i>`;
}

// Classe de cor por recurso (ver styles.css, .c-*)
export const RES_CLASS = { gold: 'c-gold', food: 'c-food', wood: 'c-wood', stone: 'c-stone', gems: 'c-gems', crowns: 'c-crowns' };

export function resIco(r) {
  return ico(r === 'scrolls' ? 'scroll' : r, RES_CLASS[r] || '');
}
