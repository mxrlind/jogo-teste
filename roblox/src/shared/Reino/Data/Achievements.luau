-- Conquistas (porte de src/data/achievements.js): cada uma dá gemas e, às vezes, um título.
-- check(s, econ, heroes) recebe o estado e o resultado de computeEconomy.
local A = {}

local function countBuildings(s)
	local n = 0
	for _, t in s.grid.tiles do
		if t.b then n += 1 end
	end
	return n
end

local function anyTile(list, pred)
	for _, t in list do
		if t and pred(t) then return true end
	end
	return false
end

A.ACHIEVEMENTS = {
	{ id = "primeira-pedra", name = "Primeira Pedra", desc = "Construa seu primeiro prédio.", gems = 2, check = function(s) return s.stats.built >= 1 end },
	{ id = "vila", name = "Vilarejo", desc = "Tenha 10 construções.", gems = 3, check = function(s) return countBuildings(s) >= 10 end },
	{ id = "cidade", name = "Cidade", desc = "Tenha 25 construções.", gems = 5, title = "Prefeito", check = function(s) return countBuildings(s) >= 25 end },
	{ id = "metropole", name = "Metrópole", desc = "Tenha 50 construções.", gems = 10, title = "Grão-Duque", check = function(s) return countBuildings(s) >= 50 end },
	{ id = "populoso", name = "Lotado", desc = "Alcance 50 moradores.", gems = 4, check = function(s) return s.pop >= 50 end },
	{ id = "formigueiro", name = "Formigueiro", desc = "Alcance 150 moradores.", gems = 8, check = function(s) return s.pop >= 150 end },
	{ id = "rico", name = "Bolso Cheio", desc = "Ganhe 10 mil de ouro (vida toda).", gems = 3, check = function(s) return s.stats.totalGold >= 1e4 end },
	{ id = "milionario", name = "Milionário", desc = "Ganhe 1 milhão de ouro (vida toda).", gems = 8, title = "Magnata", check = function(s) return s.stats.totalGold >= 1e6 end },
	{ id = "bilionario", name = "Tesouro do Dragão", desc = "Ganhe 1 bilhão de ouro (vida toda).", gems = 25, title = "Senhor do Ouro", check = function(s) return s.stats.totalGold >= 1e9 end },
	{ id = "defensor", name = "Defensor", desc = "Vença sua primeira invasão.", gems = 2, check = function(s) return s.stats.raidsWon >= 1 end },
	{ id = "muralha-viva", name = "Muralha Viva", desc = "Vença 10 invasões.", gems = 5, title = "Guardião", check = function(s) return s.stats.raidsWon >= 10 end },
	{ id = "imbativel", name = "Imbatível", desc = "Vença 50 invasões.", gems = 12, title = "Conquistador", check = function(s) return s.stats.raidsWon >= 50 end },
	{ id = "recrutador", name = "Recrutador", desc = "Recrute 5 heróis.", gems = 3, check = function(s) return s.stats.recruits >= 5 end },
	{ id = "lenda", name = "Lenda Viva", desc = "Tenha um herói Lendário.", gems = 10, title = "Lendário", check = function(s, _e, heroes)
		for id in s.heroes.owned do
			if heroes[id] and heroes[id].rarity == "lendario" then return true end
		end
		return false
	end },
	{ id = "colecionador", name = "Colecionador", desc = "Tenha 10 heróis diferentes.", gems = 10, title = "Colecionador", check = function(s)
		local n = 0
		for _ in s.heroes.owned do n += 1 end
		return n >= 10
	end },
	{ id = "explorador", name = "Andarilho", desc = "Complete 10 expedições.", gems = 4, check = function(s) return s.stats.expeditions >= 10 end },
	{ id = "arquiteto", name = "Mestre de Obras", desc = "Leve um prédio ao nível 10.", gems = 8, title = "Mestre de Obras", check = function(s)
		return anyTile(s.grid.tiles, function(t) return t.b ~= nil and t.b.lvl >= 10 end)
	end },
	{ id = "sinergia", name = "Sinergia Perfeita", desc = "Tenha um prédio com +150% de adjacência.", gems = 6, title = "Urbanista", check = function(_s, e)
		return anyTile(e.tiles, function(t) return t.adjBonus >= 1.5 end)
	end },
	{ id = "feliz", name = "Reino Feliz", desc = "Alcance 100 de felicidade.", gems = 5, check = function(_s, e) return e.happiness >= 100 end },
	{ id = "horizonte", name = "Horizonte", desc = "Desbloqueie o mapa inteiro.", gems = 8, check = function(s) return s.grid.ring >= 5 end },
	{ id = "ascensao", name = "Renascido", desc = "Ascenda pela primeira vez.", gems = 10, title = "Renascido", check = function(s) return s.stats.ascensions >= 1 end },
	{ id = "dinastia", name = "Dinastia", desc = "Ascenda 5 vezes.", gems = 20, title = "Imperador", check = function(s) return s.stats.ascensions >= 5 end },
	{ id = "cacador", name = "Amigo dos Mercadores", desc = "Atenda 25 carroças do mercador.", gems = 5, check = function(s) return s.stats.chests >= 25 end },
	{ id = "fiel", name = "Súdito Fiel", desc = "Entre 7 dias seguidos.", gems = 10, title = "Fiel", check = function(s) return s.daily.streak >= 7 end },
}

return A
