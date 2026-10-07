-- Servidor do Reino de Bolso no Roblox.
-- Cada jogador tem o próprio reino (um Game do porte), que roda aqui no servidor e é salvo no DataStore.
-- O cliente (ReinoCliente) só mostra o estado e pede ações pelo RemoteFunction "Acao".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Game = require(Reino.Core.Game)
local State = require(Reino.Core.State)

Players.CharacterAutoLoads = false -- o jogo é só a tela do reino, sem boneco andando

local SAVE_EVERY = 60 -- segundos entre salvamentos automáticos
local TICK = 1 -- segundos entre ticks do reino (o jogo web também usa 1 s)
local store = nil
local ok, err = pcall(function()
	store = DataStoreService:GetDataStore("ReinoDeBolso_v1")
end)
if not ok then
	warn("DataStore indisponível (no Studio, ligue Game Settings > Security > Enable Studio Access to API Services). O progresso não será salvo.", err)
end

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

local sessions = {} -- [Player] = { game, events, lastUnder, lastSave, calls }

-- ------------------------------------------------------------ salvar e carregar
local function keyFor(player)
	return "reino_" .. player.UserId
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

local function load(player)
	if not store then return nil end
	local success, data = withRetry(function()
		return store:GetAsync(keyFor(player))
	end)
	if not success then return false end
	return data
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
	data.raidStrength = s.game:raidStrength()
	return data
end

local function push(player)
	local s = sessions[player]
	if not s then return end
	local events = s.events
	s.events = {}
	estado:FireClient(player, snapshot(s), events, nowMs())
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
	state = state or State.createState({ now = now })
	local g = Game.new(state, now)
	local s = { game = g, events = {}, lastSave = os.clock(), calls = 0, loadFailed = loadFailed }
	g:onAny(function(evt, payload)
		table.insert(s.events, { evt, payload })
	end)
	if loadFailed then
		table.insert(s.events, { "toast", { text = "Não deu para carregar seu reino agora. O progresso desta sessão não será salvo.", kind = "bad" } })
	end
	sessions[player] = s
	-- Primeiro tick: se o jogador ficou fora, calcula a produção offline e avisa.
	g:tick(nowMs())
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
	end
	sessions[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			save(player)
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
local ACTIONS = {
	build = true, upgrade = true, upgradeMax = true, upgradeAll = true, sell = true, move = true, clear = true, plant = true, expand = true,
	recruit = true, toggleCouncil = true, startExpedition = true, collectExpedition = true, speedUpExpedition = true,
	trainHero = true, speedUpTraining = true, openChest = true, claimMission = true, claimTier = true, claimDaily = true,
	ascend = true, buyTalent = true, undoBuild = true, dig = true, digStairs = true, buildRoom = true, upgradeRoom = true,
	sellRoom = true, equip = true, buyCosmetic = true, greetRival = true, tradeRival = true,
}

local function setName(player, s, name)
	if type(name) ~= "string" then return { ok = false, reason = "Nome vazio" } end
	name = string.sub(name, 1, 24)
	local success, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not success then return { ok = false, reason = "Não deu para conferir o nome agora" } end
	return s.game:setKingdomName(filtered)
end

acao.OnServerInvoke = function(player, name, ...)
	local s = sessions[player]
	if not s or type(name) ~= "string" then return { ok = false, reason = "Reino ainda carregando" } end
	-- Limite simples contra spam: 30 ações por segundo.
	s.calls += 1
	if s.calls > 30 then return { ok = false, reason = "Calma!" } end
	s.game.now = nowMs()
	local result
	if name == "sync" then
		-- A tela acabou de abrir: manda tudo de novo, inclusive o subsolo.
		s.lastUnder = nil
		result = { ok = true }
	elseif name == "setKingdomName" then
		result = setName(player, s, ...)
	elseif ACTIONS[name] then
		local success, r = pcall(s.game[name], s.game, ...)
		if success then
			result = type(r) == "table" and r or { ok = true, value = r }
		else
			warn("Ação " .. name .. " falhou:", r)
			result = { ok = false, reason = "Algo deu errado" }
		end
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
			task.spawn(save, player)
		end
	end
end)
