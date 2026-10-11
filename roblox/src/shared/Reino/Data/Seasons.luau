-- Temporadas, passe e missões diárias (porte de src/data/seasons.js).
-- Cada temporada dura 28 dias a partir de SEASON_EPOCH e é calculada pelo relógio.
local Util = require(script.Parent.Parent.Core.Util)

local S = {}

S.SEASON_EPOCH = 1767571200000 -- Date.UTC(2026, 0, 5): segunda-feira, 5 jan 2026
S.SEASON_LENGTH_DAYS = 28
S.SEASON_TIERS = 30
S.XP_PER_TIER = 300

S.SEASON_THEMES = {
	{ id = "fundacao", name = "Fundação", color = "#51cf66",
		desc = "Tempo de erguer o reino. Ouro +10%, casas +25% e construções -10%.",
		mods = { prod = { gold = 0.1 }, houseBonus = 0.25, cost = 0.1 } },
	{ id = "guerra", name = "Guerra", color = "#ff6b6b",
		desc = "Hordas mais frequentes, porém o saque é dobrado e a defesa ganha +25%.",
		mods = { raidInterval = 0.6, raidLoot = 1.0, defense = 0.25 } },
	{ id = "expansao", name = "Expansão", color = "#4dabf7",
		desc = "Novas terras pela metade do preço e expedições +50%.",
		mods = { landCost = 0.5, expedition = 0.5 } },
	{ id = "catastrofe", name = "Catástrofe", color = "#ff922b",
		desc = "O mundo treme: eventos mais frequentes, felicidade -10, mas +50% de Coroas.",
		mods = { eventRate = 2, happiness = -10, crowns = 0.5 } },
}

local function themeLabel(themeId)
	local t = Util.find(S.SEASON_THEMES, function(x) return x.id == themeId end)
	return t and t.name or themeId
end

function S.tierReward(tier, _seasonNumber, themeId)
	if tier == S.SEASON_TIERS then
		return { type = "cosmetic", kind = "title", id = "campeao-" .. themeId, label = "Título: Campeão da " .. themeLabel(themeId) }
	end
	if tier == 21 then return { type = "cosmetic", kind = "emblem", id = "emblema-" .. themeId, label = "Emblema da Temporada" } end
	if tier == 14 then return { type = "cosmetic", kind = "banner", id = "estandarte-" .. themeId, label = "Estandarte da Temporada" } end
	if tier % 5 == 0 then return { type = "scroll", amount = 1, label = "1 Pergaminho de Recrutamento" } end
	if tier % 3 == 0 then
		local n = 5 + math.floor(tier / 3)
		return { type = "gems", amount = n, label = n .. " gemas" }
	end
	if tier % 2 == 0 then return { type = "boost", minutes = 10, label = "Bênção: +50% produção por 10 min" } end
	return { type = "goldMinutes", minutes = 5, label = "5 min de produção de ouro" }
end

S.MISSION_POOL = {
	{ id = "build", text = function(n) return "Construa " .. n .. " prédios" end, track = "build", amounts = { 3, 5, 8 }, xp = 60 },
	{ id = "upgrade", text = function(n) return "Melhore " .. n .. " prédios" end, track = "upgrade", amounts = { 2, 4, 6 }, xp = 70 },
	{ id = "raid", text = function(n) return "Vença " .. n .. " invasões" end, track = "raidWin", amounts = { 1, 2, 3 }, xp = 90 },
	{ id = "expedition", text = function(n) return "Complete " .. n .. " expedições" end, track = "expedition", amounts = { 2, 3, 5 }, xp = 70 },
	{ id = "chest", text = function(n) return "Atenda " .. n .. " carroças do mercador" end, track = "chest", amounts = { 2, 3, 4 }, xp = 60 },
	{ id = "gold", text = function(n) return "Ganhe " .. Util.fmt(n) .. " de ouro" end, track = "gold", amounts = { 2000, 10000, 50000 }, xp = 60, scale = true },
	{ id = "clear", text = function(n) return "Limpe " .. n .. " terrenos" end, track = "clear", amounts = { 1, 2, 3 }, xp = 50 },
	{ id = "visit", text = function(n) return "Visite " .. n .. " reinos vizinhos" end, track = "visit", amounts = { 1, 2, 3 }, xp = 40 },
}

S.XP_REWARDS = { build = 2, upgrade = 3, raidWin = 15, expedition = 10, chest = 5, daily = 50, clear = 1 }

return S
