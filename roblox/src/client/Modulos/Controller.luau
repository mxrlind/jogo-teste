-- Controlador da interface (porte de src/ui/app.js): eventos do jogo -> som, efeitos no mapa e avisos;
-- clique e hover no mapa; modos (construir/mover); teclado remapeável; níveis do subsolo; trilha sonora;
-- visitas a reinos rivais; efeitos ambientes; e as ações de jogo do ACTIONS (data-action) em Ctx.actions.
-- As telas e janelas (menu, opções, saves, diária...) ficam em Screens.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Buildings = require(Reino.Data.Buildings)
local HeroData = require(Reino.Data.Heroes)
local Seasons = require(Reino.Data.Seasons)
local UnderData = require(Reino.Data.Underground)
local Events = require(Reino.Data.Events)
local GameMod = require(Reino.Core.Game)
local Config = require(Reino.Core.Config)
local Economy = require(Reino.Core.Economy)
local Map = require(Reino.Core.Map)
local Util = require(Reino.Core.Util)

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)
local Toasts = require(script.Parent.Toasts)

local h = Kit.h
local hex = T.hex
local fmt = Util.fmt
local ui = Ctx.ui

local BUILDINGS = Buildings.BUILDINGS
local RESOURCES = Buildings.RESOURCES
local DIR_NAMES = GameMod.DIR_NAMES
local TAB_NAMES = GameMod.TAB_NAMES
local GRID_W, GRID_H = Map.GRID_W, Map.GRID_H

-- Ordem fixa para percorrer tabelas de recursos (no JS, Object.entries segue a ordem de inserção).
local RES_ORDER = { "gold", "food", "wood", "stone", "gems", "scrolls", "crowns" }
local function entries(t)
	local out = {}
	if type(t) ~= "table" then
		return out
	end
	local seen = {}
	for _, k in RES_ORDER do
		if t[k] ~= nil then
			table.insert(out, { k, t[k] })
			seen[k] = true
		end
	end
	for k, v in t do
		if not seen[k] then
			table.insert(out, { k, v })
		end
	end
	return out
end

-- Cores dos números flutuantes (RES_COLORS de src/ui/assets.js).
local FLOAT_COLORS = T.float
local C_BURST = hex("#fff3bf")
local C_LEVEL = hex("#ffe08a")

local Controller = {}

-- ================================================================ utilidades
local lastModeExit = 0 -- Esc logo após sair de um modo não deve abrir o menu
local hidden = false -- janela sem foco (document.hidden do web)

-- Efeito no mapa (MapView): chama o método se existir, sem quebrar quando o mapa ainda não está pronto.
local function fx(name, ...)
	local r = Ctx.renderer
	if r and type(r[name]) == "function" then
		local ok, err = pcall(r[name], r, ...)
		if not ok then
			warn("Efeito " .. name .. " falhou: " .. tostring(err))
		end
	end
end

-- O estado da tela fica em Ctx.ui; o MapView também recebe uma cópia (renderer.mode/selected/cursor/layer do web).
local function syncR()
	local r = Ctx.renderer
	if r then
		r.mode = ui.mode
		r.selected = ui.selected
		r.cursor = ui.cursor
		r.layer = ui.layer
	end
end

local function setSelected(v)
	ui.selected = v
	syncR()
end

local function toast(text, kind, icon)
	Ctx.toast(text, kind, icon)
end

local function play(name, vol)
	Ctx.play(name, vol)
end

-- Gatilho de conquista secreta (o servidor só aceita os que nascem na interface).
local function secret(id)
	task.spawn(function()
		Ctx.call("uiSecret", id)
	end)
end

local function sameTile(a, b)
	return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y
end

local function copyXY(t)
	return t and { x = t.x, y = t.y } or nil
end

-- "a|b" (data-arg do web) ou { a, b }.
local function split2(arg)
	if type(arg) == "table" then
		return arg[1], arg[2]
	end
	local a, b = string.match(tostring(arg or ""), "^([^|]*)|(.*)$")
	return a, b
end

-- Texto com no máximo n caracteres (String.slice em UTF-8).
local function utf8Sub(s, n)
	s = tostring(s)
	local ok, len = pcall(utf8.len, s)
	if not ok or not len or len <= n then
		return s
	end
	local cut = utf8.offset(s, n + 1)
	return cut and string.sub(s, 1, cut - 1) or s
end

-- ================================================================ textos do painel (porte de panels.js)
-- hudInfo(key): explicação de cada número do topo (o toque no ícone mostra num aviso).
local function hudInfo(key)
	local g = Ctx.game
	if not g then
		return nil
	end
	local e = g.econ
	local s = g.state
	if key == "gold" then
		return string.format("Ouro paga quase tudo. Vem de casas (impostos), mercados e minas. Limite: %s (armazéns aumentam).", fmt(e.caps.gold))
	elseif key == "food" then
		return string.format("Comida: cada morador come 0,15/s. Sem comida, moradores vão embora e mercados param. Consumo atual: %s/s.", fmt(e.foodConsumption))
	elseif key == "wood" then
		return "Madeira vem das serrarias; cada floresta vizinha dá +40%."
	elseif key == "stone" then
		return "Pedra vem das pedreiras (rochas vizinhas dão +50%). Necessária para defesa e expansão."
	elseif key == "gems" then
		return "Gemas vêm de invasões, carroças, missões, conquistas, passe e expedições, ou da Loja de Gemas (aba Perfil). Compram recursos, impulsos, pergaminhos, aceleram treinos e expedições e liberam cosméticos."
	elseif key == "pop" then
		return string.format("Moradores %d de %s. Os prédios pedem %s trabalhadores. Fazendas e moinhos são ocupados primeiro; com menos gente, os outros prédios rendem menos.",
			math.floor(s.pop), Util.jsNumStr(e.popCap), Util.jsNumStr(e.workersNeeded))
	elseif key == "happiness" then
		return string.format("Felicidade %d: multiplica toda a produção por %.2f. Tavernas, templos e decorações aumentam; pedreiras, minas e superlotação reduzem.",
			math.floor(e.happiness), e.happinessMult)
	elseif key == "raid" then
		return string.format("A próxima horda vem do %s. Torres e muralhas desse lado do mapa contam 100%%; do lado oposto, 50%%. Muralha de lado para a horda conta só metade. Heróis do Conselho sempre contam inteiros. Se a horda vencer, ela danifica construções desse lado (muralhas e torres seguram os golpes primeiro); o que não for consertado até a próxima derrota vira ruína.",
			DIR_NAMES[s.raid.dir] or "")
	elseif key == "event" then
		local ev = s.event and Events.EVENT_BY_ID[s.event.id]
		return ev and (ev.name .. ": " .. ev.desc) or "Nenhum evento agora."
	elseif key == "boost" then
		return "Bênção: +50% em toda a produção enquanto durar."
	end
	return nil
end

-- lockedTabHint(id)
local function lockedTabHint(id)
	for _, rule in GameMod.TAB_UNLOCKS do
		if rule.tab == id then
			return rule.hint
		end
	end
	return ""
end

-- ================================================================ reinos rivais (porte de core/social.js)
-- O Core/Social.luau só tem generateRivals (sem a semente da cidade de cada rival), então rivalGrid,
-- encodeKingdom e decodeKingdom moram aqui, com o mesmo algoritmo do web.
local function rivalSeed(rivalsSeed, i)
	return Util.hashString("rival-" .. Util.jsNumStr(rivalsSeed) .. "-" .. Util.jsNumStr(i))
end

-- Cidade de um rival gerada a partir do poder (quanto mais poder, mais densa e nivelada).
local function rivalGrid(rival)
	local grid = Map.generateMap(rival.seed)
	local rand = Util.mulberry32(bit32.bxor(rival.seed, 0x9e3779b9))
	grid.ring = math.min(5, 2 + math.floor(rival.tier / 2))
	local density = math.min(0.85, 0.3 + rival.tier * 0.07)
	local maxLvl = math.min(10, 1 + rival.tier)
	local choices = Util.filter(Buildings.BUILDING_ORDER, function(id)
		return id ~= "mina" and id ~= "cais"
	end)
	for i, t in grid.tiles do
		local x, y = Map.xy(i)
		if t.t == "grass" and Map.ringOf(x, y) <= grid.ring and not t.b then
			if rand() < density then
				t.b = { id = Util.pick(rand, choices), lvl = Util.randInt(rand, 1, maxLvl) }
			end
		end
	end
	return grid
end

-- ---- Código do Reino ----
local TERRAIN_CODE = { grass = "g", forest = "f", rock = "r", water = "w", mountain = "m", sapling = "s" }
local CODE_TERRAIN = {}
for k, v in TERRAIN_CODE do
	CODE_TERRAIN[v] = k
end
-- Ordem fixa das letras: prédio novo entra no fim, para códigos antigos continuarem válidos.
local CODE_ORDER = {
	"casa", "fazenda", "serraria", "pedreira", "mercado", "moinho", "armazem",
	"taverna", "muralha", "torre", "mina", "templo", "jardim", "fogueira", "estatua", "quartel", "escadaria", "cais",
}
local BUILD_CODE, CODE_BUILD = {}, {}
for i, id in CODE_ORDER do
	local ch = string.char(64 + i)
	BUILD_CODE[id] = ch
	CODE_BUILD[ch] = id
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INV = {}
for i = 1, 64 do
	B64_INV[string.byte(B64, i)] = i - 1
end

-- btoa sobre os bytes UTF-8 (o web faz btoa(unescape(encodeURIComponent(json)))).
local function base64Encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = string.byte(s, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = bit32.rshift(n, 18)
		local c2 = bit32.band(bit32.rshift(n, 12), 63)
		local c3 = bit32.band(bit32.rshift(n, 6), 63)
		local c4 = bit32.band(n, 63)
		table.insert(out, string.sub(B64, c1 + 1, c1 + 1) .. string.sub(B64, c2 + 1, c2 + 1)
			.. (b and string.sub(B64, c3 + 1, c3 + 1) or "=") .. (c and string.sub(B64, c4 + 1, c4 + 1) or "="))
	end
	return table.concat(out)
end

local function base64Decode(s)
	s = string.gsub(s, "%s", "")
	s = string.gsub(s, "=+$", "")
	if #s % 4 == 1 then
		error("Código de reino inválido", 0)
	end
	local out = {}
	local bits, nbits = 0, 0
	for i = 1, #s do
		local v = B64_INV[string.byte(s, i)]
		if v == nil then
			error("Código de reino inválido", 0)
		end
		bits = bits * 64 + v
		nbits += 6
		if nbits >= 8 then
			nbits -= 8
			local byte = math.floor(bits / 2 ^ nbits)
			table.insert(out, string.char(byte))
			bits = bits % 2 ^ nbits
		end
	end
	return table.concat(out)
end

local function encodeKingdom(state, power)
	local cells = {}
	for _, t in state.grid.tiles do
		table.insert(cells, (TERRAIN_CODE[t.t] or "g") .. (t.b and ((BUILD_CODE[t.b.id] or "") .. Util.jsNumStr(t.b.lvl)) or ""))
	end
	local k = state.kingdom
	local payload = { v = 1, n = k.name, b = k.banner, e = k.emblem, t = k.title, r = state.grid.ring, p = power, c = table.concat(cells) }
	return "RB1." .. base64Encode(HttpService:JSONEncode(payload))
end

local function decodeKingdom(code)
	local raw = string.match(tostring(code or ""), "^%s*(.-)%s*$")
	if string.sub(raw, 1, 4) ~= "RB1." then
		error("Código de reino inválido", 0)
	end
	local ok, p = pcall(function()
		return HttpService:JSONDecode(base64Decode(string.sub(raw, 5)))
	end)
	if not ok or type(p) ~= "table" then
		error("Código de reino inválido", 0)
	end
	local c = tostring(p.c or "")
	local tiles = {}
	-- /([gfrwms])([A-Z]\d{1,2})?/g
	local i, n = 1, #c
	while i <= n do
		local ch = string.sub(c, i, i)
		if CODE_TERRAIN[ch] then
			local b = nil
			local nexti = i + 1
			local letter = string.sub(c, i + 1, i + 1)
			if string.match(letter, "^%u$") then
				local digits = string.match(c, "^%d%d?", i + 2)
				if digits then
					local id = CODE_BUILD[letter]
					if id and BUILDINGS[id] then
						b = { id = id, lvl = math.min(10, tonumber(digits) :: number) }
					end
					nexti = i + 2 + #digits
				end
			end
			table.insert(tiles, { t = CODE_TERRAIN[ch], b = b })
			i = nexti
		else
			i += 1
		end
	end
	if #tiles ~= GRID_W * GRID_H then
		error("Código de reino corrompido", 0)
	end
	return {
		name = utf8Sub(p.n, 24), banner = p.b, emblem = p.e, title = utf8Sub(p.t, 30), power = tonumber(p.p) or 0,
		grid = { w = GRID_W, h = GRID_H, ring = math.min(5, tonumber(p.r) or 2), tiles = tiles },
	}
end

Controller.rivalGrid = rivalGrid
Controller.encodeKingdom = encodeKingdom
Controller.decodeKingdom = decodeKingdom

-- ================================================================ janelas (conteúdo para Ctx.modal)
-- <h2>ícone + título</h2> (.sheet > h2:first-of-type: 1.35rem, ícone 1.6rem dourado, espaço do X à direita)
local function h2(iconNode, text)
	return U.row({ gap = T.rem(0.55), pad = Kit.pad(0, T.rem(2.6), T.rem(0.5), 0) }, {
		iconNode,
		U.text(text, { bold = true, size = 1.35, color = T.c.text, wrap = true, Size = UDim2.new(1, -T.rem(2.2), 0, 0) }),
	})
end
local function icoH2(name)
	return U.ico(name, T.c.goldText, T.rem(1.6))
end
local function para(rich, o)
	o = o or {}
	return U.text(rich, { wrap = true, rich = true, color = o.color or T.c.text, size = o.size or 1, lineHeight = 1.25 })
end

local function confirm(nodes, onYes, opts)
	if Ctx.modal and Ctx.modal.confirm then
		Ctx.modal.confirm(nodes, function()
			task.spawn(onYes)
		end, opts)
	else
		task.spawn(onYes)
	end
end

-- Sem área de transferência no Roblox: mostra o texto numa caixa selecionável (o "Copie manualmente" do web).
local function copyText(text)
	if not (Ctx.modal and Ctx.modal.show) then
		return
	end
	local rem = T.rem
	local box = h("TextBox", {
		Name = "Codigo",
		BackgroundColor3 = T.c.white,
		Text = text,
		PlaceholderText = "",
		ClearTextOnFocus = false,
		TextEditable = true, -- precisa ser editável para dar para selecionar; o texto volta se for mexido
		MultiLine = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = T.font,
		TextSize = rem(0.75),
		TextColor3 = T.c.text,
		Size = UDim2.new(1, 0, 0, rem(7)),
		ClipsDescendants = true,
		onText = function(v, inst)
			if v ~= text then
				inst.Text = text
			end
		end,
		ref = function(inst)
			inst.Focused:Connect(function()
				task.defer(function()
					inst.CursorPosition = #text + 1
					inst.SelectionStart = 1
				end)
			end)
		end,
	}, {
		Kit.corner(10),
		Kit.stroke(T.c.line, 2, 0),
		Kit.pad(rem(0.5), rem(0.7)),
	})
	Ctx.modal.show({
		h2(icoH2("copy"), "Copie manualmente"),
		box,
		para("Toque na caixa para selecionar tudo e copie (Ctrl+C no computador; no celular, toque e segure).", { color = T.c.muted, size = 0.9 }),
		U.row({}, { U.btn({ text = "Fechar", onClick = Ctx.does("closeModal") }) }),
	}, "", { priority = true })
end

-- ================================================================ partes da tela
local function renderTileInfo()
	Ctx.invalidate("tileInfo", true)
end
local function renderModeHint()
	Ctx.invalidate("modeHint")
end

-- Igual a result() do web. A falha (som de erro + aviso com o motivo) já vem do Ctx.act.
local function result(res, okMsg)
	if not res or not res.ok then
		return false
	end
	if okMsg then
		toast(okMsg, "good", "check")
	end
	Ctx.invalidate("side", true)
	Ctx.invalidate("hud")
	Ctx.invalidate("tileInfo", true)
	Ctx.invalidate("palette")
	return true
end

-- ================================================================ trilha sonora
-- Folk de taverna na vila; metal quando uma horda se aproxima e nas minas do subsolo.
local function updateMood()
	local g = Ctx.game
	local battle = g ~= nil and not ui.visiting and ((g.state.raid and g.state.raid.warned) or ui.layer > 0)
	Ctx.setMood(battle and "batalha" or "vila")
end

-- ================================================================ modos
local function setMode(mode)
	if mode.type == "select" and (ui.mode and ui.mode.type) ~= "select" then
		lastModeExit = os.clock()
	end
	ui.mode = mode
	syncR()
	ui.hoverDelta = nil
	Ctx.invalidate("palette", true)
	renderModeHint()
end

-- ================================================================ subsolo
local setLayer

-- Botões de nível no canto do mapa (o Stage desenha): aparecem depois da primeira Escadaria.
local function renderLayers()
	local g = Ctx.game
	local reached = g and g.state.under and g.state.under.reached or 0
	ui.layersReached = reached
	if not g or reached < 1 then
		if ui.layer ~= 0 then
			setLayer(0)
		end
	end
	Ctx.invalidate("layers")
end

function setLayer(d)
	if ui.layer == d then
		return
	end
	ui.layer = d
	ui.selected = nil
	ui.cursor = nil
	syncR()
	if d > 0 and ui.mode.type ~= "select" then
		setMode({ type = "select" })
	end
	renderLayers()
	Ctx.invalidate("palette")
	renderTileInfo()
	updateMood()
end

-- ================================================================ visitas
local function startVisit(k)
	setLayer(0)
	ui.visiting = k
	updateMood()
	if Ctx.renderer then
		Ctx.renderer.view = { grid = k.grid }
	end
	setSelected(nil)
	setMode({ type = "select" })
	-- Missão/estatística de visita: conta no servidor (uma vez por reino por dia).
	task.spawn(function()
		Ctx.call("recordVisit", k.id or k.name)
	end)
	Toasts.renderUndo()
	Ctx.invalidate("stage", true)
	renderTileInfo()
end

local function endVisit()
	ui.visiting = nil
	updateMood()
	if Ctx.renderer then
		Ctx.renderer.view = nil
	end
	Ctx.invalidate("stage", true)
end

local function refreshAfterVisit()
	Ctx.invalidate("hud")
	renderTileInfo()
end

local function renderAll()
	endVisit()
	Ctx.invalidate("palette", true)
	Ctx.invalidate("hud")
	Ctx.invalidate("side", true)
	Ctx.invalidate("tileInfo", true)
	renderModeHint()
end

-- ================================================================ mapa: clique e hover
-- Cliques seguidos no mesmo alvo (conquistas secretas). Trocar de alvo ou parar 3 s zera.
local pokeState = { key = nil, n = 0, at = 0 }
local function poke(key)
	local now = os.clock()
	if pokeState.key ~= key or now - pokeState.at > 3 then
		pokeState = { key = key, n = 0, at = now }
	end
	pokeState.n += 1
	pokeState.at = now
	return pokeState.n
end

local function onHover(t)
	local m = ui.mode
	local g = Ctx.game
	ui.hoverDelta = nil
	if t and g and m and m.type == "build" then
		local tile = g:tileAt(t.x, t.y)
		if tile and tile.t == "grass" and not tile.b then
			ui.hoverDelta = g:previewBuild(m.id, t.x, t.y)
		end
	end
	renderModeHint()
end

local function tileClick(x, y)
	if ui.visiting then
		return
	end
	local g = Ctx.game
	if not g then
		return
	end
	if ui.layer > 0 then
		-- Subsolo: o clique só seleciona; cavar e construir ficam no painel do tile.
		play("click", 0.6)
		setSelected(not sameTile(ui.selected, { x = x, y = y }) and { x = x, y = y } or nil)
		renderTileInfo()
		return
	end
	local s = g.state
	local mode = ui.mode
	if s.chest and s.chest.x == x and s.chest.y == y and mode.type == "select" then
		Ctx.actAsync("openChest")
		return
	end
	if mode.type == "build" then
		task.spawn(function()
			local res = Ctx.act("build", mode.id, x, y)
			if not res.ok then
				return
			end
			local g2 = Ctx.game
			if g2 and ui.mode == mode and not Economy.canAfford(g2.state.res, Economy.buildCost(g2.state, mode.id, g2.econ.mods)) then
				setMode({ type = "select" })
			end
			ui.hoverDelta = nil
			Ctx.invalidate("palette")
			renderModeHint()
			Toasts.renderUndo()
		end)
		return
	end
	if mode.type == "move" then
		task.spawn(function()
			local res = Ctx.act("move", mode.from.x, mode.from.y, x, y)
			if not res.ok then
				return
			end
			setSelected({ x = x, y = y })
			setMode({ type = "select" })
			renderTileInfo()
		end)
		return
	end
	play("click", 0.6)
	local tile = g:tileAt(x, y)
	if tile and tile.b and poke(x .. "," .. y) >= 30 then
		secret("poke")
	end
	setSelected(not sameTile(ui.selected, { x = x, y = y }) and { x = x, y = y } or nil)
	renderTileInfo()
end

local function selectBuild(id)
	if ui.visiting then
		endVisit()
		refreshAfterVisit()
	end
	if ui.layer > 0 then
		setLayer(0)
	end
	if ui.mode.type == "build" and ui.mode.id == id then
		setMode({ type = "select" })
	else
		setSelected(nil)
		setMode({ type = "build", id = id })
		renderTileInfo()
	end
	play("click", 0.6)
end

-- ================================================================ efeitos ambientes
local ambientTick = 0
local function ambientFx()
	local g = Ctx.game
	if not g or not Ctx.config.particles or ui.visiting or hidden then
		return
	end
	ambientTick += 1
	if ambientTick % 3 ~= 0 then
		return
	end
	local layer = ui.layer
	local infos
	if layer > 0 then
		infos = g.econ.under and g.econ.under[layer] or {}
	else
		infos = g.econ.tiles or {}
	end
	local producers = {}
	for i, info in infos do
		if type(info) == "table" and info.out then
			for _, v in info.out do
				if v > 0 then
					table.insert(producers, { i, info })
					break
				end
			end
		end
	end
	table.sort(producers, function(a, b)
		return a[1] < b[1]
	end)
	for _ = 1, math.min(3, #producers) do
		local p = producers[math.random(1, #producers)]
		local i, info = p[1], p[2]
		local list = entries(info.out)
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		local top = list[1]
		if top and top[2] > 0 then
			local x, y = Map.xy(i)
			fx("addFloat", x, y, "+" .. fmt(top[2] * 3), hex("#ffffff"), top[1])
		end
	end
end

-- ================================================================ eventos do jogo -> som, efeitos, avisos
-- Resgatar todos os níveis do passe mostra um aviso só (no web, game.quiet calava os toasts de cada nível).
local quietTiers = false

local function wireGame()
	local on = Ctx.on
	on("toast", function(d)
		if quietTiers and type(d.text) == "string" and string.match(d.text, "^Passe nível %d+:") then
			return
		end
		toast(d.text, d.kind, d.icon)
	end)
	on("built", function(d)
		play((d.id == "mina" or d.id == "pedreira") and "mine" or "build")
		fx("pop", d.x, d.y)
		fx("addBurst", d.x, d.y, C_BURST)
		-- A Escadaria não tem desfazer (abre o subsolo).
		if d.id ~= "escadaria" then
			ui.lastBuild = { id = d.id, x = d.x, y = d.y, at = Ctx.now() }
		else
			ui.lastBuild = nil
		end
		Toasts.renderUndo()
	end)
	on("repaired", function(d)
		play("build", 0.8)
		fx("pop", d.x, d.y)
		fx("addBurst", d.x, d.y, C_BURST)
	end)
	on("upgraded", function(d)
		play("upgrade", 0.8)
		fx("pop", d.x, d.y)
		fx("addFloat", d.x, d.y, "Nível " .. tostring(d.lvl), C_LEVEL)
	end)
	on("sold", function(d)
		toast(tostring(d.name) .. " demolida (50% devolvido).", "info", "demolish")
	end)
	on("moved", function(d)
		play("build", 0.6)
		fx("pop", d.tx, d.ty)
	end)
	on("undone", function(d)
		ui.lastBuild = nil
		play("close")
		fx("addBurst", d.x, d.y, hex("#d7dde0"))
		local def = BUILDINGS[d.id]
		toast(string.format("Obra desfeita (%s): custo devolvido por inteiro.", def and def.name or tostring(d.id)), "info", "time")
		Toasts.renderUndo()
	end)
	on("cleared", function(d)
		play("chop")
		for _, kv in entries(d.yieldRes) do
			fx("addFloat", d.x, d.y, "+" .. fmt(kv[2]), FLOAT_COLORS[kv[1]], kv[1])
		end
	end)
	on("planted", function(d)
		play("build", 0.6)
		fx("addBurst", d.x, d.y, hex("#b2f2bb"))
	end)
	on("grown", function(d)
		toast((d.n or 1) > 1 and string.format("%d mudas viraram floresta.", d.n) or "Uma muda virou floresta.", "good", "emblem-tree")
	end)
	on("underOpened", function()
		renderLayers()
		toast("A Escadaria chegou ao subsolo! Use os botões no canto do mapa para descer.", "good", "tool-pickaxe")
	end)
	on("dug", function(d)
		play("mine")
		if ui.layer == d.d then
			fx("addBurst", d.x, d.y, hex("#d7c4a8"))
			for _, kv in entries(d.yieldRes) do
				local c = FLOAT_COLORS[kv[1]] or hex("#7cc6f0")
				fx("addFloat", d.x, d.y, "+" .. fmt(kv[2]), c, kv[1])
			end
		end
		if d.cavern and d.cavern > 0 then
			fx("doShake", 400)
			toast(string.format("Os mineiros romperam uma caverna! %d tiles revelados.", d.cavern), "good", "tool-pickaxe")
		end
	end)
	on("stairs", function(d)
		play("win")
		renderLayers()
		if d.first then
			toast("Nível novo descoberto: " .. tostring(UnderData.LEVEL_NAMES[d.d + 1]) .. ".", "good", "tool-pickaxe")
		end
		setLayer(d.d + 1)
		setSelected({ x = d.x, y = d.y })
		renderTileInfo()
	end)
	on("roomBuilt", function(d)
		play("build")
		fx("popUnder", d.d, d.x, d.y)
		fx("addBurst", d.x, d.y, C_BURST)
	end)
	on("roomUpgraded", function(d)
		play("upgrade", 0.8)
		fx("popUnder", d.d, d.x, d.y)
		fx("addFloat", d.x, d.y, "Nível " .. tostring(d.lvl), C_LEVEL)
	end)
	on("expanded", function(d)
		play("win")
		toast(string.format("Novas terras conquistadas (anel %d).", d.ring), "good", "map")
	end)
	on("raidWarning", function(d)
		play("warn")
		updateMood()
		toast(string.format("%s se aproximam pelo %s! Força %s contra sua defesa %d desse lado.",
			tostring(d.name), DIR_NAMES[d.dir] or "", Util.jsNumStr(d.strength), math.floor(d.defense)),
			d.defense >= d.strength and "info" or "bad", "swords")
	end)
	on("raid", function(res)
		updateMood()
		local g = Ctx.game
		local nextDir = g and DIR_NAMES[g.state.raid.dir] or ""
		if res.win then
			play("win")
			fx("doFlash", hex("#f2b632"))
			toast(string.format("Vitória sobre %s! +%s de ouro e +%s gema(s). A próxima horda vem do %s.",
				tostring(res.name), fmt(res.loot), Util.jsNumStr(res.gems), nextDir), "good", "swords")
			return
		end
		play("lose")
		fx("doShake", 650)
		fx("doFlash", hex("#b8412f"))
		local lostParts = {}
		for _, kv in entries(res.lost) do
			if kv[2] > 0 then
				local name = RESOURCES[kv[1]] and RESOURCES[kv[1]].name or kv[1]
				table.insert(lostParts, fmt(kv[2]) .. " de " .. string.lower(name))
			end
		end
		local lost = table.concat(lostParts, ", ")
		local damaged = res.damaged or {}
		local collapsed = res.collapsed or {}
		local brokeParts = {}
		if #damaged > 0 then
			table.insert(brokeParts, "danificaram " .. (#damaged == 1 and "1 construção" or string.format("%d construções", #damaged)))
		end
		if #collapsed > 0 then
			table.insert(brokeParts, #collapsed == 1 and "1 que não foi consertada desabou" or string.format("%d que não foram consertadas desabaram", #collapsed))
		end
		local broke = table.concat(brokeParts, " e ")
		for _, b in damaged do
			fx("addBurst", b.x, b.y, hex("#ff8f7d"))
		end
		for _, b in collapsed do
			fx("addBurst", b.x, b.y, hex("#8a8a8a"))
		end
		toast(string.format("%s saquearam %s%s%s. A próxima horda vem do %s.",
			tostring(res.name), lost ~= "" and lost or "quase nada", broke ~= "" and (" e " .. broke) or "",
			(res.fraction or 1) < Events.RAID_LOSS_FRACTION and " (proteção de novato)" or "", nextDir), "bad", "warning")
	end)
	on("event", function(ev)
		play("event")
		local def = Events.EVENT_BY_ID[ev.id]
		toast(tostring(ev.name) .. ": " .. tostring(ev.desc), "event", ev.icon or (def and def.icon))
	end)
	on("chest", function()
		play("cart", 0.6)
	end)
	on("chestOpened", function(d)
		play("cart")
		fx("addBurst", d.x, d.y)
		local reward = d.reward or {}
		if reward.boost then
			fx("addFloat", d.x, d.y, string.format("Bênção %s min", Util.jsNumStr(reward.boost)), C_LEVEL, "boost")
		else
			for i, kv in entries(reward) do
				task.delay((i - 1) * 0.2, function()
					fx("addFloat", d.x, d.y, "+" .. fmt(kv[2]), FLOAT_COLORS[kv[1]], kv[1])
				end)
			end
		end
	end)
	on("recruited", function(res)
		if Ctx.show and Ctx.show.recruit then
			Ctx.show.recruit(res)
		end
	end)
	on("expeditionStart", function()
		play("expedition")
	end)
	on("expeditionDone", function(d)
		play("coin")
		local r = d.reward or {}
		local parts = { fmt(r.gold or 0) .. " de ouro", fmt(r.wood or 0) .. " de madeira", fmt(r.stone or 0) .. " de pedra" }
		if r.gems and r.gems > 0 then
			table.insert(parts, Util.jsNumStr(r.gems) .. " gema(s)")
		end
		if r.scrolls and r.scrolls > 0 then
			table.insert(parts, "1 pergaminho")
		end
		local hero = HeroData.HERO_BY_ID[d.hid]
		toast(string.format("Expedição de %s: %s.", hero and hero.name or tostring(d.hid), table.concat(parts, ", ")), "good", "expedition")
	end)
	on("tierUp", function(d)
		play("tier")
		toast(string.format("Passe de temporada: nível %d! Resgate na aba Temporada.", d.tier), "season", "star")
	end)
	on("achievement", function(a)
		play("achievement")
		toast(string.format("Conquista: %s (+%s gema%s%s)", tostring(a.name), Util.jsNumStr(a.gems), a.gems == 1 and "" or "s",
			a.title and string.format(', título "%s"', a.title) or ""), "good", a.icon)
	end)
	on("tutorial", function()
		play("confirm")
		Ctx.invalidate("palette", true)
		Ctx.invalidate("side", true)
	end)
	on("unlock", function(d)
		play("tier")
		toast(string.format("Nova aba aberta: %s.", tostring(d.name)), "season", "star")
		if d.tab == "herois" then
			ui.tab = "herois"
		end
		Ctx.invalidate("side", true)
	end)
	on("offline", function(sum)
		if Ctx.show and Ctx.show.offline then
			Ctx.show.offline(sum)
		end
	end)
	on("background", function(sum)
		if (sum.elapsed or 0) >= 60 then
			toast(string.format("Com a aba em segundo plano (%s): +%s de ouro.", Util.fmtTime(sum.elapsed), fmt(math.max(0, sum.gains and sum.gains.gold or 0))), "info", "time")
		end
	end)
	on("ascended", function(d)
		play("ascend")
		ui.lastBuild = nil
		fx("doFlash", hex("#f2b632"), 1000)
		renderAll()
		if Ctx.show and Ctx.show.runSummary then
			Ctx.show.runSummary(d.summary, { fresh = true })
		end
	end)
end

-- ================================================================ ações (data-action)
local A = {}

local function selXY()
	local s = ui.selected
	if not s then
		return nil
	end
	return s.x, s.y
end

A.info = function(arg)
	local t = hudInfo(arg)
	if t then
		toast(t, "info", "info")
	end
	if arg == "gems" and poke("gems") >= 10 then
		secret("gemPoke")
	end
end
A.achLocked = function()
	secret("curious")
	play("click", 0.6)
end
A.buyShop = function(id)
	local r = Ctx.act("buyShop", id)
	if result(r) then
		play("coin")
		local item = r.item or {}
		toast("Comprado: " .. tostring(item.name or ""), "good", item.icon)
	end
end
A.buyGemPack = function(id)
	if result(Ctx.act("buyGemPack", id)) then
		play("coin")
	end
end

-- paleta e mapa
A.build = function(id)
	selectBuild(id)
end
A.lockedBuilding = function(id)
	local d = BUILDINGS[id]
	if not d then
		return
	end
	toast(string.format("%s: libera com %d construções. %s", d.name, d.unlock.buildings, d.desc), "info", "lock")
end
A.cancelMode = function()
	setMode({ type = "select" })
end
A.upgrade = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("upgrade", x, y))
	end
end
A.repair = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("repair", x, y))
	end
end
A.repairAll = function()
	local res = Ctx.act("repairAll")
	if not res.ok then
		return
	end
	local count, left = res.count or 0, res.left or 0
	toast(left > 0 and string.format("%d consertada(s). Faltam recursos para mais %d.", count, left)
		or count == 1 and "Construção consertada." or string.format("%d construções consertadas.", count), "good", "build")
	result({ ok = true })
end
-- upgradeMax e upgradeAll devolvem um número (o servidor embrulha em { ok = true, value = n }).
local function countOf(r)
	if not r.ok then
		return nil
	end
	return tonumber(r.value) or tonumber(r.n) or 0
end
A.upgradeMax = function()
	local x, y = selXY()
	if not x then
		return
	end
	local n = countOf(Ctx.act("upgradeMax", x, y))
	if n == nil then
		return
	end
	if n == 0 then
		play("error")
		toast("Recursos insuficientes.", "bad", "warning")
		return
	end
	toast(string.format("Subiu %d nível(is).", n), "good", "upgrade")
	result({ ok = true })
end
A.upgradeAll = function()
	local x, y = selXY()
	local g = Ctx.game
	if not x or not g then
		return
	end
	local b = g:tileAt(x, y).b
	if not b then
		return
	end
	local id = b.id
	local n = countOf(Ctx.act("upgradeAll", id))
	if n == nil then
		return
	end
	if n == 0 then
		play("error")
		toast("Recursos insuficientes.", "bad", "warning")
		return
	end
	toast(string.format("%d melhoria(s) em %s.", n, BUILDINGS[id].name), "good", "upgrade")
	result({ ok = true })
end
A.move = function()
	if ui.selected then
		setMode({ type = "move", from = copyXY(ui.selected) })
	end
end
A.undo = function()
	local u = ui.lastBuild
	local res = Ctx.act("undoBuild")
	if res.ok then
		ui.lastBuild = nil
		if u and ui.selected and ui.selected.x == u.x and ui.selected.y == u.y then
			setSelected(nil)
		end
	end
	result(res)
	Toasts.renderUndo()
end
A.sell = function()
	local x, y = selXY()
	if not x then
		return
	end
	local function go()
		result(Ctx.act("sell", x, y))
		setSelected(nil)
		renderTileInfo()
	end
	if not Ctx.config.confirmDemolish then
		go()
		return
	end
	confirm({ h2(icoH2("demolish"), "Demolir?"), para("Você recebe 50% do que gastou de volta.") }, go, { yes = "Demolir", danger = true })
end
A.clear = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("clear", x, y))
	end
end
A.layer = function(arg)
	play("tab", 0.6)
	setLayer(tonumber(arg) or 0)
end
A.dig = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("dig", ui.layer, x, y))
	end
end
A.digStairs = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("digStairs", ui.layer, x, y))
	end
end
A.room = function(id)
	local x, y = selXY()
	if x then
		result(Ctx.act("buildRoom", ui.layer, x, y, id))
	end
end
A.roomUp = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("upgradeRoom", ui.layer, x, y))
	end
end
A.roomSell = function()
	local x, y = selXY()
	if not x then
		return
	end
	local d = ui.layer
	local function go()
		result(Ctx.act("sellRoom", d, x, y))
		renderTileInfo()
	end
	if not Ctx.config.confirmDemolish then
		go()
		return
	end
	confirm({ h2(icoH2("demolish"), "Demolir a sala?"), para("Você recebe 50% do que gastou de volta.") }, go, { yes = "Demolir", danger = true })
end
A.goLayer = function(arg)
	local sel = ui.selected
	setLayer(tonumber(arg) or 0)
	if sel then
		setSelected(copyXY(sel))
	end
	renderTileInfo()
end
A.plant = function()
	local x, y = selXY()
	if x then
		result(Ctx.act("plant", x, y))
	end
end
A.expand = function()
	result(Ctx.act("expand"))
end
A.closeTile = function()
	setSelected(nil)
	renderTileInfo()
end

-- abas
A.tab = function(arg)
	ui.tab = arg
	play("tab", 0.6)
	Ctx.invalidate("side", true)
end
A.lockedTab = function(arg)
	toast(string.format("%s: %s.", TAB_NAMES[arg] or tostring(arg), lockedTabHint(arg)), "info", "lock")
end
A.recruit = function(method)
	result(Ctx.act("recruit", method))
end
A.council = function(hid)
	result(Ctx.act("toggleCouncil", hid))
end
A.expedition = function(arg)
	local hid, eid = split2(arg)
	result(Ctx.act("startExpedition", hid, eid))
end
A.collect = function(hid)
	result(Ctx.act("collectExpedition", hid))
end
A.speedup = function(hid)
	result(Ctx.act("speedUpExpedition", hid))
end
A.train = function(hid)
	if result(Ctx.act("trainHero", hid)) then
		play("upgrade")
	end
end
A.speedupTrain = function(hid)
	result(Ctx.act("speedUpTraining", hid))
end
A.claimTier = function(arg)
	if result(Ctx.act("claimTier", tonumber(arg))) then
		play("coin")
	end
end
A.claimAllTiers = function()
	local g = Ctx.game
	if not g then
		return
	end
	-- Um aviso só no fim (antes eram até 30 toasts seguidos, um por nível).
	local max = math.min(Seasons.SEASON_TIERS, math.floor(g.state.season.xp / Seasons.XP_PER_TIER))
	local claimed = table.clone(g.state.season.claimed)
	local labels = {}
	quietTiers = true
	local ok, err = pcall(function()
		for t = 1, max do
			if not table.find(claimed, t) then
				local r = Ctx.call("claimTier", t)
				if not r.ok and r.reason == "Calma!" then
					-- Limite de 30 ações por segundo do servidor: espera e tenta de novo.
					task.wait(1)
					r = Ctx.call("claimTier", t)
				end
				if r.ok and r.reward then
					table.insert(labels, r.reward.label)
				end
			end
		end
	end)
	-- Os avisos de cada nível chegam junto com o estado; espera um pouco antes de voltar a mostrá-los.
	task.delay(0.5, function()
		quietTiers = false
	end)
	if not ok then
		warn("Resgatar todos falhou: " .. tostring(err))
	end
	if #labels == 0 then
		return
	end
	play("coin")
	toast(string.format("Resgatou %d recompensa(s): %s.", #labels, table.concat(labels, ", ")), "good", "star")
	result({ ok = true })
end
A.claimMission = function(arg)
	if result(Ctx.act("claimMission", tonumber(arg))) then
		play("confirm")
	end
end
A.ascend = function()
	local g = Ctx.game
	if not g then
		return
	end
	local adv = g:ascendAdvice()
	if adv.crowns < 1 then
		play("error")
		toast("Ainda não há Coroas a ganhar.", "bad", "warning")
		return
	end
	local nodes = {
		h2(U.resIco("crowns", T.rem(1.6)), "Ascender?"),
		para(string.format("O reino atual (prédios, recursos, terras) recomeça num mapa novo. Você ganha <b>%s Coroas</b> para a Árvore de Legado.", Util.jsNumStr(adv.crowns))),
		para("Ficam com você: heróis, gemas, Coroas, talentos, temporada, conquistas, cosméticos e estatísticas."),
		(not adv.recommended) and U.warn("Ainda não é o momento recomendado: esta Ascensão não dobra as suas Coroas.") or nil,
	}
	confirm(nodes, function()
		result(Ctx.act("ascend"))
		setSelected(nil)
	end, { yes = "Ascender" })
end
A.toLegacy = function()
	if Ctx.modal and Ctx.modal.close then
		Ctx.modal.close()
	end
	ui.tab = "legado"
	play("tab", 0.6)
	Ctx.invalidate("side", true)
end
A.talent = function(id)
	if result(Ctx.act("buyTalent", id)) then
		play("upgrade")
	end
end
A.greet = function(rid)
	local res = Ctx.act("greetRival", rid)
	if result(res) then
		toast(res.gift and "Eles retribuíram com 1 gema!" or "Saudação enviada (+10 XP).", "good", "greet")
	end
end
A.trade = function(arg)
	local rid, res = split2(arg)
	local out = Ctx.act("tradeRival", rid, res)
	if result(out) then
		play("coin")
		local name = RESOURCES[res] and RESOURCES[res].name or tostring(res)
		toast(string.format("Trocou %s de %s por %s de ouro.", fmt(out.amount), string.lower(name), fmt(out.gold)), "good", "trade")
	end
end
A.visit = function(rid)
	local g = Ctx.game
	if not g then
		return
	end
	local rival = Util.find(g:rivals(), function(x)
		return x.id == rid
	end)
	if not rival or rival.me then
		return
	end
	local seed = rival.seed or rivalSeed(g.state.social.rivalsSeed, rival.tier)
	local grid = rivalGrid({ seed = seed, tier = rival.tier })
	startVisit({ id = rival.id, name = rival.name, title = rival.title, banner = rival.banner, emblem = rival.emblem, power = rival.power, grid = grid })
end
-- No web lê #friendCode; aqui o painel Social passa o texto da caixa como argumento.
A.visitCode = function(code)
	local ok, k = pcall(decodeKingdom, code)
	if ok then
		startVisit(k)
	else
		play("error")
		toast(tostring(k), "bad", "warning")
	end
end
A.copyCode = function()
	local g = Ctx.game
	if not g then
		return
	end
	copyText(encodeKingdom(g.state, Economy.kingdomPower(g.state)))
end
A.endVisit = function()
	endVisit()
end
-- No web lê #kname; aqui o painel passa o nome digitado como argumento.
A.rename = function(name)
	if result(Ctx.act("setKingdomName", name)) then
		toast("Nome atualizado.", "good", "check")
	end
end
A.equip = function(arg)
	local kind, id = split2(arg)
	result(Ctx.act("equip", kind, id))
end
A.buyCosmetic = function(arg)
	local kind, id = split2(arg)
	if result(Ctx.act("buyCosmetic", kind, id)) then
		Ctx.call("equip", kind, id)
		play("coin")
	end
end

-- ================================================================ teclado (remapeável)
-- KeyCode do Roblox -> valor de KeyboardEvent.key do navegador, em minúsculas (as teclas de Core/Config).
local KEY_NAMES = {
	Up = "arrowup", Down = "arrowdown", Left = "arrowleft", Right = "arrowright",
	Return = "enter", KeypadEnter = "enter", Delete = "delete", Backspace = "backspace", Tab = "tab",
	Space = " ", Escape = "escape", Insert = "insert", Home = "home", End = "end", PageUp = "pageup", PageDown = "pagedown",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4",
	KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
	KeypadPeriod = ".", KeypadDivide = "/", KeypadMultiply = "*", KeypadMinus = "-", KeypadPlus = "+", KeypadEquals = "=",
	Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",",
	Period = ".", Slash = "/", BackSlash = "\\", Backquote = "`",
	LeftShift = "shift", RightShift = "shift", LeftControl = "control", RightControl = "control",
	LeftAlt = "alt", RightAlt = "alt", LeftSuper = "meta", RightSuper = "meta", CapsLock = "capslock",
}
local function keyName(keyCode: Enum.KeyCode): string?
	local n = keyCode.Name
	if KEY_NAMES[n] then
		return KEY_NAMES[n]
	end
	if #n == 1 and string.match(n, "%a") then
		return string.lower(n)
	end
	if string.match(n, "^F%d+$") then
		return string.lower(n)
	end
	return nil
end
Controller.keyName = keyName

-- Código Konami: cima, cima, baixo, baixo, esquerda, direita, esquerda, direita, B, A.
local KONAMI = { "arrowup", "arrowup", "arrowdown", "arrowdown", "arrowleft", "arrowright", "arrowleft", "arrowright", "b", "a" }
local konamiPos = 0
local function trackKonami(key)
	if key == KONAMI[konamiPos + 1] then
		konamiPos += 1
	elseif key == KONAMI[1] then
		konamiPos = 1
	else
		konamiPos = 0
	end
	if konamiPos == #KONAMI then
		konamiPos = 0
		if Ctx.game then
			secret("konami")
		end
	end
end

local function modalOpen()
	return Ctx.modal ~= nil and Ctx.modal.isOpen ~= nil and Ctx.modal.isOpen()
end

local function onKey(key)
	-- Remapeamento de teclas (tela de Opções, em Screens): a próxima tecla vai para lá.
	if ui.remapping then
		return
	end
	trackKonami(key)
	local action = Config.actionForKey(Ctx.config, key)
	if action == "menu" then
		if modalOpen() then
			if not Ctx.modal.closable or Ctx.modal.closable() then
				Ctx.modal.close()
			end
			return
		end
		if ui.screen ~= "game" or not Ctx.game then
			return
		end
		if ui.visiting then
			endVisit()
			refreshAfterVisit()
			return
		end
		if ui.mode.type ~= "select" or ui.selected or ui.cursor then
			setMode({ type = "select" })
			ui.selected = nil
			ui.cursor = nil
			syncR()
			renderTileInfo()
			return
		end
		if os.clock() - lastModeExit < 1.5 then
			return
		end
		if Ctx.actions.gameMenu then
			Ctx.run("gameMenu")
		end
		return
	end
	if modalOpen() or ui.screen ~= "game" or not Ctx.game then
		return
	end
	local g = Ctx.game
	local function moveCursor(dx, dy)
		local c = ui.cursor or ui.selected or { x = 5, y = 5 }
		ui.cursor = { x = math.clamp(c.x + dx, 0, GRID_W - 1), y = math.clamp(c.y + dy, 0, GRID_H - 1) }
		syncR()
		onHover(ui.cursor)
	end
	if action == "up" then
		return moveCursor(0, -1)
	elseif action == "down" then
		return moveCursor(0, 1)
	elseif action == "left" then
		return moveCursor(-1, 0)
	elseif action == "right" then
		return moveCursor(1, 0)
	end
	-- No web, Enter só vale com o foco no mapa; aqui o cursor só existe depois de usar as setas.
	if action == "confirm" and ui.cursor then
		local c = ui.cursor
		tileClick(c.x, c.y)
		ui.cursor = c
		syncR()
		return
	end
	if action == "undo" and Toasts.canUndo(Ctx.now()) then
		Ctx.run("undo")
		return
	end
	local selB = ui.layer == 0 and ui.selected and g:tileAt(ui.selected.x, ui.selected.y).b
	if action == "upgrade" and selB then
		return Ctx.run("upgrade")
	end
	if action == "move" and selB then
		return Ctx.run("move")
	end
	if action == "sell" and selB then
		return Ctx.run("sell")
	end
	if action == "nextTab" then
		local open = {}
		for _, t in Ctx.TAB_ORDER do
			if g:isTabUnlocked(t) then
				table.insert(open, t)
			end
		end
		if #open > 0 then
			local i = table.find(open, ui.tab) or 0
			ui.tab = open[i % #open + 1]
			play("tab", 0.6)
			Ctx.invalidate("side", true)
		end
		return
	end
	local n = tonumber(key)
	if n and n >= 1 and n <= 9 and n == math.floor(n) then
		local ids = Util.filter(Buildings.BUILDING_ORDER, function(id)
			return g:isAvailable(id)
		end)
		if ids[n] then
			selectBuild(ids[n])
		end
	end
end

-- ================================================================ início
function Controller.init()
	-- As ações chamam o servidor (Ctx.act espera a resposta): cada uma roda numa thread própria para o
	-- clique não travar. task.spawn começa na hora, então as que só mexem na tela continuam imediatas.
	for name, fn in A do
		Ctx.actions[name] = function(arg)
			task.spawn(fn, arg)
		end
	end
	Ctx.onTileClick = tileClick
	Ctx.onHover = onHover
	Ctx.keyName = keyName
	Ctx.controller = Controller
	wireGame()
	syncR()

	-- Ponteiro pressionado: o painel lateral não se redesenha embaixo do dedo (pointerdown/up do web).
	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			ui.pointerHeld = true
			return
		end
		if t ~= Enum.UserInputType.Keyboard then
			return
		end
		-- Digitando numa caixa de texto (ou no chat do Roblox): o teclado não é do jogo.
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = keyName(input.KeyCode)
		if key then
			local ok, err = pcall(onKey, key)
			if not ok then
				warn("Tecla " .. key .. " falhou: " .. tostring(err))
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			ui.pointerHeld = false
		end
	end)
	-- Soltar o botão fora da janela não gera InputEnded: sem isto o painel lateral parava de atualizar.
	UserInputService.WindowFocusReleased:Connect(function()
		ui.pointerHeld = false
		hidden = true
	end)
	UserInputService.WindowFocused:Connect(function()
		hidden = false
	end)
end

-- A cada segundo (Main, com o ponteiro solto): botões de nível e efeitos ambientes.
function Controller.ambient()
	renderLayers()
	ambientFx()
end

-- Para os outros módulos (Screens, Stage).
Controller.tileClick = tileClick
Controller.onHover = onHover
Controller.setMode = setMode
Controller.selectBuild = selectBuild
Controller.setLayer = function(d)
	setLayer(d)
end
Controller.renderLayers = renderLayers
Controller.updateMood = updateMood
Controller.startVisit = startVisit
Controller.endVisit = endVisit
Controller.refreshAfterVisit = refreshAfterVisit
Controller.renderAll = renderAll
Controller.ambientFx = ambientFx
Controller.result = result
Controller.hudInfo = hudInfo
Controller.lockedTabHint = lockedTabHint

return Controller
