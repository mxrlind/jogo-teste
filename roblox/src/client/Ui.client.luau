-- Tela do Reino de Bolso no Roblox (porte de src/ui/). Tudo é desenhado em ScreenGui, como o jogo web:
-- mapa 12x12 com os sprites KayKit à esquerda e o painel de abas à direita.
-- O servidor manda o estado a cada segundo; aqui roda uma cópia do Game só para mostrar números e prévias.
-- Toda ação vai para o servidor pelo RemoteFunction "Acao", que decide se vale.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Map = require(Reino.Core.Map)
local Economy = require(Reino.Core.Economy)
local Game = require(Reino.Core.Game)
local Season = require(Reino.Core.Season)
local Heroes = require(Reino.Core.Heroes)
local Under = require(Reino.Core.Underground)
local Imagens = require(Reino.Imagens)
local Buildings = require(Reino.Data.Buildings)
local HeroData = require(Reino.Data.Heroes)
local Talents = require(Reino.Data.Talents)
local Seasons = require(Reino.Data.Seasons)
local UnderData = require(Reino.Data.Underground)
local Events = require(Reino.Data.Events)
local Atlas = require(script.Parent:WaitForChild("Atlas"))

local remotes = ReplicatedStorage:WaitForChild("ReinoRemotes")
local acao = remotes:WaitForChild("Acao")
local estado = remotes:WaitForChild("Estado")

local BUILDINGS, TERRAIN = Buildings.BUILDINGS, Buildings.TERRAIN
local GRID_W, GRID_H, idx = Map.GRID_W, Map.GRID_H, Map.idx
local fmt, fmtTime, fmtPct, fmtRate = Util.fmt, Util.fmtTime, Util.fmtPct, Util.fmtRate

-- ------------------------------------------------------------ visual (cores do styles.css do jogo web)
local C = {
	ink = Color3.fromHex("#1f1d27"), ink2 = Color3.fromHex("#2a2833"), ink3 = Color3.fromHex("#363341"),
	onInk = Color3.fromHex("#f3ead6"), muted = Color3.fromHex("#b5aec4"),
	paper = Color3.fromHex("#f3ecdc"), paper2 = Color3.fromHex("#fbf7ee"), paper3 = Color3.fromHex("#e8dec7"),
	line = Color3.fromHex("#d9ccb0"), text = Color3.fromHex("#2b2a33"), textMuted = Color3.fromHex("#645f70"),
	gold = Color3.fromHex("#f2b632"), goldHi = Color3.fromHex("#ffd45c"), goldText = Color3.fromHex("#8a5d00"),
	good = Color3.fromHex("#23803d"), bad = Color3.fromHex("#b8412f"), blue = Color3.fromHex("#1f6fb2"),
	purple = Color3.fromHex("#7a52c4"), grass = Color3.fromHex("#2e8b47"),
}
local RARITY_COLOR = {
	comum = Color3.fromHex("#6f7782"), raro = Color3.fromHex("#2f7cc0"),
	epico = Color3.fromHex("#7a52c4"), lendario = Color3.fromHex("#b9820e"),
}
local RES_COLOR = {
	gold = Color3.fromHex("#f2b632"), food = Color3.fromHex("#f0c27a"), wood = Color3.fromHex("#c8834a"),
	stone = Color3.fromHex("#d7dde0"), gems = Color3.fromHex("#7cc6f0"), crowns = Color3.fromHex("#ffd45c"),
}
-- Blocos coloridos enquanto as folhas de sprites não foram enviadas (Imagens.luau com id 0).
local TERRAIN_COLOR = {
	grass = Color3.fromHex("#6ab04c"), forest = Color3.fromHex("#2d6a4f"), rock = Color3.fromHex("#8d99ae"),
	water = Color3.fromHex("#4dabf7"), mountain = Color3.fromHex("#6c757d"), sapling = Color3.fromHex("#95d5b2"),
}
local UNDER_COLOR = {
	rock = Color3.fromHex("#4a4453"), gold = Color3.fromHex("#b08a2e"), gem = Color3.fromHex("#5e6fd1"),
	water = Color3.fromHex("#2b5f8a"), magma = Color3.fromHex("#e8590c"), cavern = Color3.fromHex("#3b4a3f"), floor = Color3.fromHex("#8a6e52"),
}
local FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local FONT_BLACK = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local FONT_REGULAR = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Regular)

local HAS_IMAGES = Imagens[1] ~= "rbxassetid://0" and Imagens[1] ~= ""
local RES_NAMES = { gold = "Ouro", food = "Comida", wood = "Madeira", stone = "Pedra", gems = "Gemas", crowns = "Coroas", scrolls = "Pergaminhos" }
local DIR_NAMES = { n = "Norte", s = "Sul", e = "Leste", w = "Oeste" }
local DIR_FROM = { n = "do Norte", s = "do Sul", e = "do Leste", w = "do Oeste" }

-- ------------------------------------------------------------ helpers de interface
local function new(class, props, children)
	local inst = Instance.new(class)
	local parent = props and props.Parent
	for k, v in props or {} do
		if k ~= "Parent" then inst[k] = v end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end

local function padding(px)
	return new("UIPadding", { PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px) })
end

local function vlist(gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder })
end

local function hlist(gap, wraps)
	return new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = wraps == true, VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end

local function label(props)
	local base = {
		BackgroundTransparency = 1, FontFace = FONT, TextColor3 = C.text, TextSize = 15, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true,
	}
	for k, v in props do base[k] = v end
	return new("TextLabel", base)
end

local function costText(cost, res)
	local parts = {}
	for _, r in { "gold", "food", "wood", "stone", "gems", "scrolls" } do
		local v = cost and cost[r]
		if v and v > 0 then
			local have = res and (res[r] or 0) or math.huge
			local txt = fmt(v, 1) .. " " .. string.lower(RES_NAMES[r])
			if have < v then txt = '<font color="#b8412f">' .. txt .. "</font>" end
			table.insert(parts, txt)
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "grátis"
end

local function yieldText(gain)
	local parts = {}
	for _, r in { "gold", "food", "wood", "stone", "gems", "scrolls" } do
		if gain[r] and gain[r] > 0 then
			table.insert(parts, "+" .. fmt(gain[r]) .. " " .. string.lower(RES_NAMES[r]))
		end
	end
	return table.concat(parts, ", ")
end

local function nameOf(key)
	if BUILDINGS[key] then return BUILDINGS[key].name end
	if TERRAIN[key] then return TERRAIN[key].name end
	if UnderData.UNDER_TILES[key] then return UnderData.UNDER_TILES[key].name end
	if UnderData.ROOMS[key] then return UnderData.ROOMS[key].name end
	if key == "wall" then return "Parede" end
	return key
end

-- ------------------------------------------------------------ estado do cliente
local mirror = nil -- Game com o último estado do servidor (só leitura)
local lastUnder = nil
local timeOffset = 0 -- relógio do servidor - relógio local
local ui = {
	tab = "reino", build = nil, sel = nil, hover = nil, moveFrom = nil, layer = 0,
	confirmAscend = false, confirmSell = false, heroOpen = nil,
}
local TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local function now()
	return DateTime.now().UnixTimestampMillis + timeOffset
end

local refresh -- definido mais abaixo
local toast

local function act(name, ...)
	local args = table.pack(...)
	task.spawn(function()
		local ok, r = pcall(function()
			return acao:InvokeServer(name, table.unpack(args, 1, args.n))
		end)
		if not ok then
			toast("Sem conexão com o servidor", "bad")
			return
		end
		if type(r) == "table" and not r.ok and r.reason then
			toast(r.reason, "bad")
		end
	end)
end

-- ------------------------------------------------------------ esqueleto da tela
local gui = new("ScreenGui", {
	Name = "ReinoDeBolso", ResetOnSpawn = false, IgnoreGuiInset = false, -- abaixo dos botões do Roblox ZIndexBehavior = Enum.ZIndexBehavior.Global,
	Parent = player:WaitForChild("PlayerGui"),
})
local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.ink, BorderSizePixel = 0, Parent = gui })

local TOP_H = 78
local topBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TOP_H), BackgroundColor3 = C.ink2, BorderSizePixel = 0, ZIndex = 100, Parent = root,
}, { padding(8), vlist(4) })
local resRow = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 100, LayoutOrder = 1,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 0, Parent = topBar,
}, { hlist(8) })
local infoLine = label({
	TextColor3 = C.onInk, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true,
	TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 100, LayoutOrder = 2, Parent = topBar,
}, nil)
new("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 9, Parent = infoLine })

local resLabels = {}
for i, r in { "gold", "food", "wood", "stone", "gems", "crowns", "pop", "happy", "defense" } do
	resLabels[r] = new("TextLabel", {
		BackgroundColor3 = C.ink3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), FontFace = FONT,
		TextSize = 14, TextColor3 = RES_COLOR[r] or C.onInk, RichText = true, LayoutOrder = i, ZIndex = 101, Parent = resRow,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
end

local body = new("Frame", { Position = UDim2.new(0, 0, 0, TOP_H), Size = UDim2.new(1, 0, 1, -TOP_H), BackgroundTransparency = 1, Parent = root })
local mapArea = new("Frame", { BackgroundTransparency = 1, Parent = body })
local panel = new("Frame", { BackgroundColor3 = C.paper, BorderSizePixel = 0, ZIndex = 100, Parent = body })
local tabsBar = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.paper3, BorderSizePixel = 0, ZIndex = 100, Parent = panel }, {
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 6) }), hlist(4, true),
})
local content = new("ScrollingFrame", {
	Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6,
	ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 100, Parent = panel,
}, { padding(10), vlist(8) })

-- Painel à direita; em telas estreitas (celular em pé) vai para baixo do mapa.
local function layout()
	local vp = root.AbsoluteSize
	if vp.X < 10 then vp = Vector2.new(1280, 720) end
	local h = vp.Y - TOP_H
	if vp.X >= vp.Y * 1.05 then
		local w = math.clamp(math.floor(vp.X * 0.38), 280, 440)
		w = math.max(w, vp.X - h) -- o mapa nunca fica maior que a altura
		w = math.min(w, vp.X - 200)
		mapArea.Position = UDim2.new(0, 0, 0, 0)
		mapArea.Size = UDim2.new(1, -w, 1, 0)
		panel.Position = UDim2.new(1, -w, 0, 0)
		panel.Size = UDim2.new(0, w, 1, 0)
	else
		local mapH = math.min(vp.X, math.floor(h * 0.55))
		mapArea.Position = UDim2.new(0, 0, 0, 0)
		mapArea.Size = UDim2.new(1, 0, 0, mapH)
		panel.Position = UDim2.new(0, 0, 0, mapH)
		panel.Size = UDim2.new(1, 0, 1, -mapH)
	end
end
layout()
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

-- ------------------------------------------------------------ mapa
local mapFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 1, -16),
	BackgroundColor3 = Color3.fromHex("#16141c"), BorderSizePixel = 0, ClipsDescendants = true, Parent = mapArea,
}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(10) })

local function setSprite(img, name)
	local r = name and Atlas.RECTS[name]
	if not r or not HAS_IMAGES then
		img.Image = ""
		return false
	end
	img.Image = Imagens[r[1]]
	img.ImageRectOffset = Vector2.new(r[2], r[3])
	img.ImageRectSize = Vector2.new(r[4], r[5])
	return true
end

local function pickName(list, i)
	return list[((i % #list) + #list) % #list + 1]
end

-- Quadro dos sprites KayKit em tiles, relativo ao centro do tile (igual a SPRITE_FRAME do jogo web).
local FRAME = { left = -0.6, right = 0.6, top = -1.25, bottom = 0.6 }
local cells = {}
for i = 1, GRID_W * GRID_H do
	local x, y = Map.xy(i)
	local cell = {}
	cell.ground = new("ImageLabel", {
		Position = UDim2.fromScale(x / GRID_W, y / GRID_H), Size = UDim2.fromScale(1 / GRID_W + 0.001, 1 / GRID_H + 0.001),
		BorderSizePixel = 0, BackgroundTransparency = 0, ZIndex = 2, ScaleType = Enum.ScaleType.Stretch, Parent = mapFrame,
	})
	cell.over = new("ImageLabel", {
		Position = UDim2.fromScale((x + 0.5 + FRAME.left) / GRID_W, (y + 0.5 + FRAME.top) / GRID_H),
		Size = UDim2.fromScale((FRAME.right - FRAME.left) / GRID_W, (FRAME.bottom - FRAME.top) / GRID_H),
		BackgroundTransparency = 1, ZIndex = 10 + y, ScaleType = Enum.ScaleType.Stretch, Parent = mapFrame,
	})
	-- Bloco colorido com o nome, para quando as folhas de sprites não foram enviadas.
	cell.fallback = new("TextLabel", {
		Position = UDim2.fromScale((x + 0.08) / GRID_W, (y + 0.08) / GRID_H), Size = UDim2.fromScale(0.84 / GRID_W, 0.84 / GRID_H),
		BackgroundColor3 = C.paper2, TextColor3 = C.text, FontFace = FONT_BLACK, TextScaled = true, ZIndex = 30, Visible = false, Parent = mapFrame,
	}, { corner(4), new("UITextSizeConstraint", { MaxTextSize = 14 }) })
	cell.lock = new("Frame", {
		Position = cell.ground.Position, Size = cell.ground.Size, BackgroundColor3 = Color3.fromRGB(20, 22, 32),
		BackgroundTransparency = 0.38, BorderSizePixel = 0, ZIndex = 40, Parent = mapFrame,
	})
	cell.badge = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((x + 0.84) / GRID_W, (y + 0.84) / GRID_H),
		Size = UDim2.fromScale(0.34 / GRID_W, 0.34 / GRID_H), BackgroundColor3 = C.ink, TextColor3 = C.goldHi, FontFace = FONT_BLACK,
		TextScaled = true, ZIndex = 45, Visible = false, Parent = mapFrame,
	}, { corner(20) })
	cell.warn = new("TextLabel", {
		Position = UDim2.fromScale((x + 0.62) / GRID_W, (y + 0.02) / GRID_H), Size = UDim2.fromScale(0.34 / GRID_W, 0.34 / GRID_H),
		BackgroundColor3 = Color3.fromHex("#ffb020"), Text = "!", TextColor3 = C.ink, FontFace = FONT_BLACK, TextScaled = true,
		ZIndex = 45, Visible = false, Parent = mapFrame,
	}, { corner(20) })
	cell.hit = new("TextButton", {
		Position = cell.ground.Position, Size = UDim2.fromScale(1 / GRID_W, 1 / GRID_H), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 50, Parent = mapFrame,
	})
	cells[i] = cell
end

local selBox = new("Frame", {
	Size = UDim2.fromScale(1 / GRID_W, 1 / GRID_H), BackgroundColor3 = Color3.fromHex("#ffe08a"), BackgroundTransparency = 0.75,
	ZIndex = 44, Visible = false, Parent = mapFrame,
}, { new("UIStroke", { Color = C.gold, Thickness = 3 }), corner(6) })
local hoverBox = new("Frame", {
	Size = UDim2.fromScale(1 / GRID_W, 1 / GRID_H), BackgroundTransparency = 1, ZIndex = 44, Visible = false, Parent = mapFrame,
}, { new("UIStroke", { Color = Color3.fromHex("#ffffff"), Thickness = 2, Transparency = 0.3 }), corner(6) })
local border = new("Frame", { BackgroundTransparency = 1, ZIndex = 41, Parent = mapFrame }, {
	new("UIStroke", { Color = C.gold, Thickness = 2.5 }),
})
local adjLabels = {}
for k = 1, 4 do
	adjLabels[k] = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.9 / GRID_W, 0.32 / GRID_H), BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2, FontFace = FONT_BLACK, TextScaled = true, ZIndex = 46, Visible = false, Parent = mapFrame,
	}, { corner(6) })
end
local chestLabel = new("TextButton", {
	Size = UDim2.fromScale(1 / GRID_W, 0.5 / GRID_H), BackgroundColor3 = C.gold, Text = "Carroça!", TextColor3 = C.ink,
	FontFace = FONT_BLACK, TextScaled = true, ZIndex = 47, Visible = false, Parent = mapFrame,
}, { corner(6) })
chestLabel.MouseButton1Click:Connect(function() act("openChest") end)
local raidLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.055), BackgroundColor3 = C.bad, TextColor3 = C.paper2,
	FontFace = FONT_BLACK, TextScaled = true, ZIndex = 48, Parent = mapFrame,
}, { corner(8), padding(2) })

-- Botões sobre o mapa: Desfazer e troca de nível (superfície / subsolo).
local mapTools = new("Frame", {
	Position = UDim2.new(0, 14, 0, 14), Size = UDim2.new(1, -28, 0, 32), BackgroundTransparency = 1, ZIndex = 60, Parent = mapArea,
}, { hlist(6) })

local function smallButton(text, parent, onClick, order)
	local b = new("TextButton", {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.ink3, TextColor3 = C.onInk,
		Text = text, FontFace = FONT, TextSize = 14, ZIndex = 61, LayoutOrder = order or 0, Parent = parent,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	b.MouseButton1Click:Connect(onClick)
	return b
end

local undoButton = smallButton("Desfazer (Z)", mapTools, function() act("undoBuild") end, 99)
undoButton.BackgroundColor3 = C.gold
undoButton.TextColor3 = C.ink
local layerButtons = {}
for d = 0, UnderData.DEPTHS do
	layerButtons[d] = smallButton(d == 0 and "Superfície" or UnderData.LEVEL_NAMES[d], mapTools, function()
		ui.layer = d
		ui.sel = nil
		ui.build = nil
		refresh()
	end, d)
end

-- ------------------------------------------------------------ avisos (toasts)
local toastBox = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0.9, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 200, Parent = mapArea,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }) })
local toastCount = 0
local TOAST_COLOR = { good = C.good, bad = C.bad, info = C.ink3, season = C.purple, raid = C.bad, gold = C.goldText }

function toast(text, kind)
	toastCount += 1
	local t = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(0, 0, 0, 0), BackgroundColor3 = TOAST_COLOR[kind or "info"] or C.ink3,
		TextColor3 = C.paper2, FontFace = FONT, TextSize = 15, Text = text, TextWrapped = true, RichText = true,
		LayoutOrder = toastCount, ZIndex = 201, Parent = toastBox,
	}, { corner(10), padding(8), new("UISizeConstraint", { MaxSize = Vector2.new(520, 200) }) })
	task.delay(4.5, function() t:Destroy() end)
	local kids = toastBox:GetChildren()
	if #kids > 6 then
		for _, k in kids do
			if k:IsA("TextLabel") and k.LayoutOrder <= toastCount - 5 then k:Destroy() end
		end
	end
end

-- ------------------------------------------------------------ painel: construção incremental
-- O painel é refeito só quando o que ele mostra muda de "forma" (aba, seleção, heróis...).
-- Entre uma reconstrução e outra, cada texto tem uma função que o atualiza a cada estado novo.
local updaters = {}
local panelKey = nil
local order = 0

local function nextOrder()
	order += 1
	return order
end

local function bind(fn)
	table.insert(updaters, fn)
	if mirror then fn(mirror) end
end

local function card(parent, color)
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = color or C.paper2,
		LayoutOrder = nextOrder(), ZIndex = 101, Parent = parent or content,
	}, { corner(10), padding(10), vlist(6), new("UIStroke", { Color = C.line, Thickness = 1 }) })
end

local function title(text, parent)
	return label({ Text = text, FontFace = FONT_BLACK, TextSize = 18, LayoutOrder = nextOrder(), ZIndex = 102, Parent = parent or content })
end

local function line(text, parent, props)
	local l = label({ Text = text or "", LayoutOrder = nextOrder(), ZIndex = 102, Parent = parent or content })
	for k, v in props or {} do l[k] = v end
	return l
end

local function button(text, parent, onClick, props)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.gold, TextColor3 = C.ink, Text = text, FontFace = FONT,
		TextSize = 15, TextWrapped = true, RichText = true, LayoutOrder = nextOrder(), ZIndex = 103, Parent = parent or content,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	for k, v in props or {} do b[k] = v end
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function setEnabled(b, enabled)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundTransparency = enabled and 0 or 0.55
end

local function row(parent)
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = nextOrder(), ZIndex = 102, Parent = parent or content,
	}, { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 44), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
end

local function icon(name, parent, size)
	local img = new("ImageLabel", {
		Size = UDim2.new(0, size or 44, 0, size or 44), BackgroundColor3 = C.paper3, BackgroundTransparency = HAS_IMAGES and 1 or 0,
		ZIndex = 103, LayoutOrder = nextOrder(), Parent = parent,
	}, { corner(8) })
	setSprite(img, name)
	return img
end

-- ------------------------------------------------------------ aba Reino: inspetor + paleta
local function tileOf(m, x, y)
	return m.state.grid.tiles[idx(x, y)]
end

local function previewText(d)
	local parts = {}
	for _, r in Economy.PROD_RES do
		if math.abs(d[r]) > 0.0005 then
			table.insert(parts, string.format('<font color="%s">%s %s</font>', d[r] > 0 and "#23803d" or "#b8412f", fmtRate(d[r]), string.lower(RES_NAMES[r])))
		end
	end
	if d.popCap ~= 0 then table.insert(parts, string.format("%+d moradores", d.popCap)) end
	if math.abs(d.defense) > 0.05 then table.insert(parts, string.format("%s de defesa", (d.defense > 0 and "+" or "") .. fmt(d.defense))) end
	if math.abs(d.happiness) > 0.05 then table.insert(parts, string.format("%s de felicidade", (d.happiness > 0 and "+" or "") .. fmt(d.happiness))) end
	return #parts > 0 and table.concat(parts, "  ·  ") or "Sem efeito na produção"
end

local function adjText(parts)
	local out = {}
	for _, p in parts do
		table.insert(out, string.format('<font color="%s">%s %s</font>', p.value > 0 and "#23803d" or "#b8412f", nameOf(p.key), fmtPct(p.value)))
	end
	return #out > 0 and table.concat(out, ", ") or "nenhum vizinho ajuda"
end

local function buildInspector(m)
	local s = m.state
	local focus = ui.sel
	if ui.build and not TOUCH and ui.hover then focus = ui.hover end
	if ui.moveFrom then
		local c = card()
		title("Mover " .. BUILDINGS[tileOf(m, ui.moveFrom.x, ui.moveFrom.y).b.id].name, c)
		line("Toque no tile de destino. Esc cancela.", c)
		button("Cancelar", c, function() ui.moveFrom = nil refresh() end, { BackgroundColor3 = C.paper3 })
		return
	end
	if ui.build and focus then
		local def = BUILDINGS[ui.build]
		local c = card()
		title(def.name .. " aqui", c)
		local prev = line("", c)
		local adj = line("", c)
		local b = TOUCH and button("Construir aqui", c, function() act("build", ui.build, focus.x, focus.y) end) or nil
		bind(function(mm)
			local p = mm:previewBuild(ui.build, focus.x, focus.y)
			prev.Text = p and previewText(p) or "Não dá para construir aqui"
			adj.Text = "Vizinhos: " .. adjText(Economy.adjacencyAt(mm.state, ui.build, focus.x, focus.y, mm.econ.mods).parts)
			if b then setEnabled(b, p ~= nil) end
		end)
		return
	end
	if not focus then return end
	local x, y = focus.x, focus.y
	local tile = tileOf(m, x, y)
	local i = idx(x, y)
	local c = card()
	if not Map.isUnlocked(s.grid, x, y) then
		title("Terra não conquistada", c)
		line("Expanda o reino para construir aqui.", c)
		return
	end
	if tile.b then
		local def = BUILDINGS[tile.b.id]
		local head = title("", c)
		line(def.desc, c, { FontFace = FONT_REGULAR, TextColor3 = C.textMuted, TextSize = 14 })
		local outL = line("", c)
		local adjL = line("", c)
		local workL = line("", c)
		local r = row(c)
		local up = button("", r, function() act("upgrade", x, y) end)
		local upAll = button("Melhorar todos", r, function() act("upgradeAll", tile.b and tile.b.id) end, { BackgroundColor3 = C.paper3 })
		local mv = button("Mover (M)", r, function() ui.moveFrom = { x = x, y = y } refresh() end, { BackgroundColor3 = C.paper3 })
		local sell = button("Demolir", r, function()
			if ui.confirmSell then
				ui.confirmSell = false
				ui.sel = nil
				act("sell", x, y)
			else
				ui.confirmSell = true
			end
		end, { BackgroundColor3 = Color3.fromHex("#f1c6bd") })
		bind(function(mm)
			local t = tileOf(mm, x, y)
			if not t.b then return end
			local info = mm.econ.tiles[i]
			head.Text = string.format("%s · nível %d", BUILDINGS[t.b.id].name, t.b.lvl)
			local outs = {}
			if info then
				for _, res in Economy.PROD_RES do
					if info.out[res] and info.out[res] > 0.0005 then table.insert(outs, fmtRate(info.out[res]) .. " " .. string.lower(RES_NAMES[res])) end
				end
				if info.consume then table.insert(outs, "consome " .. fmt(info.consume) .. "/s de comida") end
				if info.defense > 0 then table.insert(outs, fmt(info.defense) .. " de defesa") end
			end
			outL.Text = #outs > 0 and table.concat(outs, "  ·  ") or ""
			outL.Visible = #outs > 0
			if info and not info.active then
				adjL.Text = '<font color="#b8412f">Parado: precisa ficar encostado em ' .. string.lower(nameOf(BUILDINGS[t.b.id].requiresAdj)) .. ".</font>"
			else
				adjL.Text = "Vizinhos: " .. adjText(info and info.adjParts or {})
			end
			if info and info.workers > 0 then
				workL.Text = string.format("Trabalhadores: %d (%d%% ocupado)", info.workers, Util.round(info.staff * 100))
				workL.Visible = true
			else
				workL.Visible = false
			end
			local cost = Economy.upgradeCost(t.b.id, t.b.lvl, mm.econ.mods)
			up.Text = cost and ("Melhorar: " .. costText(cost, mm.state.res)) or "Nível máximo"
			setEnabled(up, cost ~= nil and Economy.canAfford(mm.state.res, cost))
			upAll.Visible = cost ~= nil
			sell.Text = ui.confirmSell and "Confirmar demolição" or "Demolir (Delete)"
		end)
		return
	end
	local ter = TERRAIN[tile.t]
	title(ter.name, c)
	if tile.t == "sapling" then
		local grow = line("", c)
		bind(function(mm)
			local t = tileOf(mm, x, y)
			if t.t == "sapling" then
				grow.Text = "Vira floresta em " .. fmtTime(Buildings.GROW_SECONDS - (now() - (t.p or 0)) / 1000)
			end
		end)
	end
	if ter.clearCost then
		local b = button("", c, function() act("clear", x, y) end)
		bind(function(mm)
			b.Text = (tile.t == "sapling" and "Arrancar" or "Limpar") .. ": " .. costText(ter.clearCost, mm.state.res)
				.. (next(ter.clearYield) and (" (rende " .. yieldText(ter.clearYield) .. ")") or "")
			setEnabled(b, Economy.canAfford(mm.state.res, ter.clearCost))
		end)
	elseif tile.t == "grass" then
		line("Escolha um prédio abaixo e toque aqui para construir.", c, { FontFace = FONT_REGULAR })
		local b = button("", c, function() act("plant", x, y) end, { BackgroundColor3 = Color3.fromHex("#b7e4c7") })
		bind(function(mm)
			b.Text = "Plantar árvore: " .. costText(Buildings.PLANT_COST, mm.state.res)
			setEnabled(b, Economy.canAfford(mm.state.res, Buildings.PLANT_COST))
		end)
	else
		line("Não dá para construir aqui, mas os vizinhos podem aproveitar.", c, { FontFace = FONT_REGULAR })
	end
end

local function buildPalette(m)
	title("Construir")
	local grid = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(), ZIndex = 101, Parent = content,
	}, { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 76), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for n, id in Buildings.BUILDING_ORDER do
		local def = BUILDINGS[id]
		local b = new("TextButton", {
			BackgroundColor3 = C.paper2, Text = "", AutoButtonColor = true, LayoutOrder = n, ZIndex = 102, Parent = grid,
		}, { corner(10), padding(6) })
		local stroke = new("UIStroke", { Color = C.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		local img = icon("icon-" .. id, b, 40)
		img.Position = UDim2.new(0, 0, 0, 0)
		local nm = label({ Text = (n <= 9 and (n .. ". ") or "") .. def.name, Position = UDim2.new(0, 46, 0, 0), Size = UDim2.new(1, -46, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, ZIndex = 103, Parent = b })
		local cl = label({ Position = UDim2.new(0, 46, 0, 18), Size = UDim2.new(1, -46, 1, -18), AutomaticSize = Enum.AutomaticSize.None, TextSize = 12, FontFace = FONT_REGULAR, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 103, Parent = b })
		b.MouseButton1Click:Connect(function()
			if not mirror or not mirror:isAvailable(id) then return end
			ui.build = ui.build ~= id and id or nil
			ui.moveFrom = nil
			refresh()
		end)
		bind(function(mm)
			local available = mm:isAvailable(id)
			if available then
				cl.Text = costText(Economy.buildCost(mm.state, id, mm.econ.mods), mm.state.res)
			else
				cl.Text = string.format("Abre com %d construções", def.unlock.buildings)
			end
			nm.TextTransparency = available and 0 or 0.5
			img.ImageTransparency = available and 0 or 0.6
			stroke.Color = ui.build == id and C.gold or C.line
			stroke.Thickness = ui.build == id and 3 or 1
		end)
	end
	local c = card()
	local exp = button("", c, function() act("expand") end)
	bind(function(mm)
		local cost = mm:expandCost()
		exp.Visible = cost ~= nil
		if cost then
			exp.Text = "Conquistar mais terra: " .. costText(cost, mm.state.res)
			setEnabled(exp, Economy.canAfford(mm.state.res, cost))
		end
	end)
end

-- ------------------------------------------------------------ subsolo
local function buildUnderPanel(m)
	local d = ui.layer
	local s = m.state
	title(UnderData.LEVEL_NAMES[d] .. string.format(" (nível %d)", d))
	if not ui.sel then
		line("Toque num tile ao lado de uma galeria para cavar. Cavar rende pedra, ouro ou gemas e abre espaço para salas.", nil, { FontFace = FONT_REGULAR })
		return
	end
	local x, y = ui.sel.x, ui.sel.y
	local t = Under.levelOf(s, d).tiles[idx(x, y)]
	local c = card()
	if not t.s then
		title("Escuridão", c)
		line("Ninguém viu o que tem ali. Cave até chegar perto.", c)
		return
	end
	local def = UnderData.UNDER_TILES[t.t]
	title(t.b and UnderData.ROOMS[t.b.id].name or def.name, c)
	line(t.b and UnderData.ROOMS[t.b.id].desc or def.desc, c, { FontFace = FONT_REGULAR, TextColor3 = C.textMuted, TextSize = 14 })
	if def.dig then
		local b = button("", c, function() act("dig", d, x, y) end)
		bind(function(mm)
			local cost = Under.digCost(mm.state, d, mm.econ.mods)
			local reach = Under.canReach(Under.levelOf(mm.state, d), x, y)
			b.Text = reach and ("Cavar: " .. costText(cost, mm.state.res) .. " (rende " .. yieldText(Under.digYield(t.t, d)) .. ")") or "Cave a partir de uma galeria vizinha"
			setEnabled(b, reach and Economy.canAfford(mm.state.res, cost))
		end)
		return
	end
	if t.st then
		line(t.st == "down" and "Escada para baixo." or "Escada para cima.", c)
		local target = t.st == "down" and d + 1 or d - 1
		button(target == 0 and "Subir para a superfície" or ("Ir para " .. UnderData.LEVEL_NAMES[target]), c, function()
			ui.layer = target
			refresh()
		end)
		return
	end
	if t.b then
		local info = line("", c)
		local r = row(c)
		local up = button("", r, function() act("upgradeRoom", d, x, y) end)
		button("Demolir", r, function() ui.sel = nil act("sellRoom", d, x, y) end, { BackgroundColor3 = Color3.fromHex("#f1c6bd") })
		bind(function(mm)
			local tt = Under.levelOf(mm.state, d).tiles[idx(x, y)]
			if not tt.b then return end
			local inf = mm.econ.under[d] and mm.econ.under[d][idx(x, y)]
			local outs = { "Nível " .. tt.b.lvl }
			if inf then
				for r2, v in inf.out do table.insert(outs, fmtRate(v) .. " " .. string.lower(RES_NAMES[r2])) end
				if not inf.active then table.insert(outs, '<font color="#b8412f">parada: falta o vizinho certo</font>') end
			end
			info.Text = table.concat(outs, "  ·  ")
			local cost = Under.roomUpgradeCost(tt.b.id, tt.b.lvl, mm.econ.mods)
			up.Text = cost and ("Melhorar: " .. costText(cost, mm.state.res)) or "Nível máximo"
			setEnabled(up, cost ~= nil and Economy.canAfford(mm.state.res, cost))
		end)
		return
	end
	if UnderData.UNDER_TILES[t.t].open then
		for _, id in UnderData.ROOM_ORDER do
			local room = UnderData.ROOMS[id]
			if d >= room.minDepth then
				local b = button("", c, function() act("buildRoom", d, x, y, id) end, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
				bind(function(mm)
					local cost = Under.roomCost(mm.state, id, mm.econ.mods)
					b.Text = room.name .. ": " .. costText(cost, mm.state.res)
					local lv = Under.levelOf(mm.state, d)
					local okTile = room.onTile and t.t == room.onTile or (not room.onTile and t.t == "floor")
					setEnabled(b, okTile and Under.roomAdjacency(lv, id, x, y).hasRequired and Economy.canAfford(mm.state.res, cost))
				end)
			end
		end
		if d < UnderData.DEPTHS then
			local b = button("", c, function() act("digStairs", d, x, y) end, { BackgroundColor3 = C.paper3 })
			bind(function(mm)
				local cost = Under.stairsCost(d)
				b.Text = "Cavar escada para " .. UnderData.LEVEL_NAMES[d + 1] .. ": " .. costText(cost, mm.state.res)
				setEnabled(b, Economy.canAfford(mm.state.res, cost))
			end)
		end
	end
end

-- ------------------------------------------------------------ aba Heróis
local function heroBonusText(hero, owned)
	local v = hero.bonus.value * Economy.heroStrength(owned)
	local what = HeroData.BONUS_TEXT[hero.bonus.type] or hero.bonus.type
	if hero.bonus.type == "happiness" then
		return string.format("+%s %s", fmt(v), what)
	end
	if hero.bonus.type == "cost" then
		return string.format("-%d%% %s", Util.round(v * 100), what)
	end
	return string.format("+%d%% %s", Util.round(v * 100), what)
end

local function buildHeroes(m)
	local s = m.state
	title("Heróis")
	local c = card()
	local info = line("", c)
	local r = row(c)
	local bScroll = button("", r, function() act("recruit", "scroll") end)
	local bGold = button("", r, function() act("recruit", "gold") end)
	local bGems = button("", r, function() act("recruit", "gems") end, { BackgroundColor3 = Color3.fromHex("#bfe3f7") })
	bind(function(mm)
		local slots = Heroes.councilSlots(mm.econ.mods)
		info.Text = string.format("Conselho: %d de %d vagas · Expedições: %d de %d · Pergaminhos: %d", #mm.state.heroes.council, slots,
			Heroes.activeExpeditions(mm.state), Heroes.expeditionSlots(mm.state), mm.state.items.scrolls or 0)
		bScroll.Text = "Usar pergaminho"
		setEnabled(bScroll, (mm.state.items.scrolls or 0) >= 1)
		local gold = Heroes.recruitGoldCost(mm.state)
		bGold.Text = "Recrutar: " .. costText({ gold = gold }, mm.state.res)
		setEnabled(bGold, mm.state.res.gold >= gold)
		bGems.Text = "Recrutar: " .. costText({ gems = HeroData.RECRUIT_GEM_COST }, mm.state.res)
		setEnabled(bGems, mm.state.res.gems >= HeroData.RECRUIT_GEM_COST)
	end)

	local ids = {}
	for hid in s.heroes.owned do table.insert(ids, hid) end
	table.sort(ids, function(a, b)
		local ia, ib = table.find(s.heroes.council, a), table.find(s.heroes.council, b)
		if (ia ~= nil) ~= (ib ~= nil) then return ia ~= nil end
		return HeroData.HERO_BY_ID[a].name < HeroData.HERO_BY_ID[b].name
	end)
	if #ids == 0 then
		line("Nenhum herói ainda. Use o pergaminho grátis!", nil, { FontFace = FONT_REGULAR })
	end
	for _, hid in ids do
		local hero = HeroData.HERO_BY_ID[hid]
		local hc = card()
		local head = title("", hc)
		head.TextColor3 = RARITY_COLOR[hero.rarity]
		local bonusL = line("", hc)
		line(hero.lore, hc, { FontFace = FONT_REGULAR, TextColor3 = C.textMuted, TextSize = 13 })
		local status = line("", hc)
		local rr = row(hc)
		local council = button("", rr, function() act("toggleCouncil", hid) end, { BackgroundColor3 = C.paper3 })
		local train = button("", rr, function()
			local o = mirror and mirror.state.heroes.owned[hid]
			if o and o.training then act("speedUpTraining", hid) else act("trainHero", hid) end
		end, { BackgroundColor3 = C.paper3 })
		local expButtons = {}
		for _, exp in HeroData.EXPEDITIONS do
			expButtons[exp.id] = button(string.format("%s (%s)", exp.name, fmtTime(exp.duration)), rr, function() act("startExpedition", hid, exp.id) end, { BackgroundColor3 = Color3.fromHex("#d8f0dc") })
		end
		local collect = button("", rr, function()
			local o = mirror and mirror.state.heroes.owned[hid]
			if o and o.expedition and o.expedition.endsAt <= now() then act("collectExpedition", hid) else act("speedUpExpedition", hid) end
		end)
		bind(function(mm)
			local o = mm.state.heroes.owned[hid]
			if not o then return end
			local rarity = HeroData.RARITIES[hero.rarity].name
			head.Text = string.format("%s  %s", hero.name, string.rep("★", o.stars) .. string.rep("☆", HeroData.MAX_STARS - o.stars))
			bonusL.Text = string.format("%s · nível %d · poder %d · %s", rarity, o.level or 1, Economy.heroPowerOf(hero, o), heroBonusText(hero, o))
			local inCouncil = table.find(mm.state.heroes.council, hid) ~= nil
			local t = now()
			if o.expedition then
				local left = (o.expedition.endsAt - t) / 1000
				status.Text = left > 0 and ("Em expedição: volta em " .. fmtTime(left)) or "Voltou da expedição!"
			elseif o.training then
				status.Text = "Treinando no Quartel: " .. fmtTime((o.training.endsAt - t) / 1000)
			else
				status.Text = inCouncil and "No Conselho: o bônus vale para o reino." or "Livre"
			end
			council.Text = inCouncil and "Tirar do Conselho" or "Pôr no Conselho"
			council.Visible = not o.expedition
			for _, b in expButtons do b.Visible = not inCouncil and not o.expedition and not o.training end
			collect.Visible = o.expedition ~= nil
			if o.expedition then
				local left = (o.expedition.endsAt - t) / 1000
				collect.Text = left > 0 and ("Acelerar: " .. Heroes.expeditionSpeedUpCost(left) .. " gemas") or "Coletar recompensa"
			end
			local cap = Heroes.heroLevelCap(mm.state)
			train.Visible = Heroes.trainingSlots(mm.state) > 0 and not o.expedition and ((o.level or 1) < cap or o.training ~= nil)
			if o.training then
				train.Text = "Acelerar: " .. Heroes.speedUpCost(math.max(0, (o.training.endsAt - t) / 1000)) .. " gemas"
			else
				train.Text = "Treinar: " .. costText(Heroes.trainCost(hero, o.level or 1), mm.state.res)
			end
		end)
	end
end

-- ------------------------------------------------------------ aba Temporada
local function buildSeason(m)
	local s = m.state
	local info = Season.seasonInfo(now())
	title(string.format("Temporada %d: %s", info.number, info.theme.name))
	local c = card()
	line(info.theme.desc, c, { FontFace = FONT_REGULAR })
	local prog = line("", c)
	bind(function(mm)
		local tier = Season.tierOf(mm.state.season.xp)
		prog.Text = string.format("Passe: nível %d de %d · %d XP · acaba em %s", tier, Seasons.SEASON_TIERS, mm.state.season.xp, fmtTime(Season.seasonInfo(now()).remaining))
	end)

	local dc = card()
	title("Presente do dia", dc)
	local daily = button("", dc, function() act("claimDaily") end)
	bind(function(mm)
		local st = mm:dailyStatus()
		daily.Text = st.available and string.format("Pegar o dia %d: %s", st.nextStreak, st.reward.label) or string.format("Volte amanhã (sequência de %d dias)", mm.state.daily.streak)
		setEnabled(daily, st.available)
	end)

	local mc = card()
	title("Missões do dia", mc)
	for i = 1, 3 do
		local b = button("", mc, function() act("claimMission", i) end, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		bind(function(mm)
			local list = mm.state.season.missions and mm.state.season.missions.list
			local mi = list and list[i]
			b.Visible = mi ~= nil
			if not mi then return end
			local done = mi.progress >= mi.target
			b.Text = string.format("%s: %s/%s · %d XP%s", Season.missionText(mi), fmt(math.floor(mi.progress)), fmt(mi.target), mi.xp, mi.claimed and " (pego)" or (done and " · pegar" or ""))
			setEnabled(b, done and not mi.claimed)
		end)
	end

	local pc = card()
	title("Passe da temporada (grátis)", pc)
	for tier = 1, Seasons.SEASON_TIERS do
		local reward = Season.rewardFor(tier, s)
		local b = button("", pc, function() act("claimTier", tier) end, { Size = UDim2.new(1, 0, 0, 30), TextSize = 13 })
		bind(function(mm)
			local reached = Season.tierOf(mm.state.season.xp) >= tier
			local claimed = table.find(mm.state.season.claimed, tier) ~= nil
			b.Text = string.format("Nível %d: %s%s", tier, reward.label, claimed and " (pego)" or (reached and " · pegar" or ""))
			setEnabled(b, reached and not claimed)
		end)
	end
end

-- ------------------------------------------------------------ aba Legado
local function buildLegacy(m)
	title("Legado")
	local c = card()
	local crowns = line("", c)
	local advice = line("", c, { FontFace = FONT_REGULAR })
	local asc = button("", c, function()
		if ui.confirmAscend then
			ui.confirmAscend = false
			act("ascend")
		else
			ui.confirmAscend = true
			refresh()
		end
	end, { BackgroundColor3 = C.purple, TextColor3 = C.paper2 })
	bind(function(mm)
		local a = mm:ascendAdvice()
		crowns.Text = string.format("Coroas: %d · Ascender agora dá %d", mm.state.res.crowns, a.crowns)
		if a.crowns < 1 then
			advice.Text = "Junte mais ouro nesta rodada para ganhar a primeira Coroa."
			if a.secondsToNext >= 0 then advice.Text ..= " Falta cerca de " .. fmtTime(a.secondsToNext) .. "." end
		elseif a.recommended then
			advice.Text = "Vale a pena: a Ascensão pelo menos dobra as suas Coroas."
		else
			advice.Text = "Dá para ascender, mas esperar rende mais Coroas."
		end
		asc.Text = ui.confirmAscend and "Confirmar: recomeçar o reino" or "Ascender"
		setEnabled(asc, a.crowns >= 1)
	end)
	for _, t in Talents.TALENTS do
		local tc = card()
		local head = title("", tc)
		local desc = line("", tc, { FontFace = FONT_REGULAR })
		local b = button("", tc, function() act("buyTalent", t.id) end)
		bind(function(mm)
			local lvl = mm.state.legacy[t.id] or 0
			head.Text = string.format("%s · %d/%d", t.name, lvl, t.max)
			desc.Text = lvl > 0 and ("Agora: " .. t.desc(lvl)) or t.desc(1)
			local cost = mm:talentCost(t.id)
			b.Text = cost and string.format("Comprar nível %d: %d coroa(s)", lvl + 1, cost) or "Nível máximo"
			setEnabled(b, cost ~= nil and mm.state.res.crowns >= cost)
		end)
	end
end

-- ------------------------------------------------------------ aba Social
local function buildSocial(m)
	title("Reinos vizinhos")
	line("Ranking pelo Poder do Reino. Saude e troque recursos uma vez por hora com cada vizinho.", nil, { FontFace = FONT_REGULAR })
	for pos, r in m:rivals() do
		local c = card(nil, r.me and Color3.fromHex("#fff3c4") or nil)
		title(string.format("%d. %s", pos, r.name), c)
		line(string.format("%s · %s · poder %s", r.ruler, r.title, fmt(r.power)), c, { FontFace = FONT_REGULAR })
		if not r.me then
			local rr = row(c)
			button("Saudar", rr, function() act("greetRival", r.id) end)
			for _, res in { "food", "wood", "stone" } do
				button("Trocar " .. string.lower(RES_NAMES[res]), rr, function() act("tradeRival", r.id, res) end, { BackgroundColor3 = C.paper3 })
			end
		end
	end
end

-- ------------------------------------------------------------ aba Perfil
local function buildProfile(m)
	local s = m.state
	title("Seu reino")
	local c = card()
	local box = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.paper3, Text = s.kingdom.name, PlaceholderText = "Nome do reino",
		FontFace = FONT, TextSize = 16, TextColor3 = C.text, ClearTextOnFocus = false, LayoutOrder = nextOrder(), ZIndex = 103, Parent = c,
	}, { corner(8) })
	button("Salvar nome", c, function() act("setKingdomName", box.Text) end)
	local tl = line("", c)
	bind(function(mm) tl.Text = "Título: " .. mm.state.kingdom.title end)
	local tr = row(c)
	for _, t in s.cosmetics.titles do
		button(t, tr, function() act("equip", "title", t) end, { BackgroundColor3 = C.paper3, TextSize = 13 })
	end
	local sc = card()
	title("Estatísticas", sc)
	local st = line("", sc, { FontFace = FONT_REGULAR })
	bind(function(mm)
		local x = mm.state.stats
		st.Text = string.format(
			"Ouro na vida: %s\nOuro nesta rodada: %s\nConstruções: %d · melhorias: %d\nHordas vencidas: %d · perdidas: %d\nHeróis recrutados: %d · expedições: %d\nCarroças: %d · ascensões: %d\nTempo de jogo: %s\nPoder do Reino: %s",
			fmt(x.totalGold), fmt(x.runGold), x.built, x.upgrades, x.raidsWon, x.raidsLost, x.recruits, x.expeditions, x.chests,
			x.ascensions, fmtTime(x.playTime), fmt(Economy.kingdomPower(mm.state)))
	end)
	local lc = card()
	title("Diário do reino", lc)
	local logL = line("", lc, { FontFace = FONT_REGULAR, TextSize = 13 })
	bind(function(mm)
		local lines = {}
		for _, l in mm.state.log or {} do table.insert(lines, l.text) end
		logL.Text = #lines > 0 and table.concat(lines, "\n") or "Nada por enquanto."
	end)
end

-- ------------------------------------------------------------ abas
local TABS = { { "reino", "Reino" }, { "herois", "Heróis" }, { "temporada", "Temporada" }, { "legado", "Legado" }, { "social", "Social" }, { "perfil", "Perfil" } }
local tabButtons = {}
for n, t in TABS do
	local b = new("TextButton", {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 32), BackgroundColor3 = C.paper2, Text = t[2], FontFace = FONT,
		TextSize = 14, TextColor3 = C.text, LayoutOrder = n, ZIndex = 101, Parent = tabsBar,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	b.MouseButton1Click:Connect(function()
		ui.tab = t[1]
		ui.confirmAscend = false
		refresh()
	end)
	tabButtons[t[1]] = b
end

local function computePanelKey(m)
	local s = m.state
	local parts = { ui.tab, ui.layer, ui.build or "-", ui.moveFrom and (ui.moveFrom.x .. "," .. ui.moveFrom.y) or "-", tostring(ui.confirmAscend) }
	local focus = ui.sel
	if ui.build and not TOUCH and ui.hover then focus = ui.hover end
	if focus then
		table.insert(parts, focus.x .. "," .. focus.y)
		if ui.layer == 0 then
			local t = s.grid.tiles[idx(focus.x, focus.y)]
			table.insert(parts, t.t .. (t.b and t.b.id or "") .. tostring(Map.isUnlocked(s.grid, focus.x, focus.y)))
		else
			local t = Under.levelOf(s, ui.layer).tiles[idx(focus.x, focus.y)]
			table.insert(parts, t.t .. tostring(t.s) .. (t.b and t.b.id or "") .. (t.st or ""))
		end
	end
	if ui.tab == "herois" then
		local ids = Util.keys(s.heroes.owned)
		table.sort(ids)
		table.insert(parts, table.concat(ids, ","))
		table.insert(parts, table.concat(s.heroes.council, ","))
	elseif ui.tab == "perfil" then
		table.insert(parts, s.kingdom.name .. #s.cosmetics.titles)
	elseif ui.tab == "temporada" then
		table.insert(parts, s.season.number)
	elseif ui.tab == "social" then
		table.insert(parts, math.floor(now() / 60000))
	end
	return table.concat(parts, "|")
end

local function rebuildPanel(m)
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	updaters = {}
	order = 0
	if ui.tab == "reino" then
		if ui.layer > 0 then
			buildUnderPanel(m)
		else
			buildInspector(m)
			buildPalette(m)
		end
	elseif ui.tab == "herois" then
		buildHeroes(m)
	elseif ui.tab == "temporada" then
		buildSeason(m)
	elseif ui.tab == "legado" then
		buildLegacy(m)
	elseif ui.tab == "social" then
		buildSocial(m)
	else
		buildProfile(m)
	end
end

-- ------------------------------------------------------------ desenho do mapa
local function drawSurface(m)
	local s = m.state
	local grid = s.grid
	local t = now()
	for i, cell in cells do
		local x, y = Map.xy(i)
		local tile = grid.tiles[i]
		cell.ground.Visible = true
		-- Chão: sob prédios, sempre grama.
		local base
		if tile.b or tile.t ~= "water" then
			base = pickName({ "grass-1", "grass-2" }, tile.b and (i - 1) or ((i - 1) * 7 + 3))
		else
			base = pickName({ "water-1", "water-2" }, (i - 1) * 7 + 3)
		end
		if not setSprite(cell.ground, base) then
			cell.ground.BackgroundColor3 = tile.b and TERRAIN_COLOR.grass or TERRAIN_COLOR[tile.t]
			cell.ground.BackgroundTransparency = 0
		else
			cell.ground.BackgroundTransparency = 1
		end
		-- Natureza ou prédio por cima.
		local over, name = nil, nil
		local info = m.econ.tiles[i]
		if tile.b then
			local id = tile.b.id
			if id == "muralha" then
				local mask = Map.wallMask(grid, x, y)
				over = mask > 0 and ("building-muralha-" .. mask) or "building-muralha"
			elseif (id == "taverna" or id == "quartel") and tile.b.lvl >= 5 then
				over = "building-" .. id .. (tile.b.lvl >= 10 and "-10" or "-5")
			else
				over = "building-" .. id
			end
			name = BUILDINGS[id].name
		elseif tile.t == "forest" then
			over = pickName({ "forest-1", "forest-2", "forest-3", "forest-4" }, i - 1)
		elseif tile.t == "rock" then
			over = pickName({ "rock-1", "rock-2" }, i - 1)
		elseif tile.t == "mountain" then
			over = pickName({ "mountain-1", "mountain-2" }, i - 1)
		elseif tile.t == "sapling" then
			over = ((t - (tile.p or 0)) / 1000 / Buildings.GROW_SECONDS < 0.5) and "sapling-1" or "sapling-2"
		end
		local shown = setSprite(cell.over, over)
		cell.over.Visible = shown
		local dim = info and (not info.active or (info.workers > 0 and info.staff < 0.5))
		cell.over.ImageTransparency = dim and 0.4 or 0
		cell.fallback.Visible = not shown and name ~= nil
		if name then
			cell.fallback.Text = string.sub(name, 1, 7)
			cell.fallback.BackgroundTransparency = dim and 0.5 or 0
		end
		local unlocked = Map.isUnlocked(grid, x, y)
		cell.lock.Visible = not unlocked
		cell.lock.BackgroundTransparency = Map.ringOf(x, y) == grid.ring + 1 and 0.5 or 0.38
		cell.badge.Visible = tile.b ~= nil and tile.b.lvl > 1
		if tile.b then cell.badge.Text = tostring(tile.b.lvl) end
		cell.warn.Visible = info ~= nil and not info.active
	end
	-- Contorno do território.
	local lo = math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5)
	border.Visible = true
	border.Position = UDim2.fromScale(lo / GRID_W, lo / GRID_H)
	border.Size = UDim2.fromScale((GRID_W - 2 * lo) / GRID_W, (GRID_H - 2 * lo) / GRID_H)
	-- Carroça do mercador.
	if s.chest then
		chestLabel.Visible = true
		chestLabel.Position = UDim2.fromScale(s.chest.x / GRID_W, (s.chest.y + 0.25) / GRID_H)
	else
		chestLabel.Visible = false
	end
	-- De onde vem a próxima horda.
	raidLabel.Visible = true
	local dir = s.raid.dir
	local pos = ({ n = { 0.5, 0.035 }, s = { 0.5, 0.965 }, e = { 0.79, 0.5 }, w = { 0.21, 0.5 } })[dir]
	raidLabel.Position = UDim2.fromScale(pos[1], pos[2])
	raidLabel.Text = "Horda vem " .. DIR_FROM[dir]
	raidLabel.BackgroundTransparency = s.raid.warned and 0 or 0.35
end

local function drawUnder(m)
	local d = ui.layer
	local lv = Under.levelOf(m.state, d)
	local infos = m.econ.under[d] or {}
	for i, cell in cells do
		local t = lv.tiles[i]
		cell.lock.Visible = false
		cell.badge.Visible = false
		cell.warn.Visible = false
		cell.fallback.Visible = false
		if not t.s then
			cell.ground.Image = ""
			cell.ground.BackgroundColor3 = Color3.fromHex("#121019")
			cell.ground.BackgroundTransparency = 0
			cell.over.Visible = false
		else
			local list = ({ rock = { "u-rock-1", "u-rock-2" }, floor = { "u-floor-1", "u-floor-2" }, cavern = { "u-cavern-1", "u-cavern-2" } })[t.t] or { "u-" .. t.t }
			if setSprite(cell.ground, pickName(list, i - 1)) then
				cell.ground.BackgroundTransparency = 1
			else
				cell.ground.BackgroundColor3 = UNDER_COLOR[t.t]
				cell.ground.BackgroundTransparency = 0
			end
			local over = t.b and ("room-" .. t.b.id) or nil
			local shown = setSprite(cell.over, over)
			cell.over.Visible = shown
			local labelText = t.b and UnderData.ROOMS[t.b.id].name or (t.st == "down" and "Desce" or (t.st == "up" and "Sobe" or nil))
			if labelText and (not shown or t.st) then
				cell.fallback.Visible = true
				cell.fallback.Text = string.sub(labelText, 1, 7)
				cell.fallback.BackgroundTransparency = 0
			end
			if t.b then
				cell.badge.Visible = t.b.lvl > 1
				cell.badge.Text = tostring(t.b.lvl)
				local inf = infos[i]
				cell.warn.Visible = inf ~= nil and not inf.active
			end
		end
	end
	border.Visible = false
	chestLabel.Visible = false
	raidLabel.Visible = false
end

local function drawSelection(m)
	local function place(box, p)
		box.Visible = p ~= nil
		if p then box.Position = UDim2.fromScale(p.x / GRID_W, p.y / GRID_H) end
	end
	place(selBox, ui.moveFrom or ui.sel)
	place(hoverBox, (not TOUCH) and ui.hover or nil)
	for _, l in adjLabels do l.Visible = false end
	if ui.layer ~= 0 then return end
	local parts
	local focus = ui.sel
	if ui.build and not TOUCH and ui.hover then focus = ui.hover end
	if focus then
		if ui.build then
			parts = Economy.adjacencyAt(m.state, ui.build, focus.x, focus.y, m.econ.mods).parts
		else
			local info = m.econ.tiles[idx(focus.x, focus.y)]
			parts = info and info.adjParts
		end
	end
	for k, p in parts or {} do
		local l = adjLabels[k]
		if l then
			l.Visible = true
			l.Position = UDim2.fromScale((p.x + 0.5) / GRID_W, (p.y + 0.25) / GRID_H)
			l.Text = fmtPct(p.value)
			l.TextColor3 = p.value > 0 and Color3.fromHex("#9be7a8") or Color3.fromHex("#ffb3a6")
		end
	end
end

-- ------------------------------------------------------------ barra de cima
local function drawTop(m)
	local s, e = m.state, m.econ
	for _, r in { "gold", "food", "wood", "stone" } do
		local rate = e.rates[r]
		local full = s.res[r] >= e.caps[r] - 0.5
		resLabels[r].Text = string.format('%s <b>%s</b>%s <font size="12" color="#b5aec4">%s</font>', RES_NAMES[r], fmt(s.res[r]),
			full and ' <font color="#ffb3a6">(cheio)</font>' or "", fmtRate(rate))
	end
	resLabels.gems.Text = "Gemas <b>" .. fmt(s.res.gems) .. "</b>"
	resLabels.crowns.Text = "Coroas <b>" .. fmt(s.res.crowns) .. "</b>"
	resLabels.crowns.Visible = s.res.crowns > 0 or s.stats.ascensions > 0
	resLabels.pop.Text = string.format("Moradores <b>%d/%d</b>", math.floor(s.pop), e.popCap)
	resLabels.happy.Text = string.format("Felicidade <b>%d</b>", Util.round(e.happiness))
	local strength = m:raidStrength()
	resLabels.defense.Text = string.format('Defesa <b><font color="%s">%s</font></b> / %s', e.defense >= strength and "#9be7a8" or "#ffb3a6", fmt(e.defense), fmt(strength))

	local t = now()
	local bits = {}
	if not s.tutorial.done and Game.TUTORIAL[s.tutorial.step + 1] then
		table.insert(bits, '<font color="#ffd45c">Próximo passo:</font> ' .. Game.TUTORIAL[s.tutorial.step + 1].text)
	end
	local raidName = s.raid.name or "Uma horda"
	table.insert(bits, string.format("%s %s em %s, força %d.", raidName, DIR_FROM[s.raid.dir], fmtTime((s.raid.nextAt - t) / 1000), strength))
	if s.event and s.event.endsAt > t then
		local ev = Events.EVENT_BY_ID[s.event.id]
		table.insert(bits, string.format('<font color="#ffd45c">%s: %s</font> (%s)', ev.name, ev.desc, fmtTime((s.event.endsAt - t) / 1000)))
	end
	if s.boostUntil > t then
		table.insert(bits, "Bênção +50%: " .. fmtTime((s.boostUntil - t) / 1000))
	end
	infoLine.Text = table.concat(bits, "   ")
end

-- ------------------------------------------------------------ tudo junto
function refresh()
	if not mirror then return end
	local m = mirror
	-- Abas ainda não liberadas ficam escondidas (desbloqueio gradual, como no jogo web).
	for id, b in tabButtons do
		b.Visible = m:isTabUnlocked(id)
		b.BackgroundColor3 = ui.tab == id and C.gold or C.paper2
	end
	if not m:isTabUnlocked(ui.tab) then ui.tab = "reino" end
	-- Subsolo: só os níveis já descobertos.
	local reached = m.state.under.reached
	for d, b in layerButtons do
		b.Visible = reached > 0 and d <= reached
		b.BackgroundColor3 = ui.layer == d and C.gold or C.ink3
		b.TextColor3 = ui.layer == d and C.ink or C.onInk
	end
	if ui.layer > reached then ui.layer = 0 end
	undoButton.Visible = m.state.canUndo == true and ui.layer == 0

	drawTop(m)
	if ui.layer == 0 then drawSurface(m) else drawUnder(m) end
	drawSelection(m)

	local key = computePanelKey(m)
	if key ~= panelKey then
		panelKey = key
		local scroll = content.CanvasPosition
		rebuildPanel(m)
		content.CanvasPosition = scroll
	else
		for _, fn in updaters do fn(m) end
	end
end

-- ------------------------------------------------------------ cliques no mapa
local function onTile(x, y)
	if not mirror then return end
	ui.confirmSell = false
	if ui.layer > 0 then
		ui.sel = { x = x, y = y }
		refresh()
		return
	end
	if ui.moveFrom then
		local from = ui.moveFrom
		ui.moveFrom = nil
		ui.sel = { x = x, y = y }
		act("move", from.x, from.y, x, y)
		refresh()
		return
	end
	local s = mirror.state
	if s.chest and s.chest.x == x and s.chest.y == y then
		act("openChest")
		return
	end
	if ui.build then
		-- No celular, o 1º toque mostra a prévia e o 2º constrói (igual ao jogo web).
		if TOUCH and not (ui.sel and ui.sel.x == x and ui.sel.y == y) then
			ui.sel = { x = x, y = y }
			refresh()
			return
		end
		act("build", ui.build, x, y)
		ui.sel = { x = x, y = y }
		refresh()
		return
	end
	if ui.sel and ui.sel.x == x and ui.sel.y == y then
		ui.sel = nil
	else
		ui.sel = { x = x, y = y }
	end
	refresh()
end

for i, cell in cells do
	local x, y = Map.xy(i)
	cell.hit.MouseButton1Click:Connect(function() onTile(x, y) end)
	cell.hit.MouseEnter:Connect(function()
		ui.hover = { x = x, y = y }
		if not mirror then return end
		if ui.build then refresh() else drawSelection(mirror) end
	end)
	cell.hit.MouseLeave:Connect(function()
		if ui.hover and ui.hover.x == x and ui.hover.y == y then
			ui.hover = nil
			if mirror then refresh() end
		end
	end)
end

-- ------------------------------------------------------------ teclado (mesmos atalhos do jogo web)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not mirror then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.Escape then
		ui.build, ui.moveFrom, ui.sel = nil, nil, nil
	elseif k == Enum.KeyCode.Z then
		act("undoBuild")
	elseif k == Enum.KeyCode.U and ui.sel and ui.layer == 0 then
		act("upgrade", ui.sel.x, ui.sel.y)
	elseif k == Enum.KeyCode.M and ui.sel and ui.layer == 0 then
		local t = mirror.state.grid.tiles[idx(ui.sel.x, ui.sel.y)]
		if t.b then ui.moveFrom = ui.sel end
	elseif (k == Enum.KeyCode.Delete or k == Enum.KeyCode.Backspace) and ui.sel and ui.layer == 0 then
		act("sell", ui.sel.x, ui.sel.y)
		ui.sel = nil
	elseif k == Enum.KeyCode.T then
		local list = {}
		for _, t in TABS do
			if mirror:isTabUnlocked(t[1]) then table.insert(list, t[1]) end
		end
		local at = table.find(list, ui.tab) or 0
		ui.tab = list[at % #list + 1]
	else
		local digits = {
			[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
			[Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
		}
		local n = digits[k]
		if not n then return end
		local id = Buildings.BUILDING_ORDER[n]
		if mirror:isAvailable(id) then
			ui.tab = "reino"
			ui.layer = 0
			ui.build = ui.build ~= id and id or nil
		end
	end
	refresh()
end)

-- ------------------------------------------------------------ avisos dos eventos do jogo
local function gainsText(g)
	local parts = {}
	for _, r in Economy.PROD_RES do
		if g[r] and math.abs(g[r]) >= 1 then
			table.insert(parts, (g[r] > 0 and "+" or "") .. fmt(g[r]) .. " " .. string.lower(RES_NAMES[r]))
		end
	end
	return table.concat(parts, ", ")
end

local EVENT_TEXT = {
	toast = function(d) return d.text, d.kind end,
	raidWarning = function(d)
		return string.format("%s chegando %s em 20 s! Força %d, sua defesa %s.", d.name, DIR_FROM[d.dir], d.strength, fmt(d.defense)), "raid"
	end,
	raid = function(d)
		if d.win then
			return string.format("Vitória contra %s! +%s de ouro, +%d gema(s).", d.name, fmt(d.loot), d.gems), "good"
		end
		local g = {}
		for r, v in d.lost do g[r] = -v end
		return string.format("%s saquearam o reino: %s.", d.name, gainsText(g)), "bad"
	end,
	event = function(d) return d.name .. ": " .. d.desc, "gold" end,
	chest = function() return "Uma carroça do mercador apareceu no mapa! Toque nela.", "gold" end,
	chestOpened = function(d)
		local r = d.reward
		if r.boost then return "Carroça: Bênção de +50% de produção por " .. r.boost .. " min!", "good" end
		return "Carroça: " .. yieldText(r), "good"
	end,
	achievement = function(d) return string.format("Conquista: %s (+%d gemas)%s", d.name, d.gems, d.title and (". Título novo: " .. d.title) or ""), "good" end,
	tutorial = function() return "Passo concluído! Recompensa recebida.", "good" end,
	unlock = function(d) return "Nova aba liberada: " .. d.name, "season" end,
	tierUp = function(d) return string.format("Passe da temporada: nível %d!", d.tier), "season" end,
	recruited = function(d)
		if d.isNew then return "Novo herói: " .. d.name .. "!", "good" end
		if d.gemsRefund > 0 then return string.format("%s já está no máximo: +%d gemas.", d.name, d.gemsRefund), "info" end
		return string.format("%s ganhou uma estrela (%d).", d.name, d.stars), "good"
	end,
	expeditionDone = function(d) return "Expedição: " .. yieldText(d.reward), "good" end,
	underOpened = function() return "A Escadaria abriu caminho para o subsolo! Use os botões em cima do mapa.", "season" end,
	dug = function(d) if d.cavern > 0 then return "Os mineiros romperam uma caverna!", "season" end return nil end,
	ascended = function(d) return string.format("Ascensão! +%d Coroas. Um novo reino começa.", d.crowns), "season" end,
	expanded = function(d) return "O reino cresceu! Novas terras liberadas.", "good" end,
	grown = function(d) return d.n > 1 and (d.n .. " mudas viraram floresta.") or "Uma muda virou floresta.", "info" end,
	offline = function(d)
		return string.format("Enquanto você esteve fora (%s): %s.%s", fmtTime(d.elapsed), gainsText(d.gains),
			d.capped and " O reino guarda no máximo algumas horas de produção." or ""), "good"
	end,
}

-- ------------------------------------------------------------ estado chegando do servidor
estado.OnClientEvent:Connect(function(snap, events, serverNow)
	timeOffset = serverNow - DateTime.now().UnixTimestampMillis
	if snap.under then
		lastUnder = snap.under
	else
		snap.under = lastUnder
	end
	if not snap.under then return end
	mirror = Game.new(snap, serverNow)
	for _, ev in events or {} do
		local fn = EVENT_TEXT[ev[1]]
		if fn then
			local text, kind = fn(ev[2] or {})
			if text then toast(text, kind) end
		end
	end
	refresh()
end)

-- Pede o estado completo assim que a tela abre (o primeiro envio do servidor pode ter chegado antes).
act("sync")

-- Contagens regressivas andam entre um estado e outro.
task.spawn(function()
	while true do
		task.wait(0.5)
		if mirror then
			drawTop(mirror)
		end
	end
end)

