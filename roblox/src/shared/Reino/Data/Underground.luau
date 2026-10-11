-- Subsolo (porte de src/data/underground.js): três níveis de rocha embaixo do reino, escondidos por névoa.
local U = {}

U.DEPTHS = 3
U.LEVEL_NAMES = { "Galerias", "Cavernas", "Profundezas" }

-- `dig` = dá para cavar; `open` = espaço aberto (anda-se e constrói-se); `wall` conta como parede.
U.UNDER_TILES = {
	rock = { id = "rock", name = "Rocha", dig = true, wall = true, desc = "Rocha maciça. Cavar dá pedra e abre espaço para salas." },
	gold = { id = "gold", name = "Veio de ouro", dig = true, wall = true, desc = "Cavar rende muito ouro de uma vez; deixar o veio inteiro e construir um Garimpo ao lado rende ouro para sempre." },
	gem = { id = "gem", name = "Veio de gemas", dig = true, wall = true, desc = "Cristais raros. Cavar rende gemas." },
	water = { id = "water", name = "Aquífero", desc = "Água subterrânea: não dá para cavar. Hortas de fungos ao lado rendem mais." },
	magma = { id = "magma", name = "Magma", desc = "Rio de rocha derretida: não dá para cavar. Forjas só funcionam encostadas nele." },
	cavern = { id = "cavern", name = "Caverna", open = true, desc = "Caverna natural, úmida e escura. Só aqui crescem fungos." },
	floor = { id = "floor", name = "Galeria", open = true, desc = "Espaço cavado. Construa uma sala ou cave uma escada para descer." },
}

U.DIG_BASE = { gold = 12 }
U.DIG_DEPTH_GROWTH = 4
U.DIG_COUNT_GROWTH = 1.03
U.DIG_YIELD = {
	rock = { { stone = 12 }, { stone = 30 }, { stone = 70 } },
	gold = { { gold = 150 }, { gold = 600 }, { gold = 2400 } },
	gem = { { gems = 1 }, { gems = 1 }, { gems = 2 } },
}

U.STAIRS_COST = { { gold = 400, stone = 150 }, { gold = 3000, stone = 600 } }

U.ROOMS = {
	pedreira_funda = {
		id = "pedreira_funda", name = "Pedreira Funda", minDepth = 1,
		desc = "Tira pedra das paredes em volta: cada parede de rocha vizinha dá +15%.",
		cost = { gold = 150, wood = 40 }, prod = { stone = 0.5 }, adj = { wall = 0.15 }, maxLevel = 5,
	},
	adega = {
		id = "adega", name = "Adega", minDepth = 1,
		desc = "Fresca o ano todo: guarda mais comida e as fazendas rendem +5% por nível.",
		cost = { wood = 100, stone = 80 }, storage = { food = 500 }, foodBonus = 0.05, adj = {}, maxLevel = 5,
	},
	garimpo = {
		id = "garimpo", name = "Garimpo", minDepth = 1,
		desc = "Lava o ouro de um veio vizinho. Cada veio de ouro a mais encostado dá +50%.",
		cost = { gold = 400, stone = 100 }, prod = { gold = 3.0 }, requiresAdj = "gold", adj = { gold = 0.5 }, adjSkipFirst = true, maxLevel = 5,
	},
	fungos = {
		id = "fungos", name = "Horta de Fungos", minDepth = 2, onTile = "cavern",
		desc = "Cogumelos que crescem no escuro, só em caverna natural. Cada aquífero vizinho dá +25%.",
		cost = { gold = 250, wood = 40 }, prod = { food = 1.2 }, adj = { water = 0.25 }, maxLevel = 5,
	},
	forja = {
		id = "forja", name = "Forja de Magma", minDepth = 3,
		desc = "O calor do magma melhora as ferramentas de todo o reino: +10% de toda a produção por nível.",
		cost = { gold = 3000, stone = 800, wood = 300 }, prodAll = 0.1, requiresAdj = "magma", adj = {}, maxLevel = 3,
	},
}

U.ROOM_ORDER = { "pedreira_funda", "adega", "garimpo", "fungos", "forja" }

return U
