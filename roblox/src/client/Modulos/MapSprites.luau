-- Qual imagem do atlas representa o quê no mapa (porte de src/ui/sprites.js e das cores de src/ui/assets.js).
-- Este módulo não desenha nada. Os nomes são os de Modulos/Atlas.luau.
local S = {}

-- Quadro dos sprites do KayKit em tiles, relativo ao centro do tile (y para baixo): a altura sobe para o tile de cima.
-- SPRITE_K = quanto a altura sobe na tela (a hélice do moinho já vem achatada por ele: "blades-N").
S.SPRITE_FRAME = { left = -0.6, right = 0.6, top = -1.25, bottom = 0.6 }
S.SPRITE_K = 0.7

local GRASS = { "grass-1", "grass-2" }
S.TERRAIN_SPRITES = {
	grass = { base = GRASS, icon = "grass-1" },
	forest = { base = GRASS, over = { "forest-1", "forest-2", "forest-3", "forest-4" }, icon = "icon-forest-1" },
	-- Muda: o desenho troca de estágio com o tempo (saplingSprite); `over` é o primeiro estágio.
	sapling = { base = GRASS, over = { "sapling-1" }, stages = { "sapling-1", "sapling-2" }, icon = "icon-sapling-1" },
	rock = { base = GRASS, over = { "rock-1", "rock-2" }, icon = "icon-rock-1" },
	water = { base = { "water-1", "water-2" }, icon = "water-1" },
	mountain = { base = GRASS, over = { "mountain-1", "mountain-2" }, icon = "icon-mountain-1" },
}

-- Prédios: sprite no quadro SPRITE_FRAME. `blades` = hélice do moinho em volta de `hub` (tiles, relativo ao centro).
-- `stages` = sprites maiores a partir de certos níveis ({ nível, nome }, do menor para o maior).
local function building(id, extra)
	local b = { src = "building-" .. id, icon = "icon-" .. id }
	for k, v in extra or {} do
		b[k] = v
	end
	return b
end
local function staged(id)
	return building(id, { stages = { { 5, "building-" .. id .. "-5" }, { 10, "building-" .. id .. "-10" } } })
end
S.BUILDING_SPRITES = {
	casa = building("casa"),
	fazenda = building("fazenda"),
	serraria = building("serraria"),
	pedreira = building("pedreira"),
	mercado = building("mercado"),
	moinho = building("moinho", { blades = { hub = { x = -0.004, y = -0.261 }, size = 0.712 } }),
	armazem = building("armazem"),
	taverna = staged("taverna"),
	quartel = staged("quartel"),
	muralha = building("muralha"),
	torre = building("torre"),
	mina = building("mina"),
	templo = building("templo"),
	jardim = building("jardim"),
	fogueira = building("fogueira"), -- poço do KayKit
	estatua = building("estatua"),
	escadaria = building("escadaria"),
	cais = building("cais"),
}

-- Hélice pré-girada: 12 quadros de 0 a 82,5 graus (passo de 7,5); a hélice tem simetria de 90 graus.
S.BLADE_FRAMES = 12
function S.bladesFrame(angle)
	local deg = math.deg(angle) % 90
	local f = math.floor(deg / (90 / S.BLADE_FRAMES) + 0.5) % S.BLADE_FRAMES
	return "blades-" .. (f + 1)
end

S.BOAT_SPRITE = "barco"

S.UNDER_SPRITES = {
	rock = { "u-rock-1", "u-rock-2" },
	gold = { "u-gold" },
	gem = { "u-gem" },
	water = { "u-water" },
	magma = { "u-magma" },
	floor = { "u-floor-1", "u-floor-2" },
	cavern = { "u-cavern-1", "u-cavern-2" },
}
local function room(id)
	return { src = "room-" .. id, icon = "icon-room-" .. id }
end
S.ROOM_SPRITES = {
	pedreira_funda = room("pedreira_funda"),
	adega = room("adega"),
	garimpo = room("garimpo"),
	fungos = room("fungos"),
	forja = room("forja"),
}

S.RUIN_SPRITE = "building-ruina"
S.RUIN_ICON = "icon-ruina"

-- Muralha que se liga sozinha: um sprite por máscara de vizinhos (Map.wallMask). Máscara 0 usa o sprite normal.
function S.wallSrc(mask)
	return mask == 0 and "building-muralha" or ("building-muralha-" .. mask)
end

-- Sprite do prédio no nível `lvl` (o último estágio alcançado).
function S.buildingSrc(spr, lvl)
	local src = spr.src
	for _, st in spr.stages or {} do
		if lvl >= st[1] then
			src = st[2]
		end
	end
	return src
end

-- Estágio da muda: pequena na 1ª metade do crescimento, árvores jovens na 2ª. `now` em ms (relógio do jogo).
function S.saplingSprite(tile, now, growSeconds)
	local stages = S.TERRAIN_SPRITES.sapling.stages
	local p = (now - (tile.p or 0)) / 1000 / growSeconds
	return stages[p < 0.5 and 1 or 2]
end

-- rgba(20, 22, 32, 0.62)
S.LOCKED_COLOR = Color3.fromRGB(20, 22, 32)
S.LOCKED_ALPHA = 0.62

S.CART_SPRITE = "rts-s7"
S.RAIDER_SPRITES = { "rts-u9", "rts-u10", "rts-u8" }

-- Profissões dos moradores (ver Villagers.luau): sprite do Medieval RTS e ferramenta (ícone) que balança no trabalho.
-- A ordem é a do objeto JS (usada para os sprites de quem passeia).
S.PROFESSION_ORDER = { "fazenda", "cais", "moinho", "serraria", "pedreira", "mina", "mercado", "armazem", "taverna", "torre", "quartel", "templo" }
S.PROFESSIONS = {
	fazenda = { name = "Lavrador", sprite = "rts-u13", tool = "clear" },
	cais = { name = "Pescador", sprite = "rts-u21" },
	moinho = { name = "Moleira", sprite = "rts-u12" },
	serraria = { name = "Lenhador", sprite = "rts-u19", tool = "hero-woodcutter" },
	pedreira = { name = "Pedreiro", sprite = "rts-u1", tool = "tool-pickaxe" },
	mina = { name = "Mineira", sprite = "rts-u18", tool = "tool-pickaxe" },
	mercado = { name = "Mercadora", sprite = "rts-u24" },
	armazem = { name = "Intendente", sprite = "rts-u17" },
	taverna = { name = "Taverneiro", sprite = "rts-u23" },
	torre = { name = "Guarda", sprite = "rts-u3" },
	quartel = { name = "Soldado", sprite = "rts-u4" },
	templo = { name = "Sacerdote", sprite = "rts-u2" },
}
S.SLEEPER_SPRITES = { "rts-u13", "rts-u19", "rts-u1", "rts-u12" }
S.TOOL_ICONS = { "clear", "hero-woodcutter", "tool-pickaxe" }

-- Cores de RES_COLORS / TOOL_COLOR de src/ui/assets.js (ícones desenhados no mapa).
S.RES_COLORS = {
	gold = Color3.fromHex("#f2b632"),
	food = Color3.fromHex("#f0c27a"),
	wood = Color3.fromHex("#c8834a"),
	stone = Color3.fromHex("#d7dde0"),
	gems = Color3.fromHex("#7cc6f0"),
}
S.TOOL_COLOR = Color3.fromHex("#ece6da")

return S
