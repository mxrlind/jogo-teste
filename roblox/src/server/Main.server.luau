-- Servidor do Reino de Bolso no Roblox.
-- Cada jogador tem o próprio reino (um Game do porte), que roda aqui no servidor e é salvo no DataStore.
-- O cliente (ReinoCliente) só mostra o estado e pede ações pelo RemoteFunction "Acao".
-- No mesmo DataStore ficam, em chaves à parte: as preferências ("config_<UserId>", porte de src/core/config.js)
-- e os backups em rodízio ("backup_<UserId>", porte de src/core/storage.js).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Game = require(Reino.Core.Game)
local State = require(Reino.Core.State)
local Config = require(Reino.Core.Config)
local Storage = require(Reino.Core.Storage)
local Season = require(Reino.Core.Season)
local Util = require(Reino.Core.Util)
local Seasons = require(Reino.Data.Seasons)

Players.CharacterAutoLoads = false -- o jogo é só a tela do reino, sem boneco andando

local SAVE_EVERY = 60 -- segundos entre salvamentos automáticos
local TICK = 1 -- segundos entre ticks do reino (o jogo web também usa 1 s)
local CONFIG_DEBOUNCE = 3 -- segundos parados antes de gravar as preferências (sliders mandam várias seguidas)
local BACKUP_SLOTS = Storage.BACKUP_SLOTS
local BACKUP_INTERVAL = Storage.BACKUP_INTERVAL
local store = nil
local ok, err = pcall(function()
	store = DataStoreService:GetDataStore("ReinoDeBolso_v1")
end)
if not ok then
	warn("DataStore indisponível (no Studio, ligue Game Settings > Security > Enable Studio Access to API Services). O progresso não será salvo.", err)
end

-- PolicyService: regras de compra por país/idade. Nada pago está ligado (Shop.PAYMENTS_ENABLED = false);
-- a política só é consultada para negar pacotes de gemas onde itens pagos aleatórios são restritos.
local PolicyService = nil
pcall(function()
	PolicyService = game:GetService("PolicyService")
end)

-- ------------------------------------------------------------ remotes
local remotes = Instance.new("Folder")
remotes.Name = "ReinoRemotes"
local acao = Instance.new("RemoteFunction")
acao.Name = "Acao"
acao.Parent = remotes
local estado = Instance.new("RemoteEvent")
estado.Name = "Estado"
estado.Parent = remotes
remotes.Parent = ReplicatedStorage

local function nowMs()
	return DateTime.now().UnixTimestampMillis
end

-- [Player] = { game, events, lastUnder, lastSave, calls, loadFailed, config, configDirtyAt, configFailed, sendExtra, hasSave,
--              backups, backupsFailed, policy }
local sessions = {}

-- ------------------------------------------------------------ salvar e carregar
local function keyFor(player)
	return "reino_" .. player.UserId
end
local function configKey(player)
	return "config_" .. player.UserId
end
local function backupKey(player)
	return "backup_" .. player.UserId
end

local function withRetry(fn)
	for attempt = 1, 4 do
		local success, result = pcall(fn)
		if success then return true, result end
		warn("DataStore falhou (tentativa " .. attempt .. "):", result)
		task.wait(2 ^ attempt)
	end
	return false, nil
end

-- nil = não existe; false = não deu para ler.
local function loadKey(key)
	if not store then return nil end
	local success, data = withRetry(function()
		return store:GetAsync(key)
	end)
	if not success then return false end
	return data
end

local function load(player)
	return loadKey(keyFor(player))
end

local function save(player)
	local s = sessions[player]
	if not s or not store or s.loadFailed then return end
	s.lastSave = os.clock()
	local data = State.serialize(s.game.state)
	withRetry(function()
		store:SetAsync(keyFor(player), data, { player.UserId })
	end)
end

local function saveConfig(player)
	local s = sessions[player]
	if not s or not store or not s.configDirtyAt or s.configFailed then return end
	s.configDirtyAt = nil
	local cfg = s.config
	withRetry(function()
		store:SetAsync(configKey(player), cfg, { player.UserId })
	end)
end

-- Preferências padrão do Roblox: o Esc abre o menu do próprio Roblox, então o menu do jogo fica no Q.
local function defaultConfig()
	local c = Config.defaultConfig()
	c.keys.menu = "q"
	return c
end

local function normalizeConfig(raw)
	local c = Config.normalizeConfig(raw)
	for id, k in c.keys do
		if type(k) ~= "string" or #k > 24 then
			c.keys[id] = defaultConfig().keys[id]
		end
	end
	return c
end

-- Backups em rodízio: { next = 0..SLOTS-1, lastAt = ms, slots = { [1..SLOTS] = { at, data } } }.
local function writeBackup(player, force)
	local s = sessions[player]
	if not s or not store or s.loadFailed or s.backupsFailed then return end
	local now = nowMs()
	local b = s.backups
	if not force and now - (b.lastAt or 0) < BACKUP_INTERVAL then return end
	local slot = (b.next or 0) % BACKUP_SLOTS
	b.slots = b.slots or {}
	b.slots[slot + 1] = { at = now, data = State.serialize(s.game.state) }
	b.next = (slot + 1) % BACKUP_SLOTS
	b.lastAt = now
	local copy = { next = b.next, lastAt = b.lastAt, slots = b.slots }
	task.spawn(withRetry, function()
		store:SetAsync(backupKey(player), copy, { player.UserId })
	end)
end

local function listBackups(s)
	local out = {}
	local slots = s.backups and s.backups.slots or {}
	for i = 1, BACKUP_SLOTS do
		local b = slots[i]
		if type(b) == "table" then
			local okNorm, st = pcall(State.normalize, b.data, nowMs())
			if okNorm then
				table.insert(out, { slot = i - 1, at = st.lastTick or b.at, name = st.kingdom and st.kingdom.name, gold = st.stats and st.stats.totalGold or 0 })
			else
				table.insert(out, { slot = i - 1, broken = true })
			end
		end
	end
	table.sort(out, function(a, c) return (a.at or 0) > (c.at or 0) end)
	return out
end

-- ------------------------------------------------------------ o que vai para o cliente
-- O cliente recebe o estado inteiro e roda a mesma economia (para prévias e custos sem esperar o servidor).
-- O subsolo só vai quando muda, porque é a parte grande.
local function snapshot(s)
	local data = State.serialize(s.game.state)
	local underJson = HttpService:JSONEncode(data.under)
	if underJson == s.lastUnder then
		data.under = nil
	else
		s.lastUnder = underJson
	end
	data.log = table.move(s.game.state.log, 1, math.min(15, #s.game.state.log), 1, {})
	data.canUndo = s.game:canUndo()
	-- A última obra desfazível (não vai para o save): o espelho do cliente põe em g.lastBuild para o canUndo.
	data.lastBuild = s.game.lastBuild and Util.deepCopy(s.game.lastBuild) or nil
	data.raidStrength = s.game:raidStrength()
	return data
end

-- extra (4º argumento): as preferências e se há um reino salvo (o "Continuar" do menu).
-- Vai no primeiro envio, depois de "sync" e sempre que a config muda.
local function push(player)
	local s = sessions[player]
	if not s then return end
	local events = s.events
	s.events = {}
	local extra = nil
	if s.sendExtra then
		s.sendExtra = false
		extra = { config = s.config, hasSave = s.hasSave }
	end
	estado:FireClient(player, snapshot(s), events, nowMs(), extra)
end

-- Troca o reino da sessão (novo, importado, backup): Game novo ligado à mesma fila de eventos.
local function setState(s, state)
	local now = nowMs()
	local g = Game.new(state, now)
	g:onAny(function(evt, payload)
		table.insert(s.events, { evt, payload })
	end)
	s.game = g
	s.lastUnder = nil
	g:tick(now)
	return g
end

-- ------------------------------------------------------------ jogadores
local function start(player)
	local now = nowMs()
	local data = load(player)
	local state
	local loadFailed = data == false
	if type(data) == "table" then
		local success, result = pcall(State.normalize, data, now)
		if success then
			state = result
		else
			warn("Save ilegível de " .. player.Name .. ":", result)
			loadFailed = true
		end
	end
	if loadFailed then
		-- Não sobrescreve um save que não deu para ler: o jogador joga sem salvar nesta sessão.
		warn("Não deu para carregar o reino de " .. player.Name .. "; esta sessão não vai salvar.")
	end
	local hasSave = state ~= nil
	state = state or State.createState({ now = now })
	local s = { events = {}, lastSave = os.clock(), calls = 0, loadFailed = loadFailed, hasSave = hasSave, sendExtra = true }
	-- Preferências e backups (chaves à parte; se a leitura falhar, não grava por cima).
	local rawConfig = loadKey(configKey(player))
	s.config = type(rawConfig) == "table" and normalizeConfig(rawConfig) or defaultConfig()
	s.configFailed = rawConfig == false
	local rawBackups = loadKey(backupKey(player))
	s.backupsFailed = rawBackups == false
	s.backups = type(rawBackups) == "table" and rawBackups or { next = 0, lastAt = 0, slots = {} }
	if PolicyService then
		task.spawn(function()
			local okPolicy, info = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			if okPolicy and type(info) == "table" then s.policy = info end
		end)
	end
	setState(s, state)
	if loadFailed then
		table.insert(s.events, { "toast", { text = "Não deu para carregar seu reino agora. O progresso desta sessão não será salvo.", kind = "bad" } })
	end
	sessions[player] = s
	-- O primeiro tick (em setState) já calculou a produção offline e avisou.
	push(player)
end

Players.PlayerAdded:Connect(start)
for _, p in Players:GetPlayers() do
	task.spawn(start, p)
end

Players.PlayerRemoving:Connect(function(player)
	local s = sessions[player]
	if s then
		s.game:tick(nowMs())
		save(player)
		saveConfig(player)
	end
	sessions[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			save(player)
			saveConfig(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.2)
	end
end)

-- ------------------------------------------------------------ ações pedidas pelo cliente
-- Só estas funções do Game podem ser chamadas; o Game valida cada argumento.
-- Fora da lista de propósito: secret (o cliente usa uiSecret), creditPurchasedGems (só o recibo de compra),
-- tick/catchUp/grant/addXp e os outros métodos internos.
local ACTIONS = {
	build = true, upgrade = true, upgradeMax = true, upgradeAll = true, sell = true, move = true, clear = true, plant = true, expand = true,
	repair = true, repairAll = true,
	recruit = true, toggleCouncil = true, startExpedition = true, collectExpedition = true, speedUpExpedition = true,
	trainHero = true, speedUpTraining = true, openChest = true, claimMission = true, claimTier = true, claimDaily = true,
	ascend = true, buyTalent = true, undoBuild = true, dig = true, digStairs = true, buildRoom = true, upgradeRoom = true,
	sellRoom = true, equip = true, buyCosmetic = true, greetRival = true, tradeRival = true,
	buyShop = true, uiSecret = true,
}

local function filterName(player, name)
	if type(name) ~= "string" then return nil, "Nome vazio" end
	name = string.sub(name, 1, 24)
	local success, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not success then return nil, "Não deu para conferir o nome agora" end
	return filtered
end

local function setName(player, s, name)
	local filtered, reason = filterName(player, name)
	if not filtered then return { ok = false, reason = reason } end
	return s.game:setKingdomName(filtered)
end

local function callGame(s, name, ...)
	local success, r = pcall(s.game[name], s.game, ...)
	if success then
		return type(r) == "table" and r or { ok = true, value = r }
	end
	warn("Ação " .. name .. " falhou:", r)
	return { ok = false, reason = "Algo deu errado" }
end

-- Reino novo (Novo reino, Apagar o reino atual): opts = { name, banner } opcionais, como o startKingdom do web.
local function newKingdom(player, s, opts)
	writeBackup(player, true)
	local g = setState(s, State.createState({ seed = State.newSeed(), now = nowMs() }))
	s.hasSave = true
	s.sendExtra = true
	if type(opts) == "table" then
		if type(opts.name) == "string" and opts.name ~= "" then
			local filtered = filterName(player, opts.name)
			if filtered then g:setKingdomName(filtered) end
		end
		if type(opts.banner) == "string" then g:equip("banner", opts.banner) end
	end
	task.spawn(save, player)
	return { ok = true }
end

local SPECIAL = {}

-- A tela acabou de abrir: manda tudo de novo, inclusive o subsolo e as preferências.
function SPECIAL.sync(_player, s)
	s.lastUnder = nil
	s.sendExtra = true
	return { ok = true }
end

function SPECIAL.setKingdomName(player, s, name)
	return setName(player, s, name)
end

function SPECIAL.setConfig(_player, s, cfg)
	if type(cfg) ~= "table" then return { ok = false, reason = "Inválido" } end
	s.config = normalizeConfig(cfg)
	s.configDirtyAt = os.clock()
	-- Não devolve a config no próximo envio: o cliente já a aplicou, e com o slider sendo arrastado
	-- uma resposta atrasada voltaria o valor para trás. Ela volta no próximo "sync" (tela reaberta).
	return { ok = true, config = s.config }
end

function SPECIAL.newGame(player, s, opts)
	return newKingdom(player, s, opts)
end

function SPECIAL.hardReset(player, s)
	return newKingdom(player, s, nil)
end

function SPECIAL.exportSave(_player, s)
	s.game:tick(nowMs())
	local success, code = pcall(Storage.exportCode, s.game.state)
	if not success then
		warn("Exportar falhou:", code)
		return { ok = false, reason = "Algo deu errado" }
	end
	return { ok = true, code = code }
end

function SPECIAL.importSave(player, s, code)
	if type(code) ~= "string" or #code > 4000000 then return { ok = false, reason = "Save inválido: Save vazio" } end
	local success, result = pcall(Storage.importCode, code, nowMs())
	if not success then
		return { ok = false, reason = "Save inválido: " .. Storage.cleanError(result) }
	end
	writeBackup(player, true)
	setState(s, result.state)
	s.hasSave = true
	s.sendExtra = true
	task.spawn(save, player)
	return { ok = true }
end

function SPECIAL.listBackups(_player, s)
	return { ok = true, backups = listBackups(s), slots = BACKUP_SLOTS }
end

function SPECIAL.restoreBackup(player, s, slot)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 0 or slot >= BACKUP_SLOTS then
		return { ok = false, reason = "Backup ilegível: slot inválido" }
	end
	local b = s.backups and s.backups.slots and s.backups.slots[slot + 1]
	if type(b) ~= "table" then return { ok = false, reason = "Backup ilegível: Save vazio" } end
	local success, st = pcall(State.normalize, b.data, nowMs())
	if not success then return { ok = false, reason = "Backup ilegível: " .. Storage.cleanError(st) } end
	setState(s, st)
	s.hasSave = true
	s.sendExtra = true
	task.spawn(save, player)
	return { ok = true }
end

-- Ascender troca o reino: guarda um backup do reino que acaba antes.
function SPECIAL.ascend(player, s)
	if s.game:crownsOnAscend() >= 1 then writeBackup(player, true) end
	return callGame(s, "ascend")
end

-- Pacotes de gemas: desligados (Shop.PAYMENTS_ENABLED). Respeita a política do país antes de qualquer coisa.
function SPECIAL.buyGemPack(_player, s, id)
	if s.policy and s.policy.ArePaidRandomItemsRestricted then
		return { ok = false, reason = "Compra de gemas indisponível na sua região" }
	end
	return callGame(s, "buyGemPack", id)
end

-- Visitar um reino conta uma vez por reino por dia; limita a quantidade para a estatística não ser inflada.
function SPECIAL.recordVisit(_player, s, key)
	if type(key) ~= "string" or key == "" or #key > 64 then return { ok = false, reason = "Inválido" } end
	local visited = s.game.state.social.visited
	if visited then
		local today, n = Util.dayKey(nowMs()), 0
		for _, day in visited do
			if day == today then n += 1 end
		end
		if n >= 40 and visited[key] ~= today then return { ok = true, value = false } end
	end
	return callGame(s, "recordVisit", key)
end

-- Resgatar todos os níveis do passe de uma vez (claimAllTiers do web): um aviso só no fim.
function SPECIAL.claimAllTiers(_player, s)
	local g = s.game
	local max = math.min(Seasons.SEASON_TIERS, Season.tierOf(g.state.season.xp))
	local labels = {}
	g.quiet = true
	pcall(function()
		for t = 1, max do
			if not table.find(g.state.season.claimed, t) then
				local r = g:claimTier(t)
				if r.ok then table.insert(labels, r.reward.label) end
			end
		end
	end)
	g.quiet = false
	return { ok = true, labels = labels }
end

-- "Salvar e voltar ao menu principal".
function SPECIAL.save(player, s)
	if os.clock() - s.lastSave > 5 then task.spawn(save, player) end
	return { ok = true }
end

acao.OnServerInvoke = function(player, name, ...)
	local s = sessions[player]
	if not s or type(name) ~= "string" then return { ok = false, reason = "Reino ainda carregando" } end
	-- Limite simples contra spam: 30 ações por segundo.
	s.calls += 1
	if s.calls > 30 then return { ok = false, reason = "Calma!" } end
	s.game.now = nowMs()
	local result
	local special = SPECIAL[name]
	if special then
		local success, r = pcall(special, player, s, ...)
		if success then
			result = r
		else
			warn("Ação " .. name .. " falhou:", r)
			result = { ok = false, reason = "Algo deu errado" }
		end
	elseif ACTIONS[name] then
		result = callGame(s, name, ...)
	else
		result = { ok = false, reason = "Ação desconhecida" }
	end
	push(player)
	return result
end

-- ------------------------------------------------------------ relógio do reino
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then return end
	acc = 0
	local now = nowMs()
	for player, s in sessions do
		s.calls = 0
		local success, e = pcall(function()
			s.game:tick(now, true)
		end)
		if not success then warn("Tick falhou:", e) end
		push(player)
		if os.clock() - s.lastSave > SAVE_EVERY then
			task.spawn(function()
				save(player)
				writeBackup(player, false)
			end)
		end
		if s.configDirtyAt and os.clock() - s.configDirtyAt > CONFIG_DEBOUNCE then
			task.spawn(saveConfig, player)
		end
	end
end)
