-- Conteúdo do painel do tile (renderTileInfo/underTileHtml/outputLines de src/ui/panels.js).
-- Só monta os nós; o Stage cuida da caixa (posição, rolagem, animação de entrada).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)
local Assets = require(script.Parent.Assets)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Economy = require(Reino.Core.Economy)
local Map = require(Reino.Core.Map)
local Game = require(Reino.Core.Game)
local Under = require(Reino.Core.Underground)
local Buildings = require(Reino.Data.Buildings)
local UnderData = require(Reino.Data.Underground)

local h = Kit.h
local rem = T.rem
local hex = T.hex
local AXY, AY = Enum.AutomaticSize.XY, Enum.AutomaticSize.Y
local fmt, fmtRate, fmtPct, fmtTime = Util.fmt, Util.fmtRate, Util.fmtPct, Util.fmtTime
local BUILDINGS, TERRAIN = Buildings.BUILDINGS, Buildings.TERRAIN
local UNDER_TILES, ROOMS, ROOM_ORDER, LEVEL_NAMES = UnderData.UNDER_TILES, UnderData.ROOMS, UnderData.ROOM_ORDER, UnderData.LEVEL_NAMES
local idx = Map.idx
local DIR_NAMES = Game.DIR_NAMES
local PROD_RES = { "gold", "food", "wood", "stone", "gems" }

local TileInfo = {}

local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end
local function lower(s)
	s = string.lower(s)
	for a, b in ACC do
		s = string.gsub(s, b, a)
	end
	return s
end
local esc = U.esc

-- Miniaturas (sprites.js): prédios, terreno, subsolo, salas e ruína.
local TERRAIN_ICON = {
	grass = "grass-1", forest = "icon-forest-1", sapling = "icon-sapling-1", rock = "icon-rock-1", water = "water-1", mountain = "icon-mountain-1",
}
local UNDER_ICON = {
	rock = "u-rock-1", gold = "u-gold", gem = "u-gem", water = "u-water", magma = "u-magma", floor = "u-floor-1", cavern = "u-cavern-1",
}

-- ------------------------------------------------------------ peças
-- Bloco com margens verticais (as margens do CSS; entre irmãos vale a maior, como no colapso de margens).
local function blk(node, mt, mb)
	return { node = node, mt = mt or 0, mb = mb or 0 }
end

-- p { margin: .25rem 0 .6rem }
local function para(text, muted)
	return blk(U.text(text, { wrap = true, color = muted and T.c.muted or T.c.text, LineHeight = 1.08 }), rem(0.25), rem(0.6))
end

-- .warn { margin: .45rem 0 }
local function warnBox(text)
	return blk(U.warn(text), rem(0.45), rem(0.45))
end

local function divider()
	return blk(U.divider(), rem(0.6), rem(0.6))
end

-- .lbl: rótulo em caixa alta com valor à direita.
local function lbl(left, right, rightColor)
	return blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("x", { justify = "between", align = "center" }),
		U.b(upper(left), { size = 0.72, color = T.c.muted }),
		right and U.b(upper(right), { size = 0.72, color = rightColor or T.c.muted }) or nil,
	}), rem(0.6), rem(0.2))
end

-- .stats: pílulas brancas. lines = { { icon = node, text = "..." } }
local function stats(lines, emptyText)
	local kids = {}
	for i, l in lines do
		table.insert(kids, h("Frame", {
			key = "s" .. i, BackgroundColor3 = T.c.white, AutomaticSize = AXY, Size = UDim2.new(),
		}, {
			Kit.corner(99),
			Kit.stroke(T.c.line, 1, 0),
			Kit.pad(rem(0.12), rem(0.55)),
			Kit.list("x", { gap = rem(0.25), align = "center" }),
			l.icon,
			U.text(l.text, { size = 0.82 }),
		}))
	end
	if #kids == 0 and emptyText then
		table.insert(kids, h("Frame", { BackgroundColor3 = T.c.white, AutomaticSize = AXY, Size = UDim2.new() }, {
			Kit.corner(99),
			Kit.stroke(T.c.line, 1, 0),
			Kit.pad(rem(0.12), rem(0.55)),
			U.text(emptyText, { size = 0.82, color = T.c.muted }),
		}))
	end
	return blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("x", { gap = rem(0.3), wrap = true, align = "center" }),
		kids,
	}), rem(0.5), rem(0.5))
end

-- ul.adj: pílulas verdes/vermelhas; items = { { text, kind = "pos"|"neg"|"muted" } }
local function adjList(items)
	local kids = {}
	for i, it in items do
		local bg = it.kind == "neg" and hex("#b8412f") or hex("#23803d")
		local color = it.kind == "neg" and T.c.bad or it.kind == "pos" and T.c.good or it.kind == "muted" and T.c.muted or T.c.text
		table.insert(kids, h("Frame", {
			key = "a" .. i, BackgroundColor3 = bg, BackgroundTransparency = it.kind == "muted" and 1 or 0.9,
			AutomaticSize = AXY, Size = UDim2.new(),
		}, {
			Kit.corner(99),
			Kit.pad(rem(0.1), rem(0.5), rem(0.1), it.kind == "muted" and 0 or rem(0.5)),
			U.text(it.text, { size = 0.84, color = color }),
		}))
	end
	return blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("x", { gap = rem(0.3), wrap = true, align = "center" }),
		kids,
	}), 0, rem(0.6))
end

-- .row { display: flex; gap: .4rem; flex-wrap: wrap; margin: .4rem 0 }
local function row(children)
	return blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("x", { gap = rem(0.4), wrap = true, align = "center" }),
		children,
	}), rem(0.4), rem(0.4))
end

-- Custo dentro de botão (costHtml): ícones + números; vermelho no que falta.
local function cost(c, res, size, color)
	return U.cost(c, res, { size = size, bold = true, fmt = fmt, color = color })
end
local BTN_TEXT = { grey = hex("#2b2a33"), primary = hex("#3b2a00"), danger = hex("#ffffff") }

-- Botão com ação do ACTIONS (data-action/data-arg).
local function btn(o)
	local variant = o.variant or "grey"
	local color = BTN_TEXT[variant] or BTN_TEXT.grey
	local extra = {}
	if o.cost then
		table.insert(extra, cost(o.cost, o.res, o.small and 0.85 or 0.95, color))
	end
	if o.after then
		table.insert(extra, U.text(o.after, { bold = true, size = o.small and 0.85 or 0.95, color = color }))
	end
	if o.yield then
		table.insert(extra, cost(o.yield, nil, o.small and 0.85 or 0.95, color))
	end
	return U.btn({
		key = o.key, text = o.text, icon = o.icon, variant = variant, small = o.small, poor = o.poor, iconOnly = o.iconOnly,
		tip = o.tip, width = o.width, justify = o.justify, wrap = o.wrap,
		onClick = function()
			Ctx.run(o.action, o.arg)
		end,
		children = #extra > 0 and extra or nil,
	})
end

-- .title-row: miniatura (ou ícone) + h3 com a linha pequena em caixa alta.
local function titleRow(image, icon, small, title)
	local pic
	if image then
		pic = h("Frame", { BackgroundColor3 = T.c.paper3, Size = UDim2.fromOffset(52, 52) }, {
			Kit.corner(12),
			Kit.stroke(T.c.line, 1, 0),
			-- radial-gradient(circle, #fff 30%, var(--paper3))
			h("ImageLabel", Assets.with("ui/glow", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageColor3 = T.c.white, ScaleType = Enum.ScaleType.Stretch,
			})),
			U.sprite(image, UDim2.new(1, -8, 1, -8), { Position = UDim2.fromOffset(4, 4), ZIndex = 2 }),
		})
	else
		pic = h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52) }, {
			U.ico(icon, T.c.muted, 40, { Position = UDim2.fromOffset(6, 6) }),
		})
	end
	return blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(0, rem(2.6), 0, 0),
		Kit.list("x", { gap = rem(0.6), align = "center" }),
		pic,
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -(52 + rem(0.6)), 0, 0), AutomaticSize = AY }, {
			Kit.list("y", { gap = 0 }),
			small and U.b(upper(small), { size = 0.72, color = T.c.muted, wrap = true }) or nil,
			U.b(esc(title), { size = 1.05, wrap = true, LineHeight = 1.1 }),
		}),
	}), 0, rem(0.2))
end

local function resLine(r, text)
	return { icon = U.resIco(r, math.floor(rem(0.82) * 1.25 + 0.5)), text = text }
end
local function icoLine(name, color, text)
	return { icon = U.ico(name, color or T.c.text, math.floor(rem(0.82) * 1.25 + 0.5)), text = text }
end

-- Valores de um mapa de recursos na ordem do JS (Object.entries segue a ordem de inserção: a de RESOURCE_ORDER).
local function entries(t)
	local out = {}
	if not t then
		return out
	end
	local seen = {}
	for _, r in PROD_RES do
		if t[r] ~= nil then
			table.insert(out, { r, t[r] })
			seen[r] = true
		end
	end
	for r, v in t do
		if not seen[r] then
			table.insert(out, { r, v })
		end
	end
	return out
end

-- ------------------------------------------------------------ prédio da superfície
local function outputLines(g, info, def, x, y)
	local lines = {}
	for _, kv in entries(info.out) do
		table.insert(lines, resLine(kv[1], fmtRate(kv[2])))
	end
	if info.consume and info.consume ~= 0 then
		table.insert(lines, resLine("food", "-" .. fmt(info.consume) .. "/s"))
	end
	if info.defense and info.defense ~= 0 then
		local st = g.state
		local id = st.grid.tiles[idx(x, y)].b.id
		local sideways = id == "muralha" and Economy.wallFacing(Map.wallMask(st.grid, x, y), st.raid.dir) < 1
		table.insert(lines, icoLine("defense", T.res.def, fmt(info.defense) .. " defesa (contra o " .. DIR_NAMES[st.raid.dir] .. ": "
			.. Util.jsNumStr(Util.round(Economy.defenseWeight(st, id, st.raid.dir, x, y) * 100)) .. "%" .. (sideways and ", muralha de lado" or "") .. ")"))
	end
	if def.popCap and def.popCap ~= 0 then
		table.insert(lines, icoLine("people", nil, "+" .. Util.jsNumStr(def.popCap * info.lvl) .. " moradores"))
	end
	if def.happiness and def.happiness ~= 0 then
		table.insert(lines, icoLine("heart", T.res.heart, (def.happiness > 0 and "+" or "") .. fmt(def.happiness * (def.happiness > 0 and info.mult or 1)) .. " felicidade"))
	end
	if def.storage then
		table.insert(lines, icoLine("talent-inheritance", nil, "+" .. fmt(def.storage.gold * Economy.storageMult(info.lvl)) .. " de ouro / +" .. fmt(def.storage.food * Economy.storageMult(info.lvl)) .. " dos demais"))
	end
	if def.crownBonus and def.crownBonus ~= 0 then
		table.insert(lines, resLine("crowns", "+" .. Util.jsNumStr(def.crownBonus * 100) .. "% Coroas"))
	end
	if def.globalGold and def.globalGold ~= 0 then
		table.insert(lines, resLine("gold", "+" .. Util.jsNumStr(def.globalGold * 100) .. "% de ouro global"))
	end
	if info.workers and info.workers ~= 0 then
		table.insert(lines, icoLine("people", nil, Util.jsNumStr(info.workers) .. " trabalhadores"))
	end
	return lines
end

-- deltaText de src/ui/ctx.js
local function deltaText(d)
	if not d then
		return ""
	end
	local parts = {}
	local names = { { "gold", "ouro" }, { "food", "comida" }, { "wood", "madeira" }, { "stone", "pedra" } }
	for _, nr in names do
		local v = d[nr[1]] or 0
		if math.abs(v) >= 0.05 then
			table.insert(parts, (v > 0 and "+" or "") .. fmt(v) .. " " .. nr[2] .. "/s")
		end
	end
	if math.abs(d.defense or 0) >= 0.5 then
		table.insert(parts, (d.defense > 0 and "+" or "") .. fmt(d.defense) .. " defesa")
	end
	if d.popCap and d.popCap ~= 0 then
		table.insert(parts, "+" .. Util.jsNumStr(d.popCap) .. " moradores")
	end
	if math.abs(d.happiness or 0) >= 0.5 then
		table.insert(parts, (d.happiness > 0 and "+" or "") .. fmt(d.happiness) .. " felicidade")
	end
	local s = table.concat(parts, ", ")
	return s ~= "" and s or "sem ganho direto"
end
TileInfo.deltaText = deltaText

local function adjItems(parts, nameOf, allPos)
	local items = {}
	for _, p in parts do
		table.insert(items, { text = nameOf(p.key) .. " " .. fmtPct(p.value), kind = (allPos or p.value > 0) and "pos" or "neg" })
	end
	if #items == 0 then
		items = { { text = "Nenhum vizinho com bônus", kind = "muted" } }
	end
	return items
end

-- ------------------------------------------------------------ subsolo
local function underTile(g, d, x, y)
	local s = g.state
	local lv = s.under.levels[d]
	local t = lv.tiles[idx(x, y)]
	local where = "Nível " .. d .. " · " .. LEVEL_NAMES[d]
	local out = {}
	if not t.s then
		table.insert(out, titleRow(nil, "hero-dwarf", where, "Escuridão"))
		table.insert(out, para("Ninguém sabe o que tem aqui. Cave galerias até chegar perto para descobrir.", true))
		return out
	end
	local kind = UNDER_TILES[t.t]
	local res = s.res
	if t.b then
		local def = ROOMS[t.b.id]
		local levelInfo = g.econ.under and g.econ.under[d]
		local info = levelInfo and levelInfo[idx(x, y)]
		local up = Under.roomUpgradeCost(t.b.id, t.b.lvl, g.econ.mods)
		local lines = {}
		for _, kv in entries(info and info.out) do
			table.insert(lines, resLine(kv[1], fmtRate(kv[2])))
		end
		if def.storage then
			for _, kv in entries(def.storage) do
				table.insert(lines, resLine(kv[1], "+" .. fmt(kv[2] * t.b.lvl * t.b.lvl) .. " de armazém"))
			end
		end
		if def.foodBonus then
			table.insert(lines, resLine("food", "+" .. Util.jsNumStr(Util.round(def.foodBonus * t.b.lvl * 100)) .. "% de comida no reino"))
		end
		if def.prodAll and info and info.active then
			table.insert(lines, icoLine("upgrade", nil, "+" .. Util.jsNumStr(Util.round(def.prodAll * t.b.lvl * 100)) .. "% de toda a produção"))
		end
		table.insert(out, titleRow("icon-room-" .. t.b.id, nil, "Nível " .. t.b.lvl .. " de " .. def.maxLevel .. " · subsolo " .. d, def.name))
		table.insert(out, para(esc(def.desc), true))
		if info and not info.active then
			table.insert(out, warnBox("Precisa estar encostada em " .. lower(UNDER_TILES[def.requiresAdj].name) .. "."))
		end
		table.insert(out, lbl("Produção"))
		table.insert(out, stats(lines))
		if next(def.adj) ~= nil then
			local bonus = info and info.adjBonus or 0
			table.insert(out, lbl("Vizinhos", fmtPct(bonus), bonus > 0 and T.c.good or nil))
			table.insert(out, adjList(adjItems(info and info.adjParts or {}, function(k)
				return (ROOMS[k] and ROOMS[k].name) or (UNDER_TILES[k] and UNDER_TILES[k].name) or "Parede"
			end, true)))
		end
		if up then
			table.insert(out, row({ btn({ key = "roomUp", action = "roomUp", icon = "upgrade", text = "Melhorar", variant = Economy.canAfford(res, up) and "primary" or "grey", poor = not Economy.canAfford(res, up), cost = up, res = res }) }))
		else
			table.insert(out, para("Nível máximo.", true))
		end
		table.insert(out, divider())
		table.insert(out, row({ btn({ key = "roomSell", action = "roomSell", icon = "demolish", text = "Demolir", variant = "danger", small = true }) }))
		return out
	end
	local name = t.st and (t.st == "down" and "Escada para baixo" or "Escada para cima") or kind.name
	table.insert(out, titleRow(UNDER_ICON[t.t], nil, where, name))
	if t.st then
		local to = t.st == "down" and d + 1 or d - 1
		local text
		if t.st == "down" then
			text = "Leva às " .. lower(LEVEL_NAMES[d + 1]) .. "."
		elseif to == 0 then
			text = "Leva de volta à superfície, pela Escadaria."
		else
			text = "Leva às " .. lower(LEVEL_NAMES[to]) .. "."
		end
		table.insert(out, para(text, true))
		table.insert(out, blk(btn({ key = "goLayer", action = "goLayer", arg = to, icon = "move", text = t.st == "down" and "Descer" or "Subir", variant = "primary" })))
		return out
	end
	table.insert(out, para(esc(kind.desc), true))
	if kind.dig then
		local c = Under.digCost(s, d, g.econ.mods)
		if Under.canReach(lv, x, y) then
			local can = Economy.canAfford(res, c)
			table.insert(out, blk(btn({
				key = "dig", action = "dig", icon = "tool-pickaxe", text = "Cavar", variant = can and "primary" or "grey", poor = not can,
				cost = c, res = res, after = ", ganha", yield = Under.digYield(t.t, d),
			})))
		else
			table.insert(out, warnBox("Cave a partir de uma galeria vizinha (de lado, não na diagonal)."))
		end
		return out
	end
	if not kind.open then
		return out
	end
	local rooms = {}
	for _, id in ROOM_ORDER do
		local r = ROOMS[id]
		if r.minDepth <= d and (r.onTile and t.t == r.onTile or (not r.onTile and t.t == "floor")) then
			table.insert(rooms, id)
		end
	end
	if #rooms > 0 then
		table.insert(out, lbl("Construir sala"))
		local btns = {}
		for _, id in rooms do
			local def = ROOMS[id]
			local c = Under.roomCost(s, id, g.econ.mods)
			local adj = Under.roomAdjacency(lv, id, x, y)
			local why = adj.hasRequired and "" or (" (precisa de " .. lower(UNDER_TILES[def.requiresAdj].name) .. " ao lado)")
			local line = "<b>" .. def.name .. "</b>"
			if adj.hasRequired then
				if adj.total ~= 0 then
					line ..= " " .. U.color("<b>" .. fmtPct(adj.total) .. "</b>", T.c.good)
				end
			else
				line ..= " " .. U.color("<b>sem vizinho certo</b>", T.c.bad)
			end
			local poor = not (adj.hasRequired and Economy.canAfford(s.res, c))
			table.insert(btns, U.btn({
				key = "room-" .. id, small = true, poor = poor, width = UDim.new(1, 0), justify = "start",
				tip = def.desc .. why,
				onClick = function()
					Ctx.run("room", id)
				end,
				children = {
					U.sprite("icon-room-" .. id, 34),
					h("Frame", { BackgroundTransparency = 1, AutomaticSize = AXY, Size = UDim2.new() }, {
						Kit.list("y", { gap = 0 }),
						U.text(line, { bold = true, size = 0.85, color = BTN_TEXT.grey }),
						cost(c, s.res, 0.85, BTN_TEXT.grey),
					}),
				},
			}))
		end
		table.insert(out, blk(h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.list("y", { gap = 6 }),
			btns,
		}), 4, 0))
	elseif t.t == "cavern" and d < 2 then
		table.insert(out, para("Nada para construir aqui.", true))
	end
	local stairs = Under.stairsCost(d)
	if stairs then
		table.insert(out, divider())
		table.insert(out, blk(btn({
			key = "digStairs", action = "digStairs", icon = "tool-pickaxe", text = "Cavar escada para o nível " .. (d + 1), small = true,
			poor = not Economy.canAfford(res, stairs), cost = stairs, res = res,
		})))
	end
	return out
end

-- ------------------------------------------------------------ painel inteiro
-- Devolve a lista de blocos do painel (sem o botão de fechar) para o tile selecionado.
function TileInfo.blocks(g, sel, layer)
	local s = g.state
	local res = s.res
	local tile = s.grid.tiles[idx(sel.x, sel.y)]
	local unlocked = Map.isUnlocked(s.grid, sel.x, sel.y)
	local out = {}
	if layer > 0 then
		return underTile(g, layer, sel.x, sel.y)
	elseif not unlocked then
		local c = g:expandCost()
		local nextRing = Map.ringOf(sel.x, sel.y) == s.grid.ring + 1
		table.insert(out, titleRow(nil, "map", nil, "Terra desconhecida"))
		table.insert(out, para("Expanda o reino para conquistar o próximo anel de terra."))
		if c and nextRing then
			local can = Economy.canAfford(res, c)
			table.insert(out, blk(btn({ key = "expand", action = "expand", icon = "map", text = "Expandir", variant = can and "primary" or "grey", poor = not can, cost = c, res = res })))
		else
			table.insert(out, para("Conquiste os anéis mais próximos primeiro.", true))
		end
	elseif tile.b then
		local def = BUILDINGS[tile.b.id]
		local info = g.econ.tiles[idx(sel.x, sel.y)]
		local up = Economy.upgradeCost(tile.b.id, tile.b.lvl, g.econ.mods)
		local fix = tile.b.dmg and Economy.repairCost(tile.b.id, tile.b.lvl, g.econ.mods) or nil
		local upDelta = (up and not fix) and g:previewUpgrade(sel.x, sel.y) or nil
		local sameType = Economy.countOf(s, tile.b.id)
		local maxLvl = def.maxLevel or Buildings.MAX_LEVEL
		table.insert(out, titleRow("icon-" .. tile.b.id, nil, "Nível " .. tile.b.lvl .. " de " .. maxLvl, def.name))
		table.insert(out, para(esc(def.desc), true))
		if info.damaged then
			table.insert(out, warnBox("Danificada pela horda: não produz nem defende. Conserte antes da próxima derrota ou ela desaba."))
		elseif not info.active then
			table.insert(out, warnBox("Só funciona ao lado de " .. Game.neighborName(def.requiresAdj) .. "."))
		elseif info.workers > 0 and info.staff < 1 then
			table.insert(out, warnBox("Faltam trabalhadores: rendendo " .. Util.jsNumStr(Util.round(info.staff * 100)) .. "%. Construa ou melhore casas."))
		end
		table.insert(out, lbl("Produção"))
		table.insert(out, stats(outputLines(g, info, def, sel.x, sel.y), "Sem produção direta"))
		table.insert(out, lbl("Vizinhos", fmtPct(info.adjBonus), info.adjBonus > 0 and T.c.good or info.adjBonus < 0 and T.c.bad or nil))
		table.insert(out, adjList(adjItems(info.adjParts, function(k)
			return BUILDINGS[k] and BUILDINGS[k].name or TERRAIN[k].name
		end)))
		if tile.b.dmg then
			local can = Economy.canAfford(res, fix)
			table.insert(out, row({ btn({ key = "repair", action = "repair", icon = "build", text = "Consertar", variant = can and "primary" or "grey", poor = not can, cost = fix, res = res }) }))
		elseif up then
			local can = Economy.canAfford(res, up)
			table.insert(out, row({
				btn({ key = "upgrade", action = "upgrade", icon = "upgrade", text = "Melhorar", variant = can and "primary" or "grey", poor = not can, cost = up, res = res }),
				U.b(deltaText(upDelta), { size = 0.8, color = T.c.good }),
			}))
			table.insert(out, row({
				btn({ key = "upgradeMax", action = "upgradeMax", text = "Melhorar ao máximo possível", small = true }),
				sameType > 1 and btn({ key = "upgradeAll", action = "upgradeAll", text = "Melhorar todas as " .. sameType .. " (" .. def.name .. ")", small = true }) or nil,
			}))
		else
			table.insert(out, para("Nível máximo.", true))
		end
		table.insert(out, divider())
		table.insert(out, row({
			btn({ key = "move", action = "move", icon = "move", text = "Mover", small = true }),
			btn({ key = "sell", action = "sell", icon = "demolish", text = "Demolir", variant = "danger", small = true }),
		}))
	else
		local ter = TERRAIN[tile.t]
		if tile.ruin then
			local bname = BUILDINGS[tile.ruin] and BUILDINGS[tile.ruin].name or "Construção"
			table.insert(out, titleRow("icon-ruina", nil, nil, "Ruína"))
			table.insert(out, para(bname .. " destruída por uma horda. Construa algo aqui para limpar o terreno.", true))
		else
			table.insert(out, titleRow(TERRAIN_ICON[tile.t], nil, nil, ter.name))
		end
		if tile.t == "sapling" then
			local left = math.max(0, Buildings.GROW_SECONDS - (Ctx.now() - (tile.p or 0)) / 1000)
			table.insert(out, para("Vira floresta em " .. fmtTime(left) .. ". Floresta dá madeira ao ser limpa e +40% para serrarias vizinhas.", true))
			table.insert(out, blk(btn({ key = "clear", action = "clear", icon = "clear", text = "Arrancar a muda", variant = "danger", small = true })))
		elseif ter.clearCost then
			table.insert(out, para("Pode ser limpo para construir, mas os vizinhos que gostam de " .. lower(ter.name) .. " perdem o bônus.", true))
			table.insert(out, blk(btn({
				key = "clear", action = "clear", icon = "clear", text = "Limpar", poor = not Economy.canAfford(res, ter.clearCost),
				cost = ter.clearCost, res = res, after = ", ganha", yield = ter.clearYield,
			})))
		elseif ter.buildable then
			table.insert(out, para("Terreno livre. Escolha uma construção na paleta, ou plante árvores: em " .. fmtTime(Buildings.GROW_SECONDS) .. " viram floresta.", true))
			table.insert(out, blk(btn({
				key = "plant", action = "plant", icon = "emblem-tree", text = "Plantar árvores", poor = not Economy.canAfford(res, Buildings.PLANT_COST),
				cost = Buildings.PLANT_COST, res = res,
			})))
		else
			table.insert(out, para("Não dá para construir aqui, mas vizinhos podem ganhar bônus com " .. (tile.t == "water" and "a água" or "a montanha") .. ".", true))
		end
	end
	return out
end

-- Junta os blocos com as margens (colapsadas entre irmãos) numa lista de nós.
function TileInfo.stack(blocks)
	local kids = {}
	local prevMb = nil
	for i, b in blocks do
		local gap = prevMb == nil and b.mt or math.max(prevMb, b.mt)
		if gap > 0 then
			table.insert(kids, h("Frame", { key = "gap" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, gap) }))
		end
		local n = b.node
		if n.props.key == nil then
			n.props.key = "b" .. i
		end
		table.insert(kids, n)
		prevMb = b.mb
	end
	if prevMb and prevMb > 0 then
		table.insert(kids, h("Frame", { key = "gapEnd", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, prevMb) }))
	end
	return kids
end

return TileInfo
