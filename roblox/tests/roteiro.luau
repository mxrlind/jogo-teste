-- Roteiro de jogo determinístico (mesmo de tools/roteiro.mjs): mudou um, mude o outro.
-- Devolve { roteiro = ..., cenarios = ... }.
local ORDER = { "fazenda", "casa", "serraria", "casa", "pedreira", "mercado", "muralha", "cais", "torre", "moinho", "taverna", "armazem", "jardim", "quartel" }

local function sortedKeys(t)
	local out = {}
	for k in t do table.insert(out, k) end
	table.sort(out)
	return out
end

local function roteiro(game, T0, seconds)
	local log = {}
	local function rec(t, what, r)
		table.insert(log, string.format("%d:%s:%s", t, what, r.ok and "ok" or tostring(r.reason)))
	end
	local W = 12
	local k = 0
	local function xy(i) return i % W, math.floor(i / W) end
	for t = 1, seconds do
		game:tick(T0 + t * 1000)
		local s = game.state
		if t % 3 == 0 then
			local id = ORDER[k % #ORDER + 1]
			local r = { ok = false, reason = "sem lugar" }
			for i = 0, 143 do
				if r.ok then break end
				if not s.grid.tiles[i + 1].b then
					r = game:build(id, xy(i))
				end
			end
			rec(t, "build-" .. id, r)
			if r.ok then k += 1 end
		end
		if t % 37 == 0 then
			for i = 0, 143 do
				local tile = s.grid.tiles[i + 1]
				if tile.t == "forest" then
					local reason = game:build("casa", xy(i)).reason
					if reason and string.sub(reason, 1, 5) == "Limpe" then
						rec(t, "clear", game:clear(xy(i)))
						break
					end
				end
			end
		end
		if t % 50 == 0 then
			rec(t, "scroll", game:recruit("scroll"))
			rec(t, "gold", game:recruit("gold"))
		end
		if t % 41 == 0 then
			for i = 0, 143 do
				if s.grid.tiles[i + 1].b then
					rec(t, "upgrade", game:upgrade(xy(i)))
					break
				end
			end
		end
		if t % 300 == 0 then rec(t, "expand", game:expand()) end
		if t % 120 == 0 then
			for _, h in sortedKeys(s.heroes.owned) do
				if not table.find(s.heroes.council, h) and not s.heroes.owned[h].expedition then
					rec(t, "exp-" .. h, game:startExpedition(h, "curta"))
					break
				end
			end
			for _, h in sortedKeys(s.heroes.owned) do
				if s.heroes.owned[h].expedition then rec(t, "collect-" .. h, game:collectExpedition(h)) end
			end
		end
		if s.chest and t % 7 == 0 then rec(t, "chest", game:openChest()) end
		if t % 60 == 0 then
			for m = 1, 3 do rec(t, "mission", game:claimMission(m)) end
			rec(t, "tier", game:claimTier(1))
			rec(t, "daily", game:claimDaily())
		end
		if t == 1500 then
			s.res.wood += 300
			s.res.stone += 300
			s.res.gold += 3000
			local r = { ok = false, reason = "sem lugar" }
			for i = 0, 143 do
				if r.ok then break end
				if not s.grid.tiles[i + 1].b then r = game:build("escadaria", xy(i)) end
			end
			rec(t, "escadaria", r)
		end
		if t > 1500 and t % 45 == 0 and s.under.reached >= 1 then
			local r = { ok = false, reason = "nada" }
			for i = 0, 143 do
				if r.ok then break end
				local u = s.under.levels[1].tiles[i + 1]
				if u.s and (u.t == "rock" or u.t == "gold" or u.t == "gem") then
					local x, y = xy(i)
					r = game:dig(1, x, y)
				end
			end
			rec(t, "dig", r)
			if t % 90 == 0 then
				local q = { ok = false, reason = "nada" }
				for _, id in { "garimpo", "pedreira_funda", "adega" } do
					for i = 0, 143 do
						if q.ok then break end
						local x, y = xy(i)
						q = game:buildRoom(1, x, y, id)
					end
				end
				rec(t, "room", q)
			end
		end
		if t == 900 then
			local r = { ok = false, reason = "sem lugar" }
			for i = 0, 143 do
				if r.ok then break end
				r = game:plant(xy(i))
			end
			rec(t, "plant", r)
		end
	end
	return log
end

-- Cenários das novidades de 0.16 a 0.18 (mesmo de cenarios() em tools/roteiro.mjs).
-- deps: { Util, Config } (Util.fmt, Util.dayKey e Util.jsNumStr fazem o papel de fmt, dayKey e String()).
local function cenarios(game, T0, deps)
	local Util, config = deps.Util, deps.Config
	local fmt, dayKey = Util.fmt, Util.dayKey
	-- `${v}` do JavaScript
	local function S(v)
		if type(v) == "number" then return Util.jsNumStr(v) end
		return tostring(v)
	end
	local log = {}
	local W = 12
	local s = game.state
	local function rec(what, r)
		table.insert(log, what .. ":" .. (r.ok and "ok" or tostring(r.reason)))
	end
	local function put(what, v)
		table.insert(log, what .. "=" .. S(v))
	end
	local now = T0
	local function tick(sec)
		now += sec * 1000
		game:tick(now)
	end
	local lastRaid, offline = nil, nil
	game:on("raid", function(r) lastRaid = r end)
	game:on("offline", function(r) offline = r end)
	local function sortedKeys(o)
		local out = {}
		for k in o do table.insert(out, k) end
		table.sort(out)
		return table.concat(out, ",")
	end
	local function fill()
		s.res.gold, s.res.wood, s.res.stone, s.res.food = 20000, 8000, 8000, 2000
	end
	local function free(i)
		local t = s.grid.tiles[i + 1]
		return not t.b and t.t == "grass"
	end
	local function xy(i) return i % W, math.floor(i / W) end
	local function firstFree()
		for i = 0, 143 do
			if free(i) then return i end
		end
		return -1
	end
	local function tryAll(id, want)
		for i = 0, 143 do
			if free(i) then
				local x, y = xy(i)
				if want == "fail" then
					if game:missingNeighbor(id, x, y) then return i, game:build(id, x, y) end
				else
					local r = game:build(id, x, y)
					if r.ok then return i, r end
				end
			end
		end
		return -1, { ok = false, reason = "sem lugar" }
	end
	local function list(l)
		local parts = {}
		for _, d in l or {} do table.insert(parts, string.format("%d,%d,%s", d.x, d.y, d.id)) end
		return table.concat(parts, ";")
	end
	local function raidLog(tag)
		local r = lastRaid
		put(tag, S(r.win) .. "|" .. S(r.strength) .. "|" .. list(r.damaged) .. "|" .. list(r.collapsed))
		if r.lost then put(tag .. "-saque", table.concat({ S(r.lost.gold), S(r.lost.food), S(r.lost.wood), S(r.lost.stone) }, "|")) end
		put(tag .. "-danificados", game:damagedCount())
	end

	s.stats.built = 20 -- libera todos os prédios
	s.grid.ring = 5
	s.res.gems = 200
	fill()

	-- ---- Cais e Mina só onde funcionam (0.16.1)
	local i, r = tryAll("cais", "fail")
	rec("cais-longe@" .. i, r)
	i, r = tryAll("mina", "fail")
	rec("mina-longe@" .. i, r)
	i, r = tryAll("cais", "ok")
	rec("cais@" .. i, r)
	if i >= 0 then
		local j = -1
		for k = 0, 143 do
			if free(k) and game:missingNeighbor("cais", xy(k)) then
				j = k
				break
			end
		end
		if j >= 0 then
			local fx, fy = xy(i)
			local tx, ty = xy(j)
			rec("mover-cais@" .. j, game:move(fx, fy, tx, ty))
		end
	end
	i, r = tryAll("mina", "ok")
	rec("mina@" .. i, r)
	for _, id in { "casa", "fazenda", "muralha", "torre", "serraria", "casa", "mercado", "casa", "fazenda", "muralha", "quartel", "taverna" } do
		i, r = tryAll(id, "ok")
		rec(id .. "@" .. i, r)
	end

	-- ---- teimosia sem recursos (sombra "Insistente")
	s.res.gold = 0
	i = firstFree()
	for _ = 1, 3 do rec("sem-ouro", game:build("casa", xy(i))) end
	put("failBuild", s.stats.failBuild)
	fill()

	-- ---- conquistas e o bônus de produção
	tick(1)
	put("conquistas", sortedKeys(s.achievements))
	put("prodAll", fmt(game.econ.mods.prodAll, 2))

	-- ---- horda perdida quebra construções (0.16.0)
	s.stats.raidsLost = 2 -- passa da proteção de novato
	s.raid.level = 12
	s.raid.dir = "n"
	s.raid.nextAt = now + 1000
	tick(1)
	raidLog("horda1")
	local dmg = lastRaid.damaged[1]
	if dmg then
		local info = game.econ.tiles[dmg.y * W + dmg.x + 1]
		put("danificado-info", table.concat({ S(info.damaged), S(info.active), S(info.workers), S(info.defense) }, "|"))
		rec("melhorar-danificado", game:upgrade(dmg.x, dmg.y))
		local before = table.clone(s.res)
		rec("consertar", game:repair(dmg.x, dmg.y))
		put("conserto-custou", table.concat({ S(before.gold - s.res.gold), S(before.wood - s.res.wood), S(before.stone - s.res.stone) }, "|"))
		rec("consertar-de-novo", game:repair(dmg.x, dmg.y))
	end
	s.res.gold, s.res.wood, s.res.stone = 0, 0, 0
	local all = game:repairAll()
	put("consertar-tudo-sem-recursos", table.concat({ S(all.ok), S(all.count), S(all.left), S(all.reason) }, "|"))
	fill()

	-- ---- segunda derrota: o que continuou quebrado vira ruína
	s.raid.level = 12
	s.raid.dir = "w"
	s.raid.nextAt = now + 1000
	tick(1)
	raidLog("horda2")
	local ruins = {}
	for k, t in s.grid.tiles do
		if t.ruin then table.insert(ruins, (k - 1) .. ":" .. t.ruin) end
	end
	put("ruinas", table.concat(ruins, ","))
	local ruinAt = -1
	for k, t in s.grid.tiles do
		if t.ruin and t.t == "grass" and not t.b then
			ruinAt = k - 1
			break
		end
	end
	if ruinAt >= 0 then
		rec("construir-na-ruina", game:build("casa", xy(ruinAt)))
		put("ruina-depois", s.grid.tiles[ruinAt + 1].ruin or "nenhuma")
	end

	-- ---- terceira derrota seguida e depois uma vitória
	s.raid.level = 12
	s.raid.dir = "s"
	s.raid.nextAt = now + 1000
	tick(1)
	raidLog("horda3")
	put("lossStreak", s.stats.lossStreak)
	tick(3)
	all = game:repairAll()
	put("consertar-tudo", table.concat({ S(all.ok), S(all.count), S(all.left) }, "|"))
	for _ = 1, 3 do
		local _i, q = tryAll("torre", "ok")
		rec("torre", q)
	end
	s.pop = 60 -- gente para guarnecer as torres
	s.raid.level = 0
	s.raid.dir = "n"
	s.raid.nextAt = now + 1000
	tick(1)
	raidLog("horda4")
	put("lossStreak-depois", s.stats.lossStreak)

	-- ---- secretas
	local gems = s.res.gems
	game:secret("konami")
	game:secret("konami")
	put("konami-gemas", s.res.gems - gems)
	rec("nome-1", game:setKingdomName("Outro Reino"))
	rec("nome-2", game:setKingdomName("Reino de Bolso"))
	i, r = -1, { ok = false, reason = "sem lugar" }
	for k = 0, 143 do
		if r.ok then break end
		r = game:plant(xy(k))
		i = k
	end
	rec("plantar@" .. i, r)
	rec("arrancar-muda", game:clear(xy(i)))
	s.stats.totalGold = math.max(s.stats.totalGold, 5000)
	s.res.gold = 0
	tick(3)
	fill()
	for _ = 1, 10 do
		local _i, q = tryAll("jardim", "ok")
		rec("obra", q)
		rec("desfazer", game:undoBuild())
	end
	put("undos", s.stats.undos)
	rec("recrutar", game:recruit("scroll"))
	local hid = nil
	for k in s.heroes.owned do
		if not hid or k < hid then hid = k end
	end
	if hid then
		rec("treinar", game:trainHero(hid))
		rec("acelerar-treino", game:speedUpTraining(hid))
	end
	put("trained", s.stats.trained)
	tick(3)
	put("flags", sortedKeys(s.flags))
	put("conquistas", sortedKeys(s.achievements))
	put("prodAll", fmt(game.econ.mods.prodAll, 2))
	local n = game:nextAchievement()
	put("proxima", n and table.concat({ n.a.id, fmt(n.cur), S(n.goal), fmt(n.ratio, 3) }, "|") or "nenhuma")

	-- ---- relógio voltando (0.16.1)
	local play = s.stats.playTime
	now -= 2 * 3600 * 1000
	game:tick(now)
	put("relogio-voltou", s.lastTick == now)
	tick(1)
	put("jogou-depois", fmt(s.stats.playTime - play))
	put("viajante", s.achievements["viajante-do-tempo"] ~= nil)
	put("prodAll-sombra", fmt(game.econ.mods.prodAll, 2))

	-- ---- loja de gemas (0.17.0)
	rec("loja-mudas-sem-muda", game:buyShop("mudas"))
	for _, id in { "ouro", "madeira", "pedra", "comida", "impulso", "pergaminho" } do
		local before = table.clone(s.res)
		local scrolls, boost = s.items.scrolls, s.boostUntil
		rec("loja-" .. id, game:buyShop(id))
		put("loja-" .. id .. "-deu", table.concat({
			fmt(s.res.gold - before.gold), fmt(s.res.wood - before.wood), fmt(s.res.stone - before.stone), fmt(s.res.food - before.food),
			S(before.gems - s.res.gems), S(s.items.scrolls - scrolls), S((s.boostUntil - math.max(boost, now)) / 1000),
		}, "|"))
	end
	i, r = -1, { ok = false, reason = "sem lugar" }
	for k = 0, 143 do
		if r.ok then break end
		r = game:plant(xy(k))
		i = k
	end
	rec("plantar@" .. i, r)
	rec("loja-mudas", game:buyShop("mudas"))
	put("muda-virou", s.grid.tiles[i + 1].t)
	rec("loja-nada", game:buyShop("nada"))
	gems = s.res.gems
	s.res.gems = 2
	rec("loja-sem-gemas", game:buyShop("ouro"))
	s.res.gems = gems
	rec("pacote", game:buyGemPack("saco"))
	rec("pacote-nada", game:buyGemPack("nada"))
	game:creditPurchasedGems(80)
	put("gemsBought", s.stats.gemsBought)

	-- ---- escudo da sequência (0.17.0)
	local function weekStr(v) return v == nil and "null" or S(v) end
	s.daily = { lastDay = dayKey(now - 2 * 86400000), streak = 5, shieldWeek = nil }
	local st = game:dailyStatus()
	put("escudo", table.concat({ S(st.shield), S(st.nextStreak), S(st.shieldReady) }, "|"))
	rec("diario-escudo", game:claimDaily())
	put("sequencia", S(s.daily.streak) .. "|" .. weekStr(s.daily.shieldWeek))
	s.daily.lastDay = dayKey(now - 2 * 86400000)
	st = game:dailyStatus()
	put("escudo-gasto", table.concat({ S(st.shield), S(st.nextStreak), S(st.shieldReady) }, "|"))

	-- ---- pacote de volta, madrugada e 7 dias fora
	local function welcome()
		local w = offline and offline.welcome
		return w and table.concat({ S(w.gems), S(w.scroll), S(w.goldMinutes), S(w.days) }, "|") or "nenhum"
	end
	gems = s.res.gems
	local scrolls = s.items.scrolls
	now = T0 + 3 * 86400000 - 8 * 3600000 -- sábado, 4h da manhã em Brasília
	game:tick(now)
	put("volta-1", table.concat({ welcome(), S(s.res.gems - gems), S(s.items.scrolls - scrolls), fmt(offline.gains.gold) }, "|"))
	tick(3)
	put("madrugada", s.flags.nightOwl ~= nil)
	rec("diario-sabado", game:claimDaily())
	put("sequencia-sabado", S(s.daily.streak) .. "|" .. weekStr(s.daily.shieldWeek))
	now += 8 * 86400000 -- domingo seguinte, depois de 8 dias fora
	game:tick(now)
	put("volta-2", welcome() .. "|" .. S(s.achievements["eles-apostaram"] ~= nil))
	s.daily = { lastDay = dayKey(now - 2 * 86400000), streak = 3, shieldWeek = "2026-10-05" }
	st = game:dailyStatus()
	put("escudo-domingo", table.concat({ S(st.shield), S(st.nextStreak), S(st.shieldReady) }, "|"))
	rec("diario-domingo", game:claimDaily())
	put("sequencia-domingo", S(s.daily.streak) .. "|" .. weekStr(s.daily.shieldWeek))
	offline = nil
	now += 86400000 -- segunda-feira: 1 dia fora não dá pacote
	game:tick(now)
	put("volta-3", welcome())
	st = game:dailyStatus()
	put("segunda", table.concat({ S(st.available), S(st.shield), S(st.nextStreak), S(st.shieldReady) }, "|"))

	-- ---- Opções (0.18.0)
	local function keys(c)
		local out = {}
		for _, a in config.KEY_ACTIONS do table.insert(out, c.keys[a.id]) end
		return table.concat(out, ",")
	end
	local function cfg(c)
		return table.concat({
			S(c.version), S(c.masterVolume), S(c.musicVolume), S(c.musicOn), S(c.sfxVolume), S(c.muteInBackground), S(c.batterySaver),
			S(c.confirmDemolish), S(c.particles), S(c.villagers), S(c.reduceMotion), S(c.fontScale), S(c.highContrast), keys(c),
		}, "|")
	end
	local c1 = config.normalizeConfig(nil, { sound = false, particles = false })
	put("config-legado", cfg(c1))
	local c2 = config.normalizeConfig({ masterVolume = "0.3", musicVolume = 2, sfxVolume = -1, fontScale = 3, muteInBackground = "sim", batterySaver = true, confirmDemolish = false, highContrast = 1, keys = { menu = "Q", up = "", down = 5 } }, { sound = false })
	put("config-bagunca", cfg(c2))
	local c3 = config.normalizeConfig({ masterVolume = "abc", fontScale = true, musicVolume = "", sfxVolume = " 0.25 " })
	put("config-textos", cfg(c3))
	local c4 = config.normalizeConfig({ masterVolume = 0.5, musicVolume = 0.8, sfxVolume = 0.6, muteInBackground = false })
	for _, pair in { { "c2", c2 }, { "c4", c4 } } do
		for _, hidden in { false, true } do
			local v = config.effectiveVolumes(pair[2], hidden)
			put("volumes-" .. pair[1] .. "-" .. tostring(hidden), S(v.music) .. "|" .. S(v.sfx))
		end
	end
	put("restaurar", cfg(config.resetOptions(c2)))
	put("tecla", table.concat({ config.actionForKey(c2, "Q") or "nenhuma", config.actionForKey(c2, "x") or "nenhuma", config.keyLabel("arrowup"), config.keyLabel("q"), config.keyLabel("f5") }, "|"))

	return log
end

return { roteiro = roteiro, cenarios = cenarios }
