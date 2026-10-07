-- Utilitários do porte: equivalentes Luau de Object.entries, Math.imul, toFixed etc.
-- Tudo aqui é puro (sem serviços do Roblox), então roda igual no servidor, no cliente e nos testes (Lune).
local Util = {}

-- Cópia rasa de uma tabela (o `{ ...obj }` do JavaScript).
function Util.copy(t)
	local out = {}
	if t then
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

-- Cópia rasa com campos por cima (o `{ ...a, ...b }`).
function Util.merge(a, b)
	local out = Util.copy(a)
	if b then
		for k, v in b do
			out[k] = v
		end
	end
	return out
end

-- Cópia profunda (o save é só dados: números, textos, booleanos e tabelas).
function Util.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = Util.deepCopy(v)
	end
	return out
end

function Util.keys(t)
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

function Util.count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Util.find(list, pred)
	for _, v in list do
		if pred(v) then
			return v
		end
	end
	return nil
end

function Util.filter(list, pred)
	local out = {}
	for _, v in list do
		if pred(v) then
			table.insert(out, v)
		end
	end
	return out
end

function Util.map(list, fn)
	local out = {}
	for i, v in list do
		out[i] = fn(v, i)
	end
	return out
end

function Util.includes(list, value)
	return table.find(list, value) ~= nil
end

function Util.byId(list)
	local out = {}
	for _, v in list do
		out[v.id] = v
	end
	return out
end

function Util.clamp(v, lo, hi)
	return math.min(hi, math.max(lo, v))
end

-- Math.round do JavaScript (meio arredonda para cima).
function Util.round(v)
	return math.floor(v + 0.5)
end

-- Math.imul: multiplicação de inteiros de 32 bits sem perder precisão no double do Luau.
function Util.imul(a, b)
	a = a % 4294967296
	b = b % 4294967296
	local ah = math.floor(a / 65536)
	local al = a % 65536
	return (al * b + ((ah * b) % 65536) * 65536) % 4294967296
end

local function u32(v)
	return v % 4294967296
end
Util.u32 = u32

-- ---------------------------------------------------------------- aleatoriedade (igual a src/core/rng.js)
-- Mesmo gerador do jogo web: a mesma semente dá o mesmo mapa nos dois.
function Util.mulberry32(seed)
	local a = u32(seed)
	return function()
		a = u32(a + 0x6d2b79f5)
		local t = a
		t = Util.imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, u32(t + Util.imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))))
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
end

-- Números aleatórios que não precisam de semente (eventos, saque, recrutamento).
function Util.random()
	return math.random()
end

function Util.hashString(str)
	local h = 2166136261
	for i = 1, #str do
		h = bit32.bxor(h, string.byte(str, i))
		h = Util.imul(h, 16777619)
	end
	return u32(h)
end

function Util.randInt(rand, min, max)
	return min + math.floor(rand() * (max - min + 1))
end

function Util.pick(rand, arr)
	return arr[math.floor(rand() * #arr) + 1]
end

function Util.weightedPick(rand, items, weightOf)
	local total = 0
	for _, it in items do
		total += weightOf(it)
	end
	local r = rand() * total
	for _, it in items do
		r -= weightOf(it)
		if r <= 0 then
			return it
		end
	end
	return items[#items]
end

-- Dia do calendário no horário de Brasília (UTC-3). O servidor do Roblox roda em UTC.
Util.DAY_OFFSET_HOURS = -3
function Util.dayKey(ms)
	local d = os.date("!*t", math.floor(ms / 1000) + Util.DAY_OFFSET_HOURS * 3600)
	return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

-- ---------------------------------------------------------------- formatação (igual a src/core/format.js)
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function isFinite(n)
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- toFixed do JavaScript: empate arredonda para cima (0,25 -> 0,3), diferente do printf.
local function toFixed(n, decimals)
	local p = 10 ^ decimals
	return string.format("%." .. decimals .. "f", math.floor(n * p + 0.5) / p)
end

local function fmtRaw(n, decimals)
	if not isFinite(n) then
		return "infinito"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		if n < 10 and n % 1 ~= 0 then
			return sign .. toFixed(n, decimals)
		end
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(n) / 3))
	local scaled = n / 10 ^ (tier * 3)
	return sign .. toFixed(scaled, scaled < 100 and decimals or 0) .. SUFFIXES[tier + 1]
end

-- Números no padrão brasileiro: vírgula decimal (1,5K; 0,3/s).
function Util.fmt(n, decimals)
	return (string.gsub(fmtRaw(n, decimals or 1), "%.", ",", 1))
end

function Util.fmtRate(n)
	return (n >= 0 and "+" or "") .. Util.fmt(n) .. "/s"
end

function Util.fmtPct(f)
	return (f >= 0 and "+" or "") .. Util.round(f * 100) .. "%"
end

function Util.fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

return Util
