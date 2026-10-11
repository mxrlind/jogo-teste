-- Janelas modais em fila (porte de src/ui/modals.js + #modal, .sheet e .modal-x do styles.css).
-- Ctx.modal.show(conteúdo, cls, opts): conteúdo é uma lista de nós do Kit ou uma função que devolve uma
-- (a função é chamada de novo em replace() sem argumento e quando a janela volta da fila).
-- opts: priority (mostra já, empurrando a atual para a fila), closable (false esconde o X e o clique fora),
--       onClose, wide (.sheet.wide: 40rem em vez de 32rem).
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)

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
local AY = Enum.AutomaticSize.Y

local Modals = {}

local root = nil -- Frame da camada ReinoModal
local queue = {}
local cur = nil -- { content, opts }
local pendingConfirm = nil
local onCloseCb = nil
local sheetInst = nil
local contentInst = nil
local scaleInst = nil
local backdropInst = nil
local sizeConn = nil

local function resolve(content)
	if type(content) == "function" then
		local ok, r = pcall(content)
		if not ok then
			warn("Modal: falha ao montar o conteúdo: " .. tostring(r))
			return {}
		end
		return r or {}
	end
	return content or {}
end

-- ------------------------------------------------------------ peças de texto do .sheet (para Screens e os outros módulos)
-- .sheet > h2: ícone dourado 1.6rem + título 1.35rem (com espaço à direita para o X).
function Modals.h2(icon, text, o)
	o = o or {}
	return U.row({ gap = T.rem(0.55), wrap = false, justify = o.center and "center" or nil, props = { LayoutOrder = o.order } }, {
		icon and (type(icon) == "table" and icon or U.ico(icon, T.c.goldText, T.rem(1.6))) or nil,
		U.text(text, {
			bold = true, size = o.size or 1.35, wrap = true, lineHeight = 1.2,
			align = o.center and Enum.TextXAlignment.Center or nil,
			Size = UDim2.new(1, -(icon and T.rem(2.15) or 0) - (o.center and 0 or T.rem(2.6)), 0, 0),
			AutomaticSize = AY,
		}),
		Kit.pad(0, 0, T.rem(0.3), 0),
	})
end

-- .sheet h3: rótulo em caixa alta, 0,8rem, cinza, com margem em cima.
function Modals.h3(text, o)
	o = o or {}
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(o.top or T.rem(0.55), 0, 0, 0),
		U.text(upper(text), { bold = true, size = 0.8, color = T.c.muted, wrap = true }),
	})
end

-- p (texto rico, quebra de linha). o.muted, o.color, o.size, o.center, o.icon (ícone no começo).
function Modals.p(text, o)
	o = o or {}
	local color = o.color or (o.muted and T.c.muted or T.c.text)
	local label = U.text(text, {
		size = o.size or 1, color = color, wrap = true, lineHeight = o.lineHeight or 1.3, bold = o.bold,
		align = o.center and Enum.TextXAlignment.Center or nil, font = o.font,
	})
	if not o.icon then
		return label
	end
	return U.row({ gap = T.rem(0.35), align = "start", wrap = false }, {
		U.ico(o.icon, o.iconColor or color, math.floor(T.rem(o.size or 1) * 1.25 + 0.5)),
		U.text(text, {
			size = o.size or 1, color = color, wrap = true, lineHeight = o.lineHeight or 1.3, bold = o.bold,
			Size = UDim2.new(1, -T.rem(1.7), 0, 0), AutomaticSize = AY,
		}),
	})
end

function Modals.muted(text, o)
	o = o or {}
	o.muted = true
	return Modals.p(text, o)
end

-- .row: botões lado a lado com quebra.
function Modals.row(children, o)
	o = o or {}
	return U.row({ gap = T.rem(0.4), wrap = true, justify = o.justify, props = { LayoutOrder = o.order } }, children)
end

-- Espaço vertical (margens do CSS que a lista não cobre).
function Modals.gap(px)
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, px) })
end

-- ------------------------------------------------------------ desenho
local function viewport()
	local vp = root and root.AbsoluteSize or Vector2.new(1280, 720)
	if vp.X < 10 then
		vp = Vector2.new(1280, 720)
	end
	return vp
end

local function sheetWidth(wide)
	local vp = viewport()
	-- #modal tem padding 1rem: width: min(32rem, 100%).
	return math.min(T.rem(wide and 40 or 32), vp.X - T.rem(1) * 2)
end

-- Altura do .sheet: a do conteúdo, até 90% da tela (depois rola).
local function fitHeight()
	if not sheetInst or not contentInst then return end
	local vp = viewport()
	local w = sheetWidth(cur and cur.opts.wide)
	local hgt = math.min(contentInst.AbsoluteSize.Y, math.floor(vp.Y * 0.9))
	sheetInst.Size = UDim2.fromOffset(w, math.max(hgt, T.rem(4)))
end

local function render()
	if not root then return end
	if not cur then
		Kit.render(root, nil)
		sheetInst, contentInst, scaleInst, backdropInst = nil, nil, nil, nil
		return
	end
	local opts = cur.opts
	local closable = opts.closable ~= false
	local small = viewport().X <= T.BP_SMALL
	local padV, padH = small and T.rem(1) or T.rem(1.2), small and T.rem(1) or T.rem(1.3)
	local nodes = resolve(cur.content)
	local tree = h("Frame", { Name = "Modal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
		-- Fundo escuro: rgba(14, 12, 20, .74). Clique fora fecha (quando pode).
		h("TextButton", {
			Name = "Fundo",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = T.hex("#0e0c14"),
			BackgroundTransparency = 0.26,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			ref = function(inst)
				backdropInst = inst
			end,
			onClick = function()
				if cur and cur.opts.closable ~= false then
					Modals.close()
				end
			end,
		}),
		h("Frame", {
			Name = "Sheet",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
			ref = function(inst)
				sheetInst = inst
				inst.Size = UDim2.fromOffset(sheetWidth(opts.wide), T.rem(10))
			end,
		}, {
			h("UIScale", { ref = function(inst) scaleInst = inst end }),
			U.panel({ Size = UDim2.fromScale(1, 1) }, {
				-- Segura os cliques dentro da janela (não chegam ao fundo).
				h("TextButton", {
					Name = "Bloqueio", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1), ZIndex = 1,
				}),
				h("ScrollingFrame", {
					Name = "Rolagem",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = T.hex("#645a46"),
					ScrollBarImageTransparency = 0.65,
					ZIndex = 2,
				}, {
					h("Frame", {
						Name = "Conteudo",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = AY,
						ref = function(inst)
							contentInst = inst
							if sizeConn then sizeConn:Disconnect() end
							sizeConn = inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHeight)
						end,
					}, {
						Kit.pad(padV, padH, padV, padH),
						Kit.list("y", { gap = T.rem(0.45) }),
						nodes,
					}),
				}),
			}, { shadow = "lg", pad = false, layout = false }),
			-- .modal-x: botão pequeno no canto (top/right .7rem).
			closable and U.btn({
				icon = "close", small = true, iconOnly = true, key = "modal-x",
				props = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -T.rem(0.7), 0, T.rem(0.7)), ZIndex = 10, Name = "Fechar" },
				onClick = function()
					Ctx.run("closeModal")
				end,
			}) or nil,
		}),
	})
	Kit.render(root, tree)
	fitHeight()
end

-- Animações de entrada: fadein .2s do fundo e pop .28s (escala .92 e 8px abaixo) da janela.
local function animateIn()
	if Ctx.config.reduceMotion then return end
	if backdropInst then
		backdropInst.BackgroundTransparency = 1
		TweenService:Create(backdropInst, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.26 }):Play()
	end
	if scaleInst and sheetInst then
		scaleInst.Scale = 0.92
		sheetInst.Position = UDim2.new(0.5, 0, 0.5, 8)
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(scaleInst, info, { Scale = 1 }):Play()
		TweenService:Create(sheetInst, info, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end
end

-- ------------------------------------------------------------ API (igual a modals.js)
function Modals.isOpen()
	return cur ~= nil
end

function Modals.closable()
	return cur == nil or cur.opts.closable ~= false
end

-- show(conteúdo, cls?, opts?) como o showModal(html, cls, opts) do web; cls "wide" = .sheet.wide.
-- Também aceita show(conteúdo, opts) (opts.wide no lugar da classe).
function Modals.show(content, cls, opts)
	if type(cls) == "table" then
		opts, cls = cls, nil
	end
	opts = table.clone(opts or {})
	cls = cls or opts.cls
	if type(cls) == "string" and string.find(" " .. cls .. " ", " wide ", 1, true) then opts.wide = true end
	if cur and not opts.priority then
		table.insert(queue, { content, nil, opts })
		return
	end
	if cur and opts.priority then
		table.insert(queue, 1, { cur.content, nil, { closable = cur.opts.closable, wide = cur.opts.wide } })
	end
	cur = { content = content, opts = opts }
	onCloseCb = opts.onClose
	-- Janela nova do zero (a rolagem volta ao topo).
	Kit.render(root, nil)
	render()
	animateIn()
end

-- Troca o conteúdo da janela aberta sem fechar. Sem argumento, monta de novo o conteúdo atual.
function Modals.replace(content)
	if not cur then return end
	if content ~= nil then
		cur.content = content
	end
	render()
end

function Modals.close()
	if not cur then return end
	cur = nil
	pendingConfirm = nil
	local cb = onCloseCb
	onCloseCb = nil
	if cb then
		local ok, e = pcall(cb)
		if not ok then warn("Modal onClose: " .. tostring(e)) end
	end
	local nxt = table.remove(queue, 1)
	if nxt then
		Modals.show(nxt[1], nxt[2], nxt[3])
	else
		render()
	end
end

-- Confirmação: conteúdo + [Sim (primário ou perigo)] [Cancelar]. A função roda depois de fechar.
function Modals.confirm(content, fn, o)
	o = o or {}
	local yes = o.yes or "Confirmar"
	Modals.show(function()
		return {
			resolve(content),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
				Kit.pad(T.rem(0.6), 0, 0, 0),
				U.row({ gap = T.rem(0.4), wrap = true }, {
					U.btn({ text = yes, variant = o.danger and "danger" or "primary", onClick = Ctx.does("confirmYes") }),
					U.btn({ text = "Cancelar", onClick = Ctx.does("closeModal") }),
				}),
			}),
		}
	end, nil, { priority = true })
	pendingConfirm = fn
end

function Modals.runConfirm()
	local fn = pendingConfirm
	pendingConfirm = nil
	Modals.close()
	if fn then fn() end
end

function Modals.init(frame)
	root = frame
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if cur then
			render()
		end
	end)
	Ctx.modal = {
		show = Modals.show,
		replace = Modals.replace,
		close = Modals.close,
		confirm = Modals.confirm,
		runConfirm = Modals.runConfirm,
		isOpen = Modals.isOpen,
		closable = Modals.closable,
		-- Peças de texto do .sheet, para quem monta conteúdo de janela (confirmações de demolir, ascender...).
		h2 = Modals.h2, h3 = Modals.h3, p = Modals.p, muted = Modals.muted, row = Modals.row, gap = Modals.gap,
	}
	Ctx.actions.closeModal = function()
		Ctx.play("close", 0.5)
		Modals.close()
	end
	Ctx.actions.confirmYes = function()
		Modals.runConfirm()
	end
end

return Modals
