-- Heróis: recrutamento, conselho, quartel e expedições (porte de src/core/heroes.js).
local Util = require(script.Parent.Util)
local Economy = require(script.Parent.Economy)
local D = require(script.Parent.Parent.Data.Heroes)

local H = {}

function H.councilSlots(mods)
	return D.BASE_COUNCIL_SLOTS + (mods.councilSlots or 0)
end

-- Desconto da taverna mais alta no recrutamento com ouro (nível 1 = sem desconto, nível 10 = -36%).
function H.tavernDiscount(state)
	return D.TAVERN_RECRUIT_DISCOUNT * math.max(0, Economy.maxLevelOf(state, "taverna") - 1)
end

function H.recruitGoldCost(state)
	return math.ceil(D.RECRUIT_GOLD_BASE * D.RECRUIT_GOLD_GROWTH ^ state.stats.goldRecruits * (1 - H.tavernDiscount(state)))
end

-- Nível máximo de treino: nível do quartel mais alto + 1 (sem quartel, ninguém treina).
function H.heroLevelCap(state)
	local q = Economy.maxLevelOf(state, "quartel")
	return q > 0 and math.min(D.HERO_MAX_LEVEL, q + 1) or 1
end

-- Cada quartel treina um herói por vez.
function H.trainingSlots(state)
	return Economy.countOf(state, "quartel")
end

function H.trainingCount(state)
	local n = 0
	for _, h in state.heroes.owned do
		if h.training then n += 1 end
	end
	return n
end

function H.trainCost(hero, level)
	local f = D.TRAIN_COST_GROWTH ^ (level - 1) * D.TRAIN_RARITY_COST[hero.rarity]
	return Economy.scaleCost(D.TRAIN_COST, f)
end

function H.trainSeconds(level)
	return D.TRAIN_SECONDS * level
end

function H.recruitCost(state, method)
	if method == "gold" then return { gold = H.recruitGoldCost(state) } end
	if method == "gems" then return { gems = D.RECRUIT_GEM_COST } end
	return { scrolls = 1 }
end

function H.rollHero(rand)
	local rarities = Util.map(D.RARITY_ORDER, function(id) return D.RARITIES[id] end)
	local rarity = Util.weightedPick(rand, rarities, function(r) return r.weight end)
	return Util.pick(rand, Util.filter(D.HEROES, function(h) return h.rarity == rarity.id end))
end

-- Adiciona o herói (ou estrela, se duplicado). Retorna { hero, isNew, stars, gemsRefund }.
function H.addHero(state, hero)
	local owned = state.heroes.owned[hero.id]
	if not owned then
		state.heroes.owned[hero.id] = { stars = 1, level = 1 }
		return { hero = hero, isNew = true, stars = 1, gemsRefund = 0 }
	end
	if owned.stars < D.MAX_STARS then
		owned.stars += 1
		return { hero = hero, isNew = false, stars = owned.stars, gemsRefund = 0 }
	end
	local refundGems = ({ comum = 2, raro = 5, epico = 10, lendario = 25 })[hero.rarity]
	state.res.gems += refundGems
	return { hero = hero, isNew = false, stars = owned.stars, gemsRefund = refundGems }
end

function H.expeditionReward(state, hero, exp, econ, rand)
	local owned = state.heroes.owned[hero.id]
	local power = Economy.heroPowerOf(hero, owned)
	local mult = (1 + power * 0.02) * (1 + econ.mods.expedition) * exp.yield
	local reward = {
		gold = math.floor(math.max(30, econ.rates.gold * exp.duration * D.EXPEDITION_GOLD_SHARE) * mult),
		wood = math.floor(math.max(10, econ.gross.wood * exp.duration * D.EXPEDITION_RES_SHARE) * mult),
		stone = math.floor(math.max(5, econ.gross.stone * exp.duration * D.EXPEDITION_RES_SHARE) * mult),
		gems = 0,
		scrolls = 0,
	}
	if rand() < exp.gemChance then reward.gems = Util.randInt(rand, exp.gems[1], exp.gems[2]) end
	if rand() < exp.scrollChance then reward.scrolls = 1 end
	return reward
end

function H.speedUpCost(remainingSec)
	return math.max(1, math.ceil(remainingSec / 600))
end

function H.expeditionSpeedUpCost(remainingSec)
	return math.max(1, math.ceil(remainingSec / D.EXPEDITION_SPEEDUP_SECONDS))
end

function H.expeditionSlots(state)
	local tavern = Economy.maxLevelOf(state, "taverna")
	local n = D.BASE_EXPEDITION_SLOTS
	for _, l in D.TAVERN_COUNCIL_LEVELS do
		if tavern >= l then n += 1 end
	end
	return n
end

function H.activeExpeditions(state)
	local n = 0
	for _, h in state.heroes.owned do
		if h.expedition then n += 1 end
	end
	return n
end

return H
