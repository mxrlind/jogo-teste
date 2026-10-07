-- Economia: agrega modificadores e calcula produção, população, defesa e custos (porte de src/core/economy.js).
-- Função pura: computeEconomy(state, now) não altera o estado.
local Util = require(script.Parent.Util)
local Map = require(script.Parent.Map)
local Season = require(script.Parent.Season)
local Under = require(script.Parent.Underground)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local HeroData = require(script.Parent.Parent.Data.Heroes)
local Talents = require(script.Parent.Parent.Data.Talents)
local Events = require(script.Parent.Parent.Data.Events)

local BUILDINGS, TERRAIN = Buildings.BUILDINGS, Buildings.TERRAIN
local GRID_W, GRID_H, idx = Map.GRID_W, Map.GRID_H, Map.idx

local E = {}

E.PROD_RES = { "gold", "food", "wood", "stone" }
local PROD_RES = E.PROD_RES
local DIRS = { "n", "s", "e", "w" }

function E.heroMultiplier(stars)
	return 1 + 0.5 * (stars - 1)
end

function E.heroLevelMult(level)
	return 1 + HeroData.HERO_LEVEL_STEP * ((level or 1) - 1)
end

-- Multiplicador do bônus de um herói recrutado (estrelas e nível de treino).
function E.heroStrength(owned)
	return E.heroMultiplier(owned.stars) * E.heroLevelMult(owned.level)
end

function E.heroPowerOf(hero, owned)
	return Util.round(hero.power * owned.stars * E.heroLevelMult(owned.level))
end

-- Maior nível de um tipo de prédio no mapa (0 se não houver nenhum).
function E.maxLevelOf(state, id)
	local lvl = 0
	for _, t in state.grid.tiles do
		if t.b and t.b.id == id and t.b.lvl > lvl then lvl = t.b.lvl end
	end
	return lvl
end

-- Soma de todos os modificadores ativos: talentos, conselho, temporada, evento e bênção.
function E.collectModifiers(state, now)
	local m = {
		prodAll = 0, prod = { gold = 0, food = 0, wood = 0, stone = 0 }, eventProd = { gold = 0, food = 0, wood = 0, stone = 0 },
		defense = 0, happiness = 0, cost = 0, raidLoot = 0, raidGems = 0, expedition = 0, terrainAdj = 0,
		offlineEff = 0, offlineHours = 0, councilSlots = 0, xp = 0, houseBonus = 0, landCost = 0,
		raidInterval = 1, eventRate = 1, crowns = 0, autoChest = false, startGold = 0, startWood = 0, startRing = 0,
	}

	for id, lvl in state.legacy do
		local t = Talents.TALENT_BY_ID[id]
		if t and lvl and lvl > 0 then
			for k, v in t.effect(lvl) do
				if type(v) == "boolean" then
					m[k] = m[k] or v
				else
					m[k] += v
				end
			end
		end
	end

	local tavern = E.maxLevelOf(state, "taverna")
	for _, l in HeroData.TAVERN_COUNCIL_LEVELS do
		if tavern >= l then m.councilSlots += 1 end
	end

	for _, hid in state.heroes.council do
		local h = HeroData.HERO_BY_ID[hid]
		local owned = state.heroes.owned[hid]
		if h and owned then
			local v = h.bonus.value * E.heroStrength(owned)
			local kind, res = string.match(h.bonus.type, "^(%w+):(%w+)$")
			if kind == "prod" then
				m.prod[res] += v
			elseif h.bonus.type == "offline" then
				m.offlineEff += v
				m.offlineHours += 4 * owned.stars
			else
				m[h.bonus.type] += v
			end
		end
	end

	local season = Season.seasonInfo(now).theme.mods
	if season.prod then
		for r, v in season.prod do m.prod[r] += v end
	end
	for _, k in { "houseBonus", "cost", "defense", "raidLoot", "landCost", "expedition", "happiness", "crowns" } do
		if season[k] then m[k] += season[k] end
	end
	if season.raidInterval then m.raidInterval *= season.raidInterval end
	if season.eventRate then m.eventRate *= season.eventRate end

	if state.event and state.event.endsAt > now then
		local ev = Events.EVENT_BY_ID[state.event.id]
		if ev then
			if ev.mods.prod then
				for r, v in ev.mods.prod do m.eventProd[r] += v end
			end
			if ev.mods.cost then m.cost += ev.mods.cost end
			if ev.mods.xp then m.xp += ev.mods.xp end
			if ev.mods.raidLoot then m.raidLoot += ev.mods.raidLoot end
		end
	end

	-- Subsolo: Forja de Magma (+produção geral) e Adega (+comida).
	local um = Under.underMods(state)
	m.prodAll += um.prodAll
	m.prod.food += um.food

	if state.boostUntil > now then m.prodAll += 0.5 end
	m.cost = math.min(0.75, m.cost)
	return m
end

function E.levelMult(lvl)
	return 1 + Buildings.LEVEL_OUTPUT_STEP * (lvl - 1)
end

-- Armazéns crescem com o quadrado do nível para acompanhar custos exponenciais.
function E.storageMult(lvl)
	return lvl * lvl
end

function E.workersFor(def, lvl)
	return def.workers + math.floor((lvl - 1) * def.workers * 0.5)
end

-- Peso de uma defesa em (x, y) contra uma horda vinda de `dir`: 100% na borda de onde ela vem, 50% na oposta.
function E.dirWeight(dir, x, y)
	local fy = y / (GRID_H - 1)
	local fx = x / (GRID_W - 1)
	local near = ({ n = 1 - fy, s = fy, w = 1 - fx, e = fx })[dir] or 0.5
	return 0.5 + 0.5 * near
end

-- Muralha de frente para a horda conta inteira; de lado, só metade. Muralha sozinha conta inteira.
E.SIDEWAYS_WALL = 0.5
function E.wallFacing(mask, dir)
	if mask == 0 then return 1 end
	local across
	if dir == "n" or dir == "s" then
		across = bit32.band(mask, 10)
	else
		across = bit32.band(mask, 5)
	end
	return across ~= 0 and 1 or E.SIDEWAYS_WALL
end

function E.defenseWeight(state, id, dir, x, y)
	local w = E.dirWeight(dir, x, y)
	if id == "muralha" then
		return w * E.wallFacing(Map.wallMask(state.grid, x, y), dir)
	end
	return w
end

-- Bônus de adjacência de um prédio hipotético `id` na posição (x, y).
function E.adjacencyAt(state, id, x, y, mods)
	local def = BUILDINGS[id]
	local parts = {}
	local total = 0
	local hasRequired = def.requiresAdj == nil
	for _, n in Map.neighbors(x, y) do
		local nt = state.grid.tiles[idx(n[1], n[2])]
		local key = Map.adjKey(nt)
		if def.requiresAdj and key == def.requiresAdj then hasRequired = true end
		local v = def.adj[key] or 0
		if v > 0 and TERRAIN[key] then
			v *= 1 + (mods and mods.terrainAdj or 0)
		end
		if v ~= 0 then
			table.insert(parts, { x = n[1], y = n[2], key = key, value = v })
			total += v
		end
	end
	return { total = total, parts = parts, hasRequired = hasRequired }
end

function E.computeEconomy(state, now)
	local mods = E.collectModifiers(state, now)
	local tiles = {} -- índice do tile -> info (só onde há prédio)
	local popCap = 0
	local workersNeeded = 0
	local happinessRaw = 50 + mods.happiness
	local globalGold = 0
	local crownBonus = 0
	local caps = Util.copy(Buildings.BASE_STORAGE)
	local n = #state.grid.tiles

	-- 1ª passada: estrutura (adjacência, população, trabalhadores, felicidade, armazenamento)
	for i = 1, n do
		local tile = state.grid.tiles[i]
		local def = tile.b and BUILDINGS[tile.b.id]
		if def then
			local x, y = Map.xy(i)
			local lm = E.levelMult(tile.b.lvl)
			local adj = E.adjacencyAt(state, tile.b.id, x, y, mods)
			local info = {
				id = tile.b.id, lvl = tile.b.lvl, adjBonus = adj.total, adjParts = adj.parts,
				active = adj.hasRequired, mult = math.max(0, 1 + adj.total) * lm, workers = E.workersFor(def, tile.b.lvl),
				out = {}, defense = 0, staff = 1,
			}
			tiles[i] = info
			if def.popCap then popCap += def.popCap * tile.b.lvl end
			workersNeeded += info.workers
			if def.happiness then
				happinessRaw += def.happiness * (def.happiness > 0 and info.mult or 1)
			end
			if def.storage then
				for r, v in def.storage do caps[r] += v * E.storageMult(tile.b.lvl) end
			end
			if def.globalGold then globalGold += def.globalGold end
			if def.crownBonus then crownBonus += def.crownBonus end
		end
	end

	local pop = state.pop
	happinessRaw -= 2 * math.floor(pop / 20)
	local happiness = math.max(0, math.min(100, happinessRaw))
	local happinessMult = 0.5 + happiness / 100
	local staffing = workersNeeded > 0 and math.min(1, pop / workersNeeded) or 1
	-- Moradores ocupam primeiro as vagas que produzem comida.
	local foodWorkers = 0
	for _, info in tiles do
		local prod = BUILDINGS[info.id].prod
		if info.active and prod and prod.food then foodWorkers += info.workers end
	end
	local foodStaffing = foodWorkers > 0 and math.min(1, pop / foodWorkers) or 1
	local otherWorkers = workersNeeded - foodWorkers
	local otherStaffing = otherWorkers > 0 and math.max(0, math.min(1, (pop - foodWorkers) / otherWorkers)) or 1
	local occupancy = popCap > 0 and math.min(1, pop / popCap) or 0

	local prodMult = {}
	for _, r in PROD_RES do
		prodMult[r] = (1 + mods.prodAll + mods.prod[r]) * (1 + mods.eventProd[r]) * (r == "gold" and 1 + globalGold or 1)
	end

	-- 2ª passada: produção bruta
	local gross = { gold = 0, food = 0, wood = 0, stone = 0 }
	local foodDemandMarkets = 0
	local defDir = { n = 0, s = 0, e = 0, w = 0 }
	local marketTiles = {}
	for i = 1, n do
		local info = tiles[i]
		if info then
			local def = BUILDINGS[info.id]
			local staff
			if info.workers == 0 then
				staff = 1
			elseif info.active and def.prod and def.prod.food then
				staff = foodStaffing
			else
				staff = otherStaffing
			end
			info.staff = staff
			local eff = info.active and info.mult * staff or 0
			if def.prod then
				for r, base in def.prod do
					local v = base * eff * happinessMult * prodMult[r]
					if def.id == "casa" then v *= occupancy * (1 + mods.houseBonus) end
					info.out[r] = v
					gross[r] += v
				end
			end
			if def.consume and def.consume.food then
				local c = def.consume.food * E.levelMult(info.lvl) * staff
				info.consume = c
				foodDemandMarkets += c
				table.insert(marketTiles, info)
			end
			if def.defense then
				info.defense = def.defense * eff
				local x, y = Map.xy(i)
				for _, d in DIRS do
					defDir[d] += info.defense * E.defenseWeight(state, info.id, d, x, y)
				end
			end
		end
	end

	-- Subsolo: salas não usam moradores, mas seguem felicidade e multiplicadores globais.
	local under = Under.underEconomy(state, function(r) return happinessMult * prodMult[r] end)
	for _, r in PROD_RES do gross[r] += under.gross[r] end
	for r, v in under.caps do caps[r] += v end

	-- Comida: moradores comem primeiro; mercados só convertem o que sobra quando o estoque acabou.
	local foodPop = pop * Buildings.FOOD_PER_POP
	local marketRatio = 1
	if state.res.food <= 0.01 and foodDemandMarkets > 0 then
		local available = math.max(0, gross.food - foodPop)
		marketRatio = math.min(1, available / foodDemandMarkets)
	end
	for _, info in marketTiles do
		if marketRatio < 1 then
			gross.gold -= info.out.gold * (1 - marketRatio)
			info.out.gold *= marketRatio
			info.consume *= marketRatio
		end
	end
	local foodConsumption = foodPop + foodDemandMarkets * marketRatio

	-- Heróis do conselho somam poder à defesa.
	local heroPower = 0
	for _, hid in state.heroes.council do
		local owned = state.heroes.owned[hid]
		if owned and not owned.expedition and HeroData.HERO_BY_ID[hid] then
			heroPower += E.heroPowerOf(HeroData.HERO_BY_ID[hid], owned)
		end
	end
	local defenseByDir = {}
	for _, d in DIRS do
		defenseByDir[d] = (defDir[d] + heroPower) * (1 + mods.defense)
	end
	local defense = defenseByDir[state.raid and state.raid.dir] or defenseByDir.n

	local rates = {
		gold = gross.gold,
		food = gross.food - foodConsumption,
		wood = gross.wood,
		stone = gross.stone,
	}

	return {
		mods = mods, tiles = tiles, rates = rates, gross = gross, foodConsumption = foodConsumption, popCap = popCap,
		workersNeeded = workersNeeded, staffing = staffing, occupancy = occupancy, happiness = happiness,
		happinessMult = happinessMult, defense = defense, defenseByDir = defenseByDir, heroPower = heroPower,
		caps = caps, crownBonus = crownBonus, marketRatio = marketRatio, under = under.levels,
	}
end

function E.countOf(state, id)
	local n = 0
	for _, t in state.grid.tiles do
		if t.b and t.b.id == id then n += 1 end
	end
	return n
end

local function scaleCost(cost, factor)
	local out = {}
	for r, v in cost do
		out[r] = math.ceil(v * factor)
	end
	return out
end
E.scaleCost = scaleCost

function E.buildCost(state, id, mods)
	local def = BUILDINGS[id]
	return scaleCost(def.cost, Buildings.COUNT_COST_GROWTH ^ E.countOf(state, id) * (1 - mods.cost))
end

function E.upgradeCost(id, lvl, mods)
	local def = BUILDINGS[id]
	if lvl >= (def.maxLevel or Buildings.MAX_LEVEL) then return nil end
	return scaleCost(def.cost, Buildings.LEVEL_COST_GROWTH ^ lvl * (1 - mods.cost))
end

function E.canAfford(res, cost)
	for r, v in cost do
		if (res[r] or 0) < v then return false end
	end
	return true
end

function E.pay(res, cost)
	for r, v in cost do
		res[r] = (res[r] or 0) - v
	end
end

function E.refund(res, cost, fraction)
	for r, v in cost do
		res[r] = (res[r] or 0) + math.floor(v * fraction)
	end
end

-- "Poder do Reino": pontuação usada no ranking social.
function E.kingdomPower(state)
	local buildings = 0
	for _, t in state.grid.tiles do
		if t.b then buildings += t.b.lvl end
	end
	local stars, levels = 0, 0
	for _, h in state.heroes.owned do
		stars += h.stars
		levels += (h.level or 1) - 1
	end
	return math.floor(math.sqrt(state.stats.totalGold) + buildings * 10 + stars * 40 + levels * 15 + state.stats.ascensions * 500 + state.stats.raidsWon * 15)
end

return E
