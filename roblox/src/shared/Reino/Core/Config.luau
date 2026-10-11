-- Preferências do jogador (porte de src/core/config.js): volume, acessibilidade e atalhos.
-- Ficam fora do save do reino: começar um reino novo ou ascender não deve zerar o volume de ninguém.
-- No Roblox o cliente guarda isto onde quiser (atributo, DataStore à parte); aqui só há a lógica.
local Util = require(script.Parent.Util)

local C = {}

C.CONFIG_KEY = "reino-de-bolso:config"
C.CONFIG_VERSION = 1

-- Ações remapeáveis e teclas padrão (valores de KeyboardEvent.key do navegador, em minúsculas).
C.KEY_ACTIONS = {
	{ id = "menu", label = "Abrir o menu / cancelar", key = "escape" },
	{ id = "up", label = "Cursor para cima", key = "arrowup" },
	{ id = "down", label = "Cursor para baixo", key = "arrowdown" },
	{ id = "left", label = "Cursor para a esquerda", key = "arrowleft" },
	{ id = "right", label = "Cursor para a direita", key = "arrowright" },
	{ id = "confirm", label = "Confirmar no tile do cursor", key = "enter" },
	{ id = "upgrade", label = "Melhorar o prédio selecionado", key = "u" },
	{ id = "move", label = "Mover o prédio selecionado", key = "m" },
	{ id = "sell", label = "Demolir o prédio selecionado", key = "delete" },
	{ id = "nextTab", label = "Próxima aba do painel", key = "t" },
	{ id = "undo", label = "Desfazer a última construção", key = "z" },
}

function C.defaultConfig()
	local keys = {}
	for _, a in C.KEY_ACTIONS do
		keys[a.id] = a.key
	end
	return {
		version = C.CONFIG_VERSION,
		masterVolume = 1,
		musicVolume = 0.5,
		musicOn = true,
		sfxVolume = 0.8,
		muteInBackground = true,
		batterySaver = false,
		confirmDemolish = true,
		particles = true,
		villagers = true,
		reduceMotion = false,
		fontScale = 1,
		highContrast = false,
		keys = keys,
	}
end

-- Number(v) do JavaScript: nil vira NaN, booleano vira 0/1, texto vazio vira 0.
local function toNumber(v)
	local t = type(v)
	if t == "number" then return v end
	if t == "boolean" then return v and 1 or 0 end
	if t == "string" then
		local trimmed = string.match(v, "^%s*(.-)%s*$")
		if trimmed == "" then return 0 end
		return tonumber(trimmed) or 0 / 0
	end
	return 0 / 0
end

local function clamp(v, lo, hi, d)
	local n = toNumber(v)
	if n ~= n or n == math.huge or n == -math.huge then return d end
	return math.min(hi, math.max(lo, n))
end

-- Aceita config salva (qualquer versão) e/ou as configurações antigas do save v1 ({ sound, particles }).
function C.normalizeConfig(raw, legacySettings)
	local d = C.defaultConfig()
	local c = type(raw) == "table" and raw or {}
	if legacySettings and not raw then
		if legacySettings.sound == false then d.sfxVolume = 0 end
		if legacySettings.particles == false then d.particles = false end
	end
	local keys = Util.copy(d.keys)
	local ck = type(c.keys) == "table" and c.keys or {}
	for _, a in C.KEY_ACTIONS do
		local k = ck[a.id]
		if type(k) == "string" and k ~= "" then keys[a.id] = string.lower(k) end
	end
	local function bool(k)
		if type(c[k]) == "boolean" then return c[k] end
		return d[k]
	end
	return {
		version = C.CONFIG_VERSION,
		masterVolume = clamp(c.masterVolume, 0, 1, d.masterVolume),
		musicVolume = clamp(c.musicVolume, 0, 1, d.musicVolume),
		musicOn = bool("musicOn"),
		sfxVolume = clamp(c.sfxVolume, 0, 1, d.sfxVolume),
		muteInBackground = bool("muteInBackground"),
		batterySaver = bool("batterySaver"),
		confirmDemolish = bool("confirmDemolish"),
		particles = bool("particles"),
		villagers = bool("villagers"),
		reduceMotion = bool("reduceMotion"),
		fontScale = clamp(c.fontScale, 0.85, 1.5, d.fontScale),
		highContrast = bool("highContrast"),
		keys = keys,
	}
end

-- Volumes que de fato tocam: o volume geral multiplica música e efeitos, e o jogo em segundo plano
-- silencia tudo quando a opção está ligada. hidden = janela sem foco (no Roblox, WindowFocusReleased).
function C.effectiveVolumes(config, hidden)
	local m = (hidden and config.muteInBackground) and 0 or config.masterVolume
	return { music = config.musicVolume * m, sfx = config.sfxVolume * m }
end

-- Restaura as opções padrão sem mexer nas teclas (elas têm botão próprio).
function C.resetOptions(config)
	local out = C.defaultConfig()
	out.keys = Util.copy(config.keys)
	return out
end

-- Primeira ação ligada a uma tecla (para o atalho e para detectar conflitos no remapeamento).
function C.actionForKey(config, key)
	local k = string.lower(tostring(key))
	for _, a in C.KEY_ACTIONS do
		if config.keys[a.id] == k then return a.id end
	end
	return nil
end

local KEY_NAMES = {
	escape = "Esc", enter = "Enter", delete = "Delete", tab = "Tab", [" "] = "Espaço",
	arrowup = "Seta para cima", arrowdown = "Seta para baixo", arrowleft = "Seta para a esquerda", arrowright = "Seta para a direita",
	backspace = "Backspace",
}
function C.keyLabel(key)
	if KEY_NAMES[key] then return KEY_NAMES[key] end
	if utf8.len(key) == 1 then return string.upper(key) end
	return key
end

return C
