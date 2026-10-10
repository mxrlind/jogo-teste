// Loja de gemas.
// GEM_PACKS: pacotes por dinheiro real. O pagamento ainda não está ligado (precisa de conta num
// serviço como Stripe, itch.io ou Steam); até lá os botões mostram "em breve".
// GEM_SHOP: o que as gemas compram dentro do jogo (além de acelerar treino/expedição e cosméticos).

export const PAYMENTS_ENABLED = false;

export const GEM_PACKS = [
  { id: 'punhado', name: 'Punhado de Gemas', gems: 80, price: 'R$ 4,90' },
  { id: 'saco', name: 'Saco de Gemas', gems: 450, price: 'R$ 24,90', tag: '+12%' },
  { id: 'bau', name: 'Baú de Gemas', gems: 1000, price: 'R$ 49,90', tag: '+25%' },
  { id: 'tesouro', name: 'Tesouro Real', gems: 2800, price: 'R$ 119,90', tag: 'Melhor valor' },
];

// reward usa os tipos de Game.grant. 'resMinutes' = minutos da produção bruta daquele recurso.
export const GEM_SHOP = [
  { id: 'ouro', name: '1 hora de ouro', icon: 'gold', gems: 10, reward: { type: 'goldMinutes', minutes: 60 } },
  { id: 'madeira', name: '1 hora de madeira', icon: 'wood', gems: 8, reward: { type: 'resMinutes', res: 'wood', minutes: 60 } },
  { id: 'pedra', name: '1 hora de pedra', icon: 'stone', gems: 8, reward: { type: 'resMinutes', res: 'stone', minutes: 60 } },
  { id: 'comida', name: '1 hora de comida', icon: 'food', gems: 6, reward: { type: 'resMinutes', res: 'food', minutes: 60 } },
  { id: 'impulso', name: 'Impulso de 30 min (+50% produção)', icon: 'boost', gems: 8, reward: { type: 'boost', minutes: 30 } },
  { id: 'pergaminho', name: 'Pergaminho de recrutamento', icon: 'scroll', gems: 15, reward: { type: 'scroll', amount: 1 } },
  { id: 'mudas', name: 'Crescer todas as mudas agora', icon: 'emblem-tree', gems: 3, reward: { type: 'growAll' } },
];

// Pacote de boas-vindas para quem volta depois de dias fora (retenção: voltar vale a pena).
export const WELCOME_BACK_DAYS = 2;
export const WELCOME_BACK = { gems: 3, scroll: 1, goldMinutes: 30 };
