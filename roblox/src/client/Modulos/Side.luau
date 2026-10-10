-- Painel lateral (#side do web): barra de abas e o corpo com rolagem de cada aba.
-- Porte de renderSide, tabReino, tabHerois, tabTemporada, tabLegado, tabSocial, tabPerfil, lockedTabHint,
-- describeBonus (src/ui/panels.js) e runHistoryHtml (src/ui/ascension.js), com o visual do styles.css.
-- Botões chamam Ctx.run(<data-action do web>, <data-arg>); as ações ficam no Controller.
-- Diferença de índices: claimMission e runSummary recebem o índice Luau (1 = primeiro), não o do JS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Assets = require(script.Parent.Assets)
local Ctx = require(script.Parent.Ctx)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Economy = require(Reino.Core.Economy)
local Season = require(Reino.Core.Season)
local HeroCore = require(Reino.Core.Heroes)
local Game = require(Reino.Core.Game)
local Buildings = require(Reino.Data.Buildings)
local HeroData = require(Reino.Data.Heroes)
local Talents = require(Reino.Data.Talents)
local Seasons = require(Reino.Data.Seasons)
local Achievements = require(Reino.Data.Achievements)
local Shop = require(Reino.Data.Shop)
local Cosmetics = require(Reino.Data.Cosmetics)

local h = Kit.h
local rem = T.rem
local hex = T.hex
local AY, AXY = Enum.AutomaticSize.Y, Enum.AutomaticSize.XY
local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local fmt, fmtRate, fmtTime = Util.fmt, Util.fmtRate, Util.fmtTime
local esc = U.esc

local Side = {}

-- ------------------------------------------------------------ ícones que o porte dos dados não trouxe (iguais aos .js)
local HERO_ICON = {
	lavradora = "hero-farmer", lenhador = "hero-woodcutter", pedreiro = "hero-mason", guarda = "hero-guard",
	coletora = "hero-collector", mercadora = "hero-merchant", arqueira = "hero-archer", bardo = "hero-bard",
	exploradora = "hero-explorer", arquiteta = "hero-architect", cavaleiro = "hero-knight", alquimista = "hero-alchemist",
	druida = "hero-druid", rainha = "hero-queen", dragao = "hero-dragon", relojoeiro = "hero-clock",
}
local TALENT_ICON = {
	fartura = "talent-harvest", heranca = "talent-inheritance", muralhas = "talent-walls", vigilia = "talent-vigil",
	engenharia = "talent-engineering", garimpo = "talent-mining", terras = "map", mesa = "talent-round-table",
	mordomo = "talent-butler",
}
local EMBLEM_ICON = {
	coroa = "crowns", escudo = "emblem-shield", leao = "emblem-lion", arvore = "emblem-tree", lobo = "emblem-wolf",
	aguia = "emblem-eagle", rosa = "emblem-rose", caveira = "emblem-skull", ["emblema-fundacao"] = "season-foundation",
	["emblema-guerra"] = "season-war", ["emblema-expansao"] = "season-expansion", ["emblema-catastrofe"] = "season-catastrophe",
}
local THEME_ICON = {
	fundacao = "season-foundation", guerra = "season-war", expansao = "season-expansion", catastrofe = "season-catastrophe",
}

local TAB_LIST = {
	{ "reino", "castle" }, { "herois", "tab-heroes" }, { "temporada", "star" },
	{ "legado", "crowns" }, { "social", "tab-social" }, { "perfil", "tab-profile" },
}

-- Cores fixas do styles.css.
local C = {
	dot = hex("#e0523d"),
	rarity = { comum = hex("#6f7782"), raro = hex("#2f7cc0"), epico = hex("#7a52c4"), lendario = hex("#b9820e") },
	starOff = hex("#d5cdbb"),
	crowns = hex("#b9820e"),
	tabsBottom = hex("#e2d6bb"),
	readyA = hex("#fff6d6"), readyB = hex("#fde9b0"),
	meB = hex("#fffaf0"),
	gotB = hex("#fdefc6"),
	shadowA = hex("#e9e3f7"), shadowB = hex("#d9cff0"), shadowLine = hex("#6e50aa"),
	rank = { hex("#c99400"), hex("#8d96a0"), hex("#b0703a") },
	grey999 = hex("#999999"),
	panelLine = hex("#3c2800"),
	tagText = hex("#2a1d00"),
	scroll = hex("#645a46"),
}

-- ------------------------------------------------------------ utilitários
-- color-mix(in srgb, a t, b)
local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, 1 - t)
end

local function B(s)
	return '<font weight="800">' .. s .. "</font>"
end

-- text-transform: uppercase com acentos (string.upper só troca ASCII).
local ACCENT_UP = {
	["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í",
	["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç",
}
local function upper(s)
	s = string.upper(s)
	for lo, up in ACCENT_UP do
		s = string.gsub(s, lo, up)
	end
	return s
end

-- Largura aproximada de um texto (Nunito normal; negrito ~8% mais largo). Só para montar colunas "auto".
local widthCache = {}
local function textW(str, px, bold)
	local k = str .. "|" .. px .. (bold and "b" or "")
	local w = widthCache[k]
	if w then
		return w
	end
	local ok, v = pcall(function()
		return TextService:GetTextSize(str, px, Enum.Font.Nunito, Vector2.new(10000, 10000)).X
	end)
	w = ok and v or (#str * px * 0.55)
	if bold then
		w *= 1.08
	end
	widthCache[k] = w
	return w
end

-- Largura de um .btn (para colunas auto ao lado de texto que quebra).
local function btnW(text, o)
	local fs = o.small and 0.85 or 0.95
	local padX = o.small and rem(0.45) or rem(0.6)
	local w = 16 + padX * 2 + textW(text, rem(fs), true)
	if o.icon then
		w += math.floor(rem(fs) * 1.25 + 0.5) + rem(0.45)
	end
	return math.ceil(w + (o.extra or 0))
end

local function utf8sub(s, n)
	local len = utf8.len(s)
	if not len or len <= n then
		return s
	end
	return string.sub(s, 1, (utf8.offset(s, n + 1) or (#s + 1)) - 1)
end

local function spacer(px)
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, px) })
end

-- Margens do CSS (em rem) entre blocos, com o colapso de margens verticais: M(nó, topo, baixo).
local function M(node, mt, mb)
	return { __m = true, node = node, mt = mt or 0, mb = mb or 0 }
end
-- Achata a lista (pula nil/false, abre listas aninhadas) e põe espaçadores com o maior dos dois lados.
local function stack(items)
	local flat = {}
	local function walk(list)
		if not list then
			return
		end
		local n = 0
		for k in list do
			if type(k) == "number" and k > n then
				n = k
			end
		end
		for i = 1, n do
			local c = list[i]
			if c then
				if c.class or c.__m then
					table.insert(flat, c)
				else
					walk(c)
				end
			end
		end
	end
	walk(items)
	local out = {}
	local prev = nil
	for _, it in flat do
		if not it.__m then
			it = M(it, 0, 0)
		end
		local gap = prev == nil and it.mt or math.max(prev, it.mt)
		if gap > 0 then
			table.insert(out, spacer(rem(gap)))
		end
		table.insert(out, it.node)
		prev = it.mb
	end
	if prev and prev > 0 then
		table.insert(out, spacer(rem(prev)))
	end
	return out
end

local function box(props, children)
	return h("Frame", U.merge({ BackgroundTransparency = 1, AutomaticSize = AY, Size = UDim2.fromScale(1, 0) }, props), children)
end

-- Texto em bloco (p, small, em...).
local function para(str, o)
	o = o or {}
	return U.text(str, U.merge({
		wrap = true, size = o.size or 1, color = o.color or (o.muted and T.c.muted or T.c.text),
		lineHeight = o.lineHeight or 1.45, bold = o.bold,
	}, o.props))
end
local function p(str, o)
	return M(para(str, o), 0.25, 0.6)
end

-- Ícone seguido de texto que quebra (o ico inline no começo de um parágrafo).
local function icoPara(icon, iconColor, str, o)
	o = o or {}
	local size = o.size or 1
	local is = math.floor(rem(size) * 1.25 + 0.5)
	local gap = rem(0.25)
	return box(nil, {
		Kit.list("x", { gap = gap, align = "start" }),
		U.ico(icon, iconColor or (o.muted and T.c.muted or T.c.text), is),
		para(str, { size = size, muted = o.muted, color = o.color, props = { Size = UDim2.new(1, -(is + gap), 0, 0) } }),
	})
end

-- .card
local function card(key, items)
	return h("Frame", { key = key, BackgroundColor3 = T.c.white, AutomaticSize = AY, Size = UDim2.fromScale(1, 0) }, {
		Kit.corner(T.r),
		Kit.stroke(T.c.line, 1, 0),
		Kit.pad(rem(0.8), rem(0.85)),
		Kit.list("y", { gap = 0 }),
		stack(items),
	})
end
local function h3(icon, title, count)
	return M(U.cardTitle(icon, title, count), 0, 0.6)
end
-- h4: caixa alta, cinza
local function h4(str, extra)
	local s = upper(str)
	if extra then
		s ..= " " .. string.format('<font size="%d">%s</font>', math.floor(rem(0.8) * 0.82 + 0.5), upper(extra))
	end
	return M(U.text(s, { bold = true, size = 0.8, color = T.c.muted, wrap = true, lineHeight = 1.2 }), 1, 0.4)
end

-- .row (flex, wrap, gap .4rem, margem .4rem 0)
local function row(children, o)
	o = o or {}
	return M(U.row({ gap = rem(0.4), wrap = true }, children), o.mt or 0.4, o.mb or 0.4)
end

-- Linha com valor inline (sem quebra): ícone + textos lado a lado.
local function inl(children, gap)
	return U.row({ fill = false, gap = gap or rem(0.2) }, children)
end

-- .bar (com opacidade opcional misturada no fundo)
local BAR = {
	normal = { "#5cc777", "grass" },
	gold = { "#ffd45c", "#e0a21b" },
	big = { "#b79aff", "purple" },
}
local function barColor(v)
	return string.sub(v, 1, 1) == "#" and hex(v) or T.c[v]
end
local function bar(frac, label, o)
	o = o or {}
	local f = o.fade
	local function c(col)
		return f and mix(col, o.bg or T.c.white, f) or col
	end
	local big = o.kind == "big"
	local hgt = big and 26 or 18
	local cols = BAR[o.kind or "normal"] or BAR.normal
	frac = math.clamp(frac or 0, 0, 1)
	return h("Frame", {
		BackgroundColor3 = c(T.c.paper3),
		Size = UDim2.new(o.width or UDim.new(1, 0), UDim.new(0, hgt)),
		ClipsDescendants = true,
	}, {
		Kit.corner(99),
		h("Frame", { BackgroundColor3 = T.c.white, Size = UDim2.fromScale(frac, 1), Visible = frac > 0 }, {
			Kit.corner(99),
			Kit.grad({ c(barColor(cols[1])), c(barColor(cols[2])) }, 90),
		}),
		label and U.text(label, {
			bold = true, size = big and 0.8 or 0.72, color = c(T.c.text), align = CENTER,
			Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 2,
			TextStrokeColor3 = T.c.white, TextStrokeTransparency = 0.35,
		}) or nil,
	})
end

-- .xp: pílula roxa (ou verde quando feita)
local function xpPill(text, icon, color, tip)
	local size = 0.78
	return h("Frame", {
		BackgroundColor3 = mix(color, T.c.white, 0.1),
		AutomaticSize = AXY,
		Size = UDim2.new(),
		Active = tip ~= nil,
		tip = tip,
	}, {
		Kit.corner(99),
		Kit.pad(rem(0.15), rem(0.55)),
		Kit.list("x", { gap = rem(0.2), align = "center" }),
		icon and U.ico(icon, color, math.floor(rem(size) * 1.25 + 0.5)) or nil,
		U.text(text, { bold = true, size = size, color = color }),
	})
end

-- Linha tracejada entre itens de lista.
local function dashed()
	return U.dashed()
end

-- Linhas "rótulo: valor" (.grid2: auto 1fr; valores à direita).
local function grid2(rows)
	local size = rem(0.92)
	local lw = 0
	for _, r in rows do
		lw = math.max(lw, textW(r[1], size, false))
	end
	lw = math.ceil(lw) + 2
	local gapX = rem(0.8)
	local kids = { Kit.list("y", { gap = rem(0.25) }) }
	for _, r in rows do
		table.insert(kids, box(nil, {
			Kit.list("x", { gap = gapX, align = "start" }),
			U.text(r[1], { size = 0.92, color = T.c.muted, wrap = true, lineHeight = 1.45, Size = UDim2.fromOffset(lw, 0) }),
			U.text(r[2], {
				size = 0.92, bold = true, color = r[3] and T.c.bad or T.c.text, wrap = true, align = RIGHT, lineHeight = 1.45,
				Size = UDim2.new(1, -(lw + gapX), 0, 0),
			}),
		}))
	end
	return box(nil, kids)
end

-- Duas colunas iguais com a mesma altura (grid 1fr 1fr).
local function pairsGrid(items, gap, cols)
	cols = cols or 2
	local out = { Kit.list("y", { gap = gap }) }
	for i = 1, #items, cols do
		local kids = { Kit.list("x", { gap = gap, align = "start", itemFlex = Enum.ItemLineAlignment.Stretch }) }
		for j = i, math.min(#items, i + cols - 1) do
			table.insert(kids, items[j])
		end
		table.insert(out, box(nil, kids))
	end
	return box(nil, out)
end

-- Campo de texto (input[type=text]).
local function textInput(key, value, o)
	return h("TextBox", {
		key = key,
		BackgroundColor3 = T.c.white,
		Text = value,
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = hex("#8f8a99"),
		ClearTextOnFocus = false,
		FontFace = T.font,
		TextSize = rem(1),
		TextColor3 = T.c.text,
		TextXAlignment = LEFT,
		TextTruncate = Enum.TextTruncate.None,
		ClipsDescendants = true,
		Size = o.size,
		onText = o.onText,
		ref = function(inst)
			local stroke = inst:FindFirstChild("Borda")
			inst.Focused:Connect(function()
				if stroke then
					stroke.Color = T.c.gold
				end
			end)
			inst.FocusLost:Connect(function()
				if stroke then
					stroke.Color = T.c.line
				end
			end)
		end,
	}, {
		Kit.corner(10),
		h("UIStroke", { Name = "Borda", Color = T.c.line, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Kit.pad(0, rem(0.7)),
	})
end
local function inputH()
	return math.floor(rem(1) * 1.45 + rem(1) + 0.5)
end

-- Estandarte pequeno (.banner.sm): forma de bandeira na cor bc com o emblema branco.
local function bannerSm(color, emblem)
	local hasImg = Assets.has("ui/banner-shape")
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 28) }, {
		h("ImageLabel", U.merge(Assets.image("ui/banner-shape"), {
			BackgroundColor3 = color, BackgroundTransparency = hasImg and 1 or 0,
			ImageColor3 = color, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch,
		})),
		hasImg and h("ImageLabel", U.merge(Assets.image("ui/banner-shine"), {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 2,
		})) or nil,
		U.ico(EMBLEM_ICON[emblem] or "crowns", T.c.white, 15, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = 3,
		}),
	})
end

local function bannerColor(id)
	local b = Util.find(Cosmetics.BANNERS, function(x)
		return x.id == id
	end)
	return hex(b and b.color or "#c92a2a")
end

-- ------------------------------------------------------------ animações (ping da bolinha, bob do passe)
local anims: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local function animRef(kind)
	return function(inst)
		anims[inst] = kind
	end
end

-- ------------------------------------------------------------ API pública
function Side.lockedTabHint(id)
	for _, rule in Game.TAB_UNLOCKS do
		if rule.tab == id then
			return rule.hint or ""
		end
	end
	return ""
end

function Side.describeBonus(type_, v)
	local t, r = string.match(type_, "^([^:]+):?(.*)$")
	local pct = function()
		return tostring(Util.round(v * 100))
	end
	if t == "prod" then
		local res = Buildings.RESOURCES[r]
		return "+" .. pct() .. "% de " .. string.lower(res and res.name or r)
	elseif t == "prodAll" then
		return "+" .. pct() .. "% em toda a produção"
	elseif t == "defense" then
		return "+" .. pct() .. "% de defesa"
	elseif t == "happiness" then
		return "+" .. tostring(Util.round(v)) .. " de felicidade"
	elseif t == "expedition" then
		return "+" .. pct() .. "% nas expedições"
	elseif t == "cost" then
		return "-" .. pct() .. "% no custo de obras"
	elseif t == "raidLoot" then
		return "+" .. pct() .. "% de saque"
	elseif t == "terrainAdj" then
		return "+" .. pct() .. "% na adjacência de terreno"
	elseif t == "offline" then
		return "+" .. pct() .. "% de eficiência offline"
	end
	return t or type_
end

-- ------------------------------------------------------------ estado local
local root: Frame? = nil
local paper, tabsBar, tabsTop, tabsFill, tabsLine, tabsHolder, bodyBg, bodyFill, scroller
local shadowInst = nil
local lastTab = nil
local hoverTab = nil
local inputs = { friendCode = "", kname = nil }
local lastKName = nil
local contentH = 0

local function tabsHeight()
	local labelH = math.floor(rem(Ctx.small and 0.6 or 0.66) * 1.45 + 0.5)
	return rem(0.4) + rem(0.45) + rem(1.45) + rem(0.15) + labelH + rem(0.35) + 1
end

-- ================================================================ aba Reino
local function tabReino(g)
	local s = g.state
	local e = g.econ
	local cost = g:expandCost()
	local daily = g:dailyStatus()
	local missions = s.season.missions and s.season.missions.list or {}
	local done = 0
	for _, m in missions do
		if m.claimed then
			done += 1
		end
	end

	local mRows = {}
	local barW = Ctx.mobile and rem(5) or rem(6.5)
	local rightW = rem(5.6)
	local gap = rem(0.5)
	for i, m in missions do
		local ready = not m.claimed and m.progress >= m.target
		local f = m.claimed and 0.55 or nil
		local function c(col)
			return f and mix(col, T.c.white, f) or col
		end
		local right
		if m.claimed then
			right = xpPill("Feita", "check", c(T.c.good))
		elseif ready then
			right = U.btn({
				small = true, variant = "primary", text = "Resgatar", tip = "+" .. m.xp .. " XP de temporada",
				onClick = Ctx.does("claimMission", i),
			})
		else
			right = xpPill("+" .. m.xp .. " XP", nil, T.c.purple, "Recompensa ao concluir")
		end
		local last = i == #missions
		table.insert(mRows, box({ key = "m" .. i }, {
			Kit.list("y", { gap = 0 }),
			box(nil, {
				Kit.pad(rem(0.4), 0),
				Kit.list("x", { gap = gap, align = "center" }),
				U.text(esc(Season.missionText(m)), {
					wrap = true, size = 0.9, color = c(T.c.text), lineHeight = 1.45,
					Size = UDim2.new(1, -(barW + rightW + gap * 2), 0, 0),
				}),
				bar(m.progress / m.target, fmt(m.progress) .. "/" .. fmt(m.target), {
					width = UDim.new(0, barW), kind = ready and "gold" or nil, fade = f,
				}),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rightW, 0), AutomaticSize = AY }, {
					Kit.list("x", { justify = "end", align = "center" }),
					right,
				}),
			}),
			not last and dashed() or nil,
		}))
	end

	local dailyText = daily.available and "Recompensa diária disponível"
		or string.format("Recompensa diária · %d %s", s.daily.streak, s.daily.streak == 1 and "dia seguido" or "dias seguidos")

	local logItems = {}
	local nLog = math.min(12, #s.log)
	for i = 1, nLog do
		local l = s.log[i]
		local is = rem(1.06)
		table.insert(logItems, box({ key = "l" .. i }, {
			Kit.list("y", { gap = 0 }),
			box(nil, {
				Kit.pad(rem(0.3), 0),
				Kit.list("x", { gap = rem(0.5), align = "center" }),
				U.ico(l.icon or "scroll", T.c.muted, is),
				U.text(esc(l.text), { wrap = true, size = 0.85, lineHeight = 1.45, Size = UDim2.new(1, -(is + rem(0.5)), 0, 0) }),
			}),
			i < nLog and dashed() or nil,
		}))
	end
	if nLog == 0 then
		table.insert(logItems, box(nil, {
			Kit.pad(rem(0.3), 0),
			U.text("Nada aconteceu... ainda.", { wrap = true, size = 0.85, color = T.c.muted, lineHeight = 1.45 }),
		}))
	end

	local econ = {
		{ "Ouro", fmtRate(e.rates.gold) },
		{ "Comida", fmtRate(e.rates.food), e.rates.food < 0 },
		{ "Madeira", fmtRate(e.rates.wood) },
		{ "Pedra", fmtRate(e.rates.stone) },
		{ "Trabalho", string.format("%d%% (%d/%s)", Util.round(e.staffing * 100), math.floor(s.pop), tostring(e.workersNeeded)), e.staffing < 1 },
		{ "Felicidade", string.format("%d (x%.2f)", math.floor(e.happiness), e.happinessMult) },
		{ "Defesa por lado", string.format("N %s · S %s · L %s · O %s", fmt(e.defenseByDir.n), fmt(e.defenseByDir.s), fmt(e.defenseByDir.e), fmt(e.defenseByDir.w)) },
		{ "Invasões", string.format("%d vitórias · nível %d", s.stats.raidsWon, s.raid.level) },
	}

	local territory
	if cost then
		local afford = Economy.canAfford(s.res, cost)
		territory = {
			p(string.format("Anel %d de 5. Próxima expansão:", s.grid.ring)),
			U.btn({
				variant = afford and "primary" or "grey", poor = not afford, text = "Expandir",
				onClick = Ctx.does("expand"),
				children = U.cost(cost, s.res, { fmt = fmt, size = 0.95, color = afford and hex("#3b2a00") or T.c.text }),
			}),
		}
	else
		territory = { p("O mapa inteiro é seu.") }
	end

	return {
		card("missoes", {
			h3("mission", "Missões do dia", done .. "/" .. #missions),
			mRows,
			#missions > 0 and spacer(rem(0.4)) or nil,
			U.btn({
				variant = daily.available and "primary" or "grey", icon = "calendar", text = dailyText,
				onClick = Ctx.does("showDaily"),
			}),
		}),
		card("economia", {
			h3("stats", "Economia"),
			grid2(econ),
			e.rates.food < 0 and M(U.warn("A comida está acabando. Sem comida, moradores vão embora e mercados param."), 0.45, 0.45) or nil,
			e.marketRatio < 1 and M(U.warn("Mercados sem comida suficiente."), 0.45, 0.45) or nil,
		}),
		card("territorio", { h3("map", "Território"), territory }),
		card("cronica", { h3("scroll", "Crônica do reino"), box(nil, { Kit.list("y", { gap = 0 }), logItems }) }),
	}
end

-- ================================================================ aba Heróis
local function stars(n)
	local kids = {}
	for i = 1, HeroData.MAX_STARS do
		table.insert(kids, U.ico("star", i <= n and C.rarity.lendario or C.starOff, rem(0.9)))
	end
	return U.row({ fill = false, gap = 1 }, kids)
end

local function gemsCost(n, size)
	return inl({
		U.text("(" .. n, { bold = true, size = size }),
		U.resIco("gems", math.floor(rem(size) * 1.25 + 0.5)),
		U.text(")", { bold = true, size = size }),
	}, rem(0.15))
end

local function tabHerois(g)
	local s = g.state
	local slots = HeroCore.councilSlots(g.econ.mods)
	local goldCost = HeroCore.recruitGoldCost(s)
	local now = Ctx.now()
	local owned, missing = {}, {}
	for _, hero in HeroData.HEROES do
		if s.heroes.owned[hero.id] then
			table.insert(owned, hero)
		else
			table.insert(missing, hero)
		end
	end
	local cap = HeroCore.heroLevelCap(s)
	local tSlots = HeroCore.trainingSlots(s)
	local busy = HeroCore.trainingCount(s) >= tSlots
	local active = HeroCore.activeExpeditions(s)
	local expSlots = HeroCore.expeditionSlots(s)
	local fsSmall = 0.85

	-- largura do conteúdo do card do herói (para decidir se o botão de treino quebra linha)
	local sideW = root and root.AbsoluteSize.X or rem(25)
	local contentW = sideW - 8 - rem(0.75) * 2 - rem(0.85) * 2 - 2 - rem(0.6) * 2 - 6 - 56 - rem(0.6)

	local function trainBlock(hero, o)
		if tSlots == 0 then
			return nil
		end
		local lvl = o.level or 1
		if o.training then
			local left = (o.training.endsAt - now) / 1000
			return row({
				inl({ U.ico("swords", T.c.text, rem(1.25)), U.text("Treinando para o nível " .. (lvl + 1) .. " · " .. fmtTime(math.max(0, left)), { wrap = false }) }, rem(0.25)),
				U.btn({
					small = true, icon = "speedup", text = "Acelerar", onClick = Ctx.does("speedupTrain", hero.id),
					children = gemsCost(HeroCore.speedUpCost(left), fsSmall),
				}),
			}, { mb = 0 })
		end
		if o.expedition then
			return nil
		end
		if lvl >= HeroData.HERO_MAX_LEVEL then
			return nil
		end
		if lvl >= cap then
			return M(icoPara("lock", T.c.muted, "Melhore o Quartel para treinar além do nível " .. cap .. ".", { muted = true }), 0.25, 0.6)
		end
		local cost = HeroCore.trainCost(hero, lvl)
		local ok = not busy and Economy.canAfford(s.res, cost)
		local label = "Treinar: nível " .. (lvl + 1)
		local costNode = U.cost(cost, s.res, { fmt = fmt, size = fsSmall, color = T.c.text })
		local est = btnW(label, { small = true, icon = true, extra = rem(0.45) + 110 })
		local wrap = est > contentW
		return row({
			U.btn({
				small = true, poor = not ok, icon = "swords", wrap = wrap, width = wrap and UDim.new(1, 0) or nil,
				tip = busy and "Quartel ocupado" or nil, onClick = Ctx.does("train", hero.id),
				children = { U.text(label, { bold = true, size = fsSmall, color = hex("#2b2a33"), transparency = ok and 0 or 0.22 }), costNode },
			}),
		}, { mb = 0 })
	end

	local function heroCard(hero)
		local o = s.heroes.owned[hero.id]
		local inCouncil = table.find(s.heroes.council, hero.id) ~= nil
		local rc = C.rarity[hero.rarity] or C.rarity.comum
		local exp = nil
		if o.expedition then
			local left = (o.expedition.endsAt - now) / 1000
			local ex = Util.find(HeroData.EXPEDITIONS, function(x)
				return x.id == o.expedition.id
			end)
			local exName = ex and ex.name or o.expedition.id
			if left <= 0 then
				exp = M(U.btn({
					small = true, variant = "primary", icon = "check", text = "Coletar: " .. exName,
					onClick = Ctx.does("collect", hero.id),
				}), 0, 0)
			else
				exp = row({
					inl({ U.ico("expedition", T.c.text, rem(1.25)), U.text(exName .. " · " .. fmtTime(left)) }, rem(0.25)),
					U.btn({
						small = true, icon = "speedup", text = "Acelerar", onClick = Ctx.does("speedup", hero.id),
						children = gemsCost(HeroCore.expeditionSpeedUpCost(left), fsSmall),
					}),
				}, { mb = 0 })
			end
		elseif not inCouncil and not o.training then
			local full = active >= expSlots
			local btns = {}
			for _, x in HeroData.EXPEDITIONS do
				table.insert(btns, U.btn({
					key = x.id, small = true, poor = full, icon = "expedition", text = fmtTime(x.duration),
					tip = full and "Todas as vagas de expedição estão ocupadas" or x.name,
					onClick = Ctx.does("expedition", hero.id .. "|" .. x.id),
				}))
			end
			exp = {
				M(box(nil, {
					Kit.list("x", { justify = "between", align = "center" }),
					U.text(upper("Enviar em expedição"), { bold = true, size = 0.72, color = T.c.muted }),
					U.text(upper(active .. "/" .. expSlots .. " vagas"), { bold = true, size = 0.72, color = T.c.muted }),
				}), 0.6, 0.2),
				row(btns, { mb = 0 }),
			}
		end

		local rarName = upper(HeroData.RARITIES[hero.rarity].name)
		local info = box({ Size = UDim2.new(1, -(56 + rem(0.6)), 0, 0) }, {
			Kit.list("y", { gap = 0 }),
			stack({
				U.row({ gap = 0 }, {
					U.text(rarName, { bold = true, size = 0.66, color = rc }),
					inCouncil and h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
						Kit.pad(0, 0, 0, rem(0.3)),
						h("Frame", { BackgroundColor3 = mix(T.c.good, T.c.white, 0.12), AutomaticSize = AXY, Size = UDim2.new() }, {
							Kit.corner(99),
							Kit.pad(rem(0.1), rem(0.45)),
							U.text("NO CONSELHO", { bold = true, size = 0.66, color = T.c.good }),
						}),
					}) or nil,
				}),
				U.row({ gap = rem(0.3), wrap = true }, {
					U.text(hero.name, { bold = true, size = 1, lineHeight = 1.45 }),
					stars(o.stars),
				}),
				para(string.format("Nível %d · Poder %s · %s", o.level or 1, tostring(Economy.heroPowerOf(hero, o)),
					Side.describeBonus(hero.bonus.type, hero.bonus.value * Economy.heroStrength(o))), { size = 0.8, muted = true }),
				M(para(esc(hero.lore), { size = 0.78, muted = true, props = { FontFace = Font.new(T.font.Family, Enum.FontWeight.Regular, Enum.FontStyle.Italic) } }), 0.1, 0),
				not o.expedition and row({
					U.btn({
						small = true, on = inCouncil, text = inCouncil and "Tirar do Conselho" or "Pôr no Conselho",
						onClick = Ctx.does("council", hero.id),
					}),
				}, { mb = 0 }) or nil,
				exp,
				trainBlock(hero, o),
			}),
		})

		-- .hero: degradê da raridade, borda esquerda de 5px
		return M(h("Frame", {
			key = "h-" .. hero.id,
			BackgroundColor3 = mix(rc, T.c.line, 0.3),
			AutomaticSize = AY,
			Size = UDim2.fromScale(1, 0),
		}, {
			Kit.corner(T.r),
			h("Frame", { BackgroundColor3 = rc, Size = UDim2.new(0, 17, 1, 0) }, { Kit.corner(T.r) }),
			h("Frame", {
				BackgroundColor3 = T.c.white,
				Position = UDim2.fromOffset(5, 1),
				Size = UDim2.new(1, -6, 1, -2),
			}, {
				Kit.corner(T.r - 1),
				h("UIGradient", {
					Rotation = 0,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, mix(rc, T.c.white, 0.09)),
						ColorSequenceKeypoint.new(0.6, T.c.white),
						ColorSequenceKeypoint.new(1, T.c.white),
					}),
				}),
			}),
			box({ ZIndex = 2 }, {
				Kit.pad(rem(0.6) + 1, rem(0.6) + 1, rem(0.6) + 1, rem(0.6) + 5),
				Kit.list("x", { gap = rem(0.6), align = "start" }),
				-- .portrait
				h("Frame", { BackgroundColor3 = T.c.white, Size = UDim2.fromOffset(56, 56) }, {
					Kit.corner(12),
					Kit.grad({ T.c.white, mix(rc, T.c.white, 0.22) }, 90),
					h("UIStroke", { Color = rc, Thickness = 2, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
					U.ico(HERO_ICON[hero.id] or "info", rc, 40, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }),
				}),
				info,
			}),
		}), 0.5, 0.5)
	end

	local heroNodes = {}
	for _, hero in owned do
		table.insert(heroNodes, heroCard(hero))
	end

	local ghosts = {}
	for _, hero in missing do
		local rc = C.rarity[hero.rarity] or C.rarity.comum
		table.insert(ghosts, h("Frame", {
			key = hero.id,
			BackgroundColor3 = T.c.paper,
			Size = UDim2.fromOffset(34, 34),
			Active = true,
			tip = HeroData.RARITIES[hero.rarity].name .. ", ainda não encontrado",
		}, {
			Kit.corner(9),
			Kit.stroke(mix(rc, T.c.line, 0.5), 1, 0), -- tracejada no web
			U.ico("info", mix(rc, C.grey999, 0.7), rem(1.25), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }),
		}))
	end

	local tavern = HeroCore.tavernDiscount(s)
	local scrolls = s.items.scrolls or 0
	return {
		card("recrutar", {
			h3("scroll", "Recrutar herói"),
			p("Chances: Comum 60%, Raro 28%, Épico 10%, Lendário 2%. Repetidos ganham estrelas. Tudo se ganha jogando.", { muted = true }),
			tavern > 0 and M(icoPara("happiness", T.c.muted, string.format("Taverna nível %d: recrutar com ouro custa %d%% menos.",
				Economy.maxLevelOf(s, "taverna"), Util.round(tavern * 100)), { muted = true }), 0.25, 0.6) or nil,
			row({
				U.btn({
					key = "scroll", variant = scrolls > 0 and "primary" or "grey", poor = scrolls <= 0, icon = "scroll",
					text = "Pergaminho (" .. scrolls .. ")", onClick = Ctx.does("recruit", "scroll"),
				}),
				U.btn({
					key = "gold", poor = s.res.gold < goldCost, icon = "gold", iconColor = T.res.gold, text = fmt(goldCost),
					onClick = Ctx.does("recruit", "gold"),
				}),
				U.btn({
					key = "gems", poor = s.res.gems < HeroData.RECRUIT_GEM_COST, icon = "gems", iconColor = T.res.gems,
					text = tostring(HeroData.RECRUIT_GEM_COST), onClick = Ctx.does("recruit", "gems"),
				}),
			}),
		}),
		card("conselho", {
			h3("tab-heroes", "Conselho", #s.heroes.council .. "/" .. slots .. " vagas"),
			p("Heróis no Conselho dão bônus e defendem o reino de qualquer lado. Heróis fora dele podem partir em expedições (2 de cada vez). Tavernas de nível 5 e 10 abrem uma vaga a mais no Conselho e nas expedições.", { muted = true }),
			M(icoPara("swords", T.c.muted, tSlots > 0
				and string.format("Quartel: treina %d herói%s por vez, até o nível %d. Cada nível dá +10%% de bônus e poder.", tSlots, tSlots > 1 and "s" or "", cap)
				or "Construa um Quartel para treinar heróis.", { muted = true }), 0.25, 0.6),
			#owned > 0 and heroNodes or p("Nenhum herói ainda. Use o pergaminho grátis.", { muted = true }),
			#missing > 0 and {
				M(U.row({ gap = rem(0.35), wrap = true }, ghosts), 0.6, 0),
				p(#missing .. " heróis por descobrir.", { muted = true }),
			} or p("Coleção completa."),
		}),
	}
end

-- ================================================================ aba Temporada
local function kindIcon(r)
	if r.type == "gems" then
		return "gems"
	elseif r.type == "scroll" then
		return "scroll"
	elseif r.type == "boost" then
		return "boost"
	elseif r.type == "goldMinutes" then
		return "gold"
	elseif r.type == "cosmetic" then
		return r.kind == "title" and "trophy" or r.kind == "banner" and "banner" or "emblem-shield"
	end
	return "star"
end

local function tabTemporada(g)
	local s = g.state
	local info = Season.seasonInfo(Ctx.now())
	local tier = Season.tierOf(s.season.xp)
	local into = s.season.xp - tier * Seasons.XP_PER_TIER
	local unclaimed = 0
	for t = 1, tier do
		if not table.find(s.season.claimed, t) then
			unclaimed += 1
		end
	end
	local cols = Ctx.small and 5 or 6
	local gap = rem(0.35)
	local iconS = math.floor(rem(0.72) * 1.25 + 0.5)
	local numH = math.floor(rem(0.72) * 1.45 + 0.5)
	local tierH = rem(0.35) * 2 + numH + rem(0.1) + iconS + 2
	local reduce = Ctx.config.reduceMotion
	local tiles = { Kit.grid(UDim2.new(1 / cols, -gap * (cols - 1) / cols, 0, tierH), gap) }
	for t = 1, Seasons.SEASON_TIERS do
		local r = Season.rewardFor(t, s)
		local claimed = table.find(s.season.claimed, t) ~= nil
		local ready = not claimed and t <= tier
		local special = r.type == "cosmetic"
		local f = claimed and 0.4 or nil
		local function c(col, bg)
			return f and mix(col, bg or T.c.white, f) or col
		end
		local textC = ready and T.c.goldText or T.c.muted
		local iconC = special and C.rarity.epico or textC
		table.insert(tiles, h("Frame", { key = "t" .. t, BackgroundTransparency = 1 }, {
			h("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = ready and T.c.white or c(T.c.paper),
				Size = UDim2.fromScale(1, 1),
				tip = r.label,
				hover = { Position = UDim2.fromOffset(0, -2) },
				onClick = Ctx.does("claimTier", t),
			}, {
				Kit.corner(10),
				ready and Kit.grad({ C.readyA, C.readyB }, 90) or nil,
				h("UIStroke", {
					Color = ready and T.c.gold or c(T.c.line), Thickness = ready and 2 or 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				Kit.pad(rem(0.35), 0),
				Kit.list("y", { gap = rem(0.1), align = "center", justify = "center" }),
				U.text(tostring(t), { bold = true, size = 0.72, color = c(textC), align = CENTER }),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(iconS, iconS) }, {
					U.ico(kindIcon(r), c(iconC), iconS, { ref = animRef("bob"), attrs = { bob = ready and not reduce } }),
				}),
			}),
		}))
	end

	local themeName = info.theme.name
	return {
		card("temporada", {
			h3(THEME_ICON[info.theme.id] or "star", string.format("Temporada %d: %s", info.number, themeName)),
			p(info.theme.desc),
			p("Termina em " .. fmtTime(info.remaining) .. ". A próxima traz outro modificador global.", { muted = true }),
			M(bar(tier >= Seasons.SEASON_TIERS and 1 or into / Seasons.XP_PER_TIER,
				string.format("Nível %d/%d · %s", tier, Seasons.SEASON_TIERS,
					tier >= Seasons.SEASON_TIERS and "máximo" or (into .. "/" .. Seasons.XP_PER_TIER .. " XP")),
				{ kind = "big" }), 0.6, 0.6),
			unclaimed > 0 and U.btn({
				variant = "primary", icon = "check", text = "Resgatar " .. unclaimed .. " recompensa(s)",
				onClick = Ctx.does("claimAllTiers"),
			}) or nil,
		}),
		card("passe", {
			h3("star", "Passe de temporada", "gratuito"),
			box(nil, tiles),
			p("XP vem de construir, melhorar, vencer invasões, expedições, carroças, missões e da recompensa diária.", { muted = true }),
		}),
	}
end

-- ================================================================ aba Legado
local function runHistory(runs)
	if not runs or #runs == 0 then
		return nil
	end
	local items = {}
	local bw = btnW("Ver resumo", { small = true })
	local gap = rem(0.5)
	for i, r in runs do
		local sub = fmtTime(r.duration or 0) .. " · " .. fmt(r.gold or 0) .. " de ouro" .. ((r.newRecords and #r.newRecords > 0) and " · recorde" or "")
		table.insert(items, box({ key = "r" .. i }, {
			Kit.list("y", { gap = 0 }),
			box(nil, {
				Kit.pad(rem(0.4), 0),
				Kit.list("x", { gap = gap, align = "center" }),
				U.text("nº " .. tostring(r.n), { bold = true, color = T.c.muted, Size = UDim2.fromOffset(rem(2.6), 0), AutomaticSize = AY }),
				box({ Size = UDim2.new(1, -(rem(2.6) + bw + gap * 2), 0, 0) }, {
					Kit.list("y", { gap = 0 }),
					inl({ U.b("+" .. fmt(r.crowns or 0)), U.resIco("crowns", rem(1.25)) }, rem(0.25)),
					para(sub, { size = 0.76, muted = true }),
				}),
				U.btn({ small = true, text = "Ver resumo", onClick = Ctx.does("runSummary", i) }),
			}),
			i < #runs and dashed() or nil,
		}))
	end
	return card("rodadas", {
		h3("scroll", "Rodadas anteriores", tostring(#runs)),
		box(nil, { Kit.list("y", { gap = 0 }), items }),
	})
end

local function kpi(label, valueNodes)
	return h("Frame", { BackgroundColor3 = T.c.paper, AutomaticSize = AY, Size = UDim2.new(0.5, -rem(0.25), 0, 0) }, {
		Kit.corner(10),
		Kit.stroke(T.c.line, 1, 0),
		Kit.pad(rem(0.5), rem(0.65)),
		Kit.list("y", { gap = rem(0.2) }),
		U.text(upper(label), { bold = true, size = 0.68, color = T.c.muted, wrap = true }),
		U.row({ gap = rem(0.3), wrap = true, align = "end" }, valueNodes),
	})
end

local function tabLegado(g)
	local s = g.state
	local adv = g:ascendAdvice()
	local bigSize = 1.6
	local hasNext = adv.secondsToNext ~= nil and adv.secondsToNext >= 0
	local advText = adv.recommended and "Recomendado: esta Ascensão pelo menos dobra as Coroas que você já conquistou."
		or (adv.crowns < 1 and ("A primeira Coroa chega com " .. fmt(Talents.CROWN_DIVISOR) .. " de ouro na rodada.")
			or "Ainda não dobra as suas Coroas; esperar rende mais.")
	if hasNext then
		advText ..= " Próxima Coroa em cerca de " .. fmtTime(adv.secondsToNext) .. "."
	end

	local talentRows = {}
	local gap = rem(0.55)
	for i, t in Talents.TALENTS do
		local lvl = s.legacy[t.id] or 0
		local cost = g:talentCost(t.id)
		local right, rightW
		if cost == nil then
			right = U.ico("check", T.c.good, rem(1.25))
			rightW = rem(1.25)
		else
			local can = s.res.crowns >= cost
			right = U.btn({
				small = true, variant = can and "primary" or "grey", poor = not can, icon = "crowns", iconColor = T.res.crowns,
				text = tostring(cost), onClick = Ctx.does("talent", t.id),
			})
			rightW = btnW(tostring(cost), { small = true, icon = true })
		end
		local levelNode
		if t.max <= 10 then
			local pips = {}
			for j = 1, t.max do
				table.insert(pips, h("Frame", { BackgroundColor3 = j <= lvl and C.rarity.lendario or T.c.paper3, Size = UDim2.fromOffset(7, 7) }, {
					Kit.corner(2),
					j > lvl and Kit.stroke(T.c.line, 1, 0) or nil,
				}))
			end
			levelNode = h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
				Kit.pad(0, 0, 0, rem(0.3)),
				U.row({ fill = false, gap = 2 }, pips),
			})
		else
			levelNode = U.text(lvl .. "/" .. t.max, { size = 0.82, color = T.c.muted })
		end
		table.insert(talentRows, box({ key = t.id }, {
			Kit.list("y", { gap = 0 }),
			box(nil, {
				Kit.pad(rem(0.5), 0),
				Kit.list("x", { gap = gap, align = "center" }),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(2.2), rem(1.9)) }, {
					U.ico(TALENT_ICON[t.id] or "crowns", C.rarity.lendario, rem(1.9)),
				}),
				box({ Size = UDim2.new(1, -(rem(2.2) + rightW + gap * 2), 0, 0) }, {
					Kit.list("y", { gap = 0 }),
					U.row({ gap = rem(0.25), wrap = true }, { U.b(t.name, { lineHeight = 1.45 }), levelNode }),
					para(t.desc(math.max(1, lvl)) .. (lvl > 0 and "" or " (no nível 1)"), { size = 0.82 }),
				}),
				right,
			}),
			i < #Talents.TALENTS and dashed() or nil,
		}))
	end

	return {
		card("ascensao", {
			h3("crowns", "Ascensão"),
			p("Recomece o reino num mapa novo com bônus permanentes. Coroas vêm do ouro ganho nesta rodada (" .. fmt(s.stats.runGold) .. ")."),
			M(box(nil, {
				Kit.list("x", { gap = rem(0.5), align = "start", itemFlex = Enum.ItemLineAlignment.Stretch }),
				kpi("Coroas guardadas", { U.text(tostring(s.res.crowns), { bold = true, size = bigSize, color = C.crowns, lineHeight = 1 }) }),
				kpi("Ao ascender agora", {
					U.text("+" .. adv.crowns, { bold = true, size = bigSize, color = adv.crowns >= 1 and T.c.good or T.c.muted, lineHeight = 1 }),
					(g.econ.crownBonus and g.econ.crownBonus > 0) and U.text("templos +" .. Util.round(g.econ.crownBonus * 100) .. "%", { size = 0.82, color = T.c.muted }) or nil,
				}),
			}), 0.5, 0.7),
			p(advText, { color = adv.recommended and T.c.good or T.c.muted }),
			U.btn({
				variant = adv.crowns >= 1 and "primary" or "grey", poor = adv.crowns < 1, icon = "crowns", iconColor = T.res.crowns,
				text = "Ascender", onClick = Ctx.does("ascend"),
			}),
		}),
		card("talentos", {
			h3("emblem-tree", "Árvore de Legado"),
			talentRows,
			p("Herança e Terras Ancestrais valem a partir da próxima Ascensão.", { muted = true }),
		}),
		runHistory(s.runs),
	}
end

-- ================================================================ aba Social
-- Botão das ações do ranking (.rank .ra .btn.small: 4 colunas, fonte .78rem, padding 0 .2rem .3rem).
local function raBtn(o)
	local base = U.sliceProps("ui/grey_button00")
	local pressed = U.sliceProps("ui/grey_button01")
	local transp = o.disabled and 0.55 or 0
	local props = U.merge(base, {
		key = o.key,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ImageColor3 = o.disabled and hex("#b8b8b8") or T.c.white,
		ImageTransparency = transp,
		AutomaticSize = AY,
		Size = UDim2.new(0.25, -math.ceil(rem(0.25) * 3 / 4), 0, rem(1.85)),
		Selectable = not o.disabled,
		onClick = (not o.disabled) and o.onClick or nil,
		tip = o.tip,
	})
	if not o.disabled then
		props.press = pressed
	end
	local kids = {}
	for _, c in o.children do
		table.insert(kids, c)
	end
	return h("ImageButton", props, {
		Kit.pad(8, 8 + rem(0.2), 8 + rem(0.3), 8 + rem(0.2)),
		Kit.sizeLimit(Vector2.new(0, rem(1.85))),
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), AutomaticSize = AY, ClipsDescendants = true }, {
			Kit.list("x", { gap = rem(0.2), justify = "center", align = "center" }),
			kids,
		}),
	})
end

-- .arr: setinha (borda de 2px girada 45°)
local function arrow(color, transp)
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 8) }, {
		h("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -1, 0.5, 0),
			Size = UDim2.fromOffset(6, 6), Rotation = 45,
		}, {
			h("Frame", { BackgroundColor3 = color, BackgroundTransparency = transp, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2) }),
			h("Frame", { BackgroundColor3 = color, BackgroundTransparency = transp, BorderSizePixel = 0, Position = UDim2.new(1, -2, 0, 0), Size = UDim2.new(0, 2, 1, 0) }),
		}),
	})
end

local function tabSocial(g)
	local s = g.state
	local list = g:rivals()
	local key = Util.dayKey(g.now)
	local fs = 0.78
	local is = math.floor(rem(fs) * 1.25 + 0.5)
	local textC = T.c.text
	local items = {}
	local gap = rem(0.45)
	for i, r in list do
		local powerTxt = fmt(r.power)
		local pw = math.ceil(textW(powerTxt, rem(1), true)) + 2
		local rk = C.rank[i] or T.c.muted
		local top = box(nil, {
			Kit.list("x", { gap = gap, align = "center" }),
			U.text(tostring(i), { bold = true, color = rk, align = CENTER, Size = UDim2.fromOffset(rem(1.6), 0), AutomaticSize = AY }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(1.7), 28) }, {
				Kit.list("x", { justify = "center", align = "center" }),
				bannerSm(bannerColor(r.banner), r.emblem),
			}),
			box({ Size = UDim2.new(1, -(rem(1.6) + rem(1.7) + pw + gap * 3), 0, 0) }, {
				Kit.list("y", { gap = 0 }),
				para(esc(r.name), { bold = true, lineHeight = 1.3 }),
				para(esc(r.ruler) .. " · " .. esc(r.title), { size = 0.75, muted = true, lineHeight = 1.3 }),
			}),
			U.text(powerTxt, { bold = true, align = RIGHT, Size = UDim2.fromOffset(pw, 0), AutomaticSize = AY }),
		})
		local ra = nil
		if not r.me then
			local greeted = s.social.greets[r.id] == key
			ra = box(nil, {
				Kit.list("x", { gap = rem(0.25), align = "center" }),
				raBtn({ key = "visit", onClick = Ctx.does("visit", r.id), children = {
					U.ico("visit", textC, is), U.text("Visitar", { bold = true, size = fs }),
				} }),
				raBtn({ key = "greet", disabled = greeted, onClick = Ctx.does("greet", r.id), children = {
					U.ico("greet", textC, is, { ImageTransparency = greeted and 0.55 or 0 }),
					U.text("Saudar", { bold = true, size = fs, transparency = greeted and 0.55 or 0 }),
				} }),
				raBtn({ key = "wood", tip = "Vende 25% da sua madeira por ouro (1 vez por hora)", onClick = Ctx.does("trade", r.id .. "|wood"), children = {
					U.resIco("wood", is), arrow(textC, 0.5), U.resIco("gold", is),
				} }),
				raBtn({ key = "stone", tip = "Vende 25% da sua pedra por ouro (1 vez por hora)", onClick = Ctx.does("trade", r.id .. "|stone"), children = {
					U.resIco("stone", is), arrow(textC, 0.5), U.resIco("gold", is),
				} }),
			})
		end
		table.insert(items, box({ key = "k-" .. tostring(r.id) }, {
			Kit.list("y", { gap = 0 }),
			h("Frame", {
				BackgroundColor3 = T.c.white,
				BackgroundTransparency = r.me and 0 or 1,
				AutomaticSize = AY,
				Size = UDim2.fromScale(1, 0),
			}, {
				r.me and Kit.corner(10) or nil,
				r.me and Kit.grad({ C.readyA, C.meB }, 0) or nil,
				r.me and Kit.stroke(T.c.gold, 1, 0.45) or nil,
				Kit.pad(rem(0.45), rem(0.3)),
				Kit.list("y", { gap = 0 }),
				stack({ top, ra and M(ra, 0.2, 0) or nil }),
			}),
			not r.me and dashed() or nil,
		}))
	end

	local visitW = btnW("Visitar", { icon = true })
	return {
		card("ranking", {
			h3("trophy", "Ranking da região"),
			box(nil, { Kit.list("y", { gap = 0 }), items }),
			p("Poder do Reino soma ouro da vida toda, prédios, heróis, Ascensões e vitórias.", { muted = true }),
		}),
		card("compartilhar", {
			h3("copy", "Compartilhe seu reino"),
			p("Gere um código e mande para amigos: eles veem sua cidade exatamente como está.", { muted = true }),
			U.btn({ variant = "primary", icon = "copy", text = "Copiar código do meu reino", onClick = Ctx.does("copyCode") }),
			U.b("Código de um amigo", { lineHeight = 1.45 }),
			row({
				textInput("friendCode", inputs.friendCode, {
					placeholder = "RB1....",
					size = UDim2.new(1, -(visitW + rem(0.4)), 0, inputH()),
					onText = function(text)
						inputs.friendCode = text
					end,
				}),
				U.btn({
					icon = "visit", text = "Visitar",
					onClick = function()
						Ctx.run("visitCode", inputs.friendCode)
					end,
				}),
			}),
		}),
	}
end

-- ================================================================ aba Perfil
-- .sw: amostra de estandarte/emblema (42x42).
local function swatch(o)
	local f = o.locked and 0.45 or nil
	local function c(col)
		return f and mix(col, T.c.white, f) or col
	end
	local face = o.em and T.c.paper or o.color
	local under = o.em and mix(C.panelLine, T.c.paper, 0.08) or mix(T.c.black, o.color, 0.2)
	local content = {
		h("Frame", { BackgroundColor3 = c(under), Size = UDim2.fromScale(1, 1) }, { Kit.corner(10) }),
		h("Frame", { BackgroundColor3 = c(face), Size = UDim2.new(1, 0, 1, -3) }, { Kit.corner(10) }),
		-- brilho: linear-gradient(180deg, rgba(255,255,255,.2), transparent 60%)
		not o.em and h("Frame", { BackgroundColor3 = T.c.white, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
			Kit.corner(10),
			Kit.grad({ T.c.white, T.c.white }, 90, { { 0, 0.8 }, { 0.6, 1 }, { 1, 1 } }),
		}) or nil,
		o.em and h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
			Kit.corner(10), Kit.stroke(c(T.c.line), 1, 0),
		}) or nil,
		o.icon and U.ico(o.icon, c(o.iconColor), o.iconSize, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3,
		}) or nil,
		o.on and h("Frame", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(-2, -2), Size = UDim2.new(1, 4, 1, 4), ZIndex = 4,
		}, { Kit.corner(12), Kit.stroke(T.c.gold, 3, 0) }) or nil,
		o.price and h("Frame", {
			BackgroundColor3 = T.c.white, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 6),
			AutomaticSize = AXY, Size = UDim2.new(), ZIndex = 5,
		}, {
			Kit.corner(99),
			Kit.pad(0, 4),
			U.text(o.price, { bold = true, size = 0.58, color = T.c.text, ZIndex = 5 }),
		}) or nil,
	}
	local inner
	if o.locked then
		inner = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true, tip = o.tip }, content)
	else
		inner = h("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			hover = { Position = UDim2.fromOffset(-1, -3), Size = UDim2.new(1, 2, 1, 2) },
			tip = o.tip, onClick = o.onClick,
		}, content)
	end
	return h("Frame", { key = o.key, BackgroundTransparency = 1, Size = UDim2.fromOffset(42, 42) }, { inner })
end

local function tabPerfil(g)
	local s = g.state
	local k = s.kingdom
	if k.name ~= lastKName then
		lastKName = k.name
		inputs.kname = k.name
	end
	local main, shadows = {}, {}
	local got = 0
	for _, a in Achievements.ACHIEVEMENTS do
		if a.kind == "shadow" then
			table.insert(shadows, a)
		else
			table.insert(main, a)
			if s.achievements[a.id] then
				got += 1
			end
		end
	end
	local nextA = g:nextAchievement()

	local function ach(a)
		local has = s.achievements[a.id] and true or false
		local hidden = a.kind ~= nil and not has
		local name = hidden and "???" or a.name
		local desc = hidden and ("Dica: " .. (a.hint or "")) or a.desc
		local extra = ""
		if a.gems and a.gems > 0 then
			extra ..= " · " .. a.gems .. " gema" .. (a.gems == 1 and "" or "s")
		end
		if a.title and not hidden then
			extra ..= ' · título "' .. a.title .. '"'
		end
		local f = not has and 0.6 or nil
		local function c(col)
			return f and mix(col, T.c.white, f) or col
		end
		local bgKids = {}
		local bg = c(T.c.paper)
		if has then
			bg = T.c.white
			if a.kind == "shadow" then
				table.insert(bgKids, Kit.grad({ C.shadowA, C.shadowB }, 90))
				table.insert(bgKids, Kit.stroke(C.shadowLine, 1, 0.6))
			else
				table.insert(bgKids, Kit.grad({ C.readyA, C.gotB }, 90))
				table.insert(bgKids, Kit.stroke(T.c.gold, 1, 0.55))
			end
		end
		local iconW = rem(1.9)
		local gap = rem(0.45)
		local props = {
			key = a.id,
			BackgroundColor3 = bg,
			AutomaticSize = AY,
			Size = Ctx.mobile and UDim2.fromScale(1, 0) or UDim2.new(0.5, -math.ceil(rem(0.4) / 2), 0, 0),
		}
		local kids = {
			Kit.corner(10),
			bgKids,
			Kit.pad(rem(0.45)),
			Kit.list("x", { gap = gap, align = "start" }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(iconW, rem(1.7)) }, {
				U.ico(has and a.icon or "lock", has and C.rarity.lendario or c(T.c.muted), rem(1.7)),
			}),
			box({ Size = UDim2.new(1, -(iconW + gap), 0, 0) }, {
				Kit.list("y", { gap = 0 }),
				para(B(esc(name)), { size = 0.8, color = c(T.c.text), lineHeight = 1.35 }),
				para(esc(desc .. extra), { size = 0.7, color = c(T.c.muted), lineHeight = 1.35 }),
			}),
		}
		if has then
			return h("Frame", props, kids)
		end
		props.Text = ""
		props.AutoButtonColor = false
		props.onClick = Ctx.does("achLocked")
		return h("TextButton", props, kids)
	end
	local function achGrid(list)
		local nodes = {}
		for _, a in list do
			table.insert(nodes, ach(a))
		end
		return pairsGrid(nodes, rem(0.4), Ctx.mobile and 1 or 2)
	end

	local banners = {}
	for _, b in Cosmetics.BANNERS do
		local own = g:ownsCosmetic("banner", b.id)
		local color = hex(b.color)
		if not own and b.season then
			table.insert(banners, swatch({
				key = b.id, color = color, locked = true, tip = "Recompensa de temporada",
				icon = "lock", iconColor = T.c.white, iconSize = math.floor(rem(0.65) * 1.25 + 0.5),
			}))
		else
			table.insert(banners, swatch({
				key = b.id, color = color, on = k.banner == b.id, tip = b.name,
				price = (not own and b.price) and (b.price .. " gemas") or nil,
				onClick = Ctx.does(own and "equip" or "buyCosmetic", "banner|" .. b.id),
			}))
		end
	end
	local emblems = {}
	for _, e in Cosmetics.EMBLEMS do
		local own = g:ownsCosmetic("emblem", e.id)
		if not own and e.season then
			table.insert(emblems, swatch({
				key = e.id, em = true, locked = true, tip = "Recompensa de temporada",
				icon = "lock", iconColor = T.c.text, iconSize = math.floor(rem(0.65) * 1.25 + 0.5),
			}))
		else
			table.insert(emblems, swatch({
				key = e.id, em = true, on = k.emblem == e.id,
				icon = EMBLEM_ICON[e.id] or "crowns", iconColor = T.c.text, iconSize = rem(2),
				price = (not own and e.price) and (e.price .. " gemas") or nil,
				onClick = Ctx.does(own and "equip" or "buyCosmetic", "emblem|" .. e.id),
			}))
		end
	end
	local titles = {}
	for _, t in s.cosmetics.titles do
		table.insert(titles, U.btn({ key = t, small = true, on = k.title == t, text = esc(t), onClick = Ctx.does("equip", "title|" .. t) }))
	end

	-- .shop-item: ícone | nome | preço
	local function shopItem(o)
		local f = o.poor and 0.55 or nil
		local function c(col)
			return f and mix(col, T.c.white, f) or col
		end
		local rightW = o.rightW
		local gap = rem(0.45)
		return h("TextButton", {
			key = o.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = c(T.c.paper),
			AutomaticSize = AY,
			Size = UDim2.fromScale(1, 0),
			onClick = o.onClick,
			onEnter = function(inst)
				local st = inst:FindFirstChild("Hover")
				if st then
					st.Enabled = true
				end
			end,
			onLeave = function(inst)
				local st = inst:FindFirstChild("Hover")
				if st then
					st.Enabled = false
				end
			end,
		}, {
			Kit.corner(10),
			h("UIStroke", { Name = "Hover", Color = C.rarity.lendario, Thickness = 2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Kit.pad(rem(0.5), rem(0.6)),
			Kit.list("x", { gap = gap, align = "center" }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rem(1.6), rem(1.03)) }, {
				U.ico(o.icon, c(o.iconColor or T.c.text), rem(1.03)),
			}),
			U.text(o.name, { wrap = true, size = 0.82, color = c(T.c.text), lineHeight = 1.4, Size = UDim2.new(1, -(rem(1.6) + rightW + gap * 2), 0, 0) }),
			h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
				Kit.list("x", { gap = rem(0.25), align = "center" }),
				o.right(c),
			}),
		})
	end
	local fsShop = 0.82
	local gemIco = math.floor(rem(fsShop) * 1.25 + 0.5)
	local shopItems = {}
	for _, it in Shop.GEM_SHOP do
		local poor = s.res.gems < it.gems
		table.insert(shopItems, shopItem({
			key = it.id, icon = it.icon, name = esc(it.name), poor = poor,
			rightW = gemIco + rem(0.25) + math.ceil(textW(tostring(it.gems), rem(fsShop), true)) + 2,
			onClick = Ctx.does("buyShop", it.id),
			right = function(c)
				return {
					U.ico("gems", c(T.res.gems), gemIco),
					U.text(tostring(it.gems), { bold = true, size = fsShop, color = c(T.c.text) }),
				}
			end,
		}))
	end
	local packs = {}
	for _, pk in Shop.GEM_PACKS do
		local priceTxt = Shop.PAYMENTS_ENABLED and pk.price or "Em breve"
		local nameTxt = B(fmt(pk.gems) .. " gemas") .. " " .. esc(pk.name)
		if pk.tag then
			nameTxt ..= " " .. string.format('<mark color="#%s" transparency="0"><font color="#%s" size="%d"> %s </font></mark>',
				C.rarity.lendario:ToHex(), C.tagText:ToHex(), math.floor(rem(0.68) + 0.5), esc(pk.tag))
		end
		table.insert(packs, shopItem({
			key = pk.id, icon = "gems", iconColor = T.res.gems, name = nameTxt,
			rightW = math.ceil(textW(priceTxt, rem(fsShop), true)) + 2,
			-- Pagamento real ainda não existe: o Controller só avisa "em breve" (Shop.PAYMENTS_ENABLED = false).
			onClick = Ctx.does("buyGemPack", pk.id),
			right = function(c)
				return { U.text(esc(priceTxt), { bold = true, size = fsShop, color = c(T.c.text) }) }
			end,
		}))
	end

	local nextBlock = nil
	if nextA then
		local a = nextA.a
		nextBlock = M(h("Frame", { BackgroundColor3 = T.c.paper, AutomaticSize = AY, Size = UDim2.fromScale(1, 0) }, {
			Kit.corner(10),
			Kit.pad(rem(0.5), rem(0.6)),
			Kit.list("y", { gap = rem(0.25) }),
			icoPara(a.icon, T.c.text, "Próxima: " .. B(esc(a.name)) .. " " .. U.color(string.format('<font size="%d">%s</font>', math.floor(rem(0.85) * 0.82 + 0.5), esc(a.desc)), T.c.muted), { size = 0.85 }),
			h("Frame", { BackgroundColor3 = T.c.black, BackgroundTransparency = 0.92, Size = UDim2.new(1, 0, 0, 8), ClipsDescendants = true }, {
				Kit.corner(4),
				h("Frame", { BackgroundColor3 = C.rarity.lendario, Size = UDim2.fromScale(Util.round(nextA.ratio * 100) / 100, 1) }, { Kit.corner(4) }),
			}),
			U.text(fmt(nextA.cur) .. " / " .. fmt(nextA.goal), { size = 0.85 * 0.82, color = T.c.muted }),
		}), 0.4, 0.6)
	end

	local knameW = btnW("Salvar", {})
	local st = s.stats
	return {
		card("identidade", {
			h3("tab-profile", "Identidade"),
			U.b("Nome do reino", { lineHeight = 1.45 }),
			row({
				textInput("kname", inputs.kname or k.name, {
					size = UDim2.new(1, -(knameW + rem(0.4)), 0, inputH()),
					onText = function(text, inst)
						local cut = utf8sub(text, 24)
						if cut ~= text then
							inst.Text = cut
							return
						end
						inputs.kname = text
					end,
				}),
				U.btn({
					text = "Salvar",
					onClick = function()
						Ctx.run("rename", inputs.kname or k.name)
					end,
				}),
			}),
			h4("Estandarte"),
			M(U.row({ gap = rem(0.45), wrap = true }, banners), 0.4, 0.4),
			h4("Emblema"),
			M(U.row({ gap = rem(0.45), wrap = true }, emblems), 0.4, 0.4),
			h4("Título"),
			row(titles),
		}),
		card("conquistas", {
			h3("trophy", "Conquistas " .. got .. "/" .. #main),
			p(string.format("Cada conquista dá +%d%% de produção para sempre. Bônus atual: %s.",
				Util.round(Achievements.ACH_PROD_BONUS * 100),
				B(U.color("+" .. Util.round(got * Achievements.ACH_PROD_BONUS * 100) .. "%", T.c.good))), { muted = true }),
			nextBlock,
			achGrid(main),
			h4("Sombra", "(não contam no total)"),
			achGrid(shadows),
		}),
		card("loja", {
			h3("gems", "Loja de Gemas"),
			p("Você tem " .. B(fmt(s.res.gems)) .. " gemas.", { muted = true }),
			box(nil, { Kit.list("y", { gap = rem(0.35) }), shopItems }),
			h4("Comprar gemas"),
			box(nil, { Kit.list("y", { gap = rem(0.35) }), packs }),
		}),
		card("estatisticas", {
			h3("stats", "Estatísticas"),
			grid2({
				{ "Ouro (vida toda)", fmt(st.totalGold) },
				{ "Construções erguidas", tostring(st.built) },
				{ "Invasões", st.raidsWon .. " vitórias, " .. st.raidsLost .. " derrotas" },
				{ "Expedições", tostring(st.expeditions) },
				{ "Ascensões", tostring(st.ascensions) },
				{ "Tempo de jogo", fmtTime(st.playTime) },
			}),
		}),
		card("jogo", {
			h3("settings", "Jogo"),
			row({
				U.btn({ key = "options", icon = "settings", text = "Opções", onClick = Ctx.does("options") }),
				U.btn({ key = "credits", icon = "info", text = "Créditos", onClick = Ctx.does("credits") }),
				U.btn({ key = "save", icon = "save", text = "Save e backups", onClick = Ctx.does("saveMenu") }),
			}),
		}),
	}
end

local TABS = { reino = tabReino, herois = tabHerois, temporada = tabTemporada, legado = tabLegado, social = tabSocial, perfil = tabPerfil }

-- ================================================================ barra de abas
local function tutorialFocusTab(g)
	local t = g.state.tutorial
	if t.done then
		return nil
	end
	local step = Game.TUTORIAL[t.step + 1]
	return step and step.focus and step.focus.tab or nil
end

local function badges(g)
	local s = g.state
	local tier = Season.tierOf(s.season.xp)
	local claimedUpTo = 0
	for _, t in s.season.claimed do
		if t <= tier then
			claimedUpTo += 1
		end
	end
	local missionReady = false
	if s.season.missions then
		for _, m in s.season.missions.list do
			if not m.claimed and m.progress >= m.target then
				missionReady = true
			end
		end
	end
	local expDone = false
	local now = Ctx.now()
	for _, o in s.heroes.owned do
		if o.expedition and o.expedition.endsAt <= now then
			expDone = true
		end
	end
	return {
		temporada = tier > claimedUpTo,
		reino = missionReady or g:dailyStatus().available,
		herois = expDone or (s.items.scrolls or 0) > 0,
		legado = g:ascendAdvice().recommended,
	}
end

local function tabsNode(g)
	local badge = badges(g)
	local focusTab = tutorialFocusTab(g)
	local tabH = tabsHeight() - rem(0.4) - 1
	local labelSize = Ctx.small and 0.6 or 0.66
	local labelH = math.floor(rem(labelSize) * 1.45 + 0.5)
	local iconS = rem(1.45)
	local reduce = Ctx.config.reduceMotion
	local kids = { Kit.grid(UDim2.new(1 / 6, -math.ceil(10 / 6), 0, tabH), 2, { max = 6 }) }
	for _, entry in TAB_LIST do
		local id, icon = entry[1], entry[2]
		local open = g:isTabUnlocked(id)
		local on = Ctx.ui.tab == id
		local hovered = hoverTab == id and not on
		local f = (not open) and 0.5 or nil
		local base = T.c.paper3
		local function c(col)
			return f and mix(col, base, f) or col
		end
		local color = (on or hovered) and T.c.text or T.c.muted
		local iconC = on and T.c.goldText or color
		local bgC = on and T.c.paper2 or T.c.white
		local bgT = on and 0 or (hovered and 0.55 or 1)
		local showDot = open and (badge[id] or focusTab == id)
		table.insert(kids, h("TextButton", {
			key = id,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			onClick = Ctx.does(open and "tab" or "lockedTab", id),
			onEnter = function()
				if hoverTab ~= id then
					hoverTab = id
					Side.renderTabs()
				end
			end,
			onLeave = function()
				if hoverTab == id then
					hoverTab = nil
					Side.renderTabs()
				end
			end,
		}, {
			-- fundo com só os cantos de cima arredondados (10px)
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), ClipsDescendants = true }, {
				h("Frame", { BackgroundColor3 = bgC, BackgroundTransparency = bgT, Size = UDim2.new(1, 0, 0, 20) }, { Kit.corner(10) }),
			}),
			h("Frame", { BackgroundColor3 = bgC, BackgroundTransparency = bgT, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 1, on and -9 or -10) }),
			-- box-shadow: 0 -2px 0 var(--gold) inset
			on and h("Frame", { BackgroundColor3 = T.c.gold, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), ZIndex = 2 }) or nil,
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, {
				Kit.pad(rem(0.45), 0, rem(0.35), 0),
				Kit.list("y", { gap = rem(0.15), align = "center" }),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(iconS, iconS) }, {
					U.ico(open and icon or "lock", c(iconC), iconS, { Position = UDim2.fromOffset(0, (hovered and open) and -2 or 0) }),
				}),
				U.text(Game.TAB_NAMES[id], {
					bold = true, size = labelSize, color = c(color), align = CENTER, truncate = true,
					AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, labelH),
				}),
			}),
			showDot and h("Frame", {
				BackgroundColor3 = C.dot, Position = UDim2.new(0.82, -9, 0, 5), Size = UDim2.fromOffset(9, 9), ZIndex = 4,
			}, {
				Kit.corner(99),
				Kit.stroke(T.c.paper3, 2, 0),
				not reduce and h("Frame", {
					BackgroundColor3 = C.dot, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1), ZIndex = 4, ref = animRef("ping"),
				}, { Kit.corner(99) }) or nil,
			}) or nil,
		}))
	end
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
		Kit.pad(rem(0.4), rem(0.4), 0, rem(0.4)),
		kids,
	})
end

-- ================================================================ casca (.panel sem o filete dourado)
local function paintShell()
	if not root then
		return
	end
	local tabsH = tabsHeight()
	paper.BackgroundColor3 = T.c.white
	paper:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(T.c.paper2, T.c.paper)
	local st = paper:FindFirstChildOfClass("UIStroke")
	st.Color = C.panelLine
	tabsBar.Size = UDim2.new(1, 0, 0, tabsH)
	for _, f in { tabsTop, tabsFill } do
		f:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(T.c.paper3, C.tabsBottom)
	end
	tabsTop.Size = UDim2.new(1, 0, 0, tabsH)
	tabsFill.Position = UDim2.fromOffset(0, T.rLg)
	tabsFill.Size = UDim2.new(1, 0, 1, -T.rLg)
	-- o degradê do pedaço de baixo continua o de cima
	local frac = T.rLg / math.max(1, tabsH)
	tabsFill:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(T.c.paper3:Lerp(C.tabsBottom, frac), C.tabsBottom)
	tabsLine.BackgroundColor3 = T.c.line
	bodyBg.Position = UDim2.fromOffset(0, tabsH)
	bodyBg.Size = UDim2.new(1, 0, 1, -tabsH)
	bodyBg.BackgroundColor3 = T.c.paper2
	bodyFill.BackgroundColor3 = T.c.paper2
	scroller.Position = UDim2.fromOffset(0, tabsH)
	scroller.Size = UDim2.new(1, 0, 1, -tabsH)
	scroller.ScrollingEnabled = not Ctx.mobile
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

function Side.init(frame)
	root = new("Frame", { Name = "Painel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, frame)
	shadowInst = Kit.mount(U.shadow("md"), root)
	paper = new("Frame", { Name = "Papel", BackgroundColor3 = T.c.white, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, root)
	new("UICorner", { CornerRadius = UDim.new(0, T.rLg) }, paper)
	new("UIGradient", { Rotation = 90 }, paper)
	new("UIStroke", { Thickness = 1, Transparency = 0.82, Color = C.panelLine }, paper)

	tabsBar = new("Frame", { Name = "Abas", BackgroundTransparency = 1, ZIndex = 2 }, root)
	tabsTop = new("Frame", { Name = "Topo", BackgroundColor3 = T.c.white, BorderSizePixel = 0, ZIndex = 2 }, tabsBar)
	new("UICorner", { CornerRadius = UDim.new(0, T.rLg) }, tabsTop)
	new("UIGradient", { Rotation = 90 }, tabsTop)
	tabsFill = new("Frame", { Name = "Base", BackgroundColor3 = T.c.white, BorderSizePixel = 0, ZIndex = 2 }, tabsBar)
	new("UIGradient", { Rotation = 90 }, tabsFill)
	tabsLine = new("Frame", { Name = "Linha", BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3 }, tabsBar)
	tabsHolder = new("Frame", { Name = "Botoes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, tabsBar)

	bodyBg = new("Frame", { Name = "Fundo", BorderSizePixel = 0, ZIndex = 2 }, root)
	new("UICorner", { CornerRadius = UDim.new(0, T.rLg) }, bodyBg)
	bodyFill = new("Frame", { Name = "Topo", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, T.rLg + 2), ZIndex = 2 }, bodyBg)

	scroller = new("ScrollingFrame", {
		Name = "Corpo",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.scroll,
		ScrollBarImageTransparency = 0.65,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, root)
	paintShell()

	RunService.RenderStepped:Connect(function()
		if next(anims) == nil then
			return
		end
		local t = os.clock()
		local reduce = Ctx.config.reduceMotion
		for inst, kind in anims do
			if not inst.Parent then
				anims[inst] = nil
			elseif kind == "ping" then
				-- @keyframes ping { 70%, 100% { transform: scale(2.4); opacity: 0 } }, 1.6s ease-out
				local q = math.min(1, ((t % 1.6) / 1.6) / 0.7)
				local e = 1 - (1 - q) ^ 2
				local sc = 1 + 1.4 * e
				local g = inst :: Frame
				g.Visible = not reduce
				g.Size = UDim2.fromScale(sc, sc)
				g.BackgroundTransparency = e
			elseif kind == "bob" then
				-- @keyframes bob { 50% { transform: translateY(-8px) } }, 1.4s ease-in-out
				local ph = (t % 1.4) / 1.4
				local on = not reduce and inst:GetAttribute("bob") == true
				local y = on and -8 * (1 - math.cos(ph * 2 * math.pi)) / 2 or 0
				(inst :: GuiObject).Position = UDim2.fromOffset(0, math.floor(y + 0.5))
			end
		end
	end)
end

function Side.renderTabs()
	local g = Ctx.game
	if not root or not g then
		return
	end
	Kit.render(tabsHolder, tabsNode(g))
end

local function inputFocused()
	local tb = UserInputService:GetFocusedTextBox()
	return tb ~= nil and root ~= nil and tb:IsDescendantOf(root)
end

function Side.render(force)
	if not root then
		return
	end
	local g = Ctx.game
	if not g then
		Kit.render(tabsHolder, nil)
		Kit.render(scroller, nil)
		return
	end
	if not force and (inputFocused() or Ctx.ui.pointerHeld) then
		return
	end
	if not g:isTabUnlocked(Ctx.ui.tab) or not TABS[Ctx.ui.tab] then
		Ctx.ui.tab = "reino"
	end
	local tab = Ctx.ui.tab
	paintShell()
	Side.renderTabs()
	local cards = TABS[tab](g)
	Kit.render(scroller, h("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = AY,
		Size = UDim2.fromScale(1, 0),
		onSize = function(inst)
			local hgt = tabsHeight() + inst.AbsoluteSize.Y + 2
			if math.abs(hgt - contentH) >= 1 then
				contentH = hgt
				local frame = root and root.Parent
				if frame then
					frame:SetAttribute("contentH", hgt)
				end
				if Ctx.mobile then
					Ctx.relayout()
				end
			end
		end,
	}, {
		Kit.pad(rem(0.75), rem(0.75), rem(0.75) + rem(0.7), rem(0.75)),
		Kit.list("y", { gap = rem(0.7) }),
		h("Frame", { key = "tab-" .. tab, BackgroundTransparency = 1, AutomaticSize = AY, Size = UDim2.fromScale(1, 0) }, {
			Kit.list("y", { gap = rem(0.7) }),
			cards,
		}),
	}))
	if tab ~= lastTab then
		scroller.CanvasPosition = Vector2.zero
		lastTab = tab
	end
end

return Side
