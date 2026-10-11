-- Telas e janelas do jogo (porte das partes de src/ui/app.js que não são o mapa nem os painéis):
-- carregamento, menu principal, abertura do reino, Como jogar, menu do jogo, Opções, Créditos, Save e backups,
-- recompensa diária, produção offline, recrutamento e o resumo da Ascensão (Ascension.luau).
-- Registra Ctx.show (as janelas que o Controller abre por evento) e as ações de tela em Ctx.actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local U = require(script.Parent.Ui)
local Ctx = require(script.Parent.Ctx)
local Assets = require(script.Parent.Assets)
local Audio = require(script.Parent.Audio)
local Modals = require(script.Parent.Modals)
local MapView = require(script.Parent.MapView)
local Ascension = require(script.Parent.Ascension)
local Side = require(script.Parent.Side)
local Sons = require(script.Parent.Sons)

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Util = require(Reino.Core.Util)
local Config = require(Reino.Core.Config)
local Storage = require(Reino.Core.Storage)
local Economy = require(Reino.Core.Economy)
local Cosmetics = require(Reino.Data.Cosmetics)
local HeroData = require(Reino.Data.Heroes)

local h = Kit.h
local rem = T.rem
local hex = T.hex
local AY, AXY = Enum.AutomaticSize.Y, Enum.AutomaticSize.XY
local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local fmt, fmtTime = Util.fmt, Util.fmtTime
local esc = U.esc

local Screens = {}

local ui = Ctx.ui
local frames = {}
local menuBg, menuUi = nil, nil
local menuRenderer, menuGrid = nil, nil

local preloadDone = false
local stateReady = false
local loadPct = 0
local loadText = "Carregando..."
local loadFill = nil
local loadLogo = nil
local menuCard = nil

local pendingOffline = nil -- produção offline que chegou antes de entrar no jogo
local optionsOpen = false
local drag = nil -- slider sendo arrastado: { key, min, max, inst }
local introName, introBanner = "", nil
local importText = ""

-- Animações por quadro (Screens.frame).
local anim = { recruit = nil, today = nil }

-- text-transform: uppercase com os acentos do português (string.upper só mexe em ASCII).
local ACC = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function upper(s)
	s = string.upper(s)
	for a, b in ACC do
		s = string.gsub(s, a, b)
	end
	return s
end

local function motion()
	return not Ctx.config.reduceMotion
end

local function play(name, vol)
	Ctx.play(name, vol)
end

local function toast(text, kind, icon)
	Ctx.toast(text, kind, icon)
end

local function hasSave()
	return Ctx.server ~= nil and Ctx.server.hasSave == true and Ctx.game ~= nil
end

local ITALIC = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)

-- Ícones de game-icons.net e o autor de cada um (assets/icons/game-icons/credits.json).
local ICON_CREDITS = {
	["gold"] = "delapouite", ["food"] = "lorc", ["wood"] = "delapouite", ["stone"] = "lorc",
	["gems"] = "lorc", ["crowns"] = "delapouite", ["pop"] = "delapouite", ["happiness"] = "skoll",
	["defense"] = "lorc", ["raid"] = "lorc", ["time"] = "lorc", ["build"] = "lorc",
	["upgrade"] = "delapouite", ["map"] = "lorc", ["trophy"] = "delapouite", ["settings"] = "lorc",
	["scroll"] = "lorc", ["castle"] = "delapouite", ["hero-farmer"] = "delapouite", ["hero-archer"] = "delapouite",
	["hero-wizard"] = "delapouite", ["hero-dwarf"] = "delapouite", ["hero-elf"] = "delapouite", ["hero-dragon"] = "lorc",
	["hero-queen"] = "lorc", ["hero-guard"] = "delapouite", ["hero-explorer"] = "lorc", ["hero-bard"] = "delapouite",
	["hero-clock"] = "skoll", ["hero-woodcutter"] = "lorc", ["hero-mason"] = "delapouite", ["hero-collector"] = "lorc",
	["hero-merchant"] = "delapouite", ["hero-architect"] = "lorc", ["hero-knight"] = "lorc", ["hero-alchemist"] = "lorc",
	["hero-druid"] = "lorc", ["talent-harvest"] = "delapouite", ["talent-inheritance"] = "lorc", ["talent-walls"] = "delapouite",
	["talent-vigil"] = "lorc", ["talent-engineering"] = "delapouite", ["talent-mining"] = "delapouite", ["talent-round-table"] = "delapouite",
	["talent-butler"] = "lorc", ["season-foundation"] = "delapouite", ["season-war"] = "lorc", ["season-expansion"] = "lorc",
	["season-catastrophe"] = "lorc", ["event-harvest"] = "delapouite", ["event-gold-rush"] = "willdabeast", ["event-work"] = "lorc",
	["event-inspiration"] = "delapouite", ["event-blood-moon"] = "lorc", ["event-caravan"] = "delapouite", ["emblem-lion"] = "lorc",
	["emblem-tree"] = "lorc", ["emblem-wolf"] = "lorc", ["emblem-eagle"] = "lorc", ["emblem-rose"] = "lorc",
	["emblem-skull"] = "lorc", ["emblem-shield"] = "sbed", ["banner"] = "lorc", ["move"] = "delapouite",
	["demolish"] = "lorc", ["clear"] = "delapouite", ["close"] = "sbed", ["check"] = "delapouite",
	["lock"] = "lorc", ["warning"] = "lorc", ["menu"] = "delapouite", ["speaker"] = "delapouite",
	["speaker-off"] = "delapouite", ["music"] = "delapouite", ["calendar"] = "delapouite", ["mission"] = "delapouite",
	["star"] = "delapouite", ["boost"] = "delapouite", ["tab-heroes"] = "lorc", ["tab-social"] = "delapouite",
	["tab-profile"] = "lorc", ["stats"] = "delapouite", ["info"] = "delapouite", ["copy"] = "lorc",
	["visit"] = "lorc", ["greet"] = "delapouite", ["trade"] = "lorc", ["save"] = "delapouite",
	["speedup"] = "lorc", ["cart"] = "delapouite", ["keyboard"] = "delapouite", ["play"] = "guard13007",
	["exit"] = "delapouite", ["expedition"] = "lorc", ["sun"] = "lorc", ["contrast"] = "delapouite",
	["font"] = "lorc", ["motion"] = "lorc", ["house"] = "delapouite", ["people"] = "delapouite",
	["heart"] = "skoll", ["swords"] = "lorc", ["tool-pickaxe"] = "lorc",
}
local AUTHOR_NAMES = { lorc = "Lorc", delapouite = "Delapouite", skoll = "Skoll", sbed = "Sbed", willdabeast = "Willdabeast", guard13007 = "Guard13007" }
-- Ordem em que os autores aparecem no credits.json (Object.entries do web).
local AUTHOR_ORDER = { "delapouite", "lorc", "skoll", "willdabeast", "sbed", "guard13007" }
-- Pacotes de efeitos (assets/sfx/credits.json, sem o "Kenney – ").
local SFX_PACKS = { "Interface Sounds", "Impact Sounds", "RPG Audio", "Music Jingles" }

-- ================================================================ peças de janela
local h2 = Modals.h2
local h3 = function(text, o)
	o = o or {}
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(o.top or rem(0.55), 0, 0, 0),
		U.text(upper(text), { bold = true, size = 0.8, color = T.c.muted, wrap = true }),
	})
end
local p = Modals.p
local muted = Modals.muted
local mrow = Modals.row

-- .sheet label: display block; margin .7rem 0 .3rem; negrito. Aceita ícone no começo.
local function label(text, icon)
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(rem(0.25), 0, 0, 0),
		U.row({ gap = rem(0.3), wrap = false }, {
			icon and U.ico(icon, T.c.text, rem(1.25)) or nil,
			U.text(text, { bold = true, wrap = true, Size = UDim2.new(1, icon and -rem(1.6) or 0, 0, 0), AutomaticSize = AY }),
		}),
	})
end

local function bigBtn(o)
	o.big = true
	o.width = o.width or UDim.new(1, 0)
	return U.btn(o)
end

-- Botão grande do .sheet .stack (alinhado à esquerda, ícone 1.4rem).
local function stackBtn(o)
	o.justify = "start"
	o.iconSize = rem(1.4)
	return bigBtn(o)
end

-- ul.intro: ícone verde 1.5rem + texto.
local function introList(items)
	local rows = {}
	for _, it in items do
		table.insert(rows, U.row({ gap = rem(0.65), align = "start", wrap = false }, {
			U.ico(it[1], T.c.grass, rem(1.5)),
			U.text(it[2], { wrap = true, lineHeight = 1.3, Size = UDim2.new(1, -rem(2.2), 0, 0), AutomaticSize = AY }),
		}))
	end
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(rem(0.3), 0, rem(0.3), 0),
		Kit.list("y", { gap = rem(0.55) }),
		rows,
	})
end

-- ul.credits: lista com marcador, .85rem.
local function creditList(items)
	local rows = {}
	for _, it in items do
		table.insert(rows, U.row({ gap = rem(0.4), align = "start", wrap = false }, {
			U.text("•", { size = 0.85 }),
			U.text(it, { size = 0.85, wrap = true, lineHeight = 1.3, Size = UDim2.new(1, -rem(1.1), 0, 0), AutomaticSize = AY }),
		}))
	end
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.pad(rem(0.2), 0, rem(0.2), rem(0.4)),
		Kit.list("y", { gap = rem(0.25) }),
		rows,
	})
end

-- input[type=text] / textarea: borda --line de 2px, raio 10, foco dourado.
local function textBox(o)
	local multi = o.multi == true
	local lineH = math.floor(T.rem(o.size or 1) * 1.45 + 0.5)
	return h("TextBox", {
		key = o.key,
		Name = o.name,
		BackgroundColor3 = T.c.white,
		Text = o.text or "",
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = hex("#8d8798"),
		ClearTextOnFocus = false,
		MultiLine = multi,
		TextWrapped = multi,
		TextEditable = o.editable ~= false,
		TextXAlignment = LEFT,
		TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		FontFace = T.font,
		TextSize = rem(o.size or 1),
		TextColor3 = T.c.text,
		Size = UDim2.new(1, 0, 0, o.height or (lineH + rem(1) + 4)),
		ClipsDescendants = true,
		onText = o.onText,
		ref = function(inst)
			local stroke = inst:FindFirstChildOfClass("UIStroke")
			inst.Focused:Connect(function()
				if stroke then stroke.Color = T.c.gold end
				if o.onFocus then o.onFocus(inst) end
			end)
			inst.FocusLost:Connect(function()
				if stroke then stroke.Color = T.c.line end
			end)
		end,
	}, {
		Kit.corner(10),
		Kit.stroke(T.c.line, 2, 0),
		Kit.pad(rem(0.5), rem(0.7)),
	})
end

-- Sem área de transferência no Roblox: o texto vai numa caixa selecionável (o "Copie manualmente" do web).
local function copyText(text)
	local box = textBox({
		name = "Codigo", text = text, multi = true, size = 0.75, height = rem(7),
		-- precisa ser editável para dar para selecionar; o texto volta se for mexido
		onText = function(v, inst)
			if v ~= text then inst.Text = text end
		end,
		onFocus = function(inst)
			task.defer(function()
				inst.CursorPosition = #text + 1
				inst.SelectionStart = 1
			end)
		end,
	})
	Modals.show({
		h2("copy", "Copie manualmente"),
		box,
		muted("Toque na caixa para selecionar tudo e copie (Ctrl+C no computador; no celular, toque e segure).", { size = 0.9 }),
		mrow({ U.btn({ text = "Fechar", onClick = Ctx.does("closeModal") }) }),
	}, "", { priority = true })
end

local function confirm(nodes, fn, o)
	Modals.confirm(nodes, function()
		task.spawn(fn)
	end, o)
end

-- ================================================================ preferências
local function setCfg(k, v, noSave)
	local c = Util.deepCopy(Ctx.config)
	c[k] = v
	Ctx.setConfig(c, noSave)
end

-- input[type=range]: trilho com a parte cheia dourada (accent-color) e o botão redondo.
local KNOB = 18
local function sliderValue(inst, x, lo, hi)
	local w = math.max(1, inst.AbsoluteSize.X - KNOB)
	local f = math.clamp((x - inst.AbsolutePosition.X - KNOB / 2) / w, 0, 1)
	local v = lo + f * (hi - lo)
	return math.clamp(math.floor(v / 5 + 0.5) * 5, lo, hi)
end

local function applySlider(k, v)
	local cur = Util.round(Ctx.config[k] * 100)
	if cur == v then return end
	-- Enquanto arrasta, só aplica aqui; manda para o servidor ao soltar (o limite é 30 ações por segundo).
	setCfg(k, v / 100, true)
	if k == "sfxVolume" or k == "masterVolume" then play("click") end
end

local function slider(k, text, lo, hi, icon)
	local c = Ctx.config
	local v = Util.round(c[k] * 100)
	local f = (v - lo) / (hi - lo)
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		Kit.list("y", { gap = rem(0.3) }),
		label(string.format("%s: %d%%", text, v), icon),
		h("TextButton", {
			Name = "Slider-" .. k,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, KNOB + 4),
			onDown = function(input, inst)
				drag = { key = k, min = lo, max = hi, inst = inst }
				applySlider(k, sliderValue(inst, input.Position.X, lo, hi))
			end,
		}, {
			h("Frame", {
				BackgroundColor3 = hex("#d6cfc0"),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, KNOB / 2, 0.5, 0),
				Size = UDim2.new(1, -KNOB, 0, 6),
			}, {
				Kit.corner(99),
				h("Frame", { BackgroundColor3 = T.c.gold, Size = UDim2.fromScale(f, 1), BorderSizePixel = 0 }, { Kit.corner(99) }),
			}),
			h("Frame", {
				BackgroundColor3 = T.c.gold,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(f, KNOB / 2 - f * KNOB, 0.5, 0),
				Size = UDim2.fromOffset(KNOB, KNOB),
				ZIndex = 2,
			}, { Kit.corner(99), Kit.stroke(T.c.white, 2, 0) }),
		}),
	})
end

local function check(k, text)
	return U.check({
		key = "chk-" .. k,
		checked = Ctx.config[k] == true,
		text = text,
		onClick = function()
			setCfg(k, not Ctx.config[k])
		end,
	})
end

-- ================================================================ carregamento
local function renderLoading()
	local f = frames.loading
	if not f then return end
	local w = math.min(360, math.floor(Ctx.vp.X * 0.8))
	Kit.render(f, h("Frame", { BackgroundColor3 = T.c.ink, Size = UDim2.fromScale(1, 1) }, {
		-- radial-gradient(60% 50% at 50% 45%, #3a3546 0%, var(--ink) 75%)
		U.sprite("ui/glow", UDim2.fromScale(1.2, 1.0), {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
			ImageColor3 = hex("#3a3546"), ScaleType = Enum.ScaleType.Stretch,
		}),
		h("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(math.max(w, 320), 0), AutomaticSize = AY, ZIndex = 2,
		}, {
			Kit.list("y", { gap = 0, align = "center" }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(112, 112) }, {
				U.sprite("logo-castelo", 112, { ref = function(inst) loadLogo = inst end }),
			}),
			-- h1 com text-shadow: 0 3px 0 rgba(0,0,0,.35)
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
				Kit.pad(rem(0.4), 0, rem(0.5), 0),
				U.text("Reino de Bolso", {
					bold = true, size = 2.2, color = T.c.black, transparency = 0.65, align = CENTER, wrap = true,
					Position = UDim2.fromOffset(0, 3), ZIndex = 1,
				}),
				U.text("Reino de Bolso", {
					bold = true, size = 2.2, color = T.c.onInk, align = CENTER, wrap = true, ZIndex = 2,
					Position = UDim2.fromOffset(0, 0),
				}),
			}),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 12 + rem(1.8)) }, {
				h("Frame", {
					BackgroundColor3 = T.c.black, BackgroundTransparency = 0.65, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, 12), ClipsDescendants = true,
				}, {
					Kit.corner(99),
					h("Frame", {
						BackgroundColor3 = T.c.white, BorderSizePixel = 0, Size = UDim2.fromScale(loadPct / 100, 1),
						ref = function(inst) loadFill = inst end,
					}, {
						Kit.corner(99),
						h("UIGradient", {
							Rotation = 90,
							Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0, T.c.goldHi), ColorSequenceKeypoint.new(0.6, T.c.gold),
								ColorSequenceKeypoint.new(1, hex("#d99a14")),
							}),
						}),
					}),
				}),
			}),
			U.text(loadText, { size = 0.9, color = T.c.onInkMuted, align = CENTER, wrap = true }),
		}),
	}))
end

local function setProgress(pct)
	loadPct = pct
	loadText = string.format("Carregando assets... %d%%", pct)
	renderLoading()
	if loadFill then
		local goal = { Size = UDim2.fromScale(pct / 100, 1) }
		if motion() then
			TweenService:Create(loadFill, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), goal):Play()
		else
			loadFill.Size = goal.Size
		end
	end
end

-- ================================================================ menu principal
local function drawMenuMap()
	if not menuRenderer or not menuGrid or ui.screen ~= "menu" then return end
	task.defer(function()
		if menuRenderer and menuGrid then
			menuRenderer:draw({ state = { grid = menuGrid } }, 0)
		end
	end)
end

local function renderMenu(animate)
	if not menuUi then return end
	local has = hasSave()
	local st = has and Ctx.game.state or nil
	local w = math.min(420, Ctx.vp.X - 32)
	local half = UDim.new(0.5, -math.ceil(rem(0.4) / 2))
	local tip = "Formato de save v" .. tostring(Storage.WEB_SAVE_VERSION) .. (Audio.hasMusic() and "" or " · nenhuma música instalada")
	Kit.render(menuUi, h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
		-- #menuMap { filter: brightness(.55) }: véu preto por cima do mapa (blur não existe na interface do Roblox)
		h("Frame", { Name = "Veu", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1 }),
		-- vinheta: radial-gradient(70% 70% at 50% 50%, transparent 30%, rgba(14,12,20,.75) 100%)
		U.sprite("ui/vignette", UDim2.fromScale(1.45, 1.45), {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 0.25, ZIndex = 1,
		}),
		h("Frame", {
			Name = "MenuCard",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, 0),
			AutomaticSize = AY,
			ZIndex = 2,
			ref = function(inst) menuCard = inst end,
		}, {
		h("UIScale", { Scale = 1 }),
		U.panel({ Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			-- logo por cima da borda: margin: -4.2rem auto -.2rem (104 px)
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(104, math.max(0, 104 - rem(4.2) - rem(0.2))) }, {
				U.sprite("logo-castelo", 104, { Position = UDim2.fromOffset(0, -rem(4.2)), ZIndex = 3 }),
			}),
			U.text("Reino de Bolso", { bold = true, size = 2.3, align = CENTER, wrap = true, lineHeight = 1.2 }),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
				Kit.pad(rem(0.25), 0, rem(1.1), 0),
				U.text("Um reino de bolso onde a posição de cada prédio importa.", { color = T.c.muted, align = CENTER, wrap = true, lineHeight = 1.3 }),
			}),
			U.col({ gap = rem(0.55) }, {
				has and bigBtn({ text = "Continuar: " .. esc(st.kingdom.name), icon = "play", variant = "primary", onClick = Ctx.does("continue") }) or nil,
				bigBtn({ text = "Novo reino", icon = "build", variant = has and "grey" or "primary", onClick = Ctx.does("newGame") }),
				bigBtn({ text = "Como jogar", icon = "info", onClick = Ctx.does("howTo") }),
				U.row({ gap = rem(0.4), wrap = false }, {
					U.btn({ text = "Opções", icon = "settings", width = half, onClick = Ctx.does("options") }),
					U.btn({ text = "Créditos", icon = "scroll", width = half, onClick = Ctx.does("credits") }),
				}),
			}),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
				Kit.pad(rem(1) - rem(0.5), 0, 0, 0),
				h("TextLabel", {
					BackgroundTransparency = 1, Text = "Versão " .. Ctx.VERSION, FontFace = T.font, TextSize = rem(0.75),
					TextColor3 = T.c.muted, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, tip = tip,
				}),
			}),
		}, { shadow = "md", pad = Kit.pad(rem(1.4), rem(1.5), rem(1.1), rem(1.5)), layout = Kit.list("y", { gap = rem(0.5), align = "center" }) }),
		}),
	}))
	-- .menu-card: animation: rise .5s (sobe 14 px e cresce de .98). Sem opacidade: precisaria de CanvasGroup.
	if animate and menuCard and motion() then
		local sc = menuCard:FindFirstChildOfClass("UIScale")
		menuCard.Position = UDim2.new(0.5, 0, 0.5, 14)
		local info = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		TweenService:Create(menuCard, info, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
		if sc then
			sc.Scale = 0.98
			TweenService:Create(sc, info, { Scale = 1 }):Play()
		end
	end
end

local function showMainMenu()
	Ctx.setScreen("menu")
	renderMenu(true)
	-- O fundo é o mapa do próprio reino (ou o de um vizinho), parado e escurecido; só redesenha ao mudar de tamanho.
	if hasSave() then
		menuGrid = Ctx.game.state.grid
	else
		local C = Ctx.controller
		menuGrid = C and C.rivalGrid({ seed = Util.hashString("rival-7-6"), tier = 6 }) or nil
	end
	if not menuRenderer then
		menuRenderer = MapView.new(menuBg, { fill = "cover", getConfig = function() return Ctx.config end, onResize = drawMenuMap })
	end
	menuRenderer.view = { grid = menuGrid }
	drawMenuMap()
end

-- ================================================================ janelas
local function showIntro()
	local free = Util.filter(Cosmetics.BANNERS, function(b) return b.free end)
	introName = ""
	introBanner = free[1] and free[1].id
	Modals.show(function()
		local sw = {}
		for _, b in free do
			local on = introBanner == b.id
			table.insert(sw, h("TextButton", {
				key = b.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(50, 50),
				tip = b.name,
				onClick = function()
					introBanner = b.id
					play("click", 0.6)
					Modals.replace()
				end,
			}, {
				-- outline: 3px solid var(--gold); outline-offset: 2px
				h("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(50, 50) }, {
					Kit.corner(14), Kit.stroke(T.c.gold, 3, on and 0 or 1),
				}),
				h("Frame", {
					BackgroundColor3 = hex(b.color), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(42, 42),
				}, {
					Kit.corner(10),
					h("Frame", { BackgroundColor3 = T.c.white, BackgroundTransparency = 0.8, Size = UDim2.fromScale(1, 0.6) }, {
						Kit.corner(10), Kit.grad({ T.c.white, T.c.white }, 90, { { 0, 0 }, { 1, 1 } }),
					}),
					h("Frame", { BackgroundColor3 = T.c.black, BackgroundTransparency = 0.8, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3) }),
				}),
			}))
		end
		return {
			h2(U.resIco("crowns", rem(1.6)), "Funde o seu reino"),
			p("Você herdou um terreno, uma casa e uma fazenda. O resto é com você."),
			introList({
				{ "hero-architect", "<b>A posição importa:</b> cada prédio ganha (ou perde) bônus dos 4 vizinhos. Escolha um prédio e passe pelo mapa para ver." },
				{ "swords", "<b>Hordas atacam</b> sempre por um lado anunciado. Defenda esse lado: se perder, elas quebram construções, e o que não for consertado até a próxima derrota vira ruína." },
				{ "tab-heroes", "<b>Novas abas aparecem</b> conforme o reino cresce: heróis, temporada, social e legado." },
				{ "time", "O reino <b>produz mesmo com você fora</b>. Entre 5 minutos ou fique 2 horas." },
			}),
			label("Nome do reino"),
			textBox({
				key = "introName", name = "NomeDoReino", text = introName, placeholder = "Reino de Bolso",
				onText = function(v, inst)
					-- maxlength="24"
					if utf8.len(v) and utf8.len(v) > 24 then
						v = string.sub(v, 1, utf8.offset(v, 25) - 1)
						inst.Text = v
					end
					introName = v
				end,
			}),
			label("Estandarte"),
			U.row({ gap = rem(0.45), wrap = true }, sw),
			Modals.gap(rem(0.2)),
			bigBtn({ text = "Fundar meu reino", icon = "build", variant = "primary", onClick = Ctx.does("startKingdom") }),
		}
	end, "", { closable = false })
end

local function showHowTo()
	Modals.show({
		h2("info", "Como jogar"),
		introList({
			{ "build", "Escolha um prédio na paleta e toque no mapa. No celular, o primeiro toque mostra a prévia e o segundo constrói. Errou o lugar? Você tem 5 segundos para desfazer." },
			{ "hero-architect", "Os números verdes e vermelhos mostram o bônus de cada vizinho, e a dica no topo mostra quanto o prédio vai render ali." },
			{ "people", "Casas trazem moradores; prédios precisam de trabalhadores. Falta de gente reduz toda a produção." },
			{ "swords", "A próxima horda sempre diz de que lado vem. Torres e muralhas perto daquela borda contam inteiras." },
			{ "cart", "Carroças do mercador aparecem no mapa por 20 segundos: toque nelas." },
			{ "crowns", "Quando o crescimento desacelerar, ascenda: recomece num mapa novo com bônus permanentes." },
			-- No Roblox o Esc abre o menu do próprio Roblox: o texto mostra a tecla do menu configurada.
			{ "keyboard", string.format("Teclado: setas movem o cursor, Enter confirma, 1 a 9 escolhem prédios, %s abre o menu. Tudo remapeável em Opções.", esc(Config.keyLabel(Ctx.config.keys.menu))) },
		}),
		bigBtn({ text = "Entendi", variant = "primary", onClick = Ctx.does("closeModal") }),
	}, "", { priority = true })
end

local function showGameMenu()
	play("open", 0.6)
	Modals.show({
		h2("menu", "Menu"),
		U.col({ gap = rem(0.5) }, {
			stackBtn({ text = "Continuar", icon = "play", variant = "primary", onClick = Ctx.does("closeModal") }),
			stackBtn({ text = "Opções", icon = "settings", onClick = Ctx.does("options") }),
			stackBtn({ text = "Save e backups", icon = "save", onClick = Ctx.does("saveMenu") }),
			stackBtn({ text = "Como jogar", icon = "info", onClick = Ctx.does("howTo") }),
			stackBtn({ text = "Créditos", icon = "scroll", onClick = Ctx.does("credits") }),
			stackBtn({ text = "Salvar e voltar ao menu principal", icon = "exit", onClick = Ctx.does("toMainMenu") }),
		}),
	})
end

local function optionsContent()
	local c = Ctx.config
	local keys = {}
	for _, a in Config.KEY_ACTIONS do
		local on = ui.remapping == a.id
		table.insert(keys, U.row({ gap = rem(0.6), wrap = false, props = { LayoutOrder = #keys + 1 } }, {
			U.text(a.label, { size = 0.9, wrap = true, Size = UDim2.new(1, -rem(9.5), 0, 0), AutomaticSize = AY }),
			U.spacer(),
			U.btn({
				small = true, variant = on and "primary" or "grey",
				text = on and "Pressione uma tecla..." or esc(Config.keyLabel(c.keys[a.id] or "")),
				onClick = function() Ctx.run("remap", a.id) end,
			}),
		}))
	end
	local m = Audio.nowPlaying()
	local music = Audio.hasMusic()
	return {
		h2("settings", "Opções"),
		h3("Som"),
		slider("masterVolume", "Volume geral", 0, 100, "speaker"),
		music and check("musicOn", "Tocar música") or nil,
		slider("musicVolume", "Música", 0, 100, "music"),
		music and muted((m and string.format("Tocando: %s (%s, %s). ", esc(m.title), esc(m.author), esc(m.license)) or "")
			.. "Folk de taverna na vila; metal quando uma horda se aproxima e no subsolo.")
			or muted("Nenhuma faixa de música instalada."),
		slider("sfxVolume", "Efeitos", 0, 100, "speaker"),
		check("muteInBackground", "Silenciar quando o jogo estiver em segundo plano"),
		h3("Jogo"),
		check("confirmDemolish", "Pedir confirmação antes de demolir"),
		check("batterySaver", "Modo economia de bateria (mapa a 30 quadros por segundo)"),
		-- "Jogar em tela cheia" não existe no Roblox (a tela cheia é do próprio Roblox): o botão fica escondido,
		-- como no web quando document.fullscreenEnabled é falso.
		h3("Visual e acessibilidade"),
		slider("fontScale", "Tamanho do texto", 85, 150, "font"),
		check("villagers", "Moradores andando pelo mapa"),
		check("particles", "Partículas e números flutuantes"),
		check("reduceMotion", "Reduzir movimento (sem tremor, flash nem animações)"),
		check("highContrast", "Alto contraste"),
		h3("Teclado"),
		U.col({ gap = rem(0.3) }, keys),
		mrow({ U.btn({ text = "Restaurar teclas padrão", small = true, onClick = Ctx.does("resetKeys") }) }),
		h3("Padrões"),
		mrow({ U.btn({ text = "Restaurar todas as opções (menos as teclas)", small = true, onClick = Ctx.does("resetOptions") }) }),
		Modals.gap(rem(0.2)),
		bigBtn({ text = "Fechar", variant = "primary", onClick = Ctx.does("closeModal") }),
	}
end

local function showOptions(replace)
	if replace and Modals.isOpen() and optionsOpen then
		Modals.replace()
		return
	end
	optionsOpen = true
	Modals.show(optionsContent, "", {
		priority = true,
		onClose = function()
			optionsOpen = false
			ui.remapping = nil
		end,
	})
end

local function showCredits()
	local byAuthor = {}
	for _, a in ICON_CREDITS do
		byAuthor[a] = (byAuthor[a] or 0) + 1
	end
	local authors = {}
	for _, a in AUTHOR_ORDER do
		if byAuthor[a] then
			table.insert(authors, string.format("<b>%s</b> (%d)", AUTHOR_NAMES[a] or esc(a), byAuthor[a]))
		end
	end
	local packs = {}
	for _, pk in SFX_PACKS do
		table.insert(packs, "<b>" .. esc(pk) .. "</b>")
	end
	-- Música: as faixas do jogo (Sons.luau), agrupadas por autor e licença.
	local groups, order = {}, {}
	for _, m in { "vila", "batalha" } do
		for _, t in Sons.musica[m] or {} do
			local k = t.author .. "|" .. t.license
			if not groups[k] then
				groups[k] = { author = t.author, license = t.license, titles = {} }
				table.insert(order, k)
			end
			table.insert(groups[k].titles, "<b>" .. esc(t.title) .. "</b>")
		end
	end
	local sound = { table.concat(packs, ", ") .. ", por Kenney (kenney.nl). Licença CC0 1.0." }
	for _, k in order do
		local gr = groups[k]
		table.insert(sound, string.format("Música: %s, por %s (OpenGameArt). Licença %s.", table.concat(gr.titles, ", "), esc(gr.author), esc(gr.license)))
	end
	if #order == 0 then table.insert(sound, "Música: nenhuma instalada.") end
	Modals.show({
		h2("scroll", "Créditos"),
		p(string.format("<b>Reino de Bolso</b>, versão %s.", Ctx.VERSION)),
		h3("Arte"),
		creditList({
			"Prédios e natureza do mapa: <b>KayKit Medieval Hexagon Pack</b>, por Kay Lousberg (kaylousberg.com). Licença CC0 1.0. Modelos 3D renderizados como imagens 2D.",
			"Moradores, invasores e carroça: <b>Medieval RTS</b>; interface: <b>UI Pack</b>. Por Kenney (kenney.nl). Licença CC0 1.0.",
			"Ícones de <b>game-icons.net</b>, licença <b>CC BY 3.0</b> (creativecommons.org/licenses/by/3.0). Icons made by " .. table.concat(authors, ", ") .. ". Cores alteradas e fundo removido.",
			"Fonte <b>Nunito</b>, por The Nunito Project Authors. SIL Open Font License 1.1.",
		}),
		h3("Som"),
		creditList(sound),
		muted("Lista completa, arquivo por arquivo, no ASSETS.md do repositório."),
		bigBtn({ text = "Fechar", variant = "primary", onClick = Ctx.does("closeModal") }),
	}, "", { priority = true })
end

local function fmtDate(ms)
	local ok, s = pcall(function()
		return DateTime.fromUnixTimestampMillis(ms):FormatLocalTime("DD/MM/YYYY, HH:mm:ss", "pt-br")
	end)
	return ok and s or ""
end

local function showSaveMenu()
	local r = Ctx.call("listBackups")
	local backups = (r and r.ok and r.backups) or {}
	local slots = (r and r.slots) or Storage.BACKUP_SLOTS
	importText = ""
	local rows = {}
	for _, b in backups do
		if b.broken then
			table.insert(rows, muted(string.format("Slot %d: danificado", b.slot + 1)))
		else
			table.insert(rows, mrow({
				U.text(string.format("%s · %s · %s de ouro", esc(b.name or ""), fmtDate(b.at or 0), fmt(b.gold or 0)), {
					wrap = true, Size = UDim2.new(1, -rem(6.5), 0, 0), AutomaticSize = AY,
				}),
				U.btn({ text = "Restaurar", small = true, onClick = function() Ctx.run("restoreBackup", b.slot) end }),
			}))
		end
	end
	if #rows == 0 then
		rows = { muted("Nenhum backup ainda (o primeiro é feito na primeira gravação).") }
	end
	Modals.show({
		h2("save", "Save e backups"),
		-- O servidor do Roblox salva a cada minuto (o web salva a cada 10 s no navegador).
		muted(string.format("O jogo salva sozinho a cada minuto e guarda %d backups em rodízio (um a cada 5 minutos).", slots)),
		h3("Exportar"),
		mrow({ U.btn({ text = "Copiar código do save", icon = "copy", onClick = Ctx.does("exportSave") }) }),
		h3("Importar"),
		textBox({
			key = "saveCode", name = "CodigoDoSave", multi = true, size = 0.75, height = rem(7),
			placeholder = "Cole aqui um código de save",
			onText = function(v) importText = v end,
		}),
		mrow({ U.btn({ text = "Importar", icon = "save", onClick = Ctx.does("importSave") }) }),
		h3("Backups automáticos"),
		rows,
		h3("Zona de perigo"),
		mrow({ U.btn({ text = "Apagar o reino atual", icon = "demolish", variant = "danger", onClick = Ctx.does("hardReset") }) }),
		mrow({ bigBtn({ text = "Fechar", variant = "primary", onClick = Ctx.does("closeModal") }) }),
	}, "", { priority = true })
end

-- Grade de colunas iguais (display: grid; repeat(n, 1fr)): lista com quebra e itens esticados na linha.
local function grid(items, cols, gap)
	local list = {}
	for _, it in items do
		local pr = table.clone(it.props)
		pr.Size = UDim2.new(1 / cols, -math.ceil(gap * (cols - 1) / cols) - 1, 0, 0)
		table.insert(list, h(it.class, pr, it.children))
	end
	return h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
		h("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder, ItemLineAlignment = Enum.ItemLineAlignment.Stretch,
		}),
		list,
	})
end

local function showDaily()
	local g = Ctx.game
	if not g then return end
	local st = g:dailyStatus()
	local streak = g.state.daily.streak
	anim.today = nil
	local cells = {}
	for _, r in Cosmetics.DAILY_REWARDS do
		local cur = ((st.available and st.nextStreak or streak) - 1) % 7 + 1
		local done = (st.available and r.day < cur) or (not st.available and r.day <= cur)
		local today = st.available and r.day == cur
		local icon
		local s = rem(1.4)
		if done then
			icon = U.ico("check", T.c.good, s)
		elseif r.gems then
			icon = U.resIco("gems", s)
		elseif r.boost then
			icon = U.ico("boost", T.res.gold, s)
		elseif r.scroll then
			icon = U.ico("scroll", T.res.crowns, s)
		else
			icon = U.resIco("gold", s)
		end
		local fade = done and 0.5 or 0
		table.insert(cells, h("Frame", { BackgroundTransparency = 1, AutomaticSize = AY }, {
			h("Frame", {
				BackgroundColor3 = T.c.white, BackgroundTransparency = fade, Size = UDim2.fromScale(1, 0), AutomaticSize = AY,
				ref = today and function(inst) anim.today = inst end or nil,
			}, {
				Kit.corner(10),
				Kit.stroke(today and T.c.gold or T.c.line, today and 2 or 1, fade),
				today and Kit.grad({ hex("#fff6d6"), hex("#fde9b0") }, 90) or nil,
				Kit.pad(rem(0.4), rem(0.1)),
				Kit.list("y", { gap = rem(0.2), align = "center" }),
				U.text("Dia " .. r.day, { bold = true, size = 0.72, color = today and T.c.goldText or T.c.muted, transparency = fade, align = CENTER, wrap = true }),
				icon,
				U.text(r.label, { size = 0.68, lineHeight = 1.2, align = CENTER, wrap = true, transparency = fade }),
			}),
		}))
	end
	local cols = Ctx.vp.X <= T.BP_SMALL and 4 or 7
	local shieldText = st.shield and "Você faltou ontem, mas o escudo da semana salva a sua sequência."
		or st.shieldReady and "Escudo da semana pronto: se faltar um dia, a sequência não zera."
		or "Escudo da semana já usado; volta na segunda."
	Modals.show({
		h2("calendar", "Recompensa diária"),
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.pad(rem(0.3), 0, rem(0.5), 0),
			grid(cells, cols, rem(0.3)),
		}),
		muted(shieldText, { icon = "defense" }),
		st.available and bigBtn({ text = "Resgatar: " .. st.reward.label, variant = "primary", onClick = Ctx.does("daily") }) or nil,
		(not st.available) and muted("Já resgatada hoje. Volte amanhã para manter a sequência.") or nil,
		(not st.available) and bigBtn({ text = "Fechar", onClick = Ctx.does("closeModal") }) or nil,
	})
end

local function showOffline(sum)
	if ui.screen ~= "game" then
		-- No web a produção offline aparece ao entrar no jogo (startGame); aqui ela chega já no carregamento.
		pendingOffline = sum
		return
	end
	local g = sum.gains or {}
	local cells = {}
	for _, r in { "gold", "food", "wood", "stone" } do
		local v = g[r] or 0
		table.insert(cells, h("Frame", { BackgroundColor3 = T.c.white, AutomaticSize = AY }, {
			Kit.corner(T.r),
			Kit.stroke(T.c.line, 1, 0),
			Kit.pad(rem(0.6), rem(0.3)),
			Kit.list("y", { gap = rem(0.25), align = "center" }),
			U.resIco(r, rem(1.9)),
			U.b((v >= 0 and "+" or "") .. fmt(v), { color = v < 0 and T.c.bad or T.c.text, align = CENTER }),
		}))
	end
	local cols = Ctx.vp.X <= T.BP_SMALL and 2 or 4
	local w = sum.welcome
	Modals.show({
		h2("time", string.format("Enquanto você esteve fora (%s)", fmtTime(sum.elapsed or 0))),
		p(string.format("Seu reino trabalhou com %d%% de eficiência%s.", Util.round((sum.efficiency or 1) * 100),
			sum.capped and string.format(" por até %s (limite offline)", fmtTime(sum.simulated or 0)) or "")),
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY }, {
			Kit.pad(rem(0.3), 0, rem(0.3), 0),
			grid(cells, cols, rem(0.45)),
		}),
		w and p(string.format("Pacote de volta (%s dias fora): +%s gemas, +%s pergaminho e %s min de ouro.",
			Util.jsNumStr(w.days), Util.jsNumStr(w.gems), Util.jsNumStr(w.scroll), Util.jsNumStr(w.goldMinutes)),
			{ color = T.c.good, icon = "gems" }) or nil,
		(sum.expeditionsReady and sum.expeditionsReady > 0) and p(string.format("%d expedição(ões) pronta(s) para coletar.", sum.expeditionsReady), { icon = "expedition" }) or nil,
		sum.capped and muted("Aumente o limite com o talento Vigília ou o herói O Relojoeiro.") or nil,
		bigBtn({ text = "Continuar", variant = "primary", onClick = Ctx.does("closeModal") }),
	})
end

local function mix(a, b, t)
	return a:Lerp(b, t)
end

local function showRecruit(res)
	local g = Ctx.game
	if type(res) ~= "table" or type(res.hero) ~= "table" then return end
	local hero = HeroData.HERO_BY_ID[res.hero.id] or res.hero
	local rar = HeroData.RARITIES[hero.rarity] or HeroData.RARITIES.comum
	local rc = T.rarity[hero.rarity] or T.rarity.comum
	play((hero.rarity == "lendario" or hero.rarity == "epico") and "legendary" or "recruit")
	local owned = g and g.state.heroes.owned[hero.id] or nil
	local bonus = ""
	if owned and hero.bonus then
		bonus = string.format("%s · poder %s", Side.describeBonus(hero.bonus.type, hero.bonus.value * Economy.heroStrength(owned)),
			tostring(Economy.heroPowerOf(hero, owned)))
	end
	local line = res.isNew and "Novo herói!"
		or (res.gemsRefund and res.gemsRefund > 0) and string.format("Já está no máximo: +%s gemas.", Util.jsNumStr(res.gemsRefund))
		or string.format("Repetido! Agora com %s estrelas.", Util.jsNumStr(res.stars or 0))
	anim.recruit = { t0 = os.clock() }
	Modals.show({
		h("Frame", { Name = "Revelacao", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ClipsDescendants = true }, {
			Kit.corner(T.r),
			-- radial-gradient(circle at 50% 32%, rc 32%, transparent 68%)
			U.sprite("ui/glow", UDim2.fromScale(1.1, 1.1), {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), ImageColor3 = rc,
				ImageTransparency = 0.68, ScaleType = Enum.ScaleType.Stretch, ZIndex = 1,
			}),
			-- ::before: raios girando atrás do retrato (340 px, centro a 4.6rem do topo)
			U.sprite("ui/rays", 340, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, rem(4.6)), ImageColor3 = rc,
				ImageTransparency = 0.78, ScaleType = Enum.ScaleType.Stretch, ZIndex = 1,
				ref = function(inst) anim.recruit.rays = inst end,
			}),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = AY, ZIndex = 2 }, {
				Kit.pad(rem(0.8), rem(0.6), rem(0.4), rem(0.6)),
				Kit.list("y", { gap = rem(0.3), align = "center" }),
				h("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(116, 116) }, {
					h("Frame", {
						BackgroundColor3 = T.c.white, Size = UDim2.fromScale(1, 1),
						ref = function(inst) anim.recruit.portrait = inst end,
					}, {
						Kit.corner(24),
						Kit.grad({ T.c.white, mix(T.c.white, rc, 0.22) }, 90),
						Kit.stroke(rc, 3, 0.45),
						h("UIScale", { Scale = motion() and 0 or 1 }),
						U.ico(hero.icon or "star", rc, 86, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }),
					}),
				}),
				Modals.gap(rem(0.3)),
				U.text(upper(rar.name), { bold = true, size = 0.85, color = rc, align = CENTER }),
				U.text(esc(hero.name or ""), { bold = true, size = 1.35, align = CENTER, wrap = true }),
				p(line, { center = true }),
				bonus ~= "" and muted(bonus, { center = true }) or nil,
				U.text(esc(hero.lore or ""), { font = ITALIC, align = CENTER, wrap = true, lineHeight = 1.3 }),
			}),
		}),
		bigBtn({ text = "Bem-vindo(a)!", variant = "primary", onClick = Ctx.does("closeModal") }),
	})
end

local function showRunSummary(summary, o)
	Ascension.show(summary, o)
end

-- ================================================================ entrar no jogo (startGame do web)
local function startGame(isNew)
	Ctx.setScreen("game")
	ui.selected = nil
	ui.cursor = nil
	local C = Ctx.controller
	if C then
		C.endVisit()
		C.setLayer(0)
		C.setMode({ type = "select" })
		C.renderLayers()
		C.renderAll()
		C.updateMood()
	end
	if isNew then
		pendingOffline = nil
		showIntro()
		return
	end
	if pendingOffline then
		local sum = pendingOffline
		pendingOffline = nil
		showOffline(sum)
	end
	local g = Ctx.game
	if g and g:dailyStatus().available then
		showDaily()
	end
end

-- ================================================================ ações (data-action)
local A = {}

A["continue"] = function()
	play("confirm")
	startGame(false)
end
A.newGame = function()
	local function go()
		local r = Ctx.act("newGame")
		if r.ok then
			startGame(true)
		end
	end
	if hasSave() then
		confirm({
			h2("warning", "Começar um reino novo?"),
			p("O reino atual será substituído. Os backups automáticos ficam guardados em Save e backups."),
		}, go, { yes = "Começar de novo", danger = true })
	else
		go()
	end
end
A.howTo = function() showHowTo() end
A.gameMenu = function() showGameMenu() end
A.toggleMusic = function()
	local c = Util.deepCopy(Ctx.config)
	if c.musicOn and c.musicVolume > 0 and c.masterVolume > 0 then
		c.musicOn = false
	else
		c.musicOn = true
		if c.musicVolume <= 0 then c.musicVolume = 0.5 end
		if c.masterVolume <= 0 then c.masterVolume = 1 end
	end
	Ctx.setConfig(c)
	play("click")
end
A.toMainMenu = function()
	task.spawn(Ctx.call, "save")
	Modals.close()
	showMainMenu()
end
A.options = function() showOptions(false) end
A.credits = function() showCredits() end
A.saveMenu = function() showSaveMenu() end
A.daily = function()
	Modals.close()
	local r = Ctx.act("claimDaily")
	if r.ok then
		if Ctx.controller then Ctx.controller.result(r) end
		play("coin")
	end
end
A.showDaily = function() showDaily() end
-- O Side passa a posição (1 = primeira) na lista de rodadas.
A.runSummary = function(i)
	local g = Ctx.game
	local r = g and g.state.runs and g.state.runs[tonumber(i) or 0]
	if r then
		play("open", 0.6)
		showRunSummary(r)
	end
end
A.exportSave = function()
	local r = Ctx.act("exportSave")
	if r.ok and r.code then
		copyText(r.code)
	end
end
A.importSave = function()
	local code = importText
	local ok, res = pcall(Storage.importCode, code, Ctx.now())
	if not ok then
		play("error")
		toast("Save inválido: " .. Storage.cleanError(res), "bad", "warning")
		return
	end
	local st = res.state
	Modals.close()
	confirm({
		h2("save", "Importar este save?"),
		p(string.format("Reino <b>%s</b>, %s de ouro na vida toda. O reino atual será substituído (os backups automáticos continuam guardados).",
			esc(st.kingdom.name), fmt(st.stats.totalGold or 0))),
	}, function()
		local r = Ctx.act("importSave", code)
		if r.ok then
			pendingOffline = nil
			startGame(false)
			toast("Save importado.", "good", "save")
		end
	end, { yes = "Importar" })
end
A.restoreBackup = function(slot)
	confirm({
		h2("save", "Restaurar este backup?"),
		p("O reino atual será substituído pelo backup."),
	}, function()
		local r = Ctx.act("restoreBackup", tonumber(slot))
		if r.ok then
			pendingOffline = nil
			startGame(false)
			toast("Backup restaurado.", "good", "save")
		end
	end, { yes = "Restaurar" })
end
A.hardReset = function()
	confirm({
		h2("warning", "Apagar o reino atual?"),
		p("O save principal será apagado. Os backups automáticos continuam disponíveis em Save e backups."),
	}, function()
		local r = Ctx.act("hardReset")
		if r.ok then
			startGame(true)
		end
	end, { yes = "Apagar", danger = true })
end
A.remap = function(id)
	ui.remapping = id
	showOptions(true)
end
A.resetOptions = function()
	Ctx.setConfig(Config.resetOptions(Ctx.config))
	if Ctx.renderer then Ctx.renderer:resize() end
	showOptions(true)
	toast("Opções restauradas para o padrão.", "good", "check")
end
-- Sem tela cheia própria no Roblox (o botão nem aparece em Opções).
A.fullscreen = function()
	toast("No Roblox, a tela cheia fica no menu do próprio Roblox.", "info", "info")
end
A.resetKeys = function()
	local c = Util.deepCopy(Ctx.config)
	c.keys = {}
	for _, a in Config.KEY_ACTIONS do
		c.keys[a.id] = a.key
	end
	-- No Roblox o Esc é do menu do Roblox: o menu do jogo fica no Q.
	c.keys.menu = "q"
	Ctx.setConfig(c)
	showOptions(true)
end
A.startKingdom = function()
	local name = introName ~= "" and introName or "Reino de Bolso"
	local banner = introBanner
	Modals.close()
	Ctx.act("setKingdomName", name)
	if banner then
		Ctx.call("equip", "banner", banner)
	end
	if Ctx.controller then Ctx.controller.renderAll() end
	showDaily()
end

-- Remapeamento: a próxima tecla vai para a ação escolhida (o Controller ignora o teclado enquanto isso).
local function onRemapKey(input)
	if not ui.remapping or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() then return end
	local keyName = Ctx.keyName
	local key = keyName and keyName(input.KeyCode)
	if not key then return end
	local id = ui.remapping
	-- Depois do Controller (que ainda vê ui.remapping e não trata a tecla).
	task.defer(function()
		if ui.remapping ~= id then return end
		if key ~= "escape" then
			local c = Util.deepCopy(Ctx.config)
			local clash = Config.actionForKey(c, key)
			if clash and clash ~= id then
				c.keys[clash] = c.keys[id]
			end
			c.keys[id] = key
			ui.remapping = nil
			Ctx.setConfig(c)
		else
			ui.remapping = nil
		end
		showOptions(true)
	end)
end

-- ================================================================ API (Main.client.luau)
function Screens.init(f)
	frames = f
	-- Menu: o mapa de fundo (MapView, fora do Kit) e a interface por cima.
	menuBg = Instance.new("Frame")
	menuBg.Name = "MapaDeFundo"
	menuBg.BackgroundColor3 = T.c.ink
	menuBg.BorderSizePixel = 0
	menuBg.Size = UDim2.fromScale(1, 1)
	menuBg.ClipsDescendants = true
	menuBg.ZIndex = 1
	menuBg.Parent = f.menu
	menuUi = Instance.new("Frame")
	menuUi.Name = "Interface"
	menuUi.BackgroundTransparency = 1
	menuUi.Size = UDim2.fromScale(1, 1)
	menuUi.ZIndex = 2
	menuUi.Parent = f.menu

	Ctx.show = {
		recruit = showRecruit,
		runSummary = showRunSummary,
		daily = showDaily,
		offline = showOffline,
		intro = showIntro,
		howTo = showHowTo,
		gameMenu = showGameMenu,
		options = showOptions,
		credits = showCredits,
		saveMenu = showSaveMenu,
		mainMenu = showMainMenu,
	}
	-- As ações que esperam o servidor rodam numa thread própria (o clique não trava).
	for name, fn in A do
		Ctx.actions[name] = function(arg)
			task.spawn(fn, arg)
		end
	end

	UserInputService.InputBegan:Connect(onRemapKey)
	-- Slider: arrastar com o mouse ou o dedo; ao soltar, grava a preferência no servidor.
	UserInputService.InputChanged:Connect(function(input)
		if not drag then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			local d = drag
			if d.inst and d.inst.Parent then
				applySlider(d.key, sliderValue(d.inst, input.Position.X, d.min, d.max))
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if drag and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			local k = drag.key
			drag = nil
			Ctx.actAsync("setConfig", Ctx.config)
			if k == "fontScale" and Ctx.renderer then Ctx.renderer:resize() end
		end
	end)
	renderLoading()
end

-- Carrega as folhas de imagens e os sons; depois (com o primeiro estado do servidor) abre o menu.
function Screens.boot()
	task.spawn(function()
		local ids: { any } = Assets.allIds()
		setProgress(0)
		local audio = {}
		for _, n in { "efeitos", "musica-vila", "musica-batalha" } do
			local id = Assets.audioId(n)
			if id then
				-- Sons carregam pelo Sound (o id solto não diz ao PreloadAsync que é áudio).
				local snd = Instance.new("Sound")
				snd.SoundId = id
				table.insert(audio, snd)
			end
		end
		for _, snd in audio do
			table.insert(ids, snd)
		end
		if #ids > 0 then
			local done = 0
			pcall(function()
				ContentProvider:PreloadAsync(ids, function()
					done += 1
					setProgress(math.min(100, math.floor(done / #ids * 100 + 0.5)))
				end)
			end)
		end
		setProgress(100)
		preloadDone = true
		if stateReady and ui.screen == "loading" then
			showMainMenu()
		end
	end)
end

-- Primeiro estado do servidor (Ctx.game e Ctx.server prontos).
function Screens.onFirstState()
	stateReady = true
	if preloadDone and ui.screen == "loading" then
		task.defer(showMainMenu)
	end
end

-- Preferências mudaram (Main já aplicou tema e volumes).
function Screens.onConfig()
	local c = Ctx.config
	if ui.screen == "loading" then
		renderLoading()
	elseif ui.screen == "menu" then
		renderMenu(false)
		drawMenuMap()
	end
	if optionsOpen and Modals.isOpen() then
		Modals.replace()
	end
	local v = Config.effectiveVolumes(c)
	if Ctx.game and (not c.musicOn or v.music <= 0) and v.sfx <= 0 then
		task.spawn(Ctx.call, "uiSecret", "silence")
	end
end

local function bob(period, t)
	return -8 * (0.5 - 0.5 * math.cos(t / period * 2 * math.pi))
end

-- A cada quadro: logo do carregamento, raios e retrato do recrutamento, dia de hoje da diária, Ascensão.
function Screens.frame(dt)
	local now = os.clock()
	local mo = motion()
	if ui.screen == "loading" and loadLogo and loadLogo.Parent then
		loadLogo.Position = UDim2.fromOffset(0, mo and bob(1.6, now) or 0)
	end
	local rc = anim.recruit
	if rc then
		if rc.rays and rc.rays.Parent then
			rc.rays.Rotation = mo and ((now - rc.t0) / 14 * 360) % 360 or 0
		end
		local pt = rc.portrait
		if pt and pt.Parent then
			local sc = pt:FindFirstChildOfClass("UIScale")
			local t = now - rc.t0
			if not mo or t >= 0.7 then
				if sc then sc.Scale = 1 end
				pt.Rotation = 0
				rc.portrait = nil
			else
				-- spin .7s var(--ease-back): scale(0) rotate(-180deg) -> normal
				local k = math.clamp(t / 0.7, 0, 1)
				local e = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
				if sc then sc.Scale = math.max(0, e) end
				pt.Rotation = -180 * (1 - e)
			end
		elseif not (rc.rays and rc.rays.Parent) then
			anim.recruit = nil
		end
	end
	local td = anim.today
	if td then
		if td.Parent then
			td.Position = UDim2.fromOffset(0, mo and bob(1.4, now) or 0)
		else
			anim.today = nil
		end
	end
	Ascension.frame(dt)
end

return Screens
