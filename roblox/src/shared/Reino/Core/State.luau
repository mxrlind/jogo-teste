-- Estado do jogo: criação, herança da Ascensão e normalização de saves (porte de src/core/state.js).
-- No Roblox o save vai para o DataStore como tabela (o próprio DataStore converte para JSON).
local Util = require(script.Parent.Util)
local Map = require(script.Parent.Map)
local Under = require(script.Parent.Underground)
local Season = require(script.Parent.Season)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Talents = require(script.Parent.Parent.Data.Talents)
local Events = require(script.Parent.Parent.Data.Events)

local S = {}

S.SAVE_VERSION = 1 -- versão do save do Roblox (independente da versão do save do navegador)
S.ALL_TABS = { "reino", "herois", "temporada", "legado", "social", "perfil" }

function S.newSeed()
	return math.floor(Util.random() * 2 ^ 31)
end

local function freshStats()
	return {
		totalGold = 0, runGold = 0, built = 0, upgrades = 0, raidsWon = 0, raidsLost = 0, recruits = 0, goldRecruits = 0,
		expeditions = 0, chests = 0, ascensions = 0, cleared = 0, planted = 0, dug = 0, visits = 0, playTime = 0, bestRaid = 0,
	}
end

-- opts: { seed, now, carry }
function S.createState(opts)
	opts = opts or {}
	local seed = opts.seed or S.newSeed()
	local now = assert(opts.now, "createState precisa de now")
	local carry = opts.carry
	local legacy = carry and carry.legacy or {}
	local function lvl(id) return legacy[id] or 0 end
	local startTalent = Talents.TALENT_BY_ID.heranca.effect(lvl("heranca"))
	local ringTalent = Talents.TALENT_BY_ID.terras.effect(lvl("terras"))

	local grid = Map.generateMap(seed)
	grid.ring = math.min(Map.MAX_RING, Map.START_RING + ringTalent.startRing)
	local stats = carry and Util.merge(freshStats(), carry.stats) or freshStats()
	stats.runGold = 0

	return {
		version = S.SAVE_VERSION,
		seed = seed,
		createdAt = carry and carry.createdAt or now,
		runStartedAt = now,
		lastTick = now,
		kingdom = carry and carry.kingdom or { name = "Reino de Bolso", banner = "carmesim", emblem = "coroa", title = "Fundador" },
		res = {
			gold = 100 + startTalent.startGold,
			food = 50,
			wood = 30 + startTalent.startWood,
			stone = 25, -- paga a primeira muralha (tutorial, passo 4)
			gems = carry and carry.res.gems or 0,
			crowns = carry and carry.res.crowns or 0,
		},
		pop = 1,
		grid = grid,
		under = Under.createUnder(seed),
		heroes = carry and carry.heroes or { owned = {}, council = {} },
		items = carry and carry.items or { scrolls = 1 },
		raid = { level = 0, nextAt = now + Events.RAID_FIRST_DELAY * 1000, warned = false, dir = "n" },
		nextEventAt = now + 240000,
		nextChestAt = now + 60000,
		boostUntil = 0,
		legacy = legacy,
		season = carry and carry.season or { number = Season.seasonInfo(now).number, xp = 0, claimed = {} },
		achievements = carry and carry.achievements or {},
		cosmetics = carry and carry.cosmetics or { banners = {}, emblems = {}, titles = table.clone(Cosmetics.BASE_TITLES) },
		daily = carry and carry.daily or { streak = 0 },
		social = carry and carry.social or { trades = {}, greets = {}, rivalsSeed = seed },
		tutorial = carry and { done = true, step = 99 } or { done = false, step = 0 },
		unlocks = carry and carry.unlocks or { tabs = { "reino", "perfil" } },
		stats = stats,
		runBase = Util.copy(stats),
		runs = carry and carry.runs or {},
		records = carry and carry.records or {},
		log = {},
	}
end

-- Herança para a próxima rodada (Ascensão): o que é "identidade" persiste.
function S.carryOver(state)
	for _, h in state.heroes.owned do
		h.expedition = nil
		-- Treino pago não se perde na Ascensão: o herói sobe de nível na hora.
		if h.training then
			h.level = (h.level or 1) + 1
			h.training = nil
		end
	end
	return {
		legacy = state.legacy,
		createdAt = state.createdAt,
		kingdom = state.kingdom,
		res = { gems = state.res.gems, crowns = state.res.crowns },
		heroes = state.heroes,
		items = state.items,
		season = state.season,
		achievements = state.achievements,
		cosmetics = state.cosmetics,
		daily = state.daily,
		social = state.social,
		stats = state.stats,
		unlocks = state.unlocks,
		runs = state.runs,
		records = state.records,
	}
end

-- O que vai para o DataStore: tudo menos o diário de eventos.
function S.serialize(state)
	local out = Util.copy(state)
	out.log = nil
	return Util.deepCopy(out)
end

-- Aceita um save do DataStore e completa campos que faltem (saves de versões anteriores do porte).
function S.normalize(data, now)
	if type(data) ~= "table" or type(data.grid) ~= "table" or type(data.grid.tiles) ~= "table" or type(data.res) ~= "table" then
		error("Save inválido")
	end
	if (tonumber(data.version) or 1) > S.SAVE_VERSION then
		error("Save de uma versão mais nova do jogo")
	end
	local base = S.createState({ seed = data.seed or 1, now = data.lastTick or now })
	local merged = Util.merge(base, data)
	for _, k in { "stats", "items", "social", "raid", "unlocks", "res", "kingdom", "daily", "cosmetics", "tutorial" } do
		merged[k] = Util.merge(base[k], data[k])
	end
	merged.heroes = data.heroes or base.heroes
	merged.heroes.owned = merged.heroes.owned or {}
	merged.heroes.council = merged.heroes.council or {}
	for _, h in merged.heroes.owned do
		h.level = h.level or 1
	end
	merged.season = data.season or base.season
	merged.season.claimed = merged.season.claimed or {}
	merged.legacy = data.legacy or {}
	merged.achievements = data.achievements or {}
	merged.runs = data.runs or {}
	merged.records = data.records or {}
	merged.under = data.under or base.under
	merged.log = {}
	merged.version = S.SAVE_VERSION
	return merged
end

return S
