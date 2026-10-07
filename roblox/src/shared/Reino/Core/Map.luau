-- Mapa: grade 12x12 com anéis concêntricos de terra desbloqueável (porte de src/core/map.js).
-- Coordenadas x, y começam em 0 como no jogo web; a lista de tiles começa em 1 (idx já soma 1).
local Util = require(script.Parent.Util)

local M = {}

M.GRID_W = 12
M.GRID_H = 12
M.START_RING = 2
M.MAX_RING = 5

M.RING_COSTS = {
	[3] = { gold = 2000, wood = 400 },
	[4] = { gold = 60000, stone = 4000 },
	[5] = { gold = 1000000, stone = 50000 },
}

function M.idx(x, y)
	return y * M.GRID_W + x + 1
end

-- Posição (x, y) de um índice da lista de tiles.
function M.xy(i)
	return (i - 1) % M.GRID_W, math.floor((i - 1) / M.GRID_W)
end

function M.inBounds(x, y)
	return x >= 0 and y >= 0 and x < M.GRID_W and y < M.GRID_H
end

function M.ringOf(x, y)
	local cx = (M.GRID_W - 1) / 2
	local cy = (M.GRID_H - 1) / 2
	return math.max(math.abs(x - cx), math.abs(y - cy)) - 0.5
end

function M.isUnlocked(grid, x, y)
	return M.ringOf(x, y) <= grid.ring
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
M.DIRS = DIRS

function M.neighbors(x, y)
	local out = {}
	for _, d in DIRS do
		local nx, ny = x + d[1], y + d[2]
		if M.inBounds(nx, ny) then
			table.insert(out, { nx, ny })
		end
	end
	return out
end

-- Muralha que se liga sozinha. Bits: 1 = norte, 2 = leste, 4 = sul, 8 = oeste.
local WALL_LINKS = { muralha = true, torre = true }
function M.wallMask(grid, x, y)
	local function linked(nx, ny)
		if not M.inBounds(nx, ny) then return false end
		local b = grid.tiles[M.idx(nx, ny)].b
		return b ~= nil and WALL_LINKS[b.id] == true
	end
	return (linked(x, y - 1) and 1 or 0) + (linked(x + 1, y) and 2 or 0) + (linked(x, y + 1) and 4 or 0) + (linked(x - 1, y) and 8 or 0)
end

-- Chave de adjacência de um tile: id da construção se houver, senão o terreno.
function M.adjKey(tile)
	return tile.b and tile.b.id or tile.t
end

local function cluster(tiles, rand, kind, size, startX, startY, allow)
	local x, y = startX, startY
	for _ = 1, size do
		if M.inBounds(x, y) and allow(x, y) then
			tiles[M.idx(x, y)].t = kind
		end
		local d = DIRS[math.floor(rand() * 4) + 1]
		x = math.min(M.GRID_W - 1, math.max(0, x + d[1]))
		y = math.min(M.GRID_H - 1, math.max(0, y + d[2]))
	end
end

function M.generateMap(seed)
	local rand = Util.mulberry32(seed)
	local randInt = Util.randInt
	local tiles = {}
	for i = 1, M.GRID_W * M.GRID_H do
		tiles[i] = { t = "grass" }
	end
	local function isCenter(x, y) return M.ringOf(x, y) <= 0 end
	local function notCenter(x, y) return not isCenter(x, y) end

	-- Rio serpenteando pela borda (anéis externos)
	local vertical = rand() < 0.5
	local pos = rand() < 0.5 and 0 or 1
	for i = 0, M.GRID_W - 1 do
		local x = vertical and pos or i
		local y = vertical and i or pos
		tiles[M.idx(x, y)].t = "water"
		if rand() < 0.3 then
			pos = math.min(1, math.max(0, pos + (rand() < 0.5 and -1 or 1)))
		end
	end

	-- Lago perto do centro
	cluster(tiles, rand, "water", 3, randInt(rand, 3, 8), randInt(rand, 3, 8), function(x, y)
		return notCenter(x, y) and M.ringOf(x, y) <= 2
	end)

	-- Florestas, rochas, montanhas
	for _ = 1, 6 do
		cluster(tiles, rand, "forest", randInt(rand, 3, 7), randInt(rand, 0, 11), randInt(rand, 0, 11), notCenter)
	end
	for _ = 1, 4 do
		cluster(tiles, rand, "rock", randInt(rand, 2, 4), randInt(rand, 0, 11), randInt(rand, 0, 11), notCenter)
	end
	for _ = 1, 3 do
		local side = randInt(rand, 0, 3)
		local a = randInt(rand, 1, 10)
		local starts = { { a, 11 }, { a, 0 }, { 0, a }, { 11, a } }
		local st = starts[side + 1]
		cluster(tiles, rand, "mountain", randInt(rand, 3, 5), st[1], st[2], function(x, y) return M.ringOf(x, y) >= 3 end)
	end

	-- Garantias do anel inicial: florestas, rochas e água; e montanhas no anel 3.
	local function ensure(kind, count, ringMin, ringMax)
		local cells = {}
		for y = 0, M.GRID_H - 1 do
			for x = 0, M.GRID_W - 1 do
				local r = M.ringOf(x, y)
				if r >= ringMin and r <= ringMax and not isCenter(x, y) then
					table.insert(cells, { x, y })
				end
			end
		end
		local have = 0
		local free = {}
		for _, c in cells do
			local t = tiles[M.idx(c[1], c[2])].t
			if t == kind then have += 1 end
			if t == "grass" then table.insert(free, c) end
		end
		while have < count and #free > 0 do
			local c = table.remove(free, math.floor(rand() * #free) + 1)
			tiles[M.idx(c[1], c[2])].t = kind
			have += 1
		end
	end
	ensure("forest", 3, 1, 2)
	ensure("rock", 2, 1, 2)
	ensure("water", 1, 1, 2)
	ensure("mountain", 2, 3, 3)

	-- Prédios iniciais: casa + fazenda no centro
	tiles[M.idx(5, 5)].b = { id = "casa", lvl = 1 }
	tiles[M.idx(6, 5)].b = { id = "fazenda", lvl = 1 }

	return { w = M.GRID_W, h = M.GRID_H, ring = M.START_RING, tiles = tiles }
end

return M
