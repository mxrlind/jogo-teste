-- Avisos (toast() de src/ui/modals.js) e o aviso "no lugar errado? Desfazer" (renderUndo de src/ui/app.js).
-- Estilo do #toasts / .toast do styles.css: pilha embaixo no centro (no celular, em cima), no máximo 5,
-- faixa colorida à esquerda (box-shadow inset 3px) e ícone na cor do tipo, entrada "tin" e saída ".out".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Buildings = require(Reino.Data.Buildings)
local Config = require(Reino.Core.Config)
local GameMod = require(Reino.Core.Game)

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)

local h = Kit.h
local hex = T.hex

local Toasts = {}

local LIFE = 4.2 -- s até começar a sair (setTimeout 4200)
local OUT = 0.35 -- transition: opacity .35s, transform .35s var(--ease)
local IN = 0.3 -- animation: tin .3s var(--ease-back)
local MAX = 5
local UNDO_WINDOW = GameMod.UNDO_WINDOW

-- --tc de cada tipo.
local KIND_COLOR = {
	info = hex("#7cb8f0"),
	good = hex("#7fd893"),
	bad = hex("#ff8f7d"),
	event = hex("#c5b0ff"),
	season = hex("#ffd45c"), -- var(--gold-hi)
	undo = hex("#ffd45c"),
}

-- ------------------------------------------------------------ curvas (cubic-bezier do CSS)
local function bezier(x1, y1, x2, y2)
	local function at(a1, a2, t)
		local u = 1 - t
		return 3 * u * u * t * a1 + 3 * u * t * t * a2 + t * t * t
	end
	return function(x)
		if x <= 0 then
			return 0
		elseif x >= 1 then
			return 1
		end
		-- Acha t com x(t) = x por bisseção (precisão de sobra para animação de interface).
		local lo, hi = 0, 1
		local t = x
		for _ = 1, 18 do
			local cx = at(x1, x2, t)
			if cx < x then
				lo = t
			else
				hi = t
			end
			t = (lo + hi) / 2
		end
		return at(y1, y2, t)
	end
end
local EASE = bezier(0.2, 0.8, 0.2, 1) -- --ease
local EASE_BACK = bezier(0.3, 1.5, 0.5, 1) -- --ease-back

-- ------------------------------------------------------------ estado
local box: Frame? = nil
local listLayout: UIListLayout? = nil
local sizeLimit: UISizeConstraint? = nil
local items = {} -- { wrap, body, scale, shadow, shadowBase, born, outAt, seq, undo }
local seq = 0
local undoItem = nil
local layoutMobile = nil
local layoutRem = nil

-- Ponteiro grosso (toque sem mouse): o atalho de teclado some do botão Desfazer (@media (pointer: coarse)).
local function coarse()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- #toasts: embaixo no centro, largura min(30rem, 100% - 2rem); no celular (<= 860 px) em cima, 8 px das bordas,
-- e a ordem inverte (column-reverse no PC: o mais novo fica embaixo; column no celular: o mais novo fica em cima).
local function applyLayout()
	if not box then
		return
	end
	local mobile = Ctx.mobile
	local r1 = T.rem(1)
	if mobile == layoutMobile and r1 == layoutRem then
		return
	end
	layoutMobile, layoutRem = mobile, r1
	local b = box :: Frame
	if mobile then
		b.AnchorPoint = Vector2.new(0, 0)
		b.Position = UDim2.fromOffset(8, 8)
		b.Size = UDim2.new(1, -16, 1, -16)
		;(sizeLimit :: UISizeConstraint).MaxSize = Vector2.new(math.huge, math.huge)
		;(listLayout :: UIListLayout).VerticalAlignment = Enum.VerticalAlignment.Top
	else
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.fromScale(0.5, 0)
		b.Size = UDim2.new(1, -T.rem(2), 1, -T.rem(1))
		;(sizeLimit :: UISizeConstraint).MaxSize = Vector2.new(T.rem(30), math.huge)
		;(listLayout :: UIListLayout).VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	;(listLayout :: UIListLayout).Padding = UDim.new(0, T.rem(0.45))
	for _, it in items do
		it.wrap.LayoutOrder = mobile and -it.seq or it.seq
	end
end

-- ------------------------------------------------------------ montagem de um aviso
-- Estrutura: wrap (item da lista, altura medida) > sombra + CanvasGroup (opacidade e escala) com a cor --tc
-- de fundo e, por cima, o fundo escuro deslocado 3 px: sobra a faixa curva da esquerda, como o inset do CSS.
local function makeItem(kind, contentNode, undo)
	local tc = KIND_COLOR[kind] or KIND_COLOR.info
	seq += 1
	local wrap = Instance.new("Frame")
	wrap.Name = undo and "Desfazer" or "Toast"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.LayoutOrder = Ctx.mobile and -seq or seq

	local shadowNode = U.shadow("md")
	local shadow = Kit.mount(shadowNode, wrap) :: ImageLabel
	local shadowBase = shadow.ImageTransparency

	local body = Instance.new("CanvasGroup")
	body.Name = "Corpo"
	body.BackgroundColor3 = tc
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0)
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.ZIndex = 1
	body.Parent = wrap
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, T.r)
	corner.Parent = body
	local scale = Instance.new("UIScale")
	scale.Parent = body

	-- background: rgba(31, 29, 39, .97)
	local fill = Instance.new("Frame")
	fill.Name = "Fundo"
	fill.BackgroundColor3 = hex("#1f1d27")
	fill.BackgroundTransparency = 0.03
	fill.BorderSizePixel = 0
	fill.Position = UDim2.fromOffset(3, 0)
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 1
	fill.Parent = body
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, T.r)
	fc.Parent = fill

	-- border: 1px solid rgba(255, 255, 255, .1) (no .bad: rgba(255, 143, 125, .3)). Fica 1 px para dentro
	-- porque o CanvasGroup corta o que passa da borda.
	local edge = Instance.new("Frame")
	edge.Name = "Borda"
	edge.BackgroundTransparency = 1
	edge.Position = UDim2.fromOffset(0, 0)
	edge.Size = UDim2.fromScale(1, 1)
	edge.ZIndex = 3
	edge.Parent = body
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0, T.r)
	ec.Parent = edge
	local es = Instance.new("UIStroke")
	es.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	es.Thickness = 1
	if kind == "bad" then
		es.Color = hex("#ff8f7d")
		es.Transparency = 0.7
	else
		es.Color = hex("#ffffff")
		es.Transparency = 0.9
	end
	-- UIStroke desenha por fora; com o quadro 1 px menor que o corpo, a linha cai dentro do corte.
	edge.Position = UDim2.fromOffset(1, 1)
	edge.Size = UDim2.new(1, -2, 1, -2)
	ec.CornerRadius = UDim.new(0, T.r - 1)
	es.Parent = edge

	local content = Kit.mount(contentNode, body) :: GuiObject
	content.ZIndex = 2

	local it = {
		wrap = wrap, body = body, scale = scale, shadow = shadow, shadowBase = shadowBase,
		born = os.clock(), outAt = (not undo) and os.clock() + LIFE or nil, seq = seq, undo = undo,
		animIn = not Ctx.config.reduceMotion,
	}
	-- A altura do item na lista é a do corpo sem a escala da animação.
	local function measure()
		local s = scale.Scale
		if s <= 0 then
			return
		end
		wrap.Size = UDim2.new(1, 0, 0, math.floor(body.AbsoluteSize.Y / s + 0.5))
	end
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
	it.measure = measure
	wrap.Parent = box
	measure()
	return it
end

-- Conteúdo de um aviso comum: ícone (1.5rem, margem 0 .1rem 0 .2rem, cor --tc) + texto (.92rem, altura de linha 1.3).
local function toastContent(text, kind, icon)
	local tc = KIND_COLOR[kind] or KIND_COLOR.info
	local rem = T.rem
	local icoW = icon and (rem(1.5) + rem(0.3)) or 0
	local gap = rem(0.6)
	return h("Frame", {
		Name = "Conteudo",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		-- padding: .55rem .8rem .55rem .55rem (+3 px da faixa)
		Kit.pad(rem(0.55), rem(0.8), rem(0.55), rem(0.55) + 3),
		Kit.list("x", { gap = gap, align = "center" }),
		icon and h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(icoW, rem(1.5)) }, {
			U.ico(icon, tc, rem(1.5), { Position = UDim2.fromOffset(rem(0.2), 0) }),
		}) or nil,
		h("TextLabel", {
			BackgroundTransparency = 1,
			Text = tostring(text or ""),
			RichText = false,
			FontFace = T.font,
			TextSize = math.floor(15 * T.fs * 0.92 + 0.5),
			LineHeight = 1.3,
			TextColor3 = T.c.onInk,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -(icoW + (icon and gap or 0)), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}),
	})
end

local function removeItem(it)
	local i = table.find(items, it)
	if i then
		table.remove(items, i)
	end
	if it == undoItem then
		undoItem = nil
	end
	it.wrap:Destroy()
end

-- toast(text, kind = 'info', icon = null)
function Toasts.toast(text, kind, icon)
	if not box then
		return
	end
	kind = kind or "info"
	applyLayout()
	local it = makeItem(kind, toastContent(text, kind, icon), false)
	table.insert(items, it)
	-- O aviso de desfazer não conta nem sai antes da hora.
	local normal = {}
	for _, x in items do
		if not x.undo then
			table.insert(normal, x)
		end
	end
	table.sort(normal, function(a, b)
		return a.seq > b.seq
	end)
	for i = MAX + 1, #normal do
		removeItem(normal[i])
	end
end

-- ------------------------------------------------------------ desfazer
-- O espelho do cliente não tem lastBuild (não vai no estado): o Controller guarda a última obra em
-- Ctx.ui.lastBuild ({ id, x, y, at }) ao receber "built", e o servidor manda canUndo em cada envio.
function Toasts.canUndo(now)
	local g = Ctx.game
	if not g then
		return false
	end
	now = now or Ctx.now()
	if g.lastBuild then
		return g:canUndo(now)
	end
	local u = Ctx.ui.lastBuild
	return u ~= nil and g.canUndoServer == true and now - u.at <= UNDO_WINDOW
end

local function undoContent(u, leftMs)
	local rem = T.rem
	local def = Buildings.BUILDINGS[u.id]
	local name = def and def.name or tostring(u.id)
	local tc = KIND_COLOR.undo
	local gap = rem(0.6)
	local kbd = nil
	if not coarse() then
		-- .toast.undo kbd: 800 .66rem/1 Nunito, fundo rgba(0,0,0,.08), raio 4, padding .15rem .3rem
		kbd = h("Frame", {
			BackgroundColor3 = hex("#000000"),
			BackgroundTransparency = 0.92,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
		}, {
			Kit.corner(4),
			Kit.pad(rem(0.15), rem(0.3)),
			h("TextLabel", {
				BackgroundTransparency = 1,
				Text = Config.keyLabel(Ctx.config.keys.undo or "z"),
				FontFace = T.bold,
				TextSize = rem(0.66),
				LineHeight = 1,
				TextColor3 = hex("#2b2a33"),
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.new(),
			}),
		})
	end
	local btn = U.btn({
		text = "Desfazer",
		small = true,
		onClick = function()
			Ctx.run("undo")
		end,
		children = kbd,
	})
	return h("Frame", {
		Name = "Conteudo",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		h("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			-- padding: .55rem .45rem .55rem .55rem (padding-right: .45rem no .undo)
			Kit.pad(rem(0.55), rem(0.45), rem(0.55), rem(0.55) + 3),
			Kit.list("x", { gap = gap, align = "center" }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(1.8), rem(1.5)) }, {
				U.ico("time", tc, rem(1.5), { Position = UDim2.fromOffset(rem(0.2), 0) }),
			}),
			h("TextLabel", {
				BackgroundTransparency = 1,
				Text = "<b>" .. U.esc(name) .. "</b> no lugar errado?",
				RichText = true,
				FontFace = T.font,
				TextSize = math.floor(15 * T.fs * 0.92 + 0.5),
				LineHeight = 1.3,
				TextColor3 = T.c.onInk,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			}, { Kit.flex(1) }),
			btn,
		}),
		-- .undo-bar: 3 px dourada no rodapé, encolhe da largura toda até zero no tempo que falta.
		(not Ctx.config.reduceMotion) and h("Frame", {
			Name = "Barra",
			BackgroundColor3 = T.c.gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			attrs = { left = leftMs },
		}) or nil,
	})
end

function Toasts.renderUndo()
	if not box then
		return
	end
	local g = Ctx.game
	local u = Ctx.ui.lastBuild
	local now = Ctx.now()
	if not g or not u or Ctx.ui.visiting or Ctx.ui.screen ~= "game" or not Toasts.canUndo(now) then
		if undoItem then
			removeItem(undoItem)
		end
		return
	end
	if undoItem and undoItem.at == u.at then
		return
	end
	if undoItem then
		removeItem(undoItem)
	end
	applyLayout()
	local left = math.max(0, UNDO_WINDOW - (now - u.at))
	local it = makeItem("undo", undoContent(u, left), true)
	it.at = u.at
	it.barLeft = left / 1000
	it.bar = it.body:FindFirstChild("Barra", true)
	-- O aviso de desfazer recebe cliques (pointer-events: auto); os outros deixam o clique passar.
	table.insert(items, it)
	undoItem = it
end

-- ------------------------------------------------------------ animação por quadro
local function step()
	applyLayout()
	local now = os.clock()
	for i = #items, 1, -1 do
		local it = items[i]
		local alpha, dy, s = 1, 0, 1
		local age = now - it.born
		if it.animIn and age < IN then
			-- @keyframes tin { from { opacity: 0; transform: translateY(12px) scale(.96); } }
			local k = EASE_BACK(age / IN)
			alpha = math.clamp(k, 0, 1)
			dy = 12 * (1 - k)
			s = 0.96 + 0.04 * k
		end
		if it.outAt and now >= it.outAt then
			-- .toast.out { opacity: 0; transform: translateY(8px) scale(.98); }
			local k = EASE(math.clamp((now - it.outAt) / OUT, 0, 1))
			if now - it.outAt >= 0.5 then
				removeItem(it)
				continue
			end
			alpha = 1 - math.clamp((now - it.outAt) / OUT, 0, 1) -- opacity .35s (linear "ease" do navegador fica perto)
			dy = 8 * k
			s = 1 - 0.02 * k
		end
		it.body.GroupTransparency = 1 - alpha
		it.shadow.ImageTransparency = it.shadowBase + (1 - it.shadowBase) * (1 - alpha)
		if it.scale.Scale ~= s then
			it.scale.Scale = s
			it.measure()
		end
		local hgt = it.wrap.AbsoluteSize.Y
		it.body.Position = UDim2.new(0.5, 0, 0, dy + (1 - s) * hgt / 2)
		it.shadow.Visible = alpha > 0.01
		if it.bar and it.barLeft then
			local f = it.barLeft > 0 and math.clamp(1 - age / it.barLeft, 0, 1) or 0
			it.bar.Size = UDim2.new(f, 0, 0, 3)
		end
	end
end

-- ------------------------------------------------------------ início
function Toasts.init(frame)
	local b = Instance.new("Frame")
	b.Name = "Pilha"
	b.BackgroundTransparency = 1
	b.Parent = frame
	local lim = Instance.new("UISizeConstraint")
	lim.Parent = b
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = b
	box, listLayout, sizeLimit = b, list, lim
	layoutMobile, layoutRem = nil, nil
	applyLayout()
	Ctx.toast = Toasts.toast
	RunService.RenderStepped:Connect(step)
	-- Igual ao setInterval de 250 ms do web (renderHud + renderUndo): o aviso aparece e some sozinho.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(Toasts.renderUndo)
			if not ok then
				warn("Falha no aviso de desfazer: " .. tostring(err))
			end
		end
	end)
end

return Toasts
