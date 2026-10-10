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

-- Math.round do JavaScript (meio arredonda para cima). Sem somar 0,5 antes do floor:
-- 0,49999999999999994 + 0,5 dá 1 no double, e números acima de 2^52 já são inteiros.
function Util.round(v)
	local r = math.floor(v)
	if v - r >= 0.5 then
		return r + 1
	end
	return r
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

-- String(n) do JavaScript: menor quantidade de dígitos que volta ao mesmo número,
-- sem notação científica entre 1e-6 e 1e21 (o tostring do Luau usa %.14g e daria "1e+15").
function Util.jsNumStr(n)
	if n ~= n then return "NaN" end
	if n == math.huge then return "Infinity" end
	if n == -math.huge then return "-Infinity" end
	if n == 0 then return "0" end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	local mant, ex
	for p = 1, 17 do
		local str = string.format("%." .. (p - 1) .. "e", n)
		if tonumber(str) == n or p == 17 then
			mant, ex = string.match(str, "^([%d%.]+)e([-+]%d+)$")
			break
		end
	end
	local digits = string.gsub(string.gsub(mant, "%.", ""), "0+$", "")
	local k = #digits
	local point = tonumber(ex) + 1 -- posição da vírgula decimal em relação aos dígitos
	if k <= point and point <= 21 then
		return sign .. digits .. string.rep("0", point - k)
	elseif 0 < point and point <= 21 then
		return sign .. string.sub(digits, 1, point) .. "." .. string.sub(digits, point + 1)
	elseif -6 < point and point <= 0 then
		return sign .. "0." .. string.rep("0", -point) .. digits
	end
	local e = point - 1
	local rest = k > 1 and ("." .. string.sub(digits, 2)) or ""
	return sign .. string.sub(digits, 1, 1) .. rest .. "e" .. (e >= 0 and "+" or "-") .. math.abs(e)
end

-- Soma 1 na última casa de um número decimal escrito ("9.99" -> "10.00").
local function bumpLastDigit(str)
	local chars = string.split(str, "")
	local i = #chars
	while i >= 1 do
		local c = chars[i]
		if c ~= "." then
			if c == "9" then
				chars[i] = "0"
			else
				chars[i] = tostring(tonumber(c) + 1)
				return table.concat(chars)
			end
		end
		i -= 1
	end
	return "1" .. table.concat(chars)
end

-- toFixed do JavaScript (n >= 0 e < 1e21): arredonda o valor exato do double, e no empate exato
-- (0,25; 2,5; 0,125) escolhe o maior, enquanto o printf escolhe o par. 0,15 continua dando "0.1",
-- porque o double de 0,15 é 0,1499999...
local function toFixed(n, decimals)
	local exact = string.format("%." .. (decimals + 25) .. "f", n)
	local dot = string.find(exact, ".", 1, true)
	local tail = string.sub(exact, dot + decimals + 1)
	if tail == "5" .. string.rep("0", 24) then
		local head = string.sub(exact, 1, dot + decimals)
		if decimals == 0 then head = string.sub(head, 1, dot - 1) end
		return bumpLastDigit(head)
	end
	return string.format("%." .. decimals .. "f", n)
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
		return sign .. Util.jsNumStr(math.floor(n))
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
	return (f >= 0 and "+" or "") .. Util.jsNumStr(Util.round(f * 100)) .. "%"
end

function Util.fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	local d = math.floor(sec / 86400)
	local h = math.floor(math.fmod(sec, 86400) / 3600) -- fmod = % do JavaScript (exato com números grandes)
	local m = math.floor(math.fmod(sec, 3600) / 60)
	local s = math.fmod(sec, 60)
	local str = Util.jsNumStr
	if d > 0 then
		return str(d) .. "d " .. str(h) .. "h"
	end
	if h > 0 then
		return str(h) .. "h " .. str(m) .. "m"
	end
	if m > 0 then
		return str(m) .. "m " .. string.format("%02d", s) .. "s"
	end
	return str(s) .. "s"
end

return Util
