-- Estado compartilhado da tela (o `ui` de src/ui/ctx.js) e a ponte com o servidor.
-- Os módulos se registram aqui (Ctx.renderer, Ctx.actions, Ctx.toast...) e se chamam por aqui, sem require circular.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Reino = ReplicatedStorage:WaitForChild("Reino")
local Config = require(Reino.Core.Config)

local Ctx = {}

Ctx.VERSION = "0.18.0"
Ctx.TAB_ORDER = { "reino", "herois", "temporada", "legado", "social", "perfil" }

-- Cópia do Game com o último estado do servidor, mais o relógio local (só para mostrar; o servidor decide).
Ctx.game = nil
-- Preferências (Core/Config); o servidor guarda e devolve.
Ctx.config = Config.defaultConfig()
-- No Roblox o Esc abre o menu do próprio Roblox: o menu do jogo fica no Q.
Ctx.config.keys.menu = "q"

-- Igual ao `ui` do web.
Ctx.ui = {
	screen = "loading", -- "loading" | "menu" | "game"
	tab = "reino",
	mode = { type = "select" }, -- { type = "build", id } | { type = "move", from = {x, y} } | { type = "select" }
	selected = nil, -- { x, y }
	cursor = nil, -- { x, y } (teclado)
	hover = nil, -- { x, y } tile sob o mouse
	hoverDelta = nil, -- prévia do ganho ao construir no tile sob o mouse
	layer = 0, -- 0 = superfície, 1..3 = subsolo
	visiting = nil, -- reino rival sendo visitado
	pointerHeld = false,
	heroOpen = nil,
}

-- Viewport atual em px e o tipo de layout (breakpoints do styles.css).
Ctx.vp = Vector2.new(1280, 720)
Ctx.mobile = false
Ctx.mid = false
Ctx.small = false

-- ------------------------------------------------------------ relógio do servidor
Ctx.timeOffset = 0
function Ctx.now()
	return DateTime.now().UnixTimestampMillis + Ctx.timeOffset
end

-- ------------------------------------------------------------ ações no servidor
local remotes = nil
local function acao()
	remotes = remotes or ReplicatedStorage:WaitForChild("ReinoRemotes")
	return remotes:WaitForChild("Acao")
end

-- Chama uma ação do Game no servidor e espera a resposta ({ ok, reason, ... }).
-- Falha mostra o motivo num toast vermelho com som de erro (o result() do web), a não ser que quiet = true.
function Ctx.call(name, ...)
	local args = table.pack(...)
	local ok, r = pcall(function()
		return acao():InvokeServer(name, table.unpack(args, 1, args.n))
	end)
	if not ok then
		r = { ok = false, reason = "Sem conexão com o servidor" }
	elseif type(r) ~= "table" then
		r = { ok = true, value = r }
	end
	return r
end

function Ctx.act(name, ...)
	local r = Ctx.call(name, ...)
	if not r.ok then
		Ctx.play("error")
		if r.reason then
			Ctx.toast(r.reason, "bad", "warning")
		end
	end
	return r
end

-- Igual a Ctx.act, sem esperar (para cliques em que a tela não depende da resposta).
function Ctx.actAsync(name, ...)
	local args = table.pack(...)
	task.spawn(function()
		Ctx.act(name, table.unpack(args, 1, args.n))
	end)
end

-- ------------------------------------------------------------ eventos do servidor (os .on() do Game no web)
local listeners = {}
function Ctx.on(evt, fn)
	listeners[evt] = listeners[evt] or {}
	table.insert(listeners[evt], fn)
end

function Ctx.emit(evt, data)
	for _, fn in listeners[evt] or {} do
		local ok, err = pcall(fn, data or {})
		if not ok then
			warn("Evento " .. evt .. " falhou: " .. tostring(err))
		end
	end
end

-- ------------------------------------------------------------ redesenho
-- Partes: "hud", "palette", "side", "tileInfo", "modeHint", "layers", "undo", "stage", "all".
-- force = true é o renderX(true) do web (redesenha já, mesmo com o ponteiro pressionado).
Ctx.dirty = {}
function Ctx.invalidate(part, force)
	Ctx.dirty[part] = force and "force" or (Ctx.dirty[part] or true)
	if Ctx.onInvalidate then
		Ctx.onInvalidate(part, force)
	end
end

-- ------------------------------------------------------------ registro de módulos
-- Cada módulo coloca aqui o que os outros precisam chamar. Os padrões abaixo não fazem nada.
Ctx.actions = {} -- nome -> function(arg) (o ACTIONS de app.js)
function Ctx.run(name, arg)
	local fn = Ctx.actions[name]
	if fn then
		fn(arg)
	else
		warn("Ação de tela desconhecida: " .. tostring(name))
	end
end

-- Atalho para onClick: U.btn({ onClick = Ctx.does("upgrade") })
function Ctx.does(name, arg)
	return function()
		Ctx.run(name, arg)
	end
end

function Ctx.toast(text, kind, icon) end -- Toasts
function Ctx.play(name, vol) end -- Audio
function Ctx.setMood(mood) end -- Audio
Ctx.renderer = nil -- MapView (pop, addBurst, addFloat, doShake, doFlash, layer, selected...)
Ctx.modal = nil -- Modals ({ show, replace, close, confirm, isOpen, closable })

-- ------------------------------------------------------------ preferências
function Ctx.setConfig(cfg, noSave)
	Ctx.config = Config.normalizeConfig(cfg)
	if Ctx.onConfig then
		Ctx.onConfig(Ctx.config)
	end
	if not noSave then
		Ctx.actAsync("setConfig", Ctx.config)
	end
end

return Ctx
