-- Subsolo: geração dos níveis, névoa, custos e a parte da economia que vem lá de baixo
-- (porte de src/core/underground.js). As ações (cavar, construir salas) ficam em Game.
local Util = require(script.Parent.Util)
local Map = require(script.Parent.Map)
local Data = require(script.Parent.Parent.Data.Underground)
local Buildings = require(script.Parent.Parent.Data.Buildings)

local U = {}

local GRID_W, GRID_H, idx = Map.GRID_W, Map.GRID_H, Map.idx
local DIRS8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function U.neighbors8(x, y)
	local out = {}
	for _, d in DIRS8 do
		if Map.inBounds(x + d[1], y + d[2]) then
			table.insert(out, { x + d[1], y + d[2] })
		end
	end
	return out
end

function U.isOpen(tile)
	local def = Data.UNDER_TILES[tile.t]
	return def ~= nil and def.open == true
end

function U.isWall(tile)
	local def = Data.UNDER_TILES[tile.t]
	return def ~= nil and def.wall == true
end

local function blob(tiles, rand, kind, size, allow)
	local x = Util.randInt(rand, 0, GRID_W - 1)
	local y = Util.randInt(rand, 0, GRID_H - 1)
	for _ = 1, size do
		if allow(tiles[idx(x, y)]) then
			tiles[idx(x, y)].t = kind
		end
		local d = DIRS8[math.floor(rand() * 4) + 1]
		x = math.min(GRID_W - 1, math.max(0, x + d[1]))
		y = math.min(GRID_H - 1, math.max(0, y + d[2]))
	end
end

-- Quantos aglomerados de cada tipo por nível: { quantidade, tamanho mínimo, máximo }.
local LAYOUT = {
	{ gold = { 3, 2, 4 }, water = { 2, 4, 7 } },
	{ gold = { 4, 2, 5 }, gem = { 2, 1, 3 }, cavern = { 2, 9, 15 }, water = { 1, 3, 5 } },
	{ gold = { 5, 3, 6 }, gem = { 3, 2, 4 }, cavern = { 1, 6, 10 }, magma = { 2, 5, 8 } },
}

function U.generateLevel(seed, d)
	local rand = Util.mulberry32(Util.u32(seed * 31 + d * 7919))
	local tiles = {}
	for i = 1, GRID_W * GRID_H do
		tiles[i] = { t = "rock", s = false }
	end
	local function allow(t) return t.t == "rock" end
	for _, kind in { "magma", "water", "cavern", "gold", "gem" } do
		local spec = LAYOUT[d][kind]
		if spec then
			for _ = 1, spec[1] do
				blob(tiles, rand, kind, Util.randInt(rand, spec[2], spec[3]), allow)
			end
		end
	end
	return { tiles = tiles }
end

function U.createUnder(seed)
	local levels = {}
	for d = 1, Data.DEPTHS do
		levels[d] = U.generateLevel(seed, d)
	end
	return { levels = levels, reached = 0 }
end

function U.levelOf(state, d)
	return state.under.levels[d]
end

-- Revela os 8 vizinhos de um espaço aberto. Ao encostar numa caverna, revela a caverna inteira.
-- Devolve quantos tiles de caverna apareceram.
function U.revealAround(level, x, y)
	local cavern = 0
	local stack = { { x, y } }
	local seenCave = {}
	local order = {}
	level.tiles[idx(x, y)].s = true
	while #stack > 0 do
		local c = table.remove(stack)
		for _, n in U.neighbors8(c[1], c[2]) do
			local i = idx(n[1], n[2])
			local t = level.tiles[i]
			t.s = true
			if t.t == "cavern" and not seenCave[i] then
				seenCave[i] = true
				table.insert(order, i)
				table.insert(stack, n)
			end
		end
	end
	for _, i in order do
		if not level.tiles[i].found then
			level.tiles[i].found = true
			cavern += 1
		end
	end
	return cavern
end

-- Abre um tile (entrada de escada): vira chão, ganha a marca da escada e revela os vizinhos.
function U.openAt(level, x, y, stairs)
	local t = level.tiles[idx(x, y)]
	if not U.isOpen(t) then
		t.t = "floor"
	end
	t.b = nil
	t.st = stairs
	return U.revealAround(level, x, y)
end

function U.dugCount(level)
	local n = 0
	for _, t in level.tiles do
		if t.t == "floor" then n += 1 end
	end
	return n
end

local function scale(cost, f)
	local out = {}
	for r, v in cost do
		out[r] = math.ceil(v * f)
	end
	return out
end

function U.digCost(state, d, mods)
	local f = Data.DIG_DEPTH_GROWTH ^ (d - 1) * Data.DIG_COUNT_GROWTH ^ U.dugCount(U.levelOf(state, d)) * (1 - (mods and mods.cost or 0))
	return scale(Data.DIG_BASE, f)
end

function U.digYield(kind, d)
	local list = Data.DIG_YIELD[kind]
	return list and list[d] or {}
end

function U.stairsCost(d)
	return Data.STAIRS_COST[d]
end

-- Dá para cavar se for rocha/veio e encostar (ortogonal) num espaço aberto.
function U.canReach(level, x, y)
	for _, n in Map.neighbors(x, y) do
		if U.isOpen(level.tiles[idx(n[1], n[2])]) then return true end
	end
	return false
end

function U.roomCount(state, id)
	local n = 0
	for _, lv in state.under.levels do
		for _, t in lv.tiles do
			if t.b and t.b.id == id then n += 1 end
		end
	end
	return n
end

function U.roomCost(state, id, mods)
	return scale(Data.ROOMS[id].cost, 1.15 ^ U.roomCount(state, id) * (1 - (mods and mods.cost or 0)))
end

function U.roomUpgradeCost(id, lvl, mods)
	local def = Data.ROOMS[id]
	if lvl >= def.maxLevel then return nil end
	return scale(def.cost, Buildings.LEVEL_COST_GROWTH ^ lvl * (1 - (mods and mods.cost or 0)))
end

local function roomLevelMult(lvl)
	return 1 + Buildings.LEVEL_OUTPUT_STEP * (lvl - 1)
end

-- Bônus de vizinhos de uma sala (hipotética ou construída) em (x, y) no nível.
function U.roomAdjacency(level, id, x, y)
	local def = Data.ROOMS[id]
	local total = 0
	local hasRequired = def.requiresAdj == nil
	local parts = {}
	local skipped = false
	for _, n in Map.neighbors(x, y) do
		local nt = level.tiles[idx(n[1], n[2])]
		local key = nt.b and nt.b.id or nt.t
		if def.requiresAdj and key == def.requiresAdj then hasRequired = true end
		local v = def.adj[key] or 0
		if v == 0 and def.adj.wall and U.isWall(nt) then v = def.adj.wall end
		-- Garimpo: o primeiro veio é o que faz funcionar; os seguintes dão bônus.
		if v ~= 0 and def.adjSkipFirst and key == def.requiresAdj and not skipped then
			skipped = true
			v = 0
		end
		if v ~= 0 then
			total += v
			table.insert(parts, { x = n[1], y = n[2], key = key, value = v })
		end
	end
	return { total = total, parts = parts, hasRequired = hasRequired }
end

-- Modificadores globais que vêm do subsolo (somados em collectModifiers).
function U.underMods(state)
	local m = { prodAll = 0, food = 0 }
	if not state.under then return m end
	for d = 1, Data.DEPTHS do
		local lv = U.levelOf(state, d)
		for i, t in lv.tiles do
			if t.b then
				local def = Data.ROOMS[t.b.id]
				local x, y = Map.xy(i)
				if def.prodAll and U.roomAdjacency(lv, t.b.id, x, y).hasRequired then
					m.prodAll += def.prodAll * t.b.lvl
				end
				if def.foodBonus then
					m.food += def.foodBonus * t.b.lvl
				end
			end
		end
	end
	return m
end

-- Produção e armazenamento das salas. `mult(r)` = multiplicador global do recurso.
function U.underEconomy(state, mult)
	local gross = { gold = 0, food = 0, wood = 0, stone = 0 }
	local caps = {}
	local levels = {}
	if not state.under then return { gross = gross, caps = caps, levels = levels } end
	for d = 1, Data.DEPTHS do
		local lv = U.levelOf(state, d)
		local infos = {}
		for i, t in lv.tiles do
			if t.b then
				local def = Data.ROOMS[t.b.id]
				local x, y = Map.xy(i)
				local adj = U.roomAdjacency(lv, t.b.id, x, y)
				local info = { id = t.b.id, lvl = t.b.lvl, active = adj.hasRequired, adjBonus = adj.total, adjParts = adj.parts, out = {} }
				local eff = adj.hasRequired and (1 + adj.total) * roomLevelMult(t.b.lvl) or 0
				for r, base in def.prod or {} do
					info.out[r] = base * eff * mult(r)
					gross[r] += info.out[r]
				end
				for r, v in def.storage or {} do
					caps[r] = (caps[r] or 0) + v * t.b.lvl * t.b.lvl
				end
				infos[i] = info
			end
		end
		levels[d] = infos
	end
	return { gross = gross, caps = caps, levels = levels }
end

return U
