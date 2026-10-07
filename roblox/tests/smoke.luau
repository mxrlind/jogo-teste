-- Teste de fumaça: roda o servidor e a tela de verdade num Roblox simulado (Lune + place gerado pelo Rojo).
-- As Instances são as do Lune, que conferem nome e tipo de cada propriedade com a base de dados do Roblox;
-- eventos, DataStore e remotes são simulados aqui. Pega erro de digitação, nil e propriedade errada,
-- coisas que só apareceriam ao dar Play no Studio.
-- Uso (na pasta roblox/): lune run tests/smoke
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local PLACE = "/tmp/reino-smoke.rbxl"
local built = process.exec("rojo", { "build", "default.project.json", "-o", PLACE })
assert(built.ok, built.stderr)
local place = roblox.deserializePlace(fs.readFile(PLACE))

-- ------------------------------------------------------------ sinais simulados
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ fns = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self.fns, fn)
	local fns = self.fns
	return { Disconnect = function() local i = table.find(fns, fn) if i then table.remove(fns, i) end end }
end
function Signal:Fire(...)
	for _, fn in table.clone(self.fns) do fn(...) end
end
function Signal:Wait() error("Wait não simulado") end

-- O Lune pode devolver objetos Lua diferentes para a mesma Instance: a chave é um id guardado nela.
local signals = {}
local nextId = 0
local function keyOf(inst)
	local id = inst:GetAttribute("__smokeId")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__smokeId", id)
	end
	return id
end
local function signalFor(inst, name)
	local k = keyOf(inst)
	signals[k] = signals[k] or {}
	signals[k][name] = signals[k][name] or Signal.new()
	return signals[k][name]
end
for _, ev in { "MouseButton1Click", "MouseEnter", "MouseLeave", "Activated", "FocusLost" } do
	roblox.implementProperty("GuiObject", ev, function(self) return signalFor(self, ev) end)
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, prop) return signalFor(self, "chg:" .. prop) end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local c = self:FindFirstChild(name)
	assert(c, "WaitForChild ficaria esperando para sempre: " .. name .. " em " .. self:GetFullName())
	return c
end)
-- Instance.new das telas: já nasce com um tamanho de tela (no Roblox, quem calcula é o motor).
local FakeInstance = {
	new = function(class)
		local inst = roblox.Instance.new(class)
		if inst:IsA("GuiBase2d") then inst.AbsoluteSize = roblox.Vector2.new(1280, 660) end
		return inst
	end,
}

-- ------------------------------------------------------------ serviços simulados
local clock = 1791385200000
local Players = place:GetService("Players")
local RunService = place:GetService("RunService")
local UIS = place:GetService("UserInputService")
local playersAdded, playersRemoving = Signal.new(), Signal.new()
local currentPlayers = {}
roblox.implementProperty("Players", "PlayerAdded", function() return playersAdded end)
roblox.implementProperty("Players", "PlayerRemoving", function() return playersRemoving end)
roblox.implementMethod("Players", "GetPlayers", function() return table.clone(currentPlayers) end)
local heartbeat = Signal.new()
roblox.implementProperty("RunService", "Heartbeat", function() return heartbeat end)
local inputBegan = Signal.new()
roblox.implementProperty("UserInputService", "InputBegan", function() return inputBegan end)

roblox.implementMethod("DataModel", "BindToClose", function() end)
roblox.implementMethod("HttpService", "JSONEncode", function(_, v) return serde.encode("json", v) end)
roblox.implementMethod("TextService", "FilterStringAsync", function(_, text)
	return { GetNonChatStringForBroadcastAsync = function() return text end }
end)
local saved = {}
local saves = 0
roblox.implementMethod("DataStoreService", "GetDataStore", function()
	return {
		GetAsync = function(_, key) return saved[key] and serde.decode("json", saved[key]) end,
		SetAsync = function(_, key, value)
			saves += 1
			saved[key] = serde.encode("json", value) -- o DataStore real também passa por JSON
		end,
	}
end)

local thePlayer = roblox.Instance.new("Player")
thePlayer.Name = "Josue"
thePlayer.UserId = 102836778
-- Propriedades que o Lune não deixa trocar (LocalPlayer, TouchEnabled...) vêm de um "embrulho" do serviço.
local overrides = {
	Players = { LocalPlayer = thePlayer },
	UserInputService = { TouchEnabled = false, MouseEnabled = true },
}
local function wrapService(inst)
	local o = overrides[inst.ClassName]
	if not o then return inst end
	return setmetatable({}, {
		__index = function(_, k)
			if o[k] ~= nil then return o[k] end
			local v = inst[k]
			if type(v) == "function" then return function(_, ...) return v(inst, ...) end end
			return v
		end,
		__newindex = function(_, k, v) inst[k] = v end,
	})
end
local fakeGame = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then return function(_, name) return wrapService(place:GetService(name)) end end
		local v = place[k]
		if type(v) == "function" then return function(_, ...) return v(place, ...) end end
		return v
	end,
})
local playerGui = roblox.Instance.new("PlayerGui")
playerGui.Parent = thePlayer

-- Remotes: InvokeServer chama a função do servidor na hora; FireClient chama a tela.
local callbacks = {}
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self) return callbacks[keyOf(self)] end, function(self, fn) callbacks[keyOf(self)] = fn end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
	-- Os argumentos também passam por cópia, como na rede do Roblox.
	local args = table.pack(...)
	return callbacks[keyOf(self)](thePlayer, table.unpack(args, 1, args.n))
end)
local lastSnapshot = nil
roblox.implementProperty("RemoteEvent", "OnClientEvent", function(self) return signalFor(self, "OnClientEvent") end)
roblox.implementMethod("RemoteEvent", "FireClient", function(self, _player, snap, ...)
	-- Os remotes do Roblox também copiam os dados (nada de tabela compartilhada entre servidor e cliente).
	lastSnapshot = serde.decode("json", serde.encode("json", snap))
	local copy = serde.decode("json", serde.encode("json", snap))
	if process.env.DEBUG_SMOKE then print("FireClient ->", #signalFor(self, "OnClientEvent").fns, "ouvintes") end
	signalFor(self, "OnClientEvent"):Fire(copy, ...)
end)

-- ------------------------------------------------------------ rodar scripts
local moduleCache = {}
local function env(scriptInst)
	local e = {
		game = fakeGame, script = scriptInst, workspace = place:GetService("Workspace"), Instance = FakeInstance, Enum = roblox.Enum,
		UDim = roblox.UDim, UDim2 = roblox.UDim2, Color3 = roblox.Color3, Vector2 = roblox.Vector2, Font = roblox.Font,
		task = task, warn = function(...) print("[warn]", ...) end,
		DateTime = { now = function() return { UnixTimestampMillis = clock } end },
	}
	e.require = function(target)
		if typeof(target) == "Instance" then
			if moduleCache[target] == nil then
				local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = env(target) })
				moduleCache[target] = chunk()
			end
			return moduleCache[target]
		end
		return require(target)
	end
	return e
end
local function run(scriptInst)
	luau.load(scriptInst.Source, { debugName = scriptInst:GetFullName(), environment = env(scriptInst) })()
end

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1 print("FALHOU: " .. name .. (detail and (" — " .. tostring(detail)) or "")) end
end

local function second(n)
	for _ = 1, n or 1 do
		clock += 1000
		heartbeat:Fire(1)
	end
end

local function main()
-- Servidor sobe, jogador entra, tela sobe.
run(place:GetService("ServerScriptService").ReinoServidor.Main)
table.insert(currentPlayers, thePlayer)
playersAdded:Fire(thePlayer)
local cliente = place:GetService("StarterPlayer").StarterPlayerScripts.ReinoCliente
run(cliente.Ui)
second()
local gui = playerGui:FindFirstChild("ReinoDeBolso")
check("a tela foi criada", gui ~= nil)
-- O estado vai pela rede a cada segundo: precisa ser pequeno (o Roblox recomenda bem menos de 50 KB/s).
local size = #serde.encode("json", lastSnapshot)
check("estado por segundo tem menos de 20 KB", size < 20000, size)
print("tamanho do estado com subsolo: " .. size .. " bytes")
check("o servidor mandou o estado", lastSnapshot ~= nil)

-- ------------------------------------------------------------ achar coisas na tela
local function textOf(inst)
	local parts = {}
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then table.insert(parts, inst.Text) end
	for _, d in inst:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then table.insert(parts, d.Text) end
	end
	return table.concat(parts, " ")
end
local function buttons()
	local out = {}
	for _, d in gui:GetDescendants() do
		if d:IsA("TextButton") then table.insert(out, d) end
	end
	return out
end
local function click(pattern)
	for _, b in buttons() do
		if string.find(textOf(b), pattern) then
			signalFor(b, "MouseButton1Click"):Fire()
			return true
		end
	end
	return false
end
local function tileButton(x, y)
	for _, b in buttons() do
		if b.ZIndex == 50 and b.Position == roblox.UDim2.fromScale(x / 12, y / 12) then return b end
	end
	return nil
end
local function tileAt(x, y) return lastSnapshot.grid.tiles[y * 12 + x + 1] end
local function ringOf(x, y) return math.max(math.abs(x - 5.5), math.abs(y - 5.5)) - 0.5 end

-- Construir uma serraria encostada numa floresta, pela paleta e pelo mapa.
local spot = nil
for y = 0, 11 do
	for x = 0, 11 do
		local t = tileAt(x, y)
		if not spot and t.t == "grass" and not t.b and ringOf(x, y) <= 2 then
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = x + d[1], y + d[2]
				if nx >= 0 and ny >= 0 and nx < 12 and ny < 12 and tileAt(nx, ny).t == "forest" then spot = { x, y } end
			end
		end
	end
end
check("achou lugar para a serraria", spot ~= nil)
if process.env.DEBUG_SMOKE then
	local n = 0
	for _, bt in buttons() do
		n += 1
		if bt.ZIndex ~= 50 then print("botão:", textOf(bt)) end
	end
	print("botões:", n)
	print("tela:", string.sub(textOf(gui), 1, 400))
end
check("clicou na serraria da paleta", click("Serraria"))
local hit = tileButton(spot[1], spot[2])
check("achou o tile no mapa", hit ~= nil)
signalFor(hit, "MouseEnter"):Fire()
check("prévia aparece ao passar o mouse", string.find(textOf(gui), "Serraria aqui") ~= nil)
signalFor(hit, "MouseButton1Click"):Fire()
local b = tileAt(spot[1], spot[2]).b
check("serraria construída pelo clique", b and b.id == "serraria", b and b.id)
check("botão Desfazer aparece", string.find(textOf(gui), "Desfazer") ~= nil)

-- Selecionar o prédio e melhorar pelo teclado.
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Escape }, false)
signalFor(hit, "MouseButton1Click"):Fire()
check("inspetor mostra o prédio", string.find(textOf(gui), "Serraria · nível 1") ~= nil)
lastSnapshot.res = lastSnapshot.res
second(60)
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.U }, false)
check("melhorou com U", tileAt(spot[1], spot[2]).b.lvl == 2, tileAt(spot[1], spot[2]).b.lvl)

-- Constrói pelo servidor no primeiro lugar que der (para avançar o jogo no teste).
local function buildAnywhere(id)
	local acaoRemote = place:GetService("ReplicatedStorage").ReinoRemotes.Acao
	for y = 0, 11 do
		for x = 0, 11 do
			local t = tileAt(x, y)
			if t.t == "grass" and not t.b and ringOf(x, y) <= lastSnapshot.grid.ring then
				local r = acaoRemote:InvokeServer("build", id, x, y)
				if r.ok then return true end
			end
		end
	end
	return false
end
check("construiu uma casa pelo remote", buildAnywhere("casa"))
second(3)

-- Heróis: recrutar com o pergaminho grátis (a aba abre depois das primeiras construções).
click("^Heróis$")
check("aba Heróis abriu", string.find(textOf(gui), "Usar pergaminho") ~= nil)
click("Usar pergaminho")
local heroes = 0
for _ in lastSnapshot.heroes.owned do heroes += 1 end
check("recrutou um herói", heroes == 1)

-- Passa por todas as abas e clica em todos os botões que aparecem (pega erro de qualquer tela).
local errors = {}
local tabs = { "^Reino$", "^Heróis$", "^Temporada$", "^Legado$", "^Social$", "^Perfil$" }
for round = 1, 3 do
	for _, tab in tabs do
		click(tab)
		second()
		for _, btn in buttons() do
			if btn.Parent and btn.ZIndex ~= 50 and not string.find(textOf(btn), "^Ascender") and not string.find(textOf(btn), "Confirmar") then
				local ok, err = pcall(function() signalFor(btn, "MouseButton1Click"):Fire() end)
				if not ok then table.insert(errors, textOf(btn) .. ": " .. tostring(err)) end
			end
		end
		second()
	end
	-- Muito ouro para destravar mais telas na próxima volta.
	for y = 0, 11 do
		for x = 0, 11 do
			local hb = tileButton(x, y)
			local ok, err = pcall(function()
				signalFor(hb, "MouseEnter"):Fire()
				signalFor(hb, "MouseButton1Click"):Fire()
				signalFor(hb, "MouseLeave"):Fire()
			end)
			if not ok then table.insert(errors, string.format("tile %d,%d: %s", x, y, tostring(err))) end
		end
	end
	second(30)
end
check("nenhum botão deu erro", #errors == 0, errors[1])

-- Atalhos de teclado.
for _, k in { "One", "Two", "Three", "T", "Z", "M", "Delete", "Escape" } do
	local ok, err = pcall(function() inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode[k] }, false) end)
	check("tecla " .. k, ok, err)
end

-- Subsolo: escadaria abre os botões de nível e a tela do subsolo desenha.
for _ = 1, 4 do buildAnywhere("casa") end
buildAnywhere("fazenda")
second(400) -- junta madeira e pedra para a escadaria
do
	local acaoRemote = place:GetService("ReplicatedStorage").ReinoRemotes.Acao
	for y = 0, 11 do
		for x = 0, 11 do
			if tileAt(x, y).t == "rock" and lastSnapshot.res.stone < 60 then acaoRemote:InvokeServer("clear", x, y) end
		end
	end
	print(string.format("recursos: ouro %d madeira %d pedra %d", lastSnapshot.res.gold, lastSnapshot.res.wood, lastSnapshot.res.stone))
end
local stairsSpot = nil
for y = 0, 11 do
	for x = 0, 11 do
		local t = tileAt(x, y)
		if not stairsSpot and t.t == "grass" and not t.b and ringOf(x, y) <= lastSnapshot.grid.ring then stairsSpot = { x, y } end
	end
end
if stairsSpot then
	-- dá recursos pelo próprio servidor (cheat só no teste)
	local remotes = place:GetService("ReplicatedStorage").ReinoRemotes
	local r = remotes.Acao:InvokeServer("build", "escadaria", stairsSpot[1], stairsSpot[2])
	check("escadaria construída", r.ok, r.reason)
	second()
	local okUnder = click("^Galerias$")
	check("botão Galerias aparece depois da escadaria", okUnder or not r.ok)
	second()
	local okDraw, errDraw = pcall(function()
		for y = 0, 11 do
			for x = 0, 11 do signalFor(tileButton(x, y), "MouseButton1Click"):Fire() end
		end
	end)
	check("subsolo desenha e responde a cliques", okDraw, errDraw)
	click("^Superfície$")
end

-- Sair salva; voltar carrega o mesmo reino e calcula o tempo fora.
local goldBefore = lastSnapshot.res.gold
local builtBefore = lastSnapshot.stats.built
playersRemoving:Fire(thePlayer)
check("salvou ao sair", saved["reino_102836778"] ~= nil)
clock += 3 * 3600 * 1000
local toasts = {}
playersAdded:Fire(thePlayer)
second()
check("voltou com as mesmas construções", lastSnapshot.stats.built == builtBefore, lastSnapshot.stats.built)
check("produziu enquanto estava fora", lastSnapshot.res.gold >= goldBefore, string.format("%s -> %s", goldBefore, lastSnapshot.res.gold))
check("aviso de tempo fora apareceu", string.find(textOf(gui), "Enquanto você esteve fora") ~= nil)
_ = toasts

end

local okMain, errMain = pcall(main)
if not okMain then
	failed += 1
	print("ERRO: " .. tostring(errMain))
end
print(string.format("\n%d ok, %d falharam", passed, failed))
process.exit(failed > 0 and 1 or 0)
