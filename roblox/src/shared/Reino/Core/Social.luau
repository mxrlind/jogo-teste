-- Reinos vizinhos simulados (porte de generateRivals em src/core/social.js).
-- São determinísticos pela semente do jogador. Num servidor do Roblox dá para trocar por jogadores de verdade.
local Util = require(script.Parent.Util)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)

local S = {}

local SYL_A = { "Val", "Mor", "Bel", "Cas", "Dra", "Fen", "Gor", "Lum", "Nor", "Ros", "Tar", "Zan", "Aur", "Pra" }
local SYL_B = { "dor", "vale", "mar", "tânia", "gard", "lis", "brasa", "fundo", "pedra", "luz", "monte", "rio" }
local RULERS = { "Rei Otávio", "Rainha Lúcia", "Duque Ferraz", "Baronesa Ivy", "Lorde Cássio", "Imperatriz Yara", "Conde Bruno", "Sultão Amir", "Chefe Taíra", "Mago Olavo" }
local TITLES = { "Fundador", "Prefeito", "Guardião", "Magnata", "Conquistador", "Urbanista", "Colecionador", "Imperador" }

S.RIVAL_COUNT = 9

function S.generateRivals(seed, now, createdAt)
	local rand = Util.mulberry32(Util.hashString("rivais-" .. seed))
	local hours = math.max(0, (now - createdAt) / 3600000)
	local banners = Util.filter(Cosmetics.BANNERS, function(b) return b.free or b.price end)
	local emblems = Util.filter(Cosmetics.EMBLEMS, function(e) return e.free or e.price end)
	local rivals = {}
	for i = 0, S.RIVAL_COUNT - 1 do
		local base = 40 * 3.2 ^ i * (0.7 + rand() * 0.6)
		local growth = 0.02 + rand() * 0.06
		local power = math.floor(base * (1 + hours * growth) ^ 1.3)
		table.insert(rivals, {
			id = "r" .. i,
			name = Util.pick(rand, SYL_A) .. Util.pick(rand, SYL_B),
			ruler = Util.pick(rand, RULERS),
			title = TITLES[math.min(#TITLES - 1, math.floor(i * 0.9)) + 1],
			banner = Util.pick(rand, banners).id,
			emblem = Util.pick(rand, emblems).id,
			power = power,
			tier = i,
		})
	end
	return rivals
end

return S
