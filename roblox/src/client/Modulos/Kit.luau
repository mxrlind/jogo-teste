-- Kit: um "DOM virtual" mínimo para montar a interface como o jogo web monta HTML.
-- Cada painel é uma função que devolve uma árvore de nós (h(classe, props, filhos)); Kit.render compara com a
-- árvore anterior e só mexe nas propriedades e filhos que mudaram. Assim o painel pode ser redesenhado a cada
-- segundo (como o renderSide do web) sem recriar a tela inteira.
--
-- Props especiais (não são propriedades do Roblox):
--   key            identifica o nó entre irmãos (listas que mudam de ordem); sem key, compara pela posição
--   ref            function(inst) chamada quando a instância é criada
--   onClick        GuiButton.Activated
--   onDown/onUp    botão do mouse ou toque começou/terminou em cima (recebem o InputObject)
--   onEnter/onLeave mouse entrou/saiu
--   onMove         mouse ou toque se mexeu em cima (InputChanged)
--   onWheel        roda do mouse em cima (recebe o InputObject; Position.Z é a direção)
--   onText         TextBox: texto mudou (recebe o texto)
--   onFocusLost    TextBox: perdeu o foco (recebe enterPressed)
--   onSize         AbsoluteSize mudou (recebe a instância)
--   hover          tabela de props aplicada enquanto o mouse está em cima (o :hover do CSS)
--   press          tabela de props aplicada enquanto está pressionado (o :active do CSS)
--   tip            texto de dica ao parar o mouse em cima (o title="" do HTML); ver Kit.setTipHandler
--   attrs          atributos (SetAttribute)
--   fit / fitX     nome de um filho: a altura (fit) ou a largura (fitX) segue o AbsoluteSize dele. Use no lugar de
--                  AutomaticSize quando o quadro tem decoração em escala com sobra (sombra, halo): no Roblox, um
--                  neto com Size = (1, +x) dentro de um pai com AutomaticSize faz o pai crescer até ocupar a tela.
-- Filhos podem ser nós, false/nil (ignorados) ou listas de nós (achatadas).
-- Sem LayoutOrder explícito, cada filho GuiObject recebe LayoutOrder = posição, para UIListLayout seguir a ordem.
local Kit = {}

local EMPTY = table.freeze({})
local SPECIAL = {
	key = true, ref = true, onClick = true, onDown = true, onUp = true, onEnter = true, onLeave = true, onMove = true,
	onWheel = true, onText = true, onFocusLost = true, onSize = true, fit = true, fitX = true, hover = true, press = true, tip = true, attrs = true,
}

export type Node = { class: string, props: { [string]: any }, children: { any }? }

function Kit.h(class: string, props: { [string]: any }?, children: { any }?): Node
	return { class = class, props = props or EMPTY, children = children }
end

-- Estado por instância criada pelo Kit.
type Rec = {
	node: Node,
	kids: { Instance },
	kidNodes: { Node },
	conns: { [string]: RBXScriptConnection },
	hovered: boolean,
	pressed: boolean,
}
local recs: { [Instance]: Rec } = setmetatable({}, { __mode = "k" }) :: any

-- Valores padrão de cada classe, para "tirar" uma prop que sumiu do nó.
local defaults: { [string]: Instance } = {}
local function defaultOf(class, prop)
	local d = defaults[class]
	if not d then
		d = Instance.new(class)
		defaults[class] = d
	end
	local ok, v = pcall(function()
		return (d :: any)[prop]
	end)
	return ok and v or nil
end

local tipHandler = nil
function Kit.setTipHandler(fn)
	tipHandler = fn
end

-- Achata filhos: tira false/nil, abre listas aninhadas.
local function flatten(children, out)
	out = out or {}
	if not children then
		return out
	end
	local n = 0
	for k in children do
		if type(k) == "number" and k > n then
			n = k
		end
	end
	for i = 1, n do
		local c = children[i]
		if c then
			if c.class then
				table.insert(out, c)
			else
				flatten(c, out)
			end
		end
	end
	return out
end
Kit.flatten = flatten

local function setProp(inst, k, v)
	local ok, err = pcall(function()
		(inst :: any)[k] = v
	end)
	if not ok then
		warn("Kit: não deu para definir " .. inst.ClassName .. "." .. tostring(k) .. ": " .. tostring(err))
	end
end

-- Props visíveis agora = base + hover (se em cima) + press (se pressionado).
local function effective(rec: Rec)
	local p = rec.node.props
	if not (rec.hovered and p.hover) and not (rec.pressed and p.press) then
		return p
	end
	local out = table.clone(p)
	if rec.hovered and p.hover then
		for k, v in p.hover do
			out[k] = v
		end
	end
	if rec.pressed and p.press then
		for k, v in p.press do
			out[k] = v
		end
	end
	return out
end

local function applyProps(inst, class, old, new)
	for k, v in new do
		if not SPECIAL[k] and old[k] ~= v then
			setProp(inst, k, v)
		end
	end
	for k in old do
		if not SPECIAL[k] and new[k] == nil then
			local d = defaultOf(class, k)
			if d ~= nil then
				setProp(inst, k, d)
			end
		end
	end
end

local isButton = function(inst)
	return inst:IsA("GuiButton")
end

local function isPointer(input: InputObject)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

-- Liga os eventos uma vez; o handler lê sempre o nó atual (props podem trocar de função a cada render).
local function wire(inst, rec: Rec)
	local p = rec.node.props
	local conns = rec.conns
	local function prop(name)
		return rec.node.props[name]
	end
	local function restyle()
		local before = rec.node.props
		applyProps(inst, inst.ClassName, rec.lastApplied or before, effective(rec))
		rec.lastApplied = effective(rec)
	end
	if (p.onClick) and not conns.click and isButton(inst) then
		conns.click = (inst :: GuiButton).Activated:Connect(function(input)
			local f = prop("onClick")
			if f then
				f(input, inst)
			end
		end)
	end
	local needsHover = p.onEnter or p.onLeave or p.hover or p.tip
	if needsHover and not conns.enter and inst:IsA("GuiObject") then
		conns.enter = (inst :: GuiObject).MouseEnter:Connect(function()
			rec.hovered = true
			if rec.node.props.hover then
				restyle()
			end
			local f = prop("onEnter")
			if f then
				f(inst)
			end
			if tipHandler and prop("tip") then
				tipHandler(inst, prop("tip"))
			end
		end)
		conns.leave = (inst :: GuiObject).MouseLeave:Connect(function()
			rec.hovered = false
			rec.pressed = false
			if rec.node.props.hover or rec.node.props.press then
				restyle()
			end
			local f = prop("onLeave")
			if f then
				f(inst)
			end
			if tipHandler and prop("tip") then
				tipHandler(inst, nil)
			end
		end)
	end
	local needsPress = p.onDown or p.onUp or p.press or p.onWheel
	if needsPress and not conns.began and inst:IsA("GuiObject") then
		conns.began = (inst :: GuiObject).InputBegan:Connect(function(input)
			if isPointer(input) then
				rec.pressed = true
				if rec.node.props.press then
					restyle()
				end
				local f = prop("onDown")
				if f then
					f(input, inst)
				end
			end
		end)
		conns.ended = (inst :: GuiObject).InputEnded:Connect(function(input)
			if isPointer(input) then
				rec.pressed = false
				if rec.node.props.press then
					restyle()
				end
				local f = prop("onUp")
				if f then
					f(input, inst)
				end
			end
		end)
	end
	if (p.onMove or p.onWheel) and not conns.changed and inst:IsA("GuiObject") then
		conns.changed = (inst :: GuiObject).InputChanged:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseWheel then
				local f = prop("onWheel")
				if f then
					f(input, inst)
				end
			elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
				local f = prop("onMove")
				if f then
					f(input, inst)
				end
			end
		end)
	end
	if p.onText and not conns.text and inst:IsA("TextBox") then
		conns.text = inst:GetPropertyChangedSignal("Text"):Connect(function()
			local f = prop("onText")
			if f then
				f((inst :: TextBox).Text, inst)
			end
		end)
	end
	if p.onFocusLost and not conns.focus and inst:IsA("TextBox") then
		conns.focus = (inst :: TextBox).FocusLost:Connect(function(enter)
			local f = prop("onFocusLost")
			if f then
				f(enter, inst)
			end
		end)
	end
	if (p.fit or p.fitX) and inst:IsA("GuiObject") then
		local function apply()
			local fy, fx = prop("fit"), prop("fitX")
			local base = rec.node.props.Size or (inst :: GuiObject).Size
			local cy = fy and inst:FindFirstChild(fy)
			local cx = fx and inst:FindFirstChild(fx)
			local x = (cx and cx:IsA("GuiBase2d")) and UDim.new(0, cx.AbsoluteSize.X) or base.X
			local y = (cy and cy:IsA("GuiBase2d")) and UDim.new(0, cy.AbsoluteSize.Y) or base.Y
			local size = UDim2.new(x, y)
			if (inst :: GuiObject).Size ~= size then
				(inst :: GuiObject).Size = size
			end
		end
		local function bind()
			for _, k in { "fitY", "fitXc" } do
				if conns[k] then
					conns[k]:Disconnect()
					conns[k] = nil
				end
			end
			local fy, fx = prop("fit"), prop("fitX")
			local cy = fy and inst:FindFirstChild(fy)
			local cx = fx and inst:FindFirstChild(fx)
			if cy and cy:IsA("GuiBase2d") then
				conns.fitY = cy:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
			end
			if cx and cx ~= cy and cx:IsA("GuiBase2d") then
				conns.fitXc = cx:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
			end
			apply()
		end
		if not conns.fit then
			-- Os filhos são montados depois do wire: liga no próximo quadro e quando um filho entra.
			conns.fit = inst.ChildAdded:Connect(function()
				task.defer(bind)
			end)
			task.defer(bind)
		else
			apply()
		end
	end
	if p.onSize and not conns.size and inst:IsA("GuiBase2d") then
		conns.size = inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local f = prop("onSize")
			if f then
				f(inst)
			end
		end)
	end
end

local mount, patch

local function setAttrs(inst, old, new)
	old = old or EMPTY
	new = new or EMPTY
	for k, v in new do
		if old[k] ~= v then
			inst:SetAttribute(k, v)
		end
	end
	for k in old do
		if new[k] == nil then
			inst:SetAttribute(k, nil)
		end
	end
end

local function patchChildren(inst: Instance, rec: Rec, newChildren)
	local nodes = flatten(newChildren)
	local oldKids, oldNodes = rec.kids, rec.kidNodes
	local byKey = nil
	for i, n in oldNodes do
		local k = n.props.key
		if k ~= nil then
			byKey = byKey or {}
			byKey[k] = i
		end
	end
	local used = {}
	local kids = table.create(#nodes)
	for i, n in nodes do
		local k = n.props.key
		local j = nil
		if k ~= nil then
			j = byKey and byKey[k]
		elseif oldNodes[i] and oldNodes[i].props.key == nil then
			j = i
		end
		local child
		if j and not used[j] and oldNodes[j].class == n.class then
			used[j] = true
			child = patch(oldKids[j], oldNodes[j], n)
		else
			child = mount(n)
		end
		if n.props.LayoutOrder == nil and child:IsA("GuiObject") and (child :: GuiObject).LayoutOrder ~= i then
			(child :: GuiObject).LayoutOrder = i
		end
		if child.Parent ~= inst then
			child.Parent = inst
		end
		kids[i] = child
	end
	for j, old in oldKids do
		if not used[j] then
			old:Destroy()
		end
	end
	rec.kids = kids
	rec.kidNodes = nodes
end

function mount(node: Node): Instance
	local inst = Instance.new(node.class)
	local rec: Rec = { node = node, kids = {}, kidNodes = {}, conns = {}, hovered = false, pressed = false }
	recs[inst] = rec
	applyProps(inst, node.class, EMPTY, node.props)
	rec.lastApplied = node.props
	if node.props.attrs then
		setAttrs(inst, nil, node.props.attrs)
	end
	wire(inst, rec)
	patchChildren(inst, rec, node.children)
	if node.props.ref then
		node.props.ref(inst)
	end
	return inst
end

function patch(inst: Instance, old: Node, new: Node): Instance
	if old == new then
		return inst
	end
	local rec = recs[inst]
	if not rec or old.class ~= new.class then
		local fresh = mount(new)
		fresh.Parent = inst.Parent
		inst:Destroy()
		return fresh
	end
	local before = rec.lastApplied or old.props
	rec.node = new
	local now = effective(rec)
	applyProps(inst, new.class, before, now)
	rec.lastApplied = now
	if old.props.attrs or new.props.attrs then
		setAttrs(inst, old.props.attrs, new.props.attrs)
	end
	wire(inst, rec)
	patchChildren(inst, rec, new.children)
	return inst
end

-- Desenha `node` como único conteúdo gerenciado de `container` (o container não é do Kit).
-- Chamadas seguintes comparam com a árvore anterior. node = nil limpa.
local roots: { [Instance]: { inst: Instance?, node: Node? } } = setmetatable({}, { __mode = "k" }) :: any
function Kit.render(container: Instance, node: Node?): Instance?
	local r = roots[container]
	if not r then
		r = {}
		roots[container] = r
	end
	if not node then
		if r.inst then
			r.inst:Destroy()
		end
		r.inst, r.node = nil, nil
		return nil
	end
	if r.inst and r.node and r.inst.Parent == container then
		r.inst = patch(r.inst, r.node, node)
	else
		r.inst = mount(node)
	end
	r.node = node
	if r.inst.Parent ~= container then
		r.inst.Parent = container
	end
	return r.inst
end

-- Igual a Kit.render, mas para vários nós soltos dentro do container (sem um Frame em volta).
local multi: { [Instance]: Rec } = setmetatable({}, { __mode = "k" }) :: any
function Kit.renderList(container: Instance, nodes: { any })
	local rec = multi[container]
	if not rec then
		rec = { node = Kit.h("Folder"), kids = {}, kidNodes = {}, conns = {}, hovered = false, pressed = false }
		multi[container] = rec
	end
	patchChildren(container, rec, nodes)
end

-- Monta um nó solto (sem comparação); útil para efeitos que vivem pouco.
Kit.mount = function(node: Node, parent: Instance?)
	local inst = mount(node)
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- ------------------------------------------------------------ decoradores (filhos UI*)
local function udim(v)
	if typeof(v) == "UDim" then
		return v
	end
	return UDim.new(0, v or 0)
end

function Kit.corner(r)
	return Kit.h("UICorner", { CornerRadius = udim(r or 8) })
end

function Kit.stroke(color, thickness, transparency, mode)
	return Kit.h("UIStroke", {
		Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
	})
end

-- pad(todos) | pad(vertical, horizontal) | pad(top, right, bottom, left), em px.
function Kit.pad(t, r, b, l)
	if r == nil then
		r, b, l = t, t, t
	elseif b == nil then
		b, l = t, r
	end
	return Kit.h("UIPadding", { PaddingTop = udim(t), PaddingRight = udim(r), PaddingBottom = udim(b), PaddingLeft = udim(l) })
end

-- Lista flex: dir "x" ou "y"; opts: gap, align (cross: "start"|"center"|"end"), justify ("start"|"center"|"end"|"between"), wrap.
local H_ALIGN = { start = Enum.HorizontalAlignment.Left, center = Enum.HorizontalAlignment.Center, ["end"] = Enum.HorizontalAlignment.Right }
local V_ALIGN = { start = Enum.VerticalAlignment.Top, center = Enum.VerticalAlignment.Center, ["end"] = Enum.VerticalAlignment.Bottom }
function Kit.list(dir, opts)
	opts = opts or EMPTY
	local horizontal = dir == "x"
	local props = {
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = udim(opts.gap or 0),
		Wraps = opts.wrap or false,
	}
	local cross = opts.align or (horizontal and "center" or "start")
	local main = opts.justify or "start"
	if horizontal then
		props.VerticalAlignment = V_ALIGN[cross]
		if main == "between" then
			props.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
		else
			props.HorizontalAlignment = H_ALIGN[main]
		end
	else
		props.HorizontalAlignment = H_ALIGN[cross]
		if main == "between" then
			props.VerticalFlex = Enum.UIFlexAlignment.SpaceBetween
		else
			props.VerticalAlignment = V_ALIGN[main]
		end
	end
	if opts.itemFlex then
		props.ItemLineAlignment = opts.itemFlex
	end
	return Kit.h("UIListLayout", props)
end

-- Item flexível dentro de uma lista (flex: 1 do CSS).
function Kit.flex(grow, shrink)
	return Kit.h("UIFlexItem", {
		FlexMode = Enum.UIFlexMode.Custom, GrowRatio = grow or 1, ShrinkRatio = shrink or (grow or 1),
	})
end

function Kit.grid(cellSize, gap, opts)
	opts = opts or EMPTY
	return Kit.h("UIGridLayout", {
		CellSize = cellSize, CellPadding = typeof(gap) == "UDim2" and gap or UDim2.fromOffset(gap or 0, gap or 0),
		SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = opts.max or 0,
		HorizontalAlignment = opts.halign or Enum.HorizontalAlignment.Left,
	})
end

-- Degradê: cores = { c1, c2 } ou ColorSequence; rot em graus (90 = de cima para baixo); transp opcional.
function Kit.grad(colors, rot, transp)
	local seq = colors
	if typeof(colors) ~= "ColorSequence" then
		if #colors == 1 then
			seq = ColorSequence.new(colors[1])
		elseif #colors == 2 then
			seq = ColorSequence.new(colors[1], colors[2])
		else
			local kps = {}
			for i, c in colors do
				table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
			end
			seq = ColorSequence.new(kps)
		end
	end
	local t = transp
	if type(transp) == "table" then
		local kps = {}
		for _, kp in transp do
			table.insert(kps, NumberSequenceKeypoint.new(kp[1], kp[2]))
		end
		t = NumberSequence.new(kps)
	elseif type(transp) == "number" then
		t = NumberSequence.new(transp)
	end
	return Kit.h("UIGradient", { Color = seq, Rotation = rot or 90, Transparency = t })
end

function Kit.aspect(ratio)
	return Kit.h("UIAspectRatioConstraint", { AspectRatio = ratio or 1 })
end

function Kit.sizeLimit(minSize, maxSize)
	return Kit.h("UISizeConstraint", { MinSize = minSize or Vector2.zero, MaxSize = maxSize or Vector2.new(math.huge, math.huge) })
end

function Kit.scale(s)
	return Kit.h("UIScale", { Scale = s })
end

return Kit
