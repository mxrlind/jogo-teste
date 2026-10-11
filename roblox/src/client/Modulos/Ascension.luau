-- Tela de estatísticas da Ascensão (porte de src/ui/ascension.js): fecha a rodada com o que foi conquistado
-- e aponta a próxima. Abre sozinha ao ascender e pode ser reaberta pelo histórico na aba Legado.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Buildings = require(Reino.Data.Buildings)
local Talents = require(Reino.Data.Talents)

local h = Kit.h

-- text-transform: uppercase com os acentos do português (string.upper só mexe em ASCII).
local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end
local AY, AXY = Enum.AutomaticSize.Y, Enum.AutomaticSize.XY
local fmt, fmtRate, fmtTime = Util.fmt, Util.fmtRate, Util.fmtTime

local A = {}

local COUNT_MS = 1.1
-- O Data/Talents.luau não tem os ícones do web (src/data/talents.js).
local TALENT_ICONS = {
	fartura = "talent-harvest", heranca = "talent-inheritance", muralhas = "talent-walls", vigilia = "talent-vigil",
	engenharia = "talent-engineering", garimpo = "talent-mining", terras = "map", mesa = "talent-round-table",
	mordomo = "talent-butler",
}
A.TALENT_ICONS = TALENT_ICONS

local GOLD_TEXT = T.hex("#8a5d00")

-- ------------------------------------------------------------ números que "contam" até o valor final
local anim = { t0 = 0, counters = {}, crown = nil, crownScale = nil }

local function formatValue(v, kind)
	if kind == "time" then return fmtTime(v) end
	if kind == "rate" then return fmtRate(v) end
	if kind == "pct" then return "+" .. Util.jsNumStr(Util.round(v * 100)) .. "%" end
	return fmt(math.floor(v))
end

local function progress()
	if Ctx.config.reduceMotion then return 1 end
	local p = math.min(1, (os.clock() - anim.t0) / COUNT_MS)
	return 1 - (1 - p) ^ 3
end

-- Rótulo com contagem: wrap(texto) monta o texto final (para o "+N Coroas").
local function count(value, kind, o)
	o = o or {}
	local wrap = o.wrap or function(s) return s end
	local node = U.text(wrap(formatValue(value * progress(), kind)), {
		bold = true, size = o.size or 1.25, color = o.color or T.c.text, align = o.align, lineHeight = o.lineHeight,
		Size = o.Size, AutomaticSize = o.AutomaticSize,
	})
	node.props.ref = function(inst)
		table.insert(anim.counters, { label = inst, value = value, kind = kind, wrap = wrap })
	end
	return node
end

-- ------------------------------------------------------------ peças
local function badge()
	return h("Frame", {
		BackgroundColor3 = T.c.white,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -T.rem(0.45), 0, -T.rem(0.55)),
		Size = UDim2.new(), AutomaticSize = AXY, ZIndex = 3,
	}, {
		Kit.corner(99),
		Kit.grad({ T.c.goldHi, T.c.gold }, 90),
		Kit.pad(T.rem(0.1), T.rem(0.45)),
		U.text("RECORDE", { bold = true, size = 0.6, color = T.hex("#3b2a00") }),
	})
end

-- .as-tile: o fundo/borda fica no Frame de fora (estica na linha); o conteúdo vai num Frame com lista,
-- e o selo "Recorde" (position: absolute) fica fora da lista.
local function tile(rec, label, value, o)
	if value == nil then return nil end
	o = o or {}
	local isRec = o.key and rec[o.key]
	return h("Frame", {
		BackgroundColor3 = T.c.white,
		Size = UDim2.new(),
		AutomaticSize = AY,
	}, {
		Kit.corner(T.r),
		Kit.stroke(isRec and T.c.gold or T.c.line, isRec and 2 or 1, 0),
		isRec and Kit.grad({ T.hex("#fffaf0"), T.hex("#ffffff") }, 90) or nil,
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ZIndex = 2 }, {
			Kit.pad(T.rem(0.55), T.rem(0.6), T.rem(0.5), T.rem(0.6)),
			Kit.list("y", { gap = T.rem(0.15) }),
			U.row({ gap = T.rem(0.25), wrap = false }, {
				o.icon and U.ico(o.icon, GOLD_TEXT, T.rem(1)) or nil,
				U.text(upper(label), { bold = true, size = 0.66, color = T.c.muted, wrap = true, lineHeight = 1.2, Size = UDim2.new(1, -T.rem(1.3), 0, 0), AutomaticSize = AY }),
			}),
			count(value, o.kind or "int"),
			(o.sub and o.sub ~= "") and U.text(o.sub, { size = 0.72, color = T.c.muted, wrap = true }) or nil,
		}),
		isRec and badge() or nil,
	})
end

local function grid(items, cols)
	local gap = T.rem(0.45)
	local list = {}
	for _, it in items do
		if it then
			local p = table.clone(it.props)
			p.Size = UDim2.new(1 / cols, -math.ceil(gap * (cols - 1) / cols) - 1, 0, 0)
			table.insert(list, h(it.class, p, it.children))
		end
	end
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		h("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder, ItemLineAlignment = Enum.ItemLineAlignment.Stretch,
		}),
		list,
	})
end

-- ------------------------------------------------------------ janela
-- summary vem de Game:runSummary(); fresh = acabou de ascender (mostra a chamada para a próxima rodada).
function A.build(summary, fresh)
	anim.counters = {}
	local g = Ctx.game
	local rec = {}
	local nRec = 0
	for _, k in summary.newRecords or {} do
		if not rec[k] then nRec += 1 end
		rec[k] = true
	end
	local cols = (Ctx.vp.X <= 640) and 2 or 4
	local s = summary
	local tiles = {
		tile(rec, "Duração da rodada", s.duration, { kind = "time", icon = "time", sub = s.played ~= nil and (fmtTime(s.played) .. " com o jogo aberto") or "" }),
		tile(rec, "Ouro na rodada", s.gold, { key = "gold", icon = "gold" }),
		tile(rec, "Ouro por segundo no fim", s.goldRate, { kind = "rate", key = "goldRate", icon = "stats" }),
		tile(rec, "Poder do Reino", s.power, { key = "power", icon = "trophy" }),
		tile(rec, "Construções erguidas", s.built, { icon = "build", sub = s.upgrades ~= nil and (fmt(s.upgrades) .. " melhorias") or "" }),
		tile(rec, "Prédios no mapa", s.buildings, { icon = "house", sub = string.format("maior nível %s · anel %s de 5", tostring(s.maxLvl), tostring(s.ring)) }),
		tile(rec, "Hordas vencidas", s.raidsWon, { key = "raidsWon", icon = "swords", sub = s.raidsLost ~= nil and (fmt(s.raidsLost) .. " derrota(s)") or "" }),
		tile(rec, "Expedições", s.expeditions, { icon = "expedition", sub = s.chests ~= nil and (fmt(s.chests) .. " carroça(s) atendida(s)") or "" }),
	}

	local c = s.combo
	local combo = nil
	if c then
		local isRec = rec.combo
		local def = Buildings.BUILDINGS[c.id]
		combo = h("Frame", {
			BackgroundColor3 = T.c.white, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
		}, {
			Kit.corner(T.r),
			Kit.stroke(isRec and T.c.gold or T.c.line, isRec and 2 or 1, 0),
			isRec and Kit.grad({ T.hex("#fffaf0"), T.hex("#ffffff") }, 90) or nil,
			isRec and badge() or nil,
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ZIndex = 2 }, {
			Kit.pad(T.rem(0.5), T.rem(0.7)),
			Kit.list("x", { gap = T.rem(0.7), align = "center" }),
			U.sprite("icon-" .. c.id, 48),
			U.col({ gap = 2, props = { Size = UDim2.new(1, -48 - T.rem(0.7), 0, 0) } }, {
				U.text(upper("Melhor combo da rodada"), { bold = true, size = 0.66, color = T.c.muted }),
				U.row({ gap = T.rem(0.25), wrap = true }, {
					U.text(string.format("<b>%s</b> nível %s:", U.esc(def and def.name or c.id), tostring(c.lvl)), { size = 1 }),
					count(c.bonus, "pct", { size = 1, color = T.c.good }),
					U.text("dos vizinhos", { size = 1 }),
				}),
			}),
			}),
		})
	end

	local nextNodes = nil
	if fresh and g then
		local crowns = g.state.res.crowns
		local affordable = {}
		local cheapest = nil
		for _, t in Talents.TALENTS do
			local cost = g:talentCost(t.id)
			if cost ~= nil then
				if cost <= crowns then table.insert(affordable, t) end
				if not cheapest or cost < cheapest.cost then cheapest = { t = t, cost = cost } end
			end
		end
		local body
		if #affordable > 0 then
			local items = {}
			for i = 1, math.min(4, #affordable) do
				local t = affordable[i]
				table.insert(items, h("Frame", { BackgroundColor3 = T.c.paper, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
					Kit.corner(10),
					Kit.pad(T.rem(0.35), T.rem(0.55)),
					Kit.list("x", { gap = T.rem(0.5), align = "center" }),
					U.ico(TALENT_ICONS[t.id] or "star", T.rarity.lendario, T.rem(1.5)),
					U.text(string.format("<b>%s</b> %s", t.name, U.esc(t.desc((g.state.legacy[t.id] or 0) + 1))), {
						size = 0.85, wrap = true, Size = UDim2.new(1, -T.rem(1.5) - T.rem(4.5), 0, 0), AutomaticSize = AY,
					}),
					U.row({ fill = false, gap = T.rem(0.15) }, {
						U.resIco("crowns", T.rem(1.05)),
						U.b(tostring(g:talentCost(t.id)), { size = 0.85 }),
					}),
				}))
			end
			body = {
				Ctx.modal.p(string.format("Com %d Coroas você já pode comprar:", crowns)),
				U.col({ gap = T.rem(0.3) }, items),
				Ctx.modal.row({
					U.btn({ text = "Gastar Coroas no Legado", icon = "crowns", variant = "primary", onClick = Ctx.does("toLegacy") }),
					U.btn({ text = "Começar o novo reino", onClick = Ctx.does("closeModal") }),
				}),
			}
		else
			body = {
				cheapest and Ctx.modal.p(string.format("Junte %d Coroa(s) a mais para <b>%s</b>.", cheapest.cost - crowns, cheapest.t.name))
					or Ctx.modal.p("A Árvore de Legado está completa."),
				Ctx.modal.row({ U.btn({ text = "Começar o novo reino", variant = "primary", onClick = Ctx.does("closeModal") }) }),
			}
		end
		nextNodes = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.pad(T.rem(0.9), 0, 0, 0),
			Kit.list("y", { gap = T.rem(0.35) }),
			U.divider(),
			Ctx.modal.gap(T.rem(0.4)),
			U.row({ gap = T.rem(0.4), wrap = false }, {
				U.ico("emblem-tree", T.rarity.lendario, T.rem(1.25)),
				U.text("PRÓXIMA RODADA", { bold = true, size = 0.8, color = T.c.muted }),
			}),
			body,
		})
	end

	local heroCol = {
		-- .as-crown: coroa girando ao entrar e flutuando depois.
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(T.rem(3.6), T.rem(3.6)), ref = function(inst)
			anim.crown = inst
		end }, {
			U.resIco("crowns", T.rem(3.6)),
			h("UIScale", {}),
		}),
		U.text(U.esc(upper(string.format("%s nº %s · %s", fresh and "Ascensão" or "Rodada", tostring(s.n), s.name or ""))), {
			bold = true, size = 0.75, color = GOLD_TEXT, align = Enum.TextXAlignment.Center, wrap = true,
		}),
		count(s.crowns or 0, "int", {
			size = 2.6, align = Enum.TextXAlignment.Center,
			wrap = function(v)
				return string.format('+%s <font size="%d" color="#%s">%s</font>', v, T.rem(1.1), T.c.muted:ToHex(), (s.crowns == 1) and "Coroa" or "Coroas")
			end,
		}),
		s.totalCrowns ~= nil and U.text("Coroas guardadas depois desta Ascensão: " .. fmt(s.totalCrowns), {
			size = 0.82, color = T.c.muted, align = Enum.TextXAlignment.Center, wrap = true,
		}) or nil,
		nRec > 0 and h("Frame", { BackgroundColor3 = T.hex("#fff0d6"), Size = UDim2.new(), AutomaticSize = AXY }, {
			Kit.corner(99),
			Kit.stroke(T.hex("#f4cf91"), 1, 0),
			Kit.pad(T.rem(0.15), T.rem(0.7)),
			U.text(string.format("%d %s nesta rodada", nRec, nRec == 1 and "novo recorde" or "novos recordes"), { bold = true, size = 0.78, color = T.hex("#7a3e00") }),
		}) or nil,
	}

	return {
		-- .as-hero: brilho dourado em cima (radial-gradient vira o "ui/glow").
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			U.sprite("ui/glow", UDim2.new(0.9, 0, 0, T.rem(9)), {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), ImageColor3 = T.c.gold,
				ImageTransparency = 0.6, ScaleType = Enum.ScaleType.Stretch, ZIndex = 0,
			}),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ZIndex = 2 }, {
				Kit.pad(T.rem(0.4), 0, T.rem(0.8), 0),
				Kit.list("y", { gap = T.rem(0.2), align = "center" }),
				heroCol,
			}),
		}),
		grid(tiles, cols),
		combo,
		s.built == nil and Ctx.modal.p("Este save é de antes do resumo de rodadas: alguns números não foram registrados.", { muted = true, size = 0.82, center = true }) or nil,
		nextNodes or Ctx.modal.row({
			U.btn({ text = "Fechar", big = true, variant = "primary", width = UDim.new(1, 0), onClick = Ctx.does("closeModal") }),
		}),
	}
end

function A.show(summary, o)
	if type(summary) ~= "table" then return end
	o = o or {}
	local fresh = o.fresh == true
	anim.t0 = os.clock()
	anim.crown = nil
	Ctx.modal.show(function()
		return A.build(summary, fresh)
	end, { wide = true, priority = fresh })
end

-- A cada quadro: contagem dos números e a coroa (spin .8s, depois bob 2,4 s).
function A.frame(_dt)
	if #anim.counters > 0 then
		local e = progress()
		local alive = {}
		for _, c in anim.counters do
			if c.label and c.label.Parent then
				c.label.Text = c.wrap(formatValue(c.value * e, c.kind))
				if e < 1 then table.insert(alive, c) end
			end
		end
		anim.counters = alive
	end
	local cr = anim.crown
	anim.crownScale = cr and cr:FindFirstChildOfClass("UIScale")
	if cr and cr.Parent and anim.crownScale then
		local img = cr:FindFirstChildOfClass("ImageLabel")
		if Ctx.config.reduceMotion then
			anim.crownScale.Scale = 1
			if img then img.Rotation = 0 img.Position = UDim2.new() end
			return
		end
		local t = os.clock() - anim.t0
		if t < 0.8 then
			-- cubic-bezier(.3, 1.5, .5, 1) aproximado pela Back.
			local k = math.clamp(t / 0.8, 0, 1)
			local e = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
			anim.crownScale.Scale = math.max(0, e)
			if img then img.Rotation = -180 * (1 - e) img.Position = UDim2.new() end
		else
			anim.crownScale.Scale = 1
			local b = (t - 0.8) % 2.4 / 2.4
			local y = -8 * (0.5 - 0.5 * math.cos(b * 2 * math.pi))
			if img then img.Rotation = 0 img.Position = UDim2.fromOffset(0, y) end
		end
	end
end

-- Linhas do histórico na aba Legado ficam no painel lateral (runHistoryHtml); aqui só o resumo.
return A
