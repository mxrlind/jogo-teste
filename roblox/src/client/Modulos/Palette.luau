-- Paleta de construções (o #palette do web: renderPalette de src/ui/panels.js e os estilos .pal-head/.pb).
-- No computador é uma coluna com rolagem; no celular (Ctx.mobile) vira uma fileira com rolagem lateral.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)
local Assets = require(script.Parent.Assets)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Economy = require(Reino.Core.Economy)
local Game = require(Reino.Core.Game)
local Buildings = require(Reino.Data.Buildings)

local h = Kit.h
local rem = T.rem
local hex = T.hex
local AXY, AY = Enum.AutomaticSize.XY, Enum.AutomaticSize.Y
local WHITE = Color3.new(1, 1, 1)
local BUILDINGS, BUILDING_ORDER = Buildings.BUILDINGS, Buildings.BUILDING_ORDER

local Palette = {}

local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end

local function motion()
	return not (Ctx.config and Ctx.config.reduceMotion)
end

local function spriteOf(id)
	return "icon-" .. id
end

-- Assinatura de uma árvore do Kit (o paletteSig do web): muda quando algo visível muda.
local function sigOf(node, out)
	out = out or {}
	if type(node) ~= "table" then
		return out
	end
	if node.class then
		table.insert(out, node.class)
		for k, v in node.props do
			local t = type(v)
			if t == "string" or t == "number" or t == "boolean" then
				table.insert(out, k .. "=" .. tostring(v))
			elseif typeof(v) == "Color3" or typeof(v) == "UDim2" or typeof(v) == "Vector2" then
				table.insert(out, k .. "=" .. tostring(v))
			end
		end
		table.insert(out, "(")
		for _, c in Kit.flatten(node.children) do
			sigOf(c, out)
		end
		table.insert(out, ")")
	end
	return out
end

-- Sombra/brilho em volta (box-shadow) com a imagem ui/shadow tingida.
local function halo(color, spread, transparency, dy, z)
	local p = table.clone(Assets.image("ui/shadow"))
	p.BackgroundTransparency = 1
	p.ScaleType = Enum.ScaleType.Slice
	p.SliceCenter = Rect.new(32, 32, 64, 64)
	p.SliceScale = math.max(0.05, spread / 24)
	p.ImageColor3 = color
	p.ImageTransparency = transparency
	p.Size = UDim2.new(1, spread * 2, 1, spread * 2)
	p.Position = UDim2.fromOffset(-spread, -spread + (dy or 0))
	p.ZIndex = z or 0
	return h("ImageLabel", p)
end

-- Custo como no costHtml (vermelho no que falta).
local COST_ORDER = { "gold", "food", "wood", "stone", "gems", "scrolls", "crowns" }
local function costRow(cost, res, size, color)
	local items = {}
	for _, r in COST_ORDER do
		local v = cost and cost[r]
		if v then
			local short = res and (res[r] or 0) < v
			table.insert(items, h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
				Kit.list("x", { gap = math.max(1, math.floor(rem(size) * 0.12 + 0.5)), align = "center" }),
				U.resIco(r, math.floor(rem(size) * 1.25 + 0.5)),
				U.text(Util.fmt(v), { size = size, color = short and T.c.bad or color }),
			}))
		end
	end
	return items
end

-- ------------------------------------------------------------ estado de hover (transições manuais)
local root = nil
local scroller = nil
local lastSig = ""
local cards = {} -- id -> { inner, img, ring, base = {...} }
local glows = setmetatable({}, { __mode = "k" }) -- ImageLabel (brilho do .focus) -> true
local cardH = 44 + T.rem(0.35) * 2 -- altura dos cartões na fileira do celular (cresce se algum precisar)

local TI = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_BACK = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function tween(inst, info, props)
	if not inst or not inst.Parent then
		return
	end
	if motion() then
		TweenService:Create(inst, info, props):Play()
	else
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
end

local function hoverState(id, on)
	local c = cards[id]
	if not c then
		return
	end
	c.hovered = on
	local shift = (not Ctx.mobile) and (on or c.base.active) and not c.base.locked
	tween(c.inner, TI, { Position = UDim2.fromOffset(shift and 3 or 0, 0) })
	if c.scale then
		tween(c.scale, TI_BACK, { Scale = (on and not c.base.locked) and 1.08 or 1 })
	end
	if c.ring then
		if on then
			if c.base.locked then
				tween(c.ring, TI, { Color = WHITE, Transparency = 0.86 })
			elseif not c.base.active and not c.base.focus then
				tween(c.ring, TI, { Color = hex("#b9820e"), Transparency = 0.55 })
			end
		else
			tween(c.ring, TI, { Color = c.base.ringColor, Transparency = c.base.ringT })
		end
	end
	if c.bg and c.base.locked then
		tween(c.bg, TI, { BackgroundTransparency = on and 0.92 or 0.96 })
	end
end

-- ------------------------------------------------------------ peças
local function pbNode(it, s, mobile)
	local id, def = it.id, it.def
	local locked = not it.avail
	local next = locked and it.next
	local active, focus, poor = it.active, it.focus and not locked, not locked and not it.can
	local card = {}
	cards[id] = cards[id] or {}
	local reg = cards[id]
	local ringColor, ringT, ringW
	if locked then
		ringColor, ringT, ringW = next and T.c.gold or WHITE, next and 0.65 or 0.92, 1
	elseif active or focus then
		ringColor, ringT, ringW = T.c.gold, 0, 2
	else
		ringColor, ringT, ringW = hex("#3c2800"), 0.86, 1
	end
	reg.base = { active = active, focus = focus, locked = locked, ringColor = ringColor, ringT = ringT }

	local imgSize = locked and 26 or 44
	local nameColor = locked and (next and T.c.onInk or T.c.onInkMuted) or (poor and T.c.muted or T.c.text)
	local showKbd = not locked and it.n <= 9 and not Ctx.mid
	local name = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("x", { gap = rem(0.35), align = "center" }),
		U.text(def.name, {
			bold = not locked, size = locked and 0.82 or 0.92, color = nameColor, LineHeight = 1.05,
		}),
		showKbd and U.spacer() or nil,
		showKbd and h("Frame", {
			BackgroundColor3 = T.c.paper3, AutomaticSize = AXY, Size = UDim2.new(),
		}, {
			Kit.corner(5),
			Kit.stroke(T.c.line, 1, 0),
			Kit.pad(rem(0.15), rem(0.32), rem(0.15) + 1, rem(0.32)),
			U.b(tostring(it.n), { size = 0.66, color = T.c.muted, LineHeight = 1 }),
		}) or nil,
	})
	local pc
	if locked then
		pc = h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
			Kit.list("x", { gap = rem(0.25), align = "center" }),
			U.ico("lock", next and T.c.goldHi or T.c.onInkMuted, math.floor(rem(0.72) * 0.95 + 0.5)),
			U.text(tostring(def.unlock.buildings), { size = 0.72, color = next and T.c.goldHi or T.c.onInkMuted }),
		})
	else
		pc = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.list("x", { gap = rem(0.35), wrap = true, align = "center" }),
			costRow(it.cost, s.res, 0.78, T.c.muted),
		})
	end

	local imgColor = locked and hex("#5a5a5a") or (poor and hex("#b4b4b4") or WHITE)
	local imgT = locked and 0.3 or (poor and 0.25 or 0)
	local sprite = U.sprite(spriteOf(id), UDim2.fromScale(1, 1), {
		ImageColor3 = imgColor, ImageTransparency = imgT, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	})
	sprite.children = { h("UIScale", { Scale = 1, ref = function(inst) reg.scale = inst end }) }
	local imgBox = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(imgSize, imgSize) }, { sprite })

	local minW = mobile and (locked and rem(8.5) or rem(9.5)) or 0
	local colSize = mobile and UDim2.fromOffset(minW - rem(0.5) * 3 - imgSize, 0) or UDim2.new(1, -(imgSize + rem(0.5)), 0, 0)
	-- Layout: grid 44px | 1fr (bloqueado: 26px | 1fr | auto; no celular o custo desce para baixo do nome).
	local textCol
	if locked and not mobile then
		textCol = {
			h("Frame", { BackgroundTransparency = 1, Size = colSize, AutomaticSize = AY }, {
				Kit.list("x", { gap = rem(0.5), align = "center" }),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 0), AutomaticSize = AY }, {
					Kit.flex(1, 1),
					Kit.list("x", {}),
					U.text(def.name, { size = 0.82, color = nameColor, LineHeight = 1.05 }),
				}),
				pc,
			}),
		}
	else
		textCol = {
			h("Frame", { BackgroundTransparency = 1, Size = colSize, AutomaticSize = AY }, {
				Kit.list("y", { gap = rem(0.08) }),
				name,
				pc,
			}),
		}
	end

	local padV = locked and rem(0.25) or rem(0.35)
	local bgNode
	if locked then
		bgNode = h("Frame", {
			Name = "Fundo", BackgroundColor3 = WHITE, BackgroundTransparency = 0.96, Size = UDim2.fromScale(1, 1),
			ref = function(inst) reg.bg = inst end,
		}, {
			Kit.corner(T.r),
			h("UIStroke", { Color = ringColor, Thickness = 1, Transparency = ringT, ref = function(inst) reg.ring = inst end }),
		})
	else
		local top, bot = active and hex("#fff8df") or T.c.paper2, active and hex("#fdeec2") or T.c.paper
		local estH = 44 + padV * 2
		local edge = math.clamp(1 - 3 / estH, 0.5, 0.99)
		local dark = bot:Lerp(hex("#3c2800"), 0.1)
		bgNode = h("Frame", {
			Name = "Fundo", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1),
		}, {
			Kit.corner(T.r),
			-- degradê do pergaminho + inset 0 -3px 0 rgba(60,40,0,.1) na base
			h("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(edge, bot),
					ColorSequenceKeypoint.new(math.min(0.999, edge + 0.001), dark), ColorSequenceKeypoint.new(1, dark),
				}),
			}),
			h("UIStroke", { Color = ringColor, Thickness = ringW, Transparency = ringT, ref = function(inst) reg.ring = inst end }),
			-- borda clara de 1px por dentro (border: 1px solid rgba(255,255,255,.6))
			h("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, {
				Kit.corner(T.r - 1), Kit.stroke(WHITE, 1, 0.4),
			}),
		})
	end

	local shift = (not mobile) and active
	local content = h("Frame", {
		Name = "Conteudo", BackgroundTransparency = 1,
		Size = mobile and UDim2.new() or UDim2.fromScale(1, 0), AutomaticSize = mobile and AXY or AY, ZIndex = 2,
		AnchorPoint = mobile and Vector2.new(0, 0.5) or nil, Position = mobile and UDim2.fromScale(0, 0.5) or nil,
		onSize = mobile and function(inst)
			local hh = inst.AbsoluteSize.Y
			if hh > cardH + 0.5 then
				cardH = hh
				Ctx.relayout()
				Ctx.invalidate("palette", true)
			end
		end or nil,
	}, {
		Kit.pad(padV, rem(0.5)),
		Kit.list("x", { gap = rem(0.5), align = "center" }),
		mobile and Kit.sizeLimit(Vector2.new(minW, 0)) or nil,
		imgBox,
		textCol,
	})
	-- Decoração em volta (sombras, brilho, fundo): num Frame de tamanho relativo, fora do AutomaticSize.
	local deco = h("Frame", { Name = "Deco", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
		-- 0 2px 4px rgba(0,0,0,.25); ativo: + 0 0 16px dourado; foco: brilho que pulsa
		not locked and halo(T.c.black, 4, 0.72, 2, 0) or nil,
		active and halo(T.c.gold, 16, 0.55, 0, 0) or nil,
		(focus and motion()) and (function()
			local nd = halo(T.c.gold, 18, 1, 0, 0)
			nd.props.ref = function(inst) glows[inst] = true end
			return nd
		end)() or nil,
		bgNode,
		-- .pb.focus::after: bolinha dourada na borda direita
		focus and h("Frame", {
			Name = "Ponto", BackgroundColor3 = T.c.goldHi, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(10, 10), ZIndex = 4,
		}, {
			Kit.corner(99), Kit.stroke(T.c.gold, 3, 0.65),
		}) or nil,
	})
	return h("TextButton", {
		key = id,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = mobile and UDim2.fromOffset(minW, cardH) or UDim2.fromScale(1, 0),
		AutomaticSize = mobile and Enum.AutomaticSize.X or AY,
		tip = (not locked) and def.desc or nil,
		onEnter = function()
			hoverState(id, true)
		end,
		onLeave = function()
			hoverState(id, false)
		end,
		onClick = function()
			if locked then
				Ctx.run("lockedBuilding", id)
			else
				Ctx.run("build", id)
			end
		end,
	}, {
		h("Frame", {
			Name = "Cartao", BackgroundTransparency = 1,
			Size = mobile and UDim2.new(0, minW, 1, 0) or UDim2.fromScale(1, 0),
			AutomaticSize = mobile and Enum.AutomaticSize.X or AY,
			ref = function(inst)
				reg.inner = inst
				inst.Position = UDim2.fromOffset(shift and 3 or 0, 0)
			end,
		}, { deco, content }),
	})
end

local function head(left, right, first)
	return h("Frame", { key = "head-" .. left, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(first and 0 or rem(0.55) - rem(0.35), rem(0.2), rem(0.1), rem(0.2)),
		Kit.list("x", { justify = "between", align = "center" }),
		U.b(upper(left), { size = 0.7, color = T.c.onInkMuted }),
		U.b(upper(right), { size = 0.7, color = T.c.onInkMuted }),
	})
end

local function build()
	local g = Ctx.game
	local s = g.state
	local mods = g.econ.mods
	local mode = (Ctx.renderer and Ctx.renderer.mode) or Ctx.ui.mode or { type = "select" }
	local focus = nil
	if not s.tutorial.done then
		local step = Game.TUTORIAL[s.tutorial.step + 1]
		focus = step and step.focus
	end
	local mobile = Ctx.mobile
	local n = 0
	local items = {}
	for _, id in BUILDING_ORDER do
		local def = BUILDINGS[id]
		local avail = g:isAvailable(id)
		if avail then
			n += 1
		end
		local cost = Economy.buildCost(s, id, mods)
		table.insert(items, {
			id = id, def = def, avail = avail, n = n, cost = cost, can = Economy.canAfford(s.res, cost),
			active = mode.type == "build" and mode.id == id, focus = focus ~= nil and focus.build == id,
		})
	end
	local open, locked = {}, {}
	for _, it in items do
		table.insert(it.avail and open or locked, it)
	end
	table.sort(locked, function(a, b)
		if a.def.unlock.buildings ~= b.def.unlock.buildings then
			return a.def.unlock.buildings < b.def.unlock.buildings
		end
		return table.find(BUILDING_ORDER, a.id) < table.find(BUILDING_ORDER, b.id) -- sort estável como no JS
	end)
	local have = g:unlockProgress()
	local nextAt = locked[1] and locked[1].def.unlock.buildings
	local kids = {}
	if not mobile then
		table.insert(kids, head("Construir", #open .. "/" .. #items, true))
	end
	for _, it in open do
		table.insert(kids, pbNode(it, s, mobile))
	end
	if #locked > 0 then
		if not mobile then
			table.insert(kids, head("A desbloquear", have .. "/" .. nextAt .. " obras", false))
		end
		for _, it in locked do
			it.next = it.def.unlock.buildings == nextAt
			table.insert(kids, pbNode(it, s, mobile))
		end
	end

	if mobile then
		return h("ScrollingFrame", {
			Name = "Paleta", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4, ScrollBarImageColor3 = hex("#645a46"), ScrollBarImageTransparency = 0.65,
			ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
			ref = function(inst) scroller = inst end,
		}, {
			Kit.pad(2, 2, rem(0.4), 2),
			Kit.list("x", { gap = rem(0.35), align = "start" }),
			kids,
		})
	end
	return h("ScrollingFrame", {
		Name = "Paleta", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = hex("#645a46"), ScrollBarImageTransparency = 0.65,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ref = function(inst) scroller = inst end,
	}, {
		Kit.pad(2, 4, 4, 2),
		Kit.list("y", { gap = rem(0.35) }),
		kids,
	})
end

-- Foco do tutorial: glow 1s alternate (0 0 0 2px dourado -> + 0 0 18px dourado .85).
local function stepGlow()
	if next(glows) == nil then
		return
	end
	local p = (math.sin(os.clock() * math.pi - math.pi / 2) + 1) / 2
	for inst in glows do
		if inst.Parent then
			inst.ImageTransparency = 1 - 0.7 * p
		else
			glows[inst] = nil
		end
	end
end

function Palette.init(frame)
	root = frame
	RunService.Heartbeat:Connect(stepGlow)
end

-- Altura (px) da fileira com rolagem lateral do celular.
function Palette.mobileHeight()
	-- cartão (padding .35rem×2 + imagem 44px, ou mais se o custo quebrar linha) + padding da fileira (2px / .4rem)
	return math.max(cardH, 44 + rem(0.35) * 2) + 2 + rem(0.4)
end

local lastMobile = nil
function Palette.render(force)
	if not root then
		return
	end
	if not Ctx.game then
		Kit.render(root, nil)
		lastSig = ""
		return
	end
	if lastMobile ~= Ctx.mobile then
		-- troca de layout (coluna <-> fileira): monta de novo
		Kit.render(root, nil)
		cards = {}
		lastSig = ""
		lastMobile = Ctx.mobile
		force = true
	end
	local node = build()
	local sig = table.concat(sigOf(node), "|") .. tostring(Ctx.mid)
	if not force and sig == lastSig then
		return
	end
	lastSig = sig
	Kit.render(root, node)
	-- estados que o Kit não controla (deslocamento do ativo, hover)
	for id, c in cards do
		if c.inner and c.inner.Parent and c.base then
			local shift = (not Ctx.mobile) and (c.hovered or c.base.active) and not c.base.locked
			local want = UDim2.fromOffset(shift and 3 or 0, 0)
			if c.inner.Position ~= want then
				tween(c.inner, TI, { Position = want })
			end
			if c.hovered and c.ring and not c.base.locked and not c.base.active and not c.base.focus then
				c.ring.Color, c.ring.Transparency = hex("#b9820e"), 0.55
			end
		else
			cards[id] = nil
		end
	end
end

return Palette
