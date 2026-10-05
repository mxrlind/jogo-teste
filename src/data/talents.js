// Árvore de Legado (prestígio). Pago em Coroas, permanente entre Ascensões.
// Custo do próximo nível = baseCost * (nível atual + 1).

export const TALENTS = [
  { id: 'fartura', name: 'Fartura', icon: 'talent-harvest', baseCost: 1, max: 20, desc: (l) => `+${l * 10}% em toda produção`, effect: (l) => ({ prodAll: 0.1 * l }) },
  { id: 'heranca', name: 'Herança', icon: 'talent-inheritance', baseCost: 1, max: 5, desc: (l) => `Começa com +${l * 500} ouro e +${l * 200} madeira`, effect: (l) => ({ startGold: 500 * l, startWood: 200 * l }) },
  { id: 'muralhas', name: 'Muralhas Eternas', icon: 'talent-walls', baseCost: 1, max: 10, desc: (l) => `+${l * 20}% de defesa`, effect: (l) => ({ defense: 0.2 * l }) },
  { id: 'vigilia', name: 'Vigília', icon: 'talent-vigil', baseCost: 2, max: 5, desc: (l) => `+${l * 2}h de limite offline e +${l * 8}% de eficiência offline`, effect: (l) => ({ offlineHours: 2 * l, offlineEff: 0.08 * l }) },
  { id: 'engenharia', name: 'Engenharia', icon: 'talent-engineering', baseCost: 2, max: 6, desc: (l) => `-${l * 5}% no custo de construções`, effect: (l) => ({ cost: 0.05 * l }) },
  { id: 'garimpo', name: 'Garimpo', icon: 'talent-mining', baseCost: 4, max: 3, desc: (l) => `+${l} gema(s) por invasão vencida`, effect: (l) => ({ raidGems: l }) },
  { id: 'terras', name: 'Terras Ancestrais', icon: 'map', baseCost: 5, max: 2, desc: (l) => `Começa com +${l} anel(éis) de terra desbloqueado(s)`, effect: (l) => ({ startRing: l }) },
  { id: 'mesa', name: 'Mesa Redonda', icon: 'talent-round-table', baseCost: 8, max: 2, desc: (l) => `+${l} vaga(s) no Conselho de heróis`, effect: (l) => ({ councilSlots: l }) },
  { id: 'mordomo', name: 'Mordomo Real', icon: 'talent-butler', baseCost: 10, max: 1, desc: (l) => (l ? 'Carroças do mercador são atendidas sozinhas' : 'Atende as carroças do mercador sozinho'), effect: (l) => ({ autoChest: l > 0 }) },
];

export const TALENT_BY_ID = Object.fromEntries(TALENTS.map((t) => [t.id, t]));

// Coroas ganhas ao Ascender = floor(sqrt(ouroDaRodada / CROWN_DIVISOR) * (1 + bônus de templos))
export const CROWN_DIVISOR = 1000000;
