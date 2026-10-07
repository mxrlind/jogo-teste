// Eventos relâmpago (live-ops local). Acontecem enquanto o jogador está online.

export const EVENTS = [
  { id: 'colheita', name: 'Festival da Colheita', icon: 'event-harvest', duration: 90, desc: 'Comida x3!', mods: { prod: { food: 2 } } },
  { id: 'febre', name: 'Febre do Ouro', icon: 'event-gold-rush', duration: 90, desc: 'Ouro x2!', mods: { prod: { gold: 1 } } },
  { id: 'mutirao', name: 'Mutirão', icon: 'event-work', duration: 90, desc: 'Construções -30%!', mods: { cost: 0.3 } },
  { id: 'inspiracao', name: 'Inspiração Real', icon: 'event-inspiration', duration: 120, desc: 'XP de temporada x2!', mods: { xp: 1 } },
  { id: 'lua', name: 'Lua de Sangue', icon: 'event-blood-moon', duration: 60, desc: 'Uma horda chega em 30s. Saque x3!', mods: { raidLoot: 2 }, triggersRaid: 30 },
  { id: 'caravana', name: 'Caravana Exótica', icon: 'event-caravan', duration: 90, desc: 'Madeira e pedra x2!', mods: { prod: { wood: 1, stone: 1 } } },
];

export const EVENT_BY_ID = Object.fromEntries(EVENTS.map((e) => [e.id, e]));
export const EVENT_INTERVAL = [360, 600]; // segundos entre eventos (min, máx)
export const CHEST_INTERVAL = [100, 220];
export const CHEST_LIFETIME = 20;

// Invasões
export const RAID_FIRST_DELAY = 360;
export const RAID_INTERVAL = 240;
export const RAID_WARNING = 20;
export const RAID_BASE_STRENGTH = 8;
export const RAID_GROWTH = 1.4;
export const RAID_LOSS_FRACTION = 0.1;
// Derrota também quebra construções do lado da horda (2 a 4 golpes; muralha e torre gastam 2 golpes cada).
export const RAID_HITS_MIN = 2;
export const RAID_HITS_MAX = 4;
export const RAID_DEFENSE_HITS = 2;
export const REPAIR_FRACTION = 0.3; // conserto = 30% do custo base por nível
export const RAID_NEWBIE_LOSS = 0.05; // proteção de novato: nas 2 primeiras invasões
export const RAID_NEWBIE_COUNT = 2;
export const RAID_LOSS_CAP_SECONDS = 120; // o saque nunca passa de 2 min de produção do recurso (poupar continua viável)
export const RAID_NAMES = ['Goblins', 'Bandidos', 'Lobos Famintos', 'Orcs', 'Piratas do Rio', 'Mortos-Vivos', 'Trolls', 'Cavaleiros Negros', 'Gigantes', 'Legião Sombria'];
