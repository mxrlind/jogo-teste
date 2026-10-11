-- Heróis colecionáveis (porte de src/data/heroes.js). Bônus passivos valem só para heróis no Conselho.
local Util = require(script.Parent.Parent.Core.Util)

local H = {}

H.RARITIES = {
	comum = { id = "comum", name = "Comum", color = "#9aa5b1", weight = 60 },
	raro = { id = "raro", name = "Raro", color = "#4dabf7", weight = 28 },
	epico = { id = "epico", name = "Épico", color = "#b197fc", weight = 10 },
	lendario = { id = "lendario", name = "Lendário", color = "#ffd43b", weight = 2 },
}
-- Ordem fixa: o sorteio usa a mesma sequência do jogo web.
H.RARITY_ORDER = { "comum", "raro", "epico", "lendario" }

H.HEROES = {
	{ id = "lavradora", name = "Marta, a Lavradora", rarity = "comum", power = 2, bonus = { type = "prod:food", value = 0.15 }, lore = "Diz que conversa com as sementes. As sementes parecem concordar." },
	{ id = "lenhador", name = "Tito, o Lenhador", rarity = "comum", power = 3, bonus = { type = "prod:wood", value = 0.15 }, lore = "Nunca derrubou uma árvore que não pediu desculpas antes." },
	{ id = "pedreiro", name = "Joca, o Pedreiro", rarity = "comum", power = 3, bonus = { type = "prod:stone", value = 0.15 }, lore = "Constrói muros tão retos que dá pra usar como régua." },
	{ id = "guarda", name = "Guarda Bento", rarity = "comum", power = 5, bonus = { type = "defense", value = 0.15 }, lore = "Dorme em pé. Literalmente. É um talento." },
	{ id = "coletora", name = "Lia, a Coletora", rarity = "comum", power = 2, bonus = { type = "prod:gold", value = 0.1 }, lore = "Ninguém escapa dos impostos. Ninguém." },
	{ id = "mercadora", name = "Dona Safira", rarity = "raro", power = 4, bonus = { type = "prod:gold", value = 0.2 }, lore = "Vende gelo para pinguins e areia para camelos." },
	{ id = "arqueira", name = "Ayla, a Arqueira", rarity = "raro", power = 10, bonus = { type = "defense", value = 0.25 }, lore = "Acerta uma maçã a cem passos. Depois come a maçã." },
	{ id = "bardo", name = "Rui, o Bardo", rarity = "raro", power = 3, bonus = { type = "happiness", value = 8 }, lore = "Conhece 400 canções, 399 sobre si mesmo." },
	{ id = "exploradora", name = "Nina, a Exploradora", rarity = "raro", power = 6, bonus = { type = "expedition", value = 0.3 }, lore = 'O mapa dela tem uma seção chamada "ainda não".' },
	{ id = "arquiteta", name = "Helena, a Arquiteta", rarity = "epico", power = 6, bonus = { type = "cost", value = 0.15 }, lore = "Projetou o reino inteiro num guardanapo." },
	{ id = "cavaleiro", name = "Sir Dourado", rarity = "epico", power = 20, bonus = { type = "raidLoot", value = 0.5 }, lore = "Sua armadura brilha tanto que cega os inimigos. E os aliados." },
	{ id = "alquimista", name = "Zé Alquimista", rarity = "epico", power = 8, bonus = { type = "prodAll", value = 0.1 }, lore = "Transformou chumbo em ouro uma vez. Ou foi só tinta." },
	{ id = "druida", name = "Iara, a Druida", rarity = "epico", power = 9, bonus = { type = "terrainAdj", value = 0.5 }, lore = "As florestas crescem um pouco mais quando ela passa." },
	{ id = "rainha", name = "Rainha Aurora", rarity = "lendario", power = 25, bonus = { type = "prodAll", value = 0.25 }, lore = "Governou mil reinos. Escolheu o seu." },
	{ id = "dragao", name = "Brasa, o Dragão", rarity = "lendario", power = 50, bonus = { type = "defense", value = 1.0 }, lore = "Antes era a ameaça. Agora é o cão de guarda mais caro do continente." },
	{ id = "relojoeiro", name = "O Relojoeiro", rarity = "lendario", power = 10, bonus = { type = "offline", value = 0.25 }, lore = "Dizem que ele dá corda no próprio tempo." },
}

H.BONUS_TEXT = {
	["prod:food"] = "de comida", ["prod:wood"] = "de madeira", ["prod:stone"] = "de pedra", ["prod:gold"] = "de ouro",
	prodAll = "em toda produção", defense = "de defesa", happiness = "de felicidade", expedition = "nas expedições",
	cost = "no custo das obras", raidLoot = "de saque", terrainAdj = "nos bônus de terreno", offline = "de eficiência offline",
}

H.HERO_BY_ID = Util.byId(H.HEROES)
H.MAX_STARS = 5
H.BASE_COUNCIL_SLOTS = 3
H.RECRUIT_GOLD_BASE = 300
H.RECRUIT_GOLD_GROWTH = 1.6
H.RECRUIT_GEM_COST = 15

H.TAVERN_RECRUIT_DISCOUNT = 0.04
H.TAVERN_COUNCIL_LEVELS = { 5, 10 }

H.HERO_MAX_LEVEL = 10
H.HERO_LEVEL_STEP = 0.1
H.TRAIN_COST = { gold = 200, food = 80 }
H.TRAIN_COST_GROWTH = 1.8
H.TRAIN_RARITY_COST = { comum = 1, raro = 1.5, epico = 2.5, lendario = 4 }
H.TRAIN_SECONDS = 120

H.EXPEDITIONS = {
	{ id = "curta", name = "Patrulha", duration = 60, yield = 0.8, gemChance = 0, gems = { 0, 0 }, scrollChance = 0 },
	{ id = "media", name = "Exploração", duration = 300, yield = 0.9, gemChance = 0.1, gems = { 1, 1 }, scrollChance = 0.02 },
	{ id = "longa", name = "Jornada", duration = 1800, yield = 1, gemChance = 0.5, gems = { 1, 2 }, scrollChance = 0.06 },
	{ id = "epica", name = "Grande Expedição", duration = 7200, yield = 1.25, gemChance = 1, gems = { 2, 4 }, scrollChance = 0.15 },
}
H.EXPEDITION_GOLD_SHARE = 0.15
H.EXPEDITION_RES_SHARE = 0.1
H.BASE_EXPEDITION_SLOTS = 2
H.EXPEDITION_SPEEDUP_SECONDS = 300

return H
