-- Áudio (porte de src/ui/audio.js): efeitos Kenney (CC0) e trilha sonora por clima.
-- - Os efeitos estão num arquivo só ("efeitos"); cada um é um trecho (Sons.efeitos) tocado com PlaybackRegion.
--   Um pequeno rodízio de Sounds deixa os efeitos se sobreporem, como os BufferSource do Web Audio.
-- - A música de cada clima ("vila", "batalha") é um arquivo com as faixas emendadas (Sons.musica); as faixas do
--   clima tocam em sequência; trocar de clima faz uma transição suave (FADE) entre os dois arquivos.
-- - A música "abaixa" durante as fanfarras (ducking).
-- - No Roblox não há bloqueio de autoplay: nada espera o primeiro gesto.
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ctx = require(script.Parent.Ctx)
local Assets = require(script.Parent.Assets)
local Sons = require(script.Parent.Sons)
local Config = require(ReplicatedStorage:WaitForChild("Reino").Core.Config)

local Audio = {}

local JINGLES = { win = true, lose = true, tier = true, achievement = true, legendary = true, ascend = true }
local FADE = 1.2 -- s
local DUCK_LEVEL, DUCK_TIME = 0.3, 1.8
local POOL_SIZE = 8
-- O volume 1 do web (GainNode) vira o Volume 0,5 padrão do Sound do Roblox.
local BASE = 0.5

local sfxVolume = 0.8
local musicVolume = 0.5
local musicOn = true
local hidden = false
local config = nil

local folder = nil
local pool = {}
local poolNext = 1
local sfxId = nil

-- Uma trilha por clima: { sound, id, list, idx, fade, target, track, onDone }
local players = {}
local mood = "vila"
local current = nil -- faixa tocando agora (tabela de Sons.musica)
local duckLevel = 1
local duckUntil = 0
local started = false

local function newSound(name, id)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = 0
	s.PlaybackRegionsEnabled = true
	s.Parent = folder
	return s
end

-- ------------------------------------------------------------ efeitos
local function play(name, vol)
	if not sfxId or sfxVolume <= 0 then return end
	local region = Sons.efeitos[name]
	if not region then return end
	local s = pool[poolNext]
	poolNext = poolNext % POOL_SIZE + 1
	if not s then return end
	s:Stop()
	s.PlaybackRegion = NumberRange.new(region[1], region[2])
	s.TimePosition = region[1]
	s.Volume = BASE * sfxVolume * (vol or 1)
	s:Play()
	if JINGLES[name] then
		Audio.duck()
	end
end

-- ------------------------------------------------------------ música
local function moodList(m)
	local p = players[m]
	return p and p.list or {}
end

local function anyMusic()
	for _, p in players do
		if #p.list > 0 then return true end
	end
	return false
end

function Audio.hasMusic()
	return anyMusic()
end

-- Todas as faixas instaladas (para Opções e Créditos), com o clima de cada uma.
function Audio.tracks()
	local out = {}
	for _, m in { "vila", "batalha" } do
		for _, t in moodList(m) do
			local c = table.clone(t)
			c.mood = m
			table.insert(out, c)
		end
	end
	return out
end

function Audio.nowPlaying()
	return current
end

local function applyMusicVolume()
	for _, p in players do
		p.sound.Volume = math.clamp(BASE * musicVolume * duckLevel * p.fade, 0, 10)
	end
end

local function canPlayMusic()
	return musicOn and musicVolume > 0
end

-- Começa a próxima faixa do clima `m`, subindo o volume a partir de zero.
local function playNext(m)
	local p = players[m]
	if not p or #p.list == 0 then return end
	local i = p.idx % #p.list + 1
	p.idx = i
	local t = p.list[i]
	p.track = t
	if m == mood then current = t end
	local s = p.sound
	-- Com uma faixa só no clima, ela repete; com várias, o fim do trecho passa para a próxima.
	s.Looped = #p.list == 1
	s.LoopRegion = NumberRange.new(t.from, t.to)
	s.PlaybackRegion = NumberRange.new(t.from, t.to)
	s.TimePosition = t.from
	p.fade = 0
	p.target = 1
	p.onDone = nil
	applyMusicVolume()
	if canPlayMusic() then s:Play() end
end

local function startMusic()
	if started or not anyMusic() or not canPlayMusic() then return end
	started = true
	playNext(mood)
end

-- Clima da trilha: "vila" (folk de taverna) ou "batalha" (metal). Sem faixas do clima, fica na vila.
local function setMood(m)
	local want = #moodList(m) > 0 and m or "vila"
	if want == mood then return end
	local old = players[mood]
	mood = want
	if not started then
		startMusic()
		return
	end
	-- Transição suave: o clima antigo desce até zero e para; o novo sobe.
	if old then
		old.target = 0
		old.onDone = function()
			old.sound:Pause()
		end
	end
	local p = players[mood]
	if p then
		if p.track and p.sound.TimePosition > 0 and p.sound.TimePosition < p.track.to - 0.1 then
			-- Volta de onde parou.
			current = p.track
			p.target = 1
			p.onDone = nil
			if canPlayMusic() then p.sound:Resume() end
		else
			playNext(mood)
		end
	end
end

function Audio.duck()
	if not started then return end
	duckLevel = DUCK_LEVEL
	duckUntil = os.clock() + DUCK_TIME
	applyMusicVolume()
end

local function setVolumes(m, s, on)
	musicVolume = m
	sfxVolume = s
	musicOn = on ~= false
	applyMusicVolume()
	if not started then
		startMusic()
		return
	end
	local p = players[mood]
	if not p then return end
	if not canPlayMusic() then
		for _, q in players do
			q.sound:Pause()
		end
	elseif not p.sound.IsPlaying then
		if p.track then p.sound:Resume() else playNext(mood) end
	end
end

-- A cada quadro: rampas de volume, fim do ducking e passagem para a próxima faixa.
local function step(dt)
	local changed = false
	if duckLevel < 1 and os.clock() >= duckUntil then
		duckLevel = 1
		changed = true
	end
	for m, p in players do
		if p.fade ~= p.target then
			local k = dt / FADE
			if p.fade < p.target then
				p.fade = math.min(p.target, p.fade + k)
			else
				p.fade = math.max(p.target, p.fade - k)
			end
			changed = true
			if p.fade == p.target and p.onDone then
				local fn = p.onDone
				p.onDone = nil
				fn()
			end
		end
		-- Fim do trecho da faixa (sem Looped): passa para a próxima do clima.
		if m == mood and started and p.track and not p.sound.Looped and canPlayMusic() and p.sound.IsLoaded then
			local tp = p.sound.TimePosition
			if tp >= p.track.to - 0.05 or (not p.sound.IsPlaying and p.target == 1 and tp > p.track.from + 0.5) then
				playNext(m)
			end
		end
	end
	if changed then applyMusicVolume() end
end

-- ------------------------------------------------------------ preferências
function Audio.applyConfig(cfg)
	config = cfg
	local v = Config.effectiveVolumes(cfg, hidden)
	setVolumes(v.music, v.sfx, cfg.musicOn)
end

function Audio.init()
	folder = Instance.new("Folder")
	folder.Name = "ReinoSons"
	folder.Parent = SoundService
	sfxId = Assets.audioId("efeitos")
	if sfxId then
		for i = 1, POOL_SIZE do
			pool[i] = newSound("Efeito" .. i, sfxId)
		end
	end
	for _, m in { "vila", "batalha" } do
		local id = Assets.audioId("musica-" .. m)
		local list = id and Sons.musica[m] or {}
		local s = newSound("Musica-" .. m, id or "")
		players[m] = { sound = s, id = id, list = list, idx = 0, fade = 0, target = 0 }
	end
	Ctx.play = play
	Ctx.setMood = setMood
	-- Silencia com a janela em segundo plano (visibilitychange do web).
	UserInputService.WindowFocusReleased:Connect(function()
		hidden = true
		if config then Audio.applyConfig(config) end
	end)
	UserInputService.WindowFocused:Connect(function()
		hidden = false
		if config then Audio.applyConfig(config) end
	end)
	RunService.Heartbeat:Connect(step)
	Audio.applyConfig(Ctx.config)
end

return Audio
