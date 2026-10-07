-- Game: orquestra estado + sistemas (porte de src/core/game.js). A interface só conversa com esta classe.
-- Toda ação retorna { ok, reason? } e emite eventos para a interface (aviso, som).
-- No Roblox cada jogador tem o seu Game, que vive no servidor (o cliente só pede ações).
local Util = require(script.Parent.Util)
local Map = require(script.Parent.Map)
local Economy = require(script.Parent.Economy)
local State = require(script.Parent.State)
local Season = require(script.Parent.Season)
local Heroes = require(script.Parent.Heroes)
local Social = require(script.Parent.Social)
local Under = require(script.Parent.Underground)
local Data = script.Parent.Parent.Data
local Buildings = require(Data.Buildings)
local HeroData = require(Data.Heroes)
local Talents = require(Data.Talents)
local Events = require(Data.Events)
local Seasons = require(Data.Seasons)
local Achievements = require(Data.Achievements)
local Cosmetics = require(Data.Cosmetics)
local UnderData = require(Data.Underground)

local BUILDINGS, TERRAIN = Buildings.BUILDINGS, Buildings.TERRAIN
local HERO_BY_ID = HeroData.HERO_BY_ID
local computeEconomy, canAfford, pay, refund = Economy.computeEconomy, Economy.canAfford, Economy.pay, Economy.refund
local PROD_RES = Economy.PROD_RES
local GRID_W, idx = Map.GRID_W, Map.idx

local Game = {}
Game.__index = Game

Game.OFFLINE_THRESHOLD = 30 -- s sem tick = sessão offline
Game.BASE_OFFLINE_HOURS = 4
Game.BASE_OFFLINE_EFF = 0.6
Game.UNDO_WINDOW = 5000

local function countBuilt(s)
	local n = 0
	for _, t in s.grid.tiles do
		if t.b then n += 1 end
	end
	return n
end

-- `focus` diz à interface o que destacar (prédio na paleta ou aba).
Game.TUTORIAL = {
	{ text = "Construa uma Serraria encostada numa floresta: cada floresta vizinha dá +40% de madeira.", focus = { build = "serraria" }, done = function(s) return Economy.countOf(s, "serraria") >= 1 end, reward = { gold = 50 } },
	{ text = "Construa mais uma Casa: mais moradores, mais gente para trabalhar.", focus = { build = "casa" }, done = function(s) return Economy.countOf(s, "casa") >= 2 end, reward = { gold = 60, wood = 20 } },
	{ text = "Abriu a aba Heróis: use o pergaminho grátis para recrutar seu primeiro herói.", focus = { tab = "herois" }, done = function(s) return Util.count(s.heroes.owned) >= 1 end, reward = { gold = 80 } },
	{ text = "Hordas atacam a cada poucos minutos, sempre por um lado do mapa. Construa uma Muralha ou Torre desse lado.", focus = { build = "muralha" }, done = function(s) return Economy.countOf(s, "muralha") + Economy.countOf(s, "torre") >= 1 end, reward = { stone = 40 } },
	{ text = "Construa um Mercado encostado em casas: cada casa vizinha é um cliente.", focus = { build = "mercado" }, done = function(s) return Economy.countOf(s, "mercado") >= 1 end, reward = { gold = 150 } },
	{ text = 'Não existe "missão final": o reino é seu. Chegue a 10 construções e veja o que consegue criar.', done = function(s) return countBuilt(s) >= 10 end, reward = { gems = 3 } },
}

Game.RAID_DIRS = { "n", "s", "e", "w" }
Game.DIR_NAMES = { n = "Norte", s = "Sul", e = "Leste", w = "Oeste" }

Game.RUN_HISTORY = 10
Game.RECORD_KEYS = { "gold", "goldRate", "combo", "raidsWon", "power" }
local function recordValue(summary, k)
	if k == "combo" then
		return summary.combo and summary.combo.bonus or 0
	end
	return summary[k] or 0
end
local function updatedRecords(rec, summary)
	local out = Util.copy(rec)
	for _, k in Game.RECORD_KEYS do
		out[k] = math.max(out[k] or 0, recordValue(summary, k))
	end
	return out
end

Game.TAB_UNLOCKS = {
	{ tab = "herois", hint = "Abre depois das primeiras construções", check = function(g)
		local st = g.state.stats
		return g.state.tutorial.step >= 2 or st.built >= 2 or st.raidsWon + st.raidsLost > 0
	end },
	{ tab = "temporada", hint = "Abre com 10 construções ou 8 min de jogo", check = function(g)
		return g.state.stats.playTime >= 480 or countBuilt(g.state) >= 10
	end },
	{ tab = "social", hint = "Abre com 12 construções", check = function(g) return countBuilt(g.state) >= 12 end },
	{ tab = "legado", hint = "Abre perto da primeira Coroa", check = function(g)
		return g.state.stats.ascensions > 0 or g.state.stats.runGold >= Talents.CROWN_DIVISOR * 0.5
	end },
}
Game.TAB_NAMES = { reino = "Reino", herois = "Heróis", temporada = "Temporada", legado = "Legado", social = "Social", perfil = "Perfil" }

local function ok(extra)
	local r = extra or {}
	r.ok = true
	return r
end
local function fail(reason)
	return { ok = false, reason = reason }
end

function Game.new(state, now)
	local self = setmetatable({}, Game)
	self.state = state
	self.listeners = {}
	self.quiet = false
	self.lastBuild = nil -- última construção desfazível (não vai para o save)
	self.lastAchCheck = 0
	self.now = assert(now, "Game.new precisa de now")
	self.econ = computeEconomy(state, now)
	return self
end

function Game:on(evt, fn)
	self.listeners[evt] = self.listeners[evt] or {}
	table.insert(self.listeners[evt], fn)
	return self
end

-- Ouve todos os eventos (o servidor repassa tudo para o cliente).
function Game:onAny(fn)
	self.anyListener = fn
	return self
end

function Game:emit(evt, data)
	if self.quiet and evt == "toast" then return end
	for _, fn in self.listeners[evt] or {} do
		fn(data)
	end
	if self.anyListener then
		self.anyListener(evt, data)
	end
end

function Game:toast(text, kind)
	self:emit("toast", { text = text, kind = kind or "info" })
end

function Game:log(text)
	table.insert(self.state.log, 1, { at = self.now, text = text })
	if #self.state.log > 50 then
		table.remove(self.state.log)
	end
end

-- ------------------------------------------------------------ loop
-- background = true quando o intervalo longo veio do jogo aberto sem tick (produção integral).
function Game:tick(now, background)
	local s = self.state
	self.now = now
	self:growTrees(now)
	local dt = (now - s.lastTick) / 1000
	if dt <= 0 then return end
	if dt > Game.OFFLINE_THRESHOLD then
		local summary = self:catchUp(now, background and 1 or nil)
		if summary then
			self:emit(background and "background" or "offline", summary)
		end
		return
	end
	s.lastTick = now
	s.stats.playTime += dt
	self.econ = computeEconomy(s, now)
	self:step(dt, 1)
	self:updateLive(now)
	if now - self.lastAchCheck > 2000 then
		self.lastAchCheck = now
		self:checkAchievements()
		self:checkTutorial()
		self:checkUnlocks()
		if Season.syncSeason(s, now) then
			self:toast("Uma nova temporada começou!", "season")
		end
		if Season.syncMissions(s, now, self:goldScale()) then
			self:emit("missions")
		end
	end
end

function Game:step(dt, efficiency)
	efficiency = efficiency or 1
	local s = self.state
	local e = self.econ
	for _, r in PROD_RES do
		local rate = e.rates[r]
		local gain = rate * dt * (rate > 0 and efficiency or 1)
		local before = s.res[r]
		if gain > 0 then
			s.res[r] = before >= e.caps[r] and before or math.min(e.caps[r], before + gain)
		else
			s.res[r] = math.max(0, before + gain)
		end
		if r == "gold" and s.res.gold > before then
			local earned = s.res.gold - before
			s.stats.totalGold += earned
			s.stats.runGold += earned
			self:trackMission("gold", earned)
		end
	end
	-- População cresce até a capacidade se houver comida; passa fome se não houver.
	if s.res.food > 0.5 or e.rates.food >= 0 then
		if s.pop < e.popCap then
			s.pop = math.min(e.popCap, s.pop + Buildings.POP_GROWTH * dt * (0.5 + e.happiness / 100))
		elseif s.pop > e.popCap then
			s.pop = math.max(e.popCap, s.pop - Buildings.POP_STARVE * dt)
		end
	else
		s.pop = math.max(1, s.pop - Buildings.POP_STARVE * dt)
	end
end

-- Progresso offline: simulado em blocos para respeitar limites de armazenamento e comida.
function Game:catchUp(now, efficiency)
	local s = self.state
	local elapsed = (now - s.lastTick) / 1000
	local mods = computeEconomy(s, now).mods
	local capSec = (Game.BASE_OFFLINE_HOURS + mods.offlineHours) * 3600
	local eff = efficiency or math.min(1, Game.BASE_OFFLINE_EFF + mods.offlineEff)
	local simSec = math.min(elapsed, capSec)
	local before = Util.copy(s.res)
	local popBefore = s.pop
	local chunk = math.max(5, simSec / 400)
	local t = 0
	while t < simSec do
		local d = math.min(chunk, simSec - t)
		self.econ = computeEconomy(s, s.lastTick + t * 1000)
		self:step(d, eff)
		t += d
	end
	s.lastTick = now
	self.now = now
	-- Nada de invasão/evento/carroça instantâneos ao voltar (só para ausências de 1 min ou mais).
	if elapsed >= 60 then
		s.raid.nextAt = math.max(s.raid.nextAt, now + 90000)
		s.raid.warned = false
		s.nextEventAt = math.max(s.nextEventAt, now + 120000)
		s.chest = nil
		s.nextChestAt = now + 30000
	end
	if s.event and s.event.endsAt < now then s.event = nil end
	self.econ = computeEconomy(s, now)
	Season.syncSeason(s, now)
	Season.syncMissions(s, now, self:goldScale())
	if elapsed < 60 then return nil end
	local gains = {}
	for _, r in PROD_RES do
		gains[r] = s.res[r] - before[r]
	end
	local ready = 0
	for _, h in s.heroes.owned do
		if h.expedition and h.expedition.endsAt <= now then ready += 1 end
	end
	return { elapsed = elapsed, simulated = simSec, capped = elapsed > capSec, efficiency = eff, gains = gains, popDelta = s.pop - popBefore, expeditionsReady = ready }
end

function Game:updateLive(now)
	local s = self.state
	local e = self.econ
	-- Invasões
	if not s.raid.warned and now >= s.raid.nextAt - Events.RAID_WARNING * 1000 then
		s.raid.warned = true
		s.raid.name = Events.RAID_NAMES[math.min(#Events.RAID_NAMES, math.floor(s.raid.level / 3) + 1)]
		self:emit("raidWarning", { name = s.raid.name, strength = self:raidStrength(), defense = e.defense, dir = s.raid.dir })
	end
	if now >= s.raid.nextAt then
		self:resolveRaid(now)
	end

	-- Eventos relâmpago
	if s.event and s.event.endsAt <= now then
		self:toast(Events.EVENT_BY_ID[s.event.id].name .. " terminou.")
		s.event = nil
	end
	if not s.event and now >= s.nextEventAt then
		local ev = Events.EVENTS[math.floor(Util.random() * #Events.EVENTS) + 1]
		s.event = { id = ev.id, endsAt = now + ev.duration * 1000 }
		if ev.triggersRaid then
			s.raid.nextAt = now + ev.triggersRaid * 1000
			s.raid.warned = false
		end
		s.nextEventAt = now + (Util.randInt(Util.random, Events.EVENT_INTERVAL[1], Events.EVENT_INTERVAL[2]) / e.mods.eventRate) * 1000
		self:log("Evento: " .. ev.name)
		self:emit("event", { id = ev.id, name = ev.name, desc = ev.desc })
	end

	-- Carroça do mercador
	if s.chest and s.chest.expiresAt <= now then
		s.chest = nil
		s.nextChestAt = now + Util.randInt(Util.random, Events.CHEST_INTERVAL[1], Events.CHEST_INTERVAL[2]) * 1000
	end
	if not s.chest and now >= s.nextChestAt then
		local free = {}
		for i, t in s.grid.tiles do
			local x, y = Map.xy(i)
			if not t.b and t.t == "grass" and Map.isUnlocked(s.grid, x, y) then
				table.insert(free, { x, y })
			end
		end
		if #free > 0 then
			local c = free[math.floor(Util.random() * #free) + 1]
			s.chest = { x = c[1], y = c[2], expiresAt = now + Events.CHEST_LIFETIME * 1000 }
			if e.mods.autoChest then
				self:openChest()
			else
				self:emit("chest", s.chest)
			end
		else
			s.nextChestAt = now + 60000
		end
	end

	-- Treinos do quartel terminam sozinhos.
	self:finishTraining(now)

	-- Vagas do Conselho podem cair (taverna vendida, nova rodada): os últimos a entrar saem.
	local slots = Heroes.councilSlots(e.mods)
	if #s.heroes.council > slots then
		local out = {}
		while #s.heroes.council > slots do
			table.insert(out, 1, HERO_BY_ID[table.remove(s.heroes.council)].name)
		end
		self.econ = computeEconomy(s, now)
		self:toast(string.format("O Conselho perdeu vagas: %s %s.", table.concat(out, ", "), #out > 1 and "saíram" or "saiu"))
	end

	-- Expedições prontas (aviso único)
	for hid, h in s.heroes.owned do
		if h.expedition and not h.expedition.notified and h.expedition.endsAt <= now then
			h.expedition.notified = true
			self:toast(HERO_BY_ID[hid].name .. " voltou da expedição!", "good")
		end
	end
end

function Game:goldScale()
	local rate = self.econ and self.econ.rates.gold or 1
	if rate == 0 then rate = 1 end
	return math.max(1, math.min(1000, rate / 5))
end

-- ------------------------------------------------------------ invasões
function Game:raidStrength()
	return Util.round(Events.RAID_BASE_STRENGTH * Events.RAID_GROWTH ^ self.state.raid.level)
end

function Game:resolveRaid(now)
	local s = self.state
	local e = self.econ
	local strength = self:raidStrength()
	local name = s.raid.name or Events.RAID_NAMES[1]
	local result = { name = name, strength = strength, defense = e.defense, level = s.raid.level }
	if e.defense >= strength then
		local loot = math.floor(math.max(strength * 12 * (1 + s.raid.level * 0.15), e.rates.gold * 45) * (1 + e.mods.raidLoot))
		local gems = 1 + e.mods.raidGems + (s.raid.level % 5 == 4 and 2 or 0)
		s.res.gold += loot
		s.res.gems += gems
		s.stats.totalGold += loot
		s.stats.runGold += loot
		s.stats.raidsWon += 1
		s.stats.bestRaid = math.max(s.stats.bestRaid, s.raid.level + 1)
		s.raid.level += 1
		result.win = true
		result.loot = loot
		result.gems = gems
		self:track("raidWin")
		self:log(string.format("Vitória contra %s (força %d): +%d de ouro, +%d gema(s)", name, strength, loot, gems))
	else
		local lost = {}
		local newbie = s.stats.raidsWon + s.stats.raidsLost < Events.RAID_NEWBIE_COUNT
		local fraction = newbie and Events.RAID_NEWBIE_LOSS or Events.RAID_LOSS_FRACTION
		result.fraction = fraction
		for _, r in PROD_RES do
			local cap = math.max(50, (e.gross[r] or 0) * Events.RAID_LOSS_CAP_SECONDS)
			lost[r] = math.floor(math.min(s.res[r] * fraction, cap))
			s.res[r] -= lost[r]
		end
		s.stats.raidsLost += 1
		s.raid.level = math.max(0, s.raid.level - 1)
		result.win = false
		result.lost = lost
		self:log(string.format("%s saquearam o reino (força %d contra defesa %d).", name, strength, math.floor(e.defense)))
	end
	local interval = Events.RAID_INTERVAL * e.mods.raidInterval * (0.8 + Util.random() * 0.4)
	s.raid.nextAt = now + interval * 1000
	s.raid.warned = false
	s.raid.name = nil
	result.dir = s.raid.dir
	-- A próxima horda já anuncia de onde vem.
	s.raid.dir = Game.RAID_DIRS[math.floor(Util.random() * #Game.RAID_DIRS) + 1]
	self.econ = computeEconomy(s, now)
	self:emit("raid", result)
	return result
end

-- ------------------------------------------------------------ construção
function Game:tileAt(x, y)
	return self.state.grid.tiles[idx(x, y)]
end

-- Desbloqueio pela quantidade de construções (o maior entre o histórico e o mapa atual).
function Game:unlockProgress()
	return math.max(self.state.stats.built + 2, countBuilt(self.state))
end

function Game:isAvailable(id)
	local def = BUILDINGS[id]
	if not def.unlock then return true end
	return self:unlockProgress() >= def.unlock.buildings
end

local function validXY(x, y)
	return type(x) == "number" and type(y) == "number" and x % 1 == 0 and y % 1 == 0 and Map.inBounds(x, y)
end

function Game:build(id, x, y)
	local s = self.state
	local def = BUILDINGS[id]
	if not def then return fail("Construção desconhecida") end
	if not validXY(x, y) then return fail("Fora do mapa") end
	if not self:isAvailable(id) then return fail(string.format("Desbloqueia com %d construções", def.unlock.buildings)) end
	if not Map.isUnlocked(s.grid, x, y) then return fail("Terra ainda não conquistada") end
	local tile = self:tileAt(x, y)
	if tile.b then return fail("Já existe uma construção aqui") end
	local ter = TERRAIN[tile.t]
	if not ter.buildable then
		if ter.clearCost then
			return fail("Limpe a " .. string.lower(ter.name) .. " primeiro")
		end
		return fail("Não dá para construir em " .. string.lower(ter.name))
	end
	local cost = Economy.buildCost(s, id, self.econ.mods)
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	local missions = {}
	if s.season.missions then
		for i, m in s.season.missions.list do missions[i] = m.progress end
	end
	local xpBefore = s.season.xp
	pay(s.res, cost)
	tile.b = { id = id, lvl = 1 }
	s.stats.built += 1
	if id == "escadaria" then self:openEntrance(x, y) end
	self.econ = computeEconomy(s, self.now)
	self:track("build")
	local achs = {}
	for aid in s.achievements do achs[aid] = true end
	self.lastBuild = {
		id = id, x = x, y = y, cost = cost, at = self.now, xp = s.season.xp - xpBefore, missions = missions, guard = self:undoGuard(),
		tutorial = Util.copy(s.tutorial), achs = achs, titles = table.clone(s.cosmetics.titles), title = s.kingdom.title,
	}
	-- A Escadaria já abriu o subsolo: desfazer não fecharia o buraco, então não há desfazer.
	if id == "escadaria" then self.lastBuild = nil end
	self:emit("built", { id = id, x = x, y = y })
	return ok()
end

function Game:upgrade(x, y)
	local s = self.state
	self.lastBuild = nil
	if not validXY(x, y) then return fail("Fora do mapa") end
	local tile = self:tileAt(x, y)
	if not tile.b then return fail("Nada para melhorar") end
	local cost = Economy.upgradeCost(tile.b.id, tile.b.lvl, self.econ.mods)
	if not cost then return fail("Nível máximo") end
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	tile.b.lvl += 1
	s.stats.upgrades += 1
	self.econ = computeEconomy(s, self.now)
	self:track("upgrade")
	self:emit("upgraded", { x = x, y = y, lvl = tile.b.lvl })
	return ok()
end

function Game:sell(x, y)
	local s = self.state
	self.lastBuild = nil
	if not validXY(x, y) then return fail("Fora do mapa") end
	local tile = self:tileAt(x, y)
	if not tile.b then return fail("Nada para demolir") end
	local id, lvl = tile.b.id, tile.b.lvl
	tile.b = nil
	-- reembolso: metade do custo base escalado pela quantidade restante + metade das melhorias
	refund(s.res, Economy.buildCost(s, id, self.econ.mods), Buildings.SELL_REFUND)
	for l = 1, lvl - 1 do
		refund(s.res, Economy.upgradeCost(id, l, self.econ.mods) or {}, Buildings.SELL_REFUND)
	end
	self.econ = computeEconomy(s, self.now)
	self:emit("sold", { id = id, x = x, y = y, name = BUILDINGS[id].name })
	return ok()
end

function Game:move(fx, fy, tx, ty)
	local s = self.state
	self.lastBuild = nil
	if not validXY(fx, fy) or not validXY(tx, ty) then return fail("Fora do mapa") end
	local from = self:tileAt(fx, fy)
	local to = self:tileAt(tx, ty)
	if not from.b then return fail("Nada para mover") end
	if not Map.isUnlocked(s.grid, tx, ty) then return fail("Terra ainda não conquistada") end
	if to.b then return fail("Destino ocupado") end
	if not TERRAIN[to.t].buildable then return fail("Terreno inválido") end
	to.b = from.b
	from.b = nil
	self.econ = computeEconomy(s, self.now)
	self:emit("moved", { fx = fx, fy = fy, tx = tx, ty = ty })
	return ok()
end

function Game:clear(x, y)
	local s = self.state
	self.lastBuild = nil
	if not validXY(x, y) then return fail("Fora do mapa") end
	local tile = self:tileAt(x, y)
	local ter = TERRAIN[tile.t]
	if not Map.isUnlocked(s.grid, x, y) then return fail("Terra ainda não conquistada") end
	if not ter.clearCost then return fail("Não dá para limpar isso") end
	if not canAfford(s.res, ter.clearCost) then return fail("Recursos insuficientes") end
	pay(s.res, ter.clearCost)
	for r, v in ter.clearYield do
		s.res[r] += v
	end
	local wasSapling = tile.t == "sapling"
	tile.t = "grass"
	tile.p = nil
	self.econ = computeEconomy(s, self.now)
	-- Arrancar a própria muda não conta como limpar terreno (senão vira atalho barato para missões).
	if not wasSapling then
		s.stats.cleared += 1
		self:track("clear")
	end
	self:emit("cleared", { x = x, y = y, yieldRes = ter.clearYield })
	return ok()
end

function Game:plant(x, y)
	local s = self.state
	self.lastBuild = nil
	if not validXY(x, y) then return fail("Fora do mapa") end
	if not Map.isUnlocked(s.grid, x, y) then return fail("Terra ainda não conquistada") end
	local tile = self:tileAt(x, y)
	if tile.b or tile.t ~= "grass" then return fail("Só dá para plantar em campo livre") end
	if not canAfford(s.res, Buildings.PLANT_COST) then return fail("Recursos insuficientes") end
	pay(s.res, Buildings.PLANT_COST)
	tile.t = "sapling"
	tile.p = self.now
	s.stats.planted = (s.stats.planted or 0) + 1
	self.econ = computeEconomy(s, self.now)
	self:emit("planted", { x = x, y = y })
	return ok()
end

-- Mudas viram floresta pelo relógio (vale também para o tempo offline).
function Game:growTrees(now)
	local s = self.state
	local grown = 0
	for _, t in s.grid.tiles do
		if t.t == "sapling" and now - (t.p or 0) >= Buildings.GROW_SECONDS * 1000 then
			t.t = "forest"
			t.p = nil
			grown += 1
		end
	end
	if grown == 0 then return 0 end
	self.econ = computeEconomy(s, now)
	self:emit("grown", { n = grown })
	return grown
end

-- ------------------------------------------------------------ subsolo
function Game:underTile(d, x, y)
	return Under.levelOf(self.state, d).tiles[idx(x, y)]
end

-- A Escadaria abre o nível 1 bem embaixo dela.
function Game:openEntrance(x, y)
	local s = self.state
	local first = s.under.reached < 1
	Under.openAt(Under.levelOf(s, 1), x, y, "up")
	s.under.reached = math.max(1, s.under.reached)
	if first then
		self:log("A Escadaria abriu caminho para o subsolo: as Galerias.")
		self:emit("underOpened", { d = 1 })
	end
end

function Game:underCheck(d, x, y)
	local s = self.state
	if type(d) ~= "number" or not (d >= 1 and d <= s.under.reached) then return "Nível ainda não descoberto" end
	if not validXY(x, y) then return "Fora do mapa" end
	if not self:underTile(d, x, y).s then return "Ainda não dá para ver o que tem ali" end
	return nil
end

function Game:dig(d, x, y)
	local s = self.state
	self.lastBuild = nil
	local err = self:underCheck(d, x, y)
	if err then return fail(err) end
	local lv = Under.levelOf(s, d)
	local t = lv.tiles[idx(x, y)]
	local def = UnderData.UNDER_TILES[t.t]
	if not def.dig then return fail("Não dá para cavar " .. string.lower(def.name)) end
	if not Under.canReach(lv, x, y) then return fail("Cave a partir de uma galeria vizinha") end
	local cost = Under.digCost(s, d, self.econ.mods)
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	local was = t.t
	local gain = Under.digYield(was, d)
	for r, v in gain do
		s.res[r] = (s.res[r] or 0) + v
	end
	t.t = "floor"
	local cavern = Under.revealAround(lv, x, y)
	s.stats.dug = (s.stats.dug or 0) + 1
	self.econ = computeEconomy(s, self.now)
	self:track("clear")
	if cavern > 0 then self:log(string.format("Os mineiros romperam uma caverna no nível %d!", d)) end
	self:emit("dug", { d = d, x = x, y = y, was = was, yieldRes = gain, cavern = cavern })
	return ok()
end

function Game:digStairs(d, x, y)
	local s = self.state
	self.lastBuild = nil
	local err = self:underCheck(d, x, y)
	if err then return fail(err) end
	if d >= UnderData.DEPTHS then return fail("Não há nada mais fundo que isso") end
	local t = self:underTile(d, x, y)
	if not Under.isOpen(t) or t.b or t.st then return fail("Precisa de uma galeria vazia") end
	local cost = Under.stairsCost(d)
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	t.st = "down"
	local first = s.under.reached < d + 1
	local cavern = Under.openAt(Under.levelOf(s, d + 1), x, y, "up")
	s.under.reached = math.max(s.under.reached, d + 1)
	if first then self:log("Uma escada desceu até um nível novo: " .. UnderData.LEVEL_NAMES[d + 1] .. ".") end
	self.econ = computeEconomy(s, self.now)
	self:emit("stairs", { d = d, x = x, y = y, first = first, cavern = cavern })
	return ok()
end

function Game:buildRoom(d, x, y, id)
	local s = self.state
	self.lastBuild = nil
	local def = UnderData.ROOMS[id]
	if not def then return fail("Sala desconhecida") end
	local err = self:underCheck(d, x, y)
	if err then return fail(err) end
	if d < def.minDepth then return fail(string.format("Só existe a partir do nível %d", def.minDepth)) end
	local t = self:underTile(d, x, y)
	if not Under.isOpen(t) or t.b or t.st then return fail("Precisa de uma galeria vazia") end
	if def.onTile then
		if t.t ~= def.onTile then return fail("Só dá em " .. string.lower(UnderData.UNDER_TILES[def.onTile].name)) end
	elseif t.t ~= "floor" then
		return fail("Só dá em galeria cavada")
	end
	if not Under.roomAdjacency(Under.levelOf(s, d), id, x, y).hasRequired then
		return fail("Precisa estar encostada em " .. string.lower(UnderData.UNDER_TILES[def.requiresAdj].name))
	end
	local cost = Under.roomCost(s, id, self.econ.mods)
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	t.b = { id = id, lvl = 1 }
	self.econ = computeEconomy(s, self.now)
	self:track("build")
	self:emit("roomBuilt", { d = d, x = x, y = y, id = id })
	return ok()
end

function Game:upgradeRoom(d, x, y)
	local s = self.state
	self.lastBuild = nil
	local err = self:underCheck(d, x, y)
	if err then return fail(err) end
	local t = self:underTile(d, x, y)
	if not t.b then return fail("Nada para melhorar") end
	local cost = Under.roomUpgradeCost(t.b.id, t.b.lvl, self.econ.mods)
	if not cost then return fail("Nível máximo") end
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	t.b.lvl += 1
	s.stats.upgrades += 1
	self.econ = computeEconomy(s, self.now)
	self:track("upgrade")
	self:emit("roomUpgraded", { d = d, x = x, y = y, lvl = t.b.lvl })
	return ok()
end

function Game:sellRoom(d, x, y)
	local s = self.state
	self.lastBuild = nil
	local err = self:underCheck(d, x, y)
	if err then return fail(err) end
	local t = self:underTile(d, x, y)
	if not t.b then return fail("Nada para demolir") end
	local id, lvl = t.b.id, t.b.lvl
	t.b = nil
	refund(s.res, Under.roomCost(s, id, self.econ.mods), Buildings.SELL_REFUND)
	for l = 1, lvl - 1 do
		refund(s.res, Under.roomUpgradeCost(id, l, self.econ.mods) or {}, Buildings.SELL_REFUND)
	end
	self.econ = computeEconomy(s, self.now)
	self:emit("sold", { id = id, x = x, y = y, name = UnderData.ROOMS[id].name })
	return ok()
end

function Game:expandCost()
	local base = Map.RING_COSTS[self.state.grid.ring + 1]
	if not base then return nil end
	return Economy.scaleCost(base, 1 - self.econ.mods.landCost)
end

function Game:expand()
	local s = self.state
	self.lastBuild = nil
	if s.grid.ring >= Map.MAX_RING then return fail("O mapa inteiro já é seu") end
	local cost = self:expandCost()
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	s.grid.ring += 1
	self:log(string.format("O reino se expandiu para o anel %d.", s.grid.ring))
	self:emit("expanded", { ring = s.grid.ring })
	return ok()
end

-- ------------------------------------------------------------ heróis
function Game:recruit(method)
	local s = self.state
	if method ~= "gold" and method ~= "gems" and method ~= "scroll" then return fail("Inválido") end
	local cost = Heroes.recruitCost(s, method)
	local pool = method == "scroll" and s.items or s.res
	if not canAfford(pool, cost) then
		return fail(method == "scroll" and "Sem pergaminhos" or "Recursos insuficientes")
	end
	pay(pool, cost)
	if method == "gold" then s.stats.goldRecruits += 1 end
	local result = Heroes.addHero(s, Heroes.rollHero(Util.random))
	s.stats.recruits += 1
	if result.isNew and #s.heroes.council < Heroes.councilSlots(self.econ.mods) then
		table.insert(s.heroes.council, result.hero.id)
	end
	self.econ = computeEconomy(s, self.now)
	self:track("recruit")
	self:log("Recrutou " .. result.hero.name .. (result.isNew and "" or string.format(" (%d estrelas)", result.stars)))
	local view = { heroId = result.hero.id, name = result.hero.name, rarity = result.hero.rarity, isNew = result.isNew, stars = result.stars, gemsRefund = result.gemsRefund }
	self:emit("recruited", view)
	return ok({ result = view })
end

function Game:toggleCouncil(hid)
	local s = self.state
	local owned = s.heroes.owned[hid]
	if not owned then return fail("Herói não recrutado") end
	local i = table.find(s.heroes.council, hid)
	if i then
		table.remove(s.heroes.council, i)
	else
		if owned.expedition then return fail("Herói em expedição") end
		if #s.heroes.council >= Heroes.councilSlots(self.econ.mods) then return fail("Conselho cheio") end
		table.insert(s.heroes.council, hid)
	end
	self.econ = computeEconomy(s, self.now)
	return ok()
end

local function findExpedition(id)
	for i, x in HeroData.EXPEDITIONS do
		if x.id == id then return x, i end
	end
	return nil
end

function Game:startExpedition(hid, expId)
	local s = self.state
	local owned = s.heroes.owned[hid]
	local exp = findExpedition(expId)
	if not owned or not exp then return fail("Inválido") end
	if owned.expedition then return fail("Já está em expedição") end
	if owned.training then return fail("Herói treinando no Quartel") end
	if table.find(s.heroes.council, hid) then return fail("Tire o herói do Conselho primeiro") end
	if Heroes.activeExpeditions(s) >= Heroes.expeditionSlots(s) then return fail("Todas as vagas de expedição estão ocupadas") end
	owned.expedition = { id = exp.id, startedAt = self.now, endsAt = self.now + exp.duration * 1000 }
	self:emit("expeditionStart", { hid = hid, exp = exp.id })
	return ok()
end

function Game:collectExpedition(hid)
	local s = self.state
	local owned = s.heroes.owned[hid]
	if not owned or not owned.expedition then return fail("Sem expedição") end
	if owned.expedition.endsAt > self.now then return fail("Ainda em andamento") end
	local exp, expIndex = findExpedition(owned.expedition.id)
	local reward = Heroes.expeditionReward(s, HERO_BY_ID[hid], exp, self.econ, Util.random)
	s.res.gold += reward.gold
	s.res.wood += reward.wood
	s.res.stone += reward.stone
	s.res.gems += reward.gems
	s.items.scrolls += reward.scrolls
	s.stats.totalGold += reward.gold
	s.stats.runGold += reward.gold
	s.stats.expeditions += 1
	owned.expedition = nil
	self:track("expedition", 1, Seasons.XP_REWARDS.expedition * expIndex)
	self:emit("expeditionDone", { hid = hid, reward = reward })
	return ok({ reward = reward })
end

function Game:speedUpExpedition(hid)
	local s = self.state
	local owned = s.heroes.owned[hid]
	if not owned or not owned.expedition then return fail("Sem expedição") end
	local remaining = (owned.expedition.endsAt - self.now) / 1000
	if remaining <= 0 then return fail("Já terminou") end
	local cost = Heroes.expeditionSpeedUpCost(remaining)
	if s.res.gems < cost then return fail("Gemas insuficientes") end
	s.res.gems -= cost
	owned.expedition.endsAt = self.now
	return ok()
end

-- ------------------------------------------------------------ quartel
function Game:trainHero(hid)
	local s = self.state
	local owned = s.heroes.owned[hid]
	local hero = HERO_BY_ID[hid]
	if not owned or not hero then return fail("Herói não recrutado") end
	local level = owned.level or 1
	if Heroes.trainingSlots(s) == 0 then return fail("Construa um Quartel") end
	if owned.training then return fail("Já está treinando") end
	if owned.expedition then return fail("Herói em expedição") end
	if level >= Heroes.heroLevelCap(s) then return fail("Melhore o Quartel para treinar mais") end
	if Heroes.trainingCount(s) >= Heroes.trainingSlots(s) then return fail("Quartel ocupado") end
	local cost = Heroes.trainCost(hero, level)
	if not canAfford(s.res, cost) then return fail("Recursos insuficientes") end
	pay(s.res, cost)
	owned.training = { startedAt = self.now, endsAt = self.now + Heroes.trainSeconds(level) * 1000 }
	self:emit("trainStart", { hid = hid })
	return ok()
end

function Game:speedUpTraining(hid)
	local s = self.state
	local owned = s.heroes.owned[hid]
	if not owned or not owned.training then return fail("Sem treino") end
	local remaining = (owned.training.endsAt - self.now) / 1000
	if remaining <= 0 then return fail("Já terminou") end
	local cost = Heroes.speedUpCost(remaining)
	if s.res.gems < cost then return fail("Gemas insuficientes") end
	s.res.gems -= cost
	owned.training.endsAt = self.now
	self:finishTraining(self.now)
	return ok()
end

function Game:finishTraining(now)
	now = now or self.now
	local s = self.state
	local done = false
	for hid, h in s.heroes.owned do
		if h.training and h.training.endsAt <= now then
			h.training = nil
			h.level = (h.level or 1) + 1
			done = true
			self:log(string.format("%s chegou ao nível %d", HERO_BY_ID[hid].name, h.level))
			self:toast(string.format("%s terminou o treino: nível %d!", HERO_BY_ID[hid].name, h.level), "good")
		end
	end
	if done then self.econ = computeEconomy(s, now) end
end

-- ------------------------------------------------------------ carroça do mercador
function Game:openChest()
	local s = self.state
	if not s.chest then return fail(nil) end
	local e = self.econ
	local roll = Util.random()
	local reward
	if roll < 0.45 then
		reward = { gold = math.floor(math.max(60, e.rates.gold * 60)) }
	elseif roll < 0.65 then
		reward = { food = math.floor(math.max(40, e.gross.food * 60)), wood = math.floor(math.max(30, e.gross.wood * 60)) }
	elseif roll < 0.8 then
		reward = { gems = 1 + (Util.random() < 0.3 and 1 or 0) }
	elseif roll < 0.9 then
		reward = { stone = math.floor(math.max(30, e.gross.stone * 90)) }
	else
		reward = { boost = 2 }
	end
	for r, v in reward do
		if r == "boost" then
			s.boostUntil = math.max(s.boostUntil, self.now) + v * 60000
		else
			s.res[r] += v
		end
		if r == "gold" then
			s.stats.totalGold += v
			s.stats.runGold += v
		end
	end
	local at = { x = s.chest.x, y = s.chest.y }
	s.chest = nil
	s.nextChestAt = self.now + Util.randInt(Util.random, Events.CHEST_INTERVAL[1], Events.CHEST_INTERVAL[2]) * 1000
	s.stats.chests += 1
	self:track("chest")
	self:emit("chestOpened", { reward = reward, x = at.x, y = at.y })
	return ok({ reward = reward })
end

-- ------------------------------------------------------------ progressão: missões, passe, XP
function Game:addXp(amount)
	local s = self.state
	local before = Season.tierOf(s.season.xp)
	s.season.xp += Util.round(amount * (1 + self.econ.mods.xp))
	local after = Season.tierOf(s.season.xp)
	if after > before then self:emit("tierUp", { tier = after }) end
end

function Game:trackMission(kind, amount)
	amount = amount or 1
	local missions = self.state.season.missions
	if not missions then return end
	for _, m in missions.list do
		if m.track == kind and not m.claimed then
			m.progress = math.min(m.target, m.progress + amount)
		end
	end
end

function Game:track(kind, amount, xpOverride)
	amount = amount or 1
	self:trackMission(kind, amount)
	local xp = xpOverride or Seasons.XP_REWARDS[kind]
	if xp then self:addXp(xp * amount) end
end

function Game:claimMission(i)
	local missions = self.state.season.missions
	local m = missions and missions.list[i]
	if not m or m.claimed or m.progress < m.target then return fail("Missão incompleta") end
	m.claimed = true
	self:addXp(m.xp)
	self:toast(string.format("Missão concluída: +%d XP de temporada", m.xp), "good")
	return ok()
end

function Game:grant(reward)
	local s = self.state
	local kind = reward.type
	if kind == "gems" then
		s.res.gems += reward.amount
	elseif kind == "scroll" then
		s.items.scrolls += reward.amount
	elseif kind == "boost" then
		s.boostUntil = math.max(s.boostUntil, self.now) + reward.minutes * 60000
	elseif kind == "goldMinutes" then
		local v = math.floor(math.max(100, self.econ.rates.gold * reward.minutes * 60))
		s.res.gold += v
		s.stats.totalGold += v
		s.stats.runGold += v
	elseif kind == "cosmetic" then
		local list = ({ title = "titles", banner = "banners", emblem = "emblems" })[reward.kind]
		local value = reward.kind == "title" and (Cosmetics.SEASON_TITLES[reward.id] or reward.id) or reward.id
		if not table.find(s.cosmetics[list], value) then
			table.insert(s.cosmetics[list], value)
		end
	end
end

function Game:claimTier(tier)
	local s = self.state
	if type(tier) ~= "number" or tier < 1 or tier > Seasons.SEASON_TIERS or tier > Season.tierOf(s.season.xp) then
		return fail("Nível do passe não alcançado")
	end
	if table.find(s.season.claimed, tier) then return fail("Já resgatado") end
	local reward = Season.rewardFor(tier, s)
	table.insert(s.season.claimed, tier)
	self:grant(reward)
	self:toast(string.format("Passe nível %d: %s", tier, reward.label), "good")
	return ok({ reward = reward })
end

function Game:dailyStatus()
	local today = Util.dayKey(self.now)
	local yesterday = Util.dayKey(self.now - 86400000)
	local d = self.state.daily
	local available = d.lastDay ~= today
	local nextStreak = d.lastDay == yesterday and d.streak + 1 or 1
	return { available = available, nextStreak = nextStreak, reward = Cosmetics.DAILY_REWARDS[(nextStreak - 1) % 7 + 1] }
end

function Game:claimDaily()
	local s = self.state
	local st = self:dailyStatus()
	if not st.available then return fail("Volte amanhã") end
	s.daily = { lastDay = Util.dayKey(self.now), streak = st.nextStreak }
	local r = st.reward
	if r.gold then s.res.gold += r.gold end
	if r.gems then s.res.gems += r.gems end
	if r.goldMinutes then self:grant({ type = "goldMinutes", minutes = r.goldMinutes }) end
	if r.boost then self:grant({ type = "boost", minutes = r.boost }) end
	if r.scroll then s.items.scrolls += r.scroll end
	self:track("daily")
	self:toast(string.format("Dia %d seguido: %s", st.nextStreak, r.label), "good")
	return ok()
end

-- ------------------------------------------------------------ prestígio
function Game:crownsOnAscend()
	local s = self.state
	return math.floor(math.sqrt(s.stats.runGold / Talents.CROWN_DIVISOR) * (1 + self.econ.crownBonus + self.econ.mods.crowns))
end

function Game:ascend()
	local crowns = self:crownsOnAscend()
	if crowns < 1 then return fail("Ainda não há Coroas a ganhar") end
	self.lastBuild = nil
	local s = self.state
	local summary = self:runSummary(crowns)
	s.res.crowns += crowns
	s.stats.ascensions += 1
	summary.totalCrowns = s.res.crowns
	local nextState = State.createState({ seed = State.newSeed(), now = self.now, carry = State.carryOver(s) })
	local runs = { summary }
	for _, r in s.runs or {} do
		if #runs >= Game.RUN_HISTORY then break end
		table.insert(runs, r)
	end
	nextState.runs = runs
	nextState.records = updatedRecords(s.records or {}, summary)
	nextState.log = { { at = self.now, text = string.format("Ascensão nº %d: +%d Coroas. Um novo reino começa.", nextState.stats.ascensions, crowns) } }
	self.state = nextState
	self.econ = computeEconomy(nextState, self.now)
	self:emit("ascended", { crowns = crowns, summary = summary })
	return ok({ crowns = crowns, summary = summary })
end

-- Resumo da rodada atual (tela de Ascensão).
function Game:runSummary(crowns)
	crowns = crowns or self:crownsOnAscend()
	local s = self.state
	local e = self.econ
	local b = s.runBase
	local function delta(k)
		if not b then return nil end
		return math.max(0, (s.stats[k] or 0) - (b[k] or 0))
	end
	local combo = nil
	local buildings = 0
	local maxLvl = 0
	for i, t in s.grid.tiles do
		if t.b then
			buildings += 1
			maxLvl = math.max(maxLvl, t.b.lvl)
			local info = e.tiles[i]
			if info and info.adjBonus > 0 and (not combo or info.adjBonus > combo.bonus) then
				combo = { id = info.id, bonus = info.adjBonus, lvl = info.lvl }
			end
		end
	end
	local summary = {
		n = s.stats.ascensions + 1, at = self.now, name = s.kingdom.name, crowns = crowns,
		duration = math.max(0, (self.now - (s.runStartedAt or self.now)) / 1000), played = delta("playTime"),
		gold = s.stats.runGold, goldRate = math.max(0, e.rates.gold), power = Economy.kingdomPower(s), ring = s.grid.ring,
		buildings = buildings, maxLvl = maxLvl, combo = combo,
		built = delta("built"), upgrades = delta("upgrades"), raidsWon = delta("raidsWon"), raidsLost = delta("raidsLost"),
		expeditions = delta("expeditions"), chests = delta("chests"), recruits = delta("recruits"),
	}
	-- Recordes só contam a partir da 2ª rodada registrada (na 1ª, tudo seria "recorde").
	local rec = s.records or {}
	summary.newRecords = {}
	if s.runs and #s.runs > 0 then
		for _, k in Game.RECORD_KEYS do
			if recordValue(summary, k) > (rec[k] or 0) then
				table.insert(summary.newRecords, k)
			end
		end
	end
	return summary
end

function Game:talentCost(id)
	local t = Talents.TALENT_BY_ID[id]
	if not t then return nil end
	local lvl = self.state.legacy[id] or 0
	if lvl >= t.max then return nil end
	return t.baseCost * (lvl + 1)
end

function Game:buyTalent(id)
	local cost = self:talentCost(id)
	if cost == nil then return fail("Nível máximo") end
	if self.state.res.crowns < cost then return fail("Coroas insuficientes") end
	self.state.res.crowns -= cost
	self.state.legacy[id] = (self.state.legacy[id] or 0) + 1
	self.econ = computeEconomy(self.state, self.now)
	return ok()
end

-- Conselho de quando ascender: recomendado quando a Ascensão pelo menos dobra as Coroas que você já conquistou.
function Game:ascendAdvice()
	local s = self.state
	local crowns = self:crownsOnAscend()
	local spent = 0
	for id, lvl in s.legacy do
		local t = Talents.TALENT_BY_ID[id]
		if t then spent += (t.baseCost * lvl * (lvl + 1)) / 2 end
	end
	local owned = s.res.crowns + spent
	local mult = 1 + self.econ.crownBonus + self.econ.mods.crowns
	local nextGold = Talents.CROWN_DIVISOR * ((crowns + 1) / mult) ^ 2
	local rate = math.max(0, self.econ.rates.gold)
	local secondsToNext = rate > 0 and math.max(0, (nextGold - s.stats.runGold) / rate) or -1
	return { crowns = crowns, owned = owned, recommended = crowns >= 1 and crowns >= math.max(1, owned), secondsToNext = secondsToNext }
end

-- ------------------------------------------------------------ identidade
-- O nome já chega filtrado pelo TextService (o servidor filtra antes de chamar).
function Game:setKingdomName(name)
	local clean = string.sub(string.gsub(string.gsub(tostring(name), "[<>]", ""), "^%s*(.-)%s*$", "%1"), 1, 24)
	if clean == "" then return fail("Nome vazio") end
	self.state.kingdom.name = clean
	return ok()
end

function Game:ownsCosmetic(kind, id)
	local list = kind == "banner" and Cosmetics.BANNERS or Cosmetics.EMBLEMS
	local def = Util.find(list, function(c) return c.id == id end)
	if not def then return false end
	return def.free == true or table.find(self.state.cosmetics[kind == "banner" and "banners" or "emblems"], id) ~= nil
end

function Game:buyCosmetic(kind, id)
	local list = kind == "banner" and Cosmetics.BANNERS or Cosmetics.EMBLEMS
	local def = Util.find(list, function(c) return c.id == id end)
	if not def or not def.price then return fail("Não está à venda") end
	if self:ownsCosmetic(kind, id) then return fail("Já é seu") end
	if self.state.res.gems < def.price then return fail("Gemas insuficientes") end
	self.state.res.gems -= def.price
	table.insert(self.state.cosmetics[kind == "banner" and "banners" or "emblems"], id)
	return ok()
end

function Game:equip(kind, id)
	if kind == "title" then
		if not table.find(self.state.cosmetics.titles, id) then return fail("Título bloqueado") end
		self.state.kingdom.title = id
		return ok()
	end
	if kind ~= "banner" and kind ~= "emblem" then return fail("Inválido") end
	if not self:ownsCosmetic(kind, id) then return fail("Bloqueado") end
	self.state.kingdom[kind] = id
	return ok()
end

-- ------------------------------------------------------------ social
function Game:rivals()
	local s = self.state
	local list = Social.generateRivals(s.social.rivalsSeed, self.now, s.createdAt)
	table.insert(list, { id = "me", name = s.kingdom.name, ruler = "Você", title = s.kingdom.title, banner = s.kingdom.banner, emblem = s.kingdom.emblem, power = Economy.kingdomPower(s), me = true })
	table.sort(list, function(a, b) return a.power > b.power end)
	return list
end

-- Visita conta para estatística/missão uma vez por reino por dia.
function Game:recordVisit(key)
	local s = self.state
	local today = Util.dayKey(self.now)
	s.social.visited = s.social.visited or {}
	if s.social.visited[key] == today then return false end
	s.social.visited[key] = today
	s.stats.visits += 1
	self:track("visit")
	return true
end

function Game:greetRival(rid)
	local s = self.state
	local today = Util.dayKey(self.now)
	if type(rid) ~= "string" then return fail("Inválido") end
	if s.social.greets[rid] == today then return fail("Você já saudou este reino hoje") end
	s.social.greets[rid] = today
	self:recordVisit(rid)
	self:addXp(10)
	local gift = nil
	if Util.random() < 0.25 then
		gift = 1
		s.res.gems += 1
	end
	return ok({ gift = gift })
end

function Game:tradeRival(rid, giveRes)
	local s = self.state
	local value = ({ food = 1, wood = 2, stone = 3 })[giveRes]
	if type(rid) ~= "string" or not value then return fail("Inválido") end
	local last = s.social.trades[rid] or 0
	if self.now - last < 3600000 then
		return fail(string.format("Próxima troca em %d min", math.ceil((3600000 - (self.now - last)) / 60000)))
	end
	local amount = math.floor(s.res[giveRes] * 0.25)
	if amount < 10 then return fail("Recursos insuficientes para trocar") end
	local gold = math.floor(amount * value * 1.5)
	s.res[giveRes] -= amount
	s.res.gold += gold
	s.stats.totalGold += gold
	s.stats.runGold += gold
	s.social.trades[rid] = self.now
	return ok({ amount = amount, gold = gold })
end

-- ------------------------------------------------------------ desfazer
-- Prêmios que o jogador resgata por ação própria: se mudaram desde a obra, a janela fecha.
function Game:undoGuard()
	local s = self.state
	local claimedMissions = 0
	local day = ""
	if s.season.missions then
		day = s.season.missions.day
		for _, m in s.season.missions.list do
			if m.claimed then claimedMissions += 1 end
		end
	end
	return table.concat({ s.season.number, #s.season.claimed, day, claimedMissions }, "|")
end

-- Prêmios automáticos que a obra disparou (passo do tutorial, conquista): voltam junto ao desfazer.
function Game:undoClawback(u)
	local s = self.state
	local back = {}
	local function add(r, v) back[r] = (back[r] or 0) + v end
	for i = u.tutorial.step + 1, math.min(s.tutorial.step, #Game.TUTORIAL) do
		for r, v in Game.TUTORIAL[i].reward do add(r, v) end
	end
	for _, a in Achievements.ACHIEVEMENTS do
		if s.achievements[a.id] and not u.achs[a.id] then add("gems", a.gems) end
	end
	return back
end

function Game:canUndo(now)
	now = now or self.now
	local u = self.lastBuild
	if not u or now - u.at > Game.UNDO_WINDOW then return false end
	local b = self:tileAt(u.x, u.y).b
	if not b or b.id ~= u.id or b.lvl ~= 1 or self:undoGuard() ~= u.guard then return false end
	return canAfford(self.state.res, self:undoClawback(u))
end

-- Devolve 100% do custo e volta estatística, missões e XP ao que eram antes da obra.
function Game:undoBuild()
	if not self:canUndo() then
		self.lastBuild = nil
		return fail("Não dá mais para desfazer")
	end
	local s = self.state
	local u = self.lastBuild
	self.lastBuild = nil
	pay(s.res, self:undoClawback(u))
	for id in Util.copy(s.achievements) do
		if not u.achs[id] then s.achievements[id] = nil end
	end
	s.tutorial = Util.copy(u.tutorial)
	s.cosmetics.titles = u.titles
	if not table.find(u.titles, s.kingdom.title) then s.kingdom.title = u.title end
	self:tileAt(u.x, u.y).b = nil
	refund(s.res, u.cost, 1)
	s.stats.built = math.max(0, s.stats.built - 1)
	s.season.xp = math.max(0, s.season.xp - u.xp)
	if s.season.missions then
		for i, m in s.season.missions.list do
			if m.track == "build" and not m.claimed and u.missions[i] ~= nil then m.progress = u.missions[i] end
		end
	end
	self.econ = computeEconomy(s, self.now)
	self:emit("undone", { id = u.id, x = u.x, y = u.y })
	return ok()
end

-- ------------------------------------------------------------ melhorias em lote e prévias
function Game:upgradeMax(x, y)
	local n = 0
	while self:upgrade(x, y).ok do n += 1 end
	return n
end

-- Melhora todos os prédios de um tipo, sempre o de menor nível primeiro, enquanto der para pagar.
function Game:upgradeAll(id)
	local s = self.state
	local n = 0
	while true do
		local best = nil
		for i, t in s.grid.tiles do
			if t.b and t.b.id == id and Economy.upgradeCost(id, t.b.lvl, self.econ.mods) then
				if not best or t.b.lvl < best.lvl then best = { i = i, lvl = t.b.lvl } end
			end
		end
		if not best then break end
		local x, y = Map.xy(best.i)
		if not self:upgrade(x, y).ok then break end
		n += 1
	end
	return n
end

-- Diferença de produção (por segundo), defesa e capacidade se `mutate` fosse aplicado.
function Game:previewDelta(mutate, undo)
	local s = self.state
	local function settled()
		local pop = s.pop
		s.pop = math.max(pop, computeEconomy(s, self.now).popCap)
		local e = computeEconomy(s, self.now)
		s.pop = pop
		return e
	end
	local before = settled()
	mutate()
	local after = settled()
	undo()
	local d = { defense = after.defense - before.defense, popCap = after.popCap - before.popCap, happiness = after.happiness - before.happiness }
	for _, r in PROD_RES do
		d[r] = after.rates[r] - before.rates[r]
	end
	return d
end

function Game:previewBuild(id, x, y)
	if not BUILDINGS[id] or not validXY(x, y) then return nil end
	local tile = self:tileAt(x, y)
	if tile.b then return nil end
	return self:previewDelta(function() tile.b = { id = id, lvl = 1 } end, function() tile.b = nil end)
end

function Game:previewUpgrade(x, y)
	if not validXY(x, y) then return nil end
	local tile = self:tileAt(x, y)
	if not tile.b or not Economy.upgradeCost(tile.b.id, tile.b.lvl, self.econ.mods) then return nil end
	return self:previewDelta(function() tile.b.lvl += 1 end, function() tile.b.lvl -= 1 end)
end

-- ------------------------------------------------------------ desbloqueio gradual
function Game:isTabUnlocked(tab)
	return table.find(self.state.unlocks.tabs, tab) ~= nil
end

function Game:checkUnlocks()
	for _, rule in Game.TAB_UNLOCKS do
		if not self:isTabUnlocked(rule.tab) and rule.check(self) then
			table.insert(self.state.unlocks.tabs, rule.tab)
			self:emit("unlock", { tab = rule.tab, name = Game.TAB_NAMES[rule.tab] })
		end
	end
end

-- ------------------------------------------------------------ conquistas e tutorial
function Game:checkAchievements()
	local s = self.state
	for _, a in Achievements.ACHIEVEMENTS do
		if not s.achievements[a.id] and a.check(s, self.econ, HERO_BY_ID) then
			s.achievements[a.id] = self.now
			s.res.gems += a.gems
			if a.title and not table.find(s.cosmetics.titles, a.title) then
				table.insert(s.cosmetics.titles, a.title)
			end
			self:log("Conquista: " .. a.name)
			self:emit("achievement", { id = a.id, name = a.name, desc = a.desc, gems = a.gems, title = a.title })
		end
	end
end

function Game:checkTutorial()
	local s = self.state
	if s.tutorial.done then return end
	local step = Game.TUTORIAL[s.tutorial.step + 1]
	if not step then
		s.tutorial.done = true
		return
	end
	if step.done(s) then
		for r, v in step.reward do s.res[r] += v end
		s.tutorial.step += 1
		if s.tutorial.step >= #Game.TUTORIAL then s.tutorial.done = true end
		self:emit("tutorial", { step = s.tutorial.step })
	end
end

return Game
