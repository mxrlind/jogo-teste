-- Conquistas (porte de src/data/achievements.js): cada uma dá gemas e, às vezes, um título.
-- check(s, econ, heroes) recebe o estado, o resultado de computeEconomy e o catálogo de heróis.
-- progress(s, econ, heroes) devolve { atual, meta } para a barra de "próxima conquista".
-- kind: sem kind = essencial; "secret" = aparece como "???" com uma dica (hint) até sair;
-- "shadow" = sombra (como no Cookie Clicker): não conta no total nem no bônus de produção.
-- Cada conquista essencial ou secreta dá ACH_PROD_BONUS de produção para sempre.
-- icon é o nome do ícone no jogo web (a interface do Roblox pode mapear para os seus).
local A = {}

A.ACH_PROD_BONUS = 0.01

local function countBuildings(s)
	local n = 0
	for _, t in s.grid.tiles do
		if t.b then n += 1 end
	end
	return n
end

local function countOf(s, id)
	local n = 0
	for _, t in s.grid.tiles do
		if t.b and t.b.id == id then n += 1 end
	end
	return n
end

local function maxLvl(s, id)
	local m = 0
	for _, t in s.grid.tiles do
		if t.b and t.b.id == id and t.b.lvl > m then m = t.b.lvl end
	end
	return m
end

local function flag(id)
	return function(s)
		return s.flags ~= nil and s.flags[id] ~= nil and s.flags[id] ~= false and s.flags[id] ~= 0
	end
end

local function legendaries(s, heroes)
	local n = 0
	for id in s.heroes.owned do
		if heroes[id] and heroes[id].rarity == "lendario" then n += 1 end
	end
	return n
end

local function ownedCount(s)
	local n = 0
	for _ in s.heroes.owned do n += 1 end
	return n
end

local function anyTile(list, pred)
	for _, t in list do
		if t and pred(t) then return true end
	end
	return false
end

local function maxAnyLvl(s)
	local m = 0
	for _, t in s.grid.tiles do
		if t.b and t.b.lvl > m then m = t.b.lvl end
	end
	return m
end

local function stat(s, k)
	return s.stats[k] or 0
end

local function reached(s)
	return s.under and s.under.reached or 0
end

A.ACHIEVEMENTS = {
	{ id = "primeira-pedra", name = "Primeira Pedra", icon = "build", desc = "Construa seu primeiro prédio.", gems = 2, check = function(s) return s.stats.built >= 1 end, progress = function(s) return { s.stats.built, 1 } end },
	{ id = "vila", name = "Vilarejo", icon = "house", desc = "Tenha 10 construções.", gems = 3, check = function(s) return countBuildings(s) >= 10 end, progress = function(s) return { countBuildings(s), 10 } end },
	{ id = "cidade", name = "Cidade", icon = "tab-social", desc = "Tenha 25 construções.", gems = 5, title = "Prefeito", check = function(s) return countBuildings(s) >= 25 end, progress = function(s) return { countBuildings(s), 25 } end },
	{ id = "metropole", name = "Metrópole", icon = "castle", desc = "Tenha 50 construções.", gems = 10, title = "Grão-Duque", check = function(s) return countBuildings(s) >= 50 end, progress = function(s) return { countBuildings(s), 50 } end },
	{ id = "populoso", name = "Lotado", icon = "people", desc = "Alcance 50 moradores.", gems = 4, check = function(s) return s.pop >= 50 end, progress = function(s) return { math.floor(s.pop), 50 } end },
	{ id = "formigueiro", name = "Formigueiro", icon = "people", desc = "Alcance 150 moradores.", gems = 8, check = function(s) return s.pop >= 150 end, progress = function(s) return { math.floor(s.pop), 150 } end },
	{ id = "rico", name = "Bolso Cheio", icon = "gold", desc = "Ganhe 10 mil de ouro (vida toda).", gems = 3, check = function(s) return s.stats.totalGold >= 1e4 end, progress = function(s) return { s.stats.totalGold, 1e4 } end },
	{ id = "milionario", name = "Milionário", icon = "event-gold-rush", desc = "Ganhe 1 milhão de ouro (vida toda).", gems = 8, title = "Magnata", check = function(s) return s.stats.totalGold >= 1e6 end, progress = function(s) return { s.stats.totalGold, 1e6 } end },
	{ id = "bilionario", name = "Tesouro do Dragão", icon = "hero-dragon", desc = "Ganhe 1 bilhão de ouro (vida toda).", gems = 25, title = "Senhor do Ouro", check = function(s) return s.stats.totalGold >= 1e9 end, progress = function(s) return { s.stats.totalGold, 1e9 } end },
	{ id = "defensor", name = "Defensor", icon = "defense", desc = "Vença sua primeira invasão.", gems = 2, check = function(s) return s.stats.raidsWon >= 1 end, progress = function(s) return { s.stats.raidsWon, 1 } end },
	{ id = "muralha-viva", name = "Muralha Viva", icon = "talent-walls", desc = "Vença 10 invasões.", gems = 5, title = "Guardião", check = function(s) return s.stats.raidsWon >= 10 end, progress = function(s) return { s.stats.raidsWon, 10 } end },
	{ id = "imbativel", name = "Imbatível", icon = "swords", desc = "Vença 50 invasões.", gems = 12, title = "Conquistador", check = function(s) return s.stats.raidsWon >= 50 end, progress = function(s) return { s.stats.raidsWon, 50 } end },
	{ id = "recrutador", name = "Recrutador", icon = "scroll", desc = "Recrute 5 heróis.", gems = 3, check = function(s) return s.stats.recruits >= 5 end, progress = function(s) return { s.stats.recruits, 5 } end },
	{ id = "lenda", name = "Lenda Viva", icon = "star", desc = "Tenha um herói Lendário.", gems = 10, title = "Lendário", check = function(s, _e, heroes) return legendaries(s, heroes) >= 1 end },
	{ id = "colecionador", name = "Colecionador", icon = "tab-heroes", desc = "Tenha 10 heróis diferentes.", gems = 10, title = "Colecionador", check = function(s) return ownedCount(s) >= 10 end, progress = function(s) return { ownedCount(s), 10 } end },
	{ id = "explorador", name = "Andarilho", icon = "expedition", desc = "Complete 10 expedições.", gems = 4, check = function(s) return s.stats.expeditions >= 10 end, progress = function(s) return { s.stats.expeditions, 10 } end },
	{ id = "arquiteto", name = "Mestre de Obras", icon = "upgrade", desc = "Leve um prédio ao nível 10.", gems = 8, title = "Mestre de Obras", check = function(s)
		return anyTile(s.grid.tiles, function(t) return t.b ~= nil and t.b.lvl >= 10 end)
	end, progress = function(s) return { maxAnyLvl(s), 10 } end },
	{ id = "sinergia", name = "Sinergia Perfeita", icon = "hero-architect", desc = "Tenha um prédio com +150% de adjacência.", gems = 6, title = "Urbanista", check = function(_s, e)
		return anyTile(e.tiles, function(t) return t.adjBonus >= 1.5 end)
	end },
	{ id = "feliz", name = "Reino Feliz", icon = "heart", desc = "Alcance 100 de felicidade.", gems = 5, check = function(_s, e) return e.happiness >= 100 end, progress = function(_s, e) return { math.floor(e.happiness), 100 } end },
	{ id = "horizonte", name = "Horizonte", icon = "map", desc = "Desbloqueie o mapa inteiro.", gems = 8, check = function(s) return s.grid.ring >= 5 end, progress = function(s) return { s.grid.ring, 5 } end },
	{ id = "ascensao", name = "Renascido", icon = "crowns", desc = "Ascenda pela primeira vez.", gems = 10, title = "Renascido", check = function(s) return s.stats.ascensions >= 1 end },
	{ id = "dinastia", name = "Dinastia", icon = "emblem-lion", desc = "Ascenda 5 vezes.", gems = 20, title = "Imperador", check = function(s) return s.stats.ascensions >= 5 end, progress = function(s) return { s.stats.ascensions, 5 } end },
	{ id = "cacador", name = "Amigo dos Mercadores", icon = "cart", desc = "Atenda 25 carroças do mercador.", gems = 5, check = function(s) return s.stats.chests >= 25 end, progress = function(s) return { s.stats.chests, 25 } end },
	{ id = "fiel", name = "Súdito Fiel", icon = "calendar", desc = "Entre 7 dias seguidos.", gems = 10, title = "Fiel", check = function(s) return s.daily.streak >= 7 end, progress = function(s) return { s.daily.streak, 7 } end },

	-- ---- essenciais novas (0.17.0): marcam o caminho do jogo
	{ id = "jardineiro", name = "Jardineiro", icon = "emblem-tree", desc = "Plante 10 árvores.", gems = 2, check = function(s) return stat(s, "planted") >= 10 end, progress = function(s) return { stat(s, "planted"), 10 } end },
	{ id = "reflorestador", name = "Reflorestador", icon = "emblem-tree", desc = "Plante 100 árvores.", gems = 6, title = "Druida", check = function(s) return stat(s, "planted") >= 100 end, progress = function(s) return { stat(s, "planted"), 100 } end },
	{ id = "pedra-sobre-pedra", name = "Pedra sobre Pedra", icon = "talent-walls", desc = "Tenha 20 muralhas.", gems = 3, check = function(s) return countOf(s, "muralha") >= 20 end, progress = function(s) return { countOf(s, "muralha"), 20 } end },
	{ id = "primeira-isca", name = "Primeira Isca", icon = "food", desc = "Construa um Cais de Pesca.", gems = 2, check = function(s) return countOf(s, "cais") >= 1 end, progress = function(s) return { countOf(s, "cais"), 1 } end },
	{ id = "frota", name = "Frota Pesqueira", icon = "food", desc = "Tenha 3 Cais de Pesca.", gems = 4, check = function(s) return countOf(s, "cais") >= 3 end, progress = function(s) return { countOf(s, "cais"), 3 } end },
	{ id = "strike-the-earth", name = "Strike the Earth!", icon = "tool-pickaxe", desc = "Abra o subsolo com uma Escadaria.", gems = 3, check = function(s) return reached(s) >= 1 end, progress = function(s) return { reached(s), 1 } end },
	{ id = "fundo-demais", name = "Cavamos Fundo Demais", icon = "hero-dwarf", desc = "Chegue ao nível 3 do subsolo.", gems = 8, title = "Anão Honorário", check = function(s) return reached(s) >= 3 end, progress = function(s) return { reached(s), 3 } end },
	{ id = "toupeira", name = "Toupeira Real", icon = "tool-pickaxe", desc = "Cave 500 blocos no subsolo.", gems = 6, check = function(s) return stat(s, "dug") >= 500 end, progress = function(s) return { stat(s, "dug"), 500 } end },
	{ id = "quartel-general", name = "Quartel-General", icon = "swords", desc = "Termine 10 treinos de herói.", gems = 4, check = function(s) return stat(s, "trained") >= 10 end, progress = function(s) return { stat(s, "trained"), 10 } end },
	{ id = "taverna-lotada", name = "Taverna Lotada", icon = "house", desc = "Leve a Taverna ao nível 10.", gems = 6, title = "Taverneiro", check = function(s) return maxLvl(s, "taverna") >= 10 end, progress = function(s) return { maxLvl(s, "taverna"), 10 } end },
	{ id = "trio-lendario", name = "Trio Lendário", icon = "star", desc = "Tenha 3 heróis Lendários.", gems = 15, check = function(s, _e, heroes) return legendaries(s, heroes) >= 3 end, progress = function(s, _e, heroes) return { legendaries(s, heroes), 3 } end },
	{ id = "imperador-romano", name = "Assíduo", icon = "calendar", desc = "Entre 30 dias seguidos.", gems = 20, title = "Inabalável", check = function(s) return s.daily.streak >= 30 end, progress = function(s) return { s.daily.streak, 30 } end },
	{ id = "maratona", name = "Maratona", icon = "time", desc = "Jogue 10 horas no total.", gems = 5, check = function(s) return s.stats.playTime >= 36000 end, progress = function(s) return { math.floor(s.stats.playTime / 3600), 10 } end },

	-- ---- secretas e engraçadas: aparecem como "???" com uma dica até sair
	{ id = "curioso", kind = "secret", name = "Curioso", icon = "info", hint = "Toque numa conquista trancada.", desc = "Era só clicar. Sério.", gems = 1, check = flag("curious") },
	{ id = "para-de-cutucar", kind = "secret", name = "Para de Cutucar", icon = "greet", hint = "Insista num prédio.", desc = "Clique 30 vezes seguidas no mesmo prédio. Os moradores pediram medida protetiva.", gems = 2, check = flag("poke") },
	{ id = "mudei-de-ideia", kind = "secret", name = "Mudei de Ideia", icon = "demolish", hint = "Arrependimento é normal.", desc = "Desfaça 10 construções. O arquiteto pediu demissão.", gems = 2, check = function(s) return stat(s, "undos") >= 10 end },
	{ id = "engenharia-criativa", kind = "secret", name = "Engenharia Criativa", icon = "talent-engineering", hint = "Muralha também tem lado.", desc = "Tenha uma muralha de lado para a próxima horda. Metade da muralha, todo o orgulho.", gems = 2, check = flag("sidewall") },
	{ id = "bolso-furado", kind = "secret", name = "Bolso Furado", icon = "gold", hint = "Gaste tudo.", desc = "Fique sem nenhum ouro depois de já ter juntado 1.000. O tesoureiro fugiu com a carroça.", gems = 2, check = flag("broke") },
	{ id = "va-dormir", kind = "secret", name = "Vá Dormir, Majestade", icon = "time", hint = "Jogue quando o galo ainda dorme.", desc = "Jogue entre 3h e 5h da manhã. Os aldeões estão preocupados.", gems = 3, check = flag("nightOwl") },
	{ id = "eles-apostaram", kind = "secret", name = "Eles Apostaram", icon = "trade", hint = "Suma por um tempo.", desc = "Volte depois de 7 dias fora. Metade da vila apostou que você não voltava.", gems = 5, check = flag("comeback") },
	{ id = "codigo-antigo", kind = "secret", name = "Código Antigo", icon = "keyboard", hint = "Cima, cima...", desc = "Digite o código Konami. 30 vidas? Não, 5 gemas.", gems = 5, check = flag("konami") },
	{ id = "paz-e-sossego", kind = "secret", name = "Paz e Sossego", icon = "speaker-off", hint = "Shhh.", desc = "Desligue a música e os efeitos. Finalmente dá pra ouvir as galinhas.", gems = 1, check = flag("silence") },
	{ id = "deixa-queimar", kind = "secret", name = "Deixa Queimar", icon = "event-blood-moon", hint = "Perder também ensina.", desc = "Perca 3 invasões seguidas. Estratégia ousada.", gems = 3, check = function(s) return stat(s, "lossStreak") >= 3 end },
	{ id = "lenhador-arrependido", kind = "secret", name = "Lenhador Arrependido", icon = "hero-woodcutter", hint = "Plantou? Agora...", desc = "Arranque uma muda que você mesmo plantou. Ela só queria crescer.", gems = 1, check = flag("choppedOwn") },
	{ id = "nome-original", kind = "secret", name = "Muito Original", icon = "scroll", hint = "Criatividade no nome.", desc = 'Troque o nome do reino e depois volte para "Reino de Bolso". Ninguém pensou nisso antes.', gems = 1, check = flag("defaultName") },
	{ id = "clique-magico", kind = "secret", name = "Clique Mágico", icon = "gems", hint = "Será que multiplica?", desc = "Toque 10 vezes seguidas nas suas gemas. Não, elas não multiplicam.", gems = 1, check = flag("gemPoke") },

	-- ---- sombra: não contam no total nem no bônus (sorte pura ou meio trapaça)
	{ id = "pura-sorte", kind = "shadow", name = "Pura Sorte", icon = "star", hint = "Só deixe o jogo aberto.", desc = "Chance de 1 em 1 milhão por segundo com o jogo aberto. Jogue na loteria hoje.", gems = 10, check = flag("lucky") },
	{ id = "viajante-do-tempo", kind = "shadow", name = "Viajante do Tempo", icon = "hero-clock", hint = "Mexa no que não devia.", desc = "O relógio do aparelho voltou mais de 1 hora. O tempo não volta, majestade.", gems = 0, check = flag("timeTravel") },
	{ id = "insistente", kind = "shadow", name = "Insistente", icon = "warning", hint = "Não aceite um não.", desc = "Tente construir sem recursos 100 vezes. A resposta continua sendo não.", gems = 1, check = function(s) return stat(s, "failBuild") >= 100 end },
}

return A
