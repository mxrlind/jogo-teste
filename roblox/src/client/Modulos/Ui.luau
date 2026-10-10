-- Peças de interface com o visual do styles.css: texto, ícone, botão Kenney, painel de pergaminho, card, barra.
-- Tudo devolve nós do Kit (Kit.h), para usar dentro de Kit.render.
local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local Assets = require(script.Parent.Assets)

local h = Kit.h
local U = {}

local AX, AY, AXY = Enum.AutomaticSize.X, Enum.AutomaticSize.Y, Enum.AutomaticSize.XY

local function merge(a, b)
	local out = table.clone(a)
	if b then
		for k, v in b do
			out[k] = v
		end
	end
	return out
end
U.merge = merge

-- ------------------------------------------------------------ texto
-- U.text("Olá", { size = .9 (rem), bold = true, color = T.c.muted, wrap = true, ... props do TextLabel })
-- Por padrão: largura automática numa linha. wrap = true ocupa a largura do pai e quebra linhas.
function U.text(str, o)
	o = o or {}
	local props = {
		BackgroundTransparency = 1,
		Text = str or "",
		RichText = o.rich ~= false,
		FontFace = o.font or (o.bold and T.bold or T.font),
		TextSize = T.rem(o.size or 1),
		TextColor3 = o.color or T.c.text,
		TextTransparency = o.transparency or 0,
		TextXAlignment = o.align or Enum.TextXAlignment.Left,
		TextYAlignment = o.valign or Enum.TextYAlignment.Center,
		TextWrapped = o.wrap or false,
		LineHeight = o.lineHeight or 1.1,
		AutomaticSize = o.wrap and AY or AXY,
		Size = o.wrap and UDim2.fromScale(1, 0) or UDim2.new(),
		TextTruncate = o.truncate and Enum.TextTruncate.AtEnd or nil,
	}
	for k, v in o do
		if type(k) == "string" and string.match(k, "^%u") then
			props[k] = v
		end
	end
	return h("TextLabel", props, o.children)
end

-- Texto em negrito (b, strong, h3, .num).
function U.b(str, o)
	o = o or {}
	o.bold = true
	return U.text(str, o)
end

-- Cor em texto rico: U.color("12", T.c.bad) -> <font color="#b8412f">12</font>
function U.color(str, color)
	return string.format('<font color="#%s">%s</font>', color:ToHex(), str)
end

function U.esc(s)
	s = tostring(s)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

-- ------------------------------------------------------------ ícones (game-icons, tingidos)
-- U.ico("gold", T.res.gold, 20)  (tamanho em px; padrão 1.25em de 1rem)
function U.ico(name, color, size, props)
	local s = size or T.rem(1.25)
	local p = merge(Assets.image("ico/" .. name), {
		BackgroundTransparency = 1,
		ImageColor3 = color or T.c.text,
		Size = UDim2.fromOffset(s, s),
		ScaleType = Enum.ScaleType.Fit,
	})
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return h("ImageLabel", p)
end

-- Ícone de recurso (resIco do web): "scrolls" usa o ícone "scroll".
function U.resIco(r, size, hud)
	local name = r == "scrolls" and "scroll" or r
	local pal = hud and T.resHud or T.res
	return U.ico(name, pal[r] or T.c.text, size)
end

-- Sprite (KayKit, RTS) ajustado na caixa.
function U.sprite(name, size, props)
	local p = merge(Assets.image(name), {
		BackgroundTransparency = 1,
		Size = typeof(size) == "UDim2" and size or UDim2.fromOffset(size or 44, size or 44),
		ScaleType = Enum.ScaleType.Fit,
	})
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return h("ImageLabel", p)
end

-- Linha horizontal (display: flex; align-items: center).
-- U.row({ gap = 6, wrap = true, justify = "between", props = {...} }, filhos)
function U.row(o, children)
	o = o or {}
	local props = merge({
		BackgroundTransparency = 1,
		AutomaticSize = o.fill == false and AXY or AY,
		Size = o.fill == false and UDim2.new() or UDim2.fromScale(1, 0),
	}, o.props)
	local kids = { Kit.list("x", { gap = o.gap or T.rem(0.4), wrap = o.wrap, align = o.align, justify = o.justify }) }
	if o.pad then
		table.insert(kids, o.pad)
	end
	table.insert(kids, children)
	return h("Frame", props, kids)
end

-- Coluna (display: flex; flex-direction: column).
function U.col(o, children)
	o = o or {}
	local props = merge({
		BackgroundTransparency = 1,
		AutomaticSize = o.fill == false and AXY or AY,
		Size = o.fill == false and UDim2.new() or UDim2.fromScale(1, 0),
	}, o.props)
	local kids = { Kit.list("y", { gap = o.gap or T.rem(0.5), align = o.align, justify = o.justify }) }
	if o.pad then
		table.insert(kids, o.pad)
	end
	table.insert(kids, children)
	return h("Frame", props, kids)
end

-- ------------------------------------------------------------ botões (Kenney UI Pack, border-image 8 8 12 8)
local BTN_IMG = {
	grey = { "ui/grey_button00", "ui/grey_button01" },
	primary = { "ui/yellow_button00", "ui/yellow_button01" },
	green = { "ui/green_button00", "ui/green_button01" },
	danger = { "ui/red_button00", "ui/red_button01" },
}
local BTN_TEXT = {
	grey = T.hex("#2b2a33"), primary = T.hex("#3b2a00"), green = T.hex("#ffffff"), danger = T.hex("#ffffff"),
}

local function sliceProps(name)
	local p = table.clone(Assets.image(name))
	local s = Assets.size(name) or Vector2.new(190, 49)
	p.ScaleType = Enum.ScaleType.Slice
	p.SliceCenter = Rect.new(8, 8, s.X - 8, s.Y - 12)
	p.SliceScale = 1
	return p
end
U.sliceProps = sliceProps

-- U.btn({ text = "Melhorar", icon = "upgrade", variant = "primary"|"green"|"danger"|"grey", small, big, poor,
--         disabled, on, iconOnly, onClick = fn, width = UDim, wrap, key, tip, children = {...extra} })
function U.btn(o)
	local variant = o.variant or "grey"
	local imgs = BTN_IMG[variant] or BTN_IMG.grey
	local rem = T.rem
	local fontSize = o.big and 1.08 or o.small and 0.85 or (o.size or 0.95)
	local minH = o.big and rem(3) or o.small and rem(2) or rem(2.4)
	local padX = o.iconOnly and rem(0.35) or o.small and rem(0.45) or rem(0.6)
	local padTop = o.small and 0 or rem(0.05)
	local padBottom = o.small and rem(0.3) or rem(0.35)
	if o.iconOnly then
		padTop, padBottom = 0, rem(0.3)
	end
	local textColor = o.color or BTN_TEXT[variant]
	local base = sliceProps(imgs[1])
	local pressed = sliceProps(imgs[2])
	local transp = o.disabled and 0.55 or o.poor and 0.22 or 0
	local tint = o.disabled and T.hex("#b8b8b8") or o.poor and T.hex("#d8d8d8") or T.hex("#ffffff")
	local props = merge(base, {
		key = o.key,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ImageColor3 = tint,
		ImageTransparency = transp,
		AutomaticSize = o.width and AY or AXY,
		Size = o.width and UDim2.new(o.width, UDim.new(0, minH)) or UDim2.fromOffset(0, minH),
		Selectable = not o.disabled,
		LayoutOrder = o.order,
		onClick = (not o.disabled) and o.onClick or nil,
		tip = o.tip,
		attrs = o.attrs,
	})
	if not o.disabled then
		props.press = pressed -- :active troca para a peça "01" (afundada)
	end
	if o.props then
		for k, v in o.props do
			props[k] = v
		end
	end
	local iconSize = o.iconSize or (o.iconOnly and rem(1.35) or math.floor(T.rem(fontSize) * 1.25 + 0.5))
	local content = {}
	if o.icon then
		table.insert(content, U.ico(o.icon, o.iconColor or textColor, iconSize, { ImageTransparency = transp }))
	end
	if o.text and o.text ~= "" then
		table.insert(content, U.text(o.text, {
			bold = true, size = fontSize, color = textColor, transparency = transp,
			wrap = o.wrap, align = o.wrap and Enum.TextXAlignment.Center or nil,
			Size = o.wrap and UDim2.fromScale(0, 0) or nil,
		}))
	end
	if o.children then
		table.insert(content, o.children)
	end
	local justify = o.justify or "center"
	local inner = h("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = AXY,
	}, {
		Kit.list("x", { gap = rem(0.45), justify = justify, align = "center", wrap = o.wrap }),
		content,
	})
	local kids = {
		Kit.pad(8 + padTop, 8 + padX, 8 + padBottom, 8 + padX),
		Kit.sizeLimit(Vector2.new(0, minH)),
		inner,
	}
	if o.on then
		table.insert(kids, Kit.stroke(T.c.gold, 3, 0))
	end
	return h("ImageButton", props, kids)
end

-- Caixa de seleção (grey_box / yellow_boxCheckmark).
function U.check(o)
	local img = o.checked and "ui/yellow_boxCheckmark" or "ui/grey_box"
	return h("TextButton", {
		key = o.key,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AutomaticSize = AY,
		Size = UDim2.fromScale(1, 0),
		onClick = o.onClick,
		tip = o.tip,
	}, {
		Kit.list("x", { gap = T.rem(0.6), align = "center" }),
		Kit.pad(T.rem(0.45), 0),
		h("ImageLabel", merge(Assets.image(img), { BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 28), ScaleType = Enum.ScaleType.Fit })),
		U.text(o.text, { bold = o.bold ~= false, wrap = true, Size = UDim2.new(1, -40, 0, 0) }),
	})
end

-- ------------------------------------------------------------ superfícies
-- Sombra suave (box-shadow): imagem 9-slice atrás do conteúdo. level: "sm" | "md" | "lg".
local SHADOW = {
	sm = { spread = 6, dy = 2, t = 0.75 },
	md = { spread = 22, dy = 8, t = 0.45 },
	lg = { spread = 34, dy = 14, t = 0.35 },
}
function U.shadow(level, radius)
	local s = SHADOW[level or "md"]
	local p = table.clone(Assets.image("ui/shadow"))
	p.BackgroundTransparency = 1
	p.ScaleType = Enum.ScaleType.Slice
	p.SliceCenter = Rect.new(32, 32, 64, 64)
	p.SliceScale = s.spread / 24
	p.ImageColor3 = T.hex("#080610")
	p.ImageTransparency = s.t
	p.Size = UDim2.new(1, s.spread * 2, 1, s.spread * 2)
	p.Position = UDim2.fromOffset(-s.spread, -s.spread + s.dy)
	p.ZIndex = 0
	return h("ImageLabel", p)
end

-- .panel: pergaminho com degradê, borda clara, filete dourado por dentro e sombra.
-- U.panel(props do Frame externo, filhos, { shadow = "md"|"lg"|false, pad = px | UIPadding, radius, layout = nó | false, gap })
-- Os filhos vão num Frame "body" com lista vertical; o externo pode ter AutomaticSize = Y.
function U.panel(props, children, o)
	o = o or {}
	local r = o.radius or T.rLg
	local pad = o.pad
	if pad == nil then
		pad = Kit.pad(T.rem(0.9), T.rem(1))
	elseif type(pad) == "number" then
		pad = Kit.pad(pad)
	end
	local outer = merge({ BackgroundTransparency = 1, ClipsDescendants = false }, props)
	local bodyProps = {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, (props and props.AutomaticSize == AY) and 0 or 1),
		AutomaticSize = (props and props.AutomaticSize == AY) and AY or Enum.AutomaticSize.None,
		ZIndex = 2,
	}
	if o.bodyProps then
		for k, v in o.bodyProps do
			bodyProps[k] = v
		end
	end
	local layout = o.layout
	if layout == nil then
		layout = Kit.list("y", { gap = o.gap or T.rem(0.5) })
	end
	return h("Frame", outer, {
		o.shadow ~= false and U.shadow(o.shadow or "md") or nil,
		h("Frame", {
			Name = "Paper",
			BackgroundColor3 = T.c.white,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, {
			Kit.corner(r),
			Kit.grad({ T.c.paper2, T.c.paper }, 90),
			Kit.stroke(T.hex("#3c2800"), 1, 0.82),
			h("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -8),
			}, { Kit.corner(r - 4), Kit.stroke(T.hex("#b9820e"), 1, 0.78) }),
		}),
		h("Frame", bodyProps, { pad or nil, layout or nil, children }),
	})
end

-- .card: branco, borda --line, raio 12.
function U.card(children, o)
	o = o or {}
	return h("Frame", merge({
		key = o.key,
		BackgroundColor3 = T.c.white,
		AutomaticSize = AY,
		Size = UDim2.fromScale(1, 0),
	}, o.props), {
		Kit.corner(T.r),
		Kit.stroke(T.c.line, 1, 0),
		o.pad ~= false and Kit.pad(T.rem(0.8), T.rem(0.85)) or nil,
		o.layout ~= false and Kit.list("y", { gap = o.gap or T.rem(0.4) }) or nil,
		children,
	})
end

-- .card h3: ícone dourado + título + contador à direita.
function U.cardTitle(icon, title, count)
	return U.row({ gap = T.rem(0.5), props = { Size = UDim2.fromScale(1, 0) } }, {
		icon and U.ico(icon, T.c.goldText, T.rem(1.4)) or nil,
		U.text(title, { bold = true, size = 1.05, Size = UDim2.new(), AutomaticSize = AXY }),
		count and h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(), AutomaticSize = AXY }, {
			Kit.flex(1),
		}) or nil,
		count and U.text(count, { bold = true, size = 0.78, color = T.c.muted }) or nil,
	})
end

-- text-transform: uppercase com os acentos do português (string.upper só mexe em ASCII).
local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
function U.upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end

-- h4 / .lbl: rótulo em caixa alta, espaçado.
function U.label(str, o)
	o = o or {}
	return U.text(U.upper(str), merge({ bold = true, size = o.size or 0.72, color = o.color or T.c.muted }, o))
end

-- .bar: trilho pergaminho, preenchimento verde (gold/big = roxo), texto centralizado.
-- U.bar(fração 0..1, texto, { kind = "gold"|"big", height })
local BAR = {
	normal = { T.hex("#5cc777"), T.hex("#2e8b47") },
	gold = { T.hex("#ffd45c"), T.hex("#e0a21b") },
	big = { T.hex("#b79aff"), T.hex("#7a52c4") },
}
function U.bar(frac, label, o)
	o = o or {}
	local hgt = o.height or (o.kind == "big" and 26 or 18)
	local cols = BAR[o.kind or "normal"] or BAR.normal
	frac = math.clamp(frac or 0, 0, 1)
	return h("Frame", merge({
		key = o.key,
		BackgroundColor3 = T.c.paper3,
		Size = UDim2.new(o.width or UDim.new(1, 0), UDim.new(0, hgt)),
		ClipsDescendants = true,
	}, o.props), {
		Kit.corner(99),
		h("Frame", { BackgroundColor3 = T.c.white, Size = UDim2.fromScale(frac, 1), Visible = frac > 0 }, {
			Kit.corner(99),
			Kit.grad(cols, 90),
		}),
		label and U.text(label, {
			bold = true, size = o.kind == "big" and 0.8 or 0.72, color = T.c.text, align = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 2,
			TextStrokeColor3 = T.c.white, TextStrokeTransparency = 0.35,
		}) or nil,
	})
end

-- Pílula (.stats span, .xp, .badge-on).
function U.pill(children, o)
	o = o or {}
	return h("Frame", merge({
		key = o.key,
		BackgroundColor3 = o.bg or T.c.white,
		BackgroundTransparency = o.bgTransparency or 0,
		AutomaticSize = AXY,
		Size = UDim2.new(),
	}, o.props), {
		Kit.corner(99),
		o.border ~= false and Kit.stroke(o.borderColor or T.c.line, 1, 0) or nil,
		Kit.pad(T.rem(0.12), T.rem(0.55)),
		Kit.list("x", { gap = T.rem(0.25), align = "center" }),
		children,
	})
end

-- Custo com ícones (costHtml): vermelho no que falta.
local COST_ORDER = { "gold", "food", "wood", "stone", "gems", "scrolls", "crowns" }
function U.cost(cost, res, o)
	o = o or {}
	local fmt = o.fmt
	local items = {}
	for _, r in COST_ORDER do
		local v = cost and cost[r]
		if v and v > 0 then
			local short = res and (res[r] or 0) < v
			table.insert(items, U.row({ fill = false, gap = 2 }, {
				U.resIco(r, o.iconSize or T.rem(1.25 * (o.size or 1)), o.hud),
				U.text(fmt and fmt(v) or tostring(v), {
					bold = o.bold, size = o.size or 1, color = short and T.c.bad or (o.color or T.c.text),
				}),
			}))
		end
	end
	return U.row({ fill = false, gap = T.rem(0.35), wrap = o.wrap }, items)
end

-- Linha divisória (.divider).
function U.divider()
	return h("Frame", { BackgroundColor3 = T.c.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) })
end

-- Separador tracejado entre linhas de lista (border-bottom: 1px dashed var(--line)).
function U.dashed()
	local p = table.clone(Assets.image("ui/dash-h"))
	p.BackgroundTransparency = 1
	p.ImageColor3 = T.c.line
	p.ScaleType = Enum.ScaleType.Tile
	p.TileSize = UDim2.fromOffset(9, 1)
	p.Size = UDim2.new(1, 0, 0, 1)
	return h("ImageLabel", p)
end

-- .warn: aviso laranja.
function U.warn(text)
	return h("Frame", {
		BackgroundColor3 = T.hex("#fff0d6"),
		AutomaticSize = AY,
		Size = UDim2.fromScale(1, 0),
	}, {
		Kit.corner(10),
		Kit.stroke(T.hex("#f4cf91"), 1, 0),
		Kit.pad(T.rem(0.4), T.rem(0.55)),
		Kit.list("x", { gap = T.rem(0.45), align = "start" }),
		U.ico("warning", T.hex("#c06a00"), T.rem(1.1)),
		U.text(text, { size = 0.88, color = T.hex("#7a3e00"), wrap = true, Size = UDim2.new(1, -T.rem(1.6), 0, 0) }),
	})
end

-- Espaço flexível numa linha (empurra o resto para a direita).
function U.spacer()
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0) }, { Kit.flex(1) })
end

return U
