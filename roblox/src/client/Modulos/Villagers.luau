-- Vida da vila: moradores com profissão e rotina, desenhados sobre o mapa (porte de src/ui/villagers.js).
-- Só visual: lê o estado e a economia (moradores, vagas por prédio) e nunca os altera.
--
-- - Quem trabalha onde segue a mesma regra do motor (Economy): fazendas e moinhos são ocupados
--   primeiro; o resto vai para os outros prédios. Quem sobra sem emprego dorme na rua.
-- - Cada profissão tem uma rotina de paradas (ex.: lavrador colhe na fazenda e leva comida ao armazém).
--   A rotina é refeita a cada volta, então reage a prédios novos, demolidos e à horda anunciada.
-- - Passeios: de vez em quando um trabalhador sai da rotina e vai até um ponto de encontro ou até a beira da água
--   ou da floresta. Além deles, alguns moradores de folga só passeiam. Quem para no mesmo lugar conversa.
-- - O caminho é uma busca em largura pela grama livre; se não houver, atravessa o que der.
--
-- Índices de célula começam em 0 como no web (i = y * 12 + x); a lista de tiles do Luau começa em 1 (tiles[i + 1]).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reino = ReplicatedStorage:WaitForChild("Reino")
local Map = require(Reino.Core.Map)
local Buildings = require(Reino.Data.Buildings)
local S = require(script.Parent.MapSprites)
local D = require(script.Parent.MapDraw)

local BUILDINGS = Buildings.BUILDINGS
local GRID_W, GRID_H = Map.GRID_W, Map.GRID_H
local isUnlocked, neighbors = Map.isUnlocked, Map.neighbors
local PROFESSIONS, SLEEPER_SPRITES = S.PROFESSIONS, S.SLEEPER_SPRITES

local STROLLER_SPRITES = {}
do
	local seen = {}
	for _, id in S.PROFESSION_ORDER do
		local spr = PROFESSIONS[id].sprite
		if not seen[spr] then
			seen[spr] = true
			table.insert(STROLLER_SPRITES, spr)
		end
	end
end

local MAX_WORKERS = 32 -- moradores trabalhando visíveis ao mesmo tempo
local MAX_SLEEPERS = 8
local MAX_STROLLERS = 8 -- moradores de folga passeando
local STROLL_CHANCE = 0.35 -- chance de um trabalhador passear ao fim de cada volta
local CHAT_DIST = 1.1 -- tiles: dois moradores parados a essa distância num ponto de encontro conversam
local SOCIAL = { "mercado", "taverna", "templo", "jardim", "fogueira", "estatua", "quartel" }
local SPEED = 1.2 -- tiles por segundo
-- O andar é liso, recalculado a cada quadro. A pose e a rotina avançam em passinhos de STEP segundos.
local STEP = 0.2
local MAX_DT = 0.25 -- volta de segundo plano não "teleporta" ninguém
local SYNC_MS = 1000
local REST_EVERY = 3 -- voltas de trabalho antes de descansar em casa
local PRODUCERS = { fazenda = "food", cais = "food", moinho = "food", serraria = "wood", pedreira = "stone", mina = "gold" }
local PRODUCER_IDS = { "fazenda", "cais", "moinho", "serraria", "pedreira", "mina" }

local function isFood(id)
	local def = BUILDINGS[id]
	return def ~= nil and def.prod ~= nil and (def.prod.food or 0) ~= 0
end
local function rand(a, b)
	return a + math.random() * (b - a)
end
local function pickOne(arr)
	return arr[math.floor(math.random() * #arr) + 1]
end
local function includes(list, v)
	return table.find(list, v) ~= nil
end
local function idx0(x, y)
	return y * GRID_W + x
end
local function tileAt(grid, i)
	return grid.tiles[i + 1]
end

-- ================================================================ grade e caminhos
local function cellCenter(i)
	return { x = (i % GRID_W) + 0.5, y = math.floor(i / GRID_W) + 0.5 }
end

local function buildingsOf(grid, ids)
	local out = {}
	for k, t in grid.tiles do
		if t.b and includes(ids, t.b.id) then
			table.insert(out, k - 1)
		end
	end
	return out
end

local function nearestBuilding(grid, ids, from)
	local fx = from % GRID_W
	local fy = math.floor(from / GRID_W)
	local best, bestD = nil, math.huge
	for _, i in buildingsOf(grid, ids) do
		if i ~= from then
			local d = math.abs((i % GRID_W) - fx) + math.abs(math.floor(i / GRID_W) - fy)
			if d < bestD then
				bestD = d
				best = i
			end
		end
	end
	return best
end

local function adjacentTerrain(grid, at, types)
	local options = {}
	for _, n in neighbors(at % GRID_W, math.floor(at / GRID_W)) do
		if isUnlocked(grid, n[1], n[2]) and includes(types, tileAt(grid, idx0(n[1], n[2])).t) then
			table.insert(options, n)
		end
	end
	if #options == 0 then
		return nil
	end
	local n = pickOne(options)
	return idx0(n[1], n[2])
end

-- Grama livre conquistada, sorteada (para morador de folga sem casa).
local function randomGrass(grid)
	local cells = {}
	for k, t in grid.tiles do
		local i = k - 1
		if not t.b and t.t == "grass" and isUnlocked(grid, i % GRID_W, math.floor(i / GRID_W)) then
			table.insert(cells, i)
		end
	end
	return #cells > 0 and pickOne(cells) or nil
end

-- Destino de passeio: um ponto de encontro (mais provável) ou a grama na beira da água ou da floresta.
-- Evita o que está colado em quem sai, para o passeio atravessar o mapa.
local function strollTarget(grid, from)
	local social = buildingsOf(grid, SOCIAL)
	local scenic = {}
	for k, t in grid.tiles do
		local i = k - 1
		local x, y = i % GRID_W, math.floor(i / GRID_W)
		if not t.b and t.t == "grass" and isUnlocked(grid, x, y) then
			for _, n in neighbors(x, y) do
				local nt = tileAt(grid, idx0(n[1], n[2])).t
				if nt == "water" or nt == "forest" then
					table.insert(scenic, i)
					break
				end
			end
		end
	end
	local pool
	if #social > 0 and (math.random() < 0.6 or #scenic == 0) then
		pool = social
	elseif #scenic > 0 then
		pool = scenic
	end
	if not pool then
		return randomGrass(grid)
	end
	local far = {}
	for _, i in pool do
		if from == nil or math.abs((i % GRID_W) - (from % GRID_W)) + math.abs(math.floor(i / GRID_W) - math.floor(from / GRID_W)) >= 3 then
			table.insert(far, i)
		end
	end
	return pickOne(#far > 0 and far or pool)
end

-- Ponto na borda da área conquistada, do lado de onde vem a horda.
local function raidEdge(grid, dir)
	local lo = math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5)
	local hi = GRID_W - 1 - lo
	local along = math.floor(rand(lo + 1, hi - 1) + 0.5)
	local x, y
	if dir == "s" then
		x, y = along, hi
	elseif dir == "w" then
		x, y = lo, along
	elseif dir == "e" then
		x, y = hi, along
	else
		x, y = along, lo
	end
	return idx0(x, y)
end

local function bfs(grid, start, goal, passable)
	if start == goal then
		return { start }
	end
	local n = #grid.tiles
	local prev = table.create(n, -1)
	prev[start + 1] = start
	local queue = { start }
	local q = 1
	while q <= #queue do
		local cur = queue[q]
		q += 1
		for _, nb in neighbors(cur % GRID_W, math.floor(cur / GRID_W)) do
			local ni = idx0(nb[1], nb[2])
			if prev[ni + 1] == -1 and isUnlocked(grid, nb[1], nb[2]) and (ni == goal or passable(ni)) then
				prev[ni + 1] = cur
				if ni == goal then
					local path = { ni }
					local c = cur
					while c ~= start do
						table.insert(path, c)
						c = prev[c + 1]
					end
					table.insert(path, start)
					-- inverte
					local out = table.create(#path)
					for k = #path, 1, -1 do
						table.insert(out, path[k])
					end
					return out
				end
				table.insert(queue, ni)
			end
		end
	end
	return nil
end

-- Busca em largura do tile atual até `goal`. Primeiro só pela grama livre; se não houver caminho,
-- por qualquer chão conquistado que não seja água ou montanha; por fim, em linha reta.
local function route(grid, from, goal)
	local start = idx0(math.max(0, math.min(GRID_W - 1, math.floor(from.x))), math.max(0, math.min(GRID_H - 1, math.floor(from.y))))
	local function strict(i)
		local t = tileAt(grid, i)
		return not t.b and t.t == "grass"
	end
	local function loose(i)
		local t = tileAt(grid, i)
		return t.t ~= "water" and t.t ~= "mountain"
	end
	local cells = bfs(grid, start, goal, strict) or bfs(grid, start, goal, loose) or { start, goal }
	local pts = {}
	for k = 2, #cells do
		local c = cellCenter(cells[k])
		table.insert(pts, { x = c.x + rand(-0.12, 0.12), y = c.y + rand(-0.12, 0.12) })
	end
	-- Para na "porta": um pouco antes do centro do destino, do lado de onde veio.
	local prev = #cells > 1 and cellCenter(cells[#cells - 1]) or from
	local g = cellCenter(goal)
	local dx, dy = prev.x - g.x, prev.y - g.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d == 0 then
		d = 1
	end
	local door = { x = g.x + (dx / d) * 0.3, y = g.y + (dy / d) * 0.3 }
	if #pts > 0 then
		pts[#pts] = door
	else
		table.insert(pts, door)
	end
	return pts
end

-- ================================================================ vida da vila
local V = {}
V.__index = V

function V.new()
	return setmetatable({
		people = {}, -- chave estável -> morador
		order = {}, -- chaves na ordem de inserção (o Map do JS)
		lastSync = 0,
		lastTime = 0,
		stateKey = nil,
		acc = 0,
		seq = 0,
	}, V)
end

function V:clear()
	self.people = {}
	self.order = {}
end

-- Lugares na rua para quem não tem emprego: grama livre encostada nas casas (depois, qualquer grama).
function V:sleepSpots(grid, houses, n)
	if n <= 0 then
		return {}
	end
	local near, other = {}, {}
	local isHouse = {}
	for _, h in houses do
		isHouse[h] = true
	end
	for k, t in grid.tiles do
		local i = k - 1
		local x, y = i % GRID_W, math.floor(i / GRID_W)
		if not t.b and t.t == "grass" and isUnlocked(grid, x, y) then
			local byHouse = false
			for _, nb in neighbors(x, y) do
				if isHouse[idx0(nb[1], nb[2])] then
					byHouse = true
					break
				end
			end
			table.insert(byHouse and near or other, i)
		end
	end
	local cells = near
	for _, i in other do
		table.insert(cells, i)
	end
	local out = {}
	local k = 0
	while k < n and #cells > 0 do
		local i = cells[(math.floor(k / 2) % #cells) + 1] -- até 2 por tile, lado a lado
		table.insert(out, { x = (i % GRID_W) + (k % 2 == 1 and 0.66 or 0.34), y = math.floor(i / GRID_W) + 0.55 })
		k += 1
	end
	return out
end

-- ---------------------------------------------------------------- quem existe
function V:sync(game)
	local s = game.state
	local econ = game.econ
	local grid = s.grid
	local houses, jobs = {}, {}
	for k, t in grid.tiles do
		if t.b then
			local i = k - 1
			if t.b.id == "casa" then
				table.insert(houses, i)
			end
			local info = econ and econ.tiles[k]
			if info and info.workers > 0 and info.active ~= false and PROFESSIONS[t.b.id] then
				table.insert(jobs, { i = i, id = t.b.id, need = info.workers })
			end
		end
	end
	-- Mesma prioridade do motor: quem produz comida é ocupado primeiro.
	table.sort(jobs, function(a, b)
		local fa, fb = isFood(a.id) and 1 or 0, isFood(b.id) and 1 or 0
		if fa ~= fb then
			return fa > fb
		end
		return a.i < b.i
	end)
	local pop = math.floor(s.pop)
	local free = pop
	for _, j in jobs do
		j.filled = math.min(j.need, free)
		free -= j.filled
	end
	local employed = pop - free

	-- Até 2 visíveis por prédio; com muitos prédios, primeiro 1 em cada, depois o 2º.
	local want, wantOrder = {}, {}
	local function put(key, w)
		if not want[key] then
			table.insert(wantOrder, key)
		end
		want[key] = w
	end
	local budget = MAX_WORKERS
	for round = 0, 1 do
		for _, j in jobs do
			if budget > 0 and j.filled > round then
				local key = "w:" .. j.i .. ":" .. j.id .. ":" .. round
				put(key, { kind = "work", job = j.id, at = j.i, home = #houses > 0 and houses[(#wantOrder % #houses) + 1] or j.i })
				budget -= 1
			end
		end
	end
	-- De folga: 1 a cada 4 moradores, mais 1 a cada 3 trabalhadores que não aparecem no próprio prédio (até 8).
	local strollers = math.min(MAX_STROLLERS, math.floor(pop / 4) + math.floor(math.max(0, employed - #wantOrder) / 3))
	for k = 0, strollers - 1 do
		put("s:" .. k, {
			kind = "work",
			job = "passeio",
			at = #houses > 0 and houses[(k % #houses) + 1] or nil,
			home = #houses > 0 and houses[((k + 1) % #houses) + 1] or nil,
		})
	end
	local sleepers = math.min(MAX_SLEEPERS, math.max(0, pop - employed))
	local spots = self:sleepSpots(grid, houses, sleepers)
	for k = 0, #spots - 1 do
		put("z:" .. k, { kind = "sleep", spot = spots[k + 1], sprite = SLEEPER_SPRITES[(k % #SLEEPER_SPRITES) + 1] })
	end

	-- Some quem não é mais necessário (mantendo a ordem de inserção dos que ficam).
	local keep = {}
	for _, key in self.order do
		if want[key] and self.people[key] then
			table.insert(keep, key)
		else
			self.people[key] = nil
		end
	end
	self.order = keep
	for _, key in wantOrder do
		local w = want[key]
		local p = self.people[key]
		if p then
			if w.kind == "work" then
				p.home = w.home
			else
				p.x, p.y = w.spot.x, w.spot.y
			end
		elseif w.kind == "sleep" then
			self.seq += 1
			self.people[key] = { kind = "sleep", x = w.spot.x, y = w.spot.y, sprite = w.sprite, seed = math.random() * 10, seq = self.seq }
			table.insert(self.order, key)
		else
			local origin = w.home or w.at or randomGrass(grid)
			if origin ~= nil then
				local start = cellCenter(origin)
				local prof = PROFESSIONS[w.job]
				self.seq += 1
				self.people[key] = {
					kind = "work", job = w.job, at = w.at or origin, home = w.home or origin,
					sprite = prof and prof.sprite or pickOne(STROLLER_SPRITES), tool = prof and prof.tool,
					x = start.x + rand(-0.15, 0.15), y = start.y + 0.3, path = {}, stops = {}, stop = 0, wait = rand(0, 1.2), state = "wait",
					carry = nil, cycles = math.floor(rand(0, REST_EVERY)), hidden = false, flip = false,
					pose = math.random() < 0.5 and 1 or 0, seedChat = math.floor(rand(0, 3)), seq = self.seq,
				}
				table.insert(self.order, key)
			end
		end
	end
end

-- ---------------------------------------------------------------- rotinas
-- Cada parada: { cell, dur, tool?, carry?, social?, rest? } — carry é o que vai na mão a caminho daquela parada.
function V:plan(p, game)
	local s = game.state
	local grid = s.grid
	local w = p.at
	local function nearest(ids, from)
		return nearestBuilding(grid, ids, from or w)
	end
	local function store(from)
		return nearest({ "armazem" }, from)
	end
	local function adjacent(types)
		return adjacentTerrain(grid, w, types)
	end
	local function anyOf(ids)
		local all = buildingsOf(grid, ids)
		return #all > 0 and pickOne(all) or nil
	end
	local stops = {}
	local function add(cell, dur, extra)
		if cell ~= nil then
			local st = { cell = cell, dur = dur }
			if extra then
				for k, v in extra do
					st[k] = v
				end
			end
			table.insert(stops, st)
		end
	end
	local job = p.job
	if job == "fazenda" then
		add(w, rand(3, 4.5), { tool = "clear" })
		local dest = nearest({ "armazem", "moinho", "mercado" })
		if dest == nil then
			dest = p.home
		end
		add(dest, 0.8, { carry = "food" })
	elseif job == "cais" then
		add(w, rand(4, 6)) -- pescando na ponta do cais
		local dest = store()
		if dest == nil then
			dest = nearest({ "mercado" })
		end
		if dest == nil then
			dest = p.home
		end
		add(dest, 0.8, { carry = "food" })
	elseif job == "serraria" then
		add(adjacent({ "forest" }) or w, rand(2.5, 3.5), { tool = "hero-woodcutter" })
		add(w, 1.2, { carry = "wood" })
		add(store(), 0.8, { carry = "wood" })
	elseif job == "pedreira" or job == "mina" then
		local res = PRODUCERS[job]
		add(adjacent(job == "mina" and { "mountain" } or { "rock", "mountain" }) or w, rand(2.5, 3.5), { tool = "tool-pickaxe" })
		add(w, 1, { carry = res })
		add(store(), 0.8, { carry = res })
	elseif job == "moinho" then
		add(nearest({ "fazenda" }) or w, 1.2)
		add(w, rand(2.5, 3.5), { carry = "food" })
		add(store(), 0.8, { carry = "food" })
	elseif job == "mercado" then
		add(nearest({ "armazem", "fazenda", "moinho" }) or w, 1)
		add(w, rand(2.5, 3.5), { carry = "food" })
		add(anyOf({ "casa" }), 0.8, { carry = "gold" })
	elseif job == "armazem" then
		local src = anyOf(PRODUCER_IDS)
		add(src or w, 1)
		add(w, 1.5, { carry = src ~= nil and PRODUCERS[tileAt(grid, src).b.id] or nil })
	elseif job == "taverna" then
		add(w, rand(3, 5))
		add(anyOf({ "casa" }), 1)
	elseif job == "torre" or job == "quartel" then
		add(w, rand(3, 5))
		-- Com a horda anunciada, o guarda corre para a borda de onde ela vem.
		local dest
		if s.raid and s.raid.warned then
			dest = raidEdge(grid, s.raid.dir)
		else
			dest = anyOf({ "torre", "muralha" })
			if dest == nil then
				dest = w
			end
		end
		add(dest, 2)
	elseif job == "templo" then
		add(w, rand(4, 6))
		add(anyOf({ "jardim", "fogueira", "estatua", "casa" }), 1.5)
	elseif job == "passeio" then
		-- Morador de folga: dois pontos quaisquer do mapa, sem ferramenta.
		add(strollTarget(grid, w), rand(2, 4), { social = true })
		add(strollTarget(grid, w), rand(2, 4), { social = true })
	else
		add(w, 3)
	end
	if job ~= "passeio" and math.random() < STROLL_CHANCE then
		add(strollTarget(grid, w), rand(1.5, 3), { social = true })
	end
	p.cycles += 1
	if p.cycles % REST_EVERY == 0 and p.home ~= w then
		add(p.home, rand(3, 5), { rest = true })
	end
	p.stops = stops
	p.stop = -1
end

-- Próxima parada: traça o caminho e começa a andar. (p.stop começa em 0 como no JS; stops[p.stop + 1].)
function V:next(p, game)
	p.stop += 1
	if p.stop >= #p.stops then
		self:plan(p, game)
		p.stop = 0
	end
	local st = p.stops[p.stop + 1]
	if not st then
		p.state = "wait"
		p.wait = 1
		return
	end
	p.carry = st.carry
	p.hidden = false
	p.path = route(game.state.grid, { x = p.x, y = p.y }, st.cell)
	p.state = "walk"
end

-- ---------------------------------------------------------------- tempo
-- now = relógio monotônico em ms (performance.now do web).
function V:update(game, now)
	local dt = math.max(0, (now - (self.lastTime ~= 0 and self.lastTime or now)) / 1000)
	self.lastTime = now
	-- Reino novo ou ascendido. (No Roblox o estado é recriado a cada envio do servidor: compara a semente e o início.)
	local s = game.state
	local key = tostring(s.seed) .. ":" .. tostring(s.runStartedAt)
	if key ~= self.stateKey then
		self.stateKey = key
		self:clear()
		self.lastSync = 0
	end
	if now - self.lastSync > SYNC_MS then
		self.lastSync = now
		self:sync(game)
	end
	self:walk(math.min(dt, MAX_DT))
	-- Poses e rotina em passinhos fixos; no máximo 2 de uma vez.
	self.acc = math.min(self.acc + dt, STEP * 2)
	while self.acc >= STEP do
		self.acc -= STEP
		self:step(game, STEP)
	end
end

-- Anda pelo caminho, a cada quadro; a sobra de um trecho já segue para o próximo.
function V:walk(dt)
	for _, key in self.order do
		local p = self.people[key]
		if p.kind == "work" and p.state == "walk" then
			local left = SPEED * dt
			while left > 0 and #p.path > 0 do
				local tgt = p.path[1]
				local dx, dy = tgt.x - p.x, tgt.y - p.y
				local d = math.sqrt(dx * dx + dy * dy)
				if math.abs(dx) > 0.01 then
					p.flip = dx < 0
				end
				if d <= left then
					p.x, p.y = tgt.x, tgt.y
					table.remove(p.path, 1)
					left -= d
				else
					p.x += (dx / d) * left
					p.y += (dy / d) * left
					left = 0
				end
			end
			if #p.path == 0 then
				local st = p.stops[p.stop + 1]
				p.state = "act"
				p.wait = st and st.dur or 1
				if st and st.rest then
					p.hidden = true -- entrou em casa
				end
			end
		end
	end
end

function V:step(game, dt)
	for _, key in table.clone(self.order) do
		local p = self.people[key]
		if p and p.kind == "work" then
			if p.state == "walk" then
				p.pose = 1 - p.pose
			else
				p.wait -= dt
				p.pose = 1 - p.pose
				if p.wait <= 0 then
					self:next(p, game)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- desenho
local SHADOW = Color3.new(0, 0, 0)
local BUBBLE = Color3.fromRGB(255, 253, 248)
local BUBBLE_LINE = Color3.fromRGB(43, 42, 51)
local DOT = Color3.fromHex("#2b2a33")
local Z_LINE = Color3.fromRGB(30, 30, 50)

-- Quem está parado num ponto de encontro com outro morador por perto.
local function chatting(list)
	local idle = {}
	for _, p in list do
		if p.kind == "work" and p.state == "act" then
			local st = p.stops[p.stop + 1]
			if st and st.social then
				table.insert(idle, p)
			end
		end
	end
	local out = {}
	for a = 1, #idle do
		for b = a + 1, #idle do
			local dx, dy = idle[a].x - idle[b].x, idle[a].y - idle[b].y
			if math.sqrt(dx * dx + dy * dy) <= CHAT_DIST then
				out[idle[a]] = true
				out[idle[b]] = true
			end
		end
	end
	return out
end

-- Balão de conversa com reticências que aparecem uma a uma (uma a cada 0,4 s).
local function drawChat(L, p, now, cx, cy, T)
	local w = T * 0.34
	local h = T * 0.2
	local x = cx - w / 2 + (p.flip and -T * 0.08 or T * 0.08)
	local y = cy - h
	L:rect(x, y, w, h, BUBBLE, 0.95, h / 2, BUBBLE_LINE, 0.55, 1.5)
	-- rabinho do balão: um losango pequeno com a metade de cima escondida no balão (o canvas usa um triângulo)
	local d = T * 0.045
	L:rect(cx - d * 0.7, y + h + T * 0.06 - d * 0.7 - d, d * 1.4, d * 1.4, BUBBLE, 0.95, 0, nil, nil, nil, 45)
	local dots = 1 + (math.floor(now / 400 + p.seedChat) % 3)
	for k = 0, dots - 1 do
		L:circle(x + w * (0.28 + k * 0.22), y + h / 2, T * 0.022, DOT, 1)
	end
end

local function drawSleeper(L, p, now, cx, cy, size, T)
	-- deitado: girado -90 graus em volta de (cx, cy + size * 0,1)
	local ccx, ccy = cx, cy + size * 0.1
	L:img(p.sprite, ccx - size / 2, ccy - size / 2, size, size, 0.92, nil, -90, false)
	-- "z z z" subindo, cada um com um atraso
	local fs = math.max(9, T * 0.16)
	for k = 0, 2 do
		local t = (now / 1600 + p.seed + k / 3) % 1
		local zx = cx + size * 0.25 + t * size * 0.35
		local zy = cy - size * 0.15 - t * size * 0.9
		L:text(zx, zy, "z", D.WHITE, fs, math.sin(t * math.pi), Z_LINE, 0.55, 1.25)
	end
end

-- Desenha os moradores na camada L (MapDraw), ordenados de cima para baixo.
function V:draw(L, now, T)
	local list = {}
	for _, key in self.order do
		local p = self.people[key]
		if not p.hidden then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.seq < b.seq -- sort estável como no JS
	end)
	local size = T * 0.66
	local chat = chatting(list)
	for _, p in list do
		local cx = p.x * T
		local cy = p.y * T
		-- sombra (elipse)
		local rx, ry = size * (p.kind == "sleep" and 0.42 or 0.26), size * 0.1
		L:img("ui/disc", cx - rx, cy + size * 0.36 - ry, rx * 2, ry * 2, 0.22, SHADOW)
		if p.kind == "sleep" then
			drawSleeper(L, p, now, cx, cy, size, T)
		else
			local walking = p.state == "walk"
			local st = p.stops[p.stop + 1]
			local working = p.state == "act" and st and st.tool
			-- duas poses por ação, trocadas a cada passinho
			local bob = 0
			if p.pose == 1 then
				bob = walking and -T * 0.04 or (working and -T * 0.025 or 0)
			end
			local by = cy + bob
			L:img(p.sprite, cx - size / 2, by - size / 2, size, size, 1, nil, 0, p.flip)
			if working then
				-- ferramenta balançando na mão: pivô (0,3; -0,02) do sprite, girada -0,9 (levantada) ou 0,55 (batendo)
				local a = p.pose == 1 and -0.9 or 0.55
				local f = p.flip and -1 or 1
				local vx, vy = size * 0.15, -size * 0.21 -- centro do ícone em relação ao pivô
				local ca, sa = math.cos(a), math.sin(a)
				local lx = size * 0.3 + vx * ca - vy * sa
				local ly = -size * 0.02 + vx * sa + vy * ca
				local s = size * 0.42
				L:img("ico/" .. st.tool, cx + f * lx - s / 2, by + ly - s / 2, s, s, 1, S.TOOL_COLOR, f * math.deg(a), p.flip)
			end
			if p.carry and walking then
				local s = size * 0.42
				L:img("ico/" .. p.carry, cx - s / 2, by - size * 0.62 - s / 2, s, s, 1, S.RES_COLORS[p.carry])
			end
			if chat[p] then
				drawChat(L, p, now, cx, cy - size * 0.55, T)
			end
		end
	end
end

return V
