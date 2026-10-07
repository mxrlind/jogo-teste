-- Testes do porte: roda a lógica Luau fora do Roblox (com Lune) e compara com o jogo web.
-- Uso (na pasta roblox/): lune run tests/run
-- As respostas esperadas (tests/fixtures.json) vêm de tools/fixtures.mjs, que roda o jogo web.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

-- ------------------------------------------------------------ require(script.Parent.X) fora do Roblox
-- Cada pasta/arquivo vira um "nó" com .Parent e filhos por nome, como as Instances do Roblox.
local cache = {}
local makeNode

-- Lista os arquivos antes (o fs do Lune não pode ser chamado dentro de metamétodos).
local files, dirs = {}, {}
local function scan(dir)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then scan(p) else files[p] = true end
	end
end
scan("src/shared")

local function loadModule(node)
	if cache[node.path] ~= nil then return cache[node.path] end
	local src = fs.readFile(node.path)
	local env = { script = node, require = function(target)
		if type(target) == "table" and target.__node then return loadModule(target) end
		return require(target)
	end }
	local chunk = luau.load(src, { debugName = node.path, environment = env })
	local result = chunk()
	cache[node.path] = result
	return result
end

function makeNode(path)
	local node = { __node = true, path = path }
	return setmetatable(node, { __index = function(self, key)
		if key == "Parent" then
			local parent = string.match(self.path, "^(.*)/[^/]+$")
			return makeNode(parent)
		end
		local dir = string.gsub(self.path, "%.luau$", "")
		if files[dir .. "/" .. key .. ".luau"] then return makeNode(dir .. "/" .. key .. ".luau") end
		if dirs[dir .. "/" .. key] then return makeNode(dir .. "/" .. key) end
		error("Não achei " .. key .. " em " .. dir)
	end })
end

local root = makeNode("src/shared/Reino")
local function mod(...)
	local node = root
	for _, part in { ... } do node = node[part] end
	return loadModule(node)
end

local Util = mod("Core", "Util")
local Map = mod("Core", "Map")
local Under = mod("Core", "Underground")
local Season = mod("Core", "Season")
local Social = mod("Core", "Social")
local State = mod("Core", "State")
local Game = mod("Core", "Game")
local roteiro = luau.load(fs.readFile("tests/roteiro.luau"), { debugName = "roteiro" })()

local fixtures = serde.decode("json", fs.readFile("tests/fixtures.json"))
local T0 = 1791385200000

-- ------------------------------------------------------------ mini framework
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FALHOU: " .. name .. (detail and ("\n   " .. detail) or ""))
	end
end
local function near(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return a == b end
	return math.abs(a - b) <= 1e-6 * math.max(1, math.abs(a), math.abs(b))
end

-- ------------------------------------------------------------ mapas e subsolo iguais ao web
for seed, expected in fixtures.maps do
	local tiles = Map.generateMap(tonumber(seed)).tiles
	local parts = {}
	for _, t in tiles do
		table.insert(parts, string.sub(t.t, 1, 1) .. (t.b and string.sub(t.b.id, 1, 1) or ""))
	end
	check("mapa da semente " .. seed, table.concat(parts) == expected)
end
for seed, expected in fixtures.under do
	local under = Under.createUnder(tonumber(seed))
	for d, lv in under.levels do
		local parts = {}
		for _, t in lv.tiles do table.insert(parts, string.sub(t.t, 1, 1)) end
		check(string.format("subsolo %s nível %d", seed, d), table.concat(parts) == expected[d])
	end
end

-- ------------------------------------------------------------ missões, rivais e formatação
for day, expected in fixtures.missions do
	local got = Season.dailyMissions(day, 3.7)
	for i, m in expected do
		check("missão " .. day .. " #" .. i, got[i].id == m.id and got[i].target == m.target and got[i].xp == m.xp,
			string.format("%s/%s/%s vs %s/%s/%s", got[i].id, got[i].target, got[i].xp, m.id, m.target, m.xp))
	end
end
local rivals = Social.generateRivals(4242, T0 + 7200000, T0)
for i, r in fixtures.rivals do
	check("rival #" .. i, rivals[i].name == r.name and rivals[i].ruler == r.ruler and rivals[i].power == r.power and rivals[i].banner == r.banner)
end
for n, expected in fixtures.fmt do
	local got = Util.fmt(tonumber(n))
	check("fmt " .. n, got == expected, got .. " vs " .. expected)
end
for i, sec in { 5, 75, 3725, 90061 } do
	check("fmtTime " .. sec, Util.fmtTime(sec) == fixtures.fmtTime[i], Util.fmtTime(sec))
end

-- ------------------------------------------------------------ uma hora de jogo roteirizada + 5 h offline
local function sortedKeys(t)
	local out = {}
	for k in t do table.insert(out, k) end
	table.sort(out)
	return out
end

for _, case in { { "a", 4242 }, { "b", 77 } } do
	local name, seed = case[1], case[2]
	local exp = fixtures.sessions[name]
	Util.random = Util.mulberry32(seed * 3 + 1)
	local game = Game.new(State.createState({ seed = seed, now = T0 }), T0)
	local log = roteiro(game, T0, 3600)
	local firstDiff = nil
	for i = 1, math.max(#log, #exp.log) do
		if log[i] ~= exp.log[i] then
			firstDiff = string.format("linha %d: luau=%s web=%s", i, tostring(log[i]), tostring(exp.log[i]))
			break
		end
	end
	check("sessão " .. name .. ": mesmas ações e respostas", firstDiff == nil, firstDiff)
	game:tick(T0 + 3600 * 1000 + 5 * 3600 * 1000)
	local s = game.state
	for _, r in { "gold", "food", "wood", "stone", "gems", "crowns" } do
		check("sessão " .. name .. ": " .. r, near(s.res[r], exp.res[r]), tostring(s.res[r]) .. " vs " .. tostring(exp.res[r]))
	end
	check("sessão " .. name .. ": população", near(s.pop, exp.pop), tostring(s.pop) .. " vs " .. tostring(exp.pop))
	for k, v in exp.stats do
		check("sessão " .. name .. ": stats." .. k, near(s.stats[k], v), tostring(s.stats[k]) .. " vs " .. tostring(v))
	end
	check("sessão " .. name .. ": horda", s.raid.level == exp.raid.level and s.raid.dir == exp.raid.dir)
	check("sessão " .. name .. ": heróis", table.concat(sortedKeys(s.heroes.owned), ",") == table.concat(sortedKeys(exp.heroes.owned), ","))
	check("sessão " .. name .. ": conselho", table.concat(s.heroes.council, ",") == table.concat(exp.heroes.council, ","))
	check("sessão " .. name .. ": XP", s.season.xp == exp.xp, tostring(s.season.xp) .. " vs " .. tostring(exp.xp))
	check("sessão " .. name .. ": conquistas", table.concat(sortedKeys(s.achievements), ",") == table.concat(exp.achievements, ","))
	check("sessão " .. name .. ": abas", table.concat(s.unlocks.tabs, ",") == table.concat(exp.unlocks, ","))
	local parts = {}
	for _, t in s.grid.tiles do
		table.insert(parts, string.sub(t.t, 1, 1) .. (t.b and (t.b.id .. t.b.lvl) or ""))
	end
	check("sessão " .. name .. ": mapa final", table.concat(parts, ",") == exp.grid)
	for _, r in { "gold", "food", "wood", "stone" } do
		check("sessão " .. name .. ": produção de " .. r, near(game.econ.rates[r], exp.rates[r]), tostring(game.econ.rates[r]) .. " vs " .. tostring(exp.rates[r]))
	end
	check("sessão " .. name .. ": defesa", near(game.econ.defense, exp.defense))
	check("sessão " .. name .. ": felicidade", near(game.econ.happiness, exp.happiness))
end

-- ------------------------------------------------------------ save: vai e volta pelo formato do DataStore
do
	Util.random = Util.mulberry32(9)
	local game = Game.new(State.createState({ seed = 5, now = T0 }), T0)
	roteiro(game, T0, 600)
	local saved = serde.decode("json", serde.encode("json", State.serialize(game.state)))
	local loaded = State.normalize(saved, T0 + 600000)
	check("save mantém o ouro", near(loaded.res.gold, game.state.res.gold))
	check("save mantém os prédios", loaded.stats.built == game.state.stats.built)
	local g2 = Game.new(loaded, T0 + 600000)
	g2:tick(T0 + 601000)
	check("save carregado continua rodando", g2.state.lastTick == T0 + 601000)
end

-- Ascensão e talentos
do
	Util.random = Util.mulberry32(11)
	local game = Game.new(State.createState({ seed = 8, now = T0 }), T0)
	game.state.stats.runGold = 9e6
	local r = game:ascend()
	check("ascensão dá coroas", r.ok and game.state.res.crowns == 3, tostring(game.state.res.crowns))
	check("talento compra", game:buyTalent("fartura").ok and game.state.legacy.fartura == 1)
	check("rodada nova começa limpa", game.state.stats.runGold == 0 and #game.state.runs == 1)
end

print(string.format("\n%d ok, %d falharam", passed, failed))
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
