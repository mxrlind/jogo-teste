-- Desenho do mapa em "modo imediato" sobre um pool de Instances (o lugar do <canvas> do web).
-- Cada camada é um Frame; a cada quadro ela recebe as mesmas chamadas que o canvas recebia (img, rect, texto...),
-- na mesma ordem. Cada chamada pega o próximo elemento do pool, recebe ZIndex = ordem da chamada (o container usa
-- ZIndexBehavior Sibling) e só tem escritas nas propriedades que mudaram desde o quadro anterior.
-- O que sobrar do pool no fim do quadro fica invisível. Nada de Kit aqui: o mapa redesenha a 60 fps.
local Assets = require(script.Parent.Assets)
local T = require(script.Parent.Theme)

local D = {}

local L = {}
L.__index = L

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
D.WHITE = WHITE
D.BLACK = BLACK

-- "#rrggbb" ou Color3 -> Color3 (com cache).
local hexCache = {}
function D.color(c)
	if c == nil then
		return WHITE
	end
	if typeof(c) == "Color3" then
		return c
	end
	local v = hexCache[c]
	if not v then
		local ok, r = pcall(Color3.fromHex, c)
		v = ok and r or WHITE
		hexCache[c] = v
	end
	return v
end

-- ------------------------------------------------------------ fábricas
local MAKE = {}

function MAKE.img(parent)
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.ScaleType = Enum.ScaleType.Stretch
	i.Image = ""
	i.Parent = parent
	return i
end

function MAKE.rect(parent)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = WHITE
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

function MAKE.grad(parent)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = WHITE
	f.BackgroundTransparency = 0
	local g = Instance.new("UIGradient")
	g.Parent = f
	f.Parent = parent
	return f
end

function MAKE.text(parent)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.FontFace = T.bold
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = ""
	t.Parent = parent
	return t
end

-- Etiqueta em pílula (label() do render.js): largura = texto + 12 px, sem medir o texto (AutomaticSize).
function MAKE.pill(parent)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.BackgroundColor3 = Color3.fromRGB(43, 42, 51)
	f.BackgroundTransparency = 0.1
	local c = Instance.new("UICorner")
	c.Parent = f
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 6)
	p.PaddingRight = UDim.new(0, 6)
	p.Parent = f
	local t = Instance.new("TextLabel")
	t.Name = "T"
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.FontFace = T.bold
	t.Text = ""
	t.Parent = f
	f.Parent = parent
	return f
end

-- Número flutuante: texto com contorno + ícone opcional, centrados juntos.
function MAKE.float(parent)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.AutomaticSize = Enum.AutomaticSize.X
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 2)
	l.Parent = f
	local t = Instance.new("TextLabel")
	t.Name = "T"
	t.LayoutOrder = 1
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.FontFace = T.bold
	t.Text = ""
	local s = Instance.new("UIStroke")
	s.Color = BLACK
	s.Thickness = 1.5
	s.Transparency = 0.35
	s.Parent = t
	t.Parent = f
	local i = Instance.new("ImageLabel")
	i.Name = "I"
	i.LayoutOrder = 2
	i.BackgroundTransparency = 1
	i.Image = ""
	i.Parent = f
	f.Parent = parent
	return f
end

-- ------------------------------------------------------------ camada
function D.layer(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	local self = setmetatable({
		frame = f,
		pools = { img = { n = 0 }, rect = { n = 0 }, grad = { n = 0 }, text = { n = 0 }, pill = { n = 0 }, float = { n = 0 } },
		z = 0,
		sig = nil, -- camadas estáticas: assinatura do último desenho
		visible = true,
	}, L)
	return self
end

function L:setVisible(v)
	if self.visible ~= v then
		self.visible = v
		self.frame.Visible = v
	end
end

function L:begin()
	self.z = 0
	for _, pool in self.pools do
		pool.n = 0
	end
end

function L:finish()
	for _, pool in self.pools do
		for k = pool.n + 1, #pool do
			local e = pool[k]
			if e.vis then
				e.vis = false
				e.i.Visible = false
			end
		end
	end
end

-- Esvazia a camada (tudo invisível).
function L:clear()
	self:begin()
	self:finish()
	self.sig = nil
end

function L:_get(kind)
	local pool = self.pools[kind]
	local n = pool.n + 1
	pool.n = n
	local e = pool[n]
	if not e then
		e = { i = MAKE[kind](self.frame), vis = true }
		pool[n] = e
	end
	local z = self.z + 1
	self.z = z
	if e.z ~= z then
		e.z = z
		e.i.ZIndex = z
	end
	if not e.vis then
		e.vis = true
		e.i.Visible = true
	end
	return e
end

local function place(e, x, y, w, h)
	if e.x ~= x or e.y ~= y then
		e.x, e.y = x, y
		e.i.Position = UDim2.fromOffset(x, y)
	end
	if e.w ~= w or e.h ~= h then
		e.w, e.h = w, h
		e.i.Size = UDim2.fromOffset(w, h)
	end
end

-- Imagem do atlas na caixa (x, y, w, h) esticada (drawImage). alpha = opacidade (globalAlpha), color = tinta
-- (ícones brancos), rot = graus em volta do centro, flip = espelhada na horizontal (ctx.scale(-1, 1)).
function L:img(name, x, y, w, h, alpha, color, rot, flip)
	local e = self:_get("img")
	local i = e.i
	flip = flip == true
	if e.name ~= name or e.flip ~= flip then
		e.name, e.flip = name, flip
		local p = Assets.image(name)
		i.Image = p.Image
		local off, size = p.ImageRectOffset, p.ImageRectSize
		if size then
			if flip then
				-- ImageRectSize negativo espelha a imagem.
				i.ImageRectOffset = off + Vector2.new(size.X, 0)
				i.ImageRectSize = Vector2.new(-size.X, size.Y)
			else
				i.ImageRectOffset = off
				i.ImageRectSize = size
			end
		else
			i.ImageRectOffset = Vector2.zero
			i.ImageRectSize = Vector2.zero
		end
	end
	place(e, x, y, w, h)
	local t = 1 - (alpha or 1)
	if e.t ~= t then
		e.t = t
		i.ImageTransparency = t
	end
	color = color or WHITE
	if e.c ~= color then
		e.c = color
		i.ImageColor3 = color
	end
	rot = rot or 0
	if e.r ~= rot then
		e.r = rot
		i.Rotation = rot
	end
	return i
end

-- Retângulo (arredondado se radius > 0) com preenchimento e/ou contorno.
-- Como no canvas, o contorno fica centrado no caminho: o Frame encolhe sw/2 e o UIStroke cobre sw/2 para fora.
-- alpha = opacidade do preenchimento (0 = sem preenchimento); salpha = opacidade do contorno; rot = graus.
function L:rect(x, y, w, h, color, alpha, radius, scolor, salpha, sw, rot)
	local e = self:_get("rect")
	local i = e.i
	sw = (scolor and sw and sw > 0) and sw or 0
	radius = radius or 0
	if sw > 0 then
		local hs = sw / 2
		x, y, w, h = x + hs, y + hs, w - sw, h - sw
		radius = math.max(0, radius - hs)
	end
	place(e, x, y, w, h)
	rot = rot or 0
	if e.r ~= rot then
		e.r = rot
		i.Rotation = rot
	end
	color = color or WHITE
	if e.c ~= color then
		e.c = color
		i.BackgroundColor3 = color
	end
	local t = 1 - (alpha or 0)
	if e.t ~= t then
		e.t = t
		i.BackgroundTransparency = t
	end
	if e.rad ~= radius then
		e.rad = radius
		local c = e.corner
		if not c and radius == 0 then
			return self:_rectStroke(e, i, sw, scolor, salpha)
		end
		if not c then
			c = Instance.new("UICorner")
			c.Parent = i
			e.corner = c
		end
		c.CornerRadius = UDim.new(0, radius)
	end
	return self:_rectStroke(e, i, sw, scolor, salpha)
end

function L:_rectStroke(e, i, sw, scolor, salpha)
	local st = e.stroke
	if sw > 0 then
		if not st then
			st = Instance.new("UIStroke")
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.LineJoinMode = Enum.LineJoinMode.Miter
			st.Parent = i
			e.stroke = st
		end
		if not e.sOn then
			e.sOn = true
			st.Enabled = true
		end
		if e.sc ~= scolor then
			e.sc = scolor
			st.Color = scolor
		end
		local stt = 1 - (salpha or 1)
		if e.st ~= stt then
			e.st = stt
			st.Transparency = stt
		end
		if e.sw ~= sw then
			e.sw = sw
			st.Thickness = sw
		end
	elseif st and e.sOn then
		e.sOn = false
		st.Enabled = false
	end
	return i
end

-- Círculo cheio (arc + fill) de centro (cx, cy) e raio r.
function L:circle(cx, cy, r, color, alpha, scolor, salpha, sw)
	return self:rect(cx - r, cy - r, r * 2, r * 2, color, alpha, r, scolor, salpha, sw)
end

-- Faixa em degradê (createLinearGradient): cor com opacidade a0 no início e a1 no fim; rot = direção (graus,
-- 0 = da esquerda para a direita, 90 = de cima para baixo).
function L:grad(x, y, w, h, color, a0, a1, rot)
	local e = self:_get("grad")
	local i = e.i
	place(e, x, y, w, h)
	if e.c ~= color then
		e.c = color
		i.BackgroundColor3 = color
	end
	local g = e.g
	if not g then
		g = i:FindFirstChildOfClass("UIGradient")
		e.g = g
	end
	if e.a0 ~= a0 or e.a1 ~= a1 then
		e.a0, e.a1 = a0, a1
		g.Transparency = NumberSequence.new(1 - a0, 1 - a1)
	end
	if e.r ~= rot then
		e.r = rot
		g.Rotation = rot
	end
	return i
end

-- Texto centrado em (cx, cy) (textAlign center + textBaseline middle), com contorno opcional (strokeText).
function L:text(cx, cy, text, color, size, alpha, scolor, salpha, sw)
	local e = self:_get("text")
	local i = e.i
	local bw, bh = math.max(40, size * #text), size * 1.6
	place(e, cx, cy, bw, bh)
	if e.s ~= text then
		e.s = text
		i.Text = text
	end
	if e.fs ~= size then
		e.fs = size
		i.TextSize = size
	end
	if e.c ~= color then
		e.c = color
		i.TextColor3 = color
	end
	local t = 1 - (alpha or 1)
	if e.t ~= t then
		e.t = t
		i.TextTransparency = t
	end
	local st = e.stroke
	if scolor and sw and sw > 0 then
		if not st then
			st = Instance.new("UIStroke")
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = i
			e.stroke = st
		end
		st.Enabled = true
		if e.sc ~= scolor then
			e.sc = scolor
			st.Color = scolor
		end
		-- A transparência do contorno acompanha a do texto (globalAlpha vale para os dois no canvas).
		local stt = 1 - (salpha or 1) * (alpha or 1)
		if e.st ~= stt then
			e.st = stt
			st.Transparency = stt
		end
		if e.sw ~= sw then
			e.sw = sw
			st.Thickness = sw
		end
	elseif st then
		st.Enabled = false
	end
	return i
end

-- Pílula escura com texto (label() do render.js): centro (cx, cy), altura h, fonte size.
function L:pill(cx, cy, text, color, size, h)
	local e = self:_get("pill")
	local i = e.i
	if e.x ~= cx or e.y ~= cy then
		e.x, e.y = cx, cy
		i.Position = UDim2.fromOffset(cx, cy)
	end
	if e.h ~= h then
		e.h = h
		i.Size = UDim2.fromOffset(0, h)
		i:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, h / 2)
	end
	local t = e.t
	if not t then
		t = i:FindFirstChild("T")
		e.t = t
	end
	if e.s ~= text then
		e.s = text
		t.Text = text
	end
	if e.fs ~= size or e.th ~= h then
		e.fs, e.th = size, h
		t.TextSize = size
		-- fillText(cx, cy + 1): o texto desce 1 px.
		t.Size = UDim2.fromOffset(0, h)
		t.Position = UDim2.fromOffset(0, 1)
	end
	if e.c ~= color then
		e.c = color
		t.TextColor3 = color
	end
	return i
end

-- Número flutuante: texto (com contorno preto 0,65) + ícone de iconW px, juntos centrados em (cx, cy).
function L:float(cx, cy, text, color, size, icon, iconW, alpha)
	local e = self:_get("float")
	local i = e.i
	if e.x ~= cx or e.y ~= cy then
		e.x, e.y = cx, cy
		i.Position = UDim2.fromOffset(cx, cy)
	end
	if not e.t then
		e.t = i:FindFirstChild("T")
		e.ic = i:FindFirstChild("I")
		e.stroke = e.t:FindFirstChildOfClass("UIStroke")
	end
	local tl, ic = e.t, e.ic
	if e.s ~= text then
		e.s = text
		tl.Text = text
	end
	if e.fs ~= size then
		e.fs = size
		tl.TextSize = size
		tl.Size = UDim2.fromOffset(0, size * 1.4)
		i.Size = UDim2.fromOffset(0, size * 1.4)
	end
	if e.c ~= color then
		e.c = color
		tl.TextColor3 = color
	end
	if e.icon ~= icon then
		e.icon = icon
		if icon then
			local p = Assets.image(icon)
			ic.Image = p.Image
			ic.ImageRectOffset = p.ImageRectOffset or Vector2.zero
			ic.ImageRectSize = p.ImageRectSize or Vector2.zero
			ic.Visible = true
		else
			ic.Visible = false
		end
	end
	if e.ic3 ~= color then
		e.ic3 = color
		ic.ImageColor3 = color
	end
	if e.iw ~= iconW then
		e.iw = iconW
		ic.Size = UDim2.fromOffset(iconW, iconW)
	end
	local t = 1 - alpha
	if e.a ~= t then
		e.a = t
		tl.TextTransparency = t
		ic.ImageTransparency = t
		e.stroke.Transparency = 1 - 0.65 * alpha
	end
	return i
end

-- Retângulo tracejado (setLineDash([on, off]) + strokeRect): o tracejado segue o perímetro a partir do canto de
-- cima à esquerda, em sentido horário, como no canvas. Cada traço é um Frame de espessura lw centrado no caminho.
function L:dashRect(x, y, w, h, lw, on, off, color, alpha)
	local per = on + off
	local s0 = 0
	local hw = lw / 2
	for side = 1, 4 do
		local ox, oy, dx, dy, len
		if side == 1 then
			ox, oy, dx, dy, len = x, y, 1, 0, w
		elseif side == 2 then
			ox, oy, dx, dy, len = x + w, y, 0, 1, h
		elseif side == 3 then
			ox, oy, dx, dy, len = x + w, y + h, -1, 0, w
		else
			ox, oy, dx, dy, len = x, y + h, 0, -1, h
		end
		local k = math.floor(s0 / per)
		while true do
			local a = k * per
			if a >= s0 + len then
				break
			end
			local ia = math.max(a, s0) - s0
			local ib = math.min(a + on, s0 + len) - s0
			if ib > ia then
				local px, py = ox + dx * ia, oy + dy * ia
				local qx, qy = ox + dx * ib, oy + dy * ib
				local rx, ry = math.min(px, qx), math.min(py, qy)
				if dy == 0 then
					self:rect(rx, ry - hw, math.abs(qx - px), lw, color, alpha or 1)
				else
					self:rect(rx - hw, ry, lw, math.abs(qy - py), color, alpha or 1)
				end
			end
			k += 1
		end
		s0 += len
	end
end

return D
