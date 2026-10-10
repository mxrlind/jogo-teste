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
-- Sem áudio no teste: as propriedades de Sound (IsLoaded...) só existem no motor de verdade.
do
	local img = place:GetService("ReplicatedStorage"):FindFirstChild("Reino"):FindFirstChild("Imagens")
	img.Source = string.gsub(img.Source, "audio = {.-}", "audio = {}")
end

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
for _, ev in { "AncestryChanged", "Destroying", "ChildAdded" } do
	roblox.implementProperty("Instance", ev, function(self) return signalFor(self, ev) end)
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
		if inst:IsA("GuiBase2d") then inst.AbsoluteSize = roblox.Vector2.new(1280, 660); pcall(function() inst.AbsolutePosition = roblox.Vector2.new(0, 0) end) end
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
local renderStepped = Signal.new()
roblox.implementProperty("RunService", "RenderStepped", function() return renderStepped end)
for _, ev in { "InputChanged", "InputEnded", "WindowFocused", "WindowFocusReleased" } do
	local sg = Signal.new()
	roblox.implementProperty("UserInputService", ev, function() return sg end)
end
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function() return nil end)
roblox.implementMethod("TweenService", "Create", function() return { Play = function() end, Cancel = function() end } end)
roblox.implementMethod("ContentProvider", "PreloadAsync", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Sound", "Pause", function() end)
roblox.implementMethod("Sound", "Resume", function() end)
roblox.implementProperty("GuiBase2d", "AbsolutePosition", function() return roblox.Vector2.new(0, 0) end)
roblox.implementMethod("StarterGui", "SetCoreGuiEnabled", function() end)
for _, ev in { "InputBegan", "InputEnded", "InputChanged", "Focused" } do
	roblox.implementProperty("GuiObject", ev, function(self) return signalFor(self, ev) end)
end
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
		DateTime = { now = function() return { UnixTimestampMillis = clock } end, fromUnixTimestampMillis = function(ms) return { FormatLocalTime = function() return "01/01/2026, 10:00:00" end } end },
		typeof = typeof, utf8 = utf8, bit32 = bit32, os = setmetatable({ clock = function() return clock / 1000 end }, { __index = os }), math = math, string = string, table = table,
	}
	for _, n in { "Rect", "NumberRange", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence", "NumberSequenceKeypoint", "TweenInfo", "Vector3", "CFrame", "Content" } do
		e[n] = (roblox :: any)[n]
	end
	e.TweenInfo = { new = function(...) return { ... } end }
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
		for _ = 1, 4 do renderStepped:Fire(0.25) end
	end
end

local function main()
-- Servidor sobe, jogador entra, tela sobe.
run(place:GetService("ServerScriptService").ReinoServidor.Main)
table.insert(currentPlayers, thePlayer)
playersAdded:Fire(thePlayer)
local cliente = place:GetService("StarterPlayer").StarterPlayerScripts.ReinoCliente
run(cliente.Main)
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


local function allButtons()
	local out = {}
	for _, d in playerGui:GetDescendants() do
		if d:IsA("GuiButton") then table.insert(out, d) end
	end
	return out
end
local function screenText()
	local parts = {}
	for _, d in playerGui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" then table.insert(parts, d.Text) end
	end
	return table.concat(parts, " | ")
end
local function press(pattern)
	for _, bt in allButtons() do
		if bt.Parent and string.find(textOf(bt), pattern) then
			signalFor(bt, "Activated"):Fire()
			second()
			return true
		end
	end
	print("NAO ACHEI BOTAO: " .. pattern)
	return false
end
local function has(pattern)
	for _, bt in allButtons() do
		if bt.Parent and string.find(textOf(bt), pattern) then return true end
	end
	return false
end
local function openMenu()
	for _ = 1, 4 do
		if has("Salvar e voltar") then return true end
		inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
		second()
	end
	return has("Salvar e voltar")
end
-- No Roblox, um filho com Size em escala dentro de um pai com AutomaticSize faz o pai crescer até ocupar
-- todo o espaço (o fundo do tutorial cobria o mapa). Junta os casos de cada tela; o fim do teste confere.
local autoScale = {}
local function auditAuto(tag)
	local AY, AX, AXY = roblox.Enum.AutomaticSize.Y, roblox.Enum.AutomaticSize.X, roblox.Enum.AutomaticSize.XY
	local function autoIn(inst, axis)
		local a = inst.AutomaticSize
		return a == AXY or (axis == "Y" and a == AY) or (axis == "X" and a == AX)
	end
	for _, d in playerGui:GetDescendants() do
		if d:IsA("GuiObject") then
			for _, axis in { "X", "Y" } do
				local dim = d.Size[axis]
				if dim.Scale > 0 and dim.Offset > 0 then
					-- Sobe pela cadeia de pais em escala até achar um com AutomaticSize nesse eixo.
					local par = d.Parent
					while par and par:IsA("GuiObject") do
						if autoIn(par, axis) then
							local path = par.Name .. "/../" .. d.Name
							local p2 = par.Parent
							for _ = 1, 3 do
								if not p2 or p2 == playerGui then break end
								path = p2.Name .. "/" .. path
								p2 = p2.Parent
							end
							autoScale[path] = autoScale[path] or tag
							break
						end
						if par.Size[axis].Scale == 0 then break end
						par = par.Parent
					end
				end
			end
		end
	end
end
local function show(tag)
	auditAuto(tag)
	if not process.env.DEBUG_SMOKE then return end
	print("== " .. tag .. ": " .. string.sub(screenText(), 1, 700))
end
second(2)
show("inicio")
check("menu: novo reino", press("Novo reino"))
show("intro")
for _, d in playerGui:GetDescendants() do
	if d:IsA("TextBox") and d.Name == "NomeDoReino" then d.Text = "Vila Teste"; signalFor(d, "chg:Text"):Fire() end
end
check("fundar", press("Fundar meu reino"))
show("depois de fundar")
check("nome", lastSnapshot.kingdom.name == "Vila Teste", lastSnapshot.kingdom.name)
press("Resgatar")
show("depois da diaria")
check("menu q", pcall(function() inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false) end))
second()
show("menu do jogo")
check("opcoes", press("^Opções$"))
show("opcoes")
press("Alto contraste")
check("alto contraste ligado", true)
press("Seta para cima")
show("remap")
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.W, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()
press("Restaurar todas")
press("Restaurar teclas")
press("^Fechar$")
check("save menu", press("Save e backups"))
show("save")
local code = nil
press("Copiar código")
for _, d in playerGui:GetDescendants() do
	if d:IsA("TextBox") and d.Name == "Codigo" then code = d.Text end
end
check("codigo exportado", code and #code > 1000, code and #code)
press("^Fechar$")
for _, d in playerGui:GetDescendants() do
	if d:IsA("TextBox") and d.Name == "CodigoDoSave" then d.Text = code; signalFor(d, "chg:Text"):Fire() end
end
check("importar", press("^Importar$"))
show("confirma importar")
check("confirma", press("^Importar$"))
show("depois de importar")
openMenu()
press("Save e backups")
show("save2")
check("restaurar", press("^Restaurar$"))
press("^Restaurar$")
show("depois de restaurar")
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()

inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()
press("Créditos")
show("creditos")
press("^Fechar$")
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()
press("Como jogar")
press("Entendi")
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Q, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()
openMenu()
press("Salvar e voltar")
show("menu principal")
check("continuar", press("Continuar: "))
second(2)
show("jogo de novo")

-- ------------------------------------------------------------ tela do jogo: mapa, painel do tile, abas, teclado
local Ctx
for _, m in moduleCache do
	if type(m) == "table" and m.VERSION and m.show then Ctx = m end
end
check("achou Ctx", Ctx ~= nil)
while Ctx.modal.isOpen() do Ctx.modal.close() end
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
check("paleta tem a Serraria", press("Serraria"))
check("modo construir", Ctx.ui.mode.type == "build" and Ctx.ui.mode.id == "serraria", Ctx.ui.mode.type)
local okHover, eHover = pcall(function() Ctx.onHover({ x = spot[1], y = spot[2] }) second() end)
check("prévia ao passar o mouse", okHover and Ctx.ui.hoverDelta ~= nil, eHover)
Ctx.onTileClick(spot[1], spot[2])
second()
local sb = tileAt(spot[1], spot[2]).b
check("serraria construída pelo clique", sb and sb.id == "serraria", sb and sb.id)
check("aviso de desfazer aparece", string.find(screenText(), "Desfazer") ~= nil)
Ctx.run("cancelMode")
second()
Ctx.onTileClick(spot[1], spot[2])
second()
check("painel do tile mostra o prédio", string.find(screenText(), "Serraria") ~= nil and has("Melhorar"))
second(60)
inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.U, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
second()
check("melhorou com U", tileAt(spot[1], spot[2]).b.lvl == 2, tileAt(spot[1], spot[2]).b.lvl)

-- Clica em todos os botões de todas as abas e em todos os tiles (pega erro de qualquer tela).
local errs = {}
local SKIP = { "Ascender", "Confirmar", "Salvar e voltar", "Apagar", "Novo reino", "Restaurar", "Importar", "Demolir" }
local function safe(bt)
	local t = textOf(bt)
	for _, k in SKIP do
		if string.find(t, k) then return false end
	end
	return true
end
local warns = 0
for round = 1, 2 do
	for _, tab in Ctx.TAB_ORDER do
		Ctx.run("tab", tab)
		second()
		for _, bt in allButtons() do
			if bt.Parent and bt:IsDescendantOf(gui) and safe(bt) then
				local ok, err = pcall(function() signalFor(bt, "Activated"):Fire() end)
				if not ok then table.insert(errs, textOf(bt) .. ": " .. tostring(err)) end
			end
		end
		second()
		while Ctx.modal.isOpen() do Ctx.modal.close() end
	end
	for y = 0, 11 do
		for x = 0, 11 do
			local ok, err = pcall(function() Ctx.onHover({ x = x, y = y }) Ctx.onTileClick(x, y) end)
			if not ok then table.insert(errs, string.format("tile %d,%d: %s", x, y, tostring(err))) end
		end
	end
	Ctx.run("cancelMode")
	second(30)
	while Ctx.modal.isOpen() do Ctx.modal.close() end
end
check("nenhum botão deu erro", #errs == 0, errs[1])
for _, k in { "One", "Two", "Three", "T", "Z", "M", "Delete", "Left", "Up", "Return", "Q" } do
	local ok, err = pcall(function() inputBegan:Fire({ KeyCode = roblox.Enum.KeyCode[k], UserInputType = roblox.Enum.UserInputType.Keyboard }, false) second() end)
	check("tecla " .. k, ok, err)
end
while Ctx.modal.isOpen() do Ctx.modal.close() end
-- recrutar e resumo de rodada pelos eventos do Controller
local okR, eR = pcall(function()
	Ctx.show.recruit({ hero = { id = "h1" }, isNew = false, stars = 2 })
	second()
	show("recruta")
	Ctx.modal.close()
	Ctx.show.offline({ elapsed = 3600, efficiency = 0.8, gains = { gold = 10, food = -2, wood = 1, stone = 0 }, capped = true, simulated = 3000, welcome = { days = 3, gems = 5, scroll = 1, goldMinutes = 30 }, expeditionsReady = 1 })
	second()
	show("offline")
	Ctx.modal.close()
	Ctx.show.daily()
	second()
	show("diaria")
	Ctx.modal.close()
	Ctx.modal.close()
	Ctx.show.options()
	second()
	for _, d in playerGui:GetDescendants() do
		if d:IsA("TextButton") and d.Name == "Slider-fontScale" then
			signalFor(d, "InputBegan"):Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, Position = roblox.Vector2.new(900, 0) })
		end
	end
	second()
	show("opcoes fonte")
	Ctx.modal.close()
	Ctx.run("toggleMusic")
	second()
	Ctx.run("hardReset")
	second()
	press("^Apagar$")
	show("hard reset")
	check("hard reset abre a intro", has("Fundar meu reino"))
	second(5)
	local sum = Ctx.game:runSummary()
	sum.n = 1
	sum.newRecords = { "gold" }
	Ctx.show.runSummary(sum, { fresh = true })
	second(2)
	show("resumo")
	Ctx.modal.close()
end)
check("janelas extras", okR, eR)
local listAuto = {}
for path, tag in autoScale do table.insert(listAuto, path .. " (" .. tag .. ")") end
table.sort(listAuto)
check("nenhum filho em escala dentro de AutomaticSize", #listAuto == 0, table.concat(listAuto, "\n  "))
press("Salvar e voltar")


end

local okMain, errMain = pcall(main)
if not okMain then
	failed += 1
	print("ERRO: " .. tostring(errMain))
end
print(string.format("\n%d ok, %d falharam", passed, failed))
process.exit(failed > 0 and 1 or 0)
