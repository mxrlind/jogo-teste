-- Renderizador do mapa (porte de src/ui/render.js, MapRenderer): o <canvas> do web vira um Frame quadrado com
-- ImageLabels/Frames de um pool (Modulos/MapDraw), na mesma ordem de desenho do canvas.
-- Camadas: chão (estática, só redesenha quando o mapa muda) -> natureza e prédios, linha a linha de trás para a frente
-- (o que é alto invade o tile de cima) -> território bloqueado e borda (estática) -> unidades -> realces -> efeitos.
-- Subsolo: chão, sombras e escadas (estática) -> brilho do magma -> névoa (estática) -> salas, realces e efeitos.
--
-- Uso: local r = MapView.new(parent, { onTileClick, onHover, onResize, getConfig, fill = "cover"? })
-- r.frame, r.mode, r.selected, r.cursor, r.layer, r.hover, r.view; r:draw(game, dt); r:resize(); r:pop(x, y);
-- r:popUnder(d, x, y); r:addBurst(x, y, cor?); r:addFloat(x, y, texto, cor, icone?); r:doShake(ms); r:doFlash(cor, ms?);
-- r:destroy(). Coordenadas de tile começam em 0 como no web.
-- No renderizador do jogo (com onTileClick), mode/selected/cursor/layer/hover são os mesmos de Ctx.ui
-- (ler ou escrever em r.x é ler ou escrever em Ctx.ui.x).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Map = require(Reino.Core.Map)
local Economy = require(Reino.Core.Economy)
local Util = require(Reino.Core.Util)
local Under = require(Reino.Core.Underground)
local Game = require(Reino.Core.Game)
local Buildings = require(Reino.Data.Buildings)
local UData = require(Reino.Data.Underground)

local Ctx = require(script.Parent.Ctx)
local S = require(script.Parent.MapSprites)
local D = require(script.Parent.MapDraw)
local Villagers = require(script.Parent.Villagers)

local BUILDINGS, TERRAIN, GROW_SECONDS = Buildings.BUILDINGS, Buildings.TERRAIN, Buildings.GROW_SECONDS
local GRID_W, GRID_H, idx = Map.GRID_W, Map.GRID_H, Map.idx
local isUnlocked, neighbors, ringOf, wallMask = Map.isUnlocked, Map.neighbors, Map.ringOf, Map.wallMask
local UNDER_TILES = UData.UNDER_TILES
local SPRITE_FRAME, SPRITE_K = S.SPRITE_FRAME, S.SPRITE_K
local TERRAIN_SPRITES, BUILDING_SPRITES, UNDER_SPRITES, ROOM_SPRITES = S.TERRAIN_SPRITES, S.BUILDING_SPRITES, S.UNDER_SPRITES, S.ROOM_SPRITES

local RAID_WARNING_MS = 20000

-- pick(arr, i) do web com i começando em 0.
local function pick(arr, i)
	local n = #arr
	return arr[((i % n) + n) % n + 1]
end

-- Relógio monotônico em ms (performance.now).
local function perf()
	return os.clock() * 1000
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local hex = Color3.fromHex
local WHITE, BLACK = D.WHITE, D.BLACK
local GOLD = hex("#f2b632")
local GOLD_HI = hex("#ffd45c")
local INK_TEXT = hex("#2b2a33")
local GOOD_LABEL = hex("#9be7a8")
local BAD_LABEL = hex("#ffb3a6")
local WARN_LABEL = hex("#ffe08a")
local WARN_ICON = hex("#ffb020")
local SWORDS_ICON = hex("#ff8a7a")
local SEL_FILL = rgb(255, 224, 138)
local CORNER_SHADOW = rgb(30, 24, 10)
local PREVIEW_OK, PREVIEW_OK_LINE = rgb(155, 231, 168), rgb(190, 255, 200)
local PREVIEW_BAD, PREVIEW_BAD_LINE = rgb(255, 110, 90), rgb(255, 150, 130)
local SCORCH = rgb(30, 20, 15)
local SMOKE = rgb(55, 52, 50)
local UNDER_BG = hex("#121019")
local MAGMA_GLOW = rgb(255, 200, 60)
local WALL_SHADOW = rgb(10, 8, 16)
local FOG = rgb(18, 16, 25)

-- Tiles: { x, y } nos dois formatos ({ x = , y = } e { [1], [2] }).
local function xyOf(t)
	return t.x or t[1], t.y or t[2]
end
local function tileRef(x, y)
	return { x = x, y = y, x, y }
end

-- Campos que o renderizador do jogo divide com Ctx.ui.
local SHARED = { mode = true, selected = true, cursor = true, layer = true, hover = true }

local MapView = {}
local META = {
	__index = function(t, k)
		if SHARED[k] then
			if rawget(t, "bound") then
				return Ctx.ui[k]
			end
			return rawget(t, "_f")[k]
		end
		return MapView[k]
	end,
	__newindex = function(t, k, v)
		if SHARED[k] then
			if rawget(t, "bound") then
				Ctx.ui[k] = v
			else
				rawget(t, "_f")[k] = v
			end
			return
		end
		rawset(t, k, v)
	end,
}

-- ------------------------------------------------------------ moldura (#map do styles.css)
local function stroked(parent, name, grow, radius, color, transp, thick, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, grow * 2, 1, grow * 2)
	f.Position = UDim2.fromOffset(-grow, -grow)
	f.ZIndex = z
	f.Active = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Transparency = transp
	s.Thickness = thick
	s.Parent = f
	f.Parent = parent
	return f, s
end

-- Sombra difusa (box-shadow) com a imagem 9-slice "ui/shadow" (retângulo borrado, borda em 24 px, blur 9 px).
-- blur = desfoque do CSS em px; o 9-slice escala para o sigma do CSS (blur / 2).
local function softShadow(parent, name, blur, dy, color, alpha, z)
	local Assets = require(script.Parent.Assets)
	local p = Assets.image("ui/shadow")
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = p.Image
	if p.ImageRectSize then
		i.ImageRectOffset = p.ImageRectOffset
		i.ImageRectSize = p.ImageRectSize
	end
	i.ScaleType = Enum.ScaleType.Slice
	i.SliceCenter = Rect.new(32, 32, 64, 64)
	local k = (blur / 2) / 9
	local spread = 24 * k
	i.SliceScale = k
	i.ImageColor3 = color
	i.ImageTransparency = 1 - alpha
	i.Size = UDim2.new(1, spread * 2, 1, spread * 2)
	i.Position = UDim2.fromOffset(-spread, -spread + dy)
	i.ZIndex = z
	i.Parent = parent
	return i
end

function MapView.new(parent, opts)
	opts = opts or {}
	local self = setmetatable({
		_f = { mode = { type = "select" }, layer = 0 },
		bound = opts.onTileClick ~= nil,
		parent = parent,
		onTileClick = opts.onTileClick,
		onHover = opts.onHover,
		onResize = opts.onResize,
		getConfig = opts.getConfig or function()
			return Ctx.config
		end,
		fill = opts.fill,
		view = nil,
		fx = {},
		pops = {},
		life = Villagers.new(),
		shake = 0,
		flash = nil,
		lastTouch = nil,
		touchPointer = false,
		size = nil,
		tile = nil,
		conns = {},
		look = nil,
	}, META)
	if not self.bound then
		-- No web cada MapRenderer começa sem seleção, em modo seleção e na superfície.
		self._f.selected = nil
	end
	local cover = self.fill == "cover"

	local frame = Instance.new("Frame")
	frame.Name = "Mapa"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(0, 0)
	frame.ZIndex = 1
	self.frame = frame

	if not cover then
		-- box-shadow: 0 0 0 3px #2a2433, 0 0 0 5px rgba(185,130,14,.55), 0 0 0 6px rgba(0,0,0,.5), var(--shadow-lg)
		-- --shadow-lg: 0 24px 60px rgba(8,6,16,.55), 0 4px 12px rgba(8,6,16,.35)
		self.shadowA = softShadow(frame, "SombraA", 60, 24, rgb(8, 6, 16), 0.55, 0)
		self.shadowB = softShadow(frame, "SombraB", 12, 4, rgb(8, 6, 16), 0.35, 0)
		-- Subsolo: 0 0 0 3px #5b4a3a, 0 10px 30px rgba(0,0,0,.5)
		self.shadowU = softShadow(frame, "SombraSubsolo", 30, 10, BLACK, 0.5, 0)
		self.shadowU.Visible = false
	end

	-- Recorte: o canvas não desenha fora do quadrado. (ClipsDescendants recorta em retângulo; os anéis da moldura
	-- por cima cobrem os cantos arredondados.)
	local clip = Instance.new("Frame")
	clip.Name = "Recorte"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	clip.ZIndex = 1
	clip.Parent = frame
	self.clip = clip

	local content = Instance.new("Frame")
	content.Name = "Conteudo"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = clip
	self.content = content

	self.L = {
		ter = D.layer(content, "Chao", 1),
		obj = D.layer(content, "Objetos", 2),
		lock = D.layer(content, "Territorio", 3),
		top = D.layer(content, "Unidades", 4),
		uA = D.layer(content, "SubsoloChao", 5),
		uB = D.layer(content, "SubsoloMagma", 6),
		uC = D.layer(content, "SubsoloNevoa", 7),
		uD = D.layer(content, "SubsoloSalas", 8),
	}
	for _, k in { "uA", "uB", "uC", "uD" } do
		self.L[k]:setVisible(false)
	end
	self.surface = true

	-- Clarão (doFlash): por cima de tudo, tremendo junto (fillRect -20..size+40 no canvas).
	local flash = Instance.new("Frame")
	flash.Name = "Clarao"
	flash.BorderSizePixel = 0
	flash.Size = UDim2.new(1, 40, 1, 40)
	flash.Position = UDim2.fromOffset(-20, -20)
	flash.BackgroundTransparency = 1
	flash.Visible = false
	flash.ZIndex = 50
	flash.Parent = content
	self.flashFrame = flash

	if cover then
		-- #menuMap: filter: blur(4px) saturate(1.1) brightness(.55). O desfoque não existe na GUI do Roblox;
		-- o brilho vira um véu preto de 45%.
		local dim = Instance.new("Frame")
		dim.Name = "Escurecer"
		dim.BorderSizePixel = 0
		dim.BackgroundColor3 = BLACK
		dim.BackgroundTransparency = 0.55
		dim.Size = UDim2.fromScale(1, 1)
		dim.ZIndex = 60
		dim.Parent = clip
	else
		local _, s1 = stroked(frame, "Anel1", 0, 14, hex("#2a2433"), 0, 3, 5)
		local r2 = stroked(frame, "Anel2", 3, 17, rgb(185, 130, 14), 0.45, 2, 4)
		local r3 = stroked(frame, "Anel3", 5, 19, BLACK, 0.5, 1, 3)
		self.ring1, self.ring2, self.ring3 = s1, r2, r3
		-- border-radius: 14px do canvas. ClipsDescendants só recorta em retângulo: os cantos que sobram entre o
		-- arco de 14 px e o canto quadrado são cobertos por faixas de 1 px da cor do anel (no web, o anel de 3 px
		-- do box-shadow, que segue o arco, também ocupa esse lugar).
		self.cornerMasks = {}
		local R = 14
		for row = 0, R - 1 do
			local dy = R - row - 0.5
			local wpx = R - math.sqrt(math.max(0, R * R - dy * dy))
			if wpx > 0.05 then
				for k = 0, 3 do
					local m = Instance.new("Frame")
					m.Name = "Canto"
					m.BorderSizePixel = 0
					m.BackgroundColor3 = hex("#2a2433")
					m.ZIndex = 2
					local right, bottom = k % 2 == 1, k >= 2
					m.AnchorPoint = Vector2.new(right and 1 or 0, bottom and 1 or 0)
					m.Position = UDim2.new(right and 1 or 0, 0, bottom and 1 or 0, bottom and -row or row)
					m.Size = UDim2.fromOffset(wpx, 1)
					-- borda antisserrilhada: a fração do pixel vira opacidade
					local whole = math.floor(wpx)
					if whole < 1 then
						m.Size = UDim2.fromOffset(1, 1)
						m.BackgroundTransparency = 1 - wpx
					end
					m.Parent = frame
					table.insert(self.cornerMasks, m)
				end
			end
		end
	end

	if opts.onTileClick or opts.onHover then
		local hit = Instance.new("ImageButton")
		hit.Name = "Toque"
		hit.BackgroundTransparency = 1
		hit.Image = ""
		hit.AutoButtonColor = false
		hit.Selectable = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 10
		hit.Parent = frame
		self.hit = hit
		local MB1, TOUCH, MOVE = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement
		table.insert(self.conns, hit.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == MB1 or t == TOUCH then
				self.touchPointer = t == TOUCH
				self:pointer(input, true)
			end
		end))
		table.insert(self.conns, hit.InputChanged:Connect(function(input)
			local t = input.UserInputType
			if t == MOVE or t == TOUCH then
				self.touchPointer = t == TOUCH
				self:pointer(input, false)
			end
		end))
		-- No toque, o dedo "sai" do mapa ao levantar: manter a prévia até o 2º toque.
		table.insert(self.conns, hit.MouseLeave:Connect(function()
			if self.touchPointer then
				return
			end
			self.hover = nil
			if self.onHover then
				self.onHover(nil)
			end
		end))
	end

	frame.Parent = parent
	table.insert(self.conns, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:resize()
	end))
	-- O primeiro onResize espera o construtor devolver (quem chamou ainda não tem a referência do renderizador).
	self:resize(true)
	if self.onResize then
		task.defer(function()
			if self.frame.Parent then
				self.onResize()
			end
		end)
	end
	return self
end

function MapView:destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	self.conns = {}
	self.frame:Destroy()
end

function MapView:resize(silent)
	local ps = self.parent.AbsoluteSize
	-- Elemento oculto: espera o tamanho mudar de novo.
	if ps.X == 0 and ps.Y == 0 then
		return
	end
	local frame = self.frame
	if self.fill == "cover" then
		-- Tamanho = o maior lado, preso no canto de cima à esquerda; transform: scale(1.04) em volta do centro.
		local size = math.max(ps.X, ps.Y)
		local big = size * 1.04
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(-size * 0.02, -size * 0.02)
		frame.Size = UDim2.fromOffset(big, big)
		self.size = big
	else
		local size = math.max(240, math.floor(math.min(ps.X, ps.Y > 0 and ps.Y or ps.X)))
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(size, size)
		self.size = size
	end
	self.tile = self.size / GRID_W
	-- força o redesenho das camadas estáticas
	for _, l in self.L do
		l.sig = nil
	end
	if self.onResize and not silent then
		self.onResize()
	end
end

-- ------------------------------------------------------------ entrada
function MapView:tileFromInput(input)
	local p = input.Position
	local px, py = p.X, p.Y
	-- InputObject.Position não conta a barra do Roblox; numa ScreenGui com IgnoreGuiInset as posições absolutas contam.
	local sg = self.frame:FindFirstAncestorOfClass("ScreenGui")
	if sg and sg.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()
		px += inset.X
		py += inset.Y
	end
	local ap, as = self.frame.AbsolutePosition, self.frame.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then
		return nil
	end
	local x = math.floor(((px - ap.X) / as.X) * GRID_W)
	local y = math.floor(((py - ap.Y) / as.Y) * GRID_H)
	if x >= 0 and y >= 0 and x < GRID_W and y < GRID_H then
		return tileRef(x, y)
	end
	return nil
end

function MapView:pointer(input, isClick)
	local t = self:tileFromInput(input)
	local h = self.hover
	local hx, hy
	if h then
		hx, hy = xyOf(h)
	end
	local changed = not h or not t or hx ~= t.x or hy ~= t.y
	self.hover = t
	if changed and self.onHover then
		self.onHover(t)
	end
	if not isClick or not t then
		return
	end
	-- No toque, em modo construção/mover o 1º toque só mostra a prévia; o 2º no mesmo tile confirma.
	local mode = self.mode
	if input.UserInputType == Enum.UserInputType.Touch and mode and mode.type ~= "select" then
		local lt = self.lastTouch
		if not lt or lt.x ~= t.x or lt.y ~= t.y then
			self.lastTouch = t
			return
		end
	end
	self.lastTouch = nil
	if self.onTileClick then
		self.onTileClick(t.x, t.y)
	end
end

-- ------------------------------------------------------------ efeitos
function MapView:fxOn()
	return self.getConfig().particles ~= false
end
function MapView:motionOn()
	return not self.getConfig().reduceMotion
end

function MapView:addFloat(x, y, text, color, icon)
	if not self:fxOn() then
		return
	end
	if icon and string.sub(icon, 1, 4) ~= "ico/" then
		icon = "ico/" .. icon
	end
	table.insert(self.fx, { kind = "float", x = x, y = y, text = tostring(text), color = D.color(color or "#ffffff"), icon = icon, born = perf(), life = 1500 })
	while #self.fx > 80 do
		table.remove(self.fx, 1)
	end
end

function MapView:addBurst(x, y, color)
	if not self:fxOn() then
		return
	end
	local c = D.color(color or "#f2b632")
	local now = perf()
	table.insert(self.fx, { kind = "ring", x = x, y = y, color = c, born = now, life = 520 })
	for i = 0, 11 do
		local a = (math.pi * 2 * i) / 12
		table.insert(self.fx, {
			kind = "spark", x = x, y = y, color = c, born = now, life = 650,
			vx = math.cos(a) * (0.5 + math.random() * 0.6), vy = math.sin(a) * (0.5 + math.random() * 0.6),
		})
	end
end

function MapView:pop(x, y)
	self.pops[idx(x, y)] = perf()
end
function MapView:popUnder(d, x, y)
	self.pops[-(idx(x, y) + d * 1000)] = perf()
end
function MapView:doShake(ms)
	if self:motionOn() then
		self.shake = perf() + (ms or 500)
	end
end
function MapView:doFlash(color, ms)
	if self:motionOn() then
		ms = ms or 500
		self.flash = { color = D.color(color), untilT = perf() + ms, ms = ms }
	end
end

-- ------------------------------------------------------------ primitivas do canvas
-- Sprite do KayKit no quadro SPRITE_FRAME, ancorado no centro do tile (cx, cy).
local function framed(L, name, cx, cy, T, scale, alpha, flip)
	scale = scale or 1
	local f = SPRITE_FRAME
	L:img(name, cx + f.left * T * scale, cy + f.top * T * scale, (f.right - f.left) * T * scale, (f.bottom - f.top) * T * scale, alpha, nil, 0, flip)
end

-- Hélice do moinho: quadro pré-girado (ângulo mod 90 graus) e já achatado por SPRITE_K, no cubo `hub`.
local function drawBlades(L, blades, cx, cy, T, scale, angle, alpha)
	local w = blades.size * T * scale
	local h = w * SPRITE_K
	local hx, hy = cx + blades.hub.x * T * scale, cy + blades.hub.y * T * scale
	L:img(S.bladesFrame(angle), hx - w / 2, hy - h / 2, w, h, alpha)
end

-- Bordas inteiras de um tile (sem frestas nem sobreposição entre vizinhos).
local function cell(x, y, T)
	local x0, y0 = math.floor(x * T + 0.5), math.floor(y * T + 0.5)
	return x0, y0, math.floor((x + 1) * T + 0.5) - x0, math.floor((y + 1) * T + 0.5) - y0
end

local function label(L, cx, cy, text, color, T, big)
	local fs = math.max(10, T * (big and 0.26 or 0.21))
	local h = math.max(15, T * (big and 0.36 or 0.3))
	L:pill(cx, cy, text, color, fs, h)
end

local function badge(L, cx, cy, text, T)
	local r = T * 0.15
	L:circle(cx, cy + 1.5, r, BLACK, 0.3)
	L:circle(cx, cy, r, INK_TEXT, 1, GOLD, 1, 2)
	L:text(cx, cy + 0.5, text, WHITE, math.max(9, T * 0.17))
end

-- Cantoneiras da seleção: mais legíveis que um contorno inteiro e não escondem o sprite.
local function corners(L, x, y, T, grow)
	local g = 3 - (grow or 0)
	local len = T * 0.26
	local lw = math.max(2.5, T * 0.05)
	local hw = lw / 2
	for pass = 1, 0, -1 do
		local o = pass -- sombra deslocada 1 px, depois o traço dourado
		local color = pass == 1 and CORNER_SHADOW or GOLD_HI
		local alpha = pass == 1 and 0.45 or 1
		for k = 1, 4 do
			local cx, cy, sx, sy
			if k == 1 then
				cx, cy, sx, sy = x + g, y + g, 1, 1
			elseif k == 2 then
				cx, cy, sx, sy = x + T - g, y + g, -1, 1
			elseif k == 3 then
				cx, cy, sx, sy = x + g, y + T - g, 1, -1
			else
				cx, cy, sx, sy = x + T - g, y + T - g, -1, -1
			end
			cx += o
			cy += o
			-- traço vertical e horizontal com ponta redonda (lineCap round)
			L:rect(cx - hw, math.min(cy, cy + sy * len) - hw, lw, len + lw, color, alpha, hw)
			L:rect(math.min(cx, cx + sx * len) - hw, cy - hw, len + lw, lw, color, alpha, hw)
		end
	end
end

-- Realce branco do tile sob o mouse (sem construção).
local function hoverBox(L, x, y, T)
	L:rect(x * T + 2, y * T + 2, T - 4, T - 4, WHITE, 0.10, T * 0.14, WHITE, 0.6, 2)
end

local function selection(L, x, y, T, motion, now, info)
	local pulse = motion and 0.5 + 0.5 * math.sin(now / 260) or 1
	L:rect(x * T + 2, y * T + 2, T - 4, T - 4, SEL_FILL, 0.12 + 0.08 * pulse, T * 0.14)
	corners(L, x * T, y * T, T, motion and pulse * T * 0.035 or 0)
	if info and info.adjParts then
		for _, p in info.adjParts do
			label(L, p.x * T + T / 2, p.y * T + T * 0.24, Util.fmtPct(p.value), p.value > 0 and GOOD_LABEL or BAD_LABEL, T)
		end
	end
end

-- ------------------------------------------------------------ superfície
-- Água onde fica o barquinho de cada cais funcionando: a primeira água vizinha. Índice da água -> índice do cais (0).
local function boatSpots(grid, econ)
	local out = {}
	for i, t in grid.tiles do
		if t.b and t.b.id == "cais" and not (econ and econ.tiles[i] and not econ.tiles[i].active) then
			local x, y = Map.xy(i)
			for _, n in neighbors(x, y) do
				local wi = idx(n[1], n[2])
				if grid.tiles[wi].t == "water" then
					if out[wi] == nil then
						out[wi] = i - 1
					end
					break
				end
			end
		end
	end
	return out
end

-- Barquinho indo e voltando devagar dentro do tile de água, balançando; vira para o lado em que anda.
local function drawBoat(L, x, y, T, now, seed, motion)
	local t = motion and now / 2600 + seed or seed
	local cx = x * T + T / 2 + math.sin(t) * T * 0.16
	local cy = y * T + T * 0.62 + (motion and math.sin(now / 520 + seed) * T * 0.025 or 0)
	framed(L, S.BOAT_SPRITE, cx, cy, T, 0.58, 1, math.cos(t) < 0)
end

-- Construção danificada pela horda: chão chamuscado, fogo baixo e fumaça subindo (parada sem animação).
local function drawDamage(L, cx, cy, T, seed, now)
	L:img("ui/disc", cx - T * 0.42, cy + T * 0.28 - T * 0.16, T * 0.84, T * 0.32, 0.35, SCORCH)
	for k = 0, 2 do
		local fx = cx + (k - 1) * T * 0.22 + math.sin(seed * 3 + k) * T * 0.04
		local flick = 0.75 + 0.25 * math.sin(now / 90 + k * 2 + seed)
		-- "ui/flame" (40x64): gota externa com base em (20, 50), meia-largura 13 e ponta 46 px acima; miolo amarelo.
		local by = cy + T * 0.2
		local sx = (T * 0.08) / 13
		local sy = (T * 0.2 * flick) / 46
		-- opacidade da gota externa = 0,9 * flick (a imagem já tem 0,92)
		L:img("ui/flame", fx - 20 * sx, by - 50 * sy, 40 * sx, 64 * sy, math.min(1, 0.9 * flick / 0.92))
	end
	for k = 0, 3 do
		local p = (now / 2200 + k / 4 + seed * 0.13) % 1
		local sx = cx + math.sin(p * 5 + k + seed) * T * 0.12 + (k % 2 == 1 and T * 0.1 or -T * 0.08)
		local sy = cy - T * 0.2 - p * T * 0.9
		local r = T * (0.1 + p * 0.16)
		-- arc + fill: "ui/disc" (círculo de 62 px num quadro de 64, borda nítida como no canvas)
		local s = r * 2 * 64 / 62
		L:img("ui/disc", sx - s / 2, sy - s / 2, s, s, 0.75 * (1 - p * 0.8), SMOKE)
	end
end

local function popScale(self, key, now, motion)
	local popAt = self.pops[key]
	if popAt == nil then
		return 1
	end
	local p = (now - popAt) / 420
	if p >= 1 or not motion then
		self.pops[key] = nil
		return 1
	end
	return p < 0.6 and 0.75 + (p / 0.6) * 0.4 or 1.15 - ((p - 0.6) / 0.4) * 0.15
end

local function terrainSig(grid, size)
	local h = 5381
	for _, t in grid.tiles do
		h = (h * 33 + string.byte(t.t, 1) * 2 + (t.b and 1 or 0)) % 4294967296
	end
	return string.format("%d|%.3f|%d", grid.ring, size, h)
end

function MapView:drawSurface(game, grid, now)
	local state = game and game.state
	local view = self.view
	local econ = (not view) and game.econ or nil
	local T = self.tile
	local motion = self:motionOn()
	local Ls = self.L

	-- Chão (o cache do canvas): só muda quando o mapa ou o tamanho mudam.
	local sig = terrainSig(grid, self.size)
	local Lt = Ls.ter
	if Lt.sig ~= sig then
		Lt:begin()
		for y = 0, GRID_H - 1 do
			for x = 0, GRID_W - 1 do
				local i = idx(x, y)
				local i0 = i - 1
				local tile = grid.tiles[i]
				local spr = TERRAIN_SPRITES[tile.t] or TERRAIN_SPRITES.grass
				-- Sob prédios, sempre grama (os sprites de prédio não cobrem o tile inteiro).
				local base = tile.b and pick(TERRAIN_SPRITES.grass.base, i0) or pick(spr.base, i0 * 7 + 3)
				local cx, cy, cw, ch = cell(x, y, T)
				Lt:img(base, cx, cy, cw, ch)
			end
		end
		Lt:finish()
		Lt.sig = sig
	end

	-- Natureza e prédios, de trás para a frente
	local Lo = Ls.obj
	Lo:begin()
	local boats = boatSpots(grid, econ)
	local realNow = Ctx.now()
	for y = 0, GRID_H - 1 do
		for x = 0, GRID_W - 1 do
			local i = idx(x, y)
			local i0 = i - 1
			local tile = grid.tiles[i]
			local cx, cy = x * T + T / 2, y * T + T / 2
			if not tile.b then
				local bs = boats[i]
				if bs ~= nil then
					drawBoat(Lo, x, y, T, now, bs, motion)
				end
				if tile.ruin then
					framed(Lo, S.RUIN_SPRITE, cx, cy, T)
				else
					local over
					if tile.t == "sapling" then
						over = S.saplingSprite(tile, realNow, GROW_SECONDS)
					else
						local spr = TERRAIN_SPRITES[tile.t]
						over = spr and spr.over and pick(spr.over, i0)
					end
					if over then
						framed(Lo, over, cx, cy, T)
					end
				end
			else
				local spr = BUILDING_SPRITES[tile.b.id]
				if spr then
					local info = econ and econ.tiles[i]
					local scale = popScale(self, i, now, motion)
					local dim = info and not info.damaged and (not info.active or (info.workers > 0 and info.staff < 0.5))
					local alpha = dim and 0.6 or 1
					local src = tile.b.id == "muralha" and S.wallSrc(wallMask(grid, x, y)) or S.buildingSrc(spr, tile.b.lvl)
					framed(Lo, src, cx, cy, T, scale, alpha)
					if spr.blades then
						local angle = (motion and (not info or info.active ~= false)) and now / 900 or 0.4
						drawBlades(Lo, spr.blades, cx, cy, T, scale, angle, alpha)
					end
					local dmg = tile.b.dmg
					if dmg and dmg ~= 0 then
						drawDamage(Lo, cx, cy, T, i0, motion and now or 0)
					end
				end
			end
		end
	end
	Lo:finish()

	-- Território bloqueado escurecido por cima da natureza (que sobe para o tile de cima) e a borda tracejada.
	local lsig = string.format("%d|%.3f", grid.ring, self.size)
	local Ll = Ls.lock
	if Ll.sig ~= lsig then
		Ll:begin()
		for y = 0, GRID_H - 1 do
			for x = 0, GRID_W - 1 do
				if not isUnlocked(grid, x, y) then
					local nextRing = ringOf(x, y) == grid.ring + 1
					local rx, ry, rw, rh = cell(x, y, T)
					Ll:rect(rx, ry, rw, rh, S.LOCKED_COLOR, nextRing and 0.5 or S.LOCKED_ALPHA)
				end
			end
		end
		-- Contorno tracejado do território: setLineDash([8, 5]), lineWidth 2,5, #f2b632.
		local lo = math.ceil((GRID_W - 1) / 2 - grid.ring - 0.5)
		local span = (GRID_W - 2 * lo) * T
		Ll:dashRect(lo * T + 1.5, lo * T + 1.5, span - 3, span - 3, 2.5, 8, 5, GOLD)
		Ll:finish()
		Ll.sig = lsig
	end

	-- Nível e avisos por cima de tudo que é do mapa; depois unidades, realces e efeitos.
	local L = Ls.top
	L:begin()
	for i, t in grid.tiles do
		local b = t.b
		if b then
			local x, y = Map.xy(i)
			if b.lvl > 1 then
				badge(L, x * T + T * 0.84, y * T + T * 0.84, tostring(b.lvl), T)
			end
			if b.dmg and b.dmg ~= 0 then
				L:img("ico/swords", x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3, 1, SWORDS_ICON)
			elseif econ and econ.tiles[i] and not econ.tiles[i].active then
				L:img("ico/warning", x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3, 1, WARN_ICON)
			end
		end
	end

	if not view and state then
		-- Moradores têm opção própria: "Reduzir movimento" não os esconde.
		if self.getConfig().villagers ~= false and state.pop then
			self.life:update(game, now)
			self.life:draw(L, now, T)
		end
		self:drawCart(L, state, now, T, motion)
		self:drawRaiders(L, state, now, T, motion)
	end

	-- Seleção e adjacência do prédio selecionado
	local sel = self.selected
	if sel and not view then
		local x, y = xyOf(sel)
		selection(L, x, y, T, motion, now, econ and econ.tiles[idx(x, y)])
	end

	local hov = self.hover
	if hov and not view and state then
		self:drawPreview(L, game, hov, T)
	end
	local cur = self.cursor
	if cur and not view and state then
		local cx, cy = xyOf(cur)
		L:dashRect(cx * T + 3, cy * T + 3, T - 6, T - 6, 3, 6, 4, GOLD)
		local hx, hy
		if hov then
			hx, hy = xyOf(hov)
		end
		if not hov or hx ~= cx or hy ~= cy then
			self:drawPreview(L, game, cur, T)
		end
	end

	self:drawEffects(L, now, T, motion)
	L:finish()
end

-- Carroça do mercador (evento surpresa).
function MapView:drawCart(L, state, now, T, motion)
	local chest = state.chest
	if not chest then
		return
	end
	local x, y = xyOf(chest)
	local glow = motion and 0.5 + 0.5 * math.sin(now / 220) or 0.7
	L:img("ui/disc", x * T + T / 2 - T * 0.46, y * T + T * 0.62 - T * 0.3, T * 0.92, T * 0.6, 0.25 + glow * 0.3, GOLD)
	local bob = motion and math.abs(math.sin(now / 260)) * T * 0.06 or 0
	L:img(S.CART_SPRITE, x * T + T * 0.08, y * T + T * 0.04 - bob, T * 0.84, T * 0.84)
end

-- Invasores entram pelo lado anunciado durante o aviso da horda.
function MapView:drawRaiders(L, state, now, T, motion)
	local raid = state.raid
	if not raid or not raid.warned then
		return
	end
	local left = (raid.nextAt or 0) - Ctx.now()
	local p = math.max(0, math.min(1, 1 - left / RAID_WARNING_MS))
	local dir = raid.dir or "n"
	local depth = -0.8 + p * 1.6 -- de fora do mapa até 0,8 tile para dentro
	for k = 0, 2 do
		local along = GRID_W / 2 - 1.5 + k * 1.1
		local x, y
		if dir == "n" then
			x, y = along, depth
		elseif dir == "s" then
			x, y = along, GRID_H - 1 - depth
		elseif dir == "w" then
			x, y = depth, along
		else
			x, y = GRID_W - 1 - depth, along
		end
		local bob = motion and math.sin(now / 140 + k) * T * 0.05 or 0
		L:img(pick(S.RAIDER_SPRITES, k), x * T + T * 0.1, y * T + T * 0.1 + bob, T * 0.8, T * 0.8)
	end
end

-- Prévia de construção / movimento no tile sob o mouse (ou o cursor do teclado).
function MapView:drawPreview(L, game, at, T)
	local x, y = xyOf(at)
	local state = game.state
	local grid = state.grid
	local tile = grid.tiles[idx(x, y)]
	if not tile then
		return
	end
	local mode = self.mode or { type = "select" }
	local buildId
	local fromX, fromY
	if mode.type == "build" then
		buildId = mode.id
	elseif mode.type == "move" and mode.from then
		fromX, fromY = xyOf(mode.from)
		local ft = grid.tiles[idx(fromX, fromY)]
		buildId = ft and ft.b and ft.b.id
	end
	if not buildId or not BUILDINGS[buildId] then
		hoverBox(L, x, y, T)
		return
	end
	local ter = TERRAIN[tile.t]
	local valid = not tile.b and ter ~= nil and ter.buildable and isUnlocked(grid, x, y)
	if valid then
		L:rect(x * T + 1, y * T + 1, T - 2, T - 2, PREVIEW_OK, 0.30, T * 0.12, PREVIEW_OK_LINE, 0.85, 2)
	else
		L:rect(x * T + 1, y * T + 1, T - 2, T - 2, PREVIEW_BAD, 0.38, T * 0.12, PREVIEW_BAD_LINE, 0.9, 2)
		return
	end
	-- Mover: a adjacência é calculada sem o prédio na origem (tirado e devolvido na hora, como no web).
	local restore
	if fromX then
		local from = grid.tiles[idx(fromX, fromY)]
		restore = from.b
		from.b = nil
	end
	local ok, adj = pcall(Economy.adjacencyAt, state, buildId, x, y, game.econ and game.econ.mods)
	if restore then
		grid.tiles[idx(fromX, fromY)].b = restore
	end
	if not ok then
		return
	end
	local spr = BUILDING_SPRITES[buildId]
	local cx, cy = x * T + T / 2, y * T + T / 2
	if spr then
		framed(L, buildId == "muralha" and S.wallSrc(wallMask(grid, x, y)) or S.buildingSrc(spr, 1), cx, cy, T, 1, 0.75)
		if spr.blades then
			drawBlades(L, spr.blades, cx, cy, T, 1, 0.4, 0.75)
		end
	end
	for _, n in neighbors(x, y) do
		L:rect(n[1] * T + 1, n[2] * T + 1, T - 2, T - 2, WHITE, 0, 0, WHITE, 0.35, 1)
	end
	for _, p in adj.parts do
		label(L, p.x * T + T / 2, p.y * T + T * 0.24, Util.fmtPct(p.value), p.value > 0 and GOOD_LABEL or BAD_LABEL, T)
	end
	local total = adj.hasRequired and ("Total " .. Util.fmtPct(adj.total)) or ("Precisa de " .. Game.neighborName(BUILDINGS[buildId].requiresAdj))
	local color
	if not adj.hasRequired then
		color = BAD_LABEL
	elseif adj.total > 0 then
		color = WARN_LABEL
	elseif adj.total < 0 then
		color = BAD_LABEL
	else
		color = WHITE
	end
	local ly = (y * T - T * 0.14 < T * 0.2) and (y * T + T * 1.12) or (y * T - T * 0.14)
	label(L, cx, ly, total, color, T, true)
end

-- Efeitos por cima de tudo (números flutuantes, anéis e faíscas). Compactação na própria lista.
function MapView:drawEffects(L, now, T, motion)
	local fx = self.fx
	local alive = 0
	local n = #fx
	for k = 1, n do
		local f = fx[k]
		if now - f.born < f.life then
			alive += 1
			fx[alive] = f
			local p = (now - f.born) / f.life
			local a = 1 - p
			if f.kind == "ring" then
				local e = 1 - (1 - p) ^ 3
				local lw = 3 * (1 - p) + 1
				local r = T * (0.25 + e * 0.6)
				L:circle(f.x * T + T / 2, f.y * T + T / 2, r, f.color, 0, f.color, a, lw)
			elseif f.kind == "float" then
				local fy = f.y * T + T * 0.3 - (motion and p * T * 0.8 or 0)
				local fs = math.max(11, T * 0.24)
				local iconW = f.icon and T * 0.26 or 0
				L:float(f.x * T + T / 2, fy, f.text, f.color, fs, f.icon, iconW, a)
			else
				L:circle(f.x * T + T / 2 + f.vx * p * T, f.y * T + T / 2 + f.vy * p * T, 3 * (1 - p) + 1, f.color, a)
			end
		end
	end
	for k = n, alive + 1, -1 do
		fx[k] = nil
	end
end

-- ------------------------------------------------------------ subsolo
local function underSig(lv, d, size)
	local h = 5381
	for _, t in lv.tiles do
		local st = t.st == "down" and 1 or (t.st and 2 or 0)
		h = (h * 33 + (string.byte(t.t, 1) * 16 + #t.t) * 8 + (t.s and 4 or 0) + st) % 4294967296
	end
	return string.format("%d|%.3f|%d", d, size, h)
end

-- Escada desenhada de cima: degraus que clareiam (sobe) ou escurecem (desce) em direção ao fundo.
local function drawStairs(L, x, y, T, dir)
	local m = T * 0.16
	local w = T - m * 2
	local n = 5
	L:rect(x * T + m - 2, y * T + m - 2, w + 4, w + 4, BLACK, 0.35, T * 0.08)
	for k = 0, n - 1 do
		local f = dir == "down" and k / (n - 1) or 1 - k / (n - 1)
		local c = math.floor(200 - 170 * f + 0.5)
		L:rect(x * T + m, y * T + m + (w / n) * k, w, w / n - 1.5, rgb(c, c - 8, c - 18), 1)
	end
	label(L, x * T + T / 2, y * T + T * 0.86, dir == "down" and "desce" or "sobe", WARN_LABEL, T)
end

-- Vista de cima no estilo Dwarf Fortress: rocha é parede, o que foi cavado é chão, e o que ninguém viu é escuro.
function MapView:drawUnder(game, under, now)
	local T = self.tile
	local motion = self:motionOn()
	local d = self.layer
	local lv = under.levels[d]
	if not lv then
		return
	end
	local econ = (not self.view) and game.econ or nil
	local infos = econ and econ.under and econ.under[d]
	local tiles = lv.tiles
	local function open(x, y)
		if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H then
			return false
		end
		local t = tiles[idx(x, y)]
		local def = UNDER_TILES[t.t]
		return t.s == true and def ~= nil and def.open == true
	end
	local Ls = self.L

	local sig = underSig(lv, d, self.size)
	local A, C = Ls.uA, Ls.uC
	if A.sig ~= sig then
		A:begin()
		A:rect(0, 0, self.size, self.size, UNDER_BG, 1)
		for y = 0, GRID_H - 1 do
			for x = 0, GRID_W - 1 do
				local i = idx(x, y)
				local t = tiles[i]
				if t.s then
					local spr = UNDER_SPRITES[t.t]
					if spr then
						local rx, ry, rw, rh = cell(x, y, T)
						A:img(pick(spr, (i - 1) * 7 + 3), rx, ry, rw, rh)
					end
					local def = UNDER_TILES[t.t]
					if def and def.open then
						-- Sombra das paredes sobre o chão: dá volume às galerias.
						local sh = T * 0.16
						if not open(x, y - 1) then
							A:grad(x * T, y * T, T, sh, WALL_SHADOW, 0.55, 0, 90)
						end
						if not open(x - 1, y) then
							A:grad(x * T, y * T, sh, T, WALL_SHADOW, 0.55, 0, 0)
						end
						if not open(x + 1, y) then
							A:grad(x * T + T - sh, y * T, sh, T, WALL_SHADOW, 0.55, 0, 180)
						end
						if not open(x, y + 1) then
							A:grad(x * T, y * T + T - sh * 0.6, T, sh * 0.6, WALL_SHADOW, 0.55, 0, 270)
						end
						if t.st then
							drawStairs(A, x, y, T, t.st)
						end
					end
				end
			end
		end
		A:finish()
		A.sig = sig
		-- Borda da névoa: o escuro avança um pouco sobre o que já se vê.
		C:begin()
		for y = 0, GRID_H - 1 do
			for x = 0, GRID_W - 1 do
				if not tiles[idx(x, y)].s then
					C:rect(x * T - T * 0.12, y * T - T * 0.12, T * 1.24, T * 1.24, FOG, 0.85)
				end
			end
		end
		C:finish()
	end

	-- Brilho do magma (por cima do chão do magma, embaixo da névoa).
	local B = Ls.uB
	B:begin()
	local glow = motion and 0.5 + 0.5 * math.sin(now / 700) or 0.5
	for y = 0, GRID_H - 1 do
		for x = 0, GRID_W - 1 do
			local t = tiles[idx(x, y)]
			if t.s and t.t == "magma" then
				local rx, ry, rw, rh = cell(x, y, T)
				B:rect(rx, ry, rw, rh, MAGMA_GLOW, 0.08 + 0.14 * glow)
			end
		end
	end
	B:finish()

	local L = Ls.uD
	L:begin()
	-- Salas, de trás para a frente.
	for y = 0, GRID_H - 1 do
		for x = 0, GRID_W - 1 do
			local i = idx(x, y)
			local b = tiles[i].b
			if b and ROOM_SPRITES[b.id] then
				local scale = popScale(self, -(i + d * 1000), now, motion)
				local alpha = (infos and infos[i] and not infos[i].active) and 0.6 or 1
				framed(L, ROOM_SPRITES[b.id].src, x * T + T / 2, y * T + T / 2, T, scale, alpha)
			end
		end
	end
	for i, t in tiles do
		local b = t.b
		if b then
			local x, y = Map.xy(i)
			if b.lvl > 1 then
				badge(L, x * T + T * 0.84, y * T + T * 0.84, tostring(b.lvl), T)
			end
			if infos and infos[i] and not infos[i].active then
				L:img("ico/warning", x * T + T * 0.66, y * T + T * 0.04, T * 0.3, T * 0.3, 1, WARN_ICON)
			end
		end
	end
	-- Seleção, vizinhos da sala selecionada e picareta sobre o que dá para cavar.
	local sel = self.selected
	if sel then
		local x, y = xyOf(sel)
		selection(L, x, y, T, motion, now, infos and infos[idx(x, y)])
	end
	for k = 1, 2 do
		local at = k == 1 and self.hover or self.cursor
		if at then
			local ax, ay = xyOf(at)
			local t = tiles[idx(ax, ay)]
			hoverBox(L, ax, ay, T)
			local def = t and UNDER_TILES[t.t]
			if t and t.s and def and def.dig and Under.canReach(lv, ax, ay) then
				L:img("ico/tool-pickaxe", ax * T + T * 0.3, ay * T + T * 0.3, T * 0.4, T * 0.4, 1, S.TOOL_COLOR)
			end
		end
	end
	self:drawEffects(L, now, T, motion)
	L:finish()
end

-- ------------------------------------------------------------ quadro
function MapView:_look(under)
	-- Moldura do #map: anel escuro e dourado na superfície; marrom escuro no subsolo (body[data-layer]).
	if self.look == under or not self.ring1 then
		return
	end
	self.look = under
	self.ring1.Color = under and hex("#5b4a3a") or hex("#2a2433")
	for _, m in self.cornerMasks do
		m.BackgroundColor3 = self.ring1.Color
	end
	self.ring2.Visible = not under
	self.ring3.Visible = not under
	self.shadowA.Visible = not under
	self.shadowB.Visible = not under
	self.shadowU.Visible = under
end

function MapView:_showSurface(on)
	if self.surface == on then
		return
	end
	self.surface = on
	local Ls = self.L
	Ls.ter:setVisible(on)
	Ls.obj:setVisible(on)
	Ls.lock:setVisible(on)
	Ls.top:setVisible(on)
	Ls.uA:setVisible(not on)
	Ls.uB:setVisible(not on)
	Ls.uC:setVisible(not on)
	Ls.uD:setVisible(not on)
end

function MapView:draw(game, _dt)
	local now = perf()
	local state = game and game.state
	local view = self.view
	local grid = (view and view.grid) or (state and state.grid)
	if not grid or not self.size or not self.tile then
		return
	end
	local layer = self.layer or 0
	local under = nil
	if layer > 0 then
		if not view and state and state.under then
			under = state.under
		elseif view and view.under then
			under = view.under
		end
	end
	-- moldura: só o jogo (não a visita) muda a cor no subsolo, como body[data-layer]
	self:_look(layer > 0 and not view)

	-- Tremor (doShake): o desenho todo se desloca ao acaso.
	local content = self.content
	if self.shake > now then
		local k = (self.shake - now) / 500
		content.Position = UDim2.fromOffset((math.random() - 0.5) * 9 * k, (math.random() - 0.5) * 9 * k)
		self.shaking = true
	elseif self.shaking then
		self.shaking = false
		content.Position = UDim2.new()
	end

	if under then
		self:_showSurface(false)
		self:drawUnder(game, under, now)
	else
		self:_showSurface(true)
		self:drawSurface(game, grid, now)
	end

	-- Clarão (doFlash)
	local fl = self.flash
	local ff = self.flashFrame
	if fl and fl.untilT > now then
		ff.BackgroundColor3 = fl.color
		ff.BackgroundTransparency = 1 - ((fl.untilT - now) / fl.ms) * 0.35
		ff.Visible = true
	elseif ff.Visible then
		self.flash = nil
		ff.Visible = false
	end
end

return MapView
