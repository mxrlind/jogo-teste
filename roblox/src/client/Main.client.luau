-- Tela do Reino de Bolso no Roblox: a mesma interface do jogo web (index.html + styles.css + src/ui/).
-- Este script monta o esqueleto (telas, layout em grade, camadas de toasts/modais), recebe o estado do servidor
-- e chama os módulos de Modulos/ para desenhar cada parte. O servidor decide tudo; aqui só se mostra e se pede.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Reino = ReplicatedStorage:WaitForChild("Reino")
local Game = require(Reino.Core.Game)
local Config = require(Reino.Core.Config)

local M = script.Parent:WaitForChild("Modulos")
local Kit = require(M.Kit)
local T = require(M.Theme)
local Ctx = require(M.Ctx)
local Audio = require(M.Audio)
local Toasts = require(M.Toasts)
local Modals = require(M.Modals)
local MapView = require(M.MapView)
local Hud = require(M.Hud)
local Palette = require(M.Palette)
local Stage = require(M.Stage)
local Side = require(M.Side)
local Screens = require(M.Screens)
local Controller = require(M.Controller)

local h = Kit.h

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
end)

-- ------------------------------------------------------------ camadas (ScreenGuis)
local playerGui = player:WaitForChild("PlayerGui")
local function layer(name, order)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order
	g.Parent = playerGui
	return g
end
local mainGui = layer("ReinoDeBolso", 1)
local toastGui = layer("ReinoToasts", 5)
local modalGui = layer("ReinoModal", 10)
local tipGui = layer("ReinoDicas", 20)

-- Sonda da área segura (entalhe e barra de gestos do celular): o tamanho dela com DeviceSafeInsets
-- comparado com a tela inteira dá quanto sobra nas bordas.
local safeGui = layer("ReinoAreaSegura", 0)
pcall(function()
	safeGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
end)

-- Fundo da página: radial-gradient(120% 90% at 50% 0%, #2e2b3a 0%, var(--ink) 60%).
local page = Instance.new("Frame")
page.Name = "Pagina"
page.Size = UDim2.fromScale(1, 1)
page.BackgroundColor3 = Color3.new(1, 1, 1)
page.BorderSizePixel = 0
page.Parent = mainGui
local pageGrad = Instance.new("UIGradient")
pageGrad.Rotation = 90
pageGrad.Parent = page

-- Área útil: abaixo da barra do Roblox (botões do menu e do chat ficam no canto de cima).
local root = Instance.new("Frame")
root.Name = "Raiz"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = mainGui

local function screenFrame(name, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Visible = false
	f.Parent = parent or root
	return f
end
local loadingScreen = screenFrame("Carregando")
local menuScreen = screenFrame("MenuPrincipal")
local gameScreen = screenFrame("Jogo")

-- Jogo: HUD em cima e a grade palette | stage | side (no celular, tudo empilhado com rolagem).
local gameScroll = Instance.new("ScrollingFrame")
gameScroll.Name = "Rolagem"
gameScroll.BackgroundTransparency = 1
gameScroll.BorderSizePixel = 0
gameScroll.Size = UDim2.fromScale(1, 1)
gameScroll.CanvasSize = UDim2.new()
gameScroll.ScrollBarThickness = 0
gameScroll.ScrollingEnabled = false
gameScroll.Parent = gameScreen

local hudFrame = Instance.new("Frame")
hudFrame.Name = "Hud"
hudFrame.BackgroundTransparency = 1
hudFrame.Size = UDim2.fromScale(1, 0)
hudFrame.AutomaticSize = Enum.AutomaticSize.Y
hudFrame.ZIndex = 6
hudFrame.Parent = gameScroll

local layoutFrame = Instance.new("Frame")
layoutFrame.Name = "Layout"
layoutFrame.BackgroundTransparency = 1
layoutFrame.Parent = gameScroll

local function region(name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Parent = layoutFrame
	return f
end
local paletteFrame = region("Paleta")
local stageFrame = region("Palco")
local sideFrame = region("Lado")

local toastFrame = Instance.new("Frame")
toastFrame.Name = "Toasts"
toastFrame.BackgroundTransparency = 1
toastFrame.Size = UDim2.fromScale(1, 1)
toastFrame.Parent = toastGui

local modalFrame = Instance.new("Frame")
modalFrame.Name = "Modal"
modalFrame.BackgroundTransparency = 1
modalFrame.Size = UDim2.fromScale(1, 1)
modalFrame.Parent = modalGui

-- ------------------------------------------------------------ dicas (title="" do HTML)
local tipLabel = nil
local tipFor = nil
Kit.setTipHandler(function(inst, text)
	if text == nil then
		if tipFor == inst and tipLabel then
			tipLabel.Visible = false
		end
		return
	end
	tipFor = inst
	if not tipLabel then
		tipLabel = Instance.new("TextLabel")
		tipLabel.BackgroundColor3 = T.c.ink
		tipLabel.BackgroundTransparency = 0.03
		tipLabel.TextColor3 = T.c.onInk
		tipLabel.FontFace = T.font
		tipLabel.TextWrapped = true
		tipLabel.AutomaticSize = Enum.AutomaticSize.XY
		tipLabel.Size = UDim2.new()
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = tipLabel
		local p = Instance.new("UIPadding")
		p.PaddingTop, p.PaddingBottom = UDim.new(0, 4), UDim.new(0, 5)
		p.PaddingLeft, p.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		p.Parent = tipLabel
		local lim = Instance.new("UISizeConstraint")
		lim.MaxSize = Vector2.new(300, math.huge)
		lim.Parent = tipLabel
		tipLabel.Parent = tipGui
	end
	tipLabel.TextSize = T.rem(0.8)
	tipLabel.Text = text
	local pos = inst.AbsolutePosition + Vector2.new(0, inst.AbsoluteSize.Y + 6)
	local vp = tipGui.AbsoluteSize
	tipLabel.Position = UDim2.fromOffset(math.clamp(pos.X, 4, math.max(4, vp.X - 304)), math.min(pos.Y, vp.Y - 40))
	tipLabel.Visible = true
end)

-- ------------------------------------------------------------ layout (grade do #layout e breakpoints)
-- Fim da barra do Roblox em px da tela. Max.Y (e não Height): no celular em pé a barra começa abaixo do
-- entalhe, e só a altura deixava o HUD por baixo dos botões do Roblox.
local function inset()
	local ok, r = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and r then
		return math.max(r.Max.Y, r.Height)
	end
	return 0
end

-- Px fora da área segura: em cada lado e embaixo (o topo já fica abaixo da barra do Roblox).
-- Sem a sonda (Studio antigo, testes), zero.
local function safeArea(vp)
	local s = safeGui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return 0, 0
	end
	local x = math.max(0, math.floor((vp.X - s.X) / 2))
	-- ponytail: limite de 48 px caso a sonda não informe o entalhe de cima na posição (aí ele cairia embaixo).
	local bottom = math.clamp(vp.Y - s.Y - math.max(0, safeGui.AbsolutePosition.Y), 0, 48)
	return x, bottom
end

-- "mobile" | "desktop" pela opção de layout (Opções > Tela); no automático, pela tela e pelo aparelho.
function Ctx.detectLayout(layout)
	local vp = mainGui.AbsoluteSize
	if vp.X < 10 then
		vp = Vector2.new(1280, 720)
	end
	return Config.resolveLayout(layout or "auto", { width = vp.X, touch = Ctx.touchOnly(), screenMin = math.min(vp.X, vp.Y) })
end

-- Celular no layout de celular fica em pé (mapa em cima, painel embaixo); no de computador, deitado.
-- Sem checar o aparelho: no PC o Roblox ignora a orientação, e a checagem errava em alguns celulares.
-- O jogo já abre em pé (StarterGui.ScreenOrientation no default.project.json); aqui só gira se precisar.
local lastOrientation = nil
local function applyOrientation()
	local want = Ctx.mobile and Enum.ScreenOrientation.Portrait or Enum.ScreenOrientation.LandscapeSensor
	if want ~= lastOrientation then
		lastOrientation = want
		pcall(function()
			playerGui.ScreenOrientation = want
		end)
	end
end

local layoutDirty = true
local function layout()
	local vp = mainGui.AbsoluteSize
	-- Tamanho da tela ainda desconhecido no primeiro quadro: não gira (o 1280x720 de reserva deitaria o celular).
	local known = vp.X >= 10
	if not known then
		vp = Vector2.new(1280, 720)
	end
	local top = inset()
	local sx, sb = safeArea(vp)
	root.Position = UDim2.fromOffset(sx, top)
	root.Size = UDim2.new(1, -sx * 2, 1, -top - sb)
	toastFrame.Position, toastFrame.Size = root.Position, root.Size
	vp = Vector2.new(vp.X - sx * 2, vp.Y)
	local h0 = vp.Y - top - sb
	Ctx.vp = Vector2.new(vp.X, h0)
	local wasMobile = Ctx.mobile
	Ctx.mobile = Ctx.detectLayout(Ctx.config.layout) == "mobile"
	if known then
		applyOrientation()
	end
	if wasMobile ~= Ctx.mobile then
		-- Troca de layout (girar o celular, mudar a opção): HUD, paleta e painel mudam de forma.
		Ctx.invalidate("all", true)
	end
	Ctx.mid = vp.X <= T.BP_MID
	Ctx.small = vp.X <= T.BP_SMALL
	local hudH = hudFrame.AbsoluteSize.Y
	local rem = T.rem
	if not Ctx.mobile then
		gameScroll.ScrollingEnabled = false
		gameScroll.CanvasSize = UDim2.new()
		hudFrame.Position = UDim2.new()
		local pad, gap = rem(0.75), rem(0.75)
		local palW = Ctx.mid and rem(12) or rem(14)
		local sideW = Ctx.mid and rem(21) or rem(25)
		layoutFrame.Position = UDim2.fromOffset(0, hudH)
		layoutFrame.Size = UDim2.new(1, 0, 1, -hudH)
		local innerH = h0 - hudH - pad * 2
		paletteFrame.Position = UDim2.fromOffset(pad, pad)
		paletteFrame.Size = UDim2.fromOffset(palW, innerH)
		sideFrame.Position = UDim2.new(1, -pad - sideW, 0, pad)
		sideFrame.Size = UDim2.fromOffset(sideW, innerH)
		stageFrame.Position = UDim2.fromOffset(pad + palW + gap, pad)
		stageFrame.Size = UDim2.new(1, -(pad * 2 + palW + sideW + gap * 2), 0, innerH)
	else
		-- Celular: #hud fixo em cima; mapa, paleta (rolagem lateral) e painel empilhados, a página rola.
		gameScroll.ScrollingEnabled = true
		local side = 16
		local w = vp.X - side * 2
		-- Mapa quadrado do tamanho da largura, mas cabendo inteiro na tela abaixo do HUD (celular deitado).
		local mapH = math.max(240, math.min(w, h0 - hudH - rem(1.2))) -- 240 = mínimo do MapView
		Ctx.mapMax = mapH
		local stageH = mapH + Stage.mobileExtra()
		local palH = Palette.mobileHeight()
		local sideH = math.max(math.floor(h0 * 0.6), sideFrame:GetAttribute("contentH") or 0)
		local y = rem(0.6)
		layoutFrame.Position = UDim2.fromOffset(0, hudH)
		stageFrame.Position = UDim2.fromOffset(side, y)
		stageFrame.Size = UDim2.fromOffset(w, stageH)
		y += stageH + rem(0.6)
		paletteFrame.Position = UDim2.fromOffset(side, y)
		paletteFrame.Size = UDim2.fromOffset(w, palH)
		y += palH + rem(0.6)
		sideFrame.Position = UDim2.fromOffset(side, y)
		sideFrame.Size = UDim2.fromOffset(w, sideH)
		y += sideH + rem(1)
		layoutFrame.Size = UDim2.new(1, 0, 0, y)
		gameScroll.CanvasSize = UDim2.fromOffset(0, hudH + y)
		-- HUD "sticky": acompanha a rolagem.
		hudFrame.Position = UDim2.fromOffset(0, gameScroll.CanvasPosition.Y)
	end
	layoutDirty = false
end
Ctx.relayout = function()
	layoutDirty = true
end
mainGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Ctx.relayout)
safeGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Ctx.relayout)
-- Entrada preferida muda (teclado ligado no tablet, toque depois do mouse): recalcula o automático.
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(Ctx.relayout)
end)
hudFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(Ctx.relayout)
gameScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if Ctx.mobile then
		hudFrame.Position = UDim2.fromOffset(0, gameScroll.CanvasPosition.Y)
	end
end)

local function paintPage()
	pageGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#2e2b3a")),
		ColorSequenceKeypoint.new(0.6, T.c.ink),
		ColorSequenceKeypoint.new(1, T.c.ink),
	})
end

-- ------------------------------------------------------------ telas
function Ctx.setScreen(name)
	Ctx.ui.screen = name
	loadingScreen.Visible = name == "loading"
	menuScreen.Visible = name == "menu"
	gameScreen.Visible = name == "game"
	Ctx.relayout()
	Ctx.invalidate("all", true)
end

-- ------------------------------------------------------------ redesenho
local function renderGame(part, force)
	if Ctx.ui.screen ~= "game" or not Ctx.game then
		return
	end
	if part == "hud" or part == "all" then
		Hud.render(force)
	end
	if part == "palette" or part == "all" then
		Palette.render(force)
	end
	if part == "side" or part == "all" then
		Side.render(force)
	end
	if part ~= "hud" and part ~= "palette" and part ~= "side" then
		Stage.render(part, force)
	end
end

local function flush()
	local d = Ctx.dirty
	if next(d) == nil then
		return
	end
	Ctx.dirty = {}
	if d.all then
		renderGame("all", true)
		return
	end
	for part, how in d do
		local ok, err = pcall(renderGame, part, how == "force")
		if not ok then
			warn("Falha ao desenhar " .. part .. ": " .. tostring(err))
		end
	end
end

Ctx.onConfig = function(cfg)
	T.apply(cfg)
	paintPage()
	Audio.applyConfig(cfg)
	Ctx.relayout()
	Ctx.invalidate("all", true)
	Screens.onConfig()
end

-- ------------------------------------------------------------ estado do servidor
local remotes = ReplicatedStorage:WaitForChild("ReinoRemotes")
local estado = remotes:WaitForChild("Estado")
local lastUnder = nil
local firstState = true

estado.OnClientEvent:Connect(function(snap, events, serverNow, extra)
	Ctx.timeOffset = serverNow - DateTime.now().UnixTimestampMillis
	if snap.under then
		lastUnder = snap.under
	else
		snap.under = lastUnder
	end
	if not snap.under then
		return
	end
	local g = Game.new(snap, serverNow)
	g.canUndoServer = snap.canUndo
	Ctx.game = g
	if extra then
		if extra.configs then
			Ctx.setConfig(extra.configs[Ctx.device()], true)
		end
		Ctx.server = extra
	end
	if firstState then
		firstState = false
		Screens.onFirstState()
	end
	for _, ev in events or {} do
		Ctx.emit(ev[1], ev[2])
	end
	Ctx.invalidate("hud")
	Ctx.invalidate("undo")
	Ctx.invalidate("side")
	Ctx.invalidate("palette")
	Ctx.invalidate("tileInfo")
	Ctx.invalidate("layers")
end)

-- ------------------------------------------------------------ início
T.apply(Ctx.config)
paintPage()
Toasts.init(toastFrame)
Modals.init(modalFrame)
Audio.init()
Hud.init(hudFrame)
Palette.init(paletteFrame)
Stage.init(stageFrame)
Side.init(sideFrame)
Screens.init({ loading = loadingScreen, menu = menuScreen, game = gameScreen })
Controller.init()
Ctx.setScreen("loading")
layout()

-- Ciclos do web: tick de 250 ms (HUD, desfazer), 1 s (painéis), e o mapa a cada quadro.
local acc250, acc1000 = 0, 0
local lastDraw = 0
RunService.RenderStepped:Connect(function(dt)
	if layoutDirty then
		layout()
	end
	acc250 += dt
	acc1000 += dt
	local g = Ctx.game
	local inGame = Ctx.ui.screen == "game" and g ~= nil
	if acc250 >= 0.25 then
		acc250 = 0
		if inGame then
			pcall(function()
				g:tick(Ctx.now(), false)
			end)
			Ctx.invalidate("hud")
			Ctx.invalidate("undo")
		end
	end
	if acc1000 >= 1 then
		acc1000 = 0
		if inGame and not Ctx.ui.pointerHeld then
			Ctx.invalidate("side")
			Ctx.invalidate("palette")
			Ctx.invalidate("layers")
			Ctx.invalidate("tileInfo")
			Controller.ambient()
		end
	end
	flush()
	local now = os.clock()
	if Ctx.config.batterySaver and now - lastDraw < 1 / 30 - 0.002 then
		return
	end
	lastDraw = now
	Screens.frame(dt)
	if inGame and Ctx.renderer then
		Ctx.renderer:draw(g, dt)
	end
end)

-- Pede o estado completo (o primeiro envio do servidor pode ter chegado antes deste script).
task.spawn(function()
	Ctx.call("sync")
end)
Screens.boot()
