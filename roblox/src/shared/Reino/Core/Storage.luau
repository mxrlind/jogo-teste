-- Código de save (porte de exportCode/importCode de src/core/storage.js).
-- O código é o mesmo do jogo web: base64 (UTF-8) do envelope
--   { "format": "reino-de-bolso", "v": 2, "sum": "<fnv1a hex>", "data": "<json do estado>" }
-- e o checksum é o FNV-1a sobre as unidades UTF-16 da string, como o charCodeAt do JavaScript.
-- O JSON é escrito aqui mesmo (sem HttpService) para os testes com Lune e para as chaves vazias saírem
-- como no web ({} nos mapas, [] nas listas).
-- Backups em rodízio e o save principal ficam no DataStore (servidor); aqui só a codificação.
local Util = require(script.Parent.Util)
local State = require(script.Parent.State)

local S = {}

S.FORMAT = "reino-de-bolso"
S.WEB_SAVE_VERSION = 2 -- SAVE_VERSION de src/core/state.js: o estado do porte é o formato v2 do web
S.BACKUP_SLOTS = 3
S.BACKUP_INTERVAL = 5 * 60 * 1000

local ALL_TABS = { "reino", "herois", "temporada", "legado", "social", "perfil" }

-- Mensagem de erro sem "arquivo:linha:" na frente.
function S.cleanError(err)
	local msg = tostring(err)
	msg = string.gsub(msg, "^.-:%d+: ", "")
	return msg
end

local function fail(msg)
	error(msg, 0)
end

-- ------------------------------------------------------------ checksum (FNV-1a em UTF-16)
local function utf16Units(str, fn)
	local ok = pcall(function()
		for _, cp in utf8.codes(str) do
			if cp >= 0x10000 then
				local v = cp - 0x10000
				fn(0xD800 + bit32.rshift(v, 10))
				fn(0xDC00 + bit32.band(v, 0x3FF))
			else
				fn(cp)
			end
		end
	end)
	if not ok then
		-- Texto que não é UTF-8 válido: cai para os bytes (o web nunca gera isso).
		for i = 1, #str do
			fn(string.byte(str, i))
		end
	end
end

function S.checksum(str)
	local h = 0x811c9dc5
	utf16Units(str, function(u)
		h = bit32.bxor(h, u)
		h = Util.imul(h, 0x01000193)
	end)
	return string.format("%08x", h % 4294967296)
end

-- ------------------------------------------------------------ JSON
-- Mapas que podem ficar vazios: no web são objetos ({}), não listas ([]).
local OBJECT_KEYS = {
	legacy = true, achievements = true, flags = true, owned = true, trades = true, greets = true, visited = true,
	records = true, stats = true, res = true, items = true, kingdom = true, raid = true, daily = true, social = true,
	heroes = true, season = true, cosmetics = true, tutorial = true, unlocks = true, grid = true, under = true,
	runBase = true, mods = true, reward = true, lost = true, gains = true,
}

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function encodeString(s)
	s = string.gsub(s, '[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local function encodeNumber(n)
	if n ~= n or n == math.huge or n == -math.huge then
		return "null"
	end
	if n % 1 == 0 and math.abs(n) < 2 ^ 53 then
		return string.format("%d", n)
	end
	return Util.jsNumStr(n)
end

local function isArray(t)
	local n = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		n += 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local encodeValue
local function encodeInto(out, v, key)
	local t = type(v)
	if t == "nil" then
		table.insert(out, "null")
	elseif t == "boolean" then
		table.insert(out, v and "true" or "false")
	elseif t == "number" then
		table.insert(out, encodeNumber(v))
	elseif t == "string" then
		table.insert(out, encodeString(v))
	elseif t == "table" then
		if next(v) == nil then
			table.insert(out, OBJECT_KEYS[key] and "{}" or "[]")
		elseif isArray(v) then
			table.insert(out, "[")
			for i, item in ipairs(v) do
				if i > 1 then
					table.insert(out, ",")
				end
				encodeInto(out, item, nil)
			end
			table.insert(out, "]")
		else
			-- Ordem estável das chaves (o checksum é do texto, então qualquer ordem vale; estável ajuda a comparar).
			local keys = {}
			for k, item in v do
				if type(item) ~= "function" then
					table.insert(keys, tostring(k))
				end
			end
			table.sort(keys)
			table.insert(out, "{")
			local first = true
			for _, k in keys do
				local item = v[k]
				if item == nil then
					item = v[tonumber(k)]
				end
				if not first then
					table.insert(out, ",")
				end
				first = false
				table.insert(out, encodeString(k))
				table.insert(out, ":")
				encodeInto(out, item, k)
			end
			table.insert(out, "}")
		end
	else
		table.insert(out, "null")
	end
end
function encodeValue(v)
	local out = {}
	encodeInto(out, v, nil)
	return table.concat(out)
end
S.jsonEncode = encodeValue

-- Decodificador JSON simples (objetos viram tabelas com chaves texto, listas viram listas 1..n).
function S.jsonDecode(str)
	local pos = 1
	local len = #str
	local function ws()
		pos = string.find(str, "[^ \t\r\n]", pos) or len + 1
	end
	local value
	local function parseString()
		pos += 1
		local parts = {}
		while true do
			local s, e = string.find(str, '["\\]', pos)
			if not s then
				fail("JSON inválido")
			end
			table.insert(parts, string.sub(str, pos, s - 1))
			local c = string.sub(str, s, s)
			if c == '"' then
				pos = e + 1
				break
			end
			local n = string.sub(str, s + 1, s + 1)
			if n == "u" then
				local hex = string.sub(str, s + 2, s + 5)
				local cp = tonumber(hex, 16)
				if not cp or #hex < 4 then
					fail("JSON inválido")
				end
				pos = s + 6
				if cp >= 0xD800 and cp <= 0xDBFF and string.sub(str, pos, pos + 1) == "\\u" then
					local lo = tonumber(string.sub(str, pos + 2, pos + 5), 16)
					if lo and lo >= 0xDC00 and lo <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
						pos += 6
					end
				end
				table.insert(parts, utf8.char(cp))
			else
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				local r = map[n]
				if not r then
					fail("JSON inválido")
				end
				table.insert(parts, r)
				pos = s + 2
			end
		end
		return table.concat(parts)
	end
	function value()
		ws()
		local c = string.sub(str, pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			ws()
			if string.sub(str, pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				ws()
				if string.sub(str, pos, pos) ~= '"' then
					fail("JSON inválido")
				end
				local k = parseString()
				ws()
				if string.sub(str, pos, pos) ~= ":" then
					fail("JSON inválido")
				end
				pos += 1
				obj[k] = value()
				ws()
				local d = string.sub(str, pos, pos)
				pos += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					fail("JSON inválido")
				end
			end
		elseif c == "[" then
			pos += 1
			local arr = {}
			ws()
			if string.sub(str, pos, pos) == "]" then
				pos += 1
				return arr
			end
			local i = 0
			while true do
				i += 1
				arr[i] = value()
				ws()
				local d = string.sub(str, pos, pos)
				pos += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					fail("JSON inválido")
				end
			end
		elseif c == '"' then
			return parseString()
		elseif string.sub(str, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(str, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(str, pos, pos + 3) == "null" then
			pos += 4
			return nil
		else
			local s, e = string.find(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not s then
				fail("JSON inválido")
			end
			local n = tonumber(string.sub(str, s, e))
			if n == nil then
				fail("JSON inválido")
			end
			pos = e + 1
			return n
		end
	end
	local v = value()
	ws()
	if pos <= len then
		fail("JSON inválido")
	end
	return v
end

-- ------------------------------------------------------------ base64 (btoa/atob sobre os bytes UTF-8)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_CHARS = {}
local B64_INDEX = {}
for i = 1, 64 do
	local c = string.sub(B64, i, i)
	B64_CHARS[i - 1] = c
	B64_INDEX[string.byte(c)] = i - 1
end

function S.toB64(str)
	local out = table.create(math.ceil(#str / 3))
	for i = 1, #str, 3 do
		local a, b, c = string.byte(str, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = B64_CHARS[bit32.rshift(n, 18) % 64]
		local c2 = B64_CHARS[bit32.rshift(n, 12) % 64]
		local c3 = b and B64_CHARS[bit32.rshift(n, 6) % 64] or "="
		local c4 = c and B64_CHARS[n % 64] or "="
		table.insert(out, c1 .. c2 .. c3 .. c4)
	end
	return table.concat(out)
end

function S.fromB64(b64)
	b64 = string.gsub(b64, "[ \t\r\n]", "")
	b64 = string.gsub(b64, "=+$", "")
	if #b64 % 4 == 1 or string.find(b64, "[^A-Za-z0-9+/]") then
		fail("Código inválido")
	end
	local out = table.create(math.ceil(#b64 / 4))
	for i = 1, #b64, 4 do
		local n, count = 0, 0
		for j = i, math.min(i + 3, #b64) do
			n = n * 64 + B64_INDEX[string.byte(b64, j)]
			count += 1
		end
		for _ = count + 1, 4 do
			n *= 64
		end
		local a = bit32.rshift(n, 16) % 256
		local b = bit32.rshift(n, 8) % 256
		local c = n % 256
		if count == 4 then
			table.insert(out, string.char(a, b, c))
		elseif count == 3 then
			table.insert(out, string.char(a, b))
		else
			table.insert(out, string.char(a))
		end
	end
	return table.concat(out)
end

-- ------------------------------------------------------------ envelope
-- Estado do porte -> texto JSON do envelope (encodeSave do web).
function S.encodeSave(state)
	local data = State.serialize(state)
	data.version = S.WEB_SAVE_VERSION
	local json = S.jsonEncode(data)
	return S.jsonEncode({ format = S.FORMAT, v = S.WEB_SAVE_VERSION, sum = S.checksum(json), data = json })
end

-- Migrações do web (migrateWithSettings) até o v2, depois a versão do porte para State.normalize.
local function migrate(data)
	if type(data) ~= "table" or type(data.grid) ~= "table" or type(data.grid.tiles) ~= "table" or type(data.res) ~= "table" then
		fail("Save inválido")
	end
	local from = tonumber(data.version) or 1
	if from > S.WEB_SAVE_VERSION then
		fail(string.format("Save de uma versão mais nova do jogo (v%s)", Util.jsNumStr(from)))
	end
	if from < 2 then
		-- Prédio "Fonte" virou "Fogueira"; direção das hordas; quem jogava v1 conhecia todas as abas.
		for _, t in data.grid.tiles do
			if type(t) == "table" and type(t.b) == "table" and t.b.id == "fonte" then
				t.b.id = "fogueira"
			end
		end
		data.raid = type(data.raid) == "table" and data.raid or {}
		data.raid.dir = data.raid.dir or "n"
		data.unlocks = { tabs = table.clone(ALL_TABS) }
		data.settings = nil
	end
	data.version = State.SAVE_VERSION
	return data
end

-- Texto do envelope (ou JSON puro do v1) -> dados do save prontos para State.normalize. Lança erro se corrompido.
function S.decodeSave(raw)
	if type(raw) ~= "string" or not string.find(raw, "%S") then
		fail("Save vazio")
	end
	local outer = S.jsonDecode(raw)
	if type(outer) == "table" and outer.format == S.FORMAT then
		if type(outer.data) ~= "string" or S.checksum(outer.data) ~= outer.sum then
			fail("Checksum não confere")
		end
		return migrate(S.jsonDecode(outer.data))
	end
	return migrate(outer)
end

function S.exportCode(state)
	return S.toB64(S.encodeSave(state))
end

-- Código -> { state } já normalizado. Erros com mensagem limpa (para o aviso "Save inválido: ...").
function S.importCode(code, now)
	local ok, result = pcall(function()
		local raw = S.fromB64((string.gsub(tostring(code), "^%s*(.-)%s*$", "%1")))
		local data = S.decodeSave(raw)
		return State.normalize(data, now)
	end)
	if not ok then
		fail(S.cleanError(result))
	end
	return { state = result }
end

return S
