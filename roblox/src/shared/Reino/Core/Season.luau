-- Temporadas, passe de temporada e missões diárias (porte de src/core/season.js).
local Util = require(script.Parent.Util)
local Seasons = require(script.Parent.Parent.Data.Seasons)

local S = {}

local DAY = 86400000

function S.seasonInfo(now)
	local len = Seasons.SEASON_LENGTH_DAYS * DAY
	local index = math.max(0, math.floor((now - Seasons.SEASON_EPOCH) / len))
	local start = Seasons.SEASON_EPOCH + index * len
	local finish = start + len
	local theme = Seasons.SEASON_THEMES[index % #Seasons.SEASON_THEMES + 1]
	return { index = index, number = index + 1, theme = theme, start = start, finish = finish, remaining = (finish - now) / 1000 }
end

function S.tierOf(xp)
	return math.min(Seasons.SEASON_TIERS, math.floor(xp / Seasons.XP_PER_TIER))
end

-- Garante que o estado da temporada corresponde à temporada atual (troca de temporada = passe zera).
function S.syncSeason(state, now)
	local info = S.seasonInfo(now)
	if state.season.number ~= info.number then
		state.season = { number = info.number, xp = 0, claimed = {}, missions = state.season.missions }
		return true
	end
	return false
end

function S.dailyMissions(dateKey, goldScale)
	goldScale = goldScale or 1
	local rand = Util.mulberry32(Util.hashString("missoes-" .. dateKey))
	local pool = table.clone(Seasons.MISSION_POOL)
	local out = {}
	for _ = 1, 3 do
		local m = table.remove(pool, math.floor(rand() * #pool) + 1)
		local tier = math.floor(rand() * #m.amounts)
		local target = m.amounts[tier + 1]
		if m.scale then
			target = Util.round(target * goldScale)
		end
		table.insert(out, { id = m.id, track = m.track, target = target, xp = m.xp + tier * 20, progress = 0, claimed = false })
	end
	return out
end

function S.syncMissions(state, now, goldScale)
	local key = Util.dayKey(now)
	local missions = state.season.missions
	if not missions or missions.day ~= key then
		state.season.missions = { day = key, list = S.dailyMissions(key, goldScale) }
		return true
	end
	return false
end

function S.missionText(m)
	local def = Util.find(Seasons.MISSION_POOL, function(p) return p.id == m.id end)
	return def and def.text(m.target) or m.id
end

function S.rewardFor(tier, state)
	local number = state.season.number
	local themeIdx = (number - 1) % #Seasons.SEASON_THEMES + 1
	return Seasons.tierReward(tier, number, Seasons.SEASON_THEMES[themeIdx].id)
end

return S
