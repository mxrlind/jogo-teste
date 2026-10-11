-- HUD do topo (o #hud do web: renderHud/hudInfo de src/ui/panels.js e renderMusicBtn de app.js).
-- Botão do menu, estandarte e nome do reino, botão de música, fichas de recurso (com taxa e barra de capacidade)
-- e as pílulas de situação (horda, conserto, evento, bênção, ascensão).
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
local Config = require(Reino.Core.Config)
local Buildings = require(Reino.Data.Buildings)
local Cosmetics = require(Reino.Data.Cosmetics)
local Events = require(Reino.Data.Events)

local h = Kit.h
local rem = T.rem
local fmt, fmtTime = Util.fmt, Util.fmtTime
local AXY, AY = Enum.AutomaticSize.XY, Enum.AutomaticSize.Y
local WHITE = Color3.new(1, 1, 1)
local hex = T.hex

local Hud = {}

local RES_LIST = { "gold", "food", "wood", "stone" }
local DIR_NAMES = Game.DIR_NAMES

-- O porte de Data/Cosmetics e Data/Events não trouxe os ícones; aqui ficam os mesmos do web.
local EMBLEM_ICONS = {
	coroa = "crowns", escudo = "emblem-shield", leao = "emblem-lion", arvore = "emblem-tree", lobo = "emblem-wolf",
	aguia = "emblem-eagle", rosa = "emblem-rose", caveira = "emblem-skull", ["emblema-fundacao"] = "season-foundation",
	["emblema-guerra"] = "season-war", ["emblema-expansao"] = "season-expansion", ["emblema-catastrofe"] = "season-catastrophe",
}
local EVENT_ICONS = {
	colheita = "event-harvest", febre = "event-gold-rush", mutirao = "event-work", inspiracao = "event-inspiration",
	lua = "event-blood-moon", caravana = "event-caravan",
}

-- bannerColor/emblemIcon de src/ui/ctx.js (também usados pela barra de visita do Stage).
function Hud.bannerColor(id)
	for _, b in Cosmetics.BANNERS do
		if b.id == id then
			return hex(b.color)
		end
	end
	return hex("#c92a2a")
end
function Hud.emblemIcon(id)
	for _, e in Cosmetics.EMBLEMS do
		if e.id == id then
			return e.icon or EMBLEM_ICONS[id] or "crowns"
		end
	end
	return "crowns"
end

-- text-transform: uppercase com os acentos do português (string.upper só mexe em ASCII).
local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
function Hud.upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end
local upper = Hud.upper

local function motion()
	return not (Ctx.config and Ctx.config.reduceMotion)
end

-- Estandarte (.banner): forma tingida com a cor, brilho por cima e o emblema branco.
function Hud.banner(color, emblem, small)
	local w, hgt = small and 24 or 34, small and 28 or 40
	local icoS = small and 15 or 22
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, hgt) }, {
		h("ImageLabel", Assets.with("ui/banner-shape", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageColor3 = color, ScaleType = Enum.ScaleType.Stretch,
		})),
		h("ImageLabel", Assets.with("ui/banner-shine", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 2,
		})),
		-- sombra do emblema (drop-shadow 0 1px 0 rgba(0,0,0,.3))
		U.ico(emblem, T.c.black, icoS, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2 + 1), ImageTransparency = 0.7, ZIndex = 3,
		}),
		U.ico(emblem, WHITE, icoS, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = 4 }),
	})
end

-- ------------------------------------------------------------ música
local function hasMusic()
	local ok, r = pcall(function()
		local A = require(script.Parent:FindFirstChild("Audio"))
		if type(A.hasMusic) == "function" then
			return A.hasMusic()
		end
		return true
	end)
	return not ok or r ~= false
end

-- ------------------------------------------------------------ animações (pulo do número e pulso da horda)
local numLabels = {} -- r -> TextLabel visível do número
local numColor = {} -- r -> cor "de repouso" do número (a do último render)
local bumping = {} -- r -> { kind, t0 }
local pulses = setmetatable({}, { __mode = "k" }) -- UIStroke -> true (status.danger.soon)

local GAIN = { dur = 0.6, color = hex("#9ef0ae"), dy = -3, scale = 1.12 }
local SPEND = { dur = 0.5, color = hex("#ff9c8c"), dy = 2, scale = 1 }

-- cubic-bezier(.2, .8, .2, 1) aproximado (sai rápido, assenta devagar).
local function ease(t)
	return 1 - (1 - t) ^ 3.2
end

local function stepBumps()
	local now = os.clock()
	for r, b in bumping do
		local lab = numLabels[r]
		if not lab or not lab.Parent then
			bumping[r] = nil
			continue
		end
		local k = b.kind == "gain" and GAIN or SPEND
		local t = (now - b.t0) / k.dur
		local sc = lab:FindFirstChildOfClass("UIScale")
		local base = numColor[r] or T.c.onInk
		if t >= 1 then
			bumping[r] = nil
			lab.Position = UDim2.new()
			lab.TextColor3 = base
			if sc then sc.Scale = 1 end
			continue
		end
		-- keyframe em 30%: vai até o pico e volta (cada trecho com a mesma curva, como no CSS)
		local f
		if t < 0.3 then
			f = ease(t / 0.3)
		else
			f = 1 - ease((t - 0.3) / 0.7)
		end
		lab.Position = UDim2.fromOffset(0, k.dy * f)
		lab.TextColor3 = base:Lerp(k.color, f)
		if sc then sc.Scale = 1 + (k.scale - 1) * f end
	end
	-- pulse .8s alternate: box-shadow 0 0 0 4px rgba(255,110,90,.35)
	local p = (math.sin(now * math.pi / 0.8 - math.pi / 2) + 1) / 2
	for st in pulses do
		if st.Parent then
			st.Thickness = motion() and 4 * p or 0
		else
			pulses[st] = nil
		end
	end
end

-- Feedback de recurso: produção normal não anima; ganhos e gastos de uma vez (recompensa, obra) sim.
local lastRes = {}
local lastResKey = nil
local function bump(r, value, rate)
	local prev = lastRes[r]
	lastRes[r] = value
	if prev == nil then
		return
	end
	local d = value - prev
	local tickGain = math.max(0, rate) * 0.6 + 0.5
	local kind = nil
	if d > tickGain + math.max(1, prev * 0.02) then
		kind = "gain"
	elseif d < -math.max(0.5, -math.min(0, rate) * 0.6 + 0.5) then
		kind = "spend"
	end
	if not kind or not motion() then
		return
	end
	bumping[r] = { kind = kind, t0 = os.clock() }
end

-- ------------------------------------------------------------ peças
local INK_LINE_T = 0.92 -- rgba(255,255,255,.08)

-- Número da ficha: um rótulo invisível dá o tamanho e o visível por cima pode pular sem mexer no layout.
local function numNode(r, text, color)
	numColor[r] = color
	local vis = U.b(text, {
		color = color, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		children = { h("UIScale", { Scale = 1 }) },
	})
	vis.props.ref = function(inst)
		numLabels[r] = inst
	end
	return h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
		U.b(text, { color = color, transparency = 1 }),
		vis,
	})
end

local function chip(key, o)
	local mobile = Ctx.mobile
	return h("TextButton", {
		key = key,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.94,
		AutomaticSize = AXY,
		Size = UDim2.new(),
		ClipsDescendants = true,
		tip = o.tip,
		hover = { BackgroundTransparency = 0.89 },
		onClick = function()
			Ctx.run("info", o.arg)
		end,
	}, {
		Kit.corner(10),
		Kit.stroke(WHITE, 1, INK_LINE_T),
		h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
			Kit.pad(rem(0.28), rem(0.6), rem(0.36), rem(0.45)),
			Kit.list("x", { gap = rem(0.35), align = "center" }),
			o.icon,
			numNode(key, o.num, o.full and T.c.goldHi or T.c.onInk),
			(o.rate and not mobile) and U.b(o.rate, { size = 0.72, color = o.rateNeg and hex("#ff8f7d") or hex("#7fd893") }) or nil,
		}),
		-- sombra interna de baixo (inset 0 -2px 0 rgba(0,0,0,.25))
		h("Frame", {
			BackgroundColor3 = T.c.black, BackgroundTransparency = 0.75, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2),
		}),
		o.pct and h("Frame", {
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2,
			Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(o.pct / 100, 0, 0, 3), Visible = o.pct > 0,
		}, {
			Kit.grad(o.full and { T.c.gold, T.c.goldHi } or { hex("#3fae5a"), hex("#7fd893") }, 0),
		}) or nil,
	})
end

-- .status: ícone + duas linhas (small em caixa alta + texto).
local STATUS = {
	safe = { bg = WHITE, bgT = 0.94, stroke = hex("#7fd893"), strokeT = 0.65, ico = hex("#7fd893") },
	danger = { bg = hex("#b8412f"), bgT = 0.72, stroke = hex("#ff8f7d"), strokeT = 0.55, ico = hex("#ffb0a2") },
	event = { bg = hex("#7a52c4"), bgT = 0.7, stroke = hex("#b197fc"), strokeT = 0.55, ico = hex("#cdb9ff") },
	boost = { bg = hex("#f2b632"), bgT = 0.8, stroke = hex("#ffd45c"), strokeT = 0.55, ico = T.c.goldHi },
}
STATUS.ascend = STATUS.boost

local function status(key, kind, icon, small, main, onClick, soon)
	local st = STATUS[kind]
	local mobile = Ctx.mobile
	return h("TextButton", {
		key = key,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		BackgroundTransparency = st.bgT,
		AutomaticSize = AXY,
		Size = UDim2.new(),
		-- .status:hover só vale para a neutra (as coloridas vêm depois no CSS e mantêm o fundo)
		hover = kind == "safe" and { BackgroundTransparency = 0.88 } or nil,
		onClick = onClick,
	}, {
		Kit.corner(10),
		Kit.stroke(st.stroke, 1, st.strokeT),
		mobile and Kit.flex(1, 1) or nil,
		-- .status.danger.soon: anel que pulsa para fora
		soon and h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
			Kit.corner(10),
			h("UIStroke", {
				Color = hex("#ff6e5a"), Transparency = 0.65, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ref = function(inst)
					pulses[inst] = true
				end,
			}),
		}) or nil,
		h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
			Kit.pad(rem(0.3), rem(0.7)),
			Kit.list("x", { gap = rem(0.45), align = "center" }),
			U.ico(icon, st.ico, math.floor(rem(0.85) * 1.35 + 0.5)),
			h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
				Kit.list("y", { gap = 0 }),
				U.b(upper(small), { size = 0.7, color = T.c.onInkMuted, LineHeight = 1.05 }),
				U.text(main, { size = 0.85, color = T.c.onInk, LineHeight = 1.05 }),
			}),
		}),
	})
end

-- ------------------------------------------------------------ texto de ajuda
function Hud.hudInfo(key)
	local g = Ctx.game
	if not g then
		return nil
	end
	local e = g.econ
	local s = g.state
	local ev = s.event and Events.EVENT_BY_ID[s.event.id]
	local txt = {
		gold = "Ouro paga quase tudo. Vem de casas (impostos), mercados e minas. Limite: " .. fmt(e.caps.gold) .. " (armazéns aumentam).",
		food = "Comida: cada morador come 0,15/s. Sem comida, moradores vão embora e mercados param. Consumo atual: " .. fmt(e.foodConsumption) .. "/s.",
		wood = "Madeira vem das serrarias; cada floresta vizinha dá +40%.",
		stone = "Pedra vem das pedreiras (rochas vizinhas dão +50%). Necessária para defesa e expansão.",
		gems = "Gemas vêm de invasões, carroças, missões, conquistas, passe e expedições, ou da Loja de Gemas (aba Perfil). Compram recursos, impulsos, pergaminhos, aceleram treinos e expedições e liberam cosméticos.",
		pop = "Moradores " .. math.floor(s.pop) .. " de " .. e.popCap .. ". Os prédios pedem " .. e.workersNeeded .. " trabalhadores. Fazendas e moinhos são ocupados primeiro; com menos gente, os outros prédios rendem menos.",
		happiness = "Felicidade " .. math.floor(e.happiness) .. ": multiplica toda a produção por " .. string.format("%.2f", e.happinessMult) .. ". Tavernas, templos e decorações aumentam; pedreiras, minas e superlotação reduzem.",
		raid = "A próxima horda vem do " .. DIR_NAMES[s.raid.dir] .. ". Torres e muralhas desse lado do mapa contam 100%; do lado oposto, 50%. Muralha de lado para a horda conta só metade. Heróis do Conselho sempre contam inteiros. Se a horda vencer, ela danifica construções desse lado (muralhas e torres seguram os golpes primeiro); o que não for consertado até a próxima derrota vira ruína.",
		event = ev and (ev.name .. ": " .. ev.desc) or "Nenhum evento agora.",
		boost = "Bênção: +50% em toda a produção enquanto durar.",
	}
	return txt[key]
end

-- ------------------------------------------------------------ desenho
local root = nil
local hudH = 0
local outerInst = nil

local function build()
	local g = Ctx.game
	local s = g.state
	local e = g.econ
	local now = Ctx.now()
	local mobile = Ctx.mobile

	local key = tostring(s.seed) .. ":" .. tostring(s.stats.ascensions) .. ":" .. tostring(s.createdAt)
	if lastResKey ~= key then -- reino novo/importado/ascendido: sem "pulo" falso
		lastRes = {}
		lastResKey = key
	end

	-- fichas
	local chips = {}
	for _, r in RES_LIST do
		bump(r, s.res[r], e.rates[r])
		local pct = math.min(100, (s.res[r] / e.caps[r]) * 100)
		table.insert(chips, chip(r, {
			arg = r,
			icon = U.resIco(r, rem(1.25), true),
			num = fmt(s.res[r]),
			rate = Util.fmtRate(e.rates[r]),
			rateNeg = e.rates[r] < 0,
			pct = pct,
			full = pct >= 99.5,
			tip = Buildings.RESOURCES[r].name .. ": " .. fmt(s.res[r]) .. " de " .. fmt(e.caps[r]),
		}))
	end
	bump("gems", s.res.gems, 0)
	table.insert(chips, chip("gems", { arg = "gems", icon = U.resIco("gems", rem(1.25), true), num = fmt(s.res.gems) }))
	table.insert(chips, chip("pop", {
		arg = "pop", icon = U.ico("people", T.c.onInk, rem(1.25)),
		num = math.floor(s.pop) .. "/" .. e.popCap, rate = e.workersNeeded .. " trab.", rateNeg = e.staffing < 1,
	}))
	table.insert(chips, chip("happy", {
		arg = "happiness", icon = U.ico("heart", T.resHud.heart, rem(1.25)),
		num = tostring(math.floor(e.happiness)), rate = "x" .. string.format("%.2f", e.happinessMult),
	}))

	-- situação
	local view = Ctx.renderer and Ctx.renderer.view
	local pills = {}
	local strength = g:raidStrength()
	local raidIn = (s.raid.nextAt - now) / 1000
	local safe = e.defense >= strength
	local defTxt = fmt(e.defense)
	if not safe then
		defTxt = U.color(defTxt, hex("#ffb0a2"))
	end
	table.insert(pills, status("raid", safe and "safe" or "danger", safe and "defense" or "warning",
		"Horda pelo " .. DIR_NAMES[s.raid.dir] .. " · " .. (s.raid.warned and "chegando" or fmtTime(raidIn)),
		"Defesa <b>" .. defTxt .. "</b> / " .. fmt(strength) .. " " .. (safe and "· protegido" or "· vulnerável"),
		Ctx.does("info", "raid"), not safe and raidIn < 20 and motion()))
	local broken = g:damagedCount()
	if broken > 0 and not view then
		table.insert(pills, status("repair", "danger", "build", broken .. " danificada" .. (broken > 1 and "s" or ""), "Consertar tudo", Ctx.does("repairAll")))
	end
	local ev = s.event and s.event.endsAt > now and Events.EVENT_BY_ID[s.event.id] or nil
	if ev then
		table.insert(pills, status("event", "event", ev.icon or EVENT_ICONS[ev.id] or "star",
			"Evento · " .. fmtTime((s.event.endsAt - now) / 1000), U.esc(ev.name), Ctx.does("info", "event")))
	end
	if (s.boostUntil or 0) > now then
		table.insert(pills, status("boost", "boost", "boost", "Bênção · " .. fmtTime((s.boostUntil - now) / 1000), "+50% produção", Ctx.does("info", "boost")))
	end
	local adv = g:isTabUnlocked("legado") and g:ascendAdvice() or nil
	if adv and adv.recommended then
		table.insert(pills, status("ascend", "ascend", "crowns", "Vale ascender", "+" .. adv.crowns .. " " .. (adv.crowns == 1 and "Coroa" or "Coroas"), Ctx.does("tab", "legado")))
	end

	-- marca
	local k = s.kingdom
	local brand = h("Frame", {
		key = "brand", BackgroundTransparency = 1, AutomaticSize = mobile and AY or AXY,
		Size = mobile and UDim2.fromOffset(0, 0) or UDim2.new(),
	}, {
		Kit.list("x", { gap = rem(0.55), align = "center" }),
		mobile and Kit.flex(1, 1) or Kit.sizeLimit(Vector2.new(rem(11), 0)),
		Hud.banner(Hud.bannerColor(k.banner), Hud.emblemIcon(k.emblem)),
		h("Frame", {
			BackgroundTransparency = 1, AutomaticSize = mobile and AY or AXY,
			Size = mobile and UDim2.new(1, -(34 + rem(0.55)), 0, 0) or UDim2.new(),
		}, {
			Kit.list("y", { gap = 0 }),
			U.b(U.esc(k.name), { size = 1.05, color = T.c.onInk, LineHeight = 1.15, truncate = mobile, Size = mobile and UDim2.fromScale(1, 0) or nil, AutomaticSize = mobile and AY or nil }),
			U.text(U.esc(k.title) .. " · Poder " .. fmt(Economy.kingdomPower(s)), {
				size = 0.75, color = T.c.onInkMuted, truncate = mobile, Size = mobile and UDim2.fromScale(1, 0) or nil, AutomaticSize = mobile and AY or nil,
			}),
		}),
	})

	local menuBtn = U.btn({ key = "menu", icon = "menu", small = true, iconOnly = true, iconSize = rem(1.35), onClick = Ctx.does("gameMenu") })
	local musicBtn = nil
	if hasMusic() then
		local cfg = Ctx.config
		local on = cfg.musicOn and Config.effectiveVolumes(cfg).music > 0
		-- [aria-pressed=false] { opacity: .7 }
		musicBtn = h("CanvasGroup", {
			key = "music", BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new(), GroupTransparency = on and 0 or 0.3,
		}, {
			U.btn({
				icon = on and "music" or "speaker-off", small = true, iconOnly = true, iconSize = rem(1.35),
				tip = on and "Desligar a música" or "Ligar a música", onClick = Ctx.does("toggleMusic"),
			}),
		})
	end

	local inner = mobile and (Ctx.vp.X - 32) or (Ctx.vp.X - rem(0.75) * 2)
	local resNode, statusNode
	if mobile then
		resNode = h("ScrollingFrame", {
			key = "res", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		}, {
			Kit.list("x", { gap = rem(0.35), align = "center" }),
			Kit.pad(0, rem(1.5), 0, 0),
			chips,
		})
		statusNode = h("Frame", { key = "status", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.list("x", { gap = rem(0.4), wrap = true, align = "center" }),
			pills,
		})
	else
		resNode = h("Frame", { key = "res", BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(7), 0), AutomaticSize = AY }, {
			Kit.flex(1, 1),
			Kit.list("x", { gap = rem(0.35), wrap = true, align = "center" }),
			chips,
		})
		statusNode = h("Frame", { key = "status", BackgroundTransparency = 1, Size = UDim2.new(), AutomaticSize = AXY }, {
			Kit.sizeLimit(nil, Vector2.new(inner, math.huge)),
			Kit.list("x", { gap = rem(0.4), wrap = true, align = "center" }),
			pills,
		})
	end

	local content
	if mobile then
		content = h("Frame", {
			Name = "Conteudo", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
			onSize = function(inst)
				hudH = inst.AbsoluteSize.Y
				if outerInst then outerInst.Size = UDim2.new(1, 0, 0, hudH) end
			end,
		}, {
			Kit.pad(rem(0.4), 16),
			Kit.list("y", { gap = rem(0.4) }),
			h("Frame", { key = "top", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
				Kit.list("x", { gap = rem(0.4), align = "center" }),
				menuBtn, brand, musicBtn,
			}),
			resNode,
			#pills > 0 and statusNode or nil,
		})
	else
		content = h("Frame", {
			Name = "Conteudo", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
			onSize = function(inst)
				hudH = inst.AbsoluteSize.Y
				if outerInst then outerInst.Size = UDim2.new(1, 0, 0, hudH) end
			end,
		}, {
			Kit.pad(rem(0.45), rem(0.75)),
			Kit.list("x", { gap = rem(0.6), wrap = true, align = "center" }),
			menuBtn, brand, musicBtn, resNode, statusNode,
		})
	end

	return h("Frame", {
		Name = "HudFundo",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, hudH),
		ref = function(inst)
			outerInst = inst
		end,
	}, {
		Kit.grad({ T.c.ink3, T.c.ink2 }, 90),
		content,
		-- 0 1px 0 var(--ink-line) inset
		h("Frame", { Name = "Luz", BackgroundColor3 = WHITE, BackgroundTransparency = INK_LINE_T, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) }),
		-- border-bottom: 1px solid rgba(0,0,0,.5)
		h("Frame", { Name = "Borda", BackgroundColor3 = T.c.black, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 2 }),
		-- 0 6px 18px rgba(0,0,0,.35)
		h("Frame", { Name = "Sombra", BackgroundColor3 = T.c.black, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 18) }, {
			Kit.grad({ T.c.black, T.c.black }, 90, { { 0, 0.62 }, { 0.4, 0.82 }, { 1, 1 } }),
		}),
	})
end

function Hud.init(frame)
	root = frame
	RunService.Heartbeat:Connect(stepBumps)
end

function Hud.render(force)
	if not root then
		return
	end
	if not Ctx.game then
		Kit.render(root, nil)
		return
	end
	Kit.render(root, build())
	-- renderHud também atualiza a rosa dos ventos e o banner do tutorial (no web ficam no mesmo laço de 250 ms).
	local ok, Stage = pcall(require, script.Parent.Stage)
	if ok and Stage and Stage.hudTick then
		Stage.hudTick()
	end
end

return Hud
