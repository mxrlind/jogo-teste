-- Palco (o #stage do web): banner do tutorial, barra de visita, dica de modo, mapa (MapView) com a rosa dos
-- ventos e os botões de nível, e o painel do tile. Porte de renderTutorial/renderModeHint/renderTileInfo
-- (src/ui/panels.js) e de placeCompass/renderLayers/startVisit (src/ui/app.js).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)
local Assets = require(script.Parent.Assets)
local TileInfo = require(script.Parent.TileInfo)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Map = require(Reino.Core.Map)
local Game = require(Reino.Core.Game)
local Buildings = require(Reino.Data.Buildings)
local UnderData = require(Reino.Data.Underground)

local h = Kit.h
local rem = T.rem
local hex = T.hex
local AXY, AY = Enum.AutomaticSize.XY, Enum.AutomaticSize.Y
local WHITE = Color3.new(1, 1, 1)
local BUILDINGS = Buildings.BUILDINGS
local DIR_NAMES = Game.DIR_NAMES

local Stage = {}

local function motion()
	return not (Ctx.config and Ctx.config.reduceMotion)
end

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

-- var(--ease) e var(--ease-back) aproximados
local TI_RISE = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_DROP = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TI_HOVER = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Assinatura de uma árvore do Kit (o tileSig/setHtml do web).
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
			elseif typeof(v) == "Color3" or typeof(v) == "UDim2" or typeof(v) == "Vector2" or typeof(v) == "UDim" then
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
local function sig(node)
	return table.concat(sigOf(node), "|")
end

-- Sombra/brilho (box-shadow) com a imagem ui/shadow tingida.
local function halo(color, spread, transparency, dy)
	local p = table.clone(Assets.image("ui/shadow"))
	p.BackgroundTransparency = 1
	p.ScaleType = Enum.ScaleType.Slice
	p.SliceCenter = Rect.new(32, 32, 64, 64)
	p.SliceScale = math.max(0.05, spread / 24)
	p.ImageColor3 = color
	p.ImageTransparency = transparency
	p.Size = UDim2.new(1, spread * 2, 1, spread * 2)
	p.Position = UDim2.fromOffset(-spread, -spread + (dy or 0))
	return h("ImageLabel", p)
end

local function hudMod()
	local ok, Hud = pcall(require, script.Parent.Hud)
	return ok and Hud or nil
end

local function renderer()
	return Ctx.renderer
end
local function curMode()
	local r = renderer()
	return (r and r.mode) or Ctx.ui.mode or { type = "select" }
end
local function curSelected()
	local r = renderer()
	if r then
		return r.selected
	end
	return Ctx.ui.selected
end
local function curLayer()
	local r = renderer()
	return (r and r.layer) or Ctx.ui.layer or 0
end

-- ------------------------------------------------------------ quadros
local stage = nil
local tutHost, mapWrap, mapHolder, compassHost, layersHost, overlayHost, tileHost, fixedHost
local tutInst, compassInst, layersInst, tileInst, tileContent
local tutVisible, tileVisible = false, false
local tileH = 0
local lastExtra = 0

-- Faixa de cartão das dicas (#tutorial, #modeHint, #visitBar).
local function strip(o, children)
	return h("Frame", {
		Name = o.name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
		AnchorPoint = o.anchor, Position = o.pos, Active = o.active,
	}, {
		h("Frame", { Name = "Deco", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
			halo(T.c.black, o.shadow or 12, o.shadowT or 0.7, o.shadowDy or 4),
			h("Frame", { BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
				Kit.corner(T.r),
				Kit.grad(o.colors or { T.c.paper2, T.c.paper }, 90),
				Kit.stroke(o.ring or hex("#3c2800"), 1, o.ringT or 0.84),
			}),
		}),
		h("Frame", { Name = "Conteudo", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ZIndex = 3 }, {
			Kit.pad(rem(0.5), rem(0.75)),
			Kit.list("x", { gap = rem(0.55), wrap = true, align = "center" }),
			children,
		}),
		h("UIScale", { Scale = 1 }),
	})
end

-- ------------------------------------------------------------ layout do palco
local function layoutStage()
	if not stage then
		return
	end
	local w = stage.AbsoluteSize.X
	local stH = stage.AbsoluteSize.Y
	local tutH = (tutVisible and tutInst and tutInst.Parent) and (tutInst.AbsoluteSize.Y + rem(0.6)) or 0
	if Ctx.mobile then
		mapWrap.Position = UDim2.fromOffset(0, tutH)
		mapWrap.Size = UDim2.new(1, 0, 0, w)
		tileHost.AnchorPoint = Vector2.zero
		tileHost.Position = UDim2.fromOffset(0, tutH + w + rem(0.6))
		tileHost.Size = UDim2.new(1, 0, 0, tileH)
	else
		mapWrap.Position = UDim2.fromOffset(0, tutH)
		mapWrap.Size = UDim2.new(1, 0, 1, -tutH)
		tileHost.AnchorPoint = Vector2.new(1, 1)
		tileHost.Position = UDim2.new(1, -rem(0.5), 1, -rem(0.5))
		local tw = math.min(rem(23), w - rem(1))
		tileHost.Size = UDim2.fromOffset(tw, tileH)
	end
	if tileInst and tileInst.Parent then
		local maxH = Ctx.mobile and math.huge or math.floor(stH * 0.72)
		tileInst.Size = UDim2.new(1, 0, 0, math.min(tileH, maxH))
		tileHost.Size = UDim2.new(tileHost.Size.X, UDim.new(0, math.min(tileH, maxH)))
	end
	local extra = tutH + ((tileVisible and tileH > 0) and (rem(0.6) + tileH) or 0)
	if extra ~= lastExtra then
		lastExtra = extra
		if Ctx.mobile then
			Ctx.relayout()
		end
	end
end

-- Px do palco além do mapa quadrado no celular (tutorial em cima e painel do tile embaixo).
function Stage.mobileExtra()
	return lastExtra
end

-- ------------------------------------------------------------ rosa dos ventos e níveis (placeCompass)
local function compassSize()
	return Ctx.mobile and 46 or 60
end

local function placeCompass()
	local r = renderer()
	local map = r and r.frame
	if not map or not mapWrap then
		return
	end
	local wrapPos, wrapSize = mapWrap.AbsolutePosition, mapWrap.AbsoluteSize
	local left = map.AbsolutePosition.X - wrapPos.X
	local top = map.AbsolutePosition.Y - wrapPos.Y
	local right = left + map.AbsoluteSize.X
	if compassInst and compassInst.Parent then
		local cw = compassSize()
		local outside = wrapSize.X - right >= cw + 14
		compassInst.Position = UDim2.fromOffset(outside and right + 10 or right - cw - 8, top + (outside and 0 or 8))
		local btn = compassInst:FindFirstChild("Rosa")
		if btn then
			-- #compass:not(.outside) { opacity: .94 }
			btn.ImageTransparency = outside and 0 or 0.06
		end
	end
	if layersInst and layersInst.Parent then
		local lw = layersInst.AbsoluteSize.X
		if lw < 1 then
			lw = 46
		end
		local lOut = left >= lw + 14
		layersInst.Position = UDim2.fromOffset(lOut and left - lw - 10 or left + 8, top + (lOut and 0 or 8))
	end
end
Stage.placeCompass = placeCompass

local compassHover = false
local warnGlows = setmetatable({}, { __mode = "k" })

local function renderCompass()
	local g = Ctx.game
	if not g or not compassHost then
		return
	end
	local s = g.state
	local r = renderer()
	local hidden = r and r.view ~= nil -- visitando outro reino: a horda anunciada é a do seu
	if hidden then
		Kit.render(compassHost, nil)
		compassInst = nil
		return
	end
	local size = compassSize()
	local dir = s.raid.dir
	local warned = s.raid.warned and motion()
	local label = "Rosa dos ventos. Próxima horda pelo " .. DIR_NAMES[dir] .. "."
	local node = h("Frame", { Name = "Bussola", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = 3 }, {
		h("UIScale", { Scale = 1 }),
		-- drop-shadow(0 3px 4px rgba(0,0,0,.4))
		h("ImageLabel", Assets.with("ui/disc", {
			Name = "Sombra", BackgroundTransparency = 1, ImageColor3 = T.c.black, ImageTransparency = 0.65,
			Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromOffset(-2, 1), ScaleType = Enum.ScaleType.Stretch,
		})),
		-- .warned: brilho vermelho que pulsa (drop-shadow 0 0 7px rgba(224,82,61,.95) em 50%)
		warned and h("ImageLabel", Assets.with("ui/glow", {
			Name = "Alerta", BackgroundTransparency = 1, ImageColor3 = hex("#e0523d"), ImageTransparency = 1,
			Size = UDim2.new(1, 18, 1, 18), Position = UDim2.fromOffset(-9, -9), ScaleType = Enum.ScaleType.Stretch,
			ref = function(inst)
				warnGlows[inst] = true
			end,
		})) or nil,
		h("ImageButton", Assets.with("ui/compass-" .. dir, {
			Name = "Rosa", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Fit, ZIndex = 2, tip = label,
			onClick = function()
				Ctx.run("info", "raid")
			end,
			onEnter = function(inst)
				compassHover = true
				local sc = inst.Parent and inst.Parent:FindFirstChildOfClass("UIScale")
				tween(sc, TI_HOVER, { Scale = 1.06 })
			end,
			onLeave = function(inst)
				compassHover = false
				local sc = inst.Parent and inst.Parent:FindFirstChildOfClass("UIScale")
				tween(sc, TI_HOVER, { Scale = 1 })
			end,
		})),
	})
	local before = compassInst
	compassInst = Kit.render(compassHost, node)
	if before ~= compassInst then
		placeCompass()
	end
end

local layersSig = ""
local function renderLayers()
	local g = Ctx.game
	if not layersHost then
		return
	end
	-- O Controller guarda o nível alcançado em Ctx.ui.layersReached (e volta para a superfície se precisar).
	local reached = Ctx.ui.layersReached
	if reached == nil then
		reached = g and g.state.under and g.state.under.reached or 0
	end
	if not g or reached < 1 then
		if layersInst then
			Kit.render(layersHost, nil)
			layersInst = nil
			layersSig = ""
		end
		return
	end
	local cur = curLayer()
	local function btn(d, label, icon, title)
		local on = d == cur
		return h("TextButton", {
			key = "l" .. d, Text = icon and "" or label, FontFace = T.bold, TextSize = 14,
			TextColor3 = on and T.c.ink or T.c.paper, AutoButtonColor = false,
			BackgroundColor3 = on and T.c.gold or T.c.ink3, Size = UDim2.fromOffset(38, 34), tip = title,
			hover = (not on) and { BackgroundColor3 = hex("#4a4657") } or nil,
			onClick = function()
				Ctx.run("layer", d)
			end,
		}, {
			Kit.corner(9),
			icon and U.ico(icon, on and T.c.ink or T.c.paper, 18, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }) or nil,
		})
	end
	local btns = { btn(0, nil, "house", "Superfície") }
	for i = 1, reached do
		table.insert(btns, btn(i, "-" .. i, nil, "Subsolo " .. i .. ": " .. UnderData.LEVEL_NAMES[i]))
	end
	local node = h("Frame", { Name = "Niveis", BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new(), ZIndex = 3 }, {
		h("Frame", { Name = "Deco", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
			halo(T.c.black, 8, 0.65, 3),
			h("Frame", { BackgroundColor3 = hex("#1f1d27"), BackgroundTransparency = 0.18, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
				Kit.corner(12),
			}),
		}),
		h("Frame", { Name = "Botoes", BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new(), ZIndex = 3 }, {
			Kit.pad(4),
			Kit.list("y", { gap = 4 }),
			btns,
		}),
	})
	local sg = sig(node)
	if sg == layersSig and layersInst then
		return
	end
	layersSig = sg
	layersInst = Kit.render(layersHost, node)
	task.defer(placeCompass)
end

-- ------------------------------------------------------------ tutorial (renderTutorial)
local tutStep = nil
local tutSig = ""
local function renderTutorial()
	local g = Ctx.game
	if not tutHost then
		return
	end
	local s = g and g.state
	if not s or s.tutorial.done or Ctx.ui.visiting then
		if tutVisible then
			tutVisible = false
			Kit.render(tutHost, nil)
			tutInst = nil
			tutSig = ""
			layoutStage()
		end
		return
	end
	local step = Game.TUTORIAL[s.tutorial.step + 1]
	if not step then
		return
	end
	local dots = {}
	for i = 1, #Game.TUTORIAL do
		table.insert(dots, h("Frame", {
			key = "d" .. i, BackgroundColor3 = T.c.goldText, BackgroundTransparency = (i - 1) <= s.tutorial.step and 0 or 0.75,
			Size = UDim2.fromOffset(6, 6),
		}, { Kit.corner(99) }))
	end
	local node = strip({
		name = "Tutorial", colors = { hex("#fff6d6"), hex("#fde9b0") }, ring = hex("#b9820e"), ringT = 0.6,
	}, {
		U.ico("mission", T.c.goldText, rem(1.6)),
		h("Frame", { Name = "tt", BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(12), 0), AutomaticSize = AY }, {
			Kit.flex(1, 0), -- flex: 1; min-width: 12rem
			Kit.list("y", { gap = 0 }),
			h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
				Kit.list("x", { gap = rem(0.35), align = "center" }),
				U.b("PRIMEIROS PASSOS " .. (s.tutorial.step + 1) .. "/" .. #Game.TUTORIAL, { size = 0.7, color = T.c.goldText }),
				h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
					Kit.list("x", { gap = 3, align = "center" }),
					dots,
				}),
			}),
			U.text(U.esc(step.text), { wrap = true, LineHeight = 1.08 }),
		}),
	})
	local sg = sig(node)
	if sg == tutSig and tutInst then
		return
	end
	tutSig = sg
	local before = tutStep
	tutStep = s.tutorial.step
	tutInst = Kit.render(tutHost, node)
	tutVisible = true
	if before ~= nil and before ~= tutStep and motion() then
		-- .advance: pop .45s var(--ease-back) (de scale .92 e 8px abaixo)
		local sc = tutInst:FindFirstChildOfClass("UIScale")
		if sc then
			sc.Scale = 0.92
			tween(sc, TI_POP, { Scale = 1 })
		end
		tutInst.Position = UDim2.fromOffset(0, 8)
		tween(tutInst, TI_POP, { Position = UDim2.new() })
	end
	task.defer(layoutStage)
end

-- ------------------------------------------------------------ visita (startVisit/endVisit)
local visitShown = false
local visitInst = nil
local function renderVisit()
	if not overlayHost then
		return
	end
	local k = Ctx.ui.visiting
	local holder = overlayHost:FindFirstChild("VisitaHost")
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "VisitaHost"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.ZIndex = 5
		holder.Parent = overlayHost
	end
	if not k then
		if visitShown then
			Kit.render(holder, nil)
			visitShown = false
		end
		return
	end
	local Hud = hudMod()
	local banner = Hud and Hud.banner(Hud.bannerColor(k.banner), Hud.emblemIcon(k.emblem), true) or nil
	local node = strip({ name = "Visita", anchor = Vector2.zero, pos = UDim2.new(), shadow = 22, shadowT = 0.45, shadowDy = 8, active = true }, {
		banner,
		-- o texto ocupa o meio e quebra linha se faltar espaço; o botão fica na ponta (margin-left: auto)
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(8), 0), AutomaticSize = AY }, {
			Kit.flex(1, 1),
			U.text("Visitando <b>" .. U.esc(k.name) .. "</b> · " .. U.esc(k.title or "") .. " · Poder " .. Util.fmt(k.power or 0), { wrap = true }),
		}),
		U.btn({ icon = "house", text = "Voltar ao meu reino", small = true, onClick = Ctx.does("endVisit") }),
	})
	visitInst = Kit.render(holder, node)
	if not visitShown and motion() then
		visitInst.Position = UDim2.fromOffset(0, -6)
		tween(visitInst, TI_DROP, { Position = UDim2.new() })
	end
	visitShown = true
end

-- ------------------------------------------------------------ dica de modo (renderModeHint)
local hintShown = false
local hintInst = nil
local hintHolder = nil
local function touchUi()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function renderModeHint()
	if not overlayHost then
		return
	end
	local mobile = Ctx.mobile
	local parent = mobile and fixedHost or overlayHost
	if hintHolder and hintHolder.Parent ~= parent then
		Kit.render(hintHolder, nil)
		hintHolder:Destroy()
		hintHolder = nil
		hintShown = false
	end
	if not hintHolder then
		hintHolder = Instance.new("Frame")
		hintHolder.Name = "DicaHost"
		hintHolder.BackgroundTransparency = 1
		hintHolder.ZIndex = mobile and 40 or 5
		hintHolder.Parent = parent
	end
	if mobile then
		-- position: fixed; left/right 8px; bottom 8px (flip: top 8px)
		hintHolder.Position = UDim2.fromOffset(8, 8)
		hintHolder.Size = UDim2.new(1, -16, 1, -16)
	else
		hintHolder.Position = UDim2.new()
		hintHolder.Size = UDim2.fromScale(1, 1)
	end
	local g = Ctx.game
	local m = curMode()
	local kids
	if g and m.type == "build" and BUILDINGS[m.id] then
		local def = BUILDINGS[m.id]
		local d = Ctx.ui.hoverDelta
		local line
		if d then
			line = '<font size="' .. rem(0.8) .. '" color="#' .. T.c.good:ToHex() .. '"><b>Neste lugar: ' .. U.esc(TileInfo.deltaText(d)) .. "</b></font>"
		else
			line = '<font color="#' .. T.c.muted:ToHex() .. '">' .. (touchUi() and "Toque num tile para ver o ganho; toque de novo para construir." or "Passe o mouse num tile para ver o ganho; clique para construir.") .. "</font>"
		end
		kids = {
			U.sprite("icon-" .. m.id, 32),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(12), 0), AutomaticSize = AY }, {
				Kit.flex(1, 0), -- flex: 1; min-width: 12rem
				U.text("<b>" .. def.name .. "</b>: " .. U.esc(def.desc) .. "<br />" .. line, { wrap = true, LineHeight = 1.08 }),
			}),
			U.btn({ text = "Cancelar", small = true, onClick = Ctx.does("cancelMode") }),
		}
	elseif g and m.type == "move" then
		kids = {
			U.ico("move", T.c.text, rem(1.25)),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(12), 0), AutomaticSize = AY }, {
				Kit.flex(1, 0), -- flex: 1; min-width: 12rem
				U.text("Escolha o novo lugar (mover é grátis).", { wrap = true }),
			}),
			U.btn({ text = "Cancelar", small = true, onClick = Ctx.does("cancelMode") }),
		}
	end
	if not kids then
		if hintShown then
			Kit.render(hintHolder, nil)
			hintShown = false
			hintInst = nil
		end
		return
	end
	-- dodgeModeHint: mede na posição normal e pula para a borda oposta se cobrir o tile apontado
	local flip = false
	local r = renderer()
	local t = (r and r.hover) or Ctx.ui.hover
	local function place(inst, f)
		local bottomSide = mobile ~= f -- celular: embaixo por padrão
		inst.AnchorPoint = Vector2.new(0, bottomSide and 1 or 0)
		inst.Position = UDim2.fromScale(0, bottomSide and 1 or 0)
	end
	local node = strip({ name = "DicaModo", shadow = 22, shadowT = 0.45, shadowDy = 8 }, kids)
	local fresh = not hintShown
	hintInst = Kit.render(hintHolder, node)
	hintShown = true
	place(hintInst, false)
	if t and r and r.frame then
		local c = r.frame
		local size = c.AbsoluteSize.Y / Map.GRID_H
		local top = c.AbsolutePosition.Y + t.y * size
		local bottom = top + size
		local hp, hs = hintInst.AbsolutePosition, hintInst.AbsoluteSize
		if bottom > hp.Y and top < hp.Y + hs.Y then
			flip = true
		end
	end
	place(hintInst, flip)
	if fresh and motion() then
		local base = hintInst.Position
		hintInst.Position = base + UDim2.fromOffset(0, -6)
		tween(hintInst, TI_DROP, { Position = base })
	end
end

-- ------------------------------------------------------------ painel do tile (renderTileInfo)
local tileSig = ""
local tileKey = nil
local function hideTile()
	if tileVisible then
		Kit.render(tileHost, nil)
		tileInst, tileContent = nil, nil
		tileVisible = false
		tileH = 0
		layoutStage()
	end
	tileSig = ""
end

local function renderTileInfo(force)
	if not tileHost then
		return
	end
	local sel = curSelected()
	local g = Ctx.game
	if not g or not sel or Ctx.ui.visiting then
		hideTile()
		return
	end
	local layer = curLayer()
	local ok, blocks = pcall(TileInfo.blocks, g, sel, layer)
	if not ok then
		warn("Painel do tile: " .. tostring(blocks))
		return
	end
	local mobile = Ctx.mobile
	local content = h("Frame", {
		Name = "Conteudo", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
		onSize = function(inst)
			local hh = inst.AbsoluteSize.Y
			if hh ~= tileH then
				tileH = hh
				layoutStage()
			end
		end,
	}, {
		Kit.pad(rem(0.9), rem(1)),
		Kit.list("y", { gap = 0 }),
		TileInfo.stack(blocks),
	})
	-- .x: botão de fechar no canto
	local close = U.btn({ icon = "close", small = true, iconOnly = true, onClick = Ctx.does("closeTile") })
	close.props.AnchorPoint = Vector2.new(1, 0)
	close.props.Position = UDim2.new(1, -rem(0.45), 0, rem(0.45))
	close.props.ZIndex = 3
	local node = U.panel({ Name = "PainelTile", ClipsDescendants = false }, {
		h("ScrollingFrame", {
			Name = "Rolagem", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = mobile and 0 or 6, ScrollBarImageColor3 = hex("#645a46"), ScrollBarImageTransparency = 0.65,
			ScrollingEnabled = not mobile,
		}, { content, close }),
	}, { shadow = "lg", pad = false, layout = false })
	local sg = sig(node) .. tostring(mobile)
	if not force and sg == tileSig then
		return
	end
	tileSig = sg
	-- Anima só quando abre ou troca de tile (não a cada atualização de números).
	local key = layer .. ":" .. sel.x .. "," .. sel.y
	local fresh = not tileVisible or tileKey ~= key
	tileKey = key
	tileInst = Kit.render(tileHost, node)
	tileVisible = true
	if tileH == 0 then
		local c = tileInst:FindFirstChild("Conteudo", true)
		if c then
			tileH = c.AbsoluteSize.Y
		end
	end
	layoutStage()
	if fresh and motion() then
		-- .enter: rise .25s (14px abaixo, scale .98)
		local sc = tileHost:FindFirstChildOfClass("UIScale")
		if sc then
			sc.Scale = 0.98
			tween(sc, TI_RISE, { Scale = 1 })
		end
		tileInst.Position = UDim2.fromOffset(0, 14)
		tween(tileInst, TI_RISE, { Position = UDim2.new() })
	end
end

-- ------------------------------------------------------------ animações contínuas
local function stepFx()
	if next(warnGlows) == nil then
		return
	end
	-- compassWarn 1.1s ease-in-out infinite: pico em 50%
	local t = (os.clock() % 1.1) / 1.1
	local p = (1 - math.cos(t * 2 * math.pi)) / 2
	for inst in warnGlows do
		if inst.Parent then
			inst.ImageTransparency = 1 - 0.95 * p
		else
			warnGlows[inst] = nil
		end
	end
end

-- ------------------------------------------------------------ API
local function makeFrame(name, parent, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

function Stage.init(frame)
	stage = frame
	tutHost = makeFrame("Tutorial", frame, 2)
	tutHost.Size = UDim2.fromScale(1, 0)
	tutHost.AutomaticSize = AY
	tutHost:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutStage()
	end)
	mapWrap = makeFrame("MapWrap", frame, 1)
	mapHolder = makeFrame("Mapa", mapWrap, 1)
	compassHost = makeFrame("BussolaHost", mapWrap, 3)
	layersHost = makeFrame("NiveisHost", mapWrap, 3)
	tileHost = makeFrame("TileHost", frame, 4)
	tileHost.Size = UDim2.new()
	local sc = Instance.new("UIScale")
	sc.Parent = tileHost
	overlayHost = makeFrame("Sobre", frame, 5)
	-- Dica de modo do celular: fixa na tela (fora da rolagem da página).
	local scroll = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
	local fixedParent = scroll and scroll.Parent or frame
	fixedHost = makeFrame("DicaFixa", fixedParent, 40)

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutStage)
	mapWrap:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCompass)
	mapWrap:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeCompass)

	local ok, MapView = pcall(require, script.Parent.MapView)
	if ok and MapView then
		local ok2, r = pcall(MapView.new, mapHolder, {
			onTileClick = function(x, y)
				Ctx.onTileClick(x, y)
			end,
			onHover = function(t)
				Ctx.onHover(t)
			end,
			onResize = placeCompass,
			getConfig = function()
				return Ctx.config
			end,
		})
		if ok2 then
			Ctx.renderer = r
		else
			warn("MapView.new falhou: " .. tostring(r))
		end
	else
		warn("MapView indisponível: " .. tostring(MapView))
	end
	mapHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local r = Ctx.renderer
		if r and r.resize then
			r:resize()
		end
		placeCompass()
	end)
	RunService.Heartbeat:Connect(stepFx)
	layoutStage()
end

-- Chamado pelo Hud.render (o renderHud do web também cuida da rosa dos ventos e do tutorial).
function Stage.hudTick()
	if not stage then
		return
	end
	renderCompass()
	renderTutorial()
	renderVisit()
end

function Stage.render(part, force)
	if not stage then
		return
	end
	if part == "tileInfo" then
		renderTileInfo(force)
	elseif part == "modeHint" then
		renderModeHint()
	elseif part == "layers" then
		renderLayers()
	elseif part == "tutorial" then
		renderTutorial()
	elseif part == "visit" then
		renderVisit()
		renderTutorial()
		renderCompass()
		renderTileInfo(true)
	elseif part == "undo" then
		-- nada: o aviso de desfazer vive nos Toasts, que têm o próprio laço
	elseif part == "stage" or part == "all" then
		renderVisit()
		renderTutorial()
		renderCompass()
		renderLayers()
		renderModeHint()
		renderTileInfo(true)
		layoutStage()
		placeCompass()
	end
end

return Stage
