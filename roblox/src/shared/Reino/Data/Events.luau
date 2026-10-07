-- Eventos relâmpago, carroça do mercador e invasões (porte de src/data/events.js).
local Util = require(script.Parent.Parent.Core.Util)

local E = {}

E.EVENTS = {
	{ id = "colheita", name = "Festival da Colheita", duration = 90, desc = "Comida x3!", mods = { prod = { food = 2 } } },
	{ id = "febre", name = "Febre do Ouro", duration = 90, desc = "Ouro x2!", mods = { prod = { gold = 1 } } },
	{ id = "mutirao", name = "Mutirão", duration = 90, desc = "Construções -30%!", mods = { cost = 0.3 } },
	{ id = "inspiracao", name = "Inspiração Real", duration = 120, desc = "XP de temporada x2!", mods = { xp = 1 } },
	{ id = "lua", name = "Lua de Sangue", duration = 60, desc = "Uma horda chega em 30s. Saque x3!", mods = { raidLoot = 2 }, triggersRaid = 30 },
	{ id = "caravana", name = "Caravana Exótica", duration = 90, desc = "Madeira e pedra x2!", mods = { prod = { wood = 1, stone = 1 } } },
}

E.EVENT_BY_ID = Util.byId(E.EVENTS)
E.EVENT_INTERVAL = { 360, 600 }
E.CHEST_INTERVAL = { 100, 220 }
E.CHEST_LIFETIME = 20

E.RAID_FIRST_DELAY = 360
E.RAID_INTERVAL = 240
E.RAID_WARNING = 20
E.RAID_BASE_STRENGTH = 8
E.RAID_GROWTH = 1.4
E.RAID_LOSS_FRACTION = 0.15
E.RAID_NEWBIE_LOSS = 0.05
E.RAID_NEWBIE_COUNT = 2
E.RAID_LOSS_CAP_SECONDS = 120
E.RAID_NAMES = { "Goblins", "Bandidos", "Lobos Famintos", "Orcs", "Piratas do Rio", "Mortos-Vivos", "Trolls", "Cavaleiros Negros", "Gigantes", "Legião Sombria" }

return E
