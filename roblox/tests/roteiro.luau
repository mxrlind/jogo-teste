-- Roteiro de jogo determinístico (mesmo de tools/roteiro.mjs): mudou um, mude o outro.
local ORDER = { "fazenda", "casa", "serraria", "casa", "pedreira", "mercado", "muralha", "cais", "torre", "moinho", "taverna", "armazem", "jardim", "quartel" }

local function sortedKeys(t)
	local out = {}
	for k in t do table.insert(out, k) end
	table.sort(out)
	return out
end

return function(game, T0, seconds)
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
