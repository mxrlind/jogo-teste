-- Árvore de Legado (porte de src/data/talents.js). Pago em Coroas, permanente entre Ascensões.
-- Custo do próximo nível = baseCost * (nível atual + 1).
local Util = require(script.Parent.Parent.Core.Util)

local T = {}

T.TALENTS = {
	{ id = "fartura", name = "Fartura", baseCost = 1, max = 20,
		desc = function(l) return string.format("+%d%% em toda produção", l * 10) end,
		effect = function(l) return { prodAll = 0.1 * l } end },
	{ id = "heranca", name = "Herança", baseCost = 1, max = 5,
		desc = function(l) return string.format("Começa com +%d ouro e +%d madeira", l * 500, l * 200) end,
		effect = function(l) return { startGold = 500 * l, startWood = 200 * l } end },
	{ id = "muralhas", name = "Muralhas Eternas", baseCost = 1, max = 10,
		desc = function(l) return string.format("+%d%% de defesa", l * 20) end,
		effect = function(l) return { defense = 0.2 * l } end },
	{ id = "vigilia", name = "Vigília", baseCost = 2, max = 5,
		desc = function(l) return string.format("+%dh de limite offline e +%d%% de eficiência offline", l * 2, l * 8) end,
		effect = function(l) return { offlineHours = 2 * l, offlineEff = 0.08 * l } end },
	{ id = "engenharia", name = "Engenharia", baseCost = 2, max = 6,
		desc = function(l) return string.format("-%d%% no custo de construções", l * 5) end,
		effect = function(l) return { cost = 0.05 * l } end },
	{ id = "garimpo", name = "Garimpo", baseCost = 4, max = 3,
		desc = function(l) return string.format("+%d gema(s) por invasão vencida", l) end,
		effect = function(l) return { raidGems = l } end },
	{ id = "terras", name = "Terras Ancestrais", baseCost = 5, max = 2,
		desc = function(l) return string.format("Começa com +%d anel(éis) de terra desbloqueado(s)", l) end,
		effect = function(l) return { startRing = l } end },
	{ id = "mesa", name = "Mesa Redonda", baseCost = 8, max = 2,
		desc = function(l) return string.format("+%d vaga(s) no Conselho de heróis", l) end,
		effect = function(l) return { councilSlots = l } end },
	{ id = "mordomo", name = "Mordomo Real", baseCost = 10, max = 1,
		desc = function(l) return l > 0 and "Carroças do mercador são atendidas sozinhas" or "Atende as carroças do mercador sozinho" end,
		effect = function(l) return { autoChest = l > 0 } end },
}

T.TALENT_BY_ID = Util.byId(T.TALENTS)

-- Coroas ganhas ao Ascender = floor(sqrt(ouroDaRodada / CROWN_DIVISOR) * (1 + bônus de templos))
T.CROWN_DIVISOR = 1000000

return T
